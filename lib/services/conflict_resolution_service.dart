import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/audio_capture.dart';
import 'database_service.dart';

class ConflictResolutionService {
  static final ConflictResolutionService _instance = ConflictResolutionService._internal();
  factory ConflictResolutionService() => _instance;
  ConflictResolutionService._internal();

  final DatabaseService _db = DatabaseService();
  
  // Configuration
  Duration _overlapThreshold = const Duration(seconds: 5);
  Duration _duplicateTimeWindow = const Duration(minutes: 1);
  
  Future<ConflictResolutionResult> resolveConflicts({
    String? stationId,
    DateTime? since,
  }) async {
    try {
      final captures = await _db.getAllCaptures(stationId: stationId);
      
      // Filter by time if specified
      final filteredCaptures = since != null
          ? captures.where((c) => c.capturedAt.isAfter(since)).toList()
          : captures;
      
      if (filteredCaptures.isEmpty) {
        return ConflictResolutionResult.empty();
      }
      
      // Sort by capture time
      filteredCaptures.sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
      
      final conflicts = <CaptureConflict>[];
      final resolutions = <ConflictResolution>[];
      
      // Detect overlapping captures
      final overlaps = await _detectOverlappingCaptures(filteredCaptures);
      conflicts.addAll(overlaps);
      
      // Detect duplicate captures
      final duplicates = await _detectDuplicateCaptures(filteredCaptures);
      conflicts.addAll(duplicates);
      
      // Detect temporal gaps
      final gaps = await _detectTemporalGaps(filteredCaptures);
      conflicts.addAll(gaps);
      
      // Resolve conflicts automatically where possible
      for (final conflict in conflicts) {
        final resolution = await _resolveConflict(conflict);
        if (resolution != null) {
          resolutions.add(resolution);
        }
      }
      
      return ConflictResolutionResult(
        totalCaptures: filteredCaptures.length,
        conflictsDetected: conflicts.length,
        conflictsResolved: resolutions.length,
        conflicts: conflicts,
        resolutions: resolutions,
      );
      
    } catch (e) {
      debugPrint('Conflict resolution failed: $e');
      return ConflictResolutionResult.error(e.toString());
    }
  }

  Future<List<CaptureConflict>> _detectOverlappingCaptures(List<AudioCapture> captures) async {
    final conflicts = <CaptureConflict>[];
    
    for (int i = 0; i < captures.length - 1; i++) {
      final current = captures[i];
      final next = captures[i + 1];
      
      final currentEnd = current.capturedAt.add(Duration(seconds: current.durationSeconds));
      final overlap = currentEnd.difference(next.capturedAt);
      
      if (overlap > _overlapThreshold) {
        conflicts.add(CaptureConflict(
          type: ConflictType.overlap,
          primaryCapture: current,
          secondaryCapture: next,
          description: 'Captures overlap by ${overlap.inSeconds} seconds',
          severity: _calculateOverlapSeverity(overlap),
          metadata: {
            'overlap_duration': overlap.inSeconds,
            'overlap_percentage': (overlap.inSeconds / current.durationSeconds * 100).round(),
          },
        ));
      }
    }
    
    return conflicts;
  }

  Future<List<CaptureConflict>> _detectDuplicateCaptures(List<AudioCapture> captures) async {
    final conflicts = <CaptureConflict>[];
    final processedIds = <String>{};
    
    for (int i = 0; i < captures.length; i++) {
      if (processedIds.contains(captures[i].id)) continue;
      
      final current = captures[i];
      final duplicates = <AudioCapture>[];
      
      // Look for captures within the duplicate time window
      for (int j = i + 1; j < captures.length; j++) {
        final candidate = captures[j];
        final timeDiff = candidate.capturedAt.difference(current.capturedAt).abs();
        
        if (timeDiff <= _duplicateTimeWindow) {
          // Check if they're likely duplicates
          if (_areLikelyDuplicates(current, candidate)) {
            duplicates.add(candidate);
            processedIds.add(candidate.id);
          }
        } else {
          // No more candidates in time window
          break;
        }
      }
      
      if (duplicates.isNotEmpty) {
        conflicts.add(CaptureConflict(
          type: ConflictType.duplicate,
          primaryCapture: current,
          duplicates: duplicates,
          description: 'Found ${duplicates.length} duplicate captures',
          severity: ConflictSeverity.medium,
          metadata: {
            'duplicate_count': duplicates.length,
            'time_window_seconds': _duplicateTimeWindow.inSeconds,
          },
        ));
        processedIds.add(current.id);
      }
    }
    
    return conflicts;
  }

