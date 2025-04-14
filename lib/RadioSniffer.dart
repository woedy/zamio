import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;

class RecordingPage extends StatefulWidget {
  const RecordingPage({super.key});

  @override
  State<RecordingPage> createState() => _RecordingPageState();
}

class _RecordingPageState extends State<RecordingPage> {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _isRecording = false;
  bool _isServiceRunning = false; // New flag to track service state
  Timer? _chunkTimer;

  late String chunkPathA;
  late String chunkPathB;
  bool toggle = true; // alternates between chunk A and B

  final int chunkDurationSeconds = 10;

  final String backendUrl = "http://192.168.43.121:8000/api/audio-snippet/"; // Django backend

  @override
  void initState() {
    super.initState();
    _initRecorder();
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
    } else {
      print("🎙️ Microphone permission not granted.");
    }
  }

  void _startService() {
    if (!_isServiceRunning) {
      setState(() {
        _isServiceRunning = true;
      });

      // Start first chunk
      _startChunkLoop();
    }
  }

  void _stopService() {
    if (_isServiceRunning) {
      setState(() {
        _isServiceRunning = false;
      });

      // Stop the recording and the timer
      _chunkTimer?.cancel();
      _recorder.stopRecorder();
      setState(() => _isRecording = false);
    }
  }

  void _startChunkLoop() async {
    // Start first chunk
    await _startNewChunk(chunkPathA);

    _chunkTimer = Timer.periodic(Duration(seconds: chunkDurationSeconds), (_) async {
      String currentPath = toggle ? chunkPathA : chunkPathB;
      String nextPath = toggle ? chunkPathB : chunkPathA;

      // Stop current recording
      if (_recorder.isRecording) {
        await _recorder.stopRecorder();
        setState(() => _isRecording = false);
      }

      // Upload current chunk
      await _uploadAudioChunk(File(currentPath));

      // Start next chunk
      await _startNewChunk(nextPath);

      toggle = !toggle;
    });
  }

  Future<void> _startNewChunk(String path) async {
    await _recorder.startRecorder(
      toFile: path,
      codec: Codec.aacADTS,
    );
    setState(() => _isRecording = true);
  }

  Future<void> _uploadAudioChunk(File file) async {
    try {
      if (!file.existsSync()) return;

      var request = http.MultipartRequest('POST', Uri.parse(backendUrl));
      request.files.add(await http.MultipartFile.fromPath('audio_file', file.path));
      request.fields['station_id'] = "1";
      request.fields['timestamp'] = DateTime.now().toIso8601String();

      var response = await request.send();
      var responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        print('✅ Chunk uploaded successfully');
      } else {
        print('❌ Upload failed: ${response.statusCode}, Body: $responseBody');
      }

      // Optionally delete uploaded file
      file.delete();
    } catch (e) {
      print('❌ Error uploading chunk: $e');
    }
  }

  @override
  void dispose() {
    _chunkTimer?.cancel();
    _recorder.closeRecorder();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Radio Sniffer')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              _isRecording ? Icons.mic : Icons.stop,
              size: 70,
              color: Colors.deepPurple,
            ),
            const SizedBox(height: 20),
            Text(
              _isRecording
                  ? 'Recording in 10s chunks...'
                  : _isServiceRunning
                      ? 'Service Running...'
                      : 'Service Stopped',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 20),
            const Text("Compressed audio is uploaded every 10s", style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                if (_isServiceRunning) {
                  _stopService(); // Stop the service
                } else {
                  _startService(); // Start the service
                }
              },
              child: Text(_isServiceRunning ? 'Stop Service' : 'Start Service'),
            ),
          ],
        ),
      ),
    );
  }
}
