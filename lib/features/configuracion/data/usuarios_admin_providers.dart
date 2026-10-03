import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/usuarios_providers.dart';
import '../../../core/models/usuario.dart';

/// Todos los usuarios del directorio central (para la administración).
final usuariosAdminProvider = FutureProvider<List<Usuario>>((ref) async {
  final repo = ref.watch(usuariosRepoProvider);
  if (repo == null) return const [];
  return repo.listarTodos();
});

/// Equipos vinculados a un usuario (para ver/desvincular).
final dispositivosUsuarioProvider = FutureProvider.autoDispose
    .family<List<DispositivoVinculado>, int>((ref, usuarioId) async {
  final repo = ref.watch(usuariosRepoProvider);
  if (repo == null) return const [];
  return repo.dispositivosDe(usuarioId);
});
