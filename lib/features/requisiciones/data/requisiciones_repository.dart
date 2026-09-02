import '../../../core/data/supabase_service.dart';
import '../../../core/models/requisicion.dart' as domain;

class RequisicionItem {
  const RequisicionItem({
    this.productoId,
    required this.ingrediente,
    required this.cantidad,
    this.unidad = 'unidad',
    this.peso,
    this.esPesable = false,
    this.verificado = false,
  });

  final int? productoId;
  final String ingrediente;
  final double cantidad;
  final String unidad;
  final double? peso;
  final bool esPesable;
  final bool verificado;

  String get nombre => ingrediente.isEmpty ? 'Desconocido' : ingrediente;
}

class AuditStock {
  const AuditStock({
    required this.inicial,
    required this.trasladada,
    required this.final_,
  });

  final double inicial;
  final double trasladada;
  final double final_;
}

class AuditItem {
  AuditItem({
    required this.detalleId,
    this.productoId,
    required this.ingrediente,
    required this.verificado,
    required this.origen,
    required this.destino,
  });

  final int detalleId;
  final int? productoId;
  final String ingrediente;
  bool verificado;
  final AuditStock origen;
  final AuditStock destino;
}

class RequisicionesRepository {
  RequisicionesRepository(this._db);
  final SupabaseService _db;

  Future<List<String>> getAlmacenes() async {
    final rows = await _db.fetchAll('almacenes',
        filters: {'activo': true}, orderBy: 'orden');
    final nombres = <String>{
      for (final r in rows) r['nombre'] as String,
      'principal',
      'restaurante',
    };
    // Incluir strings huérfanos aún en los datos.
    final existencias = await _db.fetchAll('existencias');
    for (final r in existencias) {
      final a = r['almacen'] as String?;
      if (a != null && a.isNotEmpty) nombres.add(a);
    }
    return nombres.toList()..sort();
  }

  Future<List<Map<String, dynamic>>> getProductosActivos({int limit = 200}) =>
      _db.client
          .from('productos')
          .select()
          .eq('activo', 1)
          .order('nombre', ascending: true)
          .limit(limit);

  Future<List<Map<String, dynamic>>> buscarProductos(String texto,
      {int limit = 30}) async {
    dynamic builder =
        _db.client.from('productos').select().eq('activo', 1);
    if (texto.isNotEmpty) {
      builder = builder.ilike('nombre', '%$texto%');
    }
    builder = builder.order('nombre', ascending: true).limit(limit);
    return builder;
  }

  Future<Map<String, dynamic>?> getProducto(int id) async {
    return _db.fetchById('productos', id);
  }

  Future<double> getExistencia(int productoId, String almacen) async {
    final rows = await _db.fetchAll(
      'existencias',
      filters: {'producto_id': productoId},
    );
    for (final r in rows) {
      if (r['almacen'] == almacen) {
        return (r['cantidad'] as num?)?.toDouble() ?? 0;
      }
    }
    return 0;
  }

  Future<List<domain.Requisicion>> loadRequisiciones() async {
    final rows = await _db.client
        .from('requisiciones')
        .select()
        .order('fecha_creacion', ascending: false);
    return rows.map(domain.Requisicion.fromMap).toList();
  }

  /// Cuenta detalles de varias requisiciones en una sola query.
  Future<Map<int, int>> contarDetallesBatch(List<int> requisicionIds) async {
    if (requisicionIds.isEmpty) return {};
    final rows = await _db.client
        .from('requisicion_detalles')
        .select('requisicion_id')
        .inFilter('requisicion_id', requisicionIds);
    final counts = <int, int>{};
    for (final r in rows) {
      final rid = r['requisicion_id'] as int;
      counts[rid] = (counts[rid] ?? 0) + 1;
    }
    return counts;
  }

  Future<int> contarDetalles(int requisicionId) async {
    final rows = await _db.client
        .from('requisicion_detalles')
        .select('id')
        .eq('requisicion_id', requisicionId);
    return rows.length;
  }

