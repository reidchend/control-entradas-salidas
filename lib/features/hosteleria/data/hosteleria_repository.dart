import '../../../core/data/postgres_service.dart';
import '../../../core/models/hosteleria_models.dart';
import '../../../core/models/pos_models.dart';

/// Repositorio del módulo Hostelería.
///
/// Lee habitaciones de `habitaciones` (las del POS) y gestiona las tablas
/// propias: `hosteleria_huespedes`, `hosteleria_reservas`,
/// `hosteleria_reserva_personas` y `hosteleria_vehiculos`.
class HosteleriaRepository {
  HosteleriaRepository(this._db);

  final PostgresService _db;

  // -------------------------------------------------------------------
  // Habitaciones (habitaciones — compartidas con el POS)
  // -------------------------------------------------------------------

  static const String _selectHabitacion = '''
    SELECT h.id, h.numero, h.piso, h.tipo, h.tipo_id, h.activo, h.creado_en,
           h.updated_at, h.estado, h.estado_notas,
           COALESCE(t.nombre, h.tipo) AS tipo_display,
           t.capacidad AS capacidad
      FROM habitaciones h
      LEFT JOIN tipos_habitacion t ON t.id = h.tipo_id
  ''';

  Future<List<Habitacion>> getHabitaciones({bool soloActivas = false}) async {
    final rows = await _db.executeSql(
      '$_selectHabitacion${soloActivas ? ' WHERE h.activo = 1' : ''} '
      'ORDER BY h.numero',
    );
    return rows.map(Habitacion.fromMap).toList();
  }

  Future<Habitacion?> getHabitacionById(int habitacionId) async {
    final rows = await _db.executeSql(
      '$_selectHabitacion WHERE h.id = \$1 LIMIT 1',
      params: [habitacionId],
    );
    return rows.isEmpty ? null : Habitacion.fromMap(rows.first);
  }

  /// Cambia el estado operativo de la habitación (libre/aseo/mantenimiento).
  Future<void> setEstadoHabitacion(
    int habitacionId,
    String estado, {
    String? notas,
  }) async {
    await _db.updateById('habitaciones', habitacionId, {
      'estado': estado,
      'estado_notas': _limpiar(notas),
      'estado_actualizado_en': DateTime.now().toIso8601String(),
    });
  }

  /// Marca la habitación como limpia y disponible.
  Future<void> marcarLimpia(int habitacionId) =>
      setEstadoHabitacion(habitacionId, EstadoHabitacion.libre);

  /// Envía la habitación a aseo (limpieza pendiente).
  Future<void> enviarAAseo(int habitacionId, {String? notas}) =>
      setEstadoHabitacion(habitacionId, EstadoHabitacion.aseo, notas: notas);

  /// Pone la habitación en mantenimiento (no vendible).
  Future<void> ponerEnMantenimiento(int habitacionId, {String? notas}) =>
      setEstadoHabitacion(habitacionId, EstadoHabitacion.mantenimiento,
          notas: notas);

  // -------------------------------------------------------------------
  // Huéspedes
  // -------------------------------------------------------------------

  Future<HostelHuesped> saveHuesped({
    int? id,
    required String nombre,
    String? apellido,
    String? tipoDocumento,
    String? numeroDocumento,
    DateTime? fechaNacimiento,
    String? estadoCivil,
    String? nacionalidad,
    String? profesion,
    String? procedencia,
    String? destino,
    String? telefono,
    String? correo,
    String? notas,
  }) async {
    final numDoc = _limpiar(numeroDocumento);
    final esCedula = tipoDocumento == DocumentoTipo.cedula;
    final data = {
      if (id != null && id > 0) 'id': id,
      'nombre': nombre.trim(),
      'apellido': _limpiar(apellido),
      'tipo_documento': _limpiar(tipoDocumento),
      'numero_documento': numDoc,
      'fecha_nacimiento': _fechaSql(fechaNacimiento),
      'estado_civil': _limpiar(estadoCivil),
      'nacionalidad': _limpiar(nacionalidad),
      'profesion': _limpiar(profesion),
      'procedencia': _limpiar(procedencia),
      'destino': _limpiar(destino),
      'telefono': _limpiar(telefono),
      'correo': _limpiar(correo),
      'notas': _limpiar(notas),
      if (esCedula) 'cedula': numDoc,
    };
    if (id != null && id > 0) {
      await _db.updateById('hosteleria_huespedes', id, data);
      return (await getHuespedById(id))!;
    }
    final newId = await _db.insert('hosteleria_huespedes', data);
    return (await getHuespedById(newId))!;
  }

