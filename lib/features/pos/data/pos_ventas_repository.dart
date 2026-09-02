import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/data/supabase_service.dart';
import '../../../core/models/pos_cierre_models.dart';
import '../../../core/models/pos_models.dart';
import '../../../core/models/producto.dart';
import 'pos_comanda_models.dart';

class PosVentasRepository {
  PosVentasRepository(this._db);

  final SupabaseService _db;

  static const Uuid _uuid = Uuid();

  // Comandas

  Future<int> guardarComanda(
    int sesionId,
    List<Map<String, dynamic>> items,
    double total, {
    int? mesaId,
    int? habitacionId,
  }) async {
    // Modo desarrollador: sin escritura en BD
    if (sesionId == 0) return -1;
    final itemsJson = jsonEncode(items);
    final now = DateTime.now().toIso8601String();

    Map<String, dynamic>? existente;
    if (mesaId != null) {
      final rows = await _db.client
          .from('pos_comandas')
          .select()
          .eq('mesa_id', mesaId)
          .eq('estado', 'abierta')
          .order('id', ascending: false)
          .limit(1);
      if (rows.isNotEmpty) existente = rows.first;
    } else if (habitacionId != null) {
      final rows = await _db.client
          .from('pos_comandas')
          .select()
          .eq('habitacion_id', habitacionId)
          .eq('estado', 'abierta')
          .order('id', ascending: false)
          .limit(1);
      if (rows.isNotEmpty) existente = rows.first;
    }

    int id;
    if (existente != null) {
      id = existente['id'] as int;
      await _db.updateById('pos_comandas', id, {
        'items_json': itemsJson,
        'total': total,
        'updated_at': now,
      });
    } else {
      final syncUuid = _uuid.v4();
      id = await _db.insert('pos_comandas', {
        'sesion_id': sesionId,
        'mesa_id': mesaId,
        'habitacion_id': habitacionId,
        'estado': 'abierta',
        'total': total,
        'items_json': itemsJson,
        'sync_uuid': syncUuid,
        'created_at': now,
      });
    }
    return id;
  }

  Future<PosComanda?> getComanda(int id) async {
    final rows = await _db.client
        .from('pos_comandas')
        .select()
        .eq('id', id)
        .limit(1);
    return rows.isEmpty ? null : PosComanda.fromMap(rows.first);
  }

  Future<PosComanda?> getComandaAbierta(
      {int? mesaId, int? habitacionId}) async {
    if (mesaId != null) {
      final rows = await _db.client
          .from('pos_comandas')
          .select()
          .eq('mesa_id', mesaId)
          .eq('estado', 'abierta')
          .order('id', ascending: false)
          .limit(1);
      return rows.isEmpty ? null : PosComanda.fromMap(rows.first);
    }
    if (habitacionId != null) {
      final rows = await _db.client
          .from('pos_comandas')
          .select()
          .eq('habitacion_id', habitacionId)
          .eq('estado', 'abierta')
          .order('id', ascending: false)
          .limit(1);
      return rows.isEmpty ? null : PosComanda.fromMap(rows.first);
    }
    return null;
  }

  Future<List<PosComanda>> getComandasAbiertas() async {
    final rows = await _db.client
        .from('pos_comandas')
        .select()
        .eq('estado', 'abierta');
    return rows.map(PosComanda.fromMap).toList();
  }

  Future<List<ComandaActiva>> getComandasActivas() async {
    final comandas = await _db.client
        .from('pos_comandas')
        .select()
        .eq('estado', 'abierta')
        .order('updated_at', ascending: false);

    final result = <ComandaActiva>[];
    for (final c in comandas) {
      String etiqueta;
      final mesaId = c['mesa_id'] as int?;
      final habId = c['habitacion_id'] as int?;
      final cId = c['id'] as int;
      final cTotal = (c['total'] as num? ?? 0).toDouble();
      final cItemsJson = c['items_json'] as String?;

      if (mesaId != null) {
        final m = await _db.client
            .from('pos_mesas')
            .select('nombre, numero')
            .eq('id', mesaId)
            .limit(1);
        if (m.isNotEmpty) {
          final mn = m.first['nombre'] as String?;
          etiqueta =
              (mn != null && mn.isNotEmpty) ? mn : 'Mesa ${m.first['numero']}';
        } else {
          etiqueta = 'Mesa $mesaId';
        }
      } else if (habId != null) {
        final h = await _db.client
            .from('pos_habitaciones')
            .select('numero')
            .eq('id', habId)
            .limit(1);
        etiqueta =
            h.isNotEmpty ? 'Hab ${h.first['numero']}' : 'Habitacion $habId';
      } else {
        etiqueta = 'Comanda #$cId';
      }
      var items = 0;
      if (cItemsJson != null) {
        try {
          items = (jsonDecode(cItemsJson) as List).length;
        } catch (_) {}
      }
      result.add((
        comandaId: cId,
        etiqueta: etiqueta,
        total: cTotal,
        items: items,
        mesaId: mesaId,
        habitacionId: habId,
      ));
    }
    return result;
  }

