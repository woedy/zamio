import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:zamio/auth_store.dart';
import 'package:zamio/foreground_service.dart';
import 'package:zamio/services/offline_capture_service.dart';
import 'package:zamio/services/connectivity_service.dart';
import 'package:zamio/services/storage_service.dart';
import 'package:zamio/models/capture_settings.dart';

class StatusPage extends StatefulWidget {
  const StatusPage({super.key});

  @override
  State<StatusPage> createState() => _StatusPageState();
}

class _StatusPageState extends State<StatusPage> with SingleTickerProviderStateMixin {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final OfflineCaptureService _captureService = OfflineCaptureService();
  final ConnectivityService _connectivity = ConnectivityService();
  final StorageService _storage = StorageService();
  
  bool _isRecording = false;
  bool _isServiceRunning = false;
  Timer? _chunkTimer;
  Timer? _uiTimer;
  DateTime? _lastUploadAt;
  DateTime? _currentChunkStartedAt;
  int _backlogCount = 0;

  late final AnimationController _meterController;

  late String chunkPathA;
  late String chunkPathB;
  bool toggle = true; // alternates between chunk A and B

    final int chunkDurationSeconds = 10;
    // Note: True overlap requires two concurrent recorders or stream processing.
    // We instead ensure gapless rotation by starting the next chunk immediately,
    // and uploading the previous chunk in the background.

  String _backendBase = '';
  String _stationId = '';
  String _authToken = '';
  String get _uploadUrl {
    final base = _backendBase.isNotEmpty ? _backendBase : 'http://192.168.43.121:8000/';
    final normalized = base.endsWith('/') ? base : (base + '/');
    return normalized + 'api/music-monitor/stream/upload/';
  }

  @override
  void initState() {
    super.initState();
    _meterController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final sess = await AuthStore.loadSession();
    setState(() {
      _backendBase = (sess['base_url'] ?? '').trim();
      _stationId = (sess['station_id'] ?? '').trim();
      _authToken = (sess['token'] ?? '').trim();
    });
    
    // Initialize services
    await _initServices();
    await _initRecorder();
    await initForegroundService();
  }

  Future<void> _initServices() async {
    try {
      await _connectivity.initialize();
      await _storage.initialize();
      await _captureService.initialize();
      
      // Listen to service changes
      _captureService.addListener(_onCaptureServiceChanged);
      _connectivity.addListener(_onConnectivityChanged);
      _storage.addListener(_onStorageChanged);
      
    } catch (e) {
      debugPrint('Failed to initialize services: $e');
    }
  }

  void _onCaptureServiceChanged() {
    if (mounted) {
      setState(() {
        _isRecording = _captureService.isCapturing;
        _backlogCount = _captureService.totalCapturesCreated - _captureService.totalCapturesCompleted;
      });
    }
  }

