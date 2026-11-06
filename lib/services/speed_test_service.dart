import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Service for automatic speed detection and connection quality monitoring
class SpeedTestService extends ChangeNotifier {
  static SpeedTestService? _instance;
  
  SpeedResult? _lastResult;
  bool _isTesting = false;
  Timer? _monitoringTimer;
  bool _autoMonitoring = false;
  
  // Thresholds
  static const int poorSpeedKbps = 100;
  static const int fairSpeedKbps = 500;
  static const int goodSpeedKbps = 2000;
  static const int excellentSpeedKbps = 10000;

  SpeedTestService._();

  static SpeedTestService getInstance() {
    _instance ??= SpeedTestService._();
    return _instance!;
  }

  SpeedResult? get lastResult => _lastResult;
  bool get isTesting => _isTesting;
  bool get autoMonitoring => _autoMonitoring;

  /// Run a speed test
  Future<SpeedResult> runSpeedTest() async {
    if (_isTesting) return _lastResult ?? SpeedResult.empty();
    
    _isTesting = true;
    notifyListeners();

    try {
      final result = SpeedResult();
      
      // Test download speed
      final downloadStart = DateTime.now();
      int downloadedBytes = 0;
      
      try {
        final client = HttpClient();
        final request = await client.getUrl(Uri.parse('https://speed.cloudflare.com/__down?bytes=1000000'));
        final response = await request.close();
        
        await for (final data in response) {
          downloadedBytes += data.length;
        }
        
        final downloadDuration = DateTime.now().difference(downloadStart);
        result.downloadSpeedKbps = (downloadedBytes * 8 / 1024) / downloadDuration.inSeconds;
        
        client.close();
      } catch (e) {
        debugPrint('Download test error: $e');
      }

      // Test latency (ping)
      try {
        final pingTimes = <int>[];
        
        for (int i = 0; i < 5; i++) {
          final stopwatch = Stopwatch()..start();
          final socket = await Socket.connect('8.8.8.8', 53, timeout: const Duration(seconds: 2));
          stopwatch.stop();
          pingTimes.add(stopwatch.elapsedMilliseconds);
          await socket.close();
        }
        
        if (pingTimes.isNotEmpty) {
          result.latencyMs = pingTimes.reduce((a, b) => a + b) ~/ pingTimes.length;
          result.jitterMs = pingTimes.reduce((a, b) => a + (b - pingTimes.first).abs()) ~/ pingTimes.length;
        }
      } catch (e) {
        debugPrint('Ping test error: $e');
      }

      // Determine quality
      result.quality = _determineQuality(result.downloadSpeedKbps, result.latencyMs);
      result.timestamp = DateTime.now();

      _lastResult = result;
      _isTesting = false;
      notifyListeners();

      return result;
    } catch (e) {
      _isTesting = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Start automatic speed monitoring
  void startAutoMonitoring({Duration interval = const Duration(minutes: 5)}) {
    _autoMonitoring = true;
    _monitoringTimer?.cancel();
    _monitoringTimer = Timer.periodic(interval, (_) {
      _monitorConnection();
    });
    notifyListeners();
  }

  /// Stop automatic speed monitoring
  void stopAutoMonitoring() {
    _autoMonitoring = false;
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    notifyListeners();
  }

  /// Monitor connection quality (lightweight test)
  Future<void> _monitorConnection() async {
    try {
      final stopwatch = Stopwatch()..start();
      final socket = await Socket.connect('8.8.8.8', 53, timeout: const Duration(seconds: 3));
      stopwatch.stop();
      await socket.close();

      final latency = stopwatch.elapsedMilliseconds;
      
      // If latency is very high, trigger warning
      if (latency > 500) {
        debugPrint('⚠️ High latency detected: ${latency}ms');
        // Could trigger notification here
      }
    } catch (e) {
      debugPrint('⚠️ Connection issue detected: $e');
      // Could trigger notification here
    }
  }

  /// Determine connection quality based on speed and latency
  ConnectionQuality _determineQuality(double? speedKbps, int? latencyMs) {
    if (speedKbps == null || latencyMs == null) return ConnectionQuality.unknown;

    // Score based on speed (0-100)
    int speedScore;
    if (speedKbps >= excellentSpeedKbps) {
      speedScore = 100;
    } else if (speedKbps >= goodSpeedKbps) {
      speedScore = 75 + ((speedKbps - goodSpeedKbps) / (excellentSpeedKbps - goodSpeedKbps) * 25).round();
    } else if (speedKbps >= fairSpeedKbps) {
      speedScore = 50 + ((speedKbps - fairSpeedKbps) / (goodSpeedKbps - fairSpeedKbps) * 25).round();
    } else if (speedKbps >= poorSpeedKbps) {
      speedScore = 25 + ((speedKbps - poorSpeedKbps) / (fairSpeedKbps - poorSpeedKbps) * 25).round();
    } else {
      speedScore = (speedKbps / poorSpeedKbps * 25).round();
    }

    // Score based on latency (0-100, lower is better)
    int latencyScore;
    if (latencyMs <= 50) {
      latencyScore = 100;
    } else if (latencyMs <= 100) {
      latencyScore = 75 + ((100 - latencyMs) / 50 * 25).round();
    } else if (latencyMs <= 200) {
      latencyScore = 50 + ((200 - latencyMs) / 100 * 25).round();
    } else if (latencyMs <= 500) {
      latencyScore = 25 + ((500 - latencyMs) / 300 * 25).round();
    } else {
      latencyScore = 0;
    }

    // Combined score
    final totalScore = (speedScore * 0.7 + latencyScore * 0.3).round();

    if (totalScore >= 80) return ConnectionQuality.excellent;
    if (totalScore >= 60) return ConnectionQuality.good;
    if (totalScore >= 40) return ConnectionQuality.fair;
    if (totalScore >= 20) return ConnectionQuality.poor;
    return ConnectionQuality.bad;
  }

  /// Get recommendation based on current connection
  String getRecommendation() {
    if (_lastResult == null) return 'Lancez un test de vitesse pour obtenir une recommandation';

    switch (_lastResult!.quality) {
      case ConnectionQuality.excellent:
        return 'Excellente connexion ! Vous pouvez partager avec plusieurs invités.';
      case ConnectionQuality.good:
        return 'Bonne connexion. Convient pour 1-2 invités.';
      case ConnectionQuality.fair:
        return 'Connexion moyenne. Limitez à 1 invité et évitez le streaming.';
      case ConnectionQuality.poor:
        return 'Connexion lente. Le partage peut être instable.';
      case ConnectionQuality.bad:
        return 'Connexion très lente. Le partage VPN n\'est pas recommandé.';
      case ConnectionQuality.unknown:
        return 'Impossible de déterminer la qualité de la connexion.';
    }
  }

  @override
  void dispose() {
    _monitoringTimer?.cancel();
    super.dispose();
  }
}

/// Speed test result
class SpeedResult {
  double? downloadSpeedKbps;
  int? latencyMs;
  int? jitterMs;
  ConnectionQuality quality = ConnectionQuality.unknown;
  DateTime? timestamp;

  SpeedResult();

  factory SpeedResult.empty() => SpeedResult();

  String get formattedDownloadSpeed {
    if (downloadSpeedKbps == null) return 'N/A';
    if (downloadSpeedKbps! >= 1000) {
      return '${(downloadSpeedKbps! / 1000).toStringAsFixed(1)} Mbps';
    }
    return '${downloadSpeedKbps!.toStringAsFixed(0)} Kbps';
  }

  String get formattedLatency {
    if (latencyMs == null) return 'N/A';
    return '${latencyMs}ms';
  }

  String get qualityLabel {
    switch (quality) {
      case ConnectionQuality.excellent:
        return 'Excellente';
      case ConnectionQuality.good:
        return 'Bonne';
      case ConnectionQuality.fair:
        return 'Moyenne';
      case ConnectionQuality.poor:
        return 'Mauvaise';
      case ConnectionQuality.bad:
        return 'Très mauvaise';
      case ConnectionQuality.unknown:
        return 'Inconnue';
    }
  }
}

/// Connection quality levels
enum ConnectionQuality {
  excellent,
  good,
  fair,
  poor,
  bad,
  unknown,
}