  Future<HostelHuesped?> getHuespedById(int id) async {
    final row = await _db.fetchById('hosteleria_huespedes', id);
    return row == null ? null : HostelHuesped.fromMap(row);
  }

  Future<List<HostelHuesped>> buscarHuespedes({String? q}) async {
    final rows = await _db.fetchAll(
      'hosteleria_huespedes',
      orderBy: 'nombre',
      search: q,
      searchColumn: 'nombre',
    );
    return rows.map(HostelHuesped.fromMap).toList();
  }

  // -------------------------------------------------------------------
  // Reservas / estancias
  // -------------------------------------------------------------------

  /// Reservas JOIN huésped + habitación para mostrar nombres en tarjetas.
  Future<List<HostelReserva>> getReservas({String? estado}) async {
    final params = <dynamic>[];
    var where = '';
    if (estado != null) {
      where = ' WHERE r.estado = \$1';
      params.add(estado);
    }
    final rows = await _db.executeSql(
      'SELECT r.*, h.nombre AS huesped_nombre, hab.numero AS habitacion_numero '
      'FROM hosteleria_reservas r '
      'JOIN hosteleria_huespedes h ON h.id = r.huesped_id '
      'JOIN habitaciones hab ON hab.id = r.habitacion_id'
      '$where '
      'ORDER BY r.fecha_inicio DESC',
      params: params,
    );
    return rows.map(HostelReserva.fromMap).toList();
  }

  /// Reservas no canceladas que solapan un rango de fechas (vistas semana/mes).
  /// Incluye finalizadas para mostrar el historial de ocupación.
  Future<List<HostelReserva>> getReservasEnRango(
    DateTime desde,
    DateTime hasta,
  ) async {
    final rows = await _db.executeSql(
      'SELECT r.*, h.nombre AS huesped_nombre, hab.numero AS habitacion_numero '
      'FROM hosteleria_reservas r '
      'JOIN hosteleria_huespedes h ON h.id = r.huesped_id '
      'JOIN habitaciones hab ON hab.id = r.habitacion_id '
      'WHERE r.estado <> \'cancelada\' '
      'AND r.fecha_inicio <= \$1 AND r.fecha_fin >= \$2 '
      'ORDER BY r.fecha_inicio',
      params: [_fechaSql(hasta), _fechaSql(desde)],
    );
    return rows.map(HostelReserva.fromMap).toList();
  }

  /// Reserva activa (no cancelada/finalizada) de una habitación, si existe.
  Future<HostelReserva?> getReservaActivaDeHabitacion(int habitacionId) async {
    final rows = await _db.executeSql(
      'SELECT r.*, h.nombre AS huesped_nombre, hab.numero AS habitacion_numero '
      'FROM hosteleria_reservas r '
      'JOIN hosteleria_huespedes h ON h.id = r.huesped_id '
      'JOIN habitaciones hab ON hab.id = r.habitacion_id '
      'WHERE r.habitacion_id = \$1 '
      'AND r.estado IN (\'reservada\', \'ocupada\') '
      'ORDER BY r.fecha_inicio DESC LIMIT 1',
      params: [habitacionId],
    );
    if (rows.isEmpty) return null;
    return HostelReserva.fromMap(rows.first);
  }

