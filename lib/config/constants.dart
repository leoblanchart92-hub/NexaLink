/// Application constants for NexaLink
class AppConstants {
  // App info
  static const String appName = 'NexaLink';
  static const String appVersion = '1.2.0';
  static const String appTagline = 'Secure Mobile Internet Sharing';

  // WireGuard defaults
  static const int wgDefaultPort = 51820;
  static const String wgDefaultDns = '1.1.1.1';
  static const int wgKeepAliveInterval = 25; // seconds
  static const String wgAllowedIPs = '0.0.0.0/0';
  static const String wgTunnelAddress = '10.10.10.0/24';
  static const String ownerTunnelIp = '10.10.10.1';
  static const String guestTunnelSubnet = '10.10.10.';

  // Relay server (can be configured by user)
  static const String defaultRelayHost = 'relay.nexalink.app';
  static const int defaultRelayPort = 443;

  // Connection limits
  static const int maxGuestDevices = 10;
  static const int maxQrCodeValidityMinutes = 30;

  // Network monitoring
  static const int statsUpdateIntervalSeconds = 3;
  static const int connectionCheckIntervalSeconds = 10;

  // Storage keys
  static const String keyOwnerConfig = 'owner_config';
  static const String keyGuestConfig = 'guest_config';
  static const String keyDeviceId = 'device_id';
  static const String keyPrivateKey = 'private_key';
  static const String keyPublicKey = 'public_key';
  static const String keyGuestList = 'guest_list';
  static const String keySettings = 'settings';
  static const String keyFirstLaunch = 'first_launch';

  // VPN notification
  static const int vpnNotificationId = 1001;
  static const String vpnNotificationChannel = 'vpn_service';
  static const String vpnNotificationChannelName = 'VPN Connection';

  // Permissions
  static const List<String> requiredPermissions = [
    'android.permission.INTERNET',
    'android.permission.ACCESS_NETWORK_STATE',
    'android.permission.ACCESS_WIFI_STATE',
    'android.permission.CAMERA',
    'android.permission.FOREGROUND_SERVICE',
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.WRITE_EXTERNAL_STORAGE',
    'android.permission.READ_EXTERNAL_STORAGE',
  ];

  // Animation durations
  static const Duration animFast = Duration(milliseconds: 200);
  static const Duration animMedium = Duration(milliseconds: 400);
  static const Duration animSlow = Duration(milliseconds: 800);
}
