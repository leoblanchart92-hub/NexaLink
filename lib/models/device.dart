/// Represents a device (owner or guest) in the NexaLink network
class Device {
  final String id;
  final String name;
  final String publicKey;
  final String? tunnelIp;
  final DateTime createdAt;
  final DateTime? lastSeen;
  final DeviceStatus status;
  final int? assignedSubnet;
  
  // Data limit fields
  final int? dataLimitBytes; // null = unlimited
  final int dataUsedBytes;
  final DateTime? dataLimitResetDate;
  final DataLimitPeriod? dataLimitPeriod;

  Device({
    required this.id,
    required this.name,
    required this.publicKey,
    this.tunnelIp,
    required this.createdAt,
    this.lastSeen,
    this.status = DeviceStatus.pending,
    this.assignedSubnet,
    this.dataLimitBytes,
    this.dataUsedBytes = 0,
    this.dataLimitResetDate,
    this.dataLimitPeriod,
  });

  /// Whether this device has a data limit
  bool get hasDataLimit => dataLimitBytes != null && dataLimitBytes! > 0;

  /// Whether this device has exceeded its data limit
  bool get isDataLimitExceeded => hasDataLimit && dataUsedBytes >= dataLimitBytes!;

  /// Data usage percentage (0.0 to 1.0)
  double get dataUsagePercent {
    if (!hasDataLimit) return 0.0;
    return (dataUsedBytes / dataLimitBytes!).clamp(0.0, 1.0);
  }

  /// Remaining data in bytes
  int get dataRemainingBytes {
    if (!hasDataLimit) return -1; // -1 = unlimited
    return (dataLimitBytes! - dataUsedBytes).clamp(0, dataLimitBytes!);
  }

  /// Formatted data used
  String get formattedDataUsed => _formatBytes(dataUsedBytes);

  /// Formatted data limit
  String get formattedDataLimit => hasDataLimit ? _formatBytes(dataLimitBytes!) : 'Illimité';

  /// Formatted data remaining
  String get formattedDataRemaining => 
      hasDataLimit ? _formatBytes(dataRemainingBytes) : 'Illimité';

  /// Color based on data usage
  int get usageColorHex {
    if (!hasDataLimit) return 0xFF3B82F6; // blue
    if (dataUsagePercent >= 0.9) return 0xFFEF4444; // red
    if (dataUsagePercent >= 0.75) return 0xFFF59E0B; // orange
    return 0xFF10B981; // green
  }

  Device copyWith({
    String? name,
    String? publicKey,
    String? tunnelIp,
    DateTime? lastSeen,
    DeviceStatus? status,
    int? assignedSubnet,
    int? dataLimitBytes,
    bool clearDataLimit = false,
    int? dataUsedBytes,
    DateTime? dataLimitResetDate,
    DataLimitPeriod? dataLimitPeriod,
  }) {
    return Device(
      id: id,
      name: name ?? this.name,
      publicKey: publicKey ?? this.publicKey,
      tunnelIp: tunnelIp ?? this.tunnelIp,
      createdAt: createdAt,
      lastSeen: lastSeen ?? this.lastSeen,
      status: status ?? this.status,
      assignedSubnet: assignedSubnet ?? this.assignedSubnet,
      dataLimitBytes: clearDataLimit ? null : (dataLimitBytes ?? this.dataLimitBytes),
      dataUsedBytes: dataUsedBytes ?? this.dataUsedBytes,
      dataLimitResetDate: dataLimitResetDate ?? this.dataLimitResetDate,
      dataLimitPeriod: dataLimitPeriod ?? this.dataLimitPeriod,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'publicKey': publicKey,
        'tunnelIp': tunnelIp,
        'createdAt': createdAt.toIso8601String(),
        'lastSeen': lastSeen?.toIso8601String(),
        'status': status.index,
        'assignedSubnet': assignedSubnet,
        'dataLimitBytes': dataLimitBytes,
        'dataUsedBytes': dataUsedBytes,
        'dataLimitResetDate': dataLimitResetDate?.toIso8601String(),
        'dataLimitPeriod': dataLimitPeriod?.index,
      };

  factory Device.fromJson(Map<String, dynamic> json) => Device(
        id: json['id'] as String,
        name: json['name'] as String,
        publicKey: json['publicKey'] as String,
        tunnelIp: json['tunnelIp'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        lastSeen: json['lastSeen'] != null
            ? DateTime.parse(json['lastSeen'] as String)
            : null,
        status: DeviceStatus.values[json['status'] as int],
        assignedSubnet: json['assignedSubnet'] as int?,
        dataLimitBytes: json['dataLimitBytes'] as int?,
        dataUsedBytes: (json['dataUsedBytes'] as int?) ?? 0,
        dataLimitResetDate: json['dataLimitResetDate'] != null
            ? DateTime.parse(json['dataLimitResetDate'] as String)
            : null,
        dataLimitPeriod: json['dataLimitPeriod'] != null
            ? DataLimitPeriod.values[json['dataLimitPeriod'] as int]
            : null,
      );

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

enum DeviceStatus {
  pending,
  connected,
  disconnected,
  revoked,
}

/// Data limit period
enum DataLimitPeriod {
  daily,
  weekly,
  monthly,
  custom,
}

/// Predefined data limit options
class DataLimitOption {
  final String label;
  final int bytes;

  const DataLimitOption(this.label, this.bytes);

  static const unlimited = DataLimitOption('Illimité', 0);
  static const mb500 = DataLimitOption('500 Mo', 500 * 1024 * 1024);
  static const gb1 = DataLimitOption('1 Go', 1024 * 1024 * 1024);
  static const gb2 = DataLimitOption('2 Go', 2 * 1024 * 1024 * 1024);
  static const gb5 = DataLimitOption('5 Go', 5 * 1024 * 1024 * 1024);
  static const gb10 = DataLimitOption('10 Go', 10 * 1024 * 1024 * 1024);
  static const gb20 = DataLimitOption('20 Go', 20 * 1024 * 1024 * 1024);
  static const gb50 = DataLimitOption('50 Go', 50 * 1024 * 1024 * 1024);

  static const List<DataLimitOption> all = [
    unlimited,
    mb500,
    gb1,
    gb2,
    gb5,
    gb10,
    gb20,
    gb50,
  ];

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
