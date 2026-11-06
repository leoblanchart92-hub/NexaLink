import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/theme.dart';
import '../../services/update_service.dart';

/// Dialog to show when an update is available
class UpdateDialog extends StatelessWidget {
  final UpdateInfo updateInfo;
  final VoidCallback? onSkip;

  const UpdateDialog({
    super.key,
    required this.updateInfo,
    this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: isDark ? NexaLinkTheme.surfaceCard : NexaLinkTheme.lightSurface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with gradient
            Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              decoration: BoxDecoration(
                gradient: updateInfo.isCritical
                    ? const LinearGradient(
                        colors: [NexaLinkTheme.error, NexaLinkTheme.warning],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : NexaLinkTheme.primaryGradient,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          updateInfo.isCritical
                              ? Icons.warning_amber_rounded
                              : Icons.system_update_alt_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              updateInfo.isCritical
                                  ? 'Mise à jour importante'
                                  : 'Nouvelle version disponible',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'v${updateInfo.currentVersion} → v${updateInfo.latestVersion}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Release info
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Release name
                  Text(
                    updateInfo.releaseName,
                    style: TextStyle(
                      color: isDark
                          ? NexaLinkTheme.textPrimary
                          : NexaLinkTheme.lightTextPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  
                  const SizedBox(height: 4),
                  
                  // Published date and size
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 12,
                        color: isDark
                            ? NexaLinkTheme.textMuted
                            : NexaLinkTheme.lightTextMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        updateInfo.formattedDate,
                        style: TextStyle(
                          color: isDark
                              ? NexaLinkTheme.textMuted
                              : NexaLinkTheme.lightTextMuted,
                          fontSize: 11,
                        ),
                      ),
                      if (updateInfo.downloadSize != null) ...[
                        const SizedBox(width: 12),
                        Icon(
                          Icons.download,
                          size: 12,
                          color: isDark
                              ? NexaLinkTheme.textMuted
                              : NexaLinkTheme.lightTextMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          UpdateService.getInstance().then(
                            (s) => s.formatDownloadSize(updateInfo.downloadSize!),
                          ).toString(),
                          style: TextStyle(
                            color: isDark
                                ? NexaLinkTheme.textMuted
                                : NexaLinkTheme.lightTextMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Release notes
                  if (updateInfo.cleanReleaseNotes.isNotEmpty) ...[
                    Container(
                      constraints: const BoxConstraints(maxHeight: 150),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? NexaLinkTheme.surfaceElevated
                            : NexaLinkTheme.lightSurfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          updateInfo.cleanReleaseNotes,
                          style: TextStyle(
                            color: isDark
                                ? NexaLinkTheme.textSecondary
                                : NexaLinkTheme.lightTextSecondary,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Action buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                children: [
                  // Update button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: updateInfo.isCritical
                            ? NexaLinkTheme.error
                            : NexaLinkTheme.electricBlue,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => _downloadUpdate(context),
                      icon: const Icon(Icons.download_rounded, color: Colors.white),
                      label: Text(
                        updateInfo.isCritical
                            ? 'Mettre à jour maintenant'
                            : 'Télécharger la mise à jour',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 10),

                  // Skip button (only if not critical)
                  if (!updateInfo.isCritical)
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: TextButton(
                        onPressed: () {
                          if (onSkip != null) onSkip!();
                          Navigator.pop(context);
                        },
                        child: Text(
                          'Plus tard',
                          style: TextStyle(
                            color: isDark
                                ? NexaLinkTheme.textMuted
                                : NexaLinkTheme.lightTextMuted,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadUpdate(BuildContext context) async {
    if (updateInfo.downloadUrl == null) return;
    
    final uri = Uri.parse(updateInfo.downloadUrl!);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    
    if (context.mounted) {
      Navigator.pop(context);
    }
  }
}

/// Simple update notification bar (for non-blocking notification)
class UpdateNotificationBar extends StatelessWidget {
  final UpdateInfo updateInfo;
  final VoidCallback onUpdate;
  final VoidCallback onDismiss;

  const UpdateNotificationBar({
    super.key,
    required this.updateInfo,
    required this.onUpdate,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: NexaLinkTheme.primaryGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: NexaLinkTheme.electricBlue.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.system_update_alt_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mise à jour v${updateInfo.latestVersion}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Touchez pour télécharger',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onUpdate,
            icon: const Icon(Icons.download_rounded, color: Colors.white, size: 22),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onDismiss,
            icon: Icon(Icons.close, color: Colors.white.withOpacity(0.7), size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}
