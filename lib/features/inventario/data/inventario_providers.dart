import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/postgres_providers.dart';
import 'inventario_repository.dart';

/// Provider del repositorio de inventario.
final inventarioRepoProvider = Provider<InventarioRepository?>((ref) {
  final db = ref.watch(postgresServiceProvider);
  if (db == null) return null;
  return InventarioRepository(db);
});
