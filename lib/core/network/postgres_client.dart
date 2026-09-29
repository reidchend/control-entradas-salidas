import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postgres/postgres.dart';

import '../config/app_config.dart';
import '../config/db_config.dart';
import '../data/http_sql_session.dart';
import '../data/native_sql_session.dart';
import '../data/sql_session.dart';

/// Inicializa la sesión SQL según la plataforma.
///
/// - Escritorio/móvil: pool de conexiones PostgreSQL directo con el driver
///   nativo `package:postgres` (no soporta sockets en web).
/// - Web: proxy HTTP `/proxy-sql` del servidor, que habla con PostgreSQL
///   server-side.
///
/// La connection string se resuelve en este orden:
/// 1. Configuración guardada en Ajustes → Base de datos ([DbConfig]).
/// 2. `--dart-define=DATABASE_URL` embebido al compilar.
Future<SqlSession> initializePostgres() async {
  if (kIsWeb) {
    return HttpSqlSession();
  }
  final url = await resolveDatabaseUrl();
  if (url.isEmpty) {
    throw StateError(
      'Base de datos no configurada. Abrí Ajustes → Sistema → '
      'Configurar conexión y guardá los datos.',
    );
  }
  return NativeSqlSession(Pool.withUrl(_normalizeUrl(url)));
}

/// Connection string efectiva para esta plataforma.
///
/// Vacía en web (el proxy resuelve la conexión) y cuando no hay ninguna
/// fuente configurada.
Future<String> resolveDatabaseUrl() async {
  if (kIsWeb) return '';
  final guardada = await DbConfig.load();
  if (guardada != null && guardada.isComplete) return guardada.toUrl();
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