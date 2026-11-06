import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../services/dev_mode_service.dart';
import '../../services/app_provider.dart';

/// Developer mode screen with logs, stats, and diagnostics
class DevModeScreen extends StatefulWidget {
  const DevModeScreen({super.key});

  @override
  State<DevModeScreen> createState() => _DevModeScreenState();
}

class _DevModeScreenState extends State<DevModeScreen> {
  late DevModeService _devService;
  bool _isTesting = false;
  LogLevel? _filterLevel;
  String? _filterCategory;

  @override
  void initState() {
    super.initState();
    _devService = DevModeService.getInstance();
    _devService.addListener(_onUpdate);
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _devService.removeListener(_onUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? NexaLinkTheme.darkBackground : NexaLinkTheme.lightBackground,
      appBar: AppBar(
        title: const Text('Mode Développeur'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: Icon(_devService.isRecording ? Icons.fiber_manual_record : Icons.circle_outlined),
            color: _devService.isRecording ? NexaLinkTheme.error : NexaLinkTheme.textMuted,
            onPressed: () {
              if (_devService.isRecording) {
                _devService.stopRecording();
              } else {
                _devService.startRecording();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _devService.clearLogs(),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'export') {
                final logs = _devService.exportLogs();
                await Clipboard.setData(ClipboardData(text: logs));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Logs copiés dans le presse-papier')),
                  );
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'export', child: Text('Exporter les logs')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats bar
          _buildStatsBar(isDark),
          
          // Filters
          _buildFilters(isDark),
          
          // Connectivity test button
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: NexaLinkTheme.electricBlue,
                  elevation: 0,
                ),
                onPressed: _isTesting ? null : _runConnectivityTest,
                icon: _isTesting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.wifi_find, color: Colors.white),
                label: Text(
                  _isTesting ? 'Test en cours...' : 'Tester la connectivité',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),

          // Logs list
          Expanded(
            child: _buildLogsList(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: NexaLinkTheme.primaryGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('Connexions', _devService.totalConnections.toString(), Icons.link),
          _buildStatItem('Déconnexions', _devService.totalDisconnections.toString(), Icons.link_off),
          _buildStatItem('Erreurs', _devService.totalErrors.toString(), Icons.error_outline),
          _buildStatItem('Uptime', _formatDuration(_devService.uptime), Icons.timer),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildFilters(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Level filter
          Expanded(
            child: DropdownButton<LogLevel?>(
              value: _filterLevel,
              isExpanded: true,
              hint: const Text('Niveau', style: TextStyle(fontSize: 12)),
              items: [
                const DropdownMenuItem(value: null, child: Text('Tous', style: TextStyle(fontSize: 12))),
                ...LogLevel.values.map((level) => DropdownMenuItem(
                  value: level,
                  child: Text(level.name, style: TextStyle(fontSize: 12)),
                )),
              ],
              onChanged: (value) {
                setState(() => _filterLevel = value);
              },
            ),
          ),
          const SizedBox(width: 8),
          // Category filter
          Expanded(
            child: DropdownButton<String?>(
              value: _filterCategory,
              isExpanded: true,
              hint: const Text('Catégorie', style: TextStyle(fontSize: 12)),
              items: [
                const DropdownMenuItem(value: null, child: Text('Toutes', style: TextStyle(fontSize: 12))),
                ...{'General', 'VPN', 'Error', 'Network'}.map((cat) => DropdownMenuItem(
                  value: cat,
                  child: Text(cat, style: TextStyle(fontSize: 12)),
                )),
              ],
              onChanged: (value) {
                setState(() => _filterCategory = value);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsList(bool isDark) {
    var filteredLogs = _devService.logs;

    if (_filterLevel != null) {
      filteredLogs = filteredLogs.where((log) => log.level == _filterLevel).toList();
    }

    if (_filterCategory != null) {
      filteredLogs = filteredLogs.where((log) => log.category == _filterCategory).toList();
    }

    if (filteredLogs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.article_outlined,
              size: 64,
              color: isDark ? NexaLinkTheme.textMuted : NexaLinkTheme.lightTextMuted,
            ),
            const SizedBox(height: 16),
            Text(
              'Aucun log disponible',
              style: TextStyle(
                color: isDark ? NexaLinkTheme.textSecondary : NexaLinkTheme.lightTextSecondary,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(16),
      itemCount: filteredLogs.length,
      itemBuilder: (context, index) {
        final log = filteredLogs[filteredLogs.length - 1 - index];
        return _buildLogTile(log, isDark);
      },
    );
  }

  Widget _buildLogTile(LogEntry log, bool isDark) {
    Color levelColor;
    IconData levelIcon;

    switch (log.level) {
      case LogLevel.debug:
        levelColor = Colors.grey;
        levelIcon = Icons.bug_report;
        break;
      case LogLevel.info:
        levelColor = NexaLinkTheme.electricBlue;
        levelIcon = Icons.info_outline;
        break;
      case LogLevel.warning:
        levelColor = NexaLinkTheme.warning;
        levelIcon = Icons.warning_amber;
        break;
      case LogLevel.error:
        levelColor = NexaLinkTheme.error;
        levelIcon = Icons.error;
        break;
      case LogLevel.success:
        levelColor = NexaLinkTheme.success;
        levelIcon = Icons.check_circle;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? NexaLinkTheme.surfaceCard : NexaLinkTheme.lightSurfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: levelColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(levelIcon, color: levelColor, size: 16),
              const SizedBox(width: 8),
              Text(
                log.level.name.toUpperCase(),
                style: TextStyle(
                  color: levelColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                _formatTime(log.timestamp),
                style: TextStyle(
                  color: isDark ? NexaLinkTheme.textMuted : NexaLinkTheme.lightTextMuted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            log.message,
            style: TextStyle(
              color: isDark ? NexaLinkTheme.textPrimary : NexaLinkTheme.lightTextPrimary,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            log.category,
            style: TextStyle(
              color: isDark ? NexaLinkTheme.textMuted : NexaLinkTheme.lightTextMuted,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runConnectivityTest() async {
    setState(() => _isTesting = true);
    
    final test = await _devService.runConnectivityTest();
    
    setState(() => _isTesting = false);

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(
                test.success ? Icons.check_circle : Icons.error,
                color: test.success ? NexaLinkTheme.success : NexaLinkTheme.error,
              ),
              const SizedBox(width: 8),
              Text(test.success ? 'Connexion OK' : 'Problème détecté'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTestResult('DNS', test.dnsResolved, test.dnsLatencyMs),
              _buildTestResult('TCP', test.tcpConnected, test.tcpLatencyMs),
              _buildTestResult('HTTP', test.httpStatus == 200, test.httpLatencyMs),
              const Divider(),
              Text('Latence totale: ${test.totalLatencyMs}ms'),
              if (test.error != null) ...[
                const SizedBox(height: 8),
                Text('Erreur: ${test.error}', style: const TextStyle(color: NexaLinkTheme.error)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildTestResult(String label, bool success, int? latency) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            success ? Icons.check_circle : Icons.cancel,
            color: success ? NexaLinkTheme.success : NexaLinkTheme.error,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(label),
          const Spacer(),
          if (latency != null) Text('${latency}ms'),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours}h${duration.inMinutes.remainder(60)}m';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m';
    } else {
      return '${duration.inSeconds}s';
    }
  }
}
