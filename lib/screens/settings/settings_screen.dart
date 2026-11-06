import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../config/constants.dart';
import '../../services/app_provider.dart';
import '../../services/storage_service.dart';
import '../../services/biometric_service.dart';
import '../../services/theme_provider.dart';
import '../../services/update_service.dart';
import '../../widgets/update_dialog.dart';

/// Settings screen for app configuration
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _relayController;
  bool _autoConnect = false;
  bool _consentGiven = false;
  bool _pinLockEnabled = false;
  bool _pinIsSet = false;
  bool _autoUpdateEnabled = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _relayController = TextEditingController();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final storage = await StorageService.getInstance();
    final biometricService = await BiometricService.getInstance();
    final updateService = await UpdateService.getInstance();
    setState(() {
      _relayController.text = storage.getRelayServer() ?? AppConstants.defaultRelayHost;
      _autoConnect = storage.getAutoConnect();
      _consentGiven = storage.getConsentGiven();
      _pinLockEnabled = biometricService.requiresPin();
      _pinIsSet = biometricService.isPinSet();
      _autoUpdateEnabled = updateService.isAutoCheckEnabled();
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _relayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: NexaLinkTheme.darkBackground,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: NexaLinkTheme.darkBackground,
      appBar: AppBar(
        title: const Text('Paramètres'),
        backgroundColor: NexaLinkTheme.darkBackground,
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // App info section
          _buildSection('Application'),
          _buildSettingsCard([
            _buildInfoTile(
              icon: Icons.info_outline,
              title: 'Version',
              subtitle: AppConstants.appVersion,
            ),
            _buildInfoTile(
              icon: Icons.phone_android,
              title: 'Appareil',
              subtitle: app.deviceName,
            ),
            _buildInfoTile(
              icon: Icons.fingerprint,
              title: 'ID Appareil',
              subtitle: app.deviceId,
            ),
          ]),

          const SizedBox(height: 16),

          // Appearance section
          _buildSection('Apparence'),
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, _) {
              return _buildSettingsCard([
                _buildThemeSelector(themeProvider),
              ]);
            },
          ),

          const SizedBox(height: 16),

          // Statistics shortcut
          _buildSection('Statistiques'),
          _buildSettingsCard([
            _buildActionTile(
              icon: Icons.bar_chart_rounded,
              title: 'Statistiques détaillées',
              subtitle: 'Graphiques et historique de consommation',
              onTap: () {
                Navigator.pushNamed(context, AppRoutes.statistics);
              },
            ),
          ]),

          const SizedBox(height: 16),

          // Connection section
          _buildSection('Connexion'),
          _buildSettingsCard([
            _buildSwitchTile(
              icon: Icons.flash_on_rounded,
              title: 'Connexion automatique',
              subtitle: 'Se connecter au démarrage de l\'app',
              value: _autoConnect,
              onChanged: (value) async {
                setState(() => _autoConnect = value);
                final storage = await StorageService.getInstance();
                await storage.setAutoConnect(value);
              },
            ),
            _buildSwitchTile(
              icon: Icons.system_update_alt_rounded,
              title: 'Mises à jour automatiques',
              subtitle: 'Vérifier les nouvelles versions au démarrage',
              value: _autoUpdateEnabled,
              onChanged: (value) async {
                setState(() => _autoUpdateEnabled = value);
                final updateService = await UpdateService.getInstance();
                await updateService.setAutoCheckEnabled(value);
              },
            ),
          ]),

          const SizedBox(height: 16),

          // Security section
          _buildSection('Sécurité'),
          _buildSettingsCard([
            _buildActionTile(
              icon: _pinIsSet ? Icons.lock_rounded : Icons.lock_open_rounded,
              title: _pinIsSet ? 'Changer le code PIN' : 'Activer le code PIN',
              subtitle: _pinIsSet 
                  ? 'Modifier le code de sécurité de l\'application'
                  : 'Protéger l\'accès à l\'application avec un code PIN',
              onTap: () => _setupPin(context),
            ),
            if (_pinIsSet)
              _buildSwitchTile(
                icon: Icons.shield_rounded,
                title: 'Verrouillage au démarrage',
                subtitle: 'Demander le code PIN à chaque lancement',
                value: _pinLockEnabled,
                onChanged: (value) async {
                  final biometricService = await BiometricService.getInstance();
                  await biometricService.setPinLockEnabled(value);
                  setState(() => _pinLockEnabled = value);
                },
              ),
            _buildSwitchTile(
              icon: Icons.verified_user_rounded,
              title: 'Consentement mutuel',
              subtitle: 'Les deux appareils doivent accepter la connexion',
              value: _consentGiven,
              onChanged: (value) async {
                setState(() => _consentGiven = value);
                final storage = await StorageService.getInstance();
                await storage.setConsentGiven(value);
              },
            ),
            _buildActionTile(
              icon: Icons.key_rounded,
              title: 'Régénérer les clés',
              subtitle: 'Créer de nouvelles clés WireGuard',
              onTap: () => _confirmRegenerateKeys(context, app),
              color: NexaLinkTheme.warning,
            ),
          ]),

          const SizedBox(height: 16),

          // Relay server section
          _buildSection('Serveur Relais'),
          _buildSettingsCard([
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Serveur relais (relay)',
                    style: TextStyle(
                      color: NexaLinkTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Utilisé pour la découverte des appareils et l\'échange de clés quand les deux téléphones sont derrière un NAT',
                    style: TextStyle(
                      color: NexaLinkTheme.textMuted,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _relayController,
                    decoration: const InputDecoration(
                      hintText: 'relay.nexalink.app',
                      prefixIcon: Icon(Icons.dns_rounded, size: 20),
                    ),
                    onSubmitted: (value) async {
                      final storage = await StorageService.getInstance();
                      await storage.setRelayServer(value);
                    },
                  ),
                ],
              ),
            ),
          ]),

          const SizedBox(height: 16),

          // Privacy section
          _buildSection('Confidentialité'),
          _buildSettingsCard([
            _buildInfoTile(
              icon: Icons.lock_outline,
              title: 'Chiffrement',
              subtitle: 'WireGuard (Curve25519 + ChaCha20)',
            ),
            _buildInfoTile(
              icon: Icons.visibility_off_outlined,
              title: 'Aucune surveillance',
              subtitle: 'Vos activités ne sont pas collectées',
            ),
            _buildActionTile(
              icon: Icons.delete_forever,
              title: 'Effacer toutes les données',
              subtitle: 'Supprimer toutes les configurations et l\'historique',
              onTap: () => _confirmClearData(context, app),
              color: NexaLinkTheme.error,
            ),
          ]),

          const SizedBox(height: 16),

          // About section
          _buildSection('À propos'),
          _buildSettingsCard([
            _buildInfoTile(
              icon: Icons.shield_outlined,
              title: 'NexaLink',
              subtitle: 'Partage Internet sécurisé via tunnel VPN WireGuard',
            ),
            _buildActionTile(
              icon: Icons.system_update_alt_rounded,
              title: 'Vérifier les mises à jour',
              subtitle: 'Dernière vérification : ${_getLastCheckText()}',
              onTap: () => _checkForUpdatesManual(context),
            ),
          ]),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _setupPin(BuildContext context) async {
    final result = await Navigator.pushNamed<bool>(context, AppRoutes.setPin);
    if (result == true) {
      _loadSettings();
    }
  }

  String _getLastCheckText() {
    // Could track this in UpdateService, for now just return a generic text
    return 'Aujourd\'hui';
  }

  Future<void> _checkForUpdatesManual(BuildContext context) async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: NexaLinkTheme.electricBlue),
      ),
    );

    try {
      final updateService = await UpdateService.getInstance();
      final updateInfo = await updateService.checkForUpdate(force: true);

      // Close loading dialog
      if (mounted) Navigator.pop(context);

      if (updateInfo == null) {
        if (mounted) {
          _showSnackbar(context, 'Impossible de vérifier les mises à jour', isError: true);
        }
        return;
      }

      if (!updateService.isUpdateAvailable(updateInfo)) {
        if (mounted) {
          _showSnackbar(context, 'Vous avez la dernière version (v${updateInfo.currentVersion})');
        }
        return;
      }

      // Show update dialog
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => UpdateDialog(
            updateInfo: updateInfo,
            onSkip: () {
              updateService.setSkipVersion(updateInfo.latestVersion);
            },
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading
        _showSnackbar(context, 'Erreur lors de la vérification', isError: true);
      }
    }
  }

  void _showSnackbar(BuildContext context, String message, {bool isError = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? (isDark ? NexaLinkTheme.error : NexaLinkTheme.error)
            : (isDark ? NexaLinkTheme.success : NexaLinkTheme.success),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildThemeSelector(ThemeProvider themeProvider) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.palette_outlined, color: NexaLinkTheme.electricBlue, size: 22),
              SizedBox(width: 12),
              Text(
                'Thème',
                style: TextStyle(
                  color: NexaLinkTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildThemeOption(
                icon: Icons.dark_mode,
                label: 'Sombre',
                isSelected: themeProvider.themeMode == AppThemeMode.dark,
                onTap: () => themeProvider.setThemeMode(AppThemeMode.dark),
              ),
              const SizedBox(width: 12),
              _buildThemeOption(
                icon: Icons.light_mode,
                label: 'Clair',
                isSelected: themeProvider.themeMode == AppThemeMode.light,
                onTap: () => themeProvider.setThemeMode(AppThemeMode.light),
              ),
              const SizedBox(width: 12),
              _buildThemeOption(
                icon: Icons.settings_brightness,
                label: 'Système',
                isSelected: themeProvider.themeMode == AppThemeMode.system,
                onTap: () => themeProvider.setThemeMode(AppThemeMode.system),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThemeOption({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? NexaLinkTheme.electricBlue.withOpacity(0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(NexaLinkTheme.radiusMd),
            border: Border.all(
              color: isSelected
                  ? NexaLinkTheme.electricBlue
                  : NexaLinkTheme.textMuted.withOpacity(0.2),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected
                    ? NexaLinkTheme.electricBlue
                    : NexaLinkTheme.textMuted,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? NexaLinkTheme.electricBlue
                      : NexaLinkTheme.textMuted,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: NexaLinkTheme.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildSettingsCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: NexaLinkTheme.surfaceCard,
        borderRadius: BorderRadius.circular(NexaLinkTheme.radiusLg),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return ListTile(
      leading: Icon(icon, color: NexaLinkTheme.electricBlue, size: 22),
      title: Text(
        title,
        style: const TextStyle(color: NexaLinkTheme.textPrimary, fontSize: 14),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: NexaLinkTheme.textMuted, fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: Icon(icon, color: NexaLinkTheme.electricBlue, size: 22),
      title: Text(
        title,
        style: const TextStyle(color: NexaLinkTheme.textPrimary, fontSize: 14),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: NexaLinkTheme.textMuted, fontSize: 12),
      ),
      value: value,
      onChanged: onChanged,
      activeColor: NexaLinkTheme.electricBlue,
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? color,
  }) {
    return ListTile(
      leading: Icon(icon, color: color ?? NexaLinkTheme.electricBlue, size: 22),
      title: Text(
        title,
        style: TextStyle(
          color: color ?? NexaLinkTheme.textPrimary,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: NexaLinkTheme.textMuted, fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right, color: NexaLinkTheme.textMuted),
      onTap: onTap,
    );
  }

  void _confirmRegenerateKeys(BuildContext context, AppProvider app) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NexaLinkTheme.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NexaLinkTheme.radiusLg),
        ),
        title: const Text('Régénérer les clés'),
        content: const Text(
          'Cela va créer de nouvelles clés WireGuard. Tous les appareils invités devront être réassociés. Continuer ?',
          style: TextStyle(color: NexaLinkTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: NexaLinkTheme.warning),
            onPressed: () async {
              Navigator.pop(context);
              final storage = await StorageService.getInstance();
              await storage.clearVpnConfig();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Clés régénérées. Redémarrez le mode pour appliquer.'),
                ),
              );
            },
            child: const Text('Régénérer'),
          ),
        ],
      ),
    );
  }

  void _confirmClearData(BuildContext context, AppProvider app) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NexaLinkTheme.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NexaLinkTheme.radiusLg),
        ),
        title: Row(
          children: [
            Icon(Icons.warning_rounded, color: NexaLinkTheme.error),
            const SizedBox(width: 8),
            const Text('Effacer les données'),
          ],
        ),
        content: const Text(
          'Toutes les configurations, clés et historique seront supprimés. Cette action est irréversible.',
          style: TextStyle(color: NexaLinkTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: NexaLinkTheme.error),
            onPressed: () async {
              Navigator.pop(context);
              final storage = await StorageService.getInstance();
              final biometric = await BiometricService.getInstance();
              await storage.clearAll();
              await biometric.clearAll();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Toutes les données ont été effacées'),
                  ),
                );
              }
            },
            child: const Text('Tout effacer'),
          ),
        ],
      ),
    );
  }
}
