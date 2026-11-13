import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/pos_models.dart';
import 'pos_dispositivo.dart' as disp;
import 'pos_providers.dart';
import 'pos_repository.dart';
import 'pos_turno_models.dart';

/// Sesión activa del POS: usuario + turno compartido al que se unió.
class PosSesionActiva {
  const PosSesionActiva({
    required this.usuario,
    required this.sesionId,
    this.esAperturista = false,
    this.aperturistaNombre,
    this.participantes = const [],
  });

  final PosUsuario usuario;
  final int sesionId;

  /// El usuario actual abrió el turno (único que puede cerrarlo).
  final bool esAperturista;
  final String? aperturistaNombre;
  final List<ParticipanteTurno> participantes;

  bool get tieneTurno => sesionId > 0;

  /// Cobrar solo en la PC principal (Windows nativo con impresora).
  bool get puedeCobrar => disp.puedeCobrar;

  /// Cerrar: aperturista + PC principal.
  bool get puedeCerrarTurno => tieneTurno && disp.puedeCerrarTurno(esAperturista);
}

/// Resultado del intento de iniciar sesión / unirse a un turno.
enum SesionLoginResult {
  /// Se abrió un turno nuevo (el usuario queda como aperturista).
  nueva,

  /// Se retomó / unió al turno abierto existente.
  retomada,

  /// El PIN era incorrecto (no se hizo nada).
  pinIncorrecto,

  /// No hay turno abierto y este dispositivo no puede abrirlo (no es la PC
  /// principal). El Android debe esperar a que se abra desde la PC.
  sinTurno,

  /// No hay turno abierto y el dispositivo no es la PC principal.
  soloPcPrincipal,
}

/// Estado de la sesión del POS (turnos compartidos):
/// - Existe UN solo turno abierto a la vez, con un aperturista y varios
///   participantes. Cada usuario se une con su propio PIN.
/// - Abrir turno y cobrar solo se permite en la PC principal (Windows nativo
///   con impresora). Los Android solo se unen y operan.
/// - Cerrar el turno solo puede hacerlo quien lo abrió, desde la PC principal.
/// - Salir ("Cambiar usuario") no cierra el turno: solo marca `salio_en` del
///   participante. Las ventas y el cierre siguen agrupados por turno.
final posSessionProvider =
    NotifierProvider<PosSessionNotifier, PosSesionActiva?>(
        PosSessionNotifier.new);

class PosSessionNotifier extends Notifier<PosSesionActiva?> {
  DateTime? _ultimoToque;

  @override
  PosSesionActiva? build() => null;

  /// Valida el PIN (si el usuario lo tiene) y:
  /// - Si [sesionId] viene definido, se une a ESE turno.
  /// - Si no, se une al turno abierto; si no hay ninguno y este dispositivo es
  ///   la PC principal, abre uno nuevo.
  Future<SesionLoginResult> iniciarSesion(PosUsuario usuario,
      {String? pin, int? sesionId}) async {
    if (usuario.pinHash != null && usuario.pinHash!.isNotEmpty) {
      if (pin == null || pin.isEmpty) return SesionLoginResult.pinIncorrecto;
      final ok = await ref.read(posRepoProvider)!.verificarPin(usuario.id, pin);
      if (!ok) return SesionLoginResult.pinIncorrecto;
    }

    final repo = ref.read(posRepoProvider)!;

    // Usuario desarrollador: inicia sesión SIN turno/caja (`sesionId = 0`).
    if (usuario.esDesarrollador) {
      state = PosSesionActiva(usuario: usuario, sesionId: 0);
      return SesionLoginResult.nueva;
    }

    if (sesionId != null && sesionId > 0) {
      await repo.unirseATurno(sesionId, usuario.id);
      await _activar(repo, usuario, sesionId);
      return SesionLoginResult.retomada;
    }

    final abierto = await repo.getTurnoAbierto();
    if (abierto != null) {
      await repo.unirseATurno(abierto.id, usuario.id);
      await _activar(repo, usuario, abierto.id);
      return SesionLoginResult.retomada;
    }

    if (!disp.puedeAbrirTurno) return SesionLoginResult.soloPcPrincipal;

    final int nuevoId;
    try {
      nuevoId = await repo.abrirTurno(usuario.id,
          origen: disp.esPcPrincipal ? 'pc' : 'otro');
    } catch (e) {
      // Carrera: otra terminal abrió el turno entre la consulta y el alta.
      // El índice único lo impide; nos unimos al ganador.
      final existente = await repo.getTurnoAbierto();
      if (existente == null) rethrow;
      await repo.unirseATurno(existente.id, usuario.id);
      await _activar(repo, usuario, existente.id);
      return SesionLoginResult.retomada;
    }
    await _activar(repo, usuario, nuevoId);
    return SesionLoginResult.nueva;
  }

