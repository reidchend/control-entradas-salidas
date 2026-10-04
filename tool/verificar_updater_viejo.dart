// Verifica si las apps compILadas con el workflow ANTERIOR detectan las releases
// nuevas (tag `<appId>-vX.Y.Z`) o si quedaron ciegas.
//
// Replica exactamente las funciones de la version VIEJA del updater, que Vivian
// en github_releases_source.dart antes del commit 1d39de9. No las importa:
// estan copiadas tal cual para que el resultado no dependa de poder compilar el
// proyecto (esta maquina no tiene Flutter ni .dart_tool).
//
// Lo que se midio en vivo contra la API de GitHub (sin auth) el 2026-10-04:
//   GET /repos/reidchend/control-entradas-salidas/releases/latest
//     -> tag_name: hosteleria-v2.1.11
//     -> assets:   [app-hosteleria-windows.zip]
//
// Uso:  dart run tool/verificar_updater_viejo.dart

/// Tal cual en update_models.dart (LA VIEJA, sin el +build).
String normalizeUpdateModels(String tag) =>
    tag.replaceFirst(RegExp(r'^v'), '');

/// Tal cual en github_releases_source.dart.
String normalizeSource(String tag) =>
    tag.replaceFirst(RegExp(r'^v'), '').replaceFirst(RegExp(r'\+.*'), '');

List<int> parse(String v) {
  final parts = v.split('.');
  return [
    int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0,
    int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0,
    int.tryParse(parts.length > 2 ? parts[2] : '') ?? 0,
  ];
}

int compareVersions(String a, String b) {
  final pa = parse(a);
  final pb = parse(b);
  for (var i = 0; i < 3; i++) {
    if (pa[i] != pb[i]) return pa[i] - pb[i];
  }
  return 0;
}

/// Devuelve la version remota si es mas nueva, `null` si esta al dia.
String? checkOfNewer(String localVersion, String remoteVersion) {
  final local = normalizeSource(localVersion);
  final remote = normalizeSource(remoteVersion);
  if (local == remote) return null;
  if (compareVersions(remote, local) <= 0) return null;
  return remote;
}

int fallos = 0;
void check(String etiqueta, bool ok, String detalle) {
  if (ok) {
    print('  OK    $etiqueta');
  } else {
    print('  FALLA $etiqueta');
    print('         $detalle');
    fallos++;
  }
}

