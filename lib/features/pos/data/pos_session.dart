import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/pos_models.dart';
import 'pos_providers.dart';

/// Sesión activa del POS: cajero + turno de caja abierto.
class PosSesionActiva {
  const PosSesionActiva({required this.usuario, required this.sesionId});
  final PosUsuario usuario;
  final int sesionId;
}

/// Resultado del intento de iniciar sesión.
enum SesionLoginResult {
  /// Se abrió un turno nuevo.
  nueva,

  /// Se retomó el turno existente del mismo usuario.
  retomada,

  /// El PIN era incorrecto (no se hizo nada).
  pinIncorrecto,
}

/// Estado de la sesión del POS (flujo de turnos/cajas multi-cajero):
/// - Al hacer login se abre un turno con caja en 0 (o se retoma el turno que
///   el MISMO cajero dejó abierto si el sistema se cerró sin logout).
/// - Cada cajero tiene SU PROPIO turno independiente. Varios cajeros pueden
///   tener turnos abiertos a la vez en el mismo dispositivo sin cerrarse entre
///   sí.
/// - Al cerrar sesión se cierra el turno y la caja (monto final automático =
///   caja inicial + ventas vigentes del turno), generando el reporte que se
///   guarda como `pos_sesiones`.
/// - Al arrancar siempre se pide login (no se restaura la sesión), pero el
///   turno de cada cajero se conserva para retomarlo en su próximo login.
final posSessionProvider =
    NotifierProvider<PosSessionNotifier, PosSesionActiva?>(
        PosSessionNotifier.new);

class PosSessionNotifier extends Notifier<PosSesionActiva?> {
  @override
  PosSesionActiva? build() => null;

  /// Valida el PIN (si el usuario lo tiene) y abre un turno de caja en 0 para
  /// ESTE cajero, o retoma el turno que ese mismo cajero dejó abierto.
  ///
  /// Cada cajero retoma o abre SU turno. Los turnos de otros cajeros quedan
  /// intactos (no se cierran al entrar otro cajero).
  Future<SesionLoginResult> iniciarSesion(PosUsuario usuario,
      {String? pin}) async {
    if (usuario.pinHash != null && usuario.pinHash!.isNotEmpty) {
      if (pin == null || pin.isEmpty) return SesionLoginResult.pinIncorrecto;
      final ok = await ref.read(posRepoProvider)!.verificarPin(usuario.id, pin);
      if (!ok) return SesionLoginResult.pinIncorrecto;
    }

    final repo = ref.read(posRepoProvider)!;

    // Se retoma o abre el turno del cajero. NO se cierran turnos stale de forma
    // automática (>8h), para evitar "cierres fantasma": cada cajero cierra su
    // propio turno manualmente al finalizar su jornada.

    // Usuario desarrollador: inicia sesión SIN aperturar turno/caja
    // (`sesionId = 0` = sin turno). No hereda ni conflictúa con turnos ajenos.
    if (usuario.esDesarrollador) {
      state = PosSesionActiva(usuario: usuario, sesionId: 0);
      return SesionLoginResult.nueva;
    }

    final abierto = await repo.getSesionActivaDeUsuario(usuario.id);
    if (abierto != null) {
      // Turno del MISMO usuario abierto: retomarlo.
      state = PosSesionActiva(usuario: usuario, sesionId: abierto.sesion.id);
      return SesionLoginResult.retomada;
    }

    final sesionId = await repo.abrirSesion(usuario.id);
    state = PosSesionActiva(usuario: usuario, sesionId: sesionId);
    return SesionLoginResult.nueva;
  }

/// Cierra el turno y la caja (monto final automático) y vuelve al login.
/// Solo cierra el turno del cajero actual; los turnos de otros cajeros no se
/// ven afectados.
Future<void> cerrarSesion() async {
    final s = state;
    state = null;
    // `sesionId == 0` = sesión de desarrollador sin turno (nada que cerrar).
    if (s != null && s.sesionId > 0) {
      await ref.read(posRepoProvider)!.cerrarSesion(s.sesionId);
      // Invalidar proveedor de turnos activos para actualizar login
      ref.invalidate(turnosActivosProvider);
    }
  }

  /// Vuelve al login sin cerrar la sesión en BD (el turno de ESTE cajero queda
  /// abierto para retomarlo en el próximo login).
  void salirSinCerrar() {
    state = null;
  }
}
