import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/postgres_providers.dart';
import 'activos_repository.dart';

/// Provider del repositorio de activos.
final activosRepoProvider = Provider<ActivosRepository?>((ref) {
  final db = ref.watch(postgresServiceProvider);
  if (db == null) return null;
  return ActivosRepository(db);
});