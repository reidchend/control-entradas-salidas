import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/usuario.dart';
import '../../hosteleria/data/hosteleria_providers.dart'
    show verificarPinLocal;
import '../../hosteleria/data/hosteleria_providers.dart'
    show hostelUsuariosSqliteProvider;

/// Sesión del recepcionista de Hostelería.
///
/// A diferencia del POS **no** abre turno ni caja: solo valida el PIN del
/// usuario del directorio central con acceso al módulo `hosteleria`.
///
/// En modo pruebas (SQLite local sin Postgres), valida contra la tabla
/// `hosteleria_usuarios` de la base local.
final hostelSessionProvider =
    NotifierProvider<HostelSessionNotifier, Usuario?>(
        HostelSessionNotifier.new);

enum HostelLoginResult { ok, pinIncorrecto, sinBase }

class HostelSessionNotifier extends Notifier<Usuario?> {
  @override
  Usuario? build() => null;

  Future<HostelLoginResult> iniciarSesion(
    Usuario usuario, {
    String? pin,
  }) async {
    // Modo Postgres: verificar PIN contra el directorio central.
    final repo = ref.read(usuariosRepoProvider);
    if (repo != null) {
      if (usuario.pinHash != null && usuario.pinHash!.isNotEmpty) {
        if (pin == null || pin.isEmpty) return HostelLoginResult.pinIncorrecto;
        if (!await repo.verificarPin(usuario, pin)) {
          return HostelLoginResult.pinIncorrecto;
        }
      }
      state = usuario;
      return HostelLoginResult.ok;
    }

    // Modo pruebas (SQLite local): buscar usuario en hosteleria_usuarios
    // y verificar PIN localmente.
    final usuariosLocales = await ref.read(hostelUsuariosSqliteProvider.future);
    final local = usuariosLocales.firstWhere(
      (u) => u.id == usuario.id,
      orElse: () => Usuario(
        id: usuario.id,
        nombre: usuario.nombre,
        pinHash: null,
        nivel: usuario.nivel,
        activo: true,
        modulos: const {'hosteleria'},
      ),
    );

    if (!local.activo) return HostelLoginResult.pinIncorrecto;

    if (local.pinHash != null && local.pinHash!.isNotEmpty) {
      if (pin == null || pin.isEmpty) return HostelLoginResult.pinIncorrecto;
      if (!verificarPinLocal(pin, local.pinHash)) {
        return HostelLoginResult.pinIncorrecto;
      }
    }

    state = usuario;
    return HostelLoginResult.ok;
  }

  void cerrarSesion() => state = null;
}
