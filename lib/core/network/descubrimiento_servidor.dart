import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'descubrimiento_error.dart';
import 'gist_api_url.dart';
import 'motivo_descubrimiento.dart';

// Reexportado para que los llamadores no tengan que saber de dónde sale.
export 'descubrimiento_error.dart' show DescubrimientoError;

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
  DescubridorServidor({this.endpoint, this.headers});

  /// Dónde se lee la URL. Por defecto, el Gist de [AppConfig].
  ///
  /// Se puede inyectar para probar el parseo contra un servidor local en vez
  /// de contra GitHub.
  final Uri? endpoint;
  final Map<String, String>? headers;

  /// Por qué falló la última lectura del Gist, o `null` si salió bien.
  ///
  /// Antes esto se perdía: la lectura devolvía `null` y no quedó rastro de si
  /// fue sin internet, por límite de tasa de GitHub o por un certificado que
  /// el antivirus intercepta. Cada uno necesita una respuesta distinta, y sin
  /// esto la pantalla terminaba diciendo "sin configurar" en los tres casos.
  ///
  /// Vive en la instancia y no en SharedPreferences a propósito: solo lo lee
  /// quien acaba de preguntar (el panel) o quien va a reportar el error, y así
  /// no se escribe en disco un diagnóstico viejo que confunda después.
  FalloDescubrimiento? ultimoFallo;

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
  /// Los fallos de red (sin internet, Gist caído, certificado rechazado) se
  /// resuelven con la caché, porque reintentar después va a funcionar. Lo que
  /// no se pierde es el motivo: queda en [ultimoFallo]. Los fallos de contenido
  /// (el Gist publica algo que no es una URL válida) sí se propagan: no tiene
  /// sentido reintentar, y el usuario necesita saber que hay que republicar.
  Future<String?> obtenerUrl({bool forzar = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final cache = prefs.getString(_kCache);
    final ts = prefs.getInt(_kCacheTs) ?? 0;
    final edad = DateTime.now().millisecondsSinceEpoch - ts;
    final cacheVigente =
        cache != null && cache.isNotEmpty && edad < _validezCache.inMilliseconds;

if (cacheVigente && !forzar) {
      // También se limpia acá: servir la caché es una lectura que salió bien, y
      // dejar el motivo de un fallo anterior haría que el próximo que lo lea
      // diagnostique un problema que ya se resolvió.
      ultimoFallo = null;
      return cache;
    }

    String? publicada;
    try {
      publicada = await _consultarGist();
    } on DescubrimientoError {
      rethrow; // Contenido inválido: hay que avisar, no reintentar.
    } catch (_) {
      // Red caída o Gist inexistente todavía: [ultimoFallo] ya quedó puesto.
    }

    if (publicada != null && publicada.isNotEmpty) {
      ultimoFallo = null;
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
  /// Falla con [DescubrimientoError] si el Gist responde y publica algo
  /// inservible. Cuando lo que falla es llegar al Gist —no hay red, se agota el
  /// tiempo, el certificado no valida, GitHub devuelve 403— no se propaga nada:
  /// el llamador usa la caché, y el motivo queda en [ultimoFallo] para que se
  /// pueda explicar en pantalla.
  Future<String?> _consultarGist() async {
    final http.Response res;
    try {
      res = await http
          .get(endpoint ?? AppConfig.apiUrlEndpoint,
              headers: headers ?? AppConfig.apiUrlHeaders)
          .timeout(esperaGist);
    } on TimeoutException {
      ultimoFallo =
          const FalloDescubrimiento(MotivoDescubrimiento.tiempoAgotado);
      return null;
    } on HandshakeException catch (e) {
      // El antivirus con inspección HTTPS se manifiesta acá, y es el caso que
      // más confunde: el navegador abre la misma dirección sin problema.
      ultimoFallo = FalloDescubrimiento(
        MotivoDescubrimiento.certificadoRechazado,
        detalle: e.message,
      );
      return null;
    } catch (e) {
      ultimoFallo = FalloDescubrimiento(
        MotivoDescubrimiento.sinRed,
        detalle: e.toString(),
      );
      return null;
    }

    if (res.statusCode != 200) {
      ultimoFallo = falloPorStatus(
        res.statusCode,
        pendiente: int.tryParse(res.headers['x-ratelimit-remaining'] ?? ''),
      );
      return null;
    }

    return leerUrlPublicada(res.body);
  }
}
