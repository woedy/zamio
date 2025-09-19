import 'package:flutter/material.dart';
import 'package:zamio/RadioSniffer.dart';
import 'package:zamio/ui/queue_page.dart';
import 'package:zamio/ui/logs_page.dart';
import 'package:zamio/ui/settings_page.dart';

class HomeScaffold extends StatefulWidget {
  const HomeScaffold({super.key});

  @override
  State<HomeScaffold> createState() => _HomeScaffoldState();
}

class _HomeScaffoldState extends State<HomeScaffold> {
  int _index = 0;

  final _pages = const [
    StatusPage(),
    QueuePage(),
    LogsPage(),
    SettingsPage(),
  ];

  final _titles = const [
    'Status',
    'Queue',
    'Logs',
    'Settings',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Status'),
          NavigationDestination(icon: Icon(Icons.queue), label: 'Queue'),
          NavigationDestination(icon: Icon(Icons.list_alt), label: 'Logs'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

