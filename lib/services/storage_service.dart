import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/audio_capture.dart';
import '../models/capture_settings.dart';
import 'database_service.dart';

class StorageService extends ChangeNotifier {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  final DatabaseService _db = DatabaseService();
  
  Timer? _monitoringTimer;
  bool _isMonitoring = false;
  
  // Storage statistics
  int _totalFilesStored = 0;
  int _totalSizeBytes = 0;
  int _availableSpaceBytes = 0;
  int _usedSpaceBytes = 0;
  double _usagePercentage = 0.0;
  
  // Storage limits and thresholds
  int _maxStorageBytes = 100 * 1024 * 1024; // 100MB default
  double _warningThreshold = 0.8; // 80%
  double _criticalThreshold = 0.95; // 95%
  
  // Getters
  bool get isMonitoring => _isMonitoring;
  int get totalFilesStored => _totalFilesStored;
  int get totalSizeBytes => _totalSizeBytes;
  int get availableSpaceBytes => _availableSpaceBytes;
  int get usedSpaceBytes => _usedSpaceBytes;
  double get usagePercentage => _usagePercentage;
  int get maxStorageBytes => _maxStorageBytes;
  
  bool get isNearLimit => _usagePercentage >= _warningThreshold;
  bool get isAtCriticalLevel => _usagePercentage >= _criticalThreshold;
  bool get canStoreMore => _usagePercentage < _criticalThreshold;
  
  String get formattedTotalSize => _formatBytes(_totalSizeBytes);
  String get formattedAvailableSpace => _formatBytes(_availableSpaceBytes);
  String get formattedMaxStorage => _formatBytes(_maxStorageBytes);

  Future<void> initialize({CaptureSettings? settings}) async {
    if (settings != null) {
      _maxStorageBytes = settings.maxStorageMB * 1024 * 1024;
    }
    
    await _updateStorageStats();
    _startMonitoring();
  }

  void dispose() {
    _stopMonitoring();
    super.dispose();
  }

  void updateSettings(CaptureSettings settings) {
    _maxStorageBytes = settings.maxStorageMB * 1024 * 1024;
    _updateStorageStats();
  }

