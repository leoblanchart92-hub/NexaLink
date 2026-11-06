import 'package:flutter/material.dart';

import '../config/theme.dart';

/// Card showing current connection status
class ConnectionStatusCard extends StatelessWidget {
  final bool isConnected;
  final String networkType;
  final int latency;
  final String? localIp;
  final String? tunnelIp;

  const ConnectionStatusCard({
    super.key,
    required this.isConnected,
    required this.networkType,
    this.latency = -1,
    this.localIp,
    this.tunnelIp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexaLinkTheme.surfaceCard,
        borderRadius: BorderRadius.circular(NexaLinkTheme.radiusLg),
        border: Border.all(
          color: (isConnected ? NexaLinkTheme.success : NexaLinkTheme.textMuted)
              .withOpacity(0.3),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Status indicator
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isConnected ? NexaLinkTheme.success : NexaLinkTheme.textMuted,
                  boxShadow: isConnected
                      ? [
                          BoxShadow(
                            color: NexaLinkTheme.success.withOpacity(0.5),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                isConnected ? 'Tunnel Actif' : 'Tunnel Inactif',
                style: TextStyle(
                  color: isConnected ? NexaLinkTheme.success : NexaLinkTheme.textMuted,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // Signal quality
              if (isConnected && latency > 0)
                _buildSignalIndicator(latency),
            ],
          ),
          
          const SizedBox(height: 12),

          // Details row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildDetail(
                icon: Icons.wifi_rounded,
                label: networkType,
              ),
              if (localIp != null)
                _buildDetail(
                  icon: Icons.lan_rounded,
                  label: localIp!,
                ),
              if (tunnelIp != null)
                _buildDetail(
                  icon: Icons.vpn_key_rounded,
                  label: tunnelIp!,
                ),
              if (latency > 0)
                _buildDetail(
                  icon: Icons.speed_rounded,
                  label: '${latency}ms',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSignalIndicator(int latencyMs) {
    Color color;
    IconData icon;
    
    if (latencyMs <= 30) {
      color = NexaLinkTheme.success;
      icon = Icons.signal_cellular_4_bar;
    } else if (latencyMs <= 80) {
      color = NexaLinkTheme.success;
      icon = Icons.signal_cellular_alt;
    } else if (latencyMs <= 150) {
      color = NexaLinkTheme.warning;
      icon = Icons.network_wifi_3_bar;
    } else {
      color = NexaLinkTheme.error;
      icon = Icons.network_wifi_1_bar;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          Text(
            '${latencyMs}ms',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetail({required IconData icon, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: NexaLinkTheme.textMuted, size: 14),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: NexaLinkTheme.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
