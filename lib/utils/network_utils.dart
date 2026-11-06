import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';

/// Network utility functions
class NetworkUtils {
  static final Connectivity _connectivity = Connectivity();
  static final NetworkInfo _networkInfo = NetworkInfo();

  /// Check if device has internet connectivity
  static Future<bool> hasInternetConnection() async {
    try {
      final result = await _connectivity.checkConnectivity();
      if (result == ConnectivityResult.none) return false;
      
      // Try to reach a public DNS server
      try {
        final socket = await Socket.connect('1.1.1.1', 53,
            timeout: const Duration(seconds: 3));
        await socket.close();
        return true;
      } catch (e) {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  /// Get current network type
  static Future<String> getNetworkType() async {
    final result = await _connectivity.checkConnectivity();
    switch (result) {
      case ConnectivityResult.mobile:
        return 'Mobile';
      case ConnectivityResult.wifi:
        return 'Wi-Fi';
      case ConnectivityResult.ethernet:
        return 'Ethernet';
      case ConnectivityResult.bluetooth:
        return 'Bluetooth';
      default:
        return 'None';
    }
  }

  /// Get local IP address
  static Future<String?> getLocalIp() async {
    try {
      final wifiIp = await _networkInfo.getWifiIP();
      if (wifiIp != null) return wifiIp;

      // Fallback: get from network interfaces
      for (final interface in await NetworkInterface.list()) {
        for (final address in interface.addresses) {
          if (address.type == InternetAddressType.IPv4 &&
              !address.isLoopback) {
            return address.address;
          }
        }
      }
    } catch (e) {
      // Ignore
    }
    return null;
  }

  /// Get the public IP address (for endpoint discovery)
  static Future<String?> getPublicIp() async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse('https://api.ipify.org'));
      final response = await request.close();
      final body = await response.transform(const SystemEncoding().decoder).join();
      client.close();
      return body.trim();
    } catch (e) {
      return null;
    }
  }

  /// Check if mobile data is active
  static Future<bool> isMobileDataActive() async {
    final result = await _connectivity.checkConnectivity();
    return result == ConnectivityResult.mobile;
  }

  /// Monitor connectivity changes
  static Stream<ConnectivityResult> onConnectivityChanged() {
    return _connectivity.onConnectivityChanged;
  }

  /// Estimate connection quality based on latency
  static Future<int> measureLatency() async {
    try {
      final stopwatch = Stopwatch()..start();
      final socket = await Socket.connect('1.1.1.1', 53,
          timeout: const Duration(seconds: 5));
      stopwatch.stop();
      await socket.close();
      return stopwatch.elapsedMilliseconds;
    } catch (e) {
      return -1; // Failed to measure
    }
  }
}