  void _startMonitoring() {
    if (_isMonitoring) return;
    
    _isMonitoring = true;
    _monitoringTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _updateStorageStats(),
    );
  }

  void _stopMonitoring() {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    _isMonitoring = false;
  }

  Future<void> _updateStorageStats() async {
    try {
      // Get database statistics
      final dbStats = await _db.getCaptureStats();
      final totalDbSize = await _db.getTotalStorageUsed();
      
      // Count actual files on disk
      final directory = await getTemporaryDirectory();
      final files = await _getAudioFiles(directory);
      
      int actualTotalSize = 0;
      for (final file in files) {
        try {
          actualTotalSize += await file.length();
        } catch (e) {
          debugPrint('Failed to get file size for ${file.path}: $e');
        }
      }
      
      // Get available device storage
      final deviceStats = await _getDeviceStorageStats();
      
      _totalFilesStored = files.length;
      _totalSizeBytes = actualTotalSize;
      _usedSpaceBytes = actualTotalSize;
      _availableSpaceBytes = _maxStorageBytes - _usedSpaceBytes;
      _usagePercentage = _maxStorageBytes > 0 ? _usedSpaceBytes / _maxStorageBytes : 0.0;
      
      // Check for cleanup needs
      if (_usagePercentage >= _criticalThreshold) {
        await _performEmergencyCleanup();
      } else if (_usagePercentage >= _warningThreshold) {
        await _performRoutineCleanup();
      }
      
      notifyListeners();
      
    } catch (e) {
      debugPrint('Failed to update storage stats: $e');
    }
  }

  Future<List<File>> _getAudioFiles(Directory directory) async {
    try {
      return directory
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.aac') || f.path.endsWith('.mp3'))
          .toList();
    } catch (e) {
      debugPrint('Failed to list audio files: $e');
      return [];
    }
  }

  Future<Map<String, int>> _getDeviceStorageStats() async {
    try {
      final directory = await getTemporaryDirectory();
      final stat = await directory.stat();
      
      // This is a simplified approach - in a real app you might use
      // platform-specific code to get accurate device storage info
      return {
        'total': 1024 * 1024 * 1024, // 1GB placeholder
        'free': 512 * 1024 * 1024,   // 512MB placeholder
      };
    } catch (e) {
      debugPrint('Failed to get device storage stats: $e');
      return {'total': 0, 'free': 0};
    }
  }

  Future<void> _performRoutineCleanup() async {
    try {
      debugPrint('Performing routine storage cleanup...');
      
      // Delete completed captures older than 12 hours
      final cutoffTime = DateTime.now().subtract(const Duration(hours: 12));
      await _db.deleteCompletedCaptures(olderThan: cutoffTime);
      
      // Clean up orphaned files
      await _cleanupOrphanedFiles();
      
      await _updateStorageStats();
      
    } catch (e) {
      debugPrint('Routine cleanup failed: $e');
    }
  }

  Future<void> _performEmergencyCleanup() async {
    try {
      debugPrint('Performing emergency storage cleanup...');
      
      // More aggressive cleanup
      // 1. Delete all completed captures
      await _db.deleteCompletedCaptures();
      
      // 2. Delete failed captures older than 1 hour
      final captures = await _db.getFailedCaptures();
      final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
      
      for (final capture in captures) {
        if (capture.capturedAt.isBefore(oneHourAgo)) {
          await deleteCapture(capture.id);
        }
      }
      
      // 3. Clean up all orphaned files
      await _cleanupOrphanedFiles();
      
      await _updateStorageStats();
      
    } catch (e) {
      debugPrint('Emergency cleanup failed: $e');
    }
  }

  Future<void> _cleanupOrphanedFiles() async {
    try {
      final directory = await getTemporaryDirectory();
      final files = await _getAudioFiles(directory);
      final captures = await _db.getAllCaptures();
      
      final captureFilePaths = captures.map((c) => c.filePath).toSet();
      
      for (final file in files) {
        if (!captureFilePaths.contains(file.path)) {
          try {
            await file.delete();
            debugPrint('Deleted orphaned file: ${file.path}');
          } catch (e) {
            debugPrint('Failed to delete orphaned file ${file.path}: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to cleanup orphaned files: $e');
    }
  }

  Future<bool> hasSpaceForCapture(int estimatedSizeBytes) async {
    await _updateStorageStats();
    
    final projectedUsage = (_usedSpaceBytes + estimatedSizeBytes) / _maxStorageBytes;
    return projectedUsage < _criticalThreshold;
  }

  Future<int> estimateCaptureSize(CaptureSettings settings) async {
    // Estimate file size based on audio settings
    // Formula: (sample_rate * bit_depth * channels * duration) / 8
    // Plus some overhead for AAC compression (roughly 50% of raw size)
    
    final rawSize = (settings.quality.sampleRate * 16 * settings.quality.channels * settings.durationSeconds) / 8;
    final compressedSize = (rawSize * 0.5).round(); // AAC compression estimate
    
    return compressedSize;
  }

  Future<void> deleteCapture(String captureId) async {
    final capture = await _db.getCaptureById(captureId);
    if (capture == null) return;
    
    // Delete file
    final file = File(capture.filePath);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (e) {
        debugPrint('Failed to delete capture file: $e');
      }
    }
    
    // Delete from database
    await _db.deleteCapture(captureId);
    
    // Update stats
    await _updateStorageStats();
  }

  Future<void> deleteAllCaptures({CaptureStatus? status}) async {
    final captures = await _db.getAllCaptures();
    final filteredCaptures = status != null 
        ? captures.where((c) => c.status == status).toList()
        : captures;
    
    for (final capture in filteredCaptures) {
      await deleteCapture(capture.id);
    }
  }

  Future<StorageCleanupResult> performManualCleanup({
    bool deleteCompleted = true,
    bool deleteFailed = false,
    Duration? olderThan,
  }) async {
    int deletedFiles = 0;
    int freedBytes = 0;
    
    try {
      final initialSize = _totalSizeBytes;
      
      if (deleteCompleted) {
        final completedCaptures = await _db.getAllCaptures();
        final toDelete = completedCaptures
            .where((c) => c.status == CaptureStatus.completed)
            .where((c) => olderThan == null || 
                         c.capturedAt.isBefore(DateTime.now().subtract(olderThan)))
            .toList();
        
        for (final capture in toDelete) {
          await deleteCapture(capture.id);
          deletedFiles++;
        }
      }
      
      if (deleteFailed) {
        final failedCaptures = await _db.getFailedCaptures();
        final toDelete = failedCaptures
            .where((c) => olderThan == null || 
                         c.capturedAt.isBefore(DateTime.now().subtract(olderThan)))
            .toList();
        
        for (final capture in toDelete) {
          await deleteCapture(capture.id);
          deletedFiles++;
        }
      }
      
      // Clean up orphaned files
      await _cleanupOrphanedFiles();
      
      await _updateStorageStats();
      
      freedBytes = initialSize - _totalSizeBytes;
      
      return StorageCleanupResult(
        success: true,
        deletedFiles: deletedFiles,
        freedBytes: freedBytes,
      );
      
    } catch (e) {
      debugPrint('Manual cleanup failed: $e');
      return StorageCleanupResult(
        success: false,
        error: e.toString(),
        deletedFiles: deletedFiles,
        freedBytes: freedBytes,
      );
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class StorageCleanupResult {
  final bool success;
  final int deletedFiles;
  final int freedBytes;
  final String? error;

  const StorageCleanupResult({
    required this.success,
    this.deletedFiles = 0,
    this.freedBytes = 0,
    this.error,
  });

  String get formattedFreedSpace => StorageService()._formatBytes(freedBytes);
}