  void _onConnectivityChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onStorageChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _initRecorder() async {
    await Permission.microphone.request();
    await Permission.storage.request();

    if (await Permission.microphone.isGranted) {
      await _recorder.openRecorder();

      // Prepare file paths
      final dir = await getTemporaryDirectory();
      chunkPathA = '${dir.path}/chunk_A.aac';
      chunkPathB = '${dir.path}/chunk_B.aac';

      // Try to upload any leftover chunks from previous runs
      // before user starts the service.
      unawaited(_scanAndUploadPendingChunks());
      _updateBacklogCount();

      // Light UI ticker for countdown ring
      _uiTimer?.cancel();
      _uiTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted) return;
        if (_isServiceRunning) setState(() {});
      });
    } else {
      print("🎙️ Microphone permission not granted.");
    }
  }

  void _startService() async {
    if (_stationId.isEmpty || _authToken.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please login and configure station before starting')));
      return;
    }
    
    if (!_isServiceRunning) {
      try {
        setState(() {
          _isServiceRunning = true;
        });

        // Start offline capture service
        await _captureService.startCapturing(_stationId);
        
        // Start legacy chunk loop for backward compatibility
        _startChunkLoop();
        
        // Ensure foreground service active on Android
        await startForegroundService(content: 'Station $_stationId - Offline Mode');
        
      } catch (e) {
        setState(() {
          _isServiceRunning = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start service: $e')),
        );
      }
    }
  }

  void _stopService() async {
    if (_isServiceRunning) {
      setState(() {
        _isServiceRunning = false;
      });

      // Stop offline capture service
      await _captureService.stopCapturing();
      
      // Stop the legacy recording and timer
      _chunkTimer?.cancel();
      if (_recorder.isRecording) {
        await _recorder.stopRecorder();
      }
      setState(() => _isRecording = false);

      // Try to flush any pending chunks
      unawaited(_scanAndUploadPendingChunks());
      _updateBacklogCount();

      // Stop foreground service
      await stopForegroundService();
    }
  }

  void _startChunkLoop() async {
    // Start first chunk
    await _startNewChunk(chunkPathA);

    _chunkTimer = Timer.periodic(Duration(seconds: chunkDurationSeconds), (_) async {
      final String currentPath = toggle ? chunkPathA : chunkPathB;
      final String nextPath = toggle ? chunkPathB : chunkPathA;

      // Stop current recording and immediately start the next one to avoid gaps
      if (_recorder.isRecording) {
        await _recorder.stopRecorder();
        setState(() => _isRecording = false);
      }

      await _startNewChunk(nextPath);
      toggle = !toggle;

      // Upload previous chunk in background (delete only on success)
      _uploadAudioChunk(File(currentPath));
      _updateBacklogCount();
    });
  }

  Future<void> _startNewChunk(String path) async {
    await _recorder.startRecorder(
      toFile: path,
      codec: Codec.aacADTS,
      sampleRate: 16000,
      numChannels: 1,
      bitRate: 24000,
    );
    setState(() {
      _isRecording = true;
      _currentChunkStartedAt = DateTime.now();
    });
  }

  Future<void> _uploadAudioChunk(File file) async {
    try {
      if (!file.existsSync()) return;

      final startedAt = _currentChunkStartedAt ?? DateTime.now();
      final durationSecs = chunkDurationSeconds;
      final chunkId = "${_stationId}-${startedAt.millisecondsSinceEpoch}";

      var request = http.MultipartRequest('POST', Uri.parse(_uploadUrl));
      // Correct field name expected by backend is `file`
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
      request.fields['station_id'] = _stationId;
      request.fields['chunk_id'] = chunkId;
      request.fields['started_at'] = startedAt.toIso8601String();
      request.fields['duration_seconds'] = durationSecs.toString();
      if (_authToken.isNotEmpty) {
        request.headers['Authorization'] = 'Token ' + _authToken;
      }

      var response = await request.send();
      var responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200 || response.statusCode == 201) {
        print('✅ Chunk uploaded successfully');
        // Delete only on success
        try { await file.delete(); } catch (_) {}
        setState(() {
          _lastUploadAt = DateTime.now();
        });
      } else {
        print('❌ Upload failed: ${response.statusCode}, Body: $responseBody');
        // Keep file for retry on next scan
      }
      _updateBacklogCount();
    } catch (e) {
      print('❌ Error uploading chunk: $e');
    }
  }

  Future<void> _scanAndUploadPendingChunks() async {
    try {
      final dir = await getTemporaryDirectory();
      final entries = dir.listSync();
      final activePath = _isRecording ? (toggle ? chunkPathA : chunkPathB) : null;

      final files = entries
          .whereType<File>()
          .where((f) => f.path.endsWith('.aac') && f.path != activePath)
          .toList()
        ..sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));

      for (final f in files) {
        await _uploadAudioChunk(f);
      }
    } catch (e) {
      print('❌ Error scanning pending chunks: $e');
    }
  }

  Future<void> _updateBacklogCount() async {
    try {
      final dir = await getTemporaryDirectory();
      final entries = dir.listSync();
      final activePath = _isRecording ? (toggle ? chunkPathA : chunkPathB) : null;
      final count = entries
          .whereType<File>()
          .where((f) => f.path.endsWith('.aac') && f.path != activePath)
          .length;
      setState(() { _backlogCount = count; });
    } catch (_) {}
  }

  @override
  void dispose() {
    _chunkTimer?.cancel();
    _uiTimer?.cancel();
    _meterController.dispose();
    _recorder.closeRecorder();
    
    // Remove service listeners
    _captureService.removeListener(_onCaptureServiceChanged);
    _connectivity.removeListener(_onConnectivityChanged);
    _storage.removeListener(_onStorageChanged);
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _AnimatedBackground(controller: _meterController),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // Top minimal header
                  Row(
                    children: [
                      Text('Zamio', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      _StatusDot(active: _isServiceRunning),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Notice
                  _NoticeBanner(isVisible: !_isServiceRunning, text: 'Service is stopped. Start to capture and upload.'),
                  const SizedBox(height: 12),

                  // Glass hero card
                  _Glass(
                    child: _HeroStatusCard(
                      isRecording: _isRecording,
                      isServiceRunning: _isServiceRunning,
                      chunkDurationSeconds: chunkDurationSeconds,
                      currentChunkStartedAt: _currentChunkStartedAt,
                      controller: _meterController,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Enhanced stat pills with offline info
                  Row(
                    children: [
                      Expanded(child: _StatPill(
                        icon: _connectivity.isConnected ? Icons.cloud_upload : Icons.cloud_off, 
                        label: 'Status', 
                        value: _connectivity.isConnected ? 'Online' : 'Offline'
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: _StatPill(icon: Icons.queue, label: 'Queue', value: '$_backlogCount')),
                      const SizedBox(width: 8),
                      Expanded(child: _StatPill(
                        icon: Icons.storage, 
                        label: 'Storage', 
                        value: '${_storage.usagePercentage.toStringAsFixed(0)}%'
                      )),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  // Storage warning if needed
                  if (_storage.isNearLimit)
                    _StorageWarningBanner(
                      isVisible: true,
                      usagePercentage: _storage.usagePercentage,
                      isCritical: _storage.isAtCriticalLevel,
                    ),

                  const Spacer(),

                  // Big gradient button
                  _BigPrimaryButton(
                    label: _isServiceRunning ? 'Stop' : 'Go Live',
                    onTap: () {
                      if (_isServiceRunning) {
                        _stopService();
                      } else {
                        _startService();
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(onPressed: _scanAndUploadPendingChunks, child: const Text('Retry Pending')),
                      const SizedBox(width: 8),
                      TextButton(onPressed: _updateBacklogCount, child: const Text('Refresh')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _MetricChip({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.deepPurple),
          const SizedBox(width: 6),
          Text('$label: ', style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _AnimatedBackground extends StatelessWidget {
  final Animation<double> controller;
  const _AnimatedBackground({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1A1C2C).withOpacity(0.98),
                const Color(0xFF3E1F47).withOpacity(0.98),
                const Color(0xFF5E35B1).withOpacity(0.98),
              ],
              stops: [0.0, (0.3 + 0.2 * math.sin(t * 2 * math.pi)).clamp(0.2, 0.6), 1.0],
            ),
          ),
        );
      },
    );
  }
}

class _Glass extends StatelessWidget {
  final Widget child;
  const _Glass({required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = (isDark ? Colors.white : Colors.black).withOpacity(0.08);
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.15)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _BigPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _BigPrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(colors: [Color(0xFF7E57C2), Color(0xFF5E35B1)]),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 12, offset: const Offset(0, 8)),
          ],
        ),
        child: Center(
          child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatPill({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return _Glass(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: Colors.white.withOpacity(0.9)),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: Colors.white.withOpacity(0.7))),
            const SizedBox(width: 6),
            Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final bool active;
  const _StatusDot({required this.active});

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.greenAccent : Colors.redAccent;
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(active ? 'Live' : 'Stopped', style: TextStyle(color: Colors.white.withOpacity(0.9))),
      ],
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  final bool isVisible;
  final String text;
  const _NoticeBanner({required this.isVisible, required this.text});

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Row(
        children: [
          const Icon(Icons.info, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _StorageWarningBanner extends StatelessWidget {
  final bool isVisible;
  final double usagePercentage;
  final bool isCritical;
  
  const _StorageWarningBanner({
    required this.isVisible,
    required this.usagePercentage,
    required this.isCritical,
  });

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();
    
    final color = isCritical ? Colors.red : Colors.orange;
    final icon = isCritical ? Icons.error : Icons.warning;
    final message = isCritical 
        ? 'Storage critically low (${usagePercentage.toStringAsFixed(0)}%)'
        : 'Storage getting full (${usagePercentage.toStringAsFixed(0)}%)';
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.shade300),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
          TextButton(
            onPressed: () => _showStorageDialog(context),
            child: const Text('Manage'),
          ),
        ],
      ),
    );
  }
  
  void _showStorageDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Storage Management'),
        content: const Text('Would you like to clean up old captures to free space?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _performCleanup(context);
            },
            child: const Text('Clean Up'),
          ),
        ],
      ),
    );
  }
  
  void _performCleanup(BuildContext context) async {
    try {
      final storage = StorageService();
      final result = await storage.performManualCleanup(
        deleteCompleted: true,
        olderThan: const Duration(hours: 6),
      );
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Cleaned up ${result.deletedFiles} files, freed ${result.formattedFreedSpace}'
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cleanup failed: $e')),
        );
      }
    }
  }
}