  Future<List<domain.RequisicionDetalle>> getDetalles(int requisicionId) async {
    final rows = await _db.client
        .from('requisicion_detalles')
        .select()
        .eq('requisicion_id', requisicionId)
        .order('id', ascending: true);
    return rows.map(domain.RequisicionDetalle.fromMap).toList();
  }

  Future<int> guardarRequisicion({
    required String origen,
    required String destino,
    String? observaciones,
    List<RequisicionItem> detalles = const [],
    domain.Requisicion? editando,
    String usuario = 'Admin',
    String estado = 'pendiente',
    bool moverStock = false,
  }) async {
    if (editando == null) {
      final numero = 'REQ-${_tsNow()}';
      final id = await _db.insert('requisiciones', {
        'numero': numero,
        'numero_secuencial': 0,
        'origen': origen,
        'destino': destino,
        'estado': estado,
        'observaciones': observaciones,
        'creada_por': usuario,
        'fecha_creacion': DateTime.now().toUtc().toIso8601String(),
        'actualizada': DateTime.now().toUtc().toIso8601String(),
      });
      for (final item in detalles) {
        await _insertDetalle(id, item);
      }
      await _aplicarMoverStock(id, moverStock);
      return id;
    }

    await _db.updateById('requisiciones', editando.id, {
      'origen': origen,
      'destino': destino,
      'observaciones': observaciones,
      'actualizada': DateTime.now().toUtc().toIso8601String(),
    });

    final prevVer = <String, bool>{};
    for (final d in await getDetalles(editando.id)) {
      prevVer['${d.productoId}|${d.ingrediente}'] = d.verificado;
    }
    await _db.deleteWhere('requisicion_detalles',
        {'requisicion_id': editando.id});
    for (final item in detalles) {
      final key = '${item.productoId}|${item.ingrediente}';
      await _insertDetalle(editando.id, item,
          verificado: prevVer[key] ?? false);
    }
    await _aplicarMoverStock(editando.id, moverStock);
    return editando.id;
  }

  Future<bool> eliminarRequisicion(int requisicionId) async {
    final req = await _db.fetchById('requisiciones', requisicionId);
    if (req == null) return false;
    await _db.deleteWhere(
        'requisicion_detalles', {'requisicion_id': requisicionId});
    await _db.deleteById('requisiciones', requisicionId);
    return true;
  }

  Future<List<AuditItem>> getAuditData(int requisicionId) async {
    final reqRows = await _db.fetchById('requisiciones', requisicionId);
    if (reqRows == null) return [];
    final req = domain.Requisicion.fromMap(reqRows);
    final detalles = await getDetalles(req.id);

    final productoIds = detalles.map((d) => d.productoId ?? -1).toSet().toList();
    final stockRows = await _db.client
        .from('existencias')
        .select('producto_id, almacen, cantidad')
        .inFilter('producto_id', productoIds);
    final stockMap = <String, double>{};
    for (final r in stockRows) {
      final key = '${r['producto_id']}_${r['almacen']}';
      stockMap[key] = (r['cantidad'] as num?)?.toDouble() ?? 0;
    }

    final items = <AuditItem>[];
    for (final d in detalles) {
      final pid = d.productoId ?? -1;
      final sOrig = stockMap['${pid}_${req.origen}'] ?? 0;
      final sDest = stockMap['${pid}_${req.destino}'] ?? 0;
      final cant = d.cantidad;
      items.add(AuditItem(
        detalleId: d.id,
        productoId: d.productoId,
        ingrediente: d.ingrediente,
        verificado: d.verificado,
        origen:
            AuditStock(inicial: sOrig, trasladada: cant, final_: sOrig - cant),
        destino:
            AuditStock(inicial: sDest, trasladada: cant, final_: sDest + cant),
      ));
    }
    return items;
  }

  Future<void> marcarDetalleVerificado(int detalleId, bool verificado) async {
    final rows = await _db.fetchById('requisicion_detalles', detalleId);
    if (rows == null) return;
    await _db.updateById(
        'requisicion_detalles', detalleId, {'verificado': verificado ? 1 : 0});
  }

  Future<void> crearAjusteStock({
    required int productoId,
    required String almacen,
    required double nuevaCantidad,
    required String motivo,
    String usuario = 'Admin',
    double? pesoTotal,
  }) async {
    final actual = await getExistencia(productoId, almacen);
    final diff = nuevaCantidad - actual;

    await _db.insert('movimientos', {
      'producto_id': productoId,
      'tipo': 'ajuste',
      'cantidad': diff,
      'cantidad_anterior': actual,
      'cantidad_nueva': nuevaCantidad,
      'peso_total': pesoTotal ?? 0,
      'registrado_por': usuario,
      'observaciones': 'Ajuste auditoría: $motivo',
      'almacen': almacen,
      'fecha_movimiento': DateTime.now().toUtc().toIso8601String(),
    });

    final prod = await _db.fetchById('productos', productoId);
    final unidad = (prod?['unidad_medida'] as String?) ?? 'unidad';
    final rows = await _db.client
        .from('existencias')
        .select('id')
        .eq('producto_id', productoId)
        .eq('almacen', almacen)
        .limit(1);
    if (rows.isNotEmpty) {
      await _db.updateById(
          'existencias', rows.first['id'] as int, {
        'cantidad': nuevaCantidad,
        'unidad': unidad,
      });
    } else {
      await _db.insert('existencias', {
        'producto_id': productoId,
        'almacen': almacen,
        'cantidad': nuevaCantidad,
        'unidad': unidad,
      });
    }
  }

  Future<void> totalizarRequisicion(int requisicionId,
      {String usuario = 'Admin'}) async {
    final reqRows = await _db.fetchById('requisiciones', requisicionId);
    if (reqRows == null) throw StateError('Requisición no encontrada');
    final req = domain.Requisicion.fromMap(reqRows);
    if (req.estado == 'completada') {
      throw StateError('La requisición ya fue totalizada');
    }

    final detalles = await getDetalles(req.id);
    if (detalles.isEmpty) {
      throw StateError('La requisición no tiene detalles');
    }

    // Productos que ya tienen su par de traslados aplicado (idempotencia:
    // permite reanudar si un totalizar anterior se interrumpió a mitad,
    // sin duplicar movimientos).
    final traslados = await _db.client
        .from('movimientos')
        .select('producto_id,tipo')
        .eq('requisicion_id', req.id);
    final productosTrasladados = <int>{
      for (final m in traslados)
        if (m['producto_id'] is int) m['producto_id'] as int,
    };
    // Un producto cuenta como trasladado solo si tiene AMBOS movimientos.
    // Por robustez: si el set es impar (solo tr_salida o solo tr_entrada),
    // lo dejamos fuera para reprocesarlo.
    final conteo = <int, int>{};
    for (final m in traslados) {
      final p = m['producto_id'];
      if (p is int) {
        conteo[p] = (conteo[p] ?? 0) + 1;
      }
    }
    productosTrasladados.removeWhere((p) => (conteo[p] ?? 0) < 2);

    final pendientes = detalles
        .where((d) =>
            d.productoId == null || !productosTrasladados.contains(d.productoId))
        .toList();

    // Si no queda nada por procesar (totalizar anterior se interrumpió solo
    // en el flag de estado), simplemente marcamos como completada.
    if (pendientes.isEmpty) {
      await _marcarCompletada(req, usuario);
      return;
    }

    for (final d in pendientes) {
      if (d.productoId == null) continue;

      final actualOrigen = await getExistencia(d.productoId!, req.origen);
      final actualDestino = await getExistencia(d.productoId!, req.destino);
      final cantOrigenNueva =
          (actualOrigen - d.cantidad).clamp(0.0, double.infinity);
      final cantDestinoNueva = actualDestino + d.cantidad;

      await _db.insert('movimientos', {
        'producto_id': d.productoId,
        'requisicion_id': req.id,
        'tipo': 'tr_salida',
        'cantidad': -d.cantidad,
        'cantidad_anterior': actualOrigen,
        'cantidad_nueva': cantOrigenNueva,
        'peso_total': 0,
        'registrado_por': usuario,
        'observaciones': 'Traslado req ${req.numero} → ${req.destino}',
        'almacen': req.origen,
        'fecha_movimiento': DateTime.now().toUtc().toIso8601String(),
      });

      await _db.insert('movimientos', {
        'producto_id': d.productoId,
        'requisicion_id': req.id,
        'tipo': 'tr_entrada',
        'cantidad': d.cantidad,
        'cantidad_anterior': actualDestino,
        'cantidad_nueva': cantDestinoNueva,
        'peso_total': 0,
        'registrado_por': usuario,
        'observaciones': 'Traslado req ${req.numero} ← ${req.origen}',
        'almacen': req.destino,
        'fecha_movimiento': DateTime.now().toUtc().toIso8601String(),
      });

      await _upsertExistencia(d.productoId!, req.origen, cantOrigenNueva);
      await _upsertExistencia(d.productoId!, req.destino, cantDestinoNueva);
    }

    await _marcarCompletada(req, usuario);
  }

  Future<void> _marcarCompletada(domain.Requisicion req, String usuario) async {
    await _db.updateById('requisiciones', req.id, {
      'estado': 'completada',
      'procesada_por': usuario,
      'fecha_procesamiento': DateTime.now().toUtc().toIso8601String(),
      'actualizada': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getMovimientosProducto(int productoId,
      {int limit = 9999}) async {
    final rows = await _db.client
        .from('movimientos')
        .select()
        .eq('producto_id', productoId)
        .order('fecha_movimiento', ascending: false)
        .limit(limit);
    return rows;
  }

  Future<void> _insertDetalle(int requisicionId, RequisicionItem item,
      {bool verificado = false}) {
    return _db.insert('requisicion_detalles', {
      'requisicion_id': requisicionId,
      'producto_id': item.productoId,
      'ingrediente': item.nombre,
      'cantidad': item.cantidad,
      'unidad': item.unidad,
      'cantidad_surtida': 0,
      'verificado': (item.verificado || verificado) ? 1 : 0,
    }).then((_) {});
  }

  Future<void> _aplicarMoverStock(int requisicionId, bool moverStock) async {
    if (!moverStock) return;
    final reqRows = await _db.fetchById('requisiciones', requisicionId);
    if (reqRows == null) return;
    final req = domain.Requisicion.fromMap(reqRows);

    for (final d in await getDetalles(req.id)) {
      if (d.productoId == null) continue;
      final actualOrigen = await getExistencia(d.productoId!, req.origen);
      final actualDestino = await getExistencia(d.productoId!, req.destino);

      await _upsertExistencia(d.productoId!, req.origen,
          (actualOrigen - d.cantidad).clamp(0.0, double.infinity));
      await _upsertExistencia(
          d.productoId!, req.destino, actualDestino + d.cantidad);
    }
  }

  Future<void> _upsertExistencia(
      int productoId, String almacen, double cantidad) async {
    final rows = await _db.client
        .from('existencias')
        .select('id')
        .eq('producto_id', productoId)
        .eq('almacen', almacen)
        .limit(1);
    if (rows.isNotEmpty) {
      await _db.updateById(
          'existencias', rows.first['id'] as int, {'cantidad': cantidad});
    } else {
      await _db.insert('existencias', {
        'producto_id': productoId,
        'almacen': almacen,
        'cantidad': cantidad,
      });
    }
  }

  String _tsNow() {
    final now = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${p(now.month)}${p(now.day)}${p(now.hour)}${p(now.minute)}${p(now.second)}';
  }
}
