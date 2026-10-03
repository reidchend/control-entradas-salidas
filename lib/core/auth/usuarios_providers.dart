import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/postgres_providers.dart';
import 'usuarios_repository.dart';

/// Repositorio del directorio central de usuarios. `null` mientras el pool de
/// base de datos no resolvió.
final usuariosRepoProvider = Provider<UsuariosRepository?>((ref) {
  final db = ref.watch(postgresServiceProvider);
  if (db == null) return null;
  return UsuariosRepository(db);
});