  /// Crea una estancia con titular + acompañantes + vehículos.
  ///
  /// Si [ocupar] es `true` (check-in directo) la reserva nace en estado
  /// `ocupada` con [horaEntrada] = ahora; si no, queda `reservada`.
  /// [capacidadMax] limita el total de personas (titular + acompañantes).
  Future<HostelReserva> crearEstancia({
    required int habitacionId,
    required DateTime fechaIngreso,
    required DateTime fechaSalida,
    required HostelHuesped titular,
    List<HostelHuesped> acompanantes = const [],
    List<HostelVehiculoInput> vehiculos = const [],
    required int capacidadMax,
    bool ocupar = false,
    ModalidadEstancia modalidad = ModalidadEstancia.noche,
    int? bloqueHoras,
    String? notas,
  }) async {
    _validarCapacidad(1 + acompanantes.length, capacidadMax);
    final ahora = DateTime.now();
    final esHoras = modalidad == ModalidadEstancia.horas;
    final horas = (bloqueHoras == null || bloqueHoras < 1) ? 3 : bloqueHoras;
    final newId = await _db.transaction((tx) async {
      final reservaId = await tx.insert('hosteleria_reservas', {
        'habitacion_id': habitacionId,
        'huesped_id': titular.id,
        'fecha_inicio': _fechaSql(fechaIngreso),
        'fecha_fin': _fechaSql(fechaSalida),
        'estado': ocupar ? 'ocupada' : 'reservada',
        'hora_entrada': ocupar ? ahora.toIso8601String() : null,
        'modalidad': modalidad.toDb(),
        'bloque_horas': esHoras ? horas : null,
        'hora_limite': (ocupar && esHoras)
            ? ahora.add(Duration(hours: horas)).toIso8601String()
            : null,
        'notas': _limpiar(notas),
      });
      await _insertPersonas(tx, reservaId, titular, acompanantes);
      await _insertVehiculos(tx, reservaId, vehiculos);
      return reservaId;
    });
    return (await _getReservaById(newId))!;
  }

  /// Completa el check-in de una reserva existente: actualiza el titular,
  /// agrega acompañantes/vehículos y pasa la reserva a `ocupada` con la hora
  /// de entrada actual.
  Future<HostelReserva> realizarCheckInCompleto({
    required int reservaId,
    required HostelHuesped titular,
    List<HostelHuesped> acompanantes = const [],
    List<HostelVehiculoInput> vehiculos = const [],
    required int capacidadMax,
    ModalidadEstancia modalidad = ModalidadEstancia.noche,
    int? bloqueHoras,
  }) async {
    _validarCapacidad(1 + acompanantes.length, capacidadMax);
    final ahora = DateTime.now();
    final esHoras = modalidad == ModalidadEstancia.horas;
    final horas = (bloqueHoras == null || bloqueHoras < 1) ? 3 : bloqueHoras;
    await _db.transaction((tx) async {
      await tx.updateById('hosteleria_reservas', reservaId, {
        'huesped_id': titular.id,
        'estado': 'ocupada',
        'hora_entrada': ahora.toIso8601String(),
        'modalidad': modalidad.toDb(),
        'bloque_horas': esHoras ? horas : null,
        'hora_limite':
            esHoras ? ahora.add(Duration(hours: horas)).toIso8601String() : null,
      });
      await tx.executeCommand(
        'DELETE FROM hosteleria_reserva_personas WHERE reserva_id = \$1',
        params: [reservaId],
      );
      await tx.executeCommand(
        'DELETE FROM hosteleria_vehiculos WHERE reserva_id = \$1',
        params: [reservaId],
      );
      await _insertPersonas(tx, reservaId, titular, acompanantes);
      await _insertVehiculos(tx, reservaId, vehiculos);
    });
    return (await _getReservaById(reservaId))!;
  }

  Future<void> actualizarEstado(int reservaId, HostelReservaEstado estado) async {
    await _db.updateById('hosteleria_reservas', reservaId, {
      'estado': estado.toDb(),
    });
  }

  Future<void> cancelarReserva(int reservaId) =>
      actualizarEstado(reservaId, HostelReservaEstado.cancelada);

  Future<void> realizarCheckIn(int reservaId) async {
    await _db.updateById('hosteleria_reservas', reservaId, {
      'estado': 'ocupada',
      'hora_entrada': DateTime.now().toIso8601String(),
    });
  }

