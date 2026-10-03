/// Modelos del módulo Hostelería (Lycoris Hosteleria).
///
/// Las habitaciones se leen de `habitaciones` (las del POS); hostelería
/// agrega sus propias entidades: huéspedes, reservas/estancias, las personas
/// que ocupan la habitación y los vehículos asociados.
library;

/// Tipos de documento de identidad admitidos.
abstract final class DocumentoTipo {
  static const cedula = 'cedula';
  static const pasaporte = 'pasaporte';
  static const otro = 'otro';

  static const opciones = [cedula, pasaporte, otro];

  static String label(String? v) => switch (v) {
        pasaporte => 'Pasaporte',
        otro => 'Otro',
        _ => 'Cédula',
      };
}

/// Estados civiles (lista fija).
abstract final class EstadoCivil {
  static const soltero = 'Soltero/a';
  static const casado = 'Casado/a';
  static const divorciado = 'Divorciado/a';
  static const viudo = 'Viudo/a';
  static const unionLibre = 'Unión libre';

  static const opciones = [soltero, casado, divorciado, viudo, unionLibre];
}

class HostelHuesped {
  const HostelHuesped({
    required this.id,
    required this.nombre,
    this.apellido,
    this.tipoDocumento,
    this.numeroDocumento,
    this.fechaNacimiento,
    this.estadoCivil,
    this.nacionalidad,
    this.profesion,
    this.procedencia,
    this.destino,
    this.telefono,
    this.correo,
    this.notas,
    this.cedula,
    this.creadoEn,
    this.updatedAt,
  });

  final int id;
  final String nombre;
  final String? apellido;
  final String? tipoDocumento;
  final String? numeroDocumento;
  final DateTime? fechaNacimiento;
  final String? estadoCivil;
  final String? nacionalidad;
  final String? profesion;
  final String? procedencia;
  final String? destino;
  final String? telefono;
  final String? correo;
  final String? notas;

  /// Legado: columna `cedula` anterior al documento genérico.
  final String? cedula;
  final DateTime? creadoEn;
  final DateTime? updatedAt;

  String get nombreCompleto =>
      [nombre, apellido].where((s) => s != null && s.trim().isNotEmpty).join(' ');

  /// Documento mostrable (nuevo o legado).
  String? get documento =>
      (numeroDocumento != null && numeroDocumento!.isNotEmpty)
          ? numeroDocumento
          : cedula;

  factory HostelHuesped.fromMap(Map<String, dynamic> m) => HostelHuesped(
        id: m['id'] as int,
        nombre: m['nombre'] as String,
        apellido: m['apellido'] as String?,
        tipoDocumento: m['tipo_documento'] as String?,
        numeroDocumento: m['numero_documento'] as String?,
        fechaNacimiento: _parseDate(m['fecha_nacimiento']),
        estadoCivil: m['estado_civil'] as String?,
        nacionalidad: m['nacionalidad'] as String?,
        profesion: m['profesion'] as String?,
        procedencia: m['procedencia'] as String?,
        destino: m['destino'] as String?,
        telefono: m['telefono'] as String?,
        correo: m['correo'] as String?,
        notas: m['notas'] as String?,
        cedula: m['cedula'] as String?,
        creadoEn: _parseDt(m['creado_en']),
        updatedAt: _parseDt(m['updated_at']),
      );

  Map<String, dynamic> toMap() => {
        if (id > 0) 'id': id,
        'nombre': nombre,
        'apellido': apellido,
        'tipo_documento': tipoDocumento,
        'numero_documento': numeroDocumento,
        'fecha_nacimiento': _formatDateSql(fechaNacimiento),
        'estado_civil': estadoCivil,
        'nacionalidad': nacionalidad,
        'profesion': profesion,
        'procedencia': procedencia,
        'destino': destino,
        'telefono': telefono,
        'correo': correo,
        'notas': notas,
        'cedula': cedula,
      };

