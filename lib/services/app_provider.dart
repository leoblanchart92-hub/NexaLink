import 'dart:async';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../models/device.dart';
import '../models/vpn_config.dart';
import '../models/connection_stats.dart';
import '../services/storage_service.dart';
import '../services/wireguard_service.dart';
import '../services/signal_service.dart';
import '../services/qr_service.dart';
import '../utils/key_generator.dart';
import '../utils/network_utils.dart';
import '../config/constants.dart';

/// Main application state provider
class AppProvider extends ChangeNotifier {
  late StorageService _storage;
  late WireGuardService _wireGuard;
  late SignalService _signal;

  // App state
  bool _isInitialized = false;
  bool _isOwnerMode = false;
  bool _isTunnelActive = false;
  String _deviceId = '';
  String _deviceName = '';
  
  // VPN config
  VpnConfig? _vpnConfig;
  List<Device> _guestDevices = [];
  ConnectionStats _stats = ConnectionStats();
  
  // Network info
  String _networkType = 'Unknown';
  String? _localIp;
  String? _publicIp;
  int _latency = -1;
  
  // QR state
  String? _pairingQrData;
  String? _currentSessionId;
  int _nextSubnetIndex = 0;
  
  // Loading & error states
  bool _isLoading = false;
  String? _error;

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isOwnerMode => _isOwnerMode;
  bool get isTunnelActive => _isTunnelActive;
  String get deviceId => _deviceId;
  String get deviceName => _deviceName;
  VpnConfig? get vpnConfig => _vpnConfig;
  List<Device> get guestDevices => _guestDevices;
  ConnectionStats get stats => _stats;
  String get networkType => _networkType;
  String? get localIp => _localIp;
  String? get publicIp => _publicIp;
  int get latency => _latency;
  String? get pairingQrData => _pairingQrData;
  String? get currentSessionId => _currentSessionId;
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  List<Device> get connectedGuests => 
      _guestDevices.where((d) => d.status == DeviceStatus.connected).toList();
  List<Device> get pendingGuests =>
      _guestDevices.where((d) => d.status == DeviceStatus.pending).toList();

  /// Initialize the app
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _storage = await StorageService.getInstance();
      _wireGuard = WireGuardService.getInstance();
      _signal = SignalService.getInstance();

      await _wireGuard.initialize();

      // Restore or create device identity
      _deviceId = _storage.getDeviceId() ?? '';
      if (_deviceId.isEmpty) {
        _deviceId = KeyGenerator.generateDeviceId();
        await _storage.setDeviceId(_deviceId);
      }

      // Get device name
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      _deviceName = '${androidInfo.manufacturer} ${androidInfo.model}';

      _signal.setDeviceId(_deviceId);

      // Load saved config
      _vpnConfig = _storage.getVpnConfig();
      _guestDevices = _storage.getGuestDevices();

      // Listen to VPN state changes
      _wireGuard.stateStream.listen((state) {
        _isTunnelActive = state == VpnState.connected;
        notifyListeners();
      });

      // Listen to stats updates
      _wireGuard.statsStream.listen((stats) {
        _stats = stats;
        notifyListeners();
      });

      // Listen to signal messages
      _signal.messageStream.listen(_handleSignalMessage);

      // Get network info
      _networkType = await NetworkUtils.getNetworkType();
      _localIp = await NetworkUtils.getLocalIp();

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      _error = 'Initialization failed: $e';
      notifyListeners();
    }
  }

  /// Set mode (owner or guest)
  void setOwnerMode(bool isOwner) {
    _isOwnerMode = isOwner;
    notifyListeners();
  }

  /// Start owner mode - generate keys and prepare for guests
  Future<void> startOwnerMode() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _isOwnerMode = true;

      // Generate WireGuard keys if needed
      if (_vpnConfig == null || !_vpnConfig!.isOwner) {
        _vpnConfig = await KeyGenerator.generateOwnerConfig();
        await _storage.saveVpnConfig(_vpnConfig!, isOwner: true);
      }

      // Get public IP for endpoint (optional, don't block on failure)
      try {
        _publicIp = await NetworkUtils.getPublicIp();
      } catch (e) {
        _publicIp = null;
      }

      // Try connecting to relay server (optional, don't block on failure)
      try {
        await _signal.connect(AppConstants.defaultRelayHost).timeout(
          const Duration(seconds: 3),
        );
      } catch (e) {
        // Relay connection is optional, continue without it
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to start owner mode: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Generate QR code for guest pairing
  Future<void> generatePairingQr() async {
    _isLoading = true;
    notifyListeners();

    try {
      _currentSessionId = await _signal.createPairingSession(
        publicKey: _vpnConfig!.publicKey,
        endpoint: _publicIp ?? _localIp ?? '',
        port: AppConstants.wgDefaultPort,
      );

      _pairingQrData = QrService.generatePairingQrData(
        ownerPublicKey: _vpnConfig!.publicKey,
        ownerEndpoint: _publicIp ?? _localIp ?? '',
        port: AppConstants.wgDefaultPort,
        sessionId: _currentSessionId!,
        relayEndpoint: _signal.isConnected ? AppConstants.defaultRelayHost : null,
      );

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to generate QR: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Process guest response (scan guest QR or receive via signal)
  Future<void> processGuestResponse(String qrData) async {
    final response = QrService.parseGuestResponseQrData(qrData);
    if (response == null) {
      _error = 'Invalid guest response QR code';
      notifyListeners();
      return;
    }

    // Assign tunnel IP
    _nextSubnetIndex++;
    final tunnelIp = KeyGenerator.assignGuestTunnelIp(_nextSubnetIndex);

    // Create guest device
    final guest = Device(
      id: KeyGenerator.generateDeviceId(),
      name: response.guestName,
      publicKey: response.guestPublicKey,
      tunnelIp: tunnelIp,
      createdAt: DateTime.now(),
      status: DeviceStatus.connected,
      assignedSubnet: _nextSubnetIndex,
    );

    _guestDevices.add(guest);
    await _storage.addGuestDevice(guest);
    notifyListeners();

    // If tunnel is active, restart with updated peers
    if (_isTunnelActive) {
      await _restartTunnelWithPeers();
    }
  }

  /// Start guest mode - process scanned QR code
  Future<bool> processOwnerQr(String qrData) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final pairingData = QrService.parseOwnerQrData(qrData);
      if (pairingData == null) {
        _error = 'Invalid QR code';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      _isOwnerMode = false;

      // Generate guest config
      _vpnConfig = await KeyGenerator.generateGuestConfig(
        ownerPublicKey: pairingData.ownerPublicKey,
        ownerEndpoint: pairingData.ownerEndpoint,
        relayEndpoint: pairingData.relayEndpoint,
      );
      await _storage.saveVpnConfig(_vpnConfig!, isOwner: false);

      _currentSessionId = pairingData.sessionId;

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to process QR code: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Start the VPN tunnel
  Future<bool> startTunnel() async {
    if (_vpnConfig == null) {
      _error = 'No VPN configuration found';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final success = await _wireGuard.startTunnel(_vpnConfig!);
      _isTunnelActive = success;
      _isLoading = false;
      notifyListeners();
      return success;
    } catch (e) {
      _error = 'Failed to start tunnel: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Stop the VPN tunnel
  Future<void> stopTunnel() async {
    await _wireGuard.stopTunnel();
    _isTunnelActive = false;
    notifyListeners();
  }

  /// Restart tunnel with all current peers (owner only)
  Future<void> _restartTunnelWithPeers() async {
    if (!_isOwnerMode || _vpnConfig == null) return;

    await _wireGuard.stopTunnel();
    // The tunnel will be restarted with all guest peers included
    await _wireGuard.startTunnel(_vpnConfig!);
  }

  /// Revoke a guest device
  Future<void> revokeGuest(String guestId) async {
    await _storage.revokeGuestDevice(guestId);
    _guestDevices = _storage.getGuestDevices();
    
    if (_isTunnelActive) {
      await _restartTunnelWithPeers();
    }
    notifyListeners();
  }

  /// Remove a guest device completely
  Future<void> removeGuest(String guestId) async {
    await _storage.removeGuestDevice(guestId);
    _guestDevices = _storage.getGuestDevices();
    notifyListeners();
  }

  /// Handle incoming signal messages
  void _handleSignalMessage(SignalMessage message) {
    switch (message.type) {
      case SignalMessageType.keyExchange:
        // A guest is trying to connect
        final guestKey = message.payload['guest_public_key'] as String?;
        final guestEndpoint = message.payload['guest_endpoint'] as String?;
        final guestDeviceId = message.payload['device_id'] as String?;
        
        if (guestKey != null && _isOwnerMode) {
          _handleGuestConnection(guestKey, guestEndpoint ?? '', guestDeviceId ?? '');
        }
        break;
        
      case SignalMessageType.approveGuest:
        // Owner approved our connection
        if (!_isOwnerMode) {
          // Update config with assigned IP
          final tunnelIp = message.payload['tunnel_ip'] as String?;
          if (tunnelIp != null && _vpnConfig != null) {
            _vpnConfig = _vpnConfig!.copyWith(tunnelAddress: tunnelIp);
            _storage.saveVpnConfig(_vpnConfig!);
          }
        }
        break;

      case SignalMessageType.revokeGuest:
        if (!_isOwnerMode) {
          stopTunnel();
        }
        break;

      default:
        break;
    }
    notifyListeners();
  }

  void _handleGuestConnection(String publicKey, String endpoint, String deviceId) async {
    _nextSubnetIndex++;
    final tunnelIp = KeyGenerator.assignGuestTunnelIp(_nextSubnetIndex);
    
    final guest = Device(
      id: deviceId.isNotEmpty ? deviceId : KeyGenerator.generateDeviceId(),
      name: 'Guest ${_guestDevices.length + 1}',
      publicKey: publicKey,
      tunnelIp: tunnelIp,
      createdAt: DateTime.now(),
      status: DeviceStatus.connected,
      assignedSubnet: _nextSubnetIndex,
    );

    _guestDevices.add(guest);
    await _storage.addGuestDevice(guest);

    // Send approval
    if (_currentSessionId != null) {
      await _signal.approveGuest(
        sessionId: _currentSessionId!,
        guestId: guest.id,
        tunnelIp: tunnelIp,
      );
    }

    notifyListeners();
  }

  /// Refresh network info
  Future<void> refreshNetworkInfo() async {
    _networkType = await NetworkUtils.getNetworkType();
    _localIp = await NetworkUtils.getLocalIp();
    _latency = await NetworkUtils.measureLatency();
    notifyListeners();
  }

  /// Reset stats counters
  void resetStats() {
    _wireGuard.updateBytes(0, 0);
    notifyListeners();
  }

  @override
  void dispose() {
    _wireGuard.dispose();
    _signal.dispose();
    super.dispose();
  }
}
