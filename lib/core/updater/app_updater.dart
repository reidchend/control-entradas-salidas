import 'dart:async';

import 'package:package_info_plus/package_info_plus.dart';

import '../config/app_config.dart';
import 'github_releases_source.dart';
import 'update_models.dart';
import 'updater_platform.dart';

/// Progreso de la descarga de una actualización.
class UpdateProgress {
  const UpdateProgress({required this.received, required this.total});
  final int received;
  final int total;

  double get fraction =>
      total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
}

/// Servicio de actualización remota de la app nativa (Windows/Android).
///
/// Porta `usr/updater.py` al Flutter: lee `versions.json`, compara la versión
/// de **esta** app (`APP_ID`) con la publicada y, si hay una nueva, descarga
/// el binario de la release `"$appId-v$version"`. En web no aplica (se sirve
/// desde el server) → `canRun=false`.
class AppUpdater {
  AppUpdater({
    GitHubReleasesSource? source,
  }) : _source = source ?? GitHubReleasesSource();

  final GitHubReleasesSource _source;

  /// Nombre del asset según app + plataforma.
  /// El POS se distribuye solo en Windows (`app-pos-windows.zip`); el
  /// inventario en Windows y Android (`app-inventario-windows.zip`,
  /// `app-inventario-android.apk`).
  static String _assetName(String appId, String platform) {
    if (platform == 'android') return 'app-$appId-android.apk';
    return 'app-$appId-windows.zip';
  }

  /// True si la plataforma soporta actualización (nativa, no web).
  bool get canRun => updaterCanRun;

  /// Version local de ESTA app (`APP_VERSION` sellado al compilar). Si el
  /// build no lo definió, cae a la versión de `pubspec` vía PackageInfo.
  Future<String> localVersion() async {
    final stamped = AppConfig.appVersion;
    if (stamped.isNotEmpty) return stamped;
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// Compara la versión de esta app contra su entrada en `versions.json`.
  /// `null` = al día (o el release del manifiesto aún no existe).
  Future<AppUpdateInfo?> checkForUpdate({bool force = false}) async {
    if (!canRun) return null;
    final remoteVersion = await _source.fetchManifestVersion(AppConfig.appId);
    if (remoteVersion == null || remoteVersion.isEmpty) return null;
    final local = await localVersion();
    final newer = _source.checkOfNewer(local, remoteVersion);
    if (newer == null) return null;
    // Descarga la release del tag propio de la app (`<appId>-v<version>`).
    return _source.fetchReleaseByTag('${AppConfig.appId}-v$newer');
  }

  /// Descarga el binario de la plataforma y devuelve la ruta local.
  /// Reporta progreso vía `onProgress`.
  Future<String> download(
    AppUpdateInfo info, {
    void Function(UpdateProgress)? onProgress,
  }) async {
    final platform = updaterPlatformKey;
    final assetName = _assetName(AppConfig.appId, platform);
    final asset = info.assetFor(assetName);
    if (asset == null) {
      throw Exception('No hay asset $assetName en la release ${info.version}');
    }

    final dir = await updaterDownloadDir();
    final destPath = '$dir/${_fileName(asset.name, info.version, platform)}';

    return updaterDownloadFile(
      asset.url,
      destPath,
      asset.size,
      (received, total) =>
          onProgress?.call(UpdateProgress(received: received, total: total)),
    );
  }

  /// Instala el binario descargado según la plataforma.
  Future<void> install(String filePath) => updaterInstall(filePath);

  static String _fileName(String assetName, String version, String platform) {
    final ext = assetName.contains('.zip')
        ? 'zip'
        : (assetName.contains('.apk') ? 'apk' : 'bin');
    return 'lycoris-$platform-$version.$ext';
  }
}