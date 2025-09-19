import 'package:flutter/material.dart';
import 'package:zamio/home_scaffold.dart';
import 'package:zamio/auth_store.dart';
import 'package:zamio/ui/login_page.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:zamio/theme_controller.dart';
import 'package:zamio/services/connectivity_service.dart';
import 'package:zamio/services/sync_service.dart';
import 'package:zamio/services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize core services
  await _initializeServices();
  
  runApp(const RadioSnifferApp());
}

Future<void> _initializeServices() async {
  try {
    // Initialize services in order of dependency
    await ConnectivityService().initialize();
    await NotificationService().initialize();
    await SyncService().initialize();
    
    debugPrint('All services initialized successfully');
  } catch (e) {
    debugPrint('Service initialization failed: $e');
    // Continue anyway - app should still work with reduced functionality
  }
}

class RadioSnifferApp extends StatelessWidget {
  const RadioSnifferApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (context, mode, _) => WithForegroundTask(
        child: MaterialApp(
        title: 'Radio Sniffer',
        theme: ThemeData(colorSchemeSeed: Colors.deepPurple, brightness: Brightness.light, useMaterial3: true),
        darkTheme: ThemeData(colorSchemeSeed: Colors.deepPurple, brightness: Brightness.dark, useMaterial3: true),
        themeMode: mode,
        home: FutureBuilder<bool>(
          future: AuthStore.hasSession(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            return snap.data == true ? const HomeScaffold() : const LoginPage();
          },
        ),
      )),
    );
  }
}
