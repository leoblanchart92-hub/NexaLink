import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../config/constants.dart';
import '../utils/key_generator.dart';

/// Signal service for device pairing and key exchange
/// Uses a simple WebSocket relay server for real-time communication
class SignalService {
  static SignalService? _instance;
  WebSocket? _ws;
  bool _isConnected = false;
  String? _deviceId;
  String? _relayEndpoint;

  final _messageController = StreamController<SignalMessage>.broadcast();
  Stream<SignalMessage> get messageStream => _messageController.stream;

  SignalService._();

  static SignalService getInstance() {
    _instance ??= SignalService._();
    return _instance!;
  }

  bool get isConnected => _isConnected;

  /// Connect to the relay/signaling server
  Future<bool> connect(String relayHost, {int port = AppConstants.defaultRelayPort}) async {
    try {
      _relayEndpoint = '$relayHost:$port';
      final uri = Uri.parse('wss://$relayHost:$port/ws');
      
      _ws = await WebSocket.connect(
        uri.toString(),
        headers: {
          'X-Device-ID': _deviceId ?? '',
        },
      ).timeout(const Duration(seconds: 10));

      _isConnected = true;
      _listenToMessages();
      return true;
    } catch (e) {
      _isConnected = false;
      // If relay connection fails, we can still use local/direct mode
      return false;
    }
  }

  /// Set the device ID for this session
  void setDeviceId(String deviceId) {
    _deviceId = deviceId;
  }

  void _listenToMessages() {
    _ws?.listen(
      (data) {
        try {
          final json = jsonDecode(data as String) as Map<String, dynamic>;
          final message = SignalMessage.fromJson(json);
          _messageController.add(message);
        } catch (e) {
          // Invalid message format
        }
      },
      onDone: () {
        _isConnected = false;
      },
      onError: (e) {
        _isConnected = false;
      },
    );
  }

  /// Register as owner and create a pairing session
  Future<String?> createPairingSession({
    required String publicKey,
    required String endpoint,
    int port = AppConstants.wgDefaultPort,
  }) async {
    if (!_isConnected || _ws == null) {
      // Generate a local session token for offline pairing
      return _generateLocalSessionToken(publicKey, endpoint, port);
    }

    final sessionId = KeyGenerator.generateDeviceId();
    _send(SignalMessage(
      type: SignalMessageType.createSession,
      payload: {
        'session_id': sessionId,
        'owner_public_key': publicKey,
        'owner_endpoint': endpoint,
        'owner_port': port,
        'device_id': _deviceId,
        'created_at': DateTime.now().toIso8601String(),
      },
    ));

    return sessionId;
  }

  /// Join a pairing session as guest
  Future<bool> joinPairingSession({
    required String sessionId,
    required String publicKey,
  }) async {
    if (!_isConnected || _ws == null) return false;

    _send(SignalMessage(
      type: SignalMessageType.joinSession,
      payload: {
        'session_id': sessionId,
        'guest_public_key': publicKey,
        'device_id': _deviceId,
      },
    ));
    return true;
  }

  /// Send guest's public key to owner (for direct connection)
  Future<void> sendGuestKey({
    required String sessionId,
    required String guestPublicKey,
    required String guestEndpoint,
  }) async {
    _send(SignalMessage(
      type: SignalMessageType.keyExchange,
      payload: {
        'session_id': sessionId,
        'guest_public_key': guestPublicKey,
        'guest_endpoint': guestEndpoint,
        'device_id': _deviceId,
      },
    ));
  }

  /// Acknowledge pairing (owner approves guest)
  Future<void> approveGuest({
    required String sessionId,
    required String guestId,
    required String tunnelIp,
  }) async {
    _send(SignalMessage(
      type: SignalMessageType.approveGuest,
      payload: {
        'session_id': sessionId,
        'guest_id': guestId,
        'tunnel_ip': tunnelIp,
        'device_id': _deviceId,
      },
    ));
  }

  /// Revoke guest access
  Future<void> revokeGuest({
    required String sessionId,
    required String guestId,
  }) async {
    _send(SignalMessage(
      type: SignalMessageType.revokeGuest,
      payload: {
        'session_id': sessionId,
        'guest_id': guestId,
        'device_id': _deviceId,
      },
    ));
  }

  /// Generate a local session token for QR-based pairing without server
  String _generateLocalSessionToken(
      String publicKey, String endpoint, int port) {
    final data = {
      'v': 1,
      'pk': publicKey,
      'ep': endpoint,
      'pt': port,
      'id': _deviceId,
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
    return base64Url.encode(utf8.encode(jsonEncode(data)));
  }

  /// Parse a local session token from QR code
  static Map<String, dynamic>? parseSessionToken(String token) {
    try {
      final decoded = utf8.decode(base64Url.decode(token));
      return jsonDecode(decoded) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  void _send(SignalMessage message) {
    if (_ws != null && _isConnected) {
      _ws!.add(jsonEncode(message.toJson()));
    }
  }

  /// Disconnect from signaling server
  Future<void> disconnect() async {
    await _ws?.close();
    _ws = null;
    _isConnected = false;
  }

  void dispose() {
    _ws?.close();
    _messageController.close();
  }
}

/// Signal message types
enum SignalMessageType {
  createSession,
  joinSession,
  keyExchange,
  approveGuest,
  revokeGuest,
  heartbeat,
  sessionInfo,
  error,
}

/// Message exchanged via the signaling server
class SignalMessage {
  final SignalMessageType type;
  final Map<String, dynamic> payload;

  SignalMessage({required this.type, required this.payload});

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'payload': payload,
        'timestamp': DateTime.now().toIso8601String(),
      };

  factory SignalMessage.fromJson(Map<String, dynamic> json) {
    return SignalMessage(
      type: SignalMessageType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => SignalMessageType.error,
      ),
      payload: json['payload'] as Map<String, dynamic>? ?? {},
    );
  }
}
