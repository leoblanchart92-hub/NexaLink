import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/notification_preferences_service.dart';

/// Screen to customize notification preferences
class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() => _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState extends State<NotificationPreferencesScreen> {
  late NotificationPreferencesService _prefs;
  bool _isLoading = true;

  // Local state
  bool _notifyGuestConnected = true;
  bool _notifyGuestDisconnected = true;
  bool _notifyDataLimitWarning = true;
  bool _notifyDataLimitReached = true;
  bool _notifyVpnStatus = false;
  bool _notifyVpnErrors = true;
  bool _notifyConnectionIssues = true;
  bool _silentHoursEnabled = false;
  int _silentHoursStart = 22;
  int _silentHoursEnd = 8;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    _prefs = await NotificationPreferencesService.getInstance();
    setState(() {
      _notifyGuestConnected = _prefs.notifyGuestConnected;
      _notifyGuestDisconnected = _prefs.notifyGuestDisconnected;
      _notifyDataLimitWarning = _prefs.notifyDataLimitWarning;
      _notifyDataLimitReached = _prefs.notifyDataLimitReached;
      _notifyVpnStatus = _prefs.notifyVpnStatus;
      _notifyVpnErrors = _prefs.notifyVpnErrors;
      _notifyConnectionIssues = _prefs.notifyConnectionIssues;
      _silentHoursEnabled = _prefs.silentHoursEnabled;
      _silentHoursStart = _prefs.silentHoursStart;
      _silentHoursEnd = _prefs.silentHoursEnd;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: NexaLinkTheme.darkBackground,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? NexaLinkTheme.darkBackground : NexaLinkTheme.lightBackground,
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: Colors.transparent,
        actions: [
          TextButton(
            onPressed: _resetToDefaults,
            child: const Text('Réinitialiser'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Guest notifications
          _buildSection(
            'Invités',
            'Notifications liées aux connexions invités',
            [
              _buildSwitch(
                icon: Icons.person_add,
                title: 'Invité connecté',
                subtitle: 'Quand un invité se connecte',
                value: _notifyGuestConnected,
                onChanged: (value) async {
                  setState(() => _notifyGuestConnected = value);
                  await _prefs.setNotifyGuestConnected(value);
                },
              ),
              _buildSwitch(
                icon: Icons.person_remove,
                title: 'Invité déconnecté',
                subtitle: 'Quand un invité se déconnecte',
                value: _notifyGuestDisconnected,
                onChanged: (value) async {
                  setState(() => _notifyGuestDisconnected = value);
                  await _prefs.setNotifyGuestDisconnected(value);
                },
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Data limit notifications
          _buildSection(
            'Limites de données',
            'Alertes de consommation',
            [
              _buildSwitch(
                icon: Icons.warning_amber,
                title: 'Alerte limite proche',
                subtitle: 'À 75% de la limite',
                value: _notifyDataLimitWarning,
                onChanged: (value) async {
                  setState(() => _notifyDataLimitWarning = value);
                  await _prefs.setNotifyDataLimitWarning(value);
                },
              ),
              _buildSwitch(
                icon: Icons.block,
                title: 'Limite atteinte',
                subtitle: 'Quand la limite est atteinte',
                value: _notifyDataLimitReached,
                onChanged: (value) async {
                  setState(() => _notifyDataLimitReached = value);
                  await _prefs.setNotifyDataLimitReached(value);
                },
              ),
            ],
          ),

          const SizedBox(height: 24),

          // VPN notifications
          _buildSection(
            'VPN',
            'Statut et erreurs du tunnel VPN',
            [
              _buildSwitch(
                icon: Icons.shield,
                title: 'Statut VPN',
                subtitle: 'Notification persistante quand le VPN est actif',
                value: _notifyVpnStatus,
                onChanged: (value) async {
                  setState(() => _notifyVpnStatus = value);
                  await _prefs.setNotifyVpnStatus(value);
                },
              ),
              _buildSwitch(
                icon: Icons.error_outline,
                title: 'Erreurs VPN',
                subtitle: 'En cas de problème de connexion',
                value: _notifyVpnErrors,
                onChanged: (value) async {
                  setState(() => _notifyVpnErrors = value);
                  await _prefs.setNotifyVpnErrors(value);
                },
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Connection quality
          _buildSection(
            'Qualité de connexion',
            'Alertes de problèmes réseau',
            [
              _buildSwitch(
                icon: Icons.signal_wifi_bad,
                title: 'Problèmes de connexion',
                subtitle: 'Quand la connexion est instable',
                value: _notifyConnectionIssues,
                onChanged: (value) async {
                  setState(() => _notifyConnectionIssues = value);
                  await _prefs.setNotifyConnectionIssues(value);
                },
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Silent hours
          _buildSection(
            'Heures silencieuses',
            'Désactiver les notifications pendant une période',
            [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Activer les heures silencieuses',
                  style: TextStyle(fontSize: 14),
                ),
                value: _silentHoursEnabled,
                onChanged: (value) async {
                  setState(() => _silentHoursEnabled = value);
                  await _prefs.setSilentHoursEnabled(value);
                },
                activeColor: NexaLinkTheme.electricBlue,
              ),
              if (_silentHoursEnabled) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildTimePicker(
                        label: 'Début',
                        hour: _silentHoursStart,
                        onChanged: (hour) async {
                          setState(() => _silentHoursStart = hour);
                          await _prefs.setSilentHoursStart(hour);
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTimePicker(
                        label: 'Fin',
                        hour: _silentHoursEnd,
                        onChanged: (hour) async {
                          setState(() => _silentHoursEnd = hour);
                          await _prefs.setSilentHoursEnd(hour);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSection(String title, String subtitle, List<Widget> children) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? NexaLinkTheme.surfaceCard : NexaLinkTheme.lightSurfaceCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: isDark ? NexaLinkTheme.textPrimary : NexaLinkTheme.lightTextPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: isDark ? NexaLinkTheme.textMuted : NexaLinkTheme.lightTextMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSwitch({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: Icon(icon, color: NexaLinkTheme.electricBlue, size: 22),
      title: Text(
        title,
        style: TextStyle(
          color: isDark ? NexaLinkTheme.textPrimary : NexaLinkTheme.lightTextPrimary,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: isDark ? NexaLinkTheme.textMuted : NexaLinkTheme.lightTextMuted,
          fontSize: 12,
        ),
      ),
      value: value,
      onChanged: onChanged,
      activeColor: NexaLinkTheme.electricBlue,
    );
  }

  Widget _buildTimePicker({
    required String label,
    required int hour,
    required ValueChanged<int> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return GestureDetector(
      onTap: () async {
        final time = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: hour, minute: 0),
        );
        if (time != null) {
          onChanged(time.hour);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? NexaLinkTheme.surfaceElevated : NexaLinkTheme.lightSurfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: NexaLinkTheme.electricBlue.withOpacity(0.3),
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: isDark ? NexaLinkTheme.textMuted : NexaLinkTheme.lightTextMuted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${hour.toString().padLeft(2, '0')}:00',
              style: TextStyle(
                color: isDark ? NexaLinkTheme.textPrimary : NexaLinkTheme.lightTextPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _resetToDefaults() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Réinitialiser'),
        content: const Text('Réinitialiser toutes les préférences de notifications ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () async {
              await _prefs.resetToDefaults();
              await _loadPreferences();
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Réinitialiser'),
          ),
        ],
      ),
    );
  }
}