  Future<Set<int>> getMesasOcupadas() async {
    final rows = await _db.client
        .from('pos_comandas')
        .select('mesa_id')
        .eq('estado', 'abierta')
        .not('mesa_id', 'is', null);
    return {for (final c in rows) c['mesa_id'] as int};
  }

  Future<Set<int>> getHabitacionesOcupadas() async {
    final rows = await _db.client
        .from('pos_comandas')
        .select('habitacion_id')
        .eq('estado', 'abierta')
        .not('habitacion_id', 'is', null);
    return {for (final c in rows) c['habitacion_id'] as int};
  }

  Future<void> cambiarEstadoComanda(int comandaId, String estado) async {
    final ahora = DateTime.now().toIso8601String();
    await _db.updateById('pos_comandas', comandaId, {
      'estado': estado,
      'updated_at': ahora,
    });
  }

  Future<void> cerrarComanda(int comandaId) {
    // Modo desarrollador: comanda fake, sin escritura
    if (comandaId < 0) return Future.value();
    return cambiarEstadoComanda(comandaId, 'cerrada');
  }

  Future<void> eliminarComanda(int comandaId) async {
    await _db.deleteById('pos_comandas', comandaId);
  }

  // Ventas

  Future<int> siguienteCorrelativo() async {
    final rows = await _db.client.from('pos_ventas').select('correlativo');
    if (rows.isEmpty) return 1;
    final max = rows.fold<int>(
        0, (m, r) => (r['correlativo'] as int? ?? 0) > m ? r['correlativo'] as int : m);
    return max + 1;
  }

