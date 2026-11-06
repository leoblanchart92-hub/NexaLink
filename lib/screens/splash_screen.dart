import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/theme.dart';
import '../config/routes.dart';
import '../services/app_provider.dart';
import '../services/biometric_service.dart';
import '../services/update_service.dart';
import '../widgets/update_dialog.dart';
import 'package:provider/provider.dart';

/// Splash screen with animated NexaLink branding
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  bool _initializing = true;
  String _statusText = 'Initialisation...';
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
    _initialize();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    final app = context.read<AppProvider>();
    
    setState(() => _statusText = 'Chargement des configurations...');
    await app.initialize();

    setState(() => _statusText = 'Préparation du réseau...');
    await Future.delayed(const Duration(milliseconds: 400));

    setState(() => _statusText = 'Vérification du réseau...');
    await app.refreshNetworkInfo();

    setState(() => _initializing = false);

    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    // Check for updates (non-blocking)
    _checkForUpdates();

    // Check if onboarding is needed
    final prefs = await SharedPreferences.getInstance();
    final onboardingCompleted = prefs.getBool('onboarding_completed') ?? false;

    if (!onboardingCompleted) {
      Navigator.of(context).pushReplacementNamed(AppRoutes.onboarding);
      return;
    }

    // Check if PIN lock is enabled
    final biometricService = await BiometricService.getInstance();
    if (biometricService.requiresPin()) {
      Navigator.of(context).pushReplacementNamed(AppRoutes.pinLock);
      return;
    }

    // Navigate to home
    Navigator.of(context).pushReplacementNamed(AppRoutes.home);
  }

  /// Check for app updates in background
  Future<void> _checkForUpdates() async {
    try {
      final updateService = await UpdateService.getInstance();
      
      // Skip if auto-check is disabled
      if (!updateService.isAutoCheckEnabled()) return;
      
      final updateInfo = await updateService.checkForUpdate();
      if (updateInfo == null) return;
      
      // Check if update is available
      if (!updateService.isUpdateAvailable(updateInfo)) return;
      
      // Check if user skipped this version (unless critical)
      if (!updateInfo.isCritical && updateService.isVersionSkipped(updateInfo)) return;
      
      // Show update dialog after navigation completes
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!mounted) return;
          _showUpdateDialog(context, updateInfo, updateService);
        });
      }
    } catch (e) {
      // Update check failed - not critical, continue
    }
  }

  void _showUpdateDialog(
    BuildContext context,
    UpdateInfo updateInfo,
    UpdateService updateService,
  ) {
    showDialog(
      context: context,
      barrierDismissible: !updateInfo.isCritical,
      builder: (context) => UpdateDialog(
        updateInfo: updateInfo,
        onSkip: () {
          updateService.setSkipVersion(updateInfo.latestVersion);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexaLinkTheme.darkBackground,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated logo with pulse
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: NexaLinkTheme.primaryGradient,
                  boxShadow: NexaLinkTheme.glowShadow,
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  size: 60,
                  color: Colors.white,
                ),
              ),
            ),
            
            const SizedBox(height: 32),

            // App name
            const Text(
              'NexaLink',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: NexaLinkTheme.textPrimary,
                letterSpacing: 2,
              ),
            ),

            const SizedBox(height: 8),

            // Tagline
            Text(
              'Partage Internet Sécurisé',
              style: TextStyle(
                fontSize: 16,
                color: NexaLinkTheme.textSecondary,
                letterSpacing: 1,
              ),
            ),

            const SizedBox(height: 48),

            // Loading indicator
            if (_initializing) ...[
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(
                    NexaLinkTheme.electricBlue,
                  ),
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _statusText,
                style: const TextStyle(
                  color: NexaLinkTheme.textMuted,
                  fontSize: 14,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
