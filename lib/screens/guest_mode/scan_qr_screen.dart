import 'package:flutter/material.dart';

import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../services/app_provider.dart';

/// Screen for guest to scan the owner's QR code
class ScanQrScreen extends StatefulWidget {
  const ScanQrScreen({super.key});

  @override
  State<ScanQrScreen> createState() => _ScanQrScreenState();
}

class _ScanQrScreenState extends State<ScanQrScreen> {
  final MobileScannerController _cameraController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  bool _isProcessing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startScanner();
  }

  Future<void> _startScanner() async {
    try {
      await _cameraController.start();
    } catch (e) {
      setState(() => _error = 'Impossible d\'accéder à la caméra');
    }
  }

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexaLinkTheme.darkBackground,
      appBar: AppBar(
        title: const Text('Scanner QR Code'),
        backgroundColor: NexaLinkTheme.darkBackground,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),

            // Instructions
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: NexaLinkTheme.neonViolet.withOpacity(0.1),
                borderRadius: BorderRadius.circular(NexaLinkTheme.radiusMd),
                border: Border.all(color: NexaLinkTheme.neonViolet.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.qr_code_scanner,
                    color: NexaLinkTheme.neonViolet,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Placez le QR code de l\'appareil propriétaire dans le cadre',
                      style: TextStyle(
                        color: NexaLinkTheme.textSecondary,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Camera view with overlay
            Expanded(
              child: _error != null
                  ? _buildErrorState()
                  : _buildScannerView(),
            ),

            // Bottom actions
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Manual entry
                  OutlinedButton.icon(
                    onPressed: () => _showManualEntryDialog(context),
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Saisie manuelle'),
                  ),
                  // Toggle flash
                  OutlinedButton.icon(
                    onPressed: () {
                      _cameraController.toggleTorch();
                    },
                    icon: const Icon(Icons.flash_on_rounded),
                    label: const Text('Flash'),
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

  Widget _buildScannerView() {
    return Stack(
      children: [
        // Camera preview
        MobileScanner(
          controller: _cameraController,
          onDetect: (capture) {
            if (_isProcessing) return;
            final barcodes = capture.barcodes;
            if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
              _processQrCode(barcodes.first.rawValue!);
            }
          },
        ),

        // Scanning overlay
        Center(
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              border: Border.all(
                color: NexaLinkTheme.electricBlue.withOpacity(0.5),
                width: 2,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),

        // Processing overlay
        if (_isProcessing)
          Container(
            color: Colors.black.withOpacity(0.7),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(
                    color: NexaLinkTheme.electricBlue,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Configuration de la connexion...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.camera_alt_outlined,
            color: NexaLinkTheme.textMuted,
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            _error ?? 'Erreur inconnue',
            style: const TextStyle(color: NexaLinkTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _startScanner,
            child: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }

  Future<void> _processQrCode(String data) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    final app = context.read<AppProvider>();
    final success = await app.processOwnerQr(data);

    setState(() => _isProcessing = false);

    if (success && mounted) {
      // Navigate to guest dashboard
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.guestDashboard,
        (route) => false,
      );
    } else if (mounted) {
      // Show error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(app.error ?? 'QR code invalide'),
          backgroundColor: NexaLinkTheme.error,
        ),
      );
    }
  }

  void _showManualEntryDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NexaLinkTheme.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NexaLinkTheme.radiusLg),
        ),
        title: const Text('Saisie manuelle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Collez le code de connexion fourni par le propriétaire',
              style: TextStyle(
                color: NexaLinkTheme.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Code de connexion...',
                border: OutlineInputBorder(),
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
              if (controller.text.isNotEmpty) {
                _processQrCode(controller.text.trim());
              }
            },
            child: const Text('Connecter'),
          ),
        ],
      ),
    );
  }
}