  /// Check-out: finaliza la reserva y deja la habitación en `aseo`.
  Future<void> realizarCheckOut(int reservaId, {int? habitacionId}) async {
    var habId = habitacionId;
    habId ??= (await _getReservaById(reservaId))?.habitacionId;
    final ahora = DateTime.now();
    await _db.transaction((tx) async {
      await tx.updateById('hosteleria_reservas', reservaId, {
        'estado': 'finalizada',
        'hora_salida': ahora.toIso8601String(),
      });
      if (habId != null) {
        await tx.updateById('habitaciones', habId, {
          'estado': EstadoHabitacion.aseo,
          'estado_notas': null,
          'estado_actualizado_en': ahora.toIso8601String(),
        });
      }
    });
  }

  Future<void> eliminarReserva(int reservaId) async {
    await _db.deleteById('hosteleria_reservas', reservaId);
  }

  Future<List<HostelPersona>> getPersonasDeReserva(int reservaId) async {
    final rows = await _db.executeSql(
      'SELECT p.id AS persona_id, p.reserva_id, p.huesped_id, p.rol, h.* '
      'FROM hosteleria_reserva_personas p '
      'JOIN hosteleria_huespedes h ON h.id = p.huesped_id '
      'WHERE p.reserva_id = \$1 '
      "ORDER BY CASE p.rol WHEN 'titular' THEN 0 ELSE 1 END, h.nombre",
      params: [reservaId],
    );
    return [
      for (final r in rows)
        HostelPersona(
          id: r['persona_id'] as int,
          reservaId: r['reserva_id'] as int,
          huespedId: r['huesped_id'] as int,
          rol: r['rol'] as String,
          huesped: HostelHuesped.fromMap(r),
        ),
    ];
  }

  Future<List<HostelVehiculo>> getVehiculosDeReserva(int reservaId) async {
    final rows = await _db.executeSql(
      'SELECT * FROM hosteleria_vehiculos WHERE reserva_id = \$1 '
      'ORDER BY id',
      params: [reservaId],
    );
    return rows.map(HostelVehiculo.fromMap).toList();
  }

  Future<HostelReserva?> _getReservaById(int id) async {
    final rows = await _db.executeSql(
      'SELECT r.*, h.nombre AS huesped_nombre, hab.numero AS habitacion_numero '
      'FROM hosteleria_reservas r '
      'JOIN hosteleria_huespedes h ON h.id = r.huesped_id '
      'JOIN habitaciones hab ON hab.id = r.habitacion_id '
      'WHERE r.id = \$1',
      params: [id],
    );
    if (rows.isEmpty) return null;
    return HostelReserva.fromMap(rows.first);
  }

  // -------------------------------------------------------------------
  // Helpers internos
  // -------------------------------------------------------------------

  Future<void> _insertPersonas(
    PostgresService tx,
    int reservaId,
    HostelHuesped titular,
    List<HostelHuesped> acompanantes,
  ) async {
    await tx.insert('hosteleria_reserva_personas', {
      'reserva_id': reservaId,
      'huesped_id': titular.id,
      'rol': 'titular',
    });
    for (final a in acompanantes) {
      await tx.insert('hosteleria_reserva_personas', {
        'reserva_id': reservaId,
        'huesped_id': a.id,
        'rol': 'acompanante',
      });
    }
  }

  Future<void> _insertVehiculos(
    PostgresService tx,
    int reservaId,
    List<HostelVehiculoInput> vehiculos,
  ) async {
    for (final v in vehiculos) {
      if (v.placa.trim().isEmpty) continue;
      await tx.insert('hosteleria_vehiculos', {
        'reserva_id': reservaId,
        'placa': v.placa.trim().toUpperCase(),
        'modelo': _limpiar(v.modelo),
      });
    }
  }

  void _validarCapacidad(int personas, int capacidadMax) {
    if (capacidadMax > 0 && personas > capacidadMax) {
      throw Exception(
        'La habitación permite máximo $capacidadMax persona(s) '
        'y se intentó registrar $personas.',
      );
    }
  }

  static String? _limpiar(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  static String? _fechaSql(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
}