  /// Abre explícitamente un turno nuevo (botón "Abrir turno" de la vista
  /// Turnos). Falla si ya hay uno abierto.
  Future<SesionLoginResult> abrirTurno(PosUsuario usuario, {String? pin}) async {
    if (!disp.puedeAbrirTurno) return SesionLoginResult.soloPcPrincipal;
    return iniciarSesion(usuario, pin: pin);
  }

  /// Une al usuario al turno indicado desde la vista Turnos.
  Future<SesionLoginResult> unirseATurno(
    PosUsuario usuario,
    int sesionId, {
    String? pin,
  }) {
    return iniciarSesion(usuario, pin: pin, sesionId: sesionId);
  }

  Future<void> _activar(
    PosRepository repo,
    PosUsuario usuario,
    int sesionId,
  ) async {
    final participantes = await repo.getParticipantes(sesionId);
    final sesion = await repo.getSesionPorId(sesionId);
    final esAperturista = sesion?.usuarioId == usuario.id;
    String? nombreAperturista;
    for (final p in participantes) {
      if (p.esAperturista) {
        nombreAperturista = p.nombre;
        break;
      }
    }
    nombreAperturista ??=
        await repo.getUsuarioNombre(sesion?.usuarioId ?? usuario.id);
    _ultimoToque = DateTime.now();
    state = PosSesionActiva(
      usuario: usuario,
      sesionId: sesionId,
      esAperturista: esAperturista,
      aperturistaNombre: nombreAperturista,
      participantes: participantes,
    );
  }

  /// Cierra la sesión local del POS y vuelve al login.
  /// El turno/caja ya fue cerrado y persistido atómicamente en la transacción
  /// de cierre (`posRepoProvider.finalizarCierreYTurno`); aquí solo se limpia
  /// el estado local y se invalidan los turnos activos.
  /// `sesionId == 0` = sesión de desarrollador sin turno (nada que cerrar).
  Future<void> cerrarSesion() async {
    final s = state;
    state = null;
    _ultimoToque = null;
    if (s != null && s.sesionId > 0) {
      ref.invalidate(turnoAbiertoProvider);
      ref.invalidate(usuariosEnTurnoProvider);
      ref.invalidate(ventasSesionActualProvider);
    }
  }

  /// Sale del turno sin cerrarlo (Cambiar usuario). El turno queda abierto
  /// para que otro usuario se una o para retomarlo más tarde.
  Future<void> salirDelTurno() async {
    final s = state;
    state = null;
    _ultimoToque = null;
    if (s == null || s.sesionId <= 0) return;
    final repo = ref.read(posRepoProvider);
    try {
      await repo?.salirTurno(s.sesionId, s.usuario.id);
    } catch (_) {
      // Si falla la marca de salida no bloqueamos el cambio de usuario: el
      // turno sigue abierto y el heartbeat dejará de actualizarse.
    }
    ref.invalidate(turnoAbiertoProvider);
    ref.invalidate(usuariosEnTurnoProvider);
    ref.invalidate(ventasSesionActualProvider);
  }

  /// Revalida contra BD que el turno siga abierto. Si OTRO dispositivo lo
  /// cerró, cierra la sesión local y vuelve al login: así la terminal deja de
  /// operar con un turno cerrado (sus ventas quedarían huérfanas).
  ///
  /// También manda un heartbeat al participante (máx. 1 vez por minuto).
  ///
  /// Devuelve `false` si la sesión local fue cerrada por esta revalidación.
  Future<bool> revalidarSesion() async {
    final s = state;
    if (s == null || s.sesionId <= 0) return true;
    final repo = ref.read(posRepoProvider);
    if (repo == null) return true;
    final abierta = await repo.sesionAbierta(s.sesionId);
    if (!abierta) {
      await cerrarSesion();
      return false;
    }
    final ahora = DateTime.now();
    final ultimo = _ultimoToque;
    if (ultimo == null || ahora.difference(ultimo).inSeconds >= 60) {
      _ultimoToque = ahora;
      try {
        await repo.tocarParticipante(s.sesionId, s.usuario.id);
      } catch (_) {
        // Heartbeat best-effort: no debe romper la operación del POS.
      }
    }
    return true;
  }
}
