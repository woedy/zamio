import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:zamio/auth_store.dart';
import 'package:zamio/home_scaffold.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController(text: 'http://192.168.43.121:8000/');
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      final base = _baseUrlCtrl.text.trim();
      final uri = Uri.parse(base).resolve('api/accounts/login-station/');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': _emailCtrl.text.trim().toLowerCase(),
          'password': _passwordCtrl.text,
          // Backend currently requires fcm_token; provide placeholder until FCM integrated
          'fcm_token': 'device',
        }),
      );
      if (res.statusCode != 200) {
        _error = 'Login failed (${res.statusCode}). Check credentials and server URL.';
        try {
          final j = jsonDecode(res.body);
          _error = j['errors']?.toString() ?? _error;
        } catch (_) {}
        setState(() { _loading = false; });
        return;
      }
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final data = (j['data'] ?? {}) as Map<String, dynamic>;
      final token = (data['token'] ?? '').toString();
      final stationId = (data['station_id'] ?? '').toString();
      if (token.isEmpty || stationId.isEmpty) {
        setState(() { _loading = false; _error = 'Invalid response from server'; });
        return;
      }
      await AuthStore.saveSession(token: token, stationId: stationId, baseUrl: base);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScaffold()),
        (route) => false,
      );
    } catch (e) {
      setState(() { _loading = false; _error = 'Network error: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Station Login')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _baseUrlCtrl,
                    decoration: const InputDecoration(labelText: 'Server Base URL', prefixIcon: Icon(Icons.cloud)),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email)),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordCtrl,
                    decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock)),
                    obscureText: true,
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  if (_error != null) ...[
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _submit,
                      icon: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.login),
                      label: const Text('Login'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

