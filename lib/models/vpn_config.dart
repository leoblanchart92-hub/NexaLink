/// WireGuard VPN configuration
class VpnConfig {
  final String privateKey;
  final String publicKey;
  final String? preSharedKey;
  final String tunnelAddress;
  final int listenPort;
  final String dns;
  final String? endpoint;
  final String allowedIps;
  final int persistentKeepalive;
  final String? peerPublicKey;
  final bool isOwner;
  final String? relayEndpoint;

  VpnConfig({
    required this.privateKey,
    required this.publicKey,
    this.preSharedKey,
    required this.tunnelAddress,
    this.listenPort = 51820,
    this.dns = '1.1.1.1',
    this.endpoint,
    this.allowedIps = '0.0.0.0/0',
    this.persistentKeepalive = 25,
    this.peerPublicKey,
    this.isOwner = false,
    this.relayEndpoint,
  });

  /// Generate WireGuard configuration string
  String toWgConfig({String? peerEndpoint, String? peerPubKey}) {
    final buffer = StringBuffer();
    buffer.writeln('[Interface]');
    buffer.writeln('PrivateKey = $privateKey');
    buffer.writeln('Address = $tunnelAddress');
    buffer.writeln('DNS = $dns');
    buffer.writeln('ListenPort = $listenPort');
    buffer.writeln('');
    buffer.writeln('[Peer]');
    buffer.writeln('PublicKey = ${peerPubKey ?? peerPublicKey ?? ''}');
    if (peerEndpoint != null || endpoint != null) {
      buffer.writeln('Endpoint = ${peerEndpoint ?? endpoint ?? ''}');
    }
    buffer.writeln('AllowedIPs = $allowedIps');
    buffer.writeln('PersistentKeepalive = $persistentKeepalive');
    if (preSharedKey != null) {
      buffer.writeln('PresharedKey = $preSharedKey');
    }
    return buffer.toString();
  }

  VpnConfig copyWith({
    String? privateKey,
    String? publicKey,
    String? preSharedKey,
    String? tunnelAddress,
    int? listenPort,
    String? dns,
    String? endpoint,
    String? allowedIps,
    int? persistentKeepalive,
    String? peerPublicKey,
    bool? isOwner,
    String? relayEndpoint,
  }) {
    return VpnConfig(
      privateKey: privateKey ?? this.privateKey,
      publicKey: publicKey ?? this.publicKey,
      preSharedKey: preSharedKey ?? this.preSharedKey,
      tunnelAddress: tunnelAddress ?? this.tunnelAddress,
      listenPort: listenPort ?? this.listenPort,
      dns: dns ?? this.dns,
      endpoint: endpoint ?? this.endpoint,
      allowedIps: allowedIps ?? this.allowedIps,
      persistentKeepalive: persistentKeepalive ?? this.persistentKeepalive,
      peerPublicKey: peerPublicKey ?? this.peerPublicKey,
      isOwner: isOwner ?? this.isOwner,
      relayEndpoint: relayEndpoint ?? this.relayEndpoint,
    );
  }

  Map<String, dynamic> toJson() => {
        'privateKey': privateKey,
        'publicKey': publicKey,
        'tunnelAddress': tunnelAddress,
        'listenPort': listenPort,
        'dns': dns,
        'endpoint': endpoint,
        'allowedIps': allowedIps,
        'persistentKeepalive': persistentKeepalive,
        'peerPublicKey': peerPublicKey,
        'isOwner': isOwner,
        'relayEndpoint': relayEndpoint,
      };

  factory VpnConfig.fromJson(Map<String, dynamic> json) => VpnConfig(
        privateKey: json['privateKey'] as String,
        publicKey: json['publicKey'] as String,
        tunnelAddress: json['tunnelAddress'] as String,
        listenPort: json['listenPort'] as int? ?? 51820,
        dns: json['dns'] as String? ?? '1.1.1.1',
        endpoint: json['endpoint'] as String?,
        allowedIps: json['allowedIps'] as String? ?? '0.0.0.0/0',
        persistentKeepalive: json['persistentKeepalive'] as int? ?? 25,
        peerPublicKey: json['peerPublicKey'] as String?,
        isOwner: json['isOwner'] as bool? ?? false,
        relayEndpoint: json['relayEndpoint'] as String?,
      );
}
