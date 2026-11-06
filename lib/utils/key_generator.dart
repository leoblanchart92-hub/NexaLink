import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';
import '../models/vpn_config.dart';
import '../config/constants.dart';

/// Handles WireGuard key generation and cryptographic operations
class KeyGenerator {
  static final _uuid = const Uuid();

  /// Generate a unique device ID
  static String generateDeviceId() {
    return _uuid.v4();
  }

  /// Generate a WireGuard private key (Curve25519)
  /// Returns base64-encoded 32-byte key
  static Future<String> generatePrivateKey() async {
    final algorithm = X25519();
    final keyPair = await algorithm.newKeyPair();
    final privateKey = await keyPair.extractPrivateKeyBytes();
    return base64.encode(privateKey);
  }

  /// Derive public key from private key
  static Future<String> derivePublicKey(String privateKeyBase64) async {
    final algorithm = X25519();
    final privateKeyBytes = base64.decode(privateKeyBase64);
    final keyPair = await algorithm.newKeyPairFromSeed(privateKeyBytes);
    final publicKey = await keyPair.extractPublicKey();
    return base64.encode(publicKey.bytes);
  }

  /// Generate a pre-shared key for extra security
  static Future<String> generatePreSharedKey() async {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64.encode(bytes);
  }

  /// Generate a complete WireGuard configuration for owner
  static Future<VpnConfig> generateOwnerConfig() async {
    final privateKey = await generatePrivateKey();
    final publicKey = await derivePublicKey(privateKey);
    final psk = await generatePreSharedKey();

    return VpnConfig(
      privateKey: privateKey,
      publicKey: publicKey,
      preSharedKey: psk,
      tunnelAddress: '${AppConstants.ownerTunnelIp}/32',
      listenPort: AppConstants.wgDefaultPort,
      dns: AppConstants.wgDefaultDns,
      allowedIps: '${AppConstants.wgTunnelAddress}',
      isOwner: true,
    );
  }

  /// Generate a WireGuard configuration for guest
  static Future<VpnConfig> generateGuestConfig({
    required String ownerPublicKey,
    required String? ownerEndpoint,
    required String? relayEndpoint,
  }) async {
    final privateKey = await generatePrivateKey();
    final publicKey = await derivePublicKey(privateKey);

    return VpnConfig(
      privateKey: privateKey,
      publicKey: publicKey,
      tunnelAddress: '', // Assigned by owner
      listenPort: 0, // Guest uses random port
      dns: AppConstants.wgDefaultDns,
      endpoint: ownerEndpoint ?? relayEndpoint,
      allowedIps: AppConstants.wgAllowedIPs,
      persistentKeepalive: AppConstants.wgKeepAliveInterval,
      peerPublicKey: ownerPublicKey,
      isOwner: false,
      relayEndpoint: relayEndpoint,
    );
  }

  /// Assign a tunnel IP to a guest device
  static String assignGuestTunnelIp(int subnetIndex) {
    return '${AppConstants.guestTunnelSubnet}${subnetIndex + 2}/32';
  }

  /// Generate a random port for the WireGuard listener
  static int generateRandomPort() {
    final random = Random.secure();
    return 1024 + random.nextInt(64511); // 1024-65534
  }
}
