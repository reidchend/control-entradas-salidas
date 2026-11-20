import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/postgres_providers.dart';
import 'hostel_db_backend.dart';
import 'hostel_postgres_backend.dart';
import 'hostel_sqlite_init.dart';

/// Notifier que inicializa el backend de base de datos de Hostelería una sola
/// vez y expone el resultado de forma síncrona mediante [state].
///
/// Esto permite acceder al repositorio sin esperar un `FutureProvider`, lo que
/// evita que el repo sea `null` mientras se carga o tras un error transitorio.
class HostelDbStateNotifier extends StateNotifier<HostelDbBackend?> {
  HostelDbStateNotifier(this._ref) : super(null) {
    _inicializar();
  }

  final Ref _ref;

  Future<void> _inicializar() async {
    // 1. Intentar SQLite local (autónomo, importa datos maestros desde Postgres
    //    si está disponible para que el grid muestre habitaciones reales).
    try {
      final pg = _ref.read(postgresServiceProvider);
      final backend = await initHosteleriaSqlite(origenPostgres: pg);
      state = backend;
      return;
    } catch (_) {}

    // 2. Fallback a Postgres directo si SQLite no se pudo crear.
    try {
      final pg = _ref.read(postgresServiceProvider);
      if (pg != null) {
        state = PostgresDbBackend(pg);
        return;
      }
    } catch (_) {}

    // 3. Si nada funciona, queda null y la UI mostrará el mensaje de error.
    state = null;
  }
}

/// Proveedor del backend de base de datos. El valor es síncrono
/// (`HostelDbBackend?`) una vez que el notifier terminó de inicializarse.
final hostelDbBackendProvider =
    StateNotifierProvider<HostelDbStateNotifier, HostelDbBackend?>((ref) {
  return HostelDbStateNotifier(ref);
});
