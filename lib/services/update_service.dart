import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/constants.dart';

/// Service to check for app updates via GitHub Releases
class UpdateService {
  static UpdateService? _instance;
  late SharedPreferences _prefs;
  
  static const String _githubApiUrl = 
      'https://api.github.com/repos/leoblanchart92-hub/NexaLink/releases/latest';
  static const String _prefsKeyLastCheck = 'last_update_check';
  static const String _prefsKeySkipVersion = 'skip_update_version';
  static const String _prefsKeyAutoCheck = 'auto_check_updates';
  
  // Check at most once per day
  static const int _checkIntervalHours = 24;

  UpdateService._();

  static Future<UpdateService> getInstance() async {
    _instance ??= UpdateService._();
    await _instance!._init();
    return _instance!;
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Check if auto-update check is enabled
  bool isAutoCheckEnabled() => _prefs.getBool(_prefsKeyAutoCheck) ?? true;

  /// Enable/disable auto-update check
  Future<void> setAutoCheckEnabled(bool enabled) async {
    await _prefs.setBool(_prefsKeyAutoCheck, enabled);
  }

  /// Get the version to skip
  String? getSkipVersion() => _prefs.getString(_prefsKeySkipVersion);

  /// Set version to skip
  Future<void> setSkipVersion(String version) async {
    await _prefs.setString(_prefsKeySkipVersion, version);
  }

  /// Clear skip version
  Future<void> clearSkipVersion() async {
    await _prefs.remove(_prefsKeySkipVersion);
  }

  /// Check if enough time has passed since last check
  bool shouldCheckNow() {
    final lastCheck = _prefs.getInt(_prefsKeyLastCheck);
    if (lastCheck == null) return true;
    
    final lastCheckDate = DateTime.fromMillisecondsSinceEpoch(lastCheck);
    final hoursSinceLastCheck = DateTime.now().difference(lastCheckDate).inHours;
    return hoursSinceLastCheck >= _checkIntervalHours;
  }

  /// Force check for updates (ignores interval)
  Future<UpdateInfo?> checkForUpdate({bool force = false}) async {
    if (!force && !shouldCheckNow()) return null;
    
    try {
      final response = await http.get(
        Uri.parse(_githubApiUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode != 200) {
        debugPrint('Update check failed: ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      
      // Parse version from tag name (e.g., "v1.2.0" -> "1.2.0")
      final tagName = data['tag_name'] as String? ?? '';
      final latestVersion = tagName.startsWith('v') ? tagName.substring(1) : tagName;
      
      // Parse release info
      final releaseName = data['name'] as String? ?? 'NexaLink $latestVersion';
      final releaseNotes = data['body'] as String? ?? '';
      final publishedAt = data['published_at'] as String?;
      final isPrerelease = data['prerelease'] as bool? ?? false;
      
      // Find APK asset
      final assets = data['assets'] as List<dynamic>? ?? [];
      String? downloadUrl;
      int? downloadSize;
      
      for (final asset in assets) {
        final assetMap = asset as Map<String, dynamic>;
        final name = assetMap['name'] as String? ?? '';
        if (name.endsWith('.apk')) {
          downloadUrl = assetMap['browser_download_url'] as String?;
          downloadSize = assetMap['size'] as int?;
          break;
        }
      }

      // If no APK found, use the HTML URL as fallback
      downloadUrl ??= data['html_url'] as String?;

      // Check if this is a critical update (contains [critical] in notes)
      final isCritical = releaseNotes.toLowerCase().contains('[critical]') ||
          releaseNotes.toLowerCase().contains('[important]');

      final updateInfo = UpdateInfo(
        latestVersion: latestVersion,
        currentVersion: AppConstants.appVersion,
        releaseName: releaseName,
        releaseNotes: releaseNotes,
        downloadUrl: downloadUrl,
        downloadSize: downloadSize,
        publishedAt: publishedAt != null ? DateTime.tryParse(publishedAt) : null,
        isPrerelease: isPrerelease,
        isCritical: isCritical,
      );

      // Save check timestamp
      await _prefs.setInt(_prefsKeyLastCheck, DateTime.now().millisecondsSinceEpoch);

      return updateInfo;
    } catch (e) {
      debugPrint('Update check error: $e');
      return null;
    }
  }

  /// Check if an update is available (comparing versions)
  bool isUpdateAvailable(UpdateInfo info) {
    final current = _parseVersion(info.currentVersion);
    final latest = _parseVersion(info.latestVersion);
    
    if (latest == null || current == null) return false;
    
    // Compare major.minor.patch
    for (int i = 0; i < 3; i++) {
      if (latest[i] > current[i]) return true;
      if (latest[i] < current[i]) return false;
    }
    return false;
  }

  /// Check if user chose to skip this version
  bool isVersionSkipped(UpdateInfo info) {
    final skipVersion = getSkipVersion();
    return skipVersion == info.latestVersion;
  }

  /// Parse version string into comparable list [major, minor, patch]
  List<int>? _parseVersion(String version) {
    try {
      final parts = version.split('.');
      if (parts.length < 2) return null;
      
      return [
        int.tryParse(parts[0]) ?? 0,
        int.tryParse(parts[1]) ?? 0,
        parts.length > 2 ? (int.tryParse(parts[2]) ?? 0) : 0,
      ];
    } catch (e) {
      return null;
    }
  }

  /// Open the download URL in browser
  Future<bool> openDownloadUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  /// Get formatted download size
  String formatDownloadSize(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Update information data class
class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String releaseName;
  final String releaseNotes;
  final String? downloadUrl;
  final int? downloadSize;
  final DateTime? publishedAt;
  final bool isPrerelease;
  final bool isCritical;

  UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.releaseName,
    required this.releaseNotes,
    this.downloadUrl,
    this.downloadSize,
    this.publishedAt,
    this.isPrerelease = false,
    this.isCritical = false,
  });

  /// Get formatted published date
  String get formattedDate {
    if (publishedAt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(publishedAt!);
    
    if (diff.inDays > 30) {
      return '${publishedAt!.day}/${publishedAt!.month}/${publishedAt!.year}';
    } else if (diff.inDays > 0) {
      return 'il y a ${diff.inDays} jour${diff.inDays > 1 ? 's' : ''}';
    } else if (diff.inHours > 0) {
      return 'il y a ${diff.inHours} heure${diff.inHours > 1 ? 's' : ''}';
    } else {
      return 'aujourd\'hui';
    }
  }

  /// Get clean release notes (without [critical] tags)
  String get cleanReleaseNotes {
    return releaseNotes
        .replaceAll(RegExp(r'\[critical\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[important\]', caseSensitive: false), '')
        .trim();
  }
}
