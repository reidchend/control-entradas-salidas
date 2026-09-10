import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/postgres_providers.dart';
import 'stock_repository.dart';

final stockRepoProvider = Provider<StockRepository?>((ref) {
  final db = ref.watch(postgresServiceProvider);
  if (db == null) return null;
  return StockRepository(db);
});
