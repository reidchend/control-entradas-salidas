import '../../../core/data/postgres_service.dart';
import '../../../core/models/hosteleria_models.dart';
import '../../../core/models/pos_models.dart';

/// Repositorio del módulo Hostelería.
///
/// Lee habitaciones de `pos_habitaciones` (las del POS) y gestiona las tablas
/// propias: `hosteleria_huespedes` y `hosteleria_reservas`.
class HosteleriaRepository {
  HosteleriaRepository(this._db);

  final PostgresService _db;

  // -------------------------------------------------------------------
  // Habitaciones (pos_habitaciones — compartidas con el POS)
  // -------------------------------------------------------------------

  Future<List<PosHabitacion>> getHabitaciones({bool soloActivas = false}) async {
    var query = _db.client.from('pos_habitaciones').select();
    if (soloActivas) query = query.eq('activo', 1);
    final rows = await query.order('numero') as List<Map<String, dynamic>>;
    return rows.map(PosHabitacion.fromMap).toList();
  }

  // -------------------------------------------------------------------
  // Huéspedes
  // -------------------------------------------------------------------

  Future<HostelHuesped> saveHuesped({
    int? id,
    required String nombre,
    String? cedula,
    String? telefono,
    String? correo,
    String? notas,
  }) async {
    final data = {
      if (id != null && id > 0) 'id': id,
      'nombre': nombre.trim(),
      'cedula': cedula?.trim().isEmpty ?? true ? null : cedula!.trim(),
      'telefono': telefono?.trim().isEmpty ?? true ? null : telefono!.trim(),
      'correo': correo?.trim().isEmpty ?? true ? null : correo!.trim(),
      'notas': notas?.trim().isEmpty ?? true ? null : notas!.trim(),
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
      'JOIN pos_habitaciones hab ON hab.id = r.habitacion_id'
      '$where '
      'ORDER BY r.fecha_inicio DESC',
      params: params,
    );
    return rows.map(HostelReserva.fromMap).toList();
  }

  /// Reserva activa (no cancelada/finalizada) de una habitación, si existe.
  Future<HostelReserva?> getReservaActivaDeHabitacion(int habitacionId) async {
    final rows = await _db.executeSql(
      'SELECT r.*, h.nombre AS huesped_nombre, hab.numero AS habitacion_numero '
      'FROM hosteleria_reservas r '
      'JOIN hosteleria_huespedes h ON h.id = r.huesped_id '
      'JOIN pos_habitaciones hab ON hab.id = r.habitacion_id '
      'WHERE r.habitacion_id = \$1 '
      'AND r.estado IN (\'reservada\', \'ocupada\') '
      'ORDER BY r.fecha_inicio DESC LIMIT 1',
      params: [habitacionId],
    );
    if (rows.isEmpty) return null;
    return HostelReserva.fromMap(rows.first);
  }

  Future<HostelReserva> crearReserva({
    required int habitacionId,
    required HostelHuesped huesped,
    required DateTime fechaIngreso,
    required DateTime fechaSalida,
    String? notas,
  }) async {
    final newId = await _db.insert('hosteleria_reservas', HostelReserva(
      id: 0,
      habitacionId: habitacionId,
      huespedId: huesped.id,
      fechaIngreso: fechaIngreso,
      fechaSalida: fechaSalida,
      estado: HostelReservaEstado.reservada,
      notas: notas,
    ).toMap());
    return (await _getReservaById(newId))!;
  }

  Future<void> actualizarEstado(int reservaId, HostelReservaEstado estado) async {
    await _db.updateById('hosteleria_reservas', reservaId, {
      'estado': estado.toDb(),
    });
  }

  Future<void> cancelarReserva(int reservaId) =>
      actualizarEstado(reservaId, HostelReservaEstado.cancelada);

  Future<void> realizarCheckIn(int reservaId) =>
      actualizarEstado(reservaId, HostelReservaEstado.ocupada);

  Future<void> realizarCheckOut(int reservaId) =>
      actualizarEstado(reservaId, HostelReservaEstado.finalizada);

  Future<void> eliminarReserva(int reservaId) async {
    await _db.deleteById('hosteleria_reservas', reservaId);
  }

  Future<HostelReserva?> _getReservaById(int id) async {
    final rows = await _db.executeSql(
      'SELECT r.*, h.nombre AS huesped_nombre, hab.numero AS habitacion_numero '
      'FROM hosteleria_reservas r '
      'JOIN hosteleria_huespedes h ON h.id = r.huesped_id '
      'JOIN pos_habitaciones hab ON hab.id = r.habitacion_id '
      'WHERE r.id = \$1',
      params: [id],
    );
    if (rows.isEmpty) return null;
    return HostelReserva.fromMap(rows.first);
  }
}