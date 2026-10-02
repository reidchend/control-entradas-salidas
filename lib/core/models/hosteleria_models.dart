/// Modelos del módulo Hostelería (Lycoris Hosteleria).
///
/// Las habitaciones se leen de `pos_habitaciones` (las del POS); hostelería
/// agrega sus propias entidades: huéspedes y reservas/estancias.
library;

class HostelHuesped {
  const HostelHuesped({
    required this.id,
    required this.nombre,
    this.cedula,
    this.telefono,
    this.correo,
    this.notas,
    this.creadoEn,
    this.updatedAt,
  });

  final int id;
  final String nombre;
  final String? cedula;
  final String? telefono;
  final String? correo;
  final String? notas;
  final DateTime? creadoEn;
  final DateTime? updatedAt;

  factory HostelHuesped.fromMap(Map<String, dynamic> m) => HostelHuesped(
        id: m['id'] as int,
        nombre: m['nombre'] as String,
        cedula: m['cedula'] as String?,
        telefono: m['telefono'] as String?,
        correo: m['correo'] as String?,
        notas: m['notas'] as String?,
        creadoEn: _parseDt(m['creado_en']),
        updatedAt: _parseDt(m['updated_at']),
      );

  Map<String, dynamic> toMap() => {
        if (id > 0) 'id': id,
        'nombre': nombre,
        'cedula': cedula,
        'telefono': telefono,
        'correo': correo,
        'notas': notas,
      };

  static DateTime? _parseDt(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }
}

/// Estado de una reserva/estancia.
enum HostelReservaEstado {
  reservada,
  ocupada,
  cancelada,
  finalizada;

  static HostelReservaEstado fromDb(String v) => switch (v) {
        'ocupada' => HostelReservaEstado.ocupada,
        'cancelada' => HostelReservaEstado.cancelada,
        'finalizada' => HostelReservaEstado.finalizada,
        _ => HostelReservaEstado.reservada,
      };

  String toDb() => name;
}

class HostelReserva {
  const HostelReserva({
    required this.id,
    required this.habitacionId,
    required this.huespedId,
    required this.fechaIngreso,
    required this.fechaSalida,
    required this.estado,
    this.huespedNombre,
    this.habitacionNumero,
    this.notas,
    this.creadoEn,
    this.updatedAt,
  });

  final int id;
  final int habitacionId;
  final int huespedId;

  /// Fecha de ingreso (check-in).
  final DateTime fechaIngreso;

  /// Fecha de salida (check-out).
  final DateTime fechaSalida;
  final HostelReservaEstado estado;

  /// Nombres desnormalizados para tarjetas/listados (se llenan en queries
  /// con join cuando están disponibles).
  final String? huespedNombre;
  final String? habitacionNumero;
  final String? notas;
  final DateTime? creadoEn;
  final DateTime? updatedAt;

  /// Una reserva ocupa la habitación si no está cancelada/finalizada.
  bool get ocupaHabitacion =>
      estado == HostelReservaEstado.reservada ||
      estado == HostelReservaEstado.ocupada;

  factory HostelReserva.fromMap(Map<String, dynamic> m) => HostelReserva(
        id: m['id'] as int,
        habitacionId: m['habitacion_id'] as int,
        huespedId: m['huesped_id'] as int,
        fechaIngreso: _parseDate(m['fecha_inicio']) ?? DateTime.now(),
        fechaSalida: _parseDate(m['fecha_fin']) ?? DateTime.now(),
        estado: HostelReservaEstado.fromDb(m['estado'] as String),
        huespedNombre: m['huesped_nombre'] as String?,
        habitacionNumero: m['habitacion_numero'] as String?,
        notas: m['notas'] as String?,
        creadoEn: _parseDt(m['creado_en']),
        updatedAt: _parseDt(m['updated_at']),
      );

  Map<String, dynamic> toMap() => {
        if (id > 0) 'id': id,
        'habitacion_id': habitacionId,
        'huesped_id': huespedId,
        'fecha_inicio': _formatDateSql(fechaIngreso),
        'fecha_fin': _formatDateSql(fechaSalida),
        'estado': estado.toDb(),
        'notas': notas,
      };

  /// Formato `YYYY-MM-DD` para DATE de PostgreSQL.
  static String _formatDateSql(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  static DateTime? _parseDt(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }
}