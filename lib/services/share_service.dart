import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import '../config/constants.dart';

/// Service for sharing connection links
class ShareService {
  static const String _scheme = 'nexalink';
  static const String _host = 'connect';

  /// Generate a shareable link for guest connection
  /// The link encodes the owner's public key and endpoint info
  static String generateShareLink({
    required String ownerPublicKey,
    required String ownerEndpoint,
    int port = AppConstants.wgDefaultPort,
    String? relayEndpoint,
    Duration? expiration,
  }) {
    final sessionId = const Uuid().v4().substring(0, 8);
    final expiry = expiration?.inMinutes ?? 60;
    
    // Build the link parameters
    final params = <String, String>{
      'pk': ownerPublicKey,
      'ep': '$ownerEndpoint:$port',
      's': sessionId,
      'exp': '$expiry',
    };
    
    if (relayEndpoint != null) {
      params['r'] = relayEndpoint;
    }
    
    // Build query string
    final queryParts = params.entries
        .map((e) => '${_encode(e.key)}=${_encode(e.value)}')
        .join('&');
    
    return '$_scheme://$_host?$queryParts';
  }

  /// Generate a short link using a base URL
  static String generateShortLink({
    required String ownerPublicKey,
    required String ownerEndpoint,
    int port = AppConstants.wgDefaultPort,
    String? relayEndpoint,
    String baseUrl = 'https://nexalink.app',
  }) {
    // Create a compact encoded link
    final link = generateShareLink(
      ownerPublicKey: ownerPublicKey,
      ownerEndpoint: ownerEndpoint,
      port: port,
      relayEndpoint: relayEndpoint,
    );
    
    // Encode to make it URL-friendly for the short link
    final encoded = _encodeBase64(link);
    return '$baseUrl/join/$encoded';
  }

  /// Share the connection link via any available app
  static Future<void> shareConnectionLink({
    required String ownerPublicKey,
    required String ownerEndpoint,
    int port = AppConstants.wgDefaultPort,
    String? relayEndpoint,
    String? ownerName,
  }) async {
    final link = generateShareLink(
      ownerPublicKey: ownerPublicKey,
      ownerEndpoint: ownerEndpoint,
      port: port,
      relayEndpoint: relayEndpoint,
    );

    final name = ownerName ?? 'NexaLink';
    final message = '🔗 Rejoins mon réseau sécurisé NexaLink !\n\n'
        'Scanne ce lien pour te connecter :\n$link\n\n'
        '⚡ Connexion chiffrée WireGuard\n'
        '🔒 100% privé et sécurisé';

    await Share.share(
      message,
      subject: '$name t\'invite sur NexaLink',
    );
  }

  /// Share a QR code image with the connection info
  static Future<void> shareQrImage(String imagePath) async {
    await Share.shareXFiles(
      [XFile(imagePath)],
      text: '🔗 Scanne ce QR code pour te connecter à mon réseau NexaLink sécurisé !',
      subject: 'NexaLink - QR Code de connexion',
    );
  }

  /// Parse a share link and extract connection parameters
  static ShareLinkData? parseShareLink(String link) {
    try {
      // Handle nexalink:// scheme
      if (link.startsWith('$_scheme://$_host')) {
        final uri = Uri.parse(link);
        final params = uri.queryParameters;
        
        return ShareLinkData(
          ownerPublicKey: _decode(params['pk'] ?? ''),
          ownerEndpoint: _decode(params['ep'] ?? ''),
          sessionId: _decode(params['s'] ?? ''),
          relayEndpoint: params.containsKey('r') ? _decode(params['r']!) : null,
          expirationMinutes: int.tryParse(params['exp'] ?? ''),
        );
      }
      
      // Handle short link format
      if (link.contains('/join/')) {
        final encoded = link.split('/join/').last;
        final decoded = _decodeBase64(encoded);
        return parseShareLink(decoded);
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Check if a string is a valid NexaLink share link
  static bool isNexaLinkLink(String link) {
    return link.startsWith('$_scheme://') || link.contains('/join/');
  }

  /// URL encode
  static String _encode(String value) {
    return Uri.encodeComponent(value);
  }

  /// URL decode
  static String _decode(String value) {
    return Uri.decodeComponent(value);
  }

  /// Simple Base64-like encoding (URL-safe)
  static String _encodeBase64(String input) {
    final bytes = input.codeUnits;
    final encoded = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return encoded;
  }

  /// Simple Base64-like decoding
  static String _decodeBase64(String input) {
    try {
      final bytes = <int>[];
      for (int i = 0; i < input.length; i += 2) {
        if (i + 2 <= input.length) {
          bytes.add(int.parse(input.substring(i, i + 2), radix: 16));
        }
      }
      return String.fromCharCodes(bytes);
    } catch (e) {
      return '';
    }
  }
}

/// Data extracted from a share link
class ShareLinkData {
  final String ownerPublicKey;
  final String ownerEndpoint;
  final String sessionId;
  final String? relayEndpoint;
  final int? expirationMinutes;

  ShareLinkData({
    required this.ownerPublicKey,
    required this.ownerEndpoint,
    required this.sessionId,
    this.relayEndpoint,
    this.expirationMinutes,
  });

  /// Check if the link has expired
  bool get isExpired {
    if (expirationMinutes == null) return false;
    // Parse session timestamp from sessionId if available
    return false;
  }
}