  static String? _formatDateSql(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  static DateTime? _parseDt(dynamic v) => _parseDate(v);
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

/// Modalidad de alquiler de una estancia.
enum ModalidadEstancia {
  /// Alquiler por noche (tarifa diaria).
  noche,

  /// Alquiler por bloque de horas ("Operativa" OP, típico 3 h).
  horas;

  static ModalidadEstancia fromDb(String? v) =>
      v == 'horas' ? ModalidadEstancia.horas : ModalidadEstancia.noche;

  String toDb() => name;

  String get label => this == ModalidadEstancia.horas ? 'Por horas (OP)' : 'Por noche';
}

class HostelReserva {
  const HostelReserva({
    required this.id,
    required this.habitacionId,
    required this.huespedId,
    required this.fechaIngreso,
    required this.fechaSalida,
    required this.estado,
    this.horaEntrada,
    this.horaSalida,
    this.modalidad = ModalidadEstancia.noche,
    this.bloqueHoras,
    this.horaLimite,
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

  /// Momento real del check-in / check-out.
  final DateTime? horaEntrada;
  final DateTime? horaSalida;

  /// Modalidad de alquiler (noche u horas) y bloque en horas para OP.
  final ModalidadEstancia modalidad;
  final int? bloqueHoras;

  /// Salida prevista para estancias por horas (check-in + bloque).
  final DateTime? horaLimite;

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

  bool get esPorHoras => modalidad == ModalidadEstancia.horas;

  /// Minutos que faltan para la hora límite (negativo si ya venció).
  int? minutosRestantes([DateTime? ahora]) {
    final limite = horaLimite;
    if (limite == null) return null;
    return limite.difference(ahora ?? DateTime.now()).inMinutes;
  }

  /// Etiqueta corta de la modalidad (ej: "OP 3 h" o "Noche").
  String get modalidadLabel {
    if (!esPorHoras) return 'Noche';
    return 'OP ${bloqueHoras ?? 3} h';
  }

  factory HostelReserva.fromMap(Map<String, dynamic> m) => HostelReserva(
        id: m['id'] as int,
        habitacionId: m['habitacion_id'] as int,
        huespedId: m['huesped_id'] as int,
        fechaIngreso: _parseDate(m['fecha_inicio']) ?? DateTime.now(),
        fechaSalida: _parseDate(m['fecha_fin']) ?? DateTime.now(),
        estado: HostelReservaEstado.fromDb(m['estado'] as String),
        horaEntrada: _parseDate(m['hora_entrada']),
        horaSalida: _parseDate(m['hora_salida']),
        modalidad: ModalidadEstancia.fromDb(m['modalidad'] as String?),
        bloqueHoras: m['bloque_horas'] as int?,
        horaLimite: _parseDate(m['hora_limite']),
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
        'modalidad': modalidad.toDb(),
        'bloque_horas': bloqueHoras,
        'hora_limite': horaLimite?.toIso8601String(),
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

  static DateTime? _parseDt(dynamic v) => _parseDate(v);
}

/// Una persona (titular o acompañante) vinculada a una estancia.
class HostelPersona {
  const HostelPersona({
    required this.id,
    required this.reservaId,
    required this.huespedId,
    required this.rol,
    this.huesped,
  });

  final int id;
  final int reservaId;
  final int huespedId;

  /// `titular` o `acompanante`.
  final String rol;
  final HostelHuesped? huesped;

  bool get esTitular => rol == 'titular';
  String get etiqueta => esTitular ? 'Titular' : 'Acompañante';

  factory HostelPersona.fromMap(Map<String, dynamic> m) => HostelPersona(
        id: m['id'] as int,
        reservaId: m['reserva_id'] as int,
        huespedId: m['huesped_id'] as int,
        rol: (m['rol'] as String?) ?? 'acompanante',
      );
}

/// Vehículo registrado en una estancia.
class HostelVehiculo {
  const HostelVehiculo({
    required this.id,
    required this.reservaId,
    required this.placa,
    this.modelo,
  });

  final int id;
  final int reservaId;
  final String placa;
  final String? modelo;

  factory HostelVehiculo.fromMap(Map<String, dynamic> m) => HostelVehiculo(
        id: m['id'] as int,
        reservaId: m['reserva_id'] as int,
        placa: m['placa'] as String,
        modelo: m['modelo'] as String?,
      );
}

/// Vehículo pendiente de guardar (entrada del formulario de check-in).
class HostelVehiculoInput {
  const HostelVehiculoInput({required this.placa, this.modelo});

  final String placa;
  final String? modelo;
}
