import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../config/theme.dart';
import '../../services/app_provider.dart';
import '../../services/share_service.dart';

/// Screen to generate and display the pairing QR code
class GenerateQrScreen extends StatefulWidget {
  const GenerateQrScreen({super.key});

  @override
  State<GenerateQrScreen> createState() => _GenerateQrScreenState();
}

class _GenerateQrScreenState extends State<GenerateQrScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppProvider>().generatePairingQr();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final qrData = app.pairingQrData;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? NexaLinkTheme.darkBackground : NexaLinkTheme.lightBackground,
      appBar: AppBar(
        title: const Text('QR Code de Connexion'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 16),

              // Instructions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: NexaLinkTheme.electricBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(NexaLinkTheme.radiusMd),
                  border: Border.all(color: NexaLinkTheme.electricBlue.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: NexaLinkTheme.electricBlue,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Montrez ce QR code à l\'appareil invité ou partagez le lien pour établir la connexion sécurisée',
                        style: TextStyle(
                          color: isDark ? NexaLinkTheme.textSecondary : NexaLinkTheme.lightTextSecondary,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // QR Code display
              if (app.isLoading)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(
                      color: NexaLinkTheme.electricBlue,
                    ),
                  ),
                )
              else if (qrData != null)
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // QR Code with animated border
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(NexaLinkTheme.radiusLg),
                              boxShadow: [
                                BoxShadow(
                                  color: NexaLinkTheme.electricBlue.withOpacity(0.2),
                                  blurRadius: 30,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: QrImageView(
                              data: qrData,
                              version: QrVersions.auto,
                              size: 220,
                              backgroundColor: Colors.white,
                              foregroundColor: NexaLinkTheme.nightBlue,
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Session info
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: isDark ? NexaLinkTheme.surfaceCard : NexaLinkTheme.lightSurfaceCard,
                              borderRadius: BorderRadius.circular(NexaLinkTheme.radiusMd),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.timer_outlined,
                                  color: NexaLinkTheme.warning,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Valide 30 minutes',
                                  style: TextStyle(
                                    color: isDark ? NexaLinkTheme.textSecondary : NexaLinkTheme.lightTextSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Share button
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: NexaLinkTheme.neonViolet,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(NexaLinkTheme.radiusMd),
                                ),
                              ),
                              onPressed: () => _shareLink(context, app),
                              icon: const Icon(Icons.share_rounded, color: Colors.white),
                              label: const Text(
                                'Partager le lien de connexion',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: NexaLinkTheme.error,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          app.error ?? 'Impossible de générer le QR code',
                          style: const TextStyle(color: NexaLinkTheme.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => app.generatePairingQr(),
                          child: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 24),

              // Copy code button
              if (qrData != null)
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: qrData));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Code copié dans le presse-papier'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copier le code'),
                ),

              const SizedBox(height: 16),

              // Scan guest response
              TextButton.icon(
                onPressed: () {
                  _showScanGuestDialog(context, app);
                },
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Scanner la réponse de l\'invité'),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _shareLink(BuildContext context, AppProvider app) {
    if (app.vpnConfig == null) return;

    final link = ShareService.generateShareLink(
      ownerPublicKey: app.vpnConfig!.publicKey,
      ownerEndpoint: app.publicIp ?? app.localIp ?? '',
      port: 51820,
      relayEndpoint: app.vpnConfig!.relayEndpoint,
      expiration: const Duration(minutes: 30),
    );

    final name = app.deviceName;

    // Build the share message
    final message = '🔗 Rejoins mon réseau sécurisé NexaLink !\n\n'
        '📱 Appareil : $name\n'
        '⚡ Connexion chiffrée WireGuard\n'
        '🔒 100% privé et sécurisé\n\n'
        'Ouvre ce lien sur ton téléphone pour te connecter :\n$link';

    // Share via system share sheet
    _showShareOptions(context, message, link);
  }

  void _showShareOptions(BuildContext context, String message, String link) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? NexaLinkTheme.surfaceCard : NexaLinkTheme.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: NexaLinkTheme.textMuted.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Partager le lien',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            
            // Share options grid
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildShareOption(
                  context: context,
                  icon: Icons.message,
                  label: 'SMS',
                  color: NexaLinkTheme.success,
                  onTap: () {
                    _shareViaIntent(context, message);
                  },
                ),
                _buildShareOption(
                  context: context,
                  icon: Icons.mail,
                  label: 'Email',
                  color: NexaLinkTheme.electricBlue,
                  onTap: () {
                    _shareViaIntent(context, message);
                  },
                ),
                _buildShareOption(
                  context: context,
                  icon: Icons.copy,
                  label: 'Copier',
                  color: NexaLinkTheme.warning,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: link));
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Lien copié !')),
                    );
                  },
                ),
                _buildShareOption(
                  context: context,
                  icon: Icons.more_horiz,
                  label: 'Plus',
                  color: NexaLinkTheme.neonViolet,
                  onTap: () {
                    _shareViaIntent(context, message);
                  },
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Link preview
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark 
                    ? NexaLinkTheme.surfaceElevated 
                    : NexaLinkTheme.lightSurfaceElevated,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link, size: 18, color: NexaLinkTheme.electricBlue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      link,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? NexaLinkTheme.textMuted : NexaLinkTheme.lightTextMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildShareOption({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).brightness == Brightness.dark
                  ? NexaLinkTheme.textSecondary
                  : NexaLinkTheme.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  void _shareViaIntent(BuildContext context, String message) {
    Navigator.pop(context);
    _performShare(message);
  }

  Future<void> _performShare(String message) async {
    try {
      await Share.share(message, subject: 'NexaLink - Invitation');
    } catch (e) {
      // Fallback to clipboard
      await Clipboard.setData(ClipboardData(text: message));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lien copié dans le presse-papier')),
        );
      }
    }
  }

  void _showScanGuestDialog(BuildContext context, AppProvider app) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? NexaLinkTheme.surfaceCard : NexaLinkTheme.lightSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NexaLinkTheme.radiusLg),
        ),
        title: const Text(
          'Ajouter un invité manuellement',
          style: TextStyle(fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: 'Nom de l\'invité',
                prefixIcon: Icon(Icons.person_outline),
              ),
              onChanged: (value) {},
            ),
            const SizedBox(height: 12),
            Text(
              'Demandez à l\'invité de scanner le QR code et de vous montrer sa réponse',
              style: TextStyle(
                color: isDark ? NexaLinkTheme.textSecondary : NexaLinkTheme.lightTextSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
  }
}
