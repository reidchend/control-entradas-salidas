import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../config/app_config.dart';
import 'update_models.dart';

/// Crea un http.Client con SSL flexible en nativo (mismo patrón que
/// TasaBcvService). En web usa el client por defecto.
http.Client _createClient() {
  if (kIsWeb) return http.Client();
  final io = HttpClient()
    ..badCertificateCallback = (_, __, ___) => true;
  return IOClient(io);
}

/// Consulta la última release de GitHub (equivalente a `usr/updater.py`).
class GitHubReleasesSource {
  GitHubReleasesSource({String? repo, http.Client? client})
      : _repo = repo ?? 'reidchend/control-entradas-salidas',
        _client = client ?? _createClient();

  final String _repo;
  final http.Client _client;

  static const _headers = {'User-Agent': 'Lycoris-App'};

  /// Endpoint público sin auth (60 req/h por IP): releases/latest.
  Uri get _latestUrl =>
      Uri.parse('https://api.github.com/repos/$_repo/releases/latest');

  /// Release concreta por tag (p.ej. `hosteleria-v2.0.3`).
  Uri _tagUrl(String tag) =>
      Uri.parse('https://api.github.com/repos/$_repo/releases/tags/$tag');

  /// Manifiesto de versiones por app. Se le agrega un cache-buster para
  /// esquivar la caché de `raw.githubusercontent.com`.
  Uri get _manifestUrl {
    final base = AppConfig.updateUrl;
    final sep = base.contains('?') ? '&' : '?';
    return Uri.parse('$base${sep}t=${DateTime.now().millisecondsSinceEpoch}');
  }

  /// Última release publicada. Lanza si no hay release o falla la red.
  Future<AppUpdateInfo> fetchLatest() async {
    final res = await _client
        .get(_latestUrl, headers: _headers)
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('GitHub respondió ${res.statusCode}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return AppUpdateInfo.fromJson(json);
  }

  /// Versión vigente de [appId] según `versions.json` (`null` si no está).
  Future<String?> fetchManifestVersion(String appId) async {
    final res = await _client
        .get(_manifestUrl, headers: _headers)
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('Manifiesto respondió ${res.statusCode}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final entry = json[appId];
    if (entry is Map) {
      final v = entry['version'];
      if (v is String && v.isNotEmpty) return _normalizeVersion(v);
    }
    return null;
  }

  /// Release de un tag concreto. `null` si el tag aún no existe (404).
  Future<AppUpdateInfo?> fetchReleaseByTag(String tag) async {
    final res = await _client
        .get(_tagUrl(tag), headers: _headers)
        .timeout(const Duration(seconds: 10));
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw Exception('GitHub respondió ${res.statusCode}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return AppUpdateInfo.fromJson(json);
  }

  /// Compara la versión local con la remota. `null` = sin actualización.
  Future<String?> checkForUpdate(String localVersion) async {
    final remote = await fetchLatest();
    return checkOfNewer(localVersion, remote.version);
  }

  /// Compara `localVersion` contra `remoteVersion` directamente.
  /// Devuelve la versión remota si es más nueva, `null` si está al día.
  String? checkOfNewer(String localVersion, String remoteVersion) {
    final local = _normalizeVersion(localVersion);
    final remote = _normalizeVersion(remoteVersion);
    if (local == remote) return null;
    if (_compareVersions(remote, local) <= 0) return null;
    return remote;
  }

  /// `v1.2.0` → `1.2.0`, `2.0.0+1` → `2.0.0`.
  static String _normalizeVersion(String tag) =>
      tag.replaceFirst(RegExp(r'^v'), '').replaceFirst(RegExp(r'\+.*'), '');

  /// Comparación semver simple (`1.2.0` vs `1.2.3`). Devuelve negativo si
  /// a < b, 0 si iguales, positivo si a > b.
  int _compareVersions(String a, String b) {
    final pa = _parse(a);
    final pb = _parse(b);
    for (var i = 0; i < 3; i++) {
      if (pa[i] != pb[i]) return pa[i] - pb[i];
    }
    return 0;
  }

  List<int> _parse(String v) {
    final parts = v.split('.');
    return [
      int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0,
      int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0,
      int.tryParse(parts.length > 2 ? parts[2] : '') ?? 0,
    ];
  }
}

/// Fábrica con URL configurable (AppConfig.updateUrl) y valores por defecto.
GitHubReleasesSource createGitHubReleasesSource() =>
    GitHubReleasesSource(repo: AppConfig.updateRepo);