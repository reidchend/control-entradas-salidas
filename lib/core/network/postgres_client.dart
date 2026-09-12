import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postgres/postgres.dart';

import '../config/app_config.dart';
import '../data/http_sql_session.dart';
import '../data/native_sql_session.dart';
import '../data/sql_session.dart';

/// Inicializa la sesión SQL según la plataforma.
///
/// - Escritorio/móvil: pool de conexiones PostgreSQL (pooler Neon) con el
///   driver nativo `package:postgres`.
/// - Web: proxy HTTP `/proxy-sql` del servidor (el driver nativo usa
///   `dart:io`, que no existe en Flutter web).
Future<SqlSession> initializePostgres() async {
  if (kIsWeb) {
    return HttpSqlSession();
  }
  if (!AppConfig.hasDatabaseUrl) {
    throw StateError('DATABASE_URL no configurado');
  }
  return NativeSqlSession(Pool.withUrl(_normalizeUrl(AppConfig.databaseUrl)));
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
  if (kept.isEmpty) return url;
  return uri.replace(queryParameters: kept).toString();
}

/// Sesión SQL de la plataforma (null si no fue inicializado).
final postgresPoolProvider = FutureProvider<SqlSession>((ref) async {
  return initializePostgres();
});