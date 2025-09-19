import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService extends ChangeNotifier {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  
  bool _isConnected = false;
  bool _isWifiConnected = false;
  bool _isMobileConnected = false;
  DateTime? _lastConnectedAt;
  DateTime? _lastDisconnectedAt;

  // Getters
  bool get isConnected => _isConnected;
  bool get isWifiConnected => _isWifiConnected;
  bool get isMobileConnected => _isMobileConnected;
  bool get hasStableConnection => _isConnected && (_isWifiConnected || _isMobileConnected);
  DateTime? get lastConnectedAt => _lastConnectedAt;
  DateTime? get lastDisconnectedAt => _lastDisconnectedAt;

  String get connectionType {
    if (_isWifiConnected) return 'WiFi';
    if (_isMobileConnected) return 'Mobile';
    return 'None';
  }

  Future<void> initialize() async {
    // Check initial connectivity
    await _updateConnectivityStatus();
    
    // Listen for connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _onConnectivityChanged,
      onError: (error) {
        debugPrint('Connectivity stream error: $error');
      },
    );
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _updateConnectivityStatus() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _onConnectivityChanged(results);
    } catch (e) {
      debugPrint('Failed to check connectivity: $e');
      _updateConnectionState(false, false, false);
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final hasWifi = results.contains(ConnectivityResult.wifi);
    final hasMobile = results.contains(ConnectivityResult.mobile);
    final hasConnection = hasWifi || hasMobile;

    _updateConnectionState(hasConnection, hasWifi, hasMobile);
  }

  void _updateConnectionState(bool isConnected, bool isWifi, bool isMobile) {
    final wasConnected = _isConnected;
    
    _isConnected = isConnected;
    _isWifiConnected = isWifi;
    _isMobileConnected = isMobile;

    final now = DateTime.now();
    
    if (isConnected && !wasConnected) {
      _lastConnectedAt = now;
      debugPrint('Connectivity restored: ${connectionType}');
    } else if (!isConnected && wasConnected) {
      _lastDisconnectedAt = now;
      debugPrint('Connectivity lost');
    }

    notifyListeners();
  }

  Future<bool> testConnection({String? testUrl}) async {
    if (!_isConnected) return false;

    try {
      // Simple connectivity test - in a real app you might ping your API
      final results = await _connectivity.checkConnectivity();
      return results.isNotEmpty && 
             (results.contains(ConnectivityResult.wifi) || 
              results.contains(ConnectivityResult.mobile));
    } catch (e) {
      debugPrint('Connection test failed: $e');
      return false;
    }
  }

  Duration? get timeSinceLastConnection {
    if (_isConnected) return Duration.zero;
    if (_lastDisconnectedAt == null) return null;
    return DateTime.now().difference(_lastDisconnectedAt!);
  }

  Duration? get connectionUptime {
    if (!_isConnected || _lastConnectedAt == null) return null;
    return DateTime.now().difference(_lastConnectedAt!);
  }

  // Utility methods for upload decisions
  bool get shouldUploadOnCurrentConnection {
    // Only upload on WiFi or if mobile data usage is acceptable
    return _isWifiConnected || (_isMobileConnected && allowMobileUploads);
  }

  bool get allowMobileUploads {
    // This could be a user setting - for now, allow mobile uploads
    return true;
  }

  Future<void> waitForConnection({Duration? timeout}) async {
    if (_isConnected) return;

    final completer = Completer<void>();
    late StreamSubscription subscription;

    subscription = _connectivity.onConnectivityChanged.listen((results) {
      final hasConnection = results.contains(ConnectivityResult.wifi) || 
                           results.contains(ConnectivityResult.mobile);
      
      if (hasConnection && !completer.isCompleted) {
        subscription.cancel();
        completer.complete();
      }
    });

    if (timeout != null) {
      Timer(timeout, () {
        if (!completer.isCompleted) {
          subscription.cancel();
          completer.completeError(TimeoutException('Connection timeout', timeout));
        }
      });
    }

    return completer.future;
  }
}

class TimeoutException implements Exception {
  final String message;
  final Duration? duration;

  const TimeoutException(this.message, [this.duration]);

  @override
  String toString() {
    if (duration != null) {
      return 'TimeoutException: $message (${duration!.inSeconds}s)';
    }
    return 'TimeoutException: $message';
  }
}