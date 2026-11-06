import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../services/app_provider.dart';
import '../../widgets/connection_status_card.dart';
import '../../widgets/animated_button.dart';

/// Guest dashboard - shows connection status and controls for the guest device
class GuestDashboard extends StatefulWidget {
  const GuestDashboard({super.key});

  @override
  State<GuestDashboard> createState() => _GuestDashboardState();
}

class _GuestDashboardState extends State<GuestDashboard> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final stats = app.stats;
    final config = app.vpnConfig;

    return Scaffold(
      backgroundColor: NexaLinkTheme.darkBackground,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: 100,
              floating: false,
              pinned: true,
              backgroundColor: NexaLinkTheme.darkBackground,
              flexibleSpace: FlexibleSpaceBar(
                title: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [NexaLinkTheme.neonViolet, NexaLinkTheme.cyan],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.wifi_find, size: 18, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Mode Invité',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.settings_rounded),
                  onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
                ),
              ],
            ),

            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: 16),

                  // Connection toggle
                  Center(
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        final glow = _pulseController.value * 0.3;
                        return GestureDetector(
                          onTap: app.isLoading ? null : () => _toggleConnection(app),
                          child: Container(
                            width: 160,
                            height: 160,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: app.isTunnelActive
                                  ? NexaLinkTheme.successGradient
                                  : const LinearGradient(
                                      colors: [NexaLinkTheme.neonViolet, NexaLinkTheme.deepViolet],
                                    ),
                              boxShadow: [
                                BoxShadow(
                                  color: (app.isTunnelActive
                                          ? NexaLinkTheme.success
                                          : NexaLinkTheme.neonViolet)
                                      .withOpacity(glow + 0.1),
                                  blurRadius: 40,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (app.isLoading)
                                  const SizedBox(
                                    width: 36,
                                    height: 36,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 3,
                                    ),
                                  )
                                else
                                  Icon(
                                    app.isTunnelActive
                                        ? Icons.wifi_rounded
                                        : Icons.wifi_off_rounded,
                                    size: 44,
                                    color: Colors.white,
                                  ),
                                const SizedBox(height: 8),
                                Text(
                                  app.isTunnelActive ? 'CONNECTÉ' : 'DÉCONNECTÉ',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Connection status
                  ConnectionStatusCard(
                    isConnected: app.isTunnelActive,
                    networkType: app.networkType,
                    latency: app.latency,
                    tunnelIp: config?.tunnelAddress,
                  ),

                  const SizedBox(height: 16),

                  // Stats grid
                  if (app.isTunnelActive) ...[
                    Row(
                      children: [
                        Expanded(
                          child: _buildInfoCard(
                            icon: Icons.download_rounded,
                            label: 'Reçu',
                            value: stats.formattedRx,
                            subValue: stats.formattedRxSpeed,
                            color: NexaLinkTheme.cyan,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildInfoCard(
                            icon: Icons.upload_rounded,
                            label: 'Envoyé',
                            value: stats.formattedTx,
                            subValue: stats.formattedTxSpeed,
                            color: NexaLinkTheme.neonViolet,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildInfoCard(
                            icon: Icons.access_time_rounded,
                            label: 'Durée',
                            value: stats.formattedDuration,
                            subValue: '',
                            color: NexaLinkTheme.success,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildInfoCard(
                            icon: Icons.signal_cellular_alt_rounded,
                            label: 'Qualité',
                            value: stats.signalQuality,
                            subValue: '${stats.latencyMs}ms',
                            color: _getSignalColor(stats.signalQualityPercent),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Connection info
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: NexaLinkTheme.surfaceCard,
                      borderRadius: BorderRadius.circular(NexaLinkTheme.radiusLg),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Informations de Connexion',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: NexaLinkTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildInfoRow('Appareil', app.deviceName),
                        _buildInfoRow('ID', '${app.deviceId.substring(0, 8)}...'),
                        _buildInfoRow(
                          'IP Tunnel',
                          config?.tunnelAddress ?? 'Non assignée',
                        ),
                        _buildInfoRow(
                          'Protocole',
                          'WireGuard',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Disconnect button (always visible)
                  AnimatedButton(
                    label: 'Nouvelle Connexion',
                    icon: Icons.qr_code_scanner_rounded,
                    gradient: const LinearGradient(
                      colors: [NexaLinkTheme.neonViolet, NexaLinkTheme.electricBlue],
                    ),
                    onTap: () {
                      Navigator.of(context).pushNamedAndRemoveUntil(
                        AppRoutes.scanQr,
                        (route) => false,
                      );
                    },
                  ),

                  const SizedBox(height: 80),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
    required String subValue,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexaLinkTheme.surfaceCard,
        borderRadius: BorderRadius.circular(NexaLinkTheme.radiusMd),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const Spacer(),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: NexaLinkTheme.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          if (subValue.isNotEmpty)
            Text(
              subValue,
              style: TextStyle(
                fontSize: 12,
                color: color.withOpacity(0.7),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: NexaLinkTheme.textMuted,
              fontSize: 13,
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                color: NexaLinkTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Color _getSignalColor(double quality) {
    if (quality >= 0.8) return NexaLinkTheme.success;
    if (quality >= 0.5) return NexaLinkTheme.warning;
    return NexaLinkTheme.error;
  }

  Future<void> _toggleConnection(AppProvider app) async {
    if (app.isTunnelActive) {
      await app.stopTunnel();
    } else {
      final success = await app.startTunnel();
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(app.error ?? 'Connexion échouée'),
            backgroundColor: NexaLinkTheme.error,
          ),
        );
      }
    }
  }
}
