import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';

/// Theme mode enum
enum AppThemeMode {
  dark,
  light,
  system,
}

/// Provider for theme management
class ThemeProvider extends ChangeNotifier {
  static const String _themeKey = 'app_theme_mode';
  
  AppThemeMode _themeMode = AppThemeMode.dark;
  ThemeMode _flutterThemeMode = ThemeMode.dark;

  ThemeProvider() {
    _loadTheme();
  }

  AppThemeMode get themeMode => _themeMode;
  ThemeMode get flutterThemeMode => _flutterThemeMode;
  
  bool get isDarkMode => _flutterThemeMode == ThemeMode.dark;
  
  /// Get current theme data based on mode
  ThemeData get currentTheme {
    if (_flutterThemeMode == ThemeMode.dark) {
      return NexaLinkTheme.darkTheme;
    }
    return NexaLinkTheme.lightTheme;
  }

  /// Load saved theme preference
  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final modeIndex = prefs.getInt(_themeKey) ?? 0;
    _themeMode = AppThemeMode.values[modeIndex];
    _updateFlutterThemeMode();
    notifyListeners();
  }

  /// Set theme mode
  Future<void> setThemeMode(AppThemeMode mode) async {
    _themeMode = mode;
    _updateFlutterThemeMode();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, mode.index);
    
    notifyListeners();
  }

  /// Toggle between dark and light mode
  Future<void> toggleTheme() async {
    if (_themeMode == AppThemeMode.system) {
      await setThemeMode(AppThemeMode.dark);
    } else if (_themeMode == AppThemeMode.dark) {
      await setThemeMode(AppThemeMode.light);
    } else {
      await setThemeMode(AppThemeMode.dark);
    }
  }

  /// Update Flutter ThemeMode based on AppThemeMode
  void _updateFlutterThemeMode() {
    switch (_themeMode) {
      case AppThemeMode.dark:
        _flutterThemeMode = ThemeMode.dark;
        break;
      case AppThemeMode.light:
        _flutterThemeMode = ThemeMode.light;
        break;
      case AppThemeMode.system:
        _flutterThemeMode = ThemeMode.system;
        break;
    }
  }
}
