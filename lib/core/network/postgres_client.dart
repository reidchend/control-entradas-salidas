import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postgres/postgres.dart';

import '../config/app_config.dart';
import '../config/db_config.dart';
import '../data/http_sql_session.dart';
import '../data/native_sql_session.dart';
import '../data/sql_session.dart';
import 'descubrimiento_servidor.dart';
import 'proxy_url_resolver.dart';

/// Inicializa la sesión SQL según la plataforma y la configuración.
///
/// Dos modos, elegibles en runtime desde Ajustes → Base de datos:
///
/// - **Proxy HTTP** ([HttpSqlSession]): la app habla HTTPS contra
///   `tool/server.py`, que a su vez habla con PostgreSQL. Es lo que usan las
///   apps Windows y Android cuando la base está detrás de un túnel de
///   Cloudflare: no requiere abrir el 5432 ni instalar Tailscale en el equipo.
/// - **TCP directo** ([NativeSqlSession]): el driver nativo contra el puerto
///   5432. Más rápido por query porque no hay viaje HTTP, pero obliga a que
///   el equipo llegue a la base por una red privada.
///
/// La connection string se resuelve en este orden:
/// 1. Configuración guardada en Ajustes → Base de datos ([DbConfig]).
/// 2. `--dart-define=DATABASE_URL` embebido al compilar.
///
/// [descubridor] existe para los tests: permite apuntar la consulta al Gist a
/// un servidor local. En producción va nulo y se usa el Gist real.
Future<SqlSession> initializePostgres({DescubridorServidor? descubridor}) async {
  if (kIsWeb) {
    // En web no hay donde guardar un secreto, así que el token viaja
    // embebido al compilar (AppConfig.proxyToken).
    return HttpSqlSession(token: AppConfig.proxyToken);
  }
  final guardada = await DbConfig.load();
  if (guardada != null && guardada.isComplete && guardada.usesProxy) {
    // La URL no sale de la config: se vuelve a preguntar al Gist, para que un
    // túnel que cambio de URL no deje a la app hablando con un servidor que ya
    // no existe. Solo la guardada si el Gist no responde.
    final base = await resolverUrlProxy(
      urlGuardada: guardada.proxyUrl,
      urlManual: guardada.proxyUrlManual,
      descubridor: descubridor,
    );
    if (base.isEmpty) {
      throw const DbNotConfiguredError(
        'No se pudo determinar la URL del servidor. Revisá que el túnel esté '
        'corriendo en la PC servidor, o escribí la URL a mano en '
        'Configuración → Base de datos.',
      );
    }
    return HttpSqlSession(
      baseUrl: DbConfig.endpointDe(base).toString(),
      token: guardada.proxyToken,
    );
  }
  final url = await resolveDatabaseUrl();
  if (url.isEmpty) {
    // Excepción tipada a propósito: las pantallas de login la usan para
    // ofrecer "Configurar conexión" en vez de mostrar un error.
    throw const DbNotConfiguredError(
      'Base de datos no configurada. Abrí Configuración → Base de datos y '
      'guardá los datos.',
    );
  }
  return NativeSqlSession(Pool.withUrl(_normalizeUrl(url)));
}

/// Connection string efectiva para esta plataforma.
///
/// Vacía en web (el proxy resuelve la conexión) y cuando no hay ninguna
/// fuente configurada. También vacía en modo proxy: ahí la app no habla
/// PostgreSQL directamente, va por HTTP.
Future<String> resolveDatabaseUrl() async {
  if (kIsWeb) return '';
  final guardada = await DbConfig.load();
  if (guardada != null && guardada.isComplete) {
    if (guardada.usesProxy) return '';
    return guardada.toUrl();
  }
  return AppConfig.databaseUrl;
}

/// El driver `postgres` rechaza parámetros de query que no entiende (p. ej.
/// `channel_binding`, propio de Neon). Se conservan solo los que soporta.
final _supportedQueryParams = {
  'sslmode', 'sslcert', 'sslkey', 'sslrootcert', 'connect_timeout',
  'client_encoding', 'replication', 'query_timeout', 'max_connection_age',
  'max_connection_count', 'max_session_use', 'max_query_count',
};

String _normalizeUrl(String url) {
  final uri = Uri.parse(url);
  final kept = Map<String, String>.fromEntries(
      uri.queryParameters.entries.where(
          (e) => _supportedQueryParams.contains(e.key)));
  var result = uri;
  if (kept.isNotEmpty) {
    result = uri.replace(queryParameters: kept);
  }
  // Pool pequeño reutilizable (4 conexiones): el default del driver es 1,
  // lo que serializaría todas las queries concurrentes de la app móvil.
  final params = Map<String, String>.from(result.queryParameters);
  params['max_connection_count'] ??= '4';
  return result.replace(queryParameters: params).toString();
}

/// Sesión SQL de la plataforma (null si no fue inicializado).
final postgresPoolProvider = FutureProvider<SqlSession>((ref) async {
  return initializePostgres();
});