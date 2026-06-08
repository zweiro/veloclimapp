import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Singleton service for managing app settings using SharedPreferences.
class PreferencesService {
  static final PreferencesService instance = PreferencesService._init();
  static SharedPreferences? _prefs;

  // Keys for stored preferences
  static const String _serverUrlKey = 'server_url';
  static const String _sessionCodeKey = 'session_code';

  PreferencesService._init();

  /// Get the SharedPreferences instance, initializing if necessary.
  Future<SharedPreferences> get prefs async {
    if (_prefs != null) return _prefs!;
    WidgetsFlutterBinding.ensureInitialized();
    _prefs = await SharedPreferences.getInstance();
    return _prefs!;
  }

  /// Get the stored server URL.
  Future<String?> getServerUrl() async {
    final preferences = await prefs;
    return preferences.getString(_serverUrlKey);
  }

  /// Set the server URL.
  Future<bool> setServerUrl(String url) async {
    final preferences = await prefs;
    return preferences.setString(_serverUrlKey, url);
  }

  /// Get the stored session code.
  Future<String?> getSessionCode() async {
    final preferences = await prefs;
    return preferences.getString(_sessionCodeKey);
  }

  /// Set the session code.
  Future<bool> setSessionCode(String code) async {
    final preferences = await prefs;
    return preferences.setString(_sessionCodeKey, code);
  }

  /// Clear all settings.
  Future<bool> clearSettings() async {
    final preferences = await prefs;
    await preferences.remove(_serverUrlKey);
    await preferences.remove(_sessionCodeKey);
    return true;
  }
}
