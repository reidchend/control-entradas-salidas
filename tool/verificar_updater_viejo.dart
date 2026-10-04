// Verifica si las apps compiladas con el workflow ANTERIOR detectan las releases
// nuevas, o si quedaron ciegas.
//
// Replica exactamente las funciones de la version VIEJA del updater, queanian
// en github_releases_source.dart antes del commit 1d39de9. No las importa:
// estan copiadas tal cual para que el resultado no dependa de poder compilar el
// proyecto (esta maquina no tiene Flutter ni .dart_tool).
//
// La razon de que el codigo viejo este pegado aqui y no sea un import es que
// ese codigo ya no existe en ninguna rama: el unico modo de probarlo es
// Keeping una copia textual. Si cambia, esta copia hay que volver a sacarla de
// 1d39de9^.
//
// Que mira, contra la API real de GitHub (sin auth):
//   1. que /releases/latest devuelva un tag que el parser viejo pueda leer;
//   2. que las apps viejas en 2.0.x/2.1.x detecten la release;
//   3. que el asset que cada app vieja pide este de verdad en esa release;
//   4. que ese tag sea una release legada `vX.Y.Z` y no una por app.
//
// El punto 4 es el que hace de alarma: /releases/latest devuelve una sola
// release, la de created_at mas reciente. Si alguien publica una release por
// app despues del puente, el endpoint vuelve a devolver `pos-v2.1.13` y las
// apps viejas se vuelven a quedar ciegas en silencio. Esta prueba falla ese dia.
//
// Uso:  dart run tool/verificar_updater_viejo.dart

import 'dart:convert';
import 'dart:io';

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

/// Tal cual en app_updater.dart: el nombre del asset no cambio entre el
/// workflow viejo y el nuevo, asi que las apps viejas piden estos y nada mas.
String assetName(String appId, [String platform = 'windows']) =>
    platform == 'android' ? 'app-$appId-android.apk' : 'app-$appId-windows.zip';

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

Future<Map<String, dynamic>> leerLatestRelease() async {
  final cliente = HttpClient();
  try {
    final peticion = await cliente.getUrl(Uri.parse('https://api.github.com/repos/'
        'reidchend/control-entradas-salidas/releases/latest'));
    // La API de GitHub rechaza las peticiones sin User-Agent.
    peticion.headers.set('User-Agent', 'verificar-updater-viejo');
    final res = await peticion.close();
    if (res.statusCode != 200) {
      throw Exception('la API respondio ${res.statusCode}');
    }
    final cuerpo = await res.transform(utf8.decoder).join();
    return jsonDecode(cuerpo) as Map<String, dynamic>;
  } finally {
    cliente.close();
  }
}

Future<void> main() async {
  Map<String, dynamic> release;
  try {
    release = await leerLatestRelease();
  } catch (e) {
    print('  No se pudo leer /releases/latest: $e');
    exit(1);
  }

  final tag = release['tag_name'] as String;
  final assets = <String>[
    for (final a in release['assets'] as List) a['name'] as String
  ];

  print('=== Lo que ve hoy una app VIEJA al arrancar ===');
  print('  GET /releases/latest  ->  tag_name = $tag');
  print('  published_at          = ${release['published_at']}');
  print('  assets                ->  $assets');
  final remoto = normalizeUpdateModels(tag);
  print('  AppUpdateInfo.version = $remoto   (la vieja solo le quita un "v")');
  print('');

  // ------------------------------------------------------------------ 1
  print('=== 1. El tag tiene que ser legible por el parser viejo ===');
  print('  _parse("$remoto") = ${parse(remoto)}');
  check('el parser viejo no lo manda a major=0', parse(remoto)[0] > 0,
      'el primer componente es "$remoto", y int.tryParse no lo puede leer: '
      'la app ve una release 0.x y nunca actualiza');
  check('es una release legada vX.Y.Z, no una por app',
      RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(tag),
      'el endpoint devolvio "$tag". Si es una por app (pos-v2.1.13) es que se '
      'publico despues del puente y las apps viejas volvieron a quedar ciegas');

  // ------------------------------------------------------------------ 2
  print('');
  print('=== 2. Las apps viejas detectan la release ===');
  const appsViejas = <String, String>{
    'pos 2.1.10+1': '2.1.10+1',
    'inventario 2.1.10+1': '2.1.10+1',
    'hosteleria 2.1.10+1': '2.1.10+1',
    'pos 2.1.9+1': '2.1.9+1',
    'inventario 2.0.2+1': '2.0.2+1',
  };
  appsViejas.forEach((nombre, local) {
    final r = checkOfNewer(local, remoto);
    print('  $nombre  ->  ${r ?? "SIN ACTUALIZACION (no se avisa)"}');
  });
  check('toda app vieja de 2.0.x/2.1.x ve laActualizacion',
      appsViejas.values
          .every((v) => checkOfNewer(v, remoto) != null),
      'alguna sigue sin avisar');
  check('una app que ya esta en $remoto no se actualiza (no el loop)',
      checkOfNewer('$remoto+1', remoto) == null,
      'se detecto a si misma como mas nueva');

  // ------------------------------------------------------------------ 3
  print('');
  print('=== 3. El asset que pide cada app esta en la release ===');
  for (final appId in ['pos', 'inventario', 'hosteleria']) {
    final nombre = assetName(appId);
    final hay = assets.contains(nombre);
    print('  $appId pide $nombre  ->  ${hay ? "esta" : "NO ESTA"}');
    check('  $nombre esta en $tag', hay,
        'la app vieja lo descargaria y recibiria "No hay asset $nombre en la '
        'release ${normalizeSource(tag)}"');
  }

  // ------------------------------------------------------------------ 4
  print('');
  print('=== 4. Por que hace falta la release legada (A/B) ===');
  // Con el tag por app, el parser viejo no ve nada. Esto es lo que el puente
  // vino a arreglar, asi que queda escrito como contraste.
  const tagPorApp = 'pos-v2.1.12';
  final porApp = normalizeUpdateModels(tagPorApp);
  print('  con "$tagPorApp": _parse = ${parse(porApp)}  ->  '
      '${checkOfNewer('2.1.10+1', porApp) ?? "SIN ACTUALIZACION"}');
  check('el tag por app es ilegible para el parser viejo (por eso el puente)',
      checkOfNewer('2.1.10+1', porApp) == null,
      'si detectara, el puente no habria hecho falta');

  print('');
  if (fallos == 0) {
    print('Todo OK: las apps viejas se actualizan solas desde $tag');
  } else {
    print('FALLARON $fallos verificaciones');
  }
  exit(fallos > 0 ? 1 : 0);
}