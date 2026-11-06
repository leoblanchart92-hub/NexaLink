import 'dart:async';
import 'package:flutter/services.dart';
import '../models/vpn_config.dart';
import '../models/connection_stats.dart';
import '../config/constants.dart';

/// WireGuard VPN service for managing the tunnel
/// Communicates with native Android VpnService via MethodChannel
class WireGuardService {
  static WireGuardService? _instance;
  static const MethodChannel _channel = MethodChannel('com.nexalink.app/vpn');
  
  VpnConfig? _config;
  bool _isRunning = false;
  DateTime? _connectionStartTime;
  Timer? _statsTimer;
  
  // Connection stats
  int _bytesRx = 0;
  int _bytesTx = 0;
  int _lastRx = 0;
  int _lastTx = 0;
  int _rxSpeed = 0;
  int _txSpeed = 0;

  // State stream
  final _stateController = StreamController<VpnState>.broadcast();
  Stream<VpnState> get stateStream => _stateController.stream;

  final _statsController = StreamController<ConnectionStats>.broadcast();
  Stream<ConnectionStats> get statsStream => _statsController.stream;

  WireGuardService._();

  static WireGuardService getInstance() {
    _instance ??= WireGuardService._();
    return _instance!;
  }

  bool get isRunning => _isRunning;
  VpnConfig? get config => _config;

  /// Initialize the WireGuard tunnel
  Future<void> initialize() async {
    // No-op: native service handles initialization
  }

  /// Prepare VPN permission (must be called before startTunnel)
  Future<bool> prepareVpn() async {
    try {
      final result = await _channel.invokeMethod<bool>('prepareVpn');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Start the VPN tunnel with given configuration
  Future<bool> startTunnel(VpnConfig config) async {
    try {
      _config = config;
      
      _stateController.add(VpnState.connecting);

      // Step 1: Request VPN permission from Android system
      final prepared = await prepareVpn();
      
      // If permission not granted yet, wait a bit for user to accept
      if (!prepared) {
        await Future.delayed(const Duration(seconds: 2));
      }

      // Step 2: Start the VPN service
      final wgConfig = config.toWgConfig();
      
      final result = await _channel.invokeMethod<bool>('startVpn', {
        'config': wgConfig,
        'ownerPublicKey': config.publicKey,
        'guestPublicKey': config.peerPublicKey ?? '',
        'tunnelAddress': config.tunnelAddress,
        'endpoint': config.endpoint ?? '',
        'port': config.listenPort,
        'isOwner': config.isOwner,
      });

      if (result == true) {
        _isRunning = true;
        _connectionStartTime = DateTime.now();
        _bytesRx = 0;
        _bytesTx = 0;
        _lastRx = 0;
        _lastTx = 0;
        _rxSpeed = 0;
        _txSpeed = 0;

        _stateController.add(VpnState.connected);
        _startStatsMonitoring();
        return true;
      } else {
        _stateController.add(VpnState.error);
        return false;
      }
    } on PlatformException catch (e) {
      _isRunning = false;
      _stateController.add(VpnState.error);
      return false;
    } catch (e) {
      _isRunning = false;
      _stateController.add(VpnState.error);
      return false;
    }
  }

  /// Stop the VPN tunnel
  Future<void> stopTunnel() async {
    try {
      await _channel.invokeMethod('stopVpn');
    } catch (e) {
      // Ignore errors on stop
    }
    _isRunning = false;
    _connectionStartTime = null;
    _statsTimer?.cancel();
    _stateController.add(VpnState.disconnected);
  }

  /// Get current connection statistics
  ConnectionStats getCurrentStats() {
    return ConnectionStats(
      bytesReceived: _bytesRx,
      bytesSent: _bytesTx,
      rxSpeed: _rxSpeed,
      txSpeed: _txSpeed,
      connectionDuration: _connectionStartTime != null
          ? DateTime.now().difference(_connectionStartTime!)
          : Duration.zero,
      isConnected: _isRunning,
      lastUpdated: DateTime.now(),
    );
  }

  /// Start periodic stats monitoring
  void _startStatsMonitoring() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(
      const Duration(seconds: AppConstants.statsUpdateIntervalSeconds),
      (_) async {
        await _updateStats();
      },
    );
  }

  /// Update tunnel statistics from native service
  Future<void> _updateStats() async {
    try {
      if (_isRunning) {
        final stats = await _channel.invokeMethod<Map>('getStats');
        
        if (stats != null) {
          final newRx = stats['bytesReceived'] as int? ?? _bytesRx;
          final newTx = stats['bytesSent'] as int? ?? _bytesTx;
          
          final elapsed = AppConstants.statsUpdateIntervalSeconds;
          _rxSpeed = ((newRx - _lastRx) / elapsed).round();
          _txSpeed = ((newTx - _lastTx) / elapsed).round();
          
          _bytesRx = newRx;
          _bytesTx = newTx;
          _lastRx = newRx;
          _lastTx = newTx;
        }

        _statsController.add(getCurrentStats());
        
        // Check if VPN is still running
        final isRunning = await _channel.invokeMethod<bool>('getStatus');
        if (isRunning == false) {
          _isRunning = false;
          _stateController.add(VpnState.disconnected);
          _statsTimer?.cancel();
        }
      }
    } catch (e) {
      // Stats update failed, continue
    }
  }

  /// Update byte counters (called from native side)
  void updateBytes(int rx, int tx) {
    _bytesRx = rx;
    _bytesTx = tx;
  }

  /// Get the WireGuard configuration string
  String? getConfigString() {
    if (_config == null) return null;
    return _config!.toWgConfig();
  }

  void dispose() {
    _statsTimer?.cancel();
    _stateController.close();
    _statsController.close();
  }
}

enum VpnState {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
}
