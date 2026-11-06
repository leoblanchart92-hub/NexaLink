import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/device.dart';

/// Tile showing a guest device with status and actions
class GuestDeviceTile extends StatelessWidget {
  final Device device;
  final VoidCallback? onRevoke;
  final VoidCallback? onRemove;

  const GuestDeviceTile({
    super.key,
    required this.device,
    this.onRevoke,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor(device.status);
    final statusText = _getStatusText(device.status);
    final statusIcon = _getStatusIcon(device.status);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NexaLinkTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(NexaLinkTheme.radiusMd),
        border: Border.all(
          color: statusColor.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          // Device avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(NexaLinkTheme.radiusSm),
            ),
            child: Icon(
              Icons.phone_android_rounded,
              color: statusColor,
              size: 22,
            ),
          ),
          
          const SizedBox(width: 12),

          // Device info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: const TextStyle(
                    color: NexaLinkTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (device.tunnelIp != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        device.tunnelIp!,
                        style: const TextStyle(
                          color: NexaLinkTheme.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Actions
          if (onRevoke != null || onRemove != null)
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert_rounded,
                color: NexaLinkTheme.textMuted,
              ),
              color: NexaLinkTheme.surfaceElevated,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(NexaLinkTheme.radiusSm),
              ),
              onSelected: (value) {
                if (value == 'revoke') onRevoke?.call();
                if (value == 'remove') onRemove?.call();
              },
              itemBuilder: (context) => [
                if (onRevoke != null)
                  PopupMenuItem(
                    value: 'revoke',
                    child: Row(
                      children: [
                        Icon(Icons.block_rounded, color: NexaLinkTheme.warning, size: 18),
                        const SizedBox(width: 8),
                        const Text('Révoquer'),
                      ],
                    ),
                  ),
                if (onRemove != null)
                  PopupMenuItem(
                    value: 'remove',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded, color: NexaLinkTheme.error, size: 18),
                        const SizedBox(width: 8),
                        const Text('Supprimer'),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Color _getStatusColor(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.connected:
        return NexaLinkTheme.success;
      case DeviceStatus.disconnected:
        return NexaLinkTheme.textMuted;
      case DeviceStatus.pending:
        return NexaLinkTheme.warning;
      case DeviceStatus.revoked:
        return NexaLinkTheme.error;
    }
  }

  String _getStatusText(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.connected:
        return 'Connecté';
      case DeviceStatus.disconnected:
        return 'Déconnecté';
      case DeviceStatus.pending:
        return 'En attente';
      case DeviceStatus.revoked:
        return 'Révoqué';
    }
  }

  IconData _getStatusIcon(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.connected:
        return Icons.check_circle;
      case DeviceStatus.disconnected:
        return Icons.cancel_outlined;
      case DeviceStatus.pending:
        return Icons.hourglass_empty;
      case DeviceStatus.revoked:
        return Icons.block;
    }
  }
}
