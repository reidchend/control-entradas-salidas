import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/postgres_providers.dart';
import '../../../core/data/postgres_service.dart';

class ReportesRepository {
  ReportesRepository(this._db);
  final PostgresService _db;

  /// Convierte un valor que puede venir como `num` o `String` a `double`
  /// (Postgres devuelve `numeric` como String según el driver).
  static double _toDouble(dynamic v, [double fallback = 0]) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  /// Igual que [_toDouble] pero a `int`.
  static int _toInt(dynamic v, [int fallback = 0]) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  /// Ventas en un rango de fechas con filtros opcionales
  Future<List<Map<String, dynamic>>> getVentas({
    required DateTime desde,
    required DateTime hasta,
    String? cajero,
    String? formaPago,
  }) async {
    final rows = await _db.executeSql('''
      SELECT
        v.id,
        v.comanda_id,
        v.correlativo,
        v.total,
        v.items_json,
        v.mesa_id,
        v.habitacion_id,
        v.usuario_id,
        v.sesion_id,
        v.estado,
        v.tasa_bs,
        v.created_at,
        v.updated_at,
        m.nombre AS mesa_nombre,
        h.numero AS habitacion_numero,
        u.nombre AS cajero_nombre
      FROM pos_ventas v
      LEFT JOIN pos_mesas m ON m.id = v.mesa_id
      LEFT JOIN pos_habitaciones h ON h.id = v.habitacion_id
      LEFT JOIN pos_usuarios u ON u.id = v.usuario_id
      WHERE v.created_at >= \$1 AND v.created_at <= \$2
      ${cajero != null && cajero != 'Todos' ? 'AND u.nombre = \$${3}' : ''}
      ${formaPago != null && formaPago != 'Todas' ? 'AND v.forma_pago = \$${3 + (cajero != null && cajero != 'Todos' ? 1 : 0)}' : ''}
      ORDER BY v.created_at DESC
    ''', params: [
      desde.toUtc().toIso8601String(),
      hasta.toUtc().toIso8601String(),
      if (cajero != null && cajero != 'Todos') cajero,
      if (formaPago != null && formaPago != 'Todas') formaPago,
    ]);
    // Normalizar campos numéricos (Postgres puede devolver `numeric` como String)
    return rows.map((v) {
      return {
        ...v,
        'total': _toDouble(v['total']),
        'tasa_bs': _toDouble(v['tasa_bs']),
      };
    }).toList();
  }

  /// Detalle de items de una venta (desde items_json de pos_ventas)
  Future<List<Map<String, dynamic>>> getItemsVenta(int ventaId) async {
    final row = await _db.client
        .from('pos_ventas')
        .select('items_json')
        .eq('id', ventaId)
        .limit(1)
        .maybeSingle();
    
    if (row == null || row['items_json'] == null) return [];
    
    final itemsJson = row['items_json'] as String;
    final items = jsonDecode(itemsJson) as List;
    return items.cast<Map<String, dynamic>>().toList();
  }

  /// Movimientos de inventario en un rango de fechas
  Future<List<Map<String, dynamic>>> getMovimientos({
    required DateTime desde,
    required DateTime hasta,
    String? tipo,
    String? almacen,
  }) async {
    final params = <dynamic>[
      desde.toUtc().toIso8601String(),
      hasta.toUtc().toIso8601String(),
    ];
    var sql =
        'SELECT m.*, p.nombre AS __producto_nombre FROM movimientos m '
        'INNER JOIN productos p ON p.id = m.producto_id '
        'WHERE m.fecha_movimiento >= \$1 AND m.fecha_movimiento <= \$2';
    if (tipo != null && tipo != 'Todos') {
      sql += ' AND m.tipo = \$${params.length + 1}';
      params.add(tipo);
    }
    if (almacen != null && almacen != 'Todos') {
      sql += ' AND m.almacen = \$${params.length + 1}';
      params.add(almacen);
    }
    sql += ' ORDER BY m.fecha_movimiento DESC';

    final rows = await _db.executeSql(sql, params: params);

    // Mapear producto_nombre desde el join
    return rows.map((m) {
      final nombre = m['__producto_nombre'] as String?;
      return {
        ...m,
        '__producto_nombre': null,
        'producto_nombre': nombre ?? 'Producto #${m['producto_id']}',
        'productos': nombre == null ? null : {'nombre': nombre},
      };
    }).toList();
  }

  /// KPIs principales para dashboard (agregación en SQL, sin N+1).
  Future<Map<String, dynamic>> getKPIs({
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final rows = await _db.executeSql('''
      SELECT
        COALESCE(SUM(total), 0)::numeric AS total_ventas,
        COUNT(*) AS num_comandas,
        COALESCE(SUM(
          (SELECT COALESCE(SUM((x->>'cantidad')::numeric), 0)
           FROM json_array_elements(items_json::json) x)
        ), 0)::numeric AS productos_vendidos
      FROM pos_ventas
      WHERE created_at >= \$1 AND created_at <= \$2
    ''', params: [
      desde.toUtc().toIso8601String(),
      hasta.toUtc().toIso8601String(),
    ]);

    final r = rows.isNotEmpty ? rows.first : null;
    final totalVentas = _toDouble(r?['total_ventas']);
    final numComandas = _toInt(r?['num_comandas']);
    final productosVendidos = _toInt(r?['productos_vendidos']);

    return {
      'total_ventas': totalVentas,
      'ticket_promedio': numComandas > 0 ? totalVentas / numComandas : 0,
      'num_comandas': numComandas,
      'productos_vendidos': productosVendidos,
    };
  }

  /// Top productos vendidos (agregación en SQL, sin N+1).
  Future<List<Map<String, dynamic>>> getTopProductos({
    required DateTime desde,
    required DateTime hasta,
    int limit = 10,
  }) async {
    final rows = await _db.executeSql('''
      SELECT COALESCE(v.item->>'producto_id', v.item->>'id') AS producto_id,
             v.item->>'nombre' AS nombre,
             SUM((v.item->>'cantidad')::numeric) AS cantidad,
             SUM((v.item->>'cantidad')::numeric * COALESCE((v.item->>'precio')::numeric, 0)) AS total
      FROM pos_ventas p
      CROSS JOIN LATERAL json_array_elements(p.items_json::json) v(item)
      WHERE p.created_at >= \$1 AND p.created_at <= \$2
      GROUP BY COALESCE(v.item->>'producto_id', v.item->>'id'), v.item->>'nombre'
      ORDER BY total DESC
      LIMIT \$3
    ''', params: [
      desde.toUtc().toIso8601String(),
      hasta.toUtc().toIso8601String(),
      limit,
    ]);

    return rows.map((r) => {
      'producto_id': int.tryParse('${r['producto_id']}') ?? 0,
      'nombre': r['nombre'] as String? ?? 'Producto #${r['producto_id']}',
      'cantidad': _toDouble(r['cantidad']),
      'total': _toDouble(r['total']),
    }).toList();
  }

  /// Tendencia de ventas por día (agregación en SQL, sin N+1).
  Future<List<Map<String, dynamic>>> getTendenciaVentas({
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final rows = await _db.executeSql('''
      SELECT substring(created_at, 1, 10) AS fecha, SUM(total) AS total
      FROM pos_ventas
      WHERE created_at >= \$1 AND created_at <= \$2
      GROUP BY substring(created_at, 1, 10)
      ORDER BY fecha ASC
    ''', params: [
      desde.toUtc().toIso8601String(),
      hasta.toUtc().toIso8601String(),
    ]);

    return rows.map((r) => {
      'fecha': r['fecha'] as String? ?? '',
      'total': _toDouble(r['total']),
    }).toList();
  }

  /// Historial detallado de un producto: ventas, entradas, salidas, traslados, ajustes.
  /// Para entradas calcula la frecuencia promedio (días entre entradas).
  Future<Map<String, dynamic>> getProductoDetalle({
    required int productoId,
    required DateTime desde,
    required DateTime hasta,
  }) async {
    // Ventas del producto
    final ventasRows = await _db.executeSql('''
      SELECT
        v.id,
        v.correlativo,
        v.total,
        v.created_at,
        u.nombre AS cajero_nombre,
        m.nombre AS mesa_nombre,
        h.numero AS habitacion_numero,
        (item->>'cantidad')::numeric AS cantidad,
        (item->>'precio')::numeric AS precio,
        (item->>'cantidad')::numeric * COALESCE((item->>'precio')::numeric, 0) AS subtotal
      FROM pos_ventas v
      CROSS JOIN LATERAL json_array_elements(v.items_json::json) item
      LEFT JOIN pos_usuarios u ON u.id = v.usuario_id
      LEFT JOIN pos_mesas m ON m.id = v.mesa_id
      LEFT JOIN pos_habitaciones h ON h.id = v.habitacion_id
      WHERE v.created_at >= \$1 AND v.created_at <= \$2
        AND COALESCE(item->>'producto_id', item->>'id') = \$3
      ORDER BY v.created_at DESC
    ''', params: [
      desde.toUtc().toIso8601String(),
      hasta.toUtc().toIso8601String(),
      productoId.toString(),
    ]);

    // Movimientos de inventario del producto
    final movRows = await _db.executeSql('''
      SELECT
        m.id,
        m.tipo,
        m.cantidad,
        m.cantidad_anterior,
        m.cantidad_nueva,
        m.peso_total,
        m.observaciones,
        m.almacen,
        m.fecha_movimiento,
        m.registrado_por
      FROM movimientos m
      WHERE m.producto_id = \$1
        AND m.fecha_movimiento >= \$2 AND m.fecha_movimiento <= \$3
      ORDER BY m.fecha_movimiento DESC
    ''', params: [
      productoId,
      desde.toUtc().toIso8601String(),
      hasta.toUtc().toIso8601String(),
    ]);

    // Normalizar campos numéricos (Postgres devuelve `numeric` como String)
    final ventasNorm = ventasRows.map((v) {
      return {
        ...v,
        'total': _toDouble(v['total']),
        'cantidad': _toDouble(v['cantidad']),
        'precio': _toDouble(v['precio']),
        'subtotal': _toDouble(v['subtotal']),
      };
    }).toList();
    final movNorm = movRows.map((m) => {
      ...m,
      'cantidad': _toDouble(m['cantidad']),
      'cantidad_anterior': _toDouble(m['cantidad_anterior']),
      'cantidad_nueva': _toDouble(m['cantidad_nueva']),
      'peso_total': _toDouble(m['peso_total']),
    }).toList();

    // Calcular frecuencia de entradas (días promedio entre entradas)
    final entradas = movNorm.where((m) => m['tipo'] == 'entrada' || m['tipo'] == 'entrada_produccion').toList();
    double? frecuenciaEntradasDias;
    if (entradas.length >= 2) {
      final fechas = entradas.map((e) => DateTime.parse(e['fecha_movimiento'] as String)).toList();
      fechas.sort();
      final intervalos = <int>[];
      for (int i = 1; i < fechas.length; i++) {
        intervalos.add(fechas[i].difference(fechas[i - 1]).inDays);
      }
      frecuenciaEntradasDias = intervalos.reduce((a, b) => a + b) / intervalos.length;
    }

    return {
      'ventas': ventasNorm,
      'movimientos': movNorm,
      'frecuencia_entradas_dias': frecuenciaEntradasDias,
      'total_entradas': entradas.length,
    };
  }

  /// Buscar productos para autocomplete
  Future<List<Map<String, dynamic>>> buscarProductos(String query, {int limit = 20}) async {
    final rows = await _db.executeSql('''
      SELECT id, nombre, codigo, unidad_medida, es_pesable, stock_minimo
      FROM productos
      WHERE activo = true
        AND (nombre ILIKE \$1 OR codigo ILIKE \$1)
      ORDER BY nombre
      LIMIT \$2
    ''', params: ['%$query%', limit]);
    return rows;
  }
}

final reportesRepoProvider = Provider<ReportesRepository>((ref) {
  final db = ref.watch(postgresServiceProvider);
  if (db == null) throw Exception('PostgreSQL no configurado');
  return ReportesRepository(db);
});