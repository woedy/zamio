class AudioCapture {
  final String id;
  final String stationId;
  final String filePath;
  final DateTime capturedAt;
  final int durationSeconds;
  final int fileSizeBytes;
  final CaptureStatus status;
  final int retryCount;
  final DateTime? lastRetryAt;
  final String? errorMessage;
  final Map<String, dynamic>? metadata;

  const AudioCapture({
    required this.id,
    required this.stationId,
    required this.filePath,
    required this.capturedAt,
    required this.durationSeconds,
    required this.fileSizeBytes,
    required this.status,
    this.retryCount = 0,
    this.lastRetryAt,
    this.errorMessage,
    this.metadata,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'station_id': stationId,
      'file_path': filePath,
      'captured_at': capturedAt.millisecondsSinceEpoch,
      'duration_seconds': durationSeconds,
      'file_size_bytes': fileSizeBytes,
      'status': status.name,
      'retry_count': retryCount,
      'last_retry_at': lastRetryAt?.millisecondsSinceEpoch,
      'error_message': errorMessage,
      'metadata': metadata != null ? _encodeMetadata(metadata!) : null,
    };
  }

  factory AudioCapture.fromMap(Map<String, dynamic> map) {
    return AudioCapture(
      id: map['id'],
      stationId: map['station_id'],
      filePath: map['file_path'],
      capturedAt: DateTime.fromMillisecondsSinceEpoch(map['captured_at']),
      durationSeconds: map['duration_seconds'],
      fileSizeBytes: map['file_size_bytes'],
      status: CaptureStatus.values.byName(map['status']),
      retryCount: map['retry_count'] ?? 0,
      lastRetryAt: map['last_retry_at'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['last_retry_at'])
          : null,
      errorMessage: map['error_message'],
      metadata: map['metadata'] != null ? _decodeMetadata(map['metadata']) : null,
    );
  }

  AudioCapture copyWith({
    String? id,
    String? stationId,
    String? filePath,
    DateTime? capturedAt,
    int? durationSeconds,
    int? fileSizeBytes,
    CaptureStatus? status,
    int? retryCount,
    DateTime? lastRetryAt,
    String? errorMessage,
    Map<String, dynamic>? metadata,
  }) {
    return AudioCapture(
      id: id ?? this.id,
      stationId: stationId ?? this.stationId,
      filePath: filePath ?? this.filePath,
      capturedAt: capturedAt ?? this.capturedAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      lastRetryAt: lastRetryAt ?? this.lastRetryAt,
      errorMessage: errorMessage ?? this.errorMessage,
      metadata: metadata ?? this.metadata,
    );
  }

  static String _encodeMetadata(Map<String, dynamic> metadata) {
    // Simple JSON-like encoding for SQLite storage
    return metadata.entries
        .map((e) => '${e.key}:${e.value}')
        .join(',');
  }

  static Map<String, dynamic> _decodeMetadata(String encoded) {
    final Map<String, dynamic> result = {};
    for (final pair in encoded.split(',')) {
      final parts = pair.split(':');
      if (parts.length == 2) {
        result[parts[0]] = parts[1];
      }
    }
    return result;
  }
}

enum CaptureStatus {
  pending,
  uploading,
  completed,
  failed,
  retrying,
}

extension CaptureStatusExtension on CaptureStatus {
  String get displayName {
    switch (this) {
      case CaptureStatus.pending:
        return 'Pending';
      case CaptureStatus.uploading:
        return 'Uploading';
      case CaptureStatus.completed:
        return 'Completed';
      case CaptureStatus.failed:
        return 'Failed';
      case CaptureStatus.retrying:
        return 'Retrying';
    }
  }

  bool get canRetry => this == CaptureStatus.failed;
  bool get isPending => this == CaptureStatus.pending || this == CaptureStatus.retrying;
}