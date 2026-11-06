import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

/// Service for intelligent app notifications
class NotificationService {
  static NotificationService? _instance;
  late FlutterLocalNotificationsPlugin _notificationsPlugin;
  bool _initialized = false;

  NotificationService._();

  static Future<NotificationService> getInstance() async {
    _instance ??= NotificationService._();
    if (!_instance!._initialized) {
      await _instance!._init();
    }
    return _instance!;
  }

  Future<void> _init() async {
    _notificationsPlugin = FlutterLocalNotificationsPlugin();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        // Handle notification tap
        debugPrint('Notification tapped: ${details.payload}');
      },
    );

    // Request permissions for Android 13+
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  /// Show notification when a guest connects
  Future<void> showGuestConnected(String guestName) async {
    await _showNotification(
      id: 1,
      title: '🔗 Invité connecté',
      body: '$guestName s\'est connecté à votre réseau',
      channelName: 'connexions',
      channelDescription: 'Notifications de connexion des invités',
      icon: Icons.person_add,
      color: const Color(0xFF10B981),
    );
  }

  /// Show notification when a guest disconnects
  Future<void> showGuestDisconnected(String guestName) async {
    await _showNotification(
      id: 2,
      title: '👋 Invité déconnecté',
      body: '$guestName s\'est déconnecté',
      channelName: 'connexions',
      channelDescription: 'Notifications de connexion des invités',
      icon: Icons.person_remove,
      color: const Color(0xFF94A3B8),
    );
  }

  /// Show notification when data limit is reached
  Future<void> showDataLimitReached(String guestName, String limitStr) async {
    await _showNotification(
      id: 3,
      title: '⚠️ Limite de données atteinte',
      body: '$guestName a atteint sa limite de $limitStr',
      channelName: 'data_limits',
      channelDescription: 'Alertes de limites de données',
      icon: Icons.data_usage,
      color: const Color(0xFFF59E0B),
    );
  }

  /// Show notification when data limit is approaching
  Future<void> showDataLimitWarning(String guestName, int percent) async {
    await _showNotification(
      id: 4,
      title: '📊 Alerte consommation',
      body: '$guestName a utilisé $percent% de sa limite de données',
      channelName: 'data_limits',
      channelDescription: 'Alertes de limites de données',
      icon: Icons.warning_amber,
      color: const Color(0xFFF59E0B),
    );
  }

  /// Show VPN status notification (persistent)
  Future<void> showVpnStatus(bool isActive, {int activeGuests = 0}) async {
    if (isActive) {
      await _showOngoingNotification(
        id: 100,
        title: '🛡️ NexaLink actif',
        body: activeGuests > 0
            ? 'Tunnel VPN ouvert • $activeGuests invité(s) connecté(s)'
            : 'Tunnel VPN ouvert • En attente d\'invités',
        channelName: 'vpn_status',
        channelDescription: 'Statut du VPN',
        icon: Icons.shield,
        color: const Color(0xFF3B82F6),
      );
    } else {
      await cancelNotification(100);
    }
  }

  /// Show connection error notification
  Future<void> showConnectionError(String message) async {
    await _showNotification(
      id: 5,
      title: '❌ Erreur de connexion',
      body: message,
      channelName: 'errors',
      channelDescription: 'Erreurs et problèmes',
      icon: Icons.error,
      color: const Color(0xFFEF4444),
    );
  }

  /// Show auto-reconnect notification
  Future<void> showReconnecting() async {
    await _showNotification(
      id: 6,
      title: '🔄 Reconnexion...',
      body: 'Tentative de reconnexion au tunnel VPN',
      channelName: 'vpn_status',
      channelDescription: 'Statut du VPN',
      icon: Icons.refresh,
      color: const Color(0xFF3B82F6),
    );
  }

  /// Cancel a specific notification
  Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
  }

  /// Cancel all notifications
  Future<void> cancelAll() async {
    await _notificationsPlugin.cancelAll();
  }

  /// Internal method to show a standard notification
  Future<void> _showNotification({
    required int id,
    required String title,
    required String body,
    required String channelName,
    required String channelDescription,
    required IconData icon,
    required Color color,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelName,
      channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      color: color,
      enableLights: true,
      enableVibration: true,
      playSound: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(id, title, body, details);
  }

  /// Internal method to show an ongoing (persistent) notification
  Future<void> _showOngoingNotification({
    required int id,
    required String title,
    required String body,
    required String channelName,
    required String channelDescription,
    required IconData icon,
    required Color color,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelName,
      channelDescription,
      importance: Importance.low,
      priority: Priority.low,
      icon: '@mipmap/ic_launcher',
      color: color,
      ongoing: true,
      autoCancel: false,
      enableLights: false,
      enableVibration: false,
      playSound: false,
      showProgress: false,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: false,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(id, title, body, details);
  }
}
