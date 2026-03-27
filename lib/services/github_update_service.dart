import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class ReleaseInfo {
  final String tagName;
  final String name;
  final String body;
  final String? apkUrl;

  ReleaseInfo({
    required this.tagName,
    required this.name,
    required this.body,
    this.apkUrl,
  });
}

class GithubUpdateService {
  // ⚠️ CAMBIA CON IL TUO REPO es: 'patrizio-franzoi/album-colorare'
  static const String _repo = 'TUO_USERNAME/album-colorare';
  static const String _currentVersion = '1.0.0';

  static Future<ReleaseInfo?> checkForUpdates() async {
    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final tagName = (data['tag_name'] as String).replaceAll('v', '');

        String? apkUrl;
        for (final asset in data['assets'] as List) {
          if ((asset['name'] as String).endsWith('.apk')) {
            apkUrl = asset['browser_download_url'] as String;
            break;
          }
        }

        return ReleaseInfo(
          tagName: tagName,
          name: data['name'] ?? tagName,
          body: data['body'] ?? '',
          apkUrl: apkUrl,
        );
      }
    } catch (e) {
      debugPrint('Errore check aggiornamenti: $e');
    }
    return null;
  }

  static bool isNewerVersion(String remote) {
    final r = remote.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final c = _currentVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      final ri = i < r.length ? r[i] : 0;
      final ci = i < c.length ? c[i] : 0;
      if (ri > ci) return true;
      if (ri < ci) return false;
    }
    return false;
  }

  static Future<void> downloadApk(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
