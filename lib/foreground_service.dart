import 'dart:io';
import 'dart:isolate';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class RecorderTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {}

  @override
  Future<void> onEvent(DateTime timestamp, SendPort? sendPort) async {}

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {}

  @override
  void onButtonPressed(String id) {}
  
  @override
  void onRepeatEvent(DateTime timestamp, SendPort? sendPort) {
    // TODO: implement onRepeatEvent
  }
}

Future<void> initForegroundService() async {
  if (!Platform.isAndroid) return;
  // Note: init returns void in recent versions; do not await
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'zamio_recorder',
      channelName: 'ZamIO Recording',
      channelDescription: 'Background audio capture in progress',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
      isSticky: true,
      visibility: NotificationVisibility.VISIBILITY_PUBLIC,
      playSound: false,
    ),
    iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
    foregroundTaskOptions: const ForegroundTaskOptions(),
  );
}

Future<void> startForegroundService({String? content}) async {
  if (!Platform.isAndroid) return;
  await FlutterForegroundTask.startService(
    notificationTitle: 'ZamIO Recording',
    notificationText: content ?? 'Capturing audio for fingerprinting',
    callback: startCallback,
  );
}

Future<void> stopForegroundService() async {
  if (!Platform.isAndroid) return;
  await FlutterForegroundTask.stopService();
}

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(RecorderTaskHandler());
}