  Future<List<CaptureConflict>> _detectTemporalGaps(List<AudioCapture> captures) async {
    final conflicts = <CaptureConflict>[];
    
    for (int i = 0; i < captures.length - 1; i++) {
      final current = captures[i];
      final next = captures[i + 1];
      
      final expectedNextStart = current.capturedAt.add(Duration(seconds: current.durationSeconds));
      final actualGap = next.capturedAt.difference(expectedNextStart);
      
      // Consider gaps longer than 2x the normal interval as significant
      final expectedInterval = Duration(seconds: current.durationSeconds);
      if (actualGap > expectedInterval * 2) {
        conflicts.add(CaptureConflict(
          type: ConflictType.gap,
          primaryCapture: current,
          secondaryCapture: next,
          description: 'Gap of ${actualGap.inSeconds} seconds between captures',
          severity: _calculateGapSeverity(actualGap),
          metadata: {
            'gap_duration': actualGap.inSeconds,
            'expected_interval': expectedInterval.inSeconds,
          },
        ));
      }
    }
    
    return conflicts;
  }

  bool _areLikelyDuplicates(AudioCapture a, AudioCapture b) {
    // Check if captures are likely duplicates based on:
    // 1. Same station
    // 2. Similar duration
    // 3. Close capture times
    // 4. Similar file sizes (if available)
    
    if (a.stationId != b.stationId) return false;
    
    final durationDiff = (a.durationSeconds - b.durationSeconds).abs();
    if (durationDiff > 2) return false; // Allow 2 second difference
    
    final sizeDiff = (a.fileSizeBytes - b.fileSizeBytes).abs();
    final avgSize = (a.fileSizeBytes + b.fileSizeBytes) / 2;
    final sizeVariance = avgSize > 0 ? sizeDiff / avgSize : 0;
    
    // Allow 10% size variance
    return sizeVariance <= 0.1;
  }

  ConflictSeverity _calculateOverlapSeverity(Duration overlap) {
    if (overlap.inSeconds > 30) return ConflictSeverity.high;
    if (overlap.inSeconds > 10) return ConflictSeverity.medium;
    return ConflictSeverity.low;
  }

  ConflictSeverity _calculateGapSeverity(Duration gap) {
    if (gap.inMinutes > 10) return ConflictSeverity.high;
    if (gap.inMinutes > 2) return ConflictSeverity.medium;
    return ConflictSeverity.low;
  }

  Future<ConflictResolution?> _resolveConflict(CaptureConflict conflict) async {
    try {
      switch (conflict.type) {
        case ConflictType.overlap:
          return await _resolveOverlapConflict(conflict);
        case ConflictType.duplicate:
          return await _resolveDuplicateConflict(conflict);
        case ConflictType.gap:
          return await _resolveGapConflict(conflict);
      }
    } catch (e) {
      debugPrint('Failed to resolve conflict ${conflict.type}: $e');
      return null;
    }
  }

  Future<ConflictResolution?> _resolveOverlapConflict(CaptureConflict conflict) async {
    if (conflict.secondaryCapture == null) return null;
    
    final primary = conflict.primaryCapture;
    final secondary = conflict.secondaryCapture!;
    
    // Strategy: Keep the capture with better quality or earlier timestamp
    AudioCapture toKeep, toRemove;
    
    if (primary.status == CaptureStatus.completed && secondary.status != CaptureStatus.completed) {
      toKeep = primary;
      toRemove = secondary;
    } else if (secondary.status == CaptureStatus.completed && primary.status != CaptureStatus.completed) {
      toKeep = secondary;
      toRemove = primary;
    } else {
      // Both have same status, keep the earlier one
      toKeep = primary.capturedAt.isBefore(secondary.capturedAt) ? primary : secondary;
      toRemove = primary.capturedAt.isBefore(secondary.capturedAt) ? secondary : primary;
    }
    
    // Delete the redundant capture
    await _deleteCapture(toRemove);
    
    return ConflictResolution(
      conflict: conflict,
      action: ResolutionAction.deleteRedundant,
      description: 'Deleted overlapping capture ${toRemove.id}',
      affectedCaptureIds: [toRemove.id],
    );
  }

  Future<ConflictResolution?> _resolveDuplicateConflict(CaptureConflict conflict) async {
    if (conflict.duplicates == null || conflict.duplicates!.isEmpty) return null;
    
    final primary = conflict.primaryCapture;
    final duplicates = conflict.duplicates!;
    
    // Keep the primary, delete duplicates
    final deletedIds = <String>[];
    
    for (final duplicate in duplicates) {
      await _deleteCapture(duplicate);
      deletedIds.add(duplicate.id);
    }
    
    return ConflictResolution(
      conflict: conflict,
      action: ResolutionAction.deleteDuplicates,
      description: 'Deleted ${deletedIds.length} duplicate captures',
      affectedCaptureIds: deletedIds,
    );
  }

  Future<ConflictResolution?> _resolveGapConflict(CaptureConflict conflict) async {
    // For gaps, we typically just log them - no automatic resolution
    return ConflictResolution(
      conflict: conflict,
      action: ResolutionAction.logOnly,
      description: 'Temporal gap logged for analysis',
      affectedCaptureIds: [],
    );
  }

  Future<void> _deleteCapture(AudioCapture capture) async {
    // Delete file if it exists
    final file = File(capture.filePath);
    if (file.existsSync()) {
      try {
        await file.delete();
      } catch (e) {
        debugPrint('Failed to delete capture file: $e');
      }
    }
    
    // Delete from database
    await _db.deleteCapture(capture.id);
  }

  // Configuration methods
  void setOverlapThreshold(Duration threshold) {
    _overlapThreshold = threshold;
  }

  void setDuplicateTimeWindow(Duration window) {
    _duplicateTimeWindow = window;
  }
}

class ConflictResolutionResult {
  final bool success;
  final int totalCaptures;
  final int conflictsDetected;
  final int conflictsResolved;
  final List<CaptureConflict> conflicts;
  final List<ConflictResolution> resolutions;
  final String? error;

  const ConflictResolutionResult({
    this.success = true,
    this.totalCaptures = 0,
    this.conflictsDetected = 0,
    this.conflictsResolved = 0,
    this.conflicts = const [],
    this.resolutions = const [],
    this.error,
  });

  factory ConflictResolutionResult.empty() {
    return const ConflictResolutionResult();
  }

  factory ConflictResolutionResult.error(String error) {
    return ConflictResolutionResult(
      success: false,
      error: error,
    );
  }

  double get resolutionRate {
    return conflictsDetected > 0 ? conflictsResolved / conflictsDetected : 1.0;
  }
}

class CaptureConflict {
  final ConflictType type;
  final AudioCapture primaryCapture;
  final AudioCapture? secondaryCapture;
  final List<AudioCapture>? duplicates;
  final String description;
  final ConflictSeverity severity;
  final Map<String, dynamic> metadata;

  const CaptureConflict({
    required this.type,
    required this.primaryCapture,
    this.secondaryCapture,
    this.duplicates,
    required this.description,
    required this.severity,
    this.metadata = const {},
  });
}

class ConflictResolution {
  final CaptureConflict conflict;
  final ResolutionAction action;
  final String description;
  final List<String> affectedCaptureIds;
  final DateTime resolvedAt;

  ConflictResolution({
    required this.conflict,
    required this.action,
    required this.description,
    required this.affectedCaptureIds,
    DateTime? resolvedAt,
  }) : resolvedAt = resolvedAt ?? DateTime.now();
}

enum ConflictType {
  overlap,
  duplicate,
  gap,
}

enum ConflictSeverity {
  low,
  medium,
  high,
}

enum ResolutionAction {
  deleteRedundant,
  deleteDuplicates,
  merge,
  logOnly,
}