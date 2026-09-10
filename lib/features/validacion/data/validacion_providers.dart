import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/postgres_providers.dart';
import 'temporales_repository.dart';
import 'validacion_repository.dart';

final validacionRepoProvider = Provider<ValidacionRepository?>((ref) {
  final db = ref.watch(postgresServiceProvider);
  if (db == null) return null;
  return ValidacionRepository(db);
});

final temporalesRepoProvider = Provider<TemporalesRepository>((ref) {
  final db = ref.watch(postgresServiceProvider);
  if (db == null) return null;
  return TemporalesRepository(db);
});

final temporalesProvider = StreamProvider<List<TemporalData>>((ref) {
  return ref.watch(temporalesRepoProvider).watchTemporales();
});

final proveedoresProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(validacionRepoProvider)!.getProveedores();
});