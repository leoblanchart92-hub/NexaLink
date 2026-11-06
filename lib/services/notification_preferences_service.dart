import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/theme.dart';

/// Service to manage notification preferences
class NotificationPreferencesService {
  static NotificationPreferencesService? _instance;
  late SharedPreferences _prefs;

  NotificationPreferencesService._();

  static Future<NotificationPreferencesService> getInstance() async {
    _instance ??= NotificationPreferencesService._();
    await _instance!._init();
    return _instance!;
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Guest connection notifications
  bool get notifyGuestConnected => _prefs.getBool('notify_guest_connected') ?? true;
  Future<void> setNotifyGuestConnected(bool value) => _prefs.setBool('notify_guest_connected', value);

  bool get notifyGuestDisconnected => _prefs.getBool('notify_guest_disconnected') ?? true;
  Future<void> setNotifyGuestDisconnected(bool value) => _prefs.setBool('notify_guest_disconnected', value);

  // Data limit notifications
  bool get notifyDataLimitWarning => _prefs.getBool('notify_data_limit_warning') ?? true;
  Future<void> setNotifyDataLimitWarning(bool value) => _prefs.setBool('notify_data_limit_warning', value);

  bool get notifyDataLimitReached => _prefs.getBool('notify_data_limit_reached') ?? true;
  Future<void> setNotifyDataLimitReached(bool value) => _prefs.setBool('notify_data_limit_reached', value);

  // VPN status notifications
  bool get notifyVpnStatus => _prefs.getBool('notify_vpn_status') ?? false;
  Future<void> setNotifyVpnStatus(bool value) => _prefs.setBool('notify_vpn_status', value);

  bool get notifyVpnErrors => _prefs.getBool('notify_vpn_errors') ?? true;
  Future<void> setNotifyVpnErrors(bool value) => _prefs.setBool('notify_vpn_errors', value);

  // Connection quality notifications
  bool get notifyConnectionIssues => _prefs.getBool('notify_connection_issues') ?? true;
  Future<void> setNotifyConnectionIssues(bool value) => _prefs.setBool('notify_connection_issues', value);

  // Silent hours
  bool get silentHoursEnabled => _prefs.getBool('silent_hours_enabled') ?? false;
  Future<void> setSilentHoursEnabled(bool value) => _prefs.setBool('silent_hours_enabled', value);

  int get silentHoursStart => _prefs.getInt('silent_hours_start') ?? 22; // 22:00
  Future<void> setSilentHoursStart(int hour) => _prefs.setInt('silent_hours_start', hour);

  int get silentHoursEnd => _prefs.getInt('silent_hours_end') ?? 8; // 08:00
  Future<void> setSilentHoursEnd(int hour) => _prefs.setInt('silent_hours_end', hour);

  /// Check if current time is within silent hours
  bool isSilentHours() {
    if (!silentHoursEnabled) return false;

    final now = DateTime.now();
    final currentHour = now.hour;

    if (silentHoursStart <= silentHoursEnd) {
      // Same day range (e.g., 9-17)
      return currentHour >= silentHoursStart && currentHour < silentHoursEnd;
    } else {
      // Overnight range (e.g., 22-8)
      return currentHour >= silentHoursStart || currentHour < silentHoursEnd;
    }
  }

  /// Reset all preferences to defaults
  Future<void> resetToDefaults() async {
    await _prefs.remove('notify_guest_connected');
    await _prefs.remove('notify_guest_disconnected');
    await _prefs.remove('notify_data_limit_warning');
    await _prefs.remove('notify_data_limit_reached');
    await _prefs.remove('notify_vpn_status');
    await _prefs.remove('notify_vpn_errors');
    await _prefs.remove('notify_connection_issues');
    await _prefs.remove('silent_hours_enabled');
    await _prefs.remove('silent_hours_start');
    await _prefs.remove('silent_hours_end');
  }
}
