class CaptureSettings {
  final int intervalSeconds;
  final int durationSeconds;
  final AudioQuality quality;
  final bool batteryOptimized;
  final int maxRetries;
  final int retryDelaySeconds;
  final bool compressBeforeStorage;
  final int maxStorageMB;
  final bool autoDeleteCompleted;

  const CaptureSettings({
    this.intervalSeconds = 10,
    this.durationSeconds = 10,
    this.quality = AudioQuality.standard,
    this.batteryOptimized = true,
    this.maxRetries = 3,
    this.retryDelaySeconds = 30,
    this.compressBeforeStorage = true,
    this.maxStorageMB = 100,
    this.autoDeleteCompleted = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'interval_seconds': intervalSeconds,
      'duration_seconds': durationSeconds,
      'quality': quality.name,
      'battery_optimized': batteryOptimized,
      'max_retries': maxRetries,
      'retry_delay_seconds': retryDelaySeconds,
      'compress_before_storage': compressBeforeStorage,
      'max_storage_mb': maxStorageMB,
      'auto_delete_completed': autoDeleteCompleted,
    };
  }

  factory CaptureSettings.fromMap(Map<String, dynamic> map) {
    return CaptureSettings(
      intervalSeconds: map['interval_seconds'] ?? 10,
      durationSeconds: map['duration_seconds'] ?? 10,
      quality: AudioQuality.values.byName(map['quality'] ?? 'standard'),
      batteryOptimized: map['battery_optimized'] ?? true,
      maxRetries: map['max_retries'] ?? 3,
      retryDelaySeconds: map['retry_delay_seconds'] ?? 30,
      compressBeforeStorage: map['compress_before_storage'] ?? true,
      maxStorageMB: map['max_storage_mb'] ?? 100,
      autoDeleteCompleted: map['auto_delete_completed'] ?? true,
    );
  }

  CaptureSettings copyWith({
    int? intervalSeconds,
    int? durationSeconds,
    AudioQuality? quality,
    bool? batteryOptimized,
    int? maxRetries,
    int? retryDelaySeconds,
    bool? compressBeforeStorage,
    int? maxStorageMB,
    bool? autoDeleteCompleted,
  }) {
    return CaptureSettings(
      intervalSeconds: intervalSeconds ?? this.intervalSeconds,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      quality: quality ?? this.quality,
      batteryOptimized: batteryOptimized ?? this.batteryOptimized,
      maxRetries: maxRetries ?? this.maxRetries,
      retryDelaySeconds: retryDelaySeconds ?? this.retryDelaySeconds,
      compressBeforeStorage: compressBeforeStorage ?? this.compressBeforeStorage,
      maxStorageMB: maxStorageMB ?? this.maxStorageMB,
      autoDeleteCompleted: autoDeleteCompleted ?? this.autoDeleteCompleted,
    );
  }
}

enum AudioQuality {
  low(sampleRate: 8000, bitRate: 16000, channels: 1),
  standard(sampleRate: 16000, bitRate: 24000, channels: 1),
  high(sampleRate: 22050, bitRate: 32000, channels: 1);

  const AudioQuality({
    required this.sampleRate,
    required this.bitRate,
    required this.channels,
  });

  final int sampleRate;
  final int bitRate;
  final int channels;

  String get displayName {
    switch (this) {
      case AudioQuality.low:
        return 'Low (8kHz)';
      case AudioQuality.standard:
        return 'Standard (16kHz)';
      case AudioQuality.high:
        return 'High (22kHz)';
    }
  }
}