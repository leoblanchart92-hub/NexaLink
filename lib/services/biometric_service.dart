import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

/// Service for biometric authentication
/// Note: Uses a simple PIN-based approach as a fallback since
/// local_auth package may not be available in the project.
/// This simulates biometric-like security with a device PIN pattern.
class BiometricService {
  static BiometricService? _instance;
  late SharedPreferences _prefs;

  BiometricService._();

  static Future<BiometricService> getInstance() async {
    _instance ??= BiometricService._();
    await _instance!._init();
    return _instance!;
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Check if biometric auth is enabled
  bool isEnabled() => _prefs.getBool('biometric_enabled') ?? false;

  /// Enable/disable biometric auth
  Future<void> setEnabled(bool enabled) async {
    await _prefs.setBool('biometric_enabled', enabled);
  }

  /// Check if PIN is set
  bool isPinSet() {
    final pin = _prefs.getString('app_pin');
    return pin != null && pin.isNotEmpty;
  }

  /// Set the app PIN (hashed)
  Future<void> setPin(String pin) async {
    if (pin.isEmpty) {
      await _prefs.remove('app_pin');
      await _prefs.remove('biometric_enabled');
    } else {
      final hash = _simpleHash(pin);
      await _prefs.setString('app_pin', hash);
    }
  }

  /// Verify PIN
  bool verifyPin(String pin) {
    final storedHash = _prefs.getString('app_pin');
    if (storedHash == null) return false;
    return _simpleHash(pin) == storedHash;
  }

  /// Check if PIN lock is required
  bool requiresPin() => isPinSet() && (_prefs.getBool('pin_lock_enabled') ?? false);

  /// Enable/disable PIN lock
  Future<void> setPinLockEnabled(bool enabled) async {
    await _prefs.setBool('pin_lock_enabled', enabled);
  }

  /// Get the number of failed attempts
  int getFailedAttempts() => _prefs.getInt('failed_pin_attempts') ?? 0;

  /// Increment failed attempts
  Future<void> incrementFailedAttempts() async {
    final attempts = getFailedAttempts() + 1;
    await _prefs.setInt('failed_pin_attempts', attempts);
  }

  /// Reset failed attempts
  Future<void> resetFailedAttempts() async {
    await _prefs.remove('failed_pin_attempts');
    await _prefs.remove('lockout_time');
  }

  /// Check if user is locked out
  bool isLockedOut() {
    final lockoutTime = _prefs.getString('lockout_time');
    if (lockoutTime == null) return false;
    
    final lockout = DateTime.parse(lockoutTime);
    final now = DateTime.now();
    
    // 5 attempts = 30 seconds lockout
    if (getFailedAttempts() >= 5 && now.difference(lockout).inSeconds < 30) {
      return true;
    }
    
    // 10 attempts = 5 minutes lockout
    if (getFailedAttempts() >= 10 && now.difference(lockout).inMinutes < 5) {
      return true;
    }
    
    return false;
  }

  /// Record failed attempt with timestamp
  Future<void> recordFailedAttempt() async {
    await incrementFailedAttempts();
    final attempts = getFailedAttempts();
    
    if (attempts == 5 || attempts == 10) {
      await _prefs.setString('lockout_time', DateTime.now().toIso8601String());
    }
  }

  /// Get remaining lockout time in seconds
  int getRemainingLockoutSeconds() {
    if (!isLockedOut()) return 0;
    
    final lockoutTime = _prefs.getString('lockout_time');
    if (lockoutTime == null) return 0;
    
    final lockout = DateTime.parse(lockoutTime);
    final now = DateTime.now();
    final attempts = getFailedAttempts();
    
    if (attempts >= 10) {
      final elapsed = now.difference(lockout).inSeconds;
      return (300 - elapsed).clamp(0, 300); // 5 min = 300 sec
    }
    
    final elapsed = now.difference(lockout).inSeconds;
    return (30 - elapsed).clamp(0, 30);
  }

  /// Simple hash function for PIN storage
  String _simpleHash(String input) {
    var hash = 0;
    for (var i = 0; i < input.length; i++) {
      final char = input.codeUnitAt(i);
      hash = ((hash << 5) - hash + char) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  /// Clear all biometric/PIN settings
  Future<void> clearAll() async {
    await _prefs.remove('app_pin');
    await _prefs.remove('biometric_enabled');
    await _prefs.remove('pin_lock_enabled');
    await _prefs.remove('failed_pin_attempts');
    await _prefs.remove('lockout_time');
  }
}
