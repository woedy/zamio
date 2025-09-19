import 'package:shared_preferences/shared_preferences.dart';

class AuthStore {
  static const _kToken = 'auth_token';
  static const _kStationId = 'station_id';
  static const _kBaseUrl = 'base_url';

  static Future<void> saveSession({required String token, required String stationId, required String baseUrl}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, token);
    await prefs.setString(_kStationId, stationId);
    await prefs.setString(_kBaseUrl, baseUrl);
  }

  static Future<Map<String, String>> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'token': prefs.getString(_kToken) ?? '',
      'station_id': prefs.getString(_kStationId) ?? '',
      'base_url': prefs.getString(_kBaseUrl) ?? '',
    };
  }

  static Future<bool> hasSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_kToken);
    final stationId = prefs.getString(_kStationId);
    return (token != null && token.isNotEmpty && stationId != null && stationId.isNotEmpty);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kStationId);
    // keep base_url unless explicitly cleared
  }

  static Future<void> setBaseUrl(String baseUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = baseUrl.endsWith('/') ? baseUrl : (baseUrl + '/');
    await prefs.setString(_kBaseUrl, normalized);
  }
}
