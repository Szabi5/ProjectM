// lib/services/theme_service.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends ChangeNotifier {
  static const _key = 'app_theme_mode';
  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  /// 👈 Add this getter (this fixes your main.dart error)
  bool get isDarkMode {
    if (_mode == ThemeMode.dark) return true;
    if (_mode == ThemeMode.light) return false;
    // When system mode — decide based on platform brightness
    final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return brightness == Brightness.dark;
  }

  ThemeService() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getString(_key) ?? 'system';

    if (val == 'light') {
      _mode = ThemeMode.light;
    } else if (val == 'dark') {
      _mode = ThemeMode.dark;
    } else {
      _mode = ThemeMode.system;
    }

    notifyListeners();
  }

  Future<void> setMode(ThemeMode m) async {
    _mode = m;

    final prefs = await SharedPreferences.getInstance();
    final strMode =
        m == ThemeMode.light ? 'light' :
        m == ThemeMode.dark ? 'dark' :
        'system';

    await prefs.setString(_key, strMode);
    notifyListeners();
  }
}
