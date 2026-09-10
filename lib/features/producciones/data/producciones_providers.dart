import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/postgres_providers.dart';
import '../../../core/models/producto.dart';
import '../../../core/models/receta.dart';
import 'producciones_repository.dart';

/// Provider del repositorio de producciones.
final produccionesRepoProvider = Provider<ProduccionesRepository?>((ref) {
  final db = ref.watch(postgresServiceProvider);
  if (db == null) return null;
  return ProduccionesRepository(db);
});

/// Helper para leer el repo de forma segura.
ProduccionesRepository? _repo(Ref ref) =>
    ref.read(produccionesRepoProvider);

/// Recetas activas para el tab "Recetas".
final recetasProvider = FutureProvider.autoDispose<List<Receta>>((ref) async {
  final repo = _repo(ref);
  if (repo == null) return [];
  return repo.getRecetas();
});

/// Productos activos para el editor de recetas (buscador/selectores).
final productosActivosProvider =
    FutureProvider.autoDispose<List<Producto>>((ref) async {
  final repo = _repo(ref);
  if (repo == null) return [];
  return repo.getProductosActivos();
});

/// Producciones pendientes para el tab "En Produccion".
final pendientesProvider =
    FutureProvider.autoDispose<List<ProduccionInfo>>((ref) async {
  final repo = _repo(ref);
  if (repo == null) return [];
  return repo.getProduccionesPorEstado('pendiente');
});

/// Historial de producciones para el tab "Historial".
final historialProduccionesProvider =
    FutureProvider.autoDispose<List<ProduccionInfo>>((ref) async {
  final repo = _repo(ref);
  if (repo == null) return [];
  return repo.getProducciones();
});
