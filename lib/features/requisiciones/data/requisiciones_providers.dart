import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/postgres_providers.dart';
import 'requisiciones_repository.dart';

final requisicionesRepoProvider = Provider<RequisicionesRepository?>((ref) {
  final db = ref.watch(postgresServiceProvider);
  if (db == null) return null;
  return RequisicionesRepository(db);
});
