import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postgres/postgres.dart';

import '../config/app_config.dart';

/// Inicializa el pool de conexiones PostgreSQL (pooler Neon).
///
/// La connection string se inyecta con `--dart-define=DATABASE_URL=...`.
Future<PostgreSQLPool> initializePostgres() async {
  if (!AppConfig.hasDatabaseUrl) {
    throw StateError('DATABASE_URL no configurado');
  }
  return PostgreSQLPool(
    AppConfig.databaseUrl,
    settings: PostgreSQLConnectionSettings(
      sslMode: SslMode.require,
    ),
  );
}

/// Pool de conexiones PostgreSQL (null si no hay URL o no fue inicializado).
final postgresPoolProvider = FutureProvider<PostgreSQLPool>((ref) async {
  return initializePostgres();
});