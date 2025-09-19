import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  FirebaseMessaging? _firebaseMessaging;
  
  bool _isInitialized = false;
  String? _fcmToken;
  
  // Notification channels
  static const String _syncChannelId = 'sync_notifications';
  static const String _captureChannelId = 'capture_notifications';
  static const String _systemChannelId = 'system_notifications';
  
  bool get isInitialized => _isInitialized;
  String? get fcmToken => _fcmToken;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _initializeLocalNotifications();
      await _initializeFirebaseMessaging();
      
      _isInitialized = true;
      debugPrint('NotificationService initialized successfully');
      
    } catch (e) {
      debugPrint('Failed to initialize NotificationService: $e');
      // Don't rethrow - notifications are not critical for core functionality
    }
  }

  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create notification channels for Android
    if (Platform.isAndroid) {
      await _createNotificationChannels();
    }
  }

  Future<void> _createNotificationChannels() async {
    const syncChannel = AndroidNotificationChannel(
      _syncChannelId,
      'Sync Notifications',
      description: 'Notifications about upload sync status',
      importance: Importance.defaultImportance,
    );

    const captureChannel = AndroidNotificationChannel(
      _captureChannelId,
      'Capture Notifications',
      description: 'Notifications about audio capture status',
      importance: Importance.low,
    );

    const systemChannel = AndroidNotificationChannel(
      _systemChannelId,
      'System Notifications',
      description: 'Important system notifications',
      importance: Importance.high,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(syncChannel);
        
    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(captureChannel);
        
    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(systemChannel);
  }

  Future<void> _initializeFirebaseMessaging() async {
    try {
      _firebaseMessaging = FirebaseMessaging.instance;
      
      // Request permission
      final settings = await _firebaseMessaging!.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('User granted notification permission');
        
        // Get FCM token
        _fcmToken = await _firebaseMessaging!.getToken();
        debugPrint('FCM Token: $_fcmToken');
        
        // Listen for token refresh
        _firebaseMessaging!.onTokenRefresh.listen((token) {
          _fcmToken = token;
          debugPrint('FCM Token refreshed: $token');
          // TODO: Send updated token to backend
        });
        
        // Handle foreground messages
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
        
        // Handle background messages
        FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);
        
      } else {
        debugPrint('User declined notification permission');
      }
      
    } catch (e) {
      debugPrint('Firebase Messaging initialization failed: $e');
      // Continue without Firebase - local notifications will still work
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.payload}');
    // TODO: Handle notification tap navigation
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint('Received foreground message: ${message.messageId}');
    
    // Show local notification for foreground messages
    await _showLocalNotification(
      title: message.notification?.title ?? 'ZamIO',
      body: message.notification?.body ?? 'New notification',
      payload: message.data.toString(),
      channelId: _systemChannelId,
    );
  }

  static Future<void> _handleBackgroundMessage(RemoteMessage message) async {
    debugPrint('Received background message: ${message.messageId}');
    // Background message handling
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
    String channelId = _systemChannelId,
    int? id,
  }) async {
    final notificationId = id ?? DateTime.now().millisecondsSinceEpoch.remainder(100000);
    
    const androidDetails = AndroidNotificationDetails(
      _systemChannelId,
      'System Notifications',
      channelDescription: 'Important system notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    
    const iosDetails = DarwinNotificationDetails();
    
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      notificationId,
      title,
      body,
      details,
      payload: payload,
    );
  }

  // Specific notification methods

  Future<void> showCaptureStartedNotification() async {
    await _showLocalNotification(
      title: 'Audio Capture Started',
      body: 'ZamIO is now capturing audio for fingerprinting',
      channelId: _captureChannelId,
    );
  }

  Future<void> showCaptureStoppedNotification() async {
    await _showLocalNotification(
      title: 'Audio Capture Stopped',
      body: 'Audio capture has been stopped',
      channelId: _captureChannelId,
    );
  }

  Future<void> showSyncStartedNotification(int pendingCount) async {
    await _showLocalNotification(
      title: 'Sync Started',
      body: 'Uploading $pendingCount pending audio captures',
      channelId: _syncChannelId,
    );
  }

  Future<void> showSyncCompletedNotification({
    required int completed,
    required int failed,
  }) async {
    final title = failed == 0 
        ? 'Sync Completed'
        : 'Sync Completed with Errors';
        
    final body = failed == 0
        ? 'Successfully uploaded $completed captures'
        : 'Uploaded $completed captures, $failed failed';
    
    await _showLocalNotification(
      title: title,
      body: body,
      channelId: _syncChannelId,
    );
  }

  Future<void> showSyncFailedNotification(String error) async {
    await _showLocalNotification(
      title: 'Sync Failed',
      body: 'Failed to sync captures: $error',
      channelId: _syncChannelId,
    );
  }

  Future<void> showConnectivityRestoredNotification() async {
    await _showLocalNotification(
      title: 'Connection Restored',
      body: 'Internet connection restored, starting sync...',
      channelId: _systemChannelId,
    );
  }

  Future<void> showStorageWarningNotification(double usagePercentage) async {
    await _showLocalNotification(
      title: 'Storage Warning',
      body: 'Storage is ${usagePercentage.toStringAsFixed(0)}% full. Consider cleaning up old captures.',
      channelId: _systemChannelId,
    );
  }

  Future<void> showStorageCriticalNotification() async {
    await _showLocalNotification(
      title: 'Storage Critical',
      body: 'Storage is critically low. New captures may fail.',
      channelId: _systemChannelId,
    );
  }

  Future<void> showCaptureProcessedNotification({
    required String trackTitle,
    required String artist,
  }) async {
    await _showLocalNotification(
      title: 'Track Identified',
      body: 'Detected: $trackTitle by $artist',
      channelId: _captureChannelId,
    );
  }

  Future<void> showUploadProgressNotification({
    required int completed,
    required int total,
  }) async {
    final progress = ((completed / total) * 100).round();
    
    await _showLocalNotification(
      title: 'Uploading Captures',
      body: 'Progress: $completed/$total ($progress%)',
      channelId: _syncChannelId,
      id: 999, // Use fixed ID to update the same notification
    );
  }

  // Utility methods

  Future<void> cancelAllNotifications() async {
    await _localNotifications.cancelAll();
  }

  Future<void> cancelNotification(int id) async {
    await _localNotifications.cancel(id);
  }

  Future<bool> areNotificationsEnabled() async {
    if (Platform.isAndroid) {
      final androidImplementation = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await androidImplementation?.areNotificationsEnabled() ?? false;
    }
    
    if (Platform.isIOS) {
      final iosImplementation = _localNotifications
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await iosImplementation?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      ) ?? false;
    }
    
    return false;
  }

  Future<void> openNotificationSettings() async {
    if (Platform.isAndroid) {
      final androidImplementation = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidImplementation?.requestNotificationsPermission();
    }
  }

  // Send FCM token to backend
  Future<void> registerTokenWithBackend() async {
    if (_fcmToken == null) return;
    
    try {
      // TODO: Implement API call to register FCM token with backend
      debugPrint('TODO: Register FCM token with backend: $_fcmToken');
    } catch (e) {
      debugPrint('Failed to register FCM token: $e');
    }
  }
}