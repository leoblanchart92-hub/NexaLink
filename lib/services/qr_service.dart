import 'dart:convert';
import '../config/constants.dart';

/// Service for generating and parsing QR codes for device pairing
class QrService {
  /// Generate a QR code data payload for owner -> guest pairing
  /// Contains the owner's public key, endpoint info, and session token
  static String generatePairingQrData({
    required String ownerPublicKey,
    required String ownerEndpoint,
    required int port,
    required String sessionId,
    String? relayEndpoint,
  }) {
    final data = {
      'v': 1, // Version
      'type': 'nexalink_pair',
      'session': sessionId,
      'owner': {
        'pk': ownerPublicKey,
        'ep': ownerEndpoint,
        'pt': port,
      },
      'relay': relayEndpoint,
      'ts': DateTime.now().toIso8601String(),
      'exp': DateTime.now()
          .add(const Duration(minutes: AppConstants.maxQrCodeValidityMinutes))
          .toIso8601String(),
    };
    return jsonEncode(data);
  }

  /// Parse a scanned QR code from owner
  static QrPairingData? parseOwnerQrData(String rawData) {
    try {
      final data = jsonDecode(rawData) as Map<String, dynamic>;
      
      // Validate
      if (data['type'] != 'nexalink_pair') return null;
      if (data['v'] != 1) return null;
      
      // Check expiration
      final expStr = data['exp'] as String?;
      if (expStr != null) {
        final exp = DateTime.parse(expStr);
        if (DateTime.now().isAfter(exp)) return null; // Expired
      }

      final owner = data['owner'] as Map<String, dynamic>;
      
      return QrPairingData(
        version: data['v'] as int,
        sessionId: data['session'] as String,
        ownerPublicKey: owner['pk'] as String,
        ownerEndpoint: owner['ep'] as String,
        ownerPort: owner['pt'] as int,
        relayEndpoint: data['relay'] as String?,
      );
    } catch (e) {
      return null;
    }
  }

  /// Generate QR data for guest -> owner response (contains guest public key)
  static String generateGuestResponseQrData({
    required String sessionId,
    required String guestPublicKey,
    required String guestName,
  }) {
    final data = {
      'v': 1,
      'type': 'nexalink_response',
      'session': sessionId,
      'guest': {
        'pk': guestPublicKey,
        'name': guestName,
      },
      'ts': DateTime.now().toIso8601String(),
    };
    return jsonEncode(data);
  }

  /// Parse guest response QR data (owner scans this)
  static GuestResponseData? parseGuestResponseQrData(String rawData) {
    try {
      final data = jsonDecode(rawData) as Map<String, dynamic>;
      if (data['type'] != 'nexalink_response') return null;

      final guest = data['guest'] as Map<String, dynamic>;
      
      return GuestResponseData(
        sessionId: data['session'] as String,
        guestPublicKey: guest['pk'] as String,
        guestName: guest['name'] as String,
      );
    } catch (e) {
      return null;
    }
  }
}

/// Data extracted from the owner's pairing QR code
class QrPairingData {
  final int version;
  final String sessionId;
  final String ownerPublicKey;
  final String ownerEndpoint;
  final int ownerPort;
  final String? relayEndpoint;

  QrPairingData({
    required this.version,
    required this.sessionId,
    required this.ownerPublicKey,
    required this.ownerEndpoint,
    required this.ownerPort,
    this.relayEndpoint,
  });
}

/// Data extracted from the guest's response QR code
class GuestResponseData {
  final String sessionId;
  final String guestPublicKey;
  final String guestName;

  GuestResponseData({
    required this.sessionId,
    required this.guestPublicKey,
    required this.guestName,
  });
}
