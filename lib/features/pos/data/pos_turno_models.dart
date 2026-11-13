import '../../../core/models/pos_models.dart';

/// Usuario que participa de un turno compartido del POS.
///
/// `salioEn == null` significa que sigue dentro del turno (aunque puede estar
/// desconectado); `ultimaActividadEn` sirve para pintar el estado "en línea".
class ParticipanteTurno {
  const ParticipanteTurno({
    required this.usuarioId,
    required this.nombre,
    this.esAperturista = false,
    this.unidoEn,
    this.ultimaActividadEn,
    this.salioEn,
    this.ventas = 0,
    this.total = 0,
    this.comandas = 0,
  });

  final int usuarioId;
  final String nombre;

  /// Abrió el turno. Solo esta persona puede cerrarlo (desde la PC principal).
  final bool esAperturista;
  final String? unidoEn;
  final String? ultimaActividadEn;
  final String? salioEn;

  /// Ventas vigentes atribuidas a este usuario dentro del turno.
  final int ventas;
  final double total;
  final int comandas;

  /// Sigue dentro del turno (no eligió "Cambiar usuario").
  bool get enTurno => salioEn == null;

  /// Actividad reciente (heartbeat del polling). Sirve solo como indicador.
  bool get enLinea {
    final v = ultimaActividadEn;
    if (v == null || !enTurno) return false;
    final dt = DateTime.tryParse(v);
    if (dt == null) return false;
    return DateTime.now().difference(dt).inMinutes < 5;
  }
}

/// Turno abierto con su aperturista y participantes.
class TurnoAbierto {
  const TurnoAbierto({
    required this.sesion,
    required this.aperturistaNombre,
    this.participantes = const [],
    this.ventas = 0,
    this.totalVentas = 0,
  });

  final PosSesion sesion;
  final String aperturistaNombre;
  final List<ParticipanteTurno> participantes;
  final int ventas;
  final double totalVentas;

  int get id => sesion.id;
  String? get abiertaEn => sesion.abiertaEn;

  /// IDs de los usuarios que están dentro del turno.
  Set<int> get usuariosEnTurno => {
        for (final p in participantes)
          if (p.enTurno) p.usuarioId,
      };
}

/// Resumen de un turno cerrado para las listas del login.
typedef TurnoCerradoResumen = ({
  PosSesion sesion,
  String? usuarioNombre,
  int ventas,
  double totalVentas,
});
