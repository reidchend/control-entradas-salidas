import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/postgres_providers.dart';
import '../../../core/data/postgres_service.dart';

class ReportesRepository {
  ReportesRepository(this._db);
  final PostgresService _db;

  /// Ventas en un rango de fechas con filtros opcionales
  Future<List<Map<String, dynamic>>> getVentas({
    required DateTime desde,
    required DateTime hasta,
    String? cajero,
    String? formaPago,
  }) async {
    dynamic query = _db.client
        .from('pos_ventas')
        .select()
        .gte('created_at', desde.toUtc().toIso8601String())
        .lte('created_at', hasta.toUtc().toIso8601String());

    if (cajero != null && cajero != 'Todos') {
      query = query.filter('cajero', 'eq', cajero);
    }
    if (formaPago != null && formaPago != 'Todas') {
      query = query.filter('forma_pago', 'eq', formaPago);
    }

    query = query.order('created_at', ascending: false);

    return await query;
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
    final totalVentas = (r?['total_ventas'] as num?)?.toDouble() ?? 0;
    final numComandas = (r?['num_comandas'] as num?)?.toInt() ?? 0;
    final productosVendidos = (r?['productos_vendidos'] as num?)?.toInt() ?? 0;

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
      'cantidad': (r['cantidad'] as num?)?.toDouble() ?? 0,
      'total': (r['total'] as num?)?.toDouble() ?? 0,
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
      'total': (r['total'] as num?)?.toDouble() ?? 0,
    }).toList();
  }
}

final reportesRepoProvider = Provider<ReportesRepository>((ref) {
  final db = ref.watch(postgresServiceProvider);
  if (db == null) throw Exception('PostgreSQL no configurado');
  return ReportesRepository(db);
});