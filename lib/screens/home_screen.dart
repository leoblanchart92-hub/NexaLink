import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/routes.dart';
import '../services/app_provider.dart';

/// Home screen - mode selection (Owner or Guest)
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: NexaLinkTheme.darkBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 8),
              
              // Top action bar
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _buildIconButton(
                    icon: Icons.bar_chart_rounded,
                    tooltip: 'Statistiques',
                    onTap: () => Navigator.pushNamed(context, AppRoutes.statistics),
                  ),
                  const SizedBox(width: 8),
                  _buildIconButton(
                    icon: Icons.settings_rounded,
                    tooltip: 'Paramètres',
                    onTap: () => Navigator.pushNamed(context, AppRoutes.settings),
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // Header
              _buildHeader(),
              
              const SizedBox(height: 48),

              // Mode selection cards
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Owner mode card
                    _buildModeCard(
                      context: context,
                      icon: Icons.router_rounded,
                      title: 'Mode Propriétaire',
                      description: 'Partagez votre connexion Internet avec des appareils distants via un tunnel VPN sécurisé',
                      gradient: NexaLinkTheme.primaryGradient,
                      onTap: () => _selectMode(context, true),
                    ),
                    
                    const SizedBox(height: 24),

                    // Guest mode card
                    _buildModeCard(
                      context: context,
                      icon: Icons.wifi_find_rounded,
                      title: 'Mode Invité',
                      description: 'Connectez-vous à un réseau partagé et accédez à Internet en toute sécurité',
                      gradient: const LinearGradient(
                        colors: [NexaLinkTheme.neonViolet, NexaLinkTheme.cyan],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      onTap: () => _selectMode(context, false),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Footer info
              _buildFooter(app),
              
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: NexaLinkTheme.primaryGradient,
            boxShadow: NexaLinkTheme.glowShadow,
          ),
          child: const Icon(
            Icons.shield_outlined,
            size: 40,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'NexaLink',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: NexaLinkTheme.textPrimary,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Connexion Internet Sécurisée à Distance',
          style: TextStyle(
            fontSize: 14,
            color: NexaLinkTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildModeCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String description,
    required LinearGradient gradient,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(NexaLinkTheme.radiusLg),
          boxShadow: [
            BoxShadow(
              color: gradient.colors.first.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(NexaLinkTheme.radiusMd),
              ),
              child: Icon(icon, size: 28, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.8),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              color: Colors.white,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(AppProvider app) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.circle,
          size: 8,
          color: app.isInitialized ? NexaLinkTheme.success : NexaLinkTheme.warning,
        ),
        const SizedBox(width: 8),
        Text(
          app.isInitialized ? 'Système prêt' : 'Initialisation...',
          style: TextStyle(
            color: NexaLinkTheme.textMuted,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  void _selectMode(BuildContext context, bool isOwner) {
    final app = context.read<AppProvider>();
    app.setOwnerMode(isOwner);
    
    if (isOwner) {
      Navigator.pushNamed(context, AppRoutes.ownerDashboard);
    } else {
      Navigator.pushNamed(context, AppRoutes.scanQr);
    }
  }

  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: NexaLinkTheme.surfaceCard,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: NexaLinkTheme.textSecondary,
            size: 20,
          ),
        ),
      ),
    );
  }
}
