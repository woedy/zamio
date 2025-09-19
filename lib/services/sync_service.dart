import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/audio_capture.dart';
import '../auth_store.dart';
import 'database_service.dart';
import 'connectivity_service.dart';
import 'notification_service.dart';

class SyncService extends ChangeNotifier {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final DatabaseService _db = DatabaseService();
  final ConnectivityService _connectivity = ConnectivityService();
  final NotificationService _notifications = NotificationService();

  Timer? _syncTimer;
  bool _isSyncing = false;
  bool _isInitialized = false;
  
  // Sync configuration
  Duration _syncInterval = const Duration(minutes: 2);
  int _maxConcurrentUploads = 3;
  int _maxRetryAttempts = 3;
  Duration _retryDelay = const Duration(seconds: 30);
  
  // Current sync state
  List<String> _currentlyUploading = [];
  int _totalPendingUploads = 0;
  int _completedUploads = 0;
  int _failedUploads = 0;
  DateTime? _lastSyncAttempt;
  DateTime? _lastSuccessfulSync;
  
  // Upload progress tracking
  final Map<String, UploadProgress> _uploadProgress = {};
  
  // Getters
  bool get isSyncing => _isSyncing;
  bool get isInitialized => _isInitialized;
  int get totalPendingUploads => _totalPendingUploads;
  int get completedUploads => _completedUploads;
  int get failedUploads => _failedUploads;
  DateTime? get lastSyncAttempt => _lastSyncAttempt;
  DateTime? get lastSuccessfulSync => _lastSuccessfulSync;
  List<String> get currentlyUploading => List.unmodifiable(_currentlyUploading);
  