  Future<int> registrarVenta(
    int correlativo,
    double total,
    List<Map<String, dynamic>> items, {
    int? comandaId,
    int? mesaId,
    int? habitacionId,
    int? usuarioId,
    int? sesionId,
    int? ventaAnulaId,
    double? tasaBs,
  }) async {
    // Modo desarrollador: sin escritura en BD
    if (sesionId != null && sesionId == 0) return -2;
    final now = DateTime.now().toIso8601String();
    final syncUuid = _uuid.v4();

    String? comandaSyncUuid;
    if (comandaId != null) {
      final c = await getComanda(comandaId);
      comandaSyncUuid = c?.syncUuid;
    }
    String? ventaAnulaSyncUuid;
    if (ventaAnulaId != null) {
      final rows = await _db.client
          .from('pos_ventas')
          .select('sync_uuid')
          .eq('id', ventaAnulaId)
          .limit(1);
      ventaAnulaSyncUuid =
          rows.isNotEmpty ? rows.first['sync_uuid'] as String? : null;
    }

    return await _db.insert('pos_ventas', {
      'comanda_id': comandaId,
      'correlativo': correlativo,
      'total': total,
      'items_json': jsonEncode(items),
      'mesa_id': mesaId,
      'habitacion_id': habitacionId,
      'usuario_id': usuarioId,
      'sesion_id': sesionId,
      'estado': 'vigente',
      'venta_anula_id': ventaAnulaId,
      'tasa_bs': tasaBs,
      'sync_uuid': syncUuid,
      'comanda_sync_uuid': comandaSyncUuid,
      'venta_anula_sync_uuid': ventaAnulaSyncUuid,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> aplicarMovimientosVenta(
    int ventaId,
    List<Map<String, dynamic>> movimientos, {
    String? registradoPor,
  }) async {
    // Modo desarrollador: venta fake, sin escritura
    if (ventaId < 0) return;
    final vsRows = await _db.client
        .from('pos_ventas')
        .select('sync_uuid')
        .eq('id', ventaId)
        .limit(1);
    final vsu = vsRows.isNotEmpty ? vsRows.first['sync_uuid'] as String? ?? '' : '';
    final now = DateTime.now().toIso8601String();

    for (final mov in movimientos) {
      final productoId = mov['producto_id'] as int?;
      final cantidad = (mov['cantidad'] as num?)?.toDouble() ?? 0;
      final almacen =
          (mov['almacen'] as String?)?.trim() ?? 'principal';
      if (productoId == null || cantidad <= 0) continue;

      final exRows = await _db.client
          .from('existencias')
          .select('cantidad')
          .eq('producto_id', productoId)
          .eq('almacen', almacen)
          .limit(1);
      final cantAnterior =
          exRows.isNotEmpty ? (exRows.first['cantidad'] as num? ?? 0).toDouble() : 0.0;
      final cantNueva = cantAnterior - cantidad;
      var obs = 'Venta #$ventaId';
      if (mov['producto_nombre'] != null) obs += ' - ${mov['producto_nombre']}';
      if (cantNueva < 0) obs += ' [STOCK INSUFICIENTE]';

      await _db.insert('movimientos', {
        'producto_id': productoId,
        'venta_id': ventaId,
        'venta_sync_uuid': vsu.isEmpty ? null : vsu,
        'tipo': 'venta',
        'cantidad': cantidad,
        'cantidad_anterior': cantAnterior,
        'cantidad_nueva': cantNueva,
        'peso_total': 0,
        'registrado_por': registradoPor,
        'observaciones': obs,
        'almacen': almacen,
        'fecha_movimiento': now,
        'created_at': now,
      });
      if (exRows.isNotEmpty) {
        final exId = await _db.client
            .from('existencias')
            .select('id')
            .eq('producto_id', productoId)
            .eq('almacen', almacen)
            .limit(1);
        if (exId.isNotEmpty) {
          await _db.updateById('existencias', exId.first['id'] as int, {
            'cantidad': cantNueva,
          });
        }
      }
    }
  }

  Future<void> anularVenta(int ventaId,
      {String? anuladaPor, String motivo = 'Correccion'}) async {
    if (ventaId < 0) return;
    final now = DateTime.now().toIso8601String();
    await _db.updateById('pos_ventas', ventaId, {
      'estado': 'anulada',
      'motivo_anulacion': motivo,
      'anulada_por': anuladaPor,
      'anulada_en': now,
      'updated_at': now,
    });
  }

  Future<void> revertirMovimientosVenta(int ventaId,
      {String? registradoPor}) async {
    if (ventaId < 0) return;
    final vsRows = await _db.client
        .from('pos_ventas')
        .select('sync_uuid')
        .eq('id', ventaId)
        .limit(1);
    final vsu = vsRows.isNotEmpty ? vsRows.first['sync_uuid'] as String? ?? '' : '';
    final movs = await _db.client
        .from('movimientos')
        .select()
        .eq('venta_id', ventaId)
        .eq('tipo', 'venta');
    final now = DateTime.now().toIso8601String();

    for (final m in movs) {
      final productoId = m['producto_id'] as int;
      final almacen = (m['almacen'] as String?) ?? 'principal';
      final cantidad = (m['cantidad'] as num?)?.toDouble() ?? 0;
      if (cantidad <= 0) continue;

      final exRows = await _db.client
          .from('existencias')
          .select('id, cantidad')
          .eq('producto_id', productoId)
          .eq('almacen', almacen)
          .limit(1);
      final cantAnterior =
          exRows.isNotEmpty ? (exRows.first['cantidad'] as num?)?.toDouble() ?? 0 : 0.0;
      final cantNueva = cantAnterior + cantidad;

      await _db.insert('movimientos', {
        'producto_id': productoId,
        'venta_id': ventaId,
        'venta_sync_uuid': vsu.isEmpty ? null : vsu,
        'tipo': 'devolucion',
        'cantidad': cantidad,
        'cantidad_anterior': cantAnterior,
        'cantidad_nueva': cantNueva,
        'peso_total': 0,
        'registrado_por': registradoPor,
        'observaciones': 'Devolucion venta #$ventaId',
        'almacen': almacen,
        'fecha_movimiento': now,
        'created_at': now,
      });
      if (exRows.isNotEmpty) {
        await _db.updateById(
            'existencias', exRows.first['id'] as int, {
          'cantidad': cantNueva,
        });
      }
    }
  }

  Future<void> eliminarVentaYMovimientos(int ventaId) async {
    final movs = await _db.client
        .from('movimientos')
        .select('id, producto_id, cantidad, almacen')
        .eq('venta_id', ventaId);
    for (final m in movs) {
      final productoId = m['producto_id'] as int;
      final almacen = (m['almacen'] as String?) ?? 'principal';
      final cant = (m['cantidad'] as num?)?.toDouble() ?? 0;
      final exRows = await _db.client
          .from('existencias')
          .select('id')
          .eq('producto_id', productoId)
          .eq('almacen', almacen)
          .limit(1);
      if (exRows.isNotEmpty) {
        await _db.updateById(
            'existencias', exRows.first['id'] as int, {
          'cantidad': cant,
        });
      }
    }
    await _db.deleteWhere('movimientos', {'venta_id': ventaId});
    await _db.deleteById('pos_ventas', ventaId);
  }

  Future<List<PosVenta>> getVentas({int limit = 200, int? beforeId}) async {
    var query = _db.client.from('pos_ventas').select();
    if (beforeId != null) query = query.lt('id', beforeId);
    final rows = await query.order('id', ascending: false).limit(limit);
    return rows.map(PosVenta.fromMap).toList();
  }

  Future<({int cantidad, double total})> getVentasHoy() async {
    final hoy = DateTime.now();
    final inicio =
        DateTime(hoy.year, hoy.month, hoy.day).toIso8601String();
    final rows = await _db.client
        .from('pos_ventas')
        .select('total')
        .eq('estado', 'vigente')
        .gte('created_at', inicio);
    var total = 0.0;
    for (final v in rows) {
      total += (v['total'] as num? ?? 0).toDouble();
    }
    return (cantidad: rows.length, total: total);
  }

  /// Resumen de ventas vigentes de una sesión/turno específica
  Future<({int cantidad, double total})> getVentasDeSesion(int sesionId) async {
    final rows = await _db.client
        .from('pos_ventas')
        .select('total')
        .eq('estado', 'vigente')
        .eq('sesion_id', sesionId);
    var total = 0.0;
    for (final v in rows) {
      total += (v['total'] as num? ?? 0).toDouble();
    }
    return (cantidad: rows.length, total: total);
  }

  Future<PosVenta?> getVenta(int id) async {
    final rows = await _db.client
        .from('pos_ventas')
        .select()
        .eq('id', id)
        .limit(1);
    return rows.isEmpty ? null : PosVenta.fromMap(rows.first);
  }

  Future<List<PosVenta>> getVentasPorSesion(int sesionId) async {
    final rows = await _db.client
        .from('pos_ventas')
        .select()
        .eq('sesion_id', sesionId)
        .order('id', ascending: false);
    return rows.map(PosVenta.fromMap).toList();
  }

  Future<Map<int, int>> getVentasCorrelativos(List<int> ids) async {
    if (ids.isEmpty) return {};
    final rows = await _db.client
        .from('pos_ventas')
        .select('id, correlativo')
        .filter('id', 'in', ids);
    return {
      for (final v in rows)
        if (v['correlativo'] != null) v['id'] as int: v['correlativo'] as int,
    };
  }

  Future<PosVenta?> getVentaAnuladaPorComanda(int comandaId) async {
    final rows = await _db.client
        .from('pos_ventas')
        .select()
        .eq('comanda_id', comandaId)
        .eq('estado', 'anulada')
        .order('id', ascending: false)
        .limit(1);
    return rows.isEmpty ? null : PosVenta.fromMap(rows.first);
  }

  Future<PosVenta?> getUltimaVentaVigente() async {
    final rows = await _db.client
        .from('pos_ventas')
        .select()
        .eq('estado', 'vigente')
        .order('id', ascending: false)
        .limit(1);
    return rows.isEmpty ? null : PosVenta.fromMap(rows.first);
  }

  Future<void> reabrirComanda(int comandaId) =>
      cambiarEstadoComanda(comandaId, 'abierta');

  Future<Producto?> getProductoById(int productoId) async {
    final rows = await _db.client
        .from('productos')
        .select()
        .eq('id', productoId)
        .limit(1);
    return rows.isEmpty ? null : Producto.fromMap(rows.first);
  }

  Future<List<({int id, int platoId, int productoId, double cantidad, String unidad, String nombre})>>
      getPlatoIngredientes(int platoId) async {
    final rows = await _db.client
        .from('plato_ingredientes')
        .select()
        .eq('plato_id', platoId);
    final nombres = <int, String>{};
    for (final r in rows) {
      final pid = r['producto_id'] as int;
      final p = await getProductoById(pid);
      nombres[pid] = p?.nombre ?? 'Producto #$pid';
    }
    return [
      for (final r in rows)
        (
          id: r['id'] as int,
          platoId: r['plato_id'] as int,
          productoId: r['producto_id'] as int,
          cantidad: (r['cantidad'] as num?)?.toDouble() ?? 0,
          unidad: (r['unidad'] as String?) ?? 'unidad',
          nombre: nombres[r['producto_id'] as int] ?? '?',
        ),
    ];
  }

  Future<List<Map<String, dynamic>>> resolverMovimientosVenta(
      List<Map<String, dynamic>> items) async {
    final acumulado = <(int, String), Map<String, dynamic>>{};

    void acumular(
        int productoId, String nombre, double cantidad, String almacen) {
      final key = (productoId, almacen);
      final m = acumulado.putIfAbsent(
          key,
          () => {
                'producto_id': productoId,
                'producto_nombre': nombre,
                'cantidad': 0.0,
                'almacen': almacen,
              });
      m['cantidad'] = (m['cantidad'] as double) + cantidad;
    }

    Future<void> acumularIngredientes(int platoId, double cant) async {
      final ing = await getPlatoIngredientes(platoId);
      for (final i in ing) {
        acumular(i.productoId, i.nombre, i.cantidad * cant, 'restaurante');
      }
    }

    for (final item in items) {
      final pid = item['id'] as int?;
      final cant = (item['cantidad'] as num?)?.toDouble() ?? 1;
      if (pid == null) continue;

      final tipo = (item['tipo'] as String? ?? '').toLowerCase();

      if (tipo == 'producto') {
        // Producto simple: consultar tabla productos
        final prod = await getProductoById(pid);
        acumular(pid, prod?.nombre ?? 'Producto #$pid', cant, 'restaurante');
      } else if (tipo == 'plato' || tipo == 'contorno') {
        // Plato o contorno compuesto: desglosar ingredientes de la tabla platos
        await acumularIngredientes(pid, cant);
      } else {
        // Fallback: intentar como producto, si no existe tratar como plato
        final prod = await getProductoById(pid);
        if (prod != null) {
          acumular(pid, prod.nombre, cant, 'restaurante');
        } else {
          await acumularIngredientes(pid, cant);
        }
      }

      final cids = <int>[
        ...?((item['contorno_ids'] as List?)?.cast<num>().map((n) => n.toInt())),
      ];
      for (final cid in cids) {
        await acumularIngredientes(cid, cant);
      }
    }
    return acumulado.values.toList();
  }

  Future<List<Map<String, dynamic>>> getMovimientosVenta(int ventaId) async {
    final rows = await _db.client
        .from('movimientos')
        .select()
        .eq('venta_id', ventaId)
        .eq('tipo', 'venta');
    final result = <Map<String, dynamic>>[];
    for (final m in rows) {
      final pid = m['producto_id'] as int;
      final p = await getProductoById(pid);
      result.add({
        'producto_id': pid,
        'cantidad': (m['cantidad'] as num?)?.toDouble() ?? 0,
        'almacen': m['almacen'],
        'producto_nombre': p?.nombre ?? 'Producto #$pid',
      });
    }
    result.sort((a, b) =>
        (a['producto_nombre'] as String).compareTo(b['producto_nombre'] as String));
    return result;
  }

  /// Resumen de items vendidos en una sesión (para el reporte simple del cierre).
  ///
  /// Se arma desde `pos_ventas.items_json` para que el reporte coincida con lo
  /// realmente vendido (productos, platos y contornos, incluso platos sin
  /// ingredientes asignados). Los contornos se agrupan aparte como referencia
  /// informativa (su costo ya está incluido en el plato base).
  Future<({List<Map<String, dynamic>> lineas, List<ResumenContorno> contornos})>
      resumenItemsVentaDeSesion(int sesionId) async {
    final ventas = await getVentasPorSesion(sesionId);
    final vigentes = ventas.where((v) => v.estado == 'vigente').toList();
    if (vigentes.isEmpty) {
      return (
        lineas: <Map<String, dynamic>>[],
        contornos: <ResumenContorno>[],
      );
    }

    final catCache = <String, String>{};

    Future<String> categoriaProducto(int? catId) async {
      final key = 'prod-$catId';
      if (catId == null) return 'Sin categoría';
      if (catCache.containsKey(key)) return catCache[key]!;
      final nombre = await _getCategoriaNombre(catId);
      catCache[key] = nombre;
      return nombre;
    }

    Future<String> categoriaPlato(int catId) async {
      final key = 'plato-$catId';
      if (!catCache.containsKey(key)) {
        final rows = await _db.client
            .from('platos_categorias')
            .select('nombre')
            .eq('id', catId)
            .limit(1);
        catCache[key] = rows.isNotEmpty ? rows.first['nombre'] as String : 'Sin categoría';
      }
      return catCache[key]!;
    }

    final acumulado = <String, Map<String, dynamic>>{};
    final contornosAcum = <String, Map<String, dynamic>>{};
    for (final venta in vigentes) {
      final itemsJson = venta.itemsJson;
      if (itemsJson == null || itemsJson.isEmpty) continue;
      final items = jsonDecode(itemsJson) as List;
      for (final item in items) {
        final pid = item['id'] as int?;
        if (pid == null) continue;
        final cant = (item['cantidad'] as num?)?.toDouble() ?? 1;
        final tipo = (item['tipo'] as String? ?? '').toLowerCase();
        final nombre = item['nombre'] as String? ?? 'Item #$pid';
        final precio = (item['precio'] as num?)?.toDouble() ?? 0;

        String categoria;
        if (tipo == 'producto') {
          final prod = await getProductoById(pid);
          categoria = await categoriaProducto(prod?.categoriaId);
        } else {
          final plato = await _getPlatoById(pid);
          categoria = plato != null
              ? await categoriaPlato(plato.categoriaId)
              : 'Sin categoría';
        }

        final key = '$tipo-$pid';
        final m = acumulado.putIfAbsent(key, () => {
              'producto_nombre': nombre,
              'cantidad': 0.0,
              'precio_venta': precio,
              'categoria': categoria,
            });
        m['cantidad'] = (m['cantidad'] as double) + cant;

        // Contornos servidos con el plato (informativo, agrupado por contorno)
        final contornos = (item['contornos'] as List?)?.cast<String>() ?? const [];
        for (var i = 0; i < contornos.length; i++) {
          final cNombre = contornos[i];
          final ckey = cNombre;
          final cm = contornosAcum.putIfAbsent(ckey, () => {
                'nombre': cNombre,
                'cantidad': 0.0,
              });
          cm['cantidad'] = (cm['cantidad'] as double) + cant;
        }
      }
    }

    final lineas = acumulado.values.toList()
      ..sort((a, b) =>
          (a['producto_nombre'] as String).compareTo(b['producto_nombre'] as String));
    final contornos = [
      for (final c in contornosAcum.values)
        ResumenContorno(
          nombre: c['nombre'] as String,
          cantidad: c['cantidad'] as double,
        ),
    ]..sort((a, b) => a.nombre.compareTo(b.nombre));
    return (lineas: lineas, contornos: contornos);
  }

  Future<PosPlato?> _getPlatoById(int platoId) async {
    final rows = await _db.client
        .from('platos')
        .select()
        .eq('id', platoId)
        .limit(1);
    return rows.isEmpty ? null : PosPlato.fromMap(rows.first);
  }

  Future<String> _getCategoriaNombre(int? categoriaId) async {
    if (categoriaId == null) return 'Sin categoría';
    final rows = await _db.client
        .from('categorias')
        .select('nombre')
        .eq('id', categoriaId)
        .limit(1);
    return rows.isNotEmpty ? rows.first['nombre'] as String : 'Sin categoría';
  }

  /// Desglose por ingrediente para una sesión: total consumido, stock final, usos por plato
  Future<List<Map<String, dynamic>>> desgloseIngredientesDeSesion(int sesionId) async {
    // 1. Obtener ventas vigentes de la sesión con sus items
    final ventas = await getVentasPorSesion(sesionId);
    final ventasVigentes = ventas.where((v) => v.estado == 'vigente').toList();
    if (ventasVigentes.isEmpty) return [];

    // 2. Acumular ingredientes a partir de items_json de cada venta
    final Map<int, Map<String, dynamic>> ingredientesAcum = {};

    void acumularIngrediente(
      int productoId,
      String nombre,
      double cantidad,
      String platoNombre,
    ) {
      final key = productoId;
      final m = ingredientesAcum.putIfAbsent(key, () => {
        'producto_id': productoId,
        'ingrediente': nombre,
        'total_consumido': 0.0,
        'usos': <Map<String, dynamic>>[],
      });
      m['total_consumido'] = (m['total_consumido'] as double) + cantidad;
      final usos = m['usos'] as List<Map<String, dynamic>>;
      usos.add({'plato': platoNombre, 'cantidad': cantidad});
    }

    for (final venta in ventasVigentes) {
      final itemsJson = venta.itemsJson;
      if (itemsJson == null || itemsJson.isEmpty) continue;
      final items = jsonDecode(itemsJson) as List;
      for (final item in items) {
        final pid = item['id'] as int?;
        final cant = (item['cantidad'] as num?)?.toDouble() ?? 1;
        if (pid == null) continue;

        final tipo = (item['tipo'] as String? ?? '').toLowerCase();

        if (tipo == 'producto') {
          // Producto para la venta: se descarga a sí mismo
          final prod = await getProductoById(pid);
          final prodNombre = prod?.nombre ?? 'Producto #$pid';
          acumularIngrediente(pid, prodNombre, cant, prodNombre);
        } else if (tipo == 'plato' || tipo == 'contorno') {
          // Plato o contorno compuesto: desglosar ingredientes de la tabla platos
          final ing = await getPlatoIngredientes(pid);
          // Para el nombre del plato, consultar tabla platos
          final platoRows = await _db.client
              .from('platos')
              .select('nombre')
              .eq('id', pid)
              .limit(1);
          final platoNombre = platoRows.isNotEmpty
              ? platoRows.first['nombre'] as String
              : 'Plato #$pid';
          for (final i in ing) {
            acumularIngrediente(i.productoId, i.nombre, i.cantidad * cant, platoNombre);
          }
        } else {
          // Fallback: intentar como plato si no es producto explícito
          final ing = await getPlatoIngredientes(pid);
          if (ing.isNotEmpty) {
            final platoRows = await _db.client
                .from('platos')
                .select('nombre')
                .eq('id', pid)
                .limit(1);
            final platoNombre = platoRows.isNotEmpty
                ? platoRows.first['nombre'] as String
                : 'Plato #$pid';
            for (final i in ing) {
              acumularIngrediente(i.productoId, i.nombre, i.cantidad * cant, platoNombre);
            }
          }
        }

        // Contornos
        final cids = <int>[
          ...?((item['contorno_ids'] as List?)?.cast<num>().map((n) => n.toInt())),
        ];
        for (final cid in cids) {
          final ing = await getPlatoIngredientes(cid);
          final contornoRows = await _db.client
              .from('platos')
              .select('nombre')
              .eq('id', cid)
              .limit(1);
          final contornoNombre = contornoRows.isNotEmpty
              ? contornoRows.first['nombre'] as String
              : 'Contorno #$cid';
          for (final i in ing) {
            acumularIngrediente(i.productoId, i.nombre, i.cantidad * cant, contornoNombre);
          }
        }
      }
    }

    // 3. Obtener stock final de cada ingrediente (desde existencias)
    for (final entry in ingredientesAcum.entries) {
      final pid = entry.key;
      final m = entry.value;
      final exRows = await _db.client
          .from('existencias')
          .select('cantidad')
          .eq('producto_id', pid)
          .eq('almacen', 'restaurante')
          .limit(1);
      m['stock_final'] = exRows.isNotEmpty
          ? (exRows.first['cantidad'] as num?)?.toDouble() ?? 0
          : 0;
    }

    // 4. Convertir a lista ordenada
    final result = ingredientesAcum.values.toList();
    result.sort((a, b) => (a['ingrediente'] as String).compareTo(b['ingrediente'] as String));
    return result;
  }
}
