import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/postgres_providers.dart';
import 'historial_repository.dart';

final historialRepoProvider = Provider<HistorialRepository?>((ref) {
  final db = ref.watch(postgresServiceProvider);
  if (db == null) return null;
  return HistorialRepository(db);
});

final facturasProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(historialRepoProvider)!.getFacturas();
});

final porFechaProvider = FutureProvider.autoDispose
    .family<List<EntradaPorFecha>, ({DateTime ini, DateTime fin})>(
        (ref, rango) {
  return ref
      .watch(historialRepoProvider)!
      .getEntradasPorFecha(rango.ini, rango.fin);
});
