/// Real-time connection statistics for the VPN tunnel
class ConnectionStats {
  final int bytesReceived;
  final int bytesSent;
  final int rxSpeed; // bytes per second
  final int txSpeed; // bytes per second
  final Duration connectionDuration;
  final int latencyMs;
  final bool isConnected;
  final DateTime? lastUpdated;

  ConnectionStats({
    this.bytesReceived = 0,
    this.bytesSent = 0,
    this.rxSpeed = 0,
    this.txSpeed = 0,
    this.connectionDuration = Duration.zero,
    this.latencyMs = 0,
    this.isConnected = false,
    this.lastUpdated,
  });

  String get formattedRx => _formatBytes(bytesReceived);
  String get formattedTx => _formatBytes(bytesSent);
  String get formattedRxSpeed => '${_formatBytes(rxSpeed)}/s';
  String get formattedTxSpeed => '${_formatBytes(txSpeed)}/s';
  String get formattedDuration {
    final hours = connectionDuration.inHours;
    final minutes = connectionDuration.inMinutes.remainder(60);
    final seconds = connectionDuration.inSeconds.remainder(60);
    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m ${seconds}s';
    return '${seconds}s';
  }

  String get signalQuality {
    if (latencyMs <= 30) return 'Excellent';
    if (latencyMs <= 80) return 'Good';
    if (latencyMs <= 150) return 'Fair';
    return 'Poor';
  }

  double get signalQualityPercent {
    if (latencyMs <= 30) return 1.0;
    if (latencyMs <= 80) return 0.75;
    if (latencyMs <= 150) return 0.5;
    return 0.25;
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  ConnectionStats copyWith({
    int? bytesReceived,
    int? bytesSent,
    int? rxSpeed,
    int? txSpeed,
    Duration? connectionDuration,
    int? latencyMs,
    bool? isConnected,
    DateTime? lastUpdated,
  }) {
    return ConnectionStats(
      bytesReceived: bytesReceived ?? this.bytesReceived,
      bytesSent: bytesSent ?? this.bytesSent,
      rxSpeed: rxSpeed ?? this.rxSpeed,
      txSpeed: txSpeed ?? this.txSpeed,
      connectionDuration: connectionDuration ?? this.connectionDuration,
      latencyMs: latencyMs ?? this.latencyMs,
      isConnected: isConnected ?? this.isConnected,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}

/// Traffic data point for chart visualization
class TrafficDataPoint {
  final DateTime time;
  final int rxBytes;
  final int txBytes;

  TrafficDataPoint({
    required this.time,
    required this.rxBytes,
    required this.txBytes,
  });
}
