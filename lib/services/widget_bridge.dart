import 'package:flutter/services.dart';

/// Bridge to communicate VPN status to Android home screen widget
class WidgetBridge {
  static const MethodChannel _channel = MethodChannel('com.nexalink.app/widget');

  /// Update the home screen widget with current VPN status
  static Future<void> updateWidget({
    required bool isActive,
    int guestCount = 0,
  }) async {
    try {
      await _channel.invokeMethod('updateWidget', {
        'isActive': isActive,
        'guestCount': guestCount,
      });
    } catch (e) {
      // Widget update failed - not critical
    }
  }
}
