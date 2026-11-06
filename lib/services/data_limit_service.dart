import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device.dart';

/// Service to manage per-guest data limits
class DataLimitService {
  static DataLimitService? _instance;
  late SharedPreferences _prefs;

  DataLimitService._();

  static Future<DataLimitService> getInstance() async {
    _instance ??= DataLimitService._();
    await _instance!._init();
    return _instance!;
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Get the data limit for a specific device
  int? getDataLimit(String deviceId) {
    return _prefs.getInt('data_limit_$deviceId');
  }

  /// Set the data limit for a specific device
  Future<void> setDataLimit(String deviceId, int? bytes) async {
    if (bytes == null || bytes <= 0) {
      await _prefs.remove('data_limit_$deviceId');
    } else {
      await _prefs.setInt('data_limit_$deviceId', bytes);
    }
  }

  /// Get the data usage for a specific device
  int getDataUsed(String deviceId) {
    return _prefs.getInt('data_used_$deviceId') ?? 0;
  }

  /// Add bytes to a device's data usage
  Future<void> addDataUsed(String deviceId, int bytes) async {
    final current = getDataUsed(deviceId);
    await _prefs.setInt('data_used_$deviceId', current + bytes);
  }

  /// Set the exact data usage for a device
  Future<void> setDataUsed(String deviceId, int bytes) async {
    await _prefs.setInt('data_used_$deviceId', bytes);
  }

  /// Reset data usage for a device
  Future<void> resetDataUsage(String deviceId) async {
    await _prefs.remove('data_used_$deviceId');
  }

  /// Get data limit period for a device
  DataLimitPeriod? getDataLimitPeriod(String deviceId) {
    final value = _prefs.getInt('data_limit_period_$deviceId');
    if (value == null) return null;
    return DataLimitPeriod.values[value];
  }

  /// Set data limit period for a device
  Future<void> setDataLimitPeriod(String deviceId, DataLimitPeriod? period) async {
    if (period == null) {
      await _prefs.remove('data_limit_period_$deviceId');
    } else {
      await _prefs.setInt('data_limit_period_$deviceId', period.index);
    }
  }

  /// Get data limit reset date
  DateTime? getDataLimitResetDate(String deviceId) {
    final str = _prefs.getString('data_limit_reset_$deviceId');
    if (str == null) return null;
    return DateTime.tryParse(str);
  }

  /// Set data limit reset date
  Future<void> setDataLimitResetDate(String deviceId, DateTime? date) async {
    if (date == null) {
      await _prefs.remove('data_limit_reset_$deviceId');
    } else {
      await _prefs.setString('data_limit_reset_$deviceId', date.toIso8601String());
    }
  }

  /// Check if data limit has been reached for a device
  bool isDataLimitReached(String deviceId) {
    final limit = getDataLimit(deviceId);
    if (limit == null || limit <= 0) return false;
    final used = getDataUsed(deviceId);
    return used >= limit;
  }

  /// Get usage percentage
  double getUsagePercent(String deviceId) {
    final limit = getDataLimit(deviceId);
    if (limit == null || limit <= 0) return 0.0;
    final used = getDataUsed(deviceId);
    return (used / limit).clamp(0.0, 1.0);
  }

  /// Calculate next reset date based on period
  DateTime? calculateNextResetDate(DataLimitPeriod period) {
    final now = DateTime.now();
    switch (period) {
      case DataLimitPeriod.daily:
        return DateTime(now.year, now.month, now.day + 1);
      case DataLimitPeriod.weekly:
        final daysUntilMonday = (8 - now.weekday) % 7;
        return DateTime(now.year, now.month, now.day + (daysUntilMonday == 0 ? 7 : daysUntilMonday));
      case DataLimitPeriod.monthly:
        return DateTime(now.year, now.month + 1, 1);
      case DataLimitPeriod.custom:
        return null;
    }
  }

  /// Check if period has elapsed and reset if needed
  Future<void> checkAndResetPeriodicLimits(List<Device> devices) async {
    for (final device in devices) {
      final period = getDataLimitPeriod(device.id);
      if (period == null) continue;

      final resetDate = getDataLimitResetDate(device.id);
      if (resetDate != null && DateTime.now().isAfter(resetDate)) {
        // Reset usage
        await setDataUsed(device.id, 0);
        // Set next reset date
        final nextReset = calculateNextResetDate(period);
        await setDataLimitResetDate(device.id, nextReset);
      }
    }
  }

  /// Get total data used across all devices
  int getTotalDataUsed() {
    final keys = _prefs.getKeys();
    int total = 0;
    for (final key in keys) {
      if (key.startsWith('data_used_')) {
        total += _prefs.getInt(key) ?? 0;
      }
    }
    return total;
  }

  /// Get all data usage stats as a map
  Map<String, int> getAllDataUsage() {
    final result = <String, int>{};
    final keys = _prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith('data_used_')) {
        final deviceId = key.replaceFirst('data_used_', '');
        result[deviceId] = _prefs.getInt(key) ?? 0;
      }
    }
    return result;
  }

  /// Clear all data limits and usage
  Future<void> clearAll() async {
    final keys = _prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith('data_limit_') ||
          key.startsWith('data_used_') ||
          key.startsWith('data_limit_period_') ||
          key.startsWith('data_limit_reset_')) {
        await _prefs.remove(key);
      }
    }
  }

  /// Get daily usage history for a device
  Map<DateTime, int> getDailyUsage(String deviceId, {int days = 30}) {
    final historyKey = 'usage_history_$deviceId';
    final json = _prefs.getString(historyKey);
    if (json == null) return {};
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final result = <DateTime, int>{};
      for (final entry in map.entries) {
        final date = DateTime.parse(entry.key);
        result[date] = entry.value as int;
      }
      return result;
    } catch (e) {
      return {};
    }
  }

  /// Record daily usage
  Future<void> recordDailyUsage(String deviceId, int bytes) async {
    final today = DateTime.now();
    final dateKey = DateTime(today.year, today.month, today.day);
    
    final history = getDailyUsage(deviceId);
    history[dateKey] = (history[dateKey] ?? 0) + bytes;
    
    // Keep only last 30 days
    final cutoff = today.subtract(const Duration(days: 30));
    history.removeWhere((key, _) => key.isBefore(cutoff));
    
    // Save
    final jsonMap = <String, int>{};
    for (final entry in history.entries) {
      jsonMap[entry.key.toIso8601String()] = entry.value;
    }
    await _prefs.setString('usage_history_$deviceId', jsonEncode(jsonMap));
  }
}
