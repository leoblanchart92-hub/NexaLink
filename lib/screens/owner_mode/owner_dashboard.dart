import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../services/app_provider.dart';
import '../../models/connection_stats.dart';
import '../../widgets/connection_status_card.dart';
import '../../widgets/traffic_chart.dart';
import '../../widgets/guest_device_tile.dart';
import '../../widgets/animated_button.dart';

/// Owner dashboard - main screen for the device owner
class OwnerDashboard extends StatefulWidget {
  const OwnerDashboard({super.key});

  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppProvider>().startOwnerMode();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();

    return Scaffold(
      backgroundColor: NexaLinkTheme.darkBackground,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // App bar
            SliverAppBar(
              expandedHeight: 120,
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
                        gradient: NexaLinkTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.shield_outlined, size: 18, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'NexaLink',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: NexaLinkTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        NexaLinkTheme.darkBackground,
                        NexaLinkTheme.nightBlue.withOpacity(0.5),
                      ],
                    ),
                  ),
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
                  
                  // VPN Toggle - Main action button
                  _buildVpnToggle(app),
                  
                  const SizedBox(height: 20),

                  // Connection status
                  ConnectionStatusCard(
                    isConnected: app.isTunnelActive,
                    networkType: app.networkType,
                    latency: app.latency,
                    localIp: app.localIp,
                  ),

                  const SizedBox(height: 16),

                  // Traffic stats
                  if (app.isTunnelActive) ...[
                    _buildTrafficOverview(app),
                    const SizedBox(height: 16),
                    
                    // Traffic chart
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
                            'Activité Réseau',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: NexaLinkTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const TrafficChart(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Action buttons
                  _buildActionButtons(app),
                  
                  const SizedBox(height: 16),

                  // Connected guests section
                  _buildGuestsSection(app),

                  const SizedBox(height: 80),
                ]),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, AppRoutes.generateQr),
        backgroundColor: NexaLinkTheme.electricBlue,
        icon: const Icon(Icons.qr_code_2_rounded),
        label: const Text('QR Code'),
      ),
    );
  }

  Widget _buildVpnToggle(AppProvider app) {
    return Center(
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final glowOpacity = _pulseController.value * 0.3;
          return GestureDetector(
            onTap: app.isLoading ? null : () => _toggleVpn(app),
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: app.isTunnelActive
                    ? NexaLinkTheme.successGradient
                    : NexaLinkTheme.primaryGradient,
                boxShadow: [
                  BoxShadow(
                    color: (app.isTunnelActive ? NexaLinkTheme.success : NexaLinkTheme.electricBlue)
                        .withOpacity(glowOpacity + 0.1),
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
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    )
                  else
                    Icon(
                      app.isTunnelActive
                          ? Icons.power_settings_new_rounded
                          : Icons.power_rounded,
                      size: 48,
                      color: Colors.white,
                    ),
                  const SizedBox(height: 8),
                  Text(
                    app.isTunnelActive ? 'ACTIF' : 'INACTIF',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTrafficOverview(AppProvider app) {
    final stats = app.stats;
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            icon: Icons.download_rounded,
            label: 'Reçu',
            value: stats.formattedRx,
            speed: stats.formattedRxSpeed,
            color: NexaLinkTheme.cyan,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.upload_rounded,
            label: 'Envoyé',
            value: stats.formattedTx,
            speed: stats.formattedTxSpeed,
            color: NexaLinkTheme.neonViolet,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.access_time_rounded,
            label: 'Durée',
            value: stats.formattedDuration,
            speed: '',
            color: NexaLinkTheme.success,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required String speed,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NexaLinkTheme.surfaceCard,
        borderRadius: BorderRadius.circular(NexaLinkTheme.radiusMd),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          if (speed.isNotEmpty)
            Text(
              speed,
              style: TextStyle(
                fontSize: 11,
                color: color.withOpacity(0.7),
              ),
            ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: NexaLinkTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(AppProvider app) {
    return Row(
      children: [
        Expanded(
          child: AnimatedButton(
            label: 'Générer QR',
            icon: Icons.qr_code_2_rounded,
            gradient: NexaLinkTheme.primaryGradient,
            onTap: () => Navigator.pushNamed(context, AppRoutes.generateQr),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AnimatedButton(
            label: 'Invités',
            icon: Icons.people_rounded,
            gradient: const LinearGradient(
              colors: [NexaLinkTheme.neonViolet, NexaLinkTheme.deepViolet],
            ),
            onTap: () => Navigator.pushNamed(context, AppRoutes.manageGuests),
          ),
        ),
      ],
    );
  }

  Widget _buildGuestsSection(AppProvider app) {
    final connected = app.connectedGuests;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexaLinkTheme.surfaceCard,
        borderRadius: BorderRadius.circular(NexaLinkTheme.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Appareils Connectés',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: NexaLinkTheme.textPrimary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: NexaLinkTheme.success.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${connected.length}',
                  style: const TextStyle(
                    color: NexaLinkTheme.success,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          if (connected.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Icon(
                    Icons.devices_other_rounded,
                    color: NexaLinkTheme.textMuted,
                    size: 40,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Aucun appareil connecté',
                    style: TextStyle(
                      color: NexaLinkTheme.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Générez un QR code pour inviter un appareil',
                    style: TextStyle(
                      color: NexaLinkTheme.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            )
          else
            ...connected.map((device) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GuestDeviceTile(
                    device: device,
                    onRevoke: () => app.revokeGuest(device.id),
                  ),
                )),
          
          if (app.guestDevices.isNotEmpty) ...[
            const Divider(height: 24),
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, AppRoutes.manageGuests),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Voir tous les appareils',
                    style: TextStyle(
                      color: NexaLinkTheme.electricBlue,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.arrow_forward,
                    size: 16,
                    color: NexaLinkTheme.electricBlue,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _toggleVpn(AppProvider app) async {
    try {
      if (app.isTunnelActive) {
        await app.stopTunnel();
      } else {
        final success = await app.startTunnel();
        if (!success && app.error != null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(app.error!),
                backgroundColor: NexaLinkTheme.error,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur VPN: $e'),
            backgroundColor: NexaLinkTheme.error,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}