  double get syncProgress {
    if (_totalPendingUploads == 0) return 1.0;
    return _completedUploads / _totalPendingUploads;
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _notifications.initialize();
      
      // Listen to connectivity changes
      _connectivity.addListener(_onConnectivityChanged);
      
      // Start periodic sync
      _startPeriodicSync();
      
      // Initial sync if connected
      if (_connectivity.isConnected) {
        unawaited(_performSync());
      }
      
      _isInitialized = true;
      notifyListeners();
      
    } catch (e) {
      debugPrint('Failed to initialize SyncService: $e');
      rethrow;
    }
  }

  void dispose() {
    _syncTimer?.cancel();
    _connectivity.removeListener(_onConnectivityChanged);
    _isInitialized = false;
    super.dispose();
  }

  void _onConnectivityChanged() {
    if (_connectivity.isConnected && !_isSyncing) {
      debugPrint('Connectivity restored, starting sync...');
      unawaited(_performSync());
    }
  }

  void _startPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(_syncInterval, (_) {
      if (_connectivity.isConnected && !_isSyncing) {
        unawaited(_performSync());
      }
    });
  }

  Future<void> _performSync() async {
    if (_isSyncing || !_connectivity.isConnected) return;

    _isSyncing = true;
    _lastSyncAttempt = DateTime.now();
    notifyListeners();

    try {
      // Get pending captures
      final pendingCaptures = await _db.getPendingCaptures();
      _totalPendingUploads = pendingCaptures.length;
      _completedUploads = 0;
      _failedUploads = 0;
      
      if (pendingCaptures.isEmpty) {
        debugPrint('No pending captures to sync');
        _lastSuccessfulSync = DateTime.now();
        return;
      }

      debugPrint('Starting sync of ${pendingCaptures.length} captures');
      
      // Process uploads in batches
      await _processCapturesInBatches(pendingCaptures);
      
      _lastSuccessfulSync = DateTime.now();
      
      // Send completion notification
      await _notifications.showSyncCompletedNotification(
        completed: _completedUploads,
        failed: _failedUploads,
      );
      
    } catch (e) {
      debugPrint('Sync failed: $e');
      await _notifications.showSyncFailedNotification(e.toString());
    } finally {
      _isSyncing = false;
      _currentlyUploading.clear();
      _uploadProgress.clear();
      notifyListeners();
    }
  }

  Future<void> _processCapturesInBatches(List<AudioCapture> captures) async {
    // Sort by capture time (oldest first)
    captures.sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    
    // Process in batches to avoid overwhelming the server
    for (int i = 0; i < captures.length; i += _maxConcurrentUploads) {
      final batch = captures.skip(i).take(_maxConcurrentUploads).toList();
      
      // Check connectivity before each batch
      if (!_connectivity.isConnected) {
        debugPrint('Lost connectivity during sync');
        break;
      }
      
      // Upload batch concurrently
      final futures = batch.map((capture) => _uploadCapture(capture)).toList();
      await Future.wait(futures, eagerError: false);
      
      // Small delay between batches to be nice to the server
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  Future<void> _uploadCapture(AudioCapture capture) async {
    if (_currentlyUploading.contains(capture.id)) return;
    
    _currentlyUploading.add(capture.id);
    _uploadProgress[capture.id] = UploadProgress(
      captureId: capture.id,
      status: UploadStatus.starting,
      progress: 0.0,
    );
    
    try {
      // Update status to uploading
      await _db.updateCaptureStatus(capture.id, CaptureStatus.uploading);
      
      _uploadProgress[capture.id] = _uploadProgress[capture.id]!.copyWith(
        status: UploadStatus.uploading,
      );
      notifyListeners();
      
      // Perform the upload
      final success = await _performUpload(capture);
      
      if (success) {
        await _db.updateCaptureStatus(capture.id, CaptureStatus.completed);
        _completedUploads++;
        
        _uploadProgress[capture.id] = _uploadProgress[capture.id]!.copyWith(
          status: UploadStatus.completed,
          progress: 1.0,
        );
        
        // Delete local file if upload successful
        await _deleteLocalFile(capture.filePath);
        
      } else {
        await _handleUploadFailure(capture);
      }
      
    } catch (e) {
      debugPrint('Upload failed for ${capture.id}: $e');
      await _handleUploadFailure(capture, error: e.toString());
    } finally {
      _currentlyUploading.remove(capture.id);
      notifyListeners();
    }
  }

  Future<bool> _performUpload(AudioCapture capture) async {
    try {
      final session = await AuthStore.loadSession();
      final baseUrl = session['base_url']?.trim() ?? '';
      final token = session['token']?.trim() ?? '';
      
      if (baseUrl.isEmpty || token.isEmpty) {
        throw Exception('Missing authentication credentials');
      }
      
      final uploadUrl = baseUrl.endsWith('/') 
          ? '${baseUrl}api/music-monitor/stream/upload/'
          : '$baseUrl/api/music-monitor/stream/upload/';
      
      final file = File(capture.filePath);
      if (!file.existsSync()) {
        throw Exception('Capture file not found: ${capture.filePath}');
      }
      
      final request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
      
      // Add file
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
      
      // Add metadata
      request.fields['station_id'] = capture.stationId;
      request.fields['chunk_id'] = capture.id;
      request.fields['started_at'] = capture.capturedAt.toIso8601String();
      request.fields['duration_seconds'] = capture.durationSeconds.toString();
      
      // Add metadata if available
      if (capture.metadata != null) {
        request.fields['metadata'] = jsonEncode(capture.metadata);
      }
      
      // Add auth header
      request.headers['Authorization'] = 'Token $token';
      
      // Send request with progress tracking
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('Upload successful for ${capture.id}');
        return true;
      } else {
        debugPrint('Upload failed for ${capture.id}: ${response.statusCode} - $responseBody');
        return false;
      }
      
    } catch (e) {
      debugPrint('Upload error for ${capture.id}: $e');
      return false;
    }
  }

  Future<void> _handleUploadFailure(AudioCapture capture, {String? error}) async {
    await _db.incrementRetryCount(capture.id);
    
    if (capture.retryCount >= _maxRetryAttempts) {
      await _db.updateCaptureStatus(
        capture.id, 
        CaptureStatus.failed,
        errorMessage: error ?? 'Max retry attempts exceeded',
      );
      _failedUploads++;
      
      _uploadProgress[capture.id] = _uploadProgress[capture.id]!.copyWith(
        status: UploadStatus.failed,
        error: error,
      );
    } else {
      await _db.updateCaptureStatus(
        capture.id, 
        CaptureStatus.retrying,
        errorMessage: error,
      );
      
      _uploadProgress[capture.id] = _uploadProgress[capture.id]!.copyWith(
        status: UploadStatus.retrying,
        error: error,
      );
    }
  }

  Future<void> _deleteLocalFile(String filePath) async {
    try {
      final file = File(filePath);
      if (file.existsSync()) {
        await file.delete();
        debugPrint('Deleted local file: $filePath');
      }
    } catch (e) {
      debugPrint('Failed to delete local file $filePath: $e');
    }
  }

  // Manual sync trigger
  Future<void> triggerSync() async {
    if (!_connectivity.isConnected) {
      throw Exception('No internet connection available');
    }
    
    await _performSync();
  }

  // Retry specific failed capture
  Future<void> retryCapture(String captureId) async {
    final capture = await _db.getCaptureById(captureId);
    if (capture == null) return;
    
    if (!_connectivity.isConnected) {
      throw Exception('No internet connection available');
    }
    
    await _uploadCapture(capture);
  }

  // Get upload progress for a specific capture
  UploadProgress? getUploadProgress(String captureId) {
    return _uploadProgress[captureId];
  }

  // Configuration methods
  void updateSyncInterval(Duration interval) {
    _syncInterval = interval;
    _startPeriodicSync();
  }

  void updateMaxConcurrentUploads(int max) {
    _maxConcurrentUploads = max.clamp(1, 10);
  }

  void updateMaxRetryAttempts(int max) {
    _maxRetryAttempts = max.clamp(1, 10);
  }
}

class UploadProgress {
  final String captureId;
  final UploadStatus status;
  final double progress;
  final String? error;
  final DateTime timestamp;

  const UploadProgress({
    required this.captureId,
    required this.status,
    required this.progress,
    this.error,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? const Duration().inMicroseconds != 0 
                    ? DateTime.now() 
                    : DateTime.now();

  UploadProgress copyWith({
    String? captureId,
    UploadStatus? status,
    double? progress,
    String? error,
    DateTime? timestamp,
  }) {
    return UploadProgress(
      captureId: captureId ?? this.captureId,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      error: error ?? this.error,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

enum UploadStatus {
  starting,
  uploading,
  completed,
  failed,
  retrying,
}

extension UploadStatusExtension on UploadStatus {
  String get displayName {
    switch (this) {
      case UploadStatus.starting:
        return 'Starting';
      case UploadStatus.uploading:
        return 'Uploading';
      case UploadStatus.completed:
        return 'Completed';
      case UploadStatus.failed:
        return 'Failed';
      case UploadStatus.retrying:
        return 'Retrying';
    }
  }
}