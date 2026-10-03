import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/usuarios_providers.dart';
import '../../../core/models/usuario.dart';

/// Sesión del recepcionista de Hostelería.
///
/// A diferencia del POS **no** abre turno ni caja: solo valida el PIN del
/// usuario del directorio central con acceso al módulo `hosteleria`.
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
    final repo = ref.read(usuariosRepoProvider);
    if (repo == null) return HostelLoginResult.sinBase;
    if (usuario.pinHash != null && usuario.pinHash!.isNotEmpty) {
      if (pin == null || pin.isEmpty) return HostelLoginResult.pinIncorrecto;
      if (!await repo.verificarPin(usuario, pin)) {
        return HostelLoginResult.pinIncorrecto;
      }
    }
    state = usuario;
    return HostelLoginResult.ok;
  }

  void cerrarSesion() => state = null;
}
