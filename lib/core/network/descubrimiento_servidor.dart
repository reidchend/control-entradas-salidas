import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// Error al averiguar la dirección del servidor.
class DescubrimientoError implements Exception {
  const DescubrimientoError(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Descubre la URL pública del servidor de base de datos.
///
/// Lee `api_url.json` del Gist, que `tool/iniciar_tunnel_api.js` publica cada
/// vez que el túnel arranca. Así el usuario solo escribe el TOKEN en cada
/// equipo: si el túnel cambia de URL, las apps toman la nueva al próximo
/// arranque sin tocar nada.
///
/// La URL cacheada se usa sin red: si el equipo está sin internet en el
/// momento de abrir, no se pierde la configuración.
class DescubridorServidor {
  const DescubridorServidor({this.endpoint, this.headers});

  /// Dónde se lee la URL. Por defecto, el Gist de [AppConfig].
  ///
  /// Se puede inyectar para probar el parseo contra un servidor local en vez
  /// de contra GitHub.
  final Uri? endpoint;
  final Map<String, String>? headers;

  static const _kCache = 'api_url_cache';
  static const _kCacheTs = 'api_url_cache_ts';

  /// Cuánto se confía en la URL cacheada antes de volver a preguntar.
  ///
  /// Corto a propósito: con el túnel rápido la URL cambia en cada reinicio de
  /// la PC servidor, así que interesa enterarse al poco de abrir la app y no
  /// horas después. Cada arranque ya la pide igual (ver `forzarProxy` en
  /// `postgres_client.dart`), así que este plazo solo governa las consultas
  /// dentro de una sesión que ya está abierta.
  static const _validezCache = Duration(minutes: 10);

  /// URL del servidor, o `null` si no se pudo determinar.
  ///
  /// Prioridad: caché vigente → Gist → caché vieja (mejor una URL que
  /// probablemente no exista que ninguna).
  ///
  /// Los fallos de red (sin internet, Gist caído) se resuelven con la caché,
  /// porque reintentar después va a funcionar. Los fallos de contenido
  /// (el Gist publica algo que no es una URL válida) sí se propagan: no tiene
  /// sentido reintentar, y el usuario necesita saber que hay que republicar.
  Future<String?> obtenerUrl({bool forzar = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final cache = prefs.getString(_kCache);
    final ts = prefs.getInt(_kCacheTs) ?? 0;
    final edad = DateTime.now().millisecondsSinceEpoch - ts;
    final cacheVigente =
        cache != null && cache.isNotEmpty && edad < _validezCache.inMilliseconds;

    if (cacheVigente && !forzar) return cache;

    String? publicada;
    try {
      publicada = await _consultarGist();
    } on DescubrimientoError {
      rethrow; // Contenido inválido: hay que avisar, no reintentar.
    } catch (_) {
      // Red caída o Gist inexistente todavía.
    }

    if (publicada != null && publicada.isNotEmpty) {
      await prefs.setString(_kCache, publicada);
      await prefs.setInt(_kCacheTs, DateTime.now().millisecondsSinceEpoch);
      return publicada;
    }

    return (cache != null && cache.isNotEmpty) ? cache : null;
  }

  /// Última URL conocida, sin tocar la red. Para mostrarla mientras consulta.
  ///
  /// Útil cuando la app abre sin red: igual puede mostrar qué servidor se usó
  /// la última vez, en vez de un campo en blanco.
  Future<String?> urlCacheada() async {
    final prefs = await SharedPreferences.getInstance();
    final cache = prefs.getString(_kCache);
    return (cache != null && cache.isNotEmpty) ? cache : null;
  }

  Future<void> olvidar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCache);
    await prefs.remove(_kCacheTs);
  }

  /// Lee `api_url.json` del Gist y devuelve la URL.
  ///
  /// Falla con [DescubrimientoError] si el Gist no responde, no tiene el
  /// archivo, o publica algo que no parece una URL.
  Future<String?> _consultarGist() async {
    final res = await http
        .get(endpoint ?? AppConfig.apiUrlEndpoint,
            headers: headers ?? AppConfig.apiUrlHeaders)
        .timeout(const Duration(seconds: 12));
    // Un Gist que todavia no existe, o uno caido, es transitorio: se
    // devuelve null y el llamador usa la cache.
    if (res.statusCode != 200) return null;

    final Map<String, dynamic> gist;
    try {
      gist = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw const DescubrimientoError('El Gist devolvió una respuesta ilegible.');
    }

    final files = gist['files'] as Map<String, dynamic>?;
    final archivo = files?[AppConfig.apiUrlFile] as Map<String, dynamic>?;
    final contenido = archivo?['content']?.toString();
    if (contenido == null || contenido.isEmpty) {
      throw const DescubrimientoError(
        'El Gist no tiene el archivo de la URL. '
        'Falta ejecutar tool/iniciar_tunnel_api.js en la PC servidor.',
      );
    }

    Map<String, dynamic> datos;
    try {
      datos = jsonDecode(contenido) as Map<String, dynamic>;
    } catch (_) {
      throw const DescubrimientoError(
        'api_url.json no contiene un JSON válido.',
      );
    }

    final url = datos['url']?.toString().trim() ?? '';
    if (url.isEmpty) {
      throw const DescubrimientoError('api_url.json no tiene el campo "url".');
    }
    // Solo https: por HTTP plano la conexión no viaja cifrada y Android 9+
    // la bloquea. Además, una URL rara acá sería un vector de inyección.
    if (!url.startsWith('https://')) {
      throw DescubrimientoError(
        'La URL publicada ("$url") no empieza con https://.',
      );
    }
    return url;
  }
}
