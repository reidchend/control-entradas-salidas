import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/postgres_client.dart';
import 'cache_service.dart';
import 'postgres_service.dart';

/// Provider del servicio PostgreSQL centralizado.
///
/// Retorna `null` si no hay configuracion de PostgreSQL.
/// Todos los repositorios deben usar este provider para acceder a la base
/// de datos remota.
final postgresServiceProvider = Provider<PostgresService?>((ref) {
  final pool = ref.watch(postgresPoolProvider).value;
  if (pool == null) return null;
  return PostgresService(pool);
});

/// Provider del pool de conexiones raw (para queries complejas que el
/// servicio genérico no cubre).
final postgresPoolRawProvider = Provider<PostgreSQLPool?>((ref) {
  return ref.watch(postgresPoolProvider).value;
});

/// Provider del servicio de cache local.
/// Se inicializa una vez y se reutiliza en toda la app.
final cacheServiceProvider = FutureProvider<CacheService>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return CacheService(prefs);
});