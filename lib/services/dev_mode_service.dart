import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/connection_stats.dart';

/// Service for developer mode - logs, stats, diagnostics
class DevModeService extends ChangeNotifier {
  static DevModeService? _instance;
  
  final List<LogEntry> _logs = [];
  final List<ConnectivityTest> _connectivityTests = [];
  bool _isEnabled = false;
  bool _isRecording = false;
  Timer? _autoRefreshTimer;
  
  // Advanced stats
  int _totalConnections = 0;
  int _totalDisconnections = 0;
  int _totalErrors = 0;
  DateTime? _sessionStartTime;
  Duration _uptime = Duration.zero;

  DevModeService._();

  static DevModeService getInstance() {
    _instance ??= DevModeService._();
    return _instance!;
  }

  bool get isEnabled => _isEnabled;
  bool get isRecording => _isRecording;
  List<LogEntry> get logs => List.unmodifiable(_logs);
  List<ConnectivityTest> get connectivityTests => List.unmodifiable(_connectivityTests);
  int get totalConnections => _totalConnections;
  int get totalDisconnections => _totalDisconnections;
  int get totalErrors => _totalErrors;
  Duration get uptime => _uptime;

  /// Enable/disable dev mode
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    if (enabled) {
      _sessionStartTime = DateTime.now();
      _startAutoRefresh();
    } else {
      _stopAutoRefresh();
    }
    notifyListeners();
  }

  /// Start recording logs
  void startRecording() {
    _isRecording = true;
    _logs.clear();
    notifyListeners();
  }

  /// Stop recording logs
  void stopRecording() {
    _isRecording = false;
    notifyListeners();
  }

  /// Add a log entry
  void log(String message, {LogLevel level = LogLevel.info, String? category}) {
    if (!_isEnabled) return;

    final entry = LogEntry(
      timestamp: DateTime.now(),
      message: message,
      level: level,
      category: category ?? 'General',
    );

    _logs.add(entry);
    
    // Keep only last 1000 logs
    if (_logs.length > 1000) {
      _logs.removeAt(0);
    }

    notifyListeners();
  }

  /// Log VPN connection
  void logConnection(String deviceName) {
    _totalConnections++;
    log('Device connected: $deviceName', level: LogLevel.success, category: 'VPN');
  }

  /// Log VPN disconnection
  void logDisconnection(String deviceName) {
    _totalDisconnections++;
    log('Device disconnected: $deviceName', level: LogLevel.warning, category: 'VPN');
  }

  /// Log error
  void logError(String error, {String? stackTrace}) {
    _totalErrors++;
    log('ERROR: $error${stackTrace != null ? '\n$stackTrace' : ''}', 
        level: LogLevel.error, category: 'Error');
  }

  /// Clear all logs
  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  /// Run connectivity test
  Future<ConnectivityTest> runConnectivityTest() async {
    final test = ConnectivityTest(
      timestamp: DateTime.now(),
      target: 'Google DNS (8.8.8.8)',
    );

    try {
      final stopwatch = Stopwatch()..start();
      
      // Test DNS resolution
      try {
        final addresses = await InternetAddress.lookup('google.com');
        test.dnsResolved = true;
        test.dnsLatencyMs = stopwatch.elapsedMilliseconds;
      } catch (e) {
        test.dnsResolved = false;
      }

      // Test TCP connection
      try {
        final socket = await Socket.connect('8.8.8.8', 53, timeout: const Duration(seconds: 5));
        test.tcpConnected = true;
        test.tcpLatencyMs = stopwatch.elapsedMilliseconds - (test.dnsLatencyMs ?? 0);
        await socket.close();
      } catch (e) {
        test.tcpConnected = false;
      }

      // Test HTTP request
      try {
        final client = HttpClient();
        final request = await client.getUrl(Uri.parse('https://www.google.com'));
        final response = await request.close();
        test.httpStatus = response.statusCode;
        test.httpLatencyMs = stopwatch.elapsedMilliseconds - test.dnsLatencyMs! - test.tcpLatencyMs!;
        client.close();
      } catch (e) {
        test.httpStatus = -1;
      }

      stopwatch.stop();
      test.totalLatencyMs = stopwatch.elapsedMilliseconds;
      test.success = test.dnsResolved && test.tcpConnected && test.httpStatus == 200;

    } catch (e) {
      test.success = false;
      test.error = e.toString();
    }

    _connectivityTests.add(test);
    
    // Keep only last 20 tests
    if (_connectivityTests.length > 20) {
      _connectivityTests.removeAt(0);
    }

    notifyListeners();
    return test;
  }

  /// Get detailed network stats
  Map<String, dynamic> getDetailedStats() {
    return {
      'totalConnections': _totalConnections,
      'totalDisconnections': _totalDisconnections,
      'totalErrors': _totalErrors,
      'uptime': _uptime.inSeconds,
      'sessionStart': _sessionStartTime?.toIso8601String(),
      'logCount': _logs.length,
      'testCount': _connectivityTests.length,
    };
  }

  /// Export logs as string
  String exportLogs() {
    final buffer = StringBuffer();
    buffer.writeln('=== NexaLink Debug Logs ===');
    buffer.writeln('Exported: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Session Start: ${_sessionStartTime?.toIso8601String()}');
    buffer.writeln('Uptime: ${_uptime.inSeconds}s');
    buffer.writeln('');
    buffer.writeln('--- Stats ---');
    buffer.writeln('Connections: $_totalConnections');
    buffer.writeln('Disconnections: $_totalDisconnections');
    buffer.writeln('Errors: $_totalErrors');
    buffer.writeln('');
    buffer.writeln('--- Logs ---');
    
    for (final entry in _logs) {
      buffer.writeln('[${entry.timestamp.toIso8601String()}] [${entry.level.name.toUpperCase()}] [${entry.category}] ${entry.message}');
    }

    if (_connectivityTests.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('--- Connectivity Tests ---');
      for (final test in _connectivityTests) {
        buffer.writeln('[${test.timestamp.toIso8601String()}] ${test.success ? '✓' : '✗'} ${test.target} - ${test.totalLatencyMs}ms');
      }
    }

    return buffer.toString();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_sessionStartTime != null) {
        _uptime = DateTime.now().difference(_sessionStartTime!);
        notifyListeners();
      }
    });
  }

  void _stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }
}

/// Log entry
class LogEntry {
  final DateTime timestamp;
  final String message;
  final LogLevel level;
  final String category;

  LogEntry({
    required this.timestamp,
    required this.message,
    required this.level,
    required this.category,
  });
}

/// Log level
enum LogLevel {
  debug,
  info,
  warning,
  error,
  success,
}

/// Connectivity test result
class ConnectivityTest {
  final DateTime timestamp;
  final String target;
  bool dnsResolved = false;
  bool tcpConnected = false;
  int? httpStatus;
  int? dnsLatencyMs;
  int? tcpLatencyMs;
  int? httpLatencyMs;
  int totalLatencyMs = 0;
  bool success = false;
  String? error;

  ConnectivityTest({
    required this.timestamp,
    required this.target,
  });
}