void main() {
  // Lo que el endpoint /releases/latest devuelve hoy.
  const latestTag = 'hosteleria-v2.1.11';
  const latestAssets = ['app-hosteleria-windows.zip'];

  print('=== Lo que ve una app VIEJA al arrancar ===');
  print('  GET /releases/latest  ->  tag_name = $latestTag');
  print('  assets               ->  $latestAssets');
  final remoteVersion = normalizeUpdateModels(latestTag);
  print('  AppUpdateInfo.version=  $remoteVersion   (solo se le quita un "v" inicial)');
  print('');

  print('=== Por que el parseo se rompe ===');
  print('  _parse("$remoteVersion") = ${parse(remoteVersion)}');
  print('    ^ el primer componente es "hosteleria-v2", que int.tryParse no puede');
  print('      leer, asi que cae a 0. La app ve major=0 en una release 2.x.');
  print('  _parse("2.1.10")            = ${parse('2.1.10')}');
  print('  compare(remoto, local)      = ${compareVersions(remoteVersion, '2.1.10')}');
  print('');

  print('=== Apps viejas contra el endpoint actual ===');
  // La app vieja tomaba la version local de PackageInfo, y el workflow viejo
  // escribia en pubspec `version: <tag>+1`.
  final appsViejas = <String, String>{
    'pos 2.1.10+1': '2.1.10+1',
    'inventario 2.1.10+1': '2.1.10+1',
    'hosteleria 2.1.10+1': '2.1.10+1',
    'inventario 2.0.2+1': '2.0.2+1',
    'pos 2.1.9+1': '2.1.9+1',
  };
  appsViejas.forEach((nombre, local) {
    final r = checkOfNewer(local, remoteVersion);
    print('  $nombre  ->  ${r ?? "SIN ACTUALIZACION (no se avisa)"}');
  });
  print('');

  check('una app vieja en 2.1.10 no detecta la 2.1.11',
      checkOfNewer('2.1.10+1', remoteVersion) == null,
      'deberia avisar y no avisa: el parseo del tag le da major=0');

  check('ninguna app vieja de 2.x detecta la release nueva',
      appsViejas.values.every((v) => checkOfNewer(v, remoteVersion) == null),
      'alguna si detecto, habria que ver que asset se intenta descargar');

  print('');
  print('=== Y si una app vieja SI llegara a descargar ===');
  // _assetName(appId, 'windows') = 'app-<appId>-windows.zip'
  for (final appId in ['pos', 'inventario', 'hosteleria']) {
    final asset = 'app-$appId-windows.zip';
    final existe = latestAssets.contains(asset);
    print('  appId=$appId  busca $asset  ->  ${existe ? "esta" : "NO ESTA"}');
    if (appId != 'hosteleria') {
      check('la app vieja de $appId no puede descargar (el asset no esta)',
          !existe,
          'encontro el asset: descargaria un binario de otra app');
    }
  }

  print('');
  print('=== La app NUEVA, en cambio ===');
  // checkForUpdate: fetchManifestVersion(APP_ID) -> fetchReleaseByTag('$APP_ID-v$newer')
  const manifiesto = {'inventario': '2.1.11', 'pos': '2.1.11', 'hosteleria': '2.1.11'};
  manifiesto.forEach((appId, remoto) {
    final local = '2.1.10'; // APP_VERSION sellado al compilar
    final nuevo = checkOfNewer(local, remoto);
    final tag = nuevo == null ? null : '$appId-v$nuevo';
    print('  appId=$appId  local=$local  manifiesto=$remoto  ->  tag=$tag');
    check('la app nueva de $appId apunta a su propio tag',
        tag == '$appId-v2.1.11',
        'apunto a $tag en vez de $appId-v2.1.11');
  });

  print('');
  if (fallos == 0) {
    print('Todo OK: el comportamiento es el esperado');
  } else {
    print('FALLARON $fallos verificaciones');
  }

  // ---------------------------------------------------------------------------
  // ¿Se pueden rescatar las apps viejas publicando ademas una release en el
  // formato viejo? Es la unica palanca que queda, porque el codigo de la app ya
  // esta compilado y no se puede tocar.
  //
  // La clave: el problema no es el prefijo del appId en si, sino que
  // _normalizeVersion no lo quita. Si el tag vuelve a ser "vX.Y.Z", el parseo
  // funciona y la comparacion vuelve a dar lo que debe.
  print('');
  print('=== ¿Se pueden rescatar? Release legada con el tag viejo "vX.Y.Z" ===');
  const legadoTag = 'v2.1.12';
  const legadoAssets = [
    'app-pos-windows.zip',
    'app-inventario-windows.zip',
    'app-hosteleria-windows.zip',
  ];
  final legadoVersion = normalizeUpdateModels(legadoTag);
  print('  /releases/latest  ->  $legadoTag');
  print('  AppUpdateInfo.version= $legadoVersion');
  print('  _parse("$legadoVersion") = ${parse(legadoVersion)}   <- si se entiende el tag');
  print('');
  for (final appId in ['pos', 'inventario', 'hosteleria']) {
    const local = '2.1.10+1';
    final nuevo = checkOfNewer(local, legadoVersion);
    final asset = 'app-$appId-windows.zip';
    final puede = nuevo != null && legadoAssets.contains(asset);
    print('  app vieja $appId: local=$local -> detecta=$nuevo, '
        "asset $asset ${legadoAssets.contains(asset) ? 'esta' : 'NO esta'}"
        '  => ${puede ? 'SE RESCATA' : 'sigue ciega'}');
    check('la app vieja de $appId se rescata con la release legada', puede,
        'no detecta la version o no encuentra su asset');
  }
  print('');
  print('  OJO: /releases/latest devuelve UNA sola release, la mas reciente.');
  print('  Si el workflow publica primero pos-v2.1.13 y despues la legada');
  print('  v2.1.13, la legada queda como la ultima y las apps viejas siguen');
  print('  funcionando. Si se publica al reves, vuelven a quedar ciegas.');
  print('');
  print('CONCLUSION FINAL:');
  print('  1. Las apps compiladas antes de 1d39de9 NO detectan las releases nuevas.');
  print('     No es red ni version: el tag con prefijo de appId no lo parsea el');
  print('     comparador y siempre da "sin actualizacion".');
  print('  2. Se pueden mantener funcionando publicando ademas una release');
  print('     legada vX.Y.Z con los tres .zip de Windows, creada AL FINAL.');
  print('  3. Sin eso, los usuarios tienen que bajar e instalar a mano una vez.');
}
