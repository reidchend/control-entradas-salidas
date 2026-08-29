import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/supabase_providers.dart';
import '../../../core/data/supabase_service.dart';

class ReportesRepository {
  ReportesRepository(this._db);
  final SupabaseService _db;

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
        .gte('created_at', desde.toIso8601String())
        .lte('created_at', hasta.toIso8601String());

    if (cajero != null && cajero != 'Todos') {
      query = query.filter('cajero', 'eq', cajero);
    }
    if (formaPago != null && formaPago != 'Todas') {
      query = query.filter('forma_pago', 'eq', formaPago);
    }

    query = query.order('created_at', ascending: false);

    return await query;
  }

  /// Detalle de items de una venta
  Future<List<Map<String, dynamic>>> getItemsVenta(int ventaId) async {
    return await _db.client
        .from('pos_venta_items')
        .select()
        .eq('venta_id', ventaId);
  }

  /// Movimientos de inventario en un rango de fechas
  Future<List<Map<String, dynamic>>> getMovimientos({
    required DateTime desde,
    required DateTime hasta,
    String? tipo,
    String? almacen,
  }) async {
    dynamic query = _db.client
        .from('movimientos')
        .select()
        .gte('fecha_movimiento', desde.toIso8601String())
        .lte('fecha_movimiento', hasta.toIso8601String());

    if (tipo != null && tipo != 'Todos') {
      query = query.filter('tipo', 'eq', tipo);
    }
    if (almacen != null && almacen != 'Todos') {
      query = query.filter('almacen', 'eq', almacen);
    }

    query = query.order('fecha_movimiento', ascending: false);

    return await query;
  }

  /// KPIs principales para dashboard
  Future<Map<String, dynamic>> getKPIs({
    required DateTime desde,
    required DateTime hasta,
  }) async {
    // Ventas totales
    final ventas = await getVentas(desde: desde, hasta: hasta);
    final totalVentas = ventas.fold<double>(0, (sum, v) => sum + ((v['total'] as num?)?.toDouble() ?? 0));
    final numComandas = ventas.length;
    final ticketPromedio = numComandas > 0 ? totalVentas / numComandas : 0;

    // Productos vendidos (desde items de ventas)
    int totalProductos = 0;
    for (final v in ventas) {
      final items = await getItemsVenta(v['id'] as int);
      totalProductos += items.fold<int>(0, (sum, i) => sum + ((i['cantidad'] as num?)?.toInt() ?? 0));
    }

    return {
      'total_ventas': totalVentas,
      'ticket_promedio': ticketPromedio,
      'num_comandas': numComandas,
      'productos_vendidos': totalProductos,
    };
  }

  /// Top productos vendidos
  Future<List<Map<String, dynamic>>> getTopProductos({
    required DateTime desde,
    required DateTime hasta,
    int limit = 10,
  }) async {
    final ventas = await getVentas(desde: desde, hasta: hasta);
    final Map<int, Map<String, dynamic>> acumulado = {};

    for (final v in ventas) {
      final items = await getItemsVenta(v['id'] as int);
      for (final i in items) {
        final pid = i['producto_id'] as int;
        final cant = (i['cantidad'] as num?)?.toDouble() ?? 0;
        final precio = (i['precio'] as num?)?.toDouble() ?? 0;
        final nombre = i['nombre'] as String? ?? 'Producto #$pid';

        if (acumulado.containsKey(pid)) {
          acumulado[pid]!['cantidad'] = (acumulado[pid]!['cantidad'] as double) + cant;
          acumulado[pid]!['total'] = (acumulado[pid]!['total'] as double) + (cant * precio);
        } else {
          acumulado[pid] = {
            'producto_id': pid,
            'nombre': nombre,
            'cantidad': cant,
            'total': cant * precio,
          };
        }
      }
    }

    final lista = acumulado.values.toList()
      ..sort((a, b) => (b['total'] as double).compareTo(a['total'] as double));

    return lista.take(limit).toList();
  }

  /// Tendencia de ventas por día
  Future<List<Map<String, dynamic>>> getTendenciaVentas({
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final ventas = await getVentas(desde: desde, hasta: hasta);
    final Map<String, double> porDia = {};

    for (final v in ventas) {
      final fecha = (v['created_at'] as String).substring(0, 10); // YYYY-MM-DD
      final total = (v['total'] as num?)?.toDouble() ?? 0;
      porDia[fecha] = (porDia[fecha] ?? 0) + total;
    }

    return porDia.entries
        .map((e) => {'fecha': e.key, 'total': e.value})
        .toList()
      ..sort((a, b) => (a['fecha'] as String).compareTo(b['fecha'] as String));
  }
}

final reportesRepoProvider = Provider<ReportesRepository>((ref) {
  final db = ref.watch(supabaseServiceProvider);
  if (db == null) throw Exception('Supabase no configurado');
  return ReportesRepository(db);
});