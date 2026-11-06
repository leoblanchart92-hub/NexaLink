import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/device.dart';
import '../../services/app_provider.dart';
import '../../services/data_limit_service.dart';

/// Screen to manage guest devices - view, revoke, remove, set data limits
class ManageGuestsScreen extends StatefulWidget {
  const ManageGuestsScreen({super.key});

  @override
  State<ManageGuestsScreen> createState() => _ManageGuestsScreenState();
}

class _ManageGuestsScreenState extends State<ManageGuestsScreen> {
  late DataLimitService _dataLimitService;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    _dataLimitService = await DataLimitService.getInstance();
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final guests = app.guestDevices;

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: NexaLinkTheme.darkBackground,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: NexaLinkTheme.darkBackground,
      appBar: AppBar(
        title: const Text('Appareils Gérés'),
        backgroundColor: NexaLinkTheme.darkBackground,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),

              // Summary bar
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: NexaLinkTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(NexaLinkTheme.radiusLg),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildSummaryItem(
                      icon: Icons.devices,
                      label: 'Total',
                      value: '${guests.length}',
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: Colors.white.withOpacity(0.3),
                    ),
                    _buildSummaryItem(
                      icon: Icons.check_circle,
                      label: 'Connectés',
                      value: '${app.connectedGuests.length}',
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: Colors.white.withOpacity(0.3),
                    ),
                    _buildSummaryItem(
                      icon: Icons.bar_chart,
                      label: 'Total données',
                      value: _formatBytes(_dataLimitService.getTotalDataUsed()),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Section: Connected
              if (app.connectedGuests.isNotEmpty) ...[
                _buildSectionHeader('Connectés', NexaLinkTheme.success),
                const SizedBox(height: 8),
                ...app.connectedGuests.map((device) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildGuestCard(context, app, device),
                    )),
                const SizedBox(height: 16),
              ],

              // All devices list
              _buildSectionHeader('Historique', NexaLinkTheme.textSecondary),
              const SizedBox(height: 8),
              
              if (guests.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.people_outline_rounded,
                          color: NexaLinkTheme.textMuted,
                          size: 64,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Aucun appareil enregistré',
                          style: TextStyle(
                            color: NexaLinkTheme.textSecondary,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Les appareils invités apparaîtront ici\naprès association',
                          style: TextStyle(
                            color: NexaLinkTheme.textMuted,
                            fontSize: 13,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    itemCount: guests.length,
                    itemBuilder: (context, index) {
                      final device = guests[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildGuestCard(context, app, device),
                      );
                    },
                  ),
                ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGuestCard(BuildContext context, AppProvider app, Device device) {
    final dataUsed = _dataLimitService.getDataUsed(device.id);
    final dataLimit = _dataLimitService.getDataLimit(device.id);
    final hasLimit = dataLimit != null && dataLimit > 0;
    final usagePercent = hasLimit ? (dataUsed / dataLimit).clamp(0.0, 1.0) : 0.0;
    final isExceeded = hasLimit && dataUsed >= dataLimit;

    return Container(
      decoration: BoxDecoration(
        color: NexaLinkTheme.surfaceCard,
        borderRadius: BorderRadius.circular(NexaLinkTheme.radiusLg),
        border: isExceeded
            ? Border.all(color: NexaLinkTheme.error.withOpacity(0.5), width: 1)
            : null,
      ),
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: device.status == DeviceStatus.connected
                  ? NexaLinkTheme.success.withOpacity(0.2)
                  : NexaLinkTheme.surfaceElevated,
              child: Icon(
                Icons.phone_android,
                color: device.status == DeviceStatus.connected
                    ? NexaLinkTheme.success
                    : NexaLinkTheme.textMuted,
                size: 20,
              ),
            ),
            title: Text(
              device.name,
              style: const TextStyle(
                color: NexaLinkTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.status == DeviceStatus.connected
                      ? 'Connecté'
                      : device.status == DeviceStatus.revoked
                          ? 'Révoqué'
                          : 'Déconnecté',
                  style: TextStyle(
                    color: device.status == DeviceStatus.connected
                        ? NexaLinkTheme.success
                        : NexaLinkTheme.textMuted,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.download_rounded,
                      size: 12,
                      color: NexaLinkTheme.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatBytes(dataUsed),
                      style: TextStyle(
                        color: NexaLinkTheme.textMuted,
                        fontSize: 11,
                      ),
                    ),
                    if (hasLimit) ...[
                      Text(
                        ' / ',
                        style: TextStyle(
                          color: NexaLinkTheme.textMuted,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        _formatBytes(dataLimit),
                        style: TextStyle(
                          color: NexaLinkTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            trailing: PopupMenuButton<String>(
              color: NexaLinkTheme.surfaceElevated,
              icon: const Icon(Icons.more_vert, color: NexaLinkTheme.textMuted),
              onSelected: (value) {
                switch (value) {
                  case 'limit':
                    _showDataLimitDialog(context, device);
                    break;
                  case 'reset':
                    _resetDataUsage(context, device);
                    break;
                  case 'revoke':
                    if (device.status != DeviceStatus.revoked) {
                      _confirmRevoke(context, app, device);
                    }
                    break;
                  case 'remove':
                    _confirmRemove(context, app, device);
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'limit',
                  child: Row(
                    children: [
                      Icon(Icons.data_usage, size: 18, color: NexaLinkTheme.electricBlue),
                      const SizedBox(width: 8),
                      const Text('Définir limite', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'reset',
                  child: Row(
                    children: [
                      Icon(Icons.refresh, size: 18, color: NexaLinkTheme.warning),
                      const SizedBox(width: 8),
                      const Text('Réinitialiser données', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
                if (device.status != DeviceStatus.revoked)
                  PopupMenuItem(
                    value: 'revoke',
                    child: Row(
                      children: [
                        Icon(Icons.block, size: 18, color: NexaLinkTheme.warning),
                        const SizedBox(width: 8),
                        const Text('Révoquer', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                PopupMenuItem(
                  value: 'remove',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 18, color: NexaLinkTheme.error),
                      const SizedBox(width: 8),
                      const Text('Supprimer', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Data usage progress bar
          if (hasLimit)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: usagePercent,
                      backgroundColor: NexaLinkTheme.surfaceElevated,
                      valueColor: AlwaysStoppedAnimation(
                        usagePercent >= 0.9
                            ? NexaLinkTheme.error
                            : usagePercent >= 0.75
                                ? NexaLinkTheme.warning
                                : NexaLinkTheme.success,
                      ),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (isExceeded)
                        Row(
                          children: [
                            Icon(
                              Icons.warning_rounded,
                              size: 12,
                              color: NexaLinkTheme.error,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Limite atteinte',
                              style: TextStyle(
                                color: NexaLinkTheme.error,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        )
                      else
                        Text(
                          '${(usagePercent * 100).toStringAsFixed(0)}% utilisé',
                          style: TextStyle(
                            color: NexaLinkTheme.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      Text(
                        hasLimit
                            ? '${_formatBytes((dataLimit - dataUsed).clamp(0, dataLimit))} restant'
                            : '',
                        style: TextStyle(
                          color: NexaLinkTheme.textMuted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showDataLimitDialog(BuildContext context, Device device) {
    final currentLimit = _dataLimitService.getDataLimit(device.id);
    int? selectedLimit = currentLimit;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: NexaLinkTheme.surfaceCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NexaLinkTheme.radiusLg),
          ),
          title: Row(
            children: [
              Icon(Icons.data_usage, color: NexaLinkTheme.electricBlue),
              const SizedBox(width: 8),
              const Text('Limite de données'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Définissez une limite de données pour "${device.name}". L\'accès sera bloqué lorsque la limite sera atteinte.',
                style: TextStyle(
                  color: NexaLinkTheme.textMuted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              ...DataLimitOption.all.map((option) => RadioListTile<int>(
                    value: option.bytes,
                    groupValue: selectedLimit ?? 0,
                    activeColor: NexaLinkTheme.electricBlue,
                    title: Text(
                      option.label,
                      style: const TextStyle(
                        color: NexaLinkTheme.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: option.bytes > 0
                        ? Text(
                            DataLimitOption.formatBytes(option.bytes),
                            style: TextStyle(
                              color: NexaLinkTheme.textMuted,
                              fontSize: 11,
                            ),
                          )
                        : null,
                    onChanged: (value) {
                      setDialogState(() => selectedLimit = value == 0 ? null : value);
                    },
                    contentPadding: EdgeInsets.zero,
                  )),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: NexaLinkTheme.electricBlue,
              ),
              onPressed: () async {
                await _dataLimitService.setDataLimit(device.id, selectedLimit);
                
                // Set reset date if period is defined
                if (selectedLimit != null) {
                  final resetDate = _dataLimitService.calculateNextResetDate(DataLimitPeriod.monthly);
                  await _dataLimitService.setDataLimitResetDate(device.id, resetDate);
                }
                
                Navigator.pop(context);
                setState(() {});
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        selectedLimit != null
                            ? 'Limite de ${DataLimitOption.formatBytes(selectedLimit!)} définie pour ${device.name}'
                            : 'Limite de données supprimée pour ${device.name}',
                      ),
                      backgroundColor: NexaLinkTheme.surfaceElevated,
                    ),
                  );
                }
              },
              child: const Text('Appliquer'),
            ),
          ],
        ),
      ),
    );
  }

  void _resetDataUsage(BuildContext context, Device device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NexaLinkTheme.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NexaLinkTheme.radiusLg),
        ),
        title: Row(
          children: [
            Icon(Icons.refresh, color: NexaLinkTheme.warning),
            const SizedBox(width: 8),
            const Text('Réinitialiser les données'),
          ],
        ),
        content: Text(
          'Réinitialiser le compteur de données de "${device.name}" à 0 ?',
          style: const TextStyle(color: NexaLinkTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: NexaLinkTheme.warning,
            ),
            onPressed: () async {
              await _dataLimitService.setDataUsed(device.id, 0);
              Navigator.pop(context);
              setState(() {});
            },
            child: const Text('Réinitialiser'),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 22),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  void _confirmRevoke(BuildContext context, AppProvider app, Device device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NexaLinkTheme.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NexaLinkTheme.radiusLg),
        ),
        title: Row(
          children: [
            Icon(Icons.block_rounded, color: NexaLinkTheme.warning),
            const SizedBox(width: 8),
            const Text('Révoquer l\'accès'),
          ],
        ),
        content: Text(
          'Voulez-vous révoquer l\'accès de "${device.name}" ? Cet appareil ne pourra plus se connecter.',
          style: const TextStyle(color: NexaLinkTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: NexaLinkTheme.warning,
            ),
            onPressed: () {
              app.revokeGuest(device.id);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Accès de ${device.name} révoqué'),
                  backgroundColor: NexaLinkTheme.surfaceElevated,
                ),
              );
            },
            child: const Text('Révoquer'),
          ),
        ],
      ),
    );
  }

  void _confirmRemove(BuildContext context, AppProvider app, Device device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NexaLinkTheme.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NexaLinkTheme.radiusLg),
        ),
        title: Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: NexaLinkTheme.error),
            const SizedBox(width: 8),
            const Text('Supprimer l\'appareil'),
          ],
        ),
        content: Text(
          'Supprimer définitivement "${device.name}" de la liste ?',
          style: const TextStyle(color: NexaLinkTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: NexaLinkTheme.error,
            ),
            onPressed: () {
              app.removeGuest(device.id);
              Navigator.pop(context);
            },
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