class _HeroStatusCard extends StatelessWidget {
  final bool isRecording;
  final bool isServiceRunning;
  final int chunkDurationSeconds;
  final DateTime? currentChunkStartedAt;
  final AnimationController controller;
  const _HeroStatusCard({required this.isRecording, required this.isServiceRunning, required this.chunkDurationSeconds, required this.currentChunkStartedAt, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
        child: Column(
          children: [
            SizedBox(
              height: 120,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _CountdownRing(
                    startedAt: currentChunkStartedAt,
                    durationSeconds: chunkDurationSeconds,
                  ),
                  Icon(
                    isRecording ? Icons.mic : Icons.mic_off,
                    size: 48,
                    color: Colors.deepPurple,
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: SizedBox(
                      height: 36,
                      child: _LevelMeter(controller: controller, active: isRecording),
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isRecording ? 'Recording' : (isServiceRunning ? 'Idle' : 'Stopped'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text("10s chunks • AAC mono 16 kHz", style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class _CountdownRing extends StatelessWidget {
  final DateTime? startedAt;
  final int durationSeconds;
  const _CountdownRing({required this.startedAt, required this.durationSeconds});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final elapsed = startedAt == null ? 0.0 : (now.difference(startedAt!).inMilliseconds / 1000.0);
    final progress = (elapsed % durationSeconds) / durationSeconds;
    return CustomPaint(
      painter: _RingPainter(progress: progress),
      size: const Size(120, 120),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  _RingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = 8.0;
    final rect = Offset(stroke/2, stroke/2) & Size(size.width - stroke, size.height - stroke);
    final bg = Paint()
      ..color = const Color(0xFFEDE7F6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final fg = Paint()
      ..shader = const LinearGradient(colors: [Color(0xFF7E57C2), Color(0xFF5E35B1)]).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    canvas.drawArc(rect, -math.pi/2, math.pi*2, false, bg);
    canvas.drawArc(rect, -math.pi/2, math.pi*2*progress, false, fg);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) => oldDelegate.progress != progress;
}

class _LevelMeter extends StatelessWidget {
  final Animation<double> controller;
  final bool active;
  const _LevelMeter({required this.controller, required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final bars = 20;
        final values = List<double>.generate(bars, (i) {
          final phase = (controller.value + i / bars) * 2 * math.pi;
          final base = (math.sin(phase) + 1) / 2; // 0..1
          final amp = active ? 1.0 : 0.2;
          return (0.2 + base * 0.8) * amp;
        });
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: values.map((v) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.0),
            child: Container(
              width: 5,
              height: 8 + v * 28,
              decoration: BoxDecoration(
                color: Colors.deepPurple,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          )).toList(),
        );
      },
    );
  }
}

String _fmtTime(DateTime t) {
  final local = t.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  final ss = local.second.toString().padLeft(2, '0');
  return '$hh:$mm:$ss';
}
