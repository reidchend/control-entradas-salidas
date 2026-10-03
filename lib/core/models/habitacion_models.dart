/// Modelos de habitaciones.
///
/// Las habitaciones pertenecen al dominio de **Hostelería** (alquiler por
/// noche u horas). El POS de restaurante las reutiliza para guardar comandas,
/// pero su estado operativo (libre/aseo/mantenimiento) es de hostelería.
library;

/// Estado operativo de una habitación, independiente de las reservas.
///
/// El estado "ocupada"/"reservada" se deriva de `hosteleria_reservas`; este
/// valor aplica cuando la habitación NO tiene una estancia activa.
abstract final class EstadoHabitacion {
  static const libre = 'libre';
  static const aseo = 'aseo';
  static const mantenimiento = 'mantenimiento';

  static const opciones = [libre, aseo, mantenimiento];

  static String label(String? v) => switch (v) {
        aseo => 'Aseo',
        mantenimiento => 'Mantenimiento',
        _ => 'Libre',
      };
}

/// Habitación (tabla `habitaciones`, dominio Hostelería).
class Habitacion {
  const Habitacion({
    required this.id,
    required this.numero,
    this.piso,
    this.tipo,
    this.tipoId,
    this.capacidad,
    this.estado = EstadoHabitacion.libre,
    this.estadoNotas,
    this.activo = true,
    this.creadoEn,
    this.updatedAt,
  });

  final int id;
  final String numero;
  final String? piso;
  final String? tipo;
  final int? tipoId;

  /// Capacidad máxima de personas del tipo de habitación (si está definido).
  final int? capacidad;
  final String estado;
  final String? estadoNotas;
  final bool activo;
  final String? creadoEn;
  final DateTime? updatedAt;

  /// Máximo de personas a permitir en el check-in (mínimo 1).
  int get maxPersonas => (capacidad == null || capacidad! < 1) ? 1 : capacidad!;

  bool get enAseo => estado == EstadoHabitacion.aseo;
  bool get enMantenimiento => estado == EstadoHabitacion.mantenimiento;
  bool get operativaLibre => estado == EstadoHabitacion.libre;

  factory Habitacion.fromMap(Map<String, dynamic> m) => Habitacion(
        id: m['id'] as int,
        numero: m['numero'] as String,
        piso: m['piso'] as String?,
        tipo: (m['tipo_display'] as String?) ?? m['tipo'] as String?,
        tipoId: m['tipo_id'] as int?,
        capacidad: m['capacidad'] as int?,
        estado: (m['estado'] as String?) ?? EstadoHabitacion.libre,
        estadoNotas: m['estado_notas'] as String?,
        activo: (m['activo'] as int?) == 1,
        creadoEn: m['creado_en'] as String?,
        updatedAt: _parseDt(m['updated_at']),
      );

  Map<String, dynamic> toMap() => {
        if (id > 0) 'id': id,
        'numero': numero,
        'piso': piso,
        'tipo': tipo,
        'tipo_id': tipoId,
        'estado': estado,
        'estado_notas': estadoNotas,
        'activo': activo ? 1 : 0,
        'creado_en': creadoEn,
      };

  static DateTime? _parseDt(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }
}

/// Tipo de habitación del catálogo (`tipos_habitacion`) con su capacidad.
class TipoHabitacion {
  const TipoHabitacion({
    required this.id,
    required this.nombre,
    this.capacidad = 1,
    this.activo = true,
    this.creadoEn,
    this.updatedAt,
  });

  final int id;
  final String nombre;
  final int capacidad;
  final bool activo;
  final String? creadoEn;
  final DateTime? updatedAt;

  factory TipoHabitacion.fromMap(Map<String, dynamic> m) => TipoHabitacion(
        id: m['id'] as int,
        nombre: m['nombre'] as String,
        capacidad: (m['capacidad'] as int?) ?? 1,
        activo: (m['activo'] as int?) == 1,
        creadoEn: m['creado_en'] as String?,
        updatedAt: _parseDt(m['updated_at']),
      );

  Map<String, dynamic> toMap() => {
        if (id > 0) 'id': id,
        'nombre': nombre.trim(),
        'capacidad': capacidad,
        'activo': activo ? 1 : 0,
        'creado_en': creadoEn,
      };

  static DateTime? _parseDt(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }
}
