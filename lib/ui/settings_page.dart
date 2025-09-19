import 'package:flutter/material.dart';
import 'package:zamio/theme_controller.dart';
import 'package:zamio/auth_store.dart';
import 'package:zamio/ui/login_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // Session-backed settings
  String _stationName = '';
  String _stationId = '';
  String _serverUrl = '';
  String _authToken = '';
  int _chunkSeconds = 10;
  bool _foregroundService = false;
  bool _startOnBoot = false;
  bool _useHttps = true;
  int _retentionDays = 7;
  ThemeMode _themeMode = appThemeMode.value;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final sess = await AuthStore.loadSession();
    setState(() {
      _serverUrl = (sess['base_url'] ?? '').trim();
      _stationId = (sess['station_id'] ?? '').trim();
      _authToken = (sess['token'] ?? '').trim();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(title: 'Station'),
          TextField(
            decoration: const InputDecoration(labelText: 'Station Name', prefixIcon: Icon(Icons.radio)),
            controller: TextEditingController(text: _stationName),
            onChanged: (v) => _stationName = v,
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(labelText: 'Station ID', prefixIcon: Icon(Icons.tag)),
            controller: TextEditingController(text: _stationId),
            onChanged: (v) => _stationId = v,
          ),
          const SizedBox(height: 16),

          _SectionHeader(title: 'Server & Auth'),
          TextField(
            decoration: const InputDecoration(labelText: 'Server URL', prefixIcon: Icon(Icons.cloud)),
            controller: TextEditingController(text: _serverUrl),
            onChanged: (v) => _serverUrl = v,
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(labelText: 'Auth Token', prefixIcon: Icon(Icons.vpn_key)),
            controller: TextEditingController(text: _authToken),
            onChanged: (v) => _authToken = v,
          ),
          SwitchListTile(
            value: _useHttps,
            onChanged: (v) => setState(() => _useHttps = v),
            title: const Text('Use HTTPS'),
            subtitle: const Text('Recommended for production'),
            secondary: const Icon(Icons.lock),
          ),
          const SizedBox(height: 16),

          _SectionHeader(title: 'Appearance'),
          ListTile(
            leading: const Icon(Icons.brightness_6),
            title: const Text('Theme'),
            subtitle: const Text('Light, Dark, or follow System'),
            trailing: DropdownButton<ThemeMode>(
              value: _themeMode,
              onChanged: (v) {
                if (v == null) return;
                setState(() => _themeMode = v);
                appThemeMode.value = v;
              },
              items: const [
                DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
              ],
            ),
          ),
          const SizedBox(height: 16),

          _SectionHeader(title: 'Recording'),
          Row(
            children: [
              const Icon(Icons.timer),
              const SizedBox(width: 12),
              const Text('Chunk Length'),
              const Spacer(),
              DropdownButton<int>(
                value: _chunkSeconds,
                items: const [10, 15, 20, 30]
                    .map((e) => DropdownMenuItem(value: e, child: Text('${e}s')))
                    .toList(),
                onChanged: (v) => setState(() => _chunkSeconds = v ?? _chunkSeconds),
              )
            ],
          ),
          const SizedBox(height: 8),
          const Text('Sample rate: 16 kHz • Mono • ~24 kbps', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),

          _SectionHeader(title: 'Background & Power'),
          SwitchListTile(
            value: _foregroundService,
            onChanged: (v) => setState(() => _foregroundService = v),
            title: const Text('Android Foreground Service'),
            subtitle: const Text('Keep recording alive in background'),
            secondary: const Icon(Icons.battery_full),
          ),
          SwitchListTile(
            value: _startOnBoot,
            onChanged: (v) => setState(() => _startOnBoot = v),
            title: const Text('Start on Boot'),
            subtitle: const Text('Resume service when device restarts'),
            secondary: const Icon(Icons.power_settings_new),
          ),
          const SizedBox(height: 16),

          _SectionHeader(title: 'Privacy & Retention'),
          Row(
            children: [
              const Icon(Icons.event),
              const SizedBox(width: 12),
              const Text('Retention'),
              const Spacer(),
              DropdownButton<int>(
                value: _retentionDays,
                items: const [3, 7, 14, 30]
                    .map((e) => DropdownMenuItem(value: e, child: Text('$e days')))
                    .toList(),
                onChanged: (v) => setState(() => _retentionDays = v ?? _retentionDays),
              )
            ],
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                await AuthStore.setBaseUrl(_serverUrl);
                if (_authToken.isNotEmpty && _stationId.isNotEmpty) {
                  await AuthStore.saveSession(token: _authToken, stationId: _stationId, baseUrl: _serverUrl);
                }
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
              },
              icon: const Icon(Icons.save),
              label: const Text('Save'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          )
          ,
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                await AuthStore.clear();
                if (!context.mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                  (route) => false,
                );
              },
              icon: const Icon(Icons.logout),
              label: const Text('Log out'),
            ),
          )
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
