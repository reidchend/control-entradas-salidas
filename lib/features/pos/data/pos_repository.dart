import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../../core/data/postgres_service.dart';
import '../../../core/models/categoria.dart';
import '../../../core/models/pos_cierre_models.dart';
import '../../../core/models/pos_models.dart';
import '../../../core/models/producto.dart';
import 'pos_comanda_models.dart';
import 'pos_turno_models.dart';
import 'pos_ventas_repository.dart';

class PosRepository {
  PosRepository(this._db);

  final PostgresService _db;

  static const Uuid _uuid = Uuid();

  static String _pinHash(String pin) =>
      sha256.convert(utf8.encode(pin.trim())).toString();

  // Settings

  Future<String?> getSetting(String key) async {
    final rows = await _db.client
        .from('pos_settings')
        .select('value')
        .eq('key', key)
        .limit(1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    await _db.client.from('pos_settings').upsert(
      {'key': key, 'value': value},
      onConflict: 'key',
    );
  }

  // Sesiones / turnos compartidos / caja
  //
  // Un turno puede tener VARIOS usuarios. `pos_sesiones.usuario_id` es quien
  // lo abrió (aperturista) y `pos_turno_participantes` guarda quiénes entraron.
  // Solo puede existir un turno abierto a la vez (índice único en BD).

  /// Turno abierto actual (o `null` si no hay ninguno).
  Future<PosSesion?> getTurnoAbierto() async {
    final rows = await _db.client
        .from('pos_sesiones')
        .select()
        .isFilter('cerrada_en', null)
        .order('abierta_en', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    return PosSesion.fromMap(rows.first);
  }

  /// Turno por id, esté abierto o cerrado (para pantallas de cierre/detalle).
  Future<PosSesion?> getSesionPorId(int sesionId) async {
    final rows = await _db.client
        .from('pos_sesiones')
        .select()
        .eq('id', sesionId)
        .limit(1);
    if (rows.isEmpty) return null;
    return PosSesion.fromMap(rows.first);
  }

  /// Turno abierto con aperturista, participantes y totales del turno.
  Future<TurnoAbierto?> getTurnoAbiertoDetalle() async {
    final sesion = await getTurnoAbierto();
    if (sesion == null) return null;
    final participantes = await getParticipantes(sesion.id);
    final resumen = await _db.executeSql(
      'SELECT COUNT(*) AS ventas, COALESCE(SUM(total), 0) AS total '
      'FROM pos_ventas WHERE sesion_id = \$1 AND estado = \$2',
      params: [sesion.id, 'vigente'],
    );
    final ventas = resumen.isEmpty
        ? 0
        : ((resumen.first['ventas'] as num?) ?? 0).toInt();
    final total = resumen.isEmpty
        ? 0.0
        : ((resumen.first['total'] as num?) ?? 0).toDouble();
    return TurnoAbierto(
      sesion: sesion,
      aperturistaNombre:
          await getUsuarioNombre(sesion.usuarioId) ?? 'Desconocido',
      participantes: participantes,
      ventas: ventas,
      totalVentas: total,
    );
  }

  /// Abre un turno nuevo con [usuarioId] como aperturista y participante.
  ///
  /// Falla si ya hay un turno abierto (la BD también lo impide con un índice
  /// único parcial).
  Future<int> abrirTurno(
    int usuarioId, {
    String origen = 'pc',
    double cajaInicial = 0,
  }) async {
    final now = DateTime.now().toIso8601String();
    return _db.transaction<int>((tx) async {
      final abiertos = await tx.client
          .from('pos_sesiones')
          .select('id')
          .isFilter('cerrada_en', null)
          .limit(1);
      if (abiertos.isNotEmpty) {
        throw Exception(
            'Ya hay un turno abierto. Únase a él en vez de abrir uno nuevo.');
      }
      final sesionId = await tx.insert('pos_sesiones', {
        'usuario_id': usuarioId,
        'abierta_en': now,
        'caja_inicial': cajaInicial,
        'origen_apertura': origen,
        'sync_uuid': _uuid.v4(),
        'created_at': now,
        'updated_at': now,
      });
      await tx.insert('pos_turno_participantes', {
        'sesion_id': sesionId,
        'usuario_id': usuarioId,
        'unido_en': now,
        'ultima_actividad_en': now,
        'created_at': now,
        'updated_at': now,
      });
      return sesionId;
    });
  }

  /// Incorpora (o reincorpora) a [usuarioId] al turno [sesionId]. Idempotente:
  /// si ya era participante, limpia `salio_en` y actualiza la actividad.
  Future<void> unirseATurno(int sesionId, int usuarioId) async {
    final now = DateTime.now().toIso8601String();
    await _db.transaction((tx) async {
      final rows = await tx.client
          .from('pos_sesiones')
          .select('id')
          .eq('id', sesionId)
          .isFilter('cerrada_en', null)
          .limit(1);
      if (rows.isEmpty) {
        throw Exception('El turno ya fue cerrado. Vuelva a iniciar sesión.');
      }
      await tx.executeCommand(
        'INSERT INTO pos_turno_participantes '
        '(sesion_id, usuario_id, unido_en, ultima_actividad_en, salio_en, '
        'created_at, updated_at) '
        'VALUES (\$1, \$2, \$3, \$3, NULL, \$3, \$3) '
        'ON CONFLICT (sesion_id, usuario_id) DO UPDATE SET '
        'salio_en = NULL, '
        'ultima_actividad_en = EXCLUDED.ultima_actividad_en, '
        'updated_at = EXCLUDED.updated_at',
        params: [sesionId, usuarioId, now],
      );
    });
  }

  /// Marca que [usuarioId] salió del turno sin cerrarlo (Cambiar usuario).
  Future<void> salirTurno(int sesionId, int usuarioId) async {
    final now = DateTime.now().toIso8601String();
    await _db.executeCommand(
      'UPDATE pos_turno_participantes SET salio_en = \$1, updated_at = \$1 '
      'WHERE sesion_id = \$2 AND usuario_id = \$3',
      params: [now, sesionId, usuarioId],
    );
  }

  /// Heartbeat liviano del participante (se llama desde el polling).
  Future<void> tocarParticipante(int sesionId, int usuarioId) async {
    final now = DateTime.now().toIso8601String();
    await _db.executeCommand(
      'UPDATE pos_turno_participantes '
      'SET ultima_actividad_en = \$1, updated_at = \$1 '
      'WHERE sesion_id = \$2 AND usuario_id = \$3 AND salio_en IS NULL',
      params: [now, sesionId, usuarioId],
    );
  }

  Future<String?> getUsuarioNombre(int usuarioId) async {
    final rows = await _db.client
        .from('usuarios')
        .select('nombre')
        .eq('id', usuarioId)
        .limit(1);
    if (rows.isEmpty) return null;
    return rows.first['nombre'] as String?;
  }

  /// Participantes del turno con sus ventas vigentes y comandas creadas.
  Future<List<ParticipanteTurno>> getParticipantes(int sesionId) async {
    final sesion = await getSesionPorId(sesionId);
    if (sesion == null) return const [];
    return _participantesConVentas(_db, sesionId, sesion.usuarioId);
  }

  Future<List<ParticipanteTurno>> _participantesConVentas(
    PostgresService db,
    int sesionId,
    int aperturistaId,
  ) async {
    final rows = await db.client
        .from('pos_turno_participantes')
        .select()
        .eq('sesion_id', sesionId);
    if (rows.isEmpty) return const [];

    final uids = <int>{
      for (final r in rows) r['usuario_id'] as int,
    }.toList();
    final nombrePorId = <int, String>{};
    final usuarios = await db.client
        .from('usuarios')
        .select('id, nombre')
        .inFilter('id', uids);
    for (final u in usuarios) {
      nombrePorId[u['id'] as int] = u['nombre'] as String? ?? 'Usuario';
    }

    final ventasPorId = <int, ({int ventas, double total})>{};
    final ventas = await db.executeSql(
      'SELECT usuario_id, COUNT(*) AS ventas, COALESCE(SUM(total), 0) AS total '
      'FROM pos_ventas WHERE sesion_id = \$1 AND estado = \$2 '
      'GROUP BY usuario_id',
      params: [sesionId, 'vigente'],
    );
    for (final v in ventas) {
      final uid = (v['usuario_id'] as num?)?.toInt();
      if (uid == null) continue;
      ventasPorId[uid] = (
        ventas: ((v['ventas'] as num?) ?? 0).toInt(),
        total: ((v['total'] as num?) ?? 0).toDouble(),
      );
    }

    final comandasPorId = <int, int>{};
    final comandas = await db.executeSql(
      'SELECT usuario_id, COUNT(*) AS comandas FROM pos_comandas '
      'WHERE sesion_id = \$1 AND usuario_id IS NOT NULL '
      'GROUP BY usuario_id',
      params: [sesionId],
    );
    for (final c in comandas) {
      final uid = (c['usuario_id'] as num?)?.toInt();
      if (uid == null) continue;
      comandasPorId[uid] = ((c['comandas'] as num?) ?? 0).toInt();
    }

    final result = <ParticipanteTurno>[];
    for (final r in rows) {
      final uid = r['usuario_id'] as int;
      final v = ventasPorId[uid];
      result.add(ParticipanteTurno(
        usuarioId: uid,
        nombre: nombrePorId[uid] ?? 'Usuario $uid',
        esAperturista: uid == aperturistaId,
        unidoEn: r['unido_en'] as String?,
        ultimaActividadEn: r['ultima_actividad_en'] as String?,
        salioEn: r['salio_en'] as String?,
        ventas: v?.ventas ?? 0,
        total: v?.total ?? 0,
        comandas: comandasPorId[uid] ?? 0,
      ));
    }
    result.sort((a, b) {
      if (a.esAperturista != b.esAperturista) return a.esAperturista ? -1 : 1;
      return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
    });
    return result;
  }

  Future<double> _totalVigenteDeSesion(int sesionId) async {
    final rows = await _db.client
        .from('pos_ventas')
        .select('total')
        .eq('sesion_id', sesionId)
        .eq('estado', 'vigente') as List<Map<String, dynamic>>;
    return rows.fold<double>(
        0, (sum, r) => sum + (r['total'] as num? ?? 0).toDouble());
  }

  /// Turnos cerrados paginados con el resumen de ventas de cada uno.
Future<List<TurnoCerradoResumen>>
    getSesiones({int limit = 50, int? beforeId}) async {
    var query = _db.client.from('pos_sesiones').select();
    if (beforeId != null) query = query.lt('id', beforeId);
    final sesiones = await query.order('id', ascending: false).limit(limit);

    final sids = <int>[for (final s in sesiones) s['id'] as int];
    // Resumir ventas solo para las sesiones de la página (no escanear todas
    // las pos_ventas en cada paginación).
    final resumenMap = <int, ({int ventas, double total})>{};
    if (sids.isNotEmpty) {
      final ventRows = await _db.client
          .from('pos_ventas')
          .select('sesion_id, total')
          .eq('estado', 'vigente')
          .inFilter('sesion_id', sids);
      for (final v in ventRows) {
        final sid = v['sesion_id'] as int;
        final prev = resumenMap[sid] ?? (ventas: 0, total: 0.0);
        resumenMap[sid] = (
          ventas: prev.ventas + 1,
          total: prev.total + (v['total'] as num? ?? 0).toDouble(),
        );
      }
    }

    // Nombres de cajeros en una sola query.
    final uids = {for (final s in sesiones) s['usuario_id'] as int};
    final uidMap = <int, String>{};
    if (uids.isNotEmpty) {
      final urows = await _db.client
          .from('usuarios')
          .select('id, nombre')
          .inFilter('id', uids.toList());
      for (final u in urows) {
        final n = u['nombre'] as String?;
        if (n != null) uidMap[u['id'] as int] = n;
      }
    }

    final result = <TurnoCerradoResumen>[];
    for (final s in sesiones) {
      final r = resumenMap[s['id'] as int] ?? (ventas: 0, total: 0.0);
      result.add((
        sesion: PosSesion.fromMap(s),
        usuarioNombre: uidMap[s['usuario_id'] as int],
        ventas: r.ventas,
        totalVentas: r.total,
      ));
    }
    return result;
  }

  // Usuarios (directorio central, módulo POS)

  Future<List<PosUsuario>> getUsuarios({bool soloActivos = true}) async {
    final rows = await _db.executeSql(
      'SELECT u.*, COALESCE(array_agg(m.modulo) '
      "FILTER (WHERE m.modulo IS NOT NULL), '{}') AS modulos "
      'FROM usuarios u '
      'JOIN usuario_modulos m ON m.usuario_id = u.id '
      "WHERE m.modulo = 'pos'${soloActivos ? ' AND u.activo = 1' : ''} "
      'GROUP BY u.id ORDER BY u.nombre',
    );
    return rows.map(PosUsuario.fromMap).toList();
  }

  Future<PosUsuario?> getUsuario(int usuarioId) async {
    final rows = await _db.executeSql(
      'SELECT * FROM usuarios WHERE id = \$1 LIMIT 1',
      params: [usuarioId],
    );
    return rows.isEmpty ? null : PosUsuario.fromMap(rows.first);
  }

  Future<int> crearUsuario(String nombre,
      {String? pin, bool esAdmin = false, bool esDesarrollador = false}) async {
    final nivel = esDesarrollador
        ? NivelUsuario.desarrollador
        : esAdmin
            ? NivelUsuario.admin
            : NivelUsuario.basico;
    final id = await _db.insert('usuarios', {
      'nombre': nombre.trim(),
      'pin_hash': pin != null && pin.trim().isNotEmpty ? _pinHash(pin) : null,
      'nivel': nivel.db,
      'activo': 1,
      'creado_en': DateTime.now().toIso8601String(),
    });
    await _db.executeCommand(
      "INSERT INTO usuario_modulos (usuario_id, modulo) VALUES (\$1, 'pos') "
      'ON CONFLICT DO NOTHING',
      params: [id],
    );
    return id;
  }

  Future<void> actualizarUsuario(
    int usuarioId, {
    String? nombre,
    String? pin,
    bool? esAdmin,
    bool? esDesarrollador,
    bool? activo,
  }) async {
    NivelUsuario? nivel;
    if (esDesarrollador != null || esAdmin != null) {
      if (esDesarrollador == true) {
        nivel = NivelUsuario.desarrollador;
      } else if (esAdmin == true) {
        nivel = NivelUsuario.admin;
      } else {
        nivel = NivelUsuario.basico;
      }
    }
    final data = <String, dynamic>{
      if (nombre != null) 'nombre': nombre.trim(),
      if (pin != null) 'pin_hash': pin.isEmpty ? null : _pinHash(pin),
      if (nivel != null) 'nivel': nivel.db,
      if (activo != null) 'activo': activo ? 1 : 0,
    };
    if (data.isEmpty) return;
    await _db.updateById('usuarios', usuarioId, data);
  }

  Future<void> eliminarUsuario(int usuarioId) async {
    await _db.deleteById('usuarios', usuarioId);
  }

  Future<bool> verificarPin(int usuarioId, String pin) async {
    final rows = await _db.executeSql(
      'SELECT pin_hash FROM usuarios WHERE id = \$1 LIMIT 1',
      params: [usuarioId],
    );
    if (rows.isEmpty) return false;
    final hash = rows.first['pin_hash'] as String?;
    if (hash == null || hash.isEmpty) return false;
    return hash == _pinHash(pin);
  }

  // Mesas

  Future<List<PosMesa>> getMesas({bool soloActivos = false}) async {
    var query = _db.client.from('pos_mesas').select();
    if (soloActivos) query = query.eq('activo', 1);
    final rows = await query.order('zona').order('numero') as List<Map<String, dynamic>>;
    return rows.map(PosMesa.fromMap).toList();
  }

  Future<PosMesa?> getMesaById(int mesaId) async {
    final rows = await _db.client
        .from('pos_mesas')
        .select()
        .eq('id', mesaId)
        .limit(1);
    return rows.isEmpty ? null : PosMesa.fromMap(rows.first);
  }

  Future<int> crearMesa(String numero, {String? nombre, String? zona}) async {
    return await _db.insert('pos_mesas', {
      'numero': numero.trim(),
      'nombre': nombre?.trim(),
      'zona': zona?.trim(),
      'activo': 1,
      'creado_en': DateTime.now().toIso8601String(),
    });
  }

  Future<void> actualizarMesa(int mesaId,
      {String? numero, String? nombre, String? zona, bool? activo}) async {
    final rows = await _db.client
        .from('pos_mesas')
        .select()
        .eq('id', mesaId)
        .limit(1);
    if (rows.isEmpty) return;
    final actual = rows.first;
    await _db.updateById('pos_mesas', mesaId, {
      'numero': numero?.trim() ?? actual['numero'],
      'nombre': nombre?.trim() ?? actual['nombre'],
      'zona': zona?.trim() ?? actual['zona'],
      if (activo != null) 'activo': activo,
    });
  }

  Future<void> eliminarMesa(int mesaId) async {
    await _db.deleteById('pos_mesas', mesaId);
  }

  // Habitaciones

  static const String _selectHabitacion = '''
    SELECT h.id, h.numero, h.piso, h.tipo, h.tipo_id, h.activo, h.creado_en,
           h.updated_at,
           COALESCE(t.nombre, h.tipo) AS tipo_display,
           t.capacidad AS capacidad
      FROM habitaciones h
      LEFT JOIN tipos_habitacion t ON t.id = h.tipo_id
  ''';

  Future<List<Habitacion>> getHabitaciones({bool soloActivos = false}) async {
    final rows = await _db.executeSql(
      '$_selectHabitacion${soloActivos ? ' WHERE h.activo = 1' : ''} '
      'ORDER BY h.numero',
    );
    return rows.map(Habitacion.fromMap).toList();
  }

  Future<Habitacion?> getHabitacionById(int habId) async {
    final rows = await _db.executeSql(
      '$_selectHabitacion WHERE h.id = \$1 LIMIT 1',
      params: [habId],
    );
    return rows.isEmpty ? null : Habitacion.fromMap(rows.first);
  }

  Future<int> crearHabitacion(String numero,
      {String? piso, String? tipo, int? tipoId}) async {
    return await _db.insert('habitaciones', {
      'numero': numero.trim(),
      'piso': piso?.trim(),
      'tipo': tipo?.trim(),
      'tipo_id': tipoId,
      'activo': 1,
      'creado_en': DateTime.now().toIso8601String(),
    });
  }

  Future<void> actualizarHabitacion(int habId,
      {String? numero, String? piso, String? tipo, int? tipoId, bool? activo}) async {
    final rows = await _db.client
        .from('habitaciones')
        .select()
        .eq('id', habId)
        .limit(1);
    if (rows.isEmpty) return;
    final actual = rows.first;
    await _db.updateById('habitaciones', habId, {
      'numero': numero?.trim() ?? actual['numero'],
      'piso': piso?.trim() ?? actual['piso'],
      'tipo': tipo != null ? tipo.trim() : actual['tipo'],
      if (tipoId != null) 'tipo_id': tipoId,
      if (activo != null) 'activo': activo ? 1 : 0,
    });
  }

  Future<void> eliminarHabitacion(int habId) async {
    await _db.deleteById('habitaciones', habId);
  }

  // Tipos de habitación (catálogo con capacidad)

  Future<List<TipoHabitacion>> getTiposHabitacion(
      {bool soloActivos = false}) async {
    var query = _db.client.from('tipos_habitacion').select();
    if (soloActivos) query = query.eq('activo', 1);
    final rows = await query.order('nombre') as List<Map<String, dynamic>>;
    return rows.map(TipoHabitacion.fromMap).toList();
  }

  Future<int> crearTipoHabitacion(String nombre, {int capacidad = 1}) async {
    return await _db.insert('tipos_habitacion', {
      'nombre': nombre.trim(),
      'capacidad': capacidad < 1 ? 1 : capacidad,
      'activo': 1,
      'creado_en': DateTime.now().toIso8601String(),
    });
  }

  Future<void> actualizarTipoHabitacion(int id,
      {String? nombre, int? capacidad, bool? activo}) async {
    await _db.updateById('tipos_habitacion', id, {
      if (nombre != null) 'nombre': nombre.trim(),
      if (capacidad != null) 'capacidad': capacidad < 1 ? 1 : capacidad,
      if (activo != null) 'activo': activo ? 1 : 0,
    });
  }

  Future<void> eliminarTipoHabitacion(int id) async {
    await _db.deleteById('tipos_habitacion', id);
  }

  // Sub-categorias (platos_categorias)

  Future<List<PosPlatoCategoria>> getPlatosCategorias(
      {bool soloActivas = false}) async {
    var query = _db.client.from('platos_categorias').select();
    if (soloActivas) query = query.eq('activo', 1);
    final rows = await query.order('nombre') as List<Map<String, dynamic>>;
    return rows.map(PosPlatoCategoria.fromMap).toList();
  }

  Future<int> guardarPlatoCategoria(
    String nombre, {
    int? id,
    String color = '#FF6F00',
    bool activo = true,
    int? categoriaPadreId,
    int? posCategoriaPadreId,
    int? platoCategoriaPadreId,
  }) async {
    final now = DateTime.now().toIso8601String();
    final data = {
      'nombre': nombre.trim(),
      'color': color,
      'activo': activo,
      'categoria_padre_id': categoriaPadreId,
      'pos_categoria_padre_id': posCategoriaPadreId,
      'plato_categoria_padre_id': platoCategoriaPadreId,
      'updated_at': now,
    };
    if (id != null) {
      await _db.updateById('platos_categorias', id, data);
      return id;
    }
    return await _db.insert('platos_categorias', {
      ...data,
      'created_at': now,
    });
  }

  Future<void> eliminarPlatoCategoria(int catId) async {
    await _db.deleteById('platos_categorias', catId);
  }

  // Platos + ingredientes + contornos

  Future<List<PosPlato>> getPlatos({
    bool soloActivos = false,
    int? categoriaId,
    bool? esContorno,
  }) async {
    var query = _db.client.from('platos').select();
    if (soloActivos) query = query.eq('activo', 1);
    if (categoriaId != null) query = query.eq('categoria_id', categoriaId);
    if (esContorno != null) query = query.eq('es_contorno', esContorno ? 1 : 0);
    final rows = await query.order('nombre') as List<Map<String, dynamic>>;
    return rows.map(PosPlato.fromMap).toList();
  }

  Future<List<PosPlato>> getPlatosPos() =>
      getPlatos(soloActivos: true, esContorno: false);

  Future<List<PosPlato>> getContornosActivos() =>
      getPlatos(soloActivos: true, esContorno: true);

  /// Categorías de inventario habilitadas para el POS.
  ///
  /// `categorias.activo` y `categorias.visible_en_pos` son **boolean** en
  /// PostgreSQL, a diferencia de `platos.activo`, que es `integer`.
  /// Filtrarlos con `.eq(campo, 1)` hace que PostgreSQL rechace
  /// la consulta con `el operador no existe: boolean = smallint`, y como acá no
  /// hay try/catch, el error sube hasta `_cargarCategorias` y deja el catálogo
  /// entero vacío. Por eso van `true`/`false` y no `1`/`0`.
  Future<List<Categoria>> getCategoriasPos() async {
    final rows = await _db.client
        .from('categorias')
        .select()
        .eq('activo', true)
        .eq('visible_en_pos', true)
        .order('nombre') as List<Map<String, dynamic>>;
    return rows.map(Categoria.fromMap).toList();
  }

  /// Productos de venta del POS.
  ///
  /// `productos.activo` también es boolean: mismo cuidado que en
  /// [getCategoriasPos].
  Future<List<Producto>> getProductosPos({int? categoriaId}) async {
    var query = _db.client
        .from('productos')
        .select()
        .eq('activo', true)
        .eq('tipo', 'Productos para la venta');
    if (categoriaId != null) query = query.eq('categoria_id', categoriaId);
    final rows = await query.order('nombre') as List<Map<String, dynamic>>;
    return rows.map(Producto.fromMap).toList();
  }

  Future<List<PosPlatoCategoria>> getSubcategorias({
    int? categoriaPadreId,
    int? posCategoriaPadreId,
    int? platoCategoriaPadreId,
  }) async {
    var query = _db.client
        .from('platos_categorias')
        .select()
        .eq('activo', 1);
    if (categoriaPadreId != null) {
      query = query.eq('categoria_padre_id', categoriaPadreId);
    }
    if (posCategoriaPadreId != null) {
      query = query.eq('pos_categoria_padre_id', posCategoriaPadreId);
    }
    if (platoCategoriaPadreId != null) {
      query = query.eq('plato_categoria_padre_id', platoCategoriaPadreId);
    }
    final rows = await query.order('nombre') as List<Map<String, dynamic>>;
    return rows.map(PosPlatoCategoria.fromMap).toList();
  }

  // Tasa de cambio

  Future<double> getTasaCambio() async {
    final v = await getSetting('tasa_cambio');
    return double.tryParse(v ?? '') ?? 0;
  }

  Future<String> getTasaCambioFecha() async =>
      await getSetting('tasa_cambio_actualizada_en') ?? '';

  Future<void> setTasaCambio(double tasa) async {
    await setSetting('tasa_cambio', tasa.toStringAsFixed(4));
    await setSetting('tasa_cambio_actualizada_en',
        DateTime.now().toIso8601String());
  }

  Future<List<PlatoIngrediente>> getIngredientes(int platoId) async {
    final rows = await _db.client
        .from('plato_ingredientes')
        .select()
        .eq('plato_id', platoId) as List<Map<String, dynamic>>;
    return rows.map(PlatoIngrediente.fromMap).toList();
  }

  Future<List<PlatoContorno>> getContornos(int platoId) async {
    final rows = await _db.client
        .from('plato_contornos')
        .select()
        .eq('plato_id', platoId) as List<Map<String, dynamic>>;
    return rows.map(PlatoContorno.fromMap).toList();
  }

  Future<int> crearPlato(
    String nombre, {
    required int categoriaId,
    double precioVenta = 0,
    bool esContorno = false,
    bool llevaContornos = false,
    List<({int productoId, double cantidad, String unidad})>? ingredientes,
    List<({int contornoId, int maxSeleccionar})>? contornos,
  }) async {
    final now = DateTime.now().toIso8601String();
    final id = await _db.insert('platos', {
      'nombre': nombre.trim(),
      'categoria_id': categoriaId,
      'precio_venta': precioVenta,
      'activo': 1,
      'es_contorno': esContorno,
      'lleva_contornos': llevaContornos,
      'created_at': now,
      'updated_at': now,
    });
    await _reemplazarRelaciones(id,
        ingredientes: ingredientes, contornos: contornos);
    return id;
  }

  Future<void> actualizarPlato(
    int platoId, {
    String? nombre,
    int? categoriaId,
    double? precioVenta,
    bool? activo,
    bool? esContorno,
    bool? llevaContornos,
    List<({int productoId, double cantidad, String unidad})>? ingredientes,
    List<({int contornoId, int maxSeleccionar})>? contornos,
  }) async {
    final rows = await _db.client
        .from('platos')
        .select()
        .eq('id', platoId)
        .limit(1);
    if (rows.isEmpty) return;
    final actual = rows.first;
    await _db.updateById('platos', platoId, {
      'nombre': nombre?.trim() ?? actual['nombre'],
      'categoria_id': categoriaId ?? actual['categoria_id'],
      'precio_venta': precioVenta ?? actual['precio_venta'],
      if (activo != null) 'activo': activo,
      if (esContorno != null) 'es_contorno': esContorno,
      if (llevaContornos != null) 'lleva_contornos': llevaContornos,
      'updated_at': DateTime.now().toIso8601String(),
    });
    if (ingredientes != null || contornos != null) {
      await _reemplazarRelaciones(platoId,
          ingredientes: ingredientes, contornos: contornos);
    }
  }

  Future<void> _reemplazarRelaciones(
    int platoId, {
    List<({int productoId, double cantidad, String unidad})>? ingredientes,
    List<({int contornoId, int maxSeleccionar})>? contornos,
  }) async {
    if (ingredientes != null) {
      await _db.deleteWhere('plato_ingredientes', {'plato_id': platoId});
      for (final ing in ingredientes) {
        await _db.insert('plato_ingredientes', {
          'plato_id': platoId,
          'producto_id': ing.productoId,
          'cantidad': ing.cantidad,
          'unidad': ing.unidad,
        });
      }
    }
    if (contornos != null) {
      await _db.deleteWhere('plato_contornos', {'plato_id': platoId});
      for (final c in contornos) {
        await _db.insert('plato_contornos', {
          'plato_id': platoId,
          'contorno_id': c.contornoId,
          'max_seleccionar': c.maxSeleccionar,
        });
      }
    }
  }

  Future<void> eliminarPlato(int platoId) async {
    await _db.deleteWhere('plato_ingredientes', {'plato_id': platoId});
    await _db.deleteWhere('plato_contornos', {'plato_id': platoId});
    await _db.deleteById('platos', platoId);
  }

  /// ¿El turno sigue abierto en BD? (`false` si fue cerrado desde otra
  /// terminal o si ya no existe.)
  Future<bool> sesionAbierta(int sesionId) async {
    final rows = await _db.client
        .from('pos_sesiones')
        .select('id')
        .eq('id', sesionId)
        .isFilter('cerrada_en', null)
        .limit(1);
    return rows.isNotEmpty;
  }

  /// Ventas hechas durante la franja de ESTE turno pero con otra sesión que
  /// ya estaba cerrada (ventas "huérfanas": no entran en ningún cierre).
  ///
  /// Solo se cuentan las de sesiones cerradas al momento de la venta, para no
  /// marcar las ventas legítimas de otros cajeros que trabajan a la vez.
  Future<({int cantidad, double total})> ventasFueraDeTurno(
    int sesionId,
    String? desde,
    String hasta,
  ) async {
    if (desde == null || desde.isEmpty) return (cantidad: 0, total: 0.0);
    final rows = await _db.client
        .from('pos_ventas')
        .select('total, sesion_id, created_at')
        .neq('sesion_id', sesionId)
        .eq('estado', 'vigente')
        .gte('created_at', desde)
        .lte('created_at', hasta);
    if (rows.isEmpty) return (cantidad: 0, total: 0.0);
    final ids = <int>{for (final r in rows) r['sesion_id'] as int}.toList();
    final sRows = await _db.client
        .from('pos_sesiones')
        .select('id, cerrada_en')
        .inFilter('id', ids);
    final cierres = <int, String>{
      for (final s in sRows)
        if (s['cerrada_en'] != null)
          s['id'] as int: s['cerrada_en'] as String,
    };
    var cantidad = 0;
    var total = 0.0;
    for (final r in rows) {
      final cierre = cierres[r['sesion_id'] as int];
      if (cierre == null) continue;
      final creada = r['created_at'] as String?;
      if (creada != null && creada.compareTo(cierre) > 0) {
        cantidad++;
        total += (r['total'] as num?)?.toDouble() ?? 0;
      }
    }
    return (cantidad: cantidad, total: total);
  }

  /// Genera el cierre de caja completo (caja + reportes) para una sesión
  Future<CierreCaja> generarCierre(int sesionId) async {
    final ventasRepo = PosVentasRepository(_db);

    // 1. Obtener sesión y usuario
    final sRows = await _db.client
        .from('pos_sesiones')
        .select()
        .eq('id', sesionId)
        .limit(1);
    if (sRows.isEmpty) throw Exception('Sesión no encontrada: $sesionId');
    final s = sRows.first;

    final uRows = await _db.client
        .from('usuarios')
        .select('nombre')
        .eq('id', s['usuario_id'] as int)
        .limit(1);
    final usuarioNombre = uRows.isNotEmpty ? uRows.first['nombre'] as String : 'Desconocido';
    final aperturistaId = s['usuario_id'] as int;

    // 1.b Participantes del turno compartido con sus ventas por usuario.
    final participantes =
        await _participantesConVentas(_db, sesionId, aperturistaId);
    final porUsuario = [
      for (final p in participantes)
        ResumenUsuario(
          usuarioId: p.usuarioId,
          nombre: p.nombre,
          esAperturista: p.esAperturista,
          esCerrador: p.esAperturista,
          ventas: p.ventas,
          total: p.total,
        ),
    ];

    // 2. Totales de caja
    final cajaInicial = (s['caja_inicial'] as num? ?? 0).toDouble();
    final totalVentas = await _totalVigenteDeSesion(sesionId);
    final cajaFinal = cajaInicial + totalVentas;

    // 3. Reporte simple: items vendidos agregados (desde items_json de la venta)
    final resumen = await ventasRepo.resumenItemsVentaDeSesion(sesionId);
    final Map<String, LineaVenta> lineasMap = {};
    for (final m in resumen.lineas) {
      final key = m['producto_nombre'].toString();
      final precio = (m['precio_venta'] as num?)?.toDouble() ?? 0;
      final cant = (m['cantidad'] as num?)?.toDouble() ?? 0;
      final cat = m['categoria'] as String? ?? 'Sin categoría';
      final nombre = m['producto_nombre'] as String? ?? 'Producto';
      if (lineasMap.containsKey(key)) {
        final existing = lineasMap[key]!;
        lineasMap[key] = LineaVenta(
          nombre: existing.nombre,
          categoria: existing.categoria,
          cantidad: existing.cantidad + cant,
          precioUnitario: existing.precioUnitario,
          total: existing.total + (cant * precio),
        );
      } else {
        lineasMap[key] = LineaVenta(
          nombre: nombre,
          categoria: cat,
          cantidad: cant,
          precioUnitario: precio,
          total: cant * precio,
        );
      }
    }
    final lineas = lineasMap.values.toList()
      ..sort((a, b) => a.nombre.compareTo(b.nombre));

    // 3.b Ventas de esta franja hechas con otra sesión ya cerrada: no entran
    //     en este cierre, pero se reportan como aviso para que el cierre no
    //     quede incompleto en silencio (p. ej. otra terminal que siguió
    //     cobrando con un turno ya cerrado).
    final fueraTurno = await ventasFueraDeTurno(
        sesionId, s['abierta_en'] as String?, DateTime.now().toIso8601String());

    final reporteSimple = ReporteSimple(
      lineas: lineas,
      contornos: resumen.contornos,
      totalGeneral: lineas.fold(0.0, (s, l) => s + l.total),
      ventasFueraTurno: fueraTurno.cantidad,
      montoFueraTurno: fueraTurno.total,
      porUsuario: porUsuario,
    );

    // 4. Reporte detallado: desglose por ingrediente
    final desglosesRaw = await ventasRepo.desgloseIngredientesDeSesion(sesionId);
    final desgloses = desglosesRaw.map((d) => DesgloseIngrediente(
      ingrediente: d['ingrediente'] as String,
      totalConsumido: (d['total_consumido'] as num?)?.toDouble() ?? 0,
      stockFinal: (d['stock_final'] as num?)?.toDouble() ?? 0,
      usos: (d['usos'] as List)
          .map((u) => UsoIngrediente(
                plato: u['plato'] as String,
                cantidad: (u['cantidad'] as num?)?.toDouble() ?? 0,
              ))
          .toList(),
    )).toList();
    final reporteDetallado = ReporteDetallado(desgloses: desgloses);

    // 5. Construir CierreCaja
    return CierreCaja(
      sesionId: sesionId,
      usuarioId: aperturistaId,
      usuarioNombre: usuarioNombre,
      abiertaEn: s['abierta_en'] as String,
      cerradaEn: DateTime.now().toIso8601String(),
      cajaInicial: cajaInicial,
      totalVentas: totalVentas,
      cajaFinal: cajaFinal,
      reporteSimple: reporteSimple,
      reporteDetallado: reporteDetallado,
      syncUuid: _uuid.v4(),
      cerradoPorId: aperturistaId,
      cerradoPorNombre: usuarioNombre,
    );
  }

  /// Persiste el cierre y cierra el turno de caja de forma atómica
  /// (transacción). Si algo falla, se revierte todo y el turno queda abierto,
  /// de modo que nunca se envían reportes sin haber guardado el cierre.
  ///
  /// Solo el usuario que abrió el turno puede cerrarlo. La fila se bloquea con
  /// `FOR UPDATE` para que dos terminales no puedan cerrar el mismo turno.
  Future<void> finalizarCierreYTurno(CierreCaja cierre) async {
    await _db.transaction((tx) async {
      final now = DateTime.now().toIso8601String();
      final rows = await tx.executeSql(
        'SELECT usuario_id, cerrada_en FROM pos_sesiones WHERE id = \$1 FOR UPDATE',
        params: [cierre.sesionId],
      );
      if (rows.isEmpty) throw Exception('Turno no encontrado.');
      final aperturistaId = rows.first['usuario_id'] as int;
      if (rows.first['cerrada_en'] != null) {
        throw Exception('El turno ya fue cerrado.');
      }
      if (aperturistaId != cierre.usuarioId) {
        throw Exception('Solo el usuario que abrió el turno puede cerrarlo.');
      }

      await tx.insert('pos_cierres', {
        'sesion_id': cierre.sesionId,
        'usuario_id': cierre.usuarioId,
        'cerrado_por_usuario_id': cierre.cerradoPorId ?? cierre.usuarioId,
        'abierta_en': cierre.abiertaEn,
        'cerrada_en': cierre.cerradaEn,
        'caja_inicial': cierre.cajaInicial,
        'total_ventas': cierre.totalVentas,
        'caja_final': cierre.cajaFinal,
        'reporte_simple_json': jsonEncode(cierre.reporteSimple.toJson()),
        'reporte_detallado_json': jsonEncode(cierre.reporteDetallado.toJson()),
        'sync_uuid': cierre.syncUuid,
        'created_at': now,
        'updated_at': now,
      });
      await tx.updateById('pos_sesiones', cierre.sesionId, {
        'cerrada_en': cierre.cerradaEn,
        'caja_final': cierre.cajaFinal,
        'cerrada_por_usuario_id': cierre.cerradoPorId ?? cierre.usuarioId,
        'updated_at': now,
      });
      // Todos los participantes quedan fuera del turno; las demás terminales
      // se expulsan solas en su siguiente revalidación.
      await tx.executeCommand(
        'UPDATE pos_turno_participantes '
        'SET salio_en = \$1, updated_at = \$1 '
        'WHERE sesion_id = \$2 AND salio_en IS NULL',
        params: [cierre.cerradaEn, cierre.sesionId],
      );
    });
  }
}
