import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/postgres_providers.dart';
import '../../../core/data/postgres_service.dart';

/// Orden del ranking de top productos. [sql] es el identificador interno del
/// ORDER BY (constante de este archivo; nunca viene del usuario).
enum _TopOrden {
  facturacion('total'),
  cantidad('cantidad');

  const _TopOrden(this.sql);
  final String sql;
}

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

  // ---------------------------------------------------------------------------
  // Límites de fecha
  //
  // `pos_ventas.created_at` es TEXT en hora local SIN zona (ej.
  // "2026-10-18T14:32:54.475087"), así que sus consultas se comparan en local;
  // mandar UTC corría ~4 h la ventana y dejaba fuera lo recién vendido.
  // `movimientos` y `pos_cierres` sí son timestamptz: ahí el rango va en UTC.
  // En ambos casos el "hasta" cierra el día completo (23:59:59.999999), para
  // que el día elegido en el calendario quede incluido.
  // ---------------------------------------------------------------------------

  /// Inicio del día (00:00) en hora local, para columnas TEXT.
  static String _inicioDiaLocal(DateTime f) =>
      DateTime(f.year, f.month, f.day).toIso8601String();

  /// Fin del día (23:59:59.999999) en hora local, para columnas TEXT.
  static String _finDiaLocal(DateTime f) =>
      DateTime(f.year, f.month, f.day, 23, 59, 59, 999, 999).toIso8601String();

  /// Inicio del día local convertido a UTC, para columnas timestamptz.
  static String _inicioDiaUtc(DateTime f) =>
      DateTime(f.year, f.month, f.day).toUtc().toIso8601String();

  /// Fin del día local convertido a UTC, para columnas timestamptz.
  static String _finDiaUtc(DateTime f) => DateTime(
        f.year,
        f.month,
        f.day,
        23,
        59,
        59,
        999,
        999,
      ).toUtc().toIso8601String();

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
      LEFT JOIN habitaciones h ON h.id = v.habitacion_id
      LEFT JOIN usuarios u ON u.id = v.usuario_id
      WHERE v.created_at >= \$1 AND v.created_at <= \$2
      ${cajero != null && cajero != 'Todos' ? 'AND u.nombre = \$${3}' : ''}
      ${formaPago != null && formaPago != 'Todas' ? 'AND v.forma_pago = \$${3 + (cajero != null && cajero != 'Todos' ? 1 : 0)}' : ''}
      ORDER BY v.created_at DESC
    ''', params: [
      _inicioDiaLocal(desde),
      _finDiaLocal(hasta),
      if (cajero != null && cajero != 'Todos') cajero,
      if (formaPago != null && formaPago != 'Todas') formaPago,
    ]);
    // Normalizar campos numéricos (Postgres puede devolver `numeric` como String)
    return rows.map((v) {
      return <String, dynamic>{
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
      _inicioDiaUtc(desde),
      _finDiaUtc(hasta),
    ];
    // El rango de fechas y el orden usan la fecha de negocio del traslado
    // (fecha_traslado = fecha en que se creó la requisición) cuando existe. Sin
    // esto, un traslado de una requisición totalizada días después se contaría
    // en el día equivocado. La columna real fecha_movimiento sigue viniendo en
    // el SELECT y la pantalla la usa solo si no hay fecha_traslado.
    var sql =
        'SELECT m.*, p.nombre AS __producto_nombre FROM movimientos m '
        'INNER JOIN productos p ON p.id = m.producto_id '
        'WHERE COALESCE(m.fecha_traslado, m.fecha_movimiento) >= \$1 '
        'AND COALESCE(m.fecha_traslado, m.fecha_movimiento) <= \$2';
    if (tipo != null && tipo != 'Todos') {
      sql += ' AND m.tipo = \$${params.length + 1}';
      params.add(tipo);
    }
    if (almacen != null && almacen != 'Todos') {
      sql += ' AND m.almacen = \$${params.length + 1}';
      params.add(almacen);
    }
    sql += ' ORDER BY COALESCE(m.fecha_traslado, m.fecha_movimiento) DESC';

    final rows = await _db.executeSql(sql, params: params);

    // Mapear producto_nombre desde el join
    return rows.map((m) {
      final nombre = m['__producto_nombre'] as String?;
      return <String, dynamic>{
        ...m,
        '__producto_nombre': null,
        'producto_nombre': nombre ?? 'Producto #${m['producto_id']}',
        'productos': nombre == null ? null : {'nombre': nombre},
      };
    }).toList();
  }

  /// KPIs principales para dashboard (agregación en SQL, sin N+1).
  ///
  /// Las ventas anuladas quedan FUERA de los totales (se cuentan aparte en
  /// `num_anuladas`/`total_anuladas` para mostrar el dato sin inflar nada).
  Future<Map<String, dynamic>> getKPIs({
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final rows = await _db.executeSql('''
      SELECT
        COALESCE(SUM(total)
          FILTER (WHERE COALESCE(estado, 'vigente') = 'vigente'), 0)::numeric AS total_ventas,
        COUNT(*) FILTER (WHERE COALESCE(estado, 'vigente') = 'vigente') AS num_comandas,
        COUNT(*) FILTER (WHERE COALESCE(estado, 'vigente') <> 'vigente') AS num_anuladas,
        COALESCE(SUM(total)
          FILTER (WHERE COALESCE(estado, 'vigente') <> 'vigente'), 0)::numeric AS total_anuladas,
        COALESCE(SUM(
          (SELECT COALESCE(SUM((x->>'cantidad')::numeric), 0)
           FROM json_array_elements(items_json::json) x)
        ) FILTER (WHERE COALESCE(estado, 'vigente') = 'vigente'), 0)::numeric
          AS productos_vendidos
      FROM pos_ventas
      WHERE created_at >= \$1 AND created_at <= \$2
    ''', params: [
      _inicioDiaLocal(desde),
      _finDiaLocal(hasta),
    ]);

    final r = rows.isNotEmpty ? rows.first : null;
    final totalVentas = _toDouble(r?['total_ventas']);
    final numComandas = _toInt(r?['num_comandas']);
    final productosVendidos = _toInt(r?['productos_vendidos']);

    return <String, dynamic>{
      'total_ventas': totalVentas,
      'ticket_promedio': numComandas > 0 ? totalVentas / numComandas : 0,
      'num_comandas': numComandas,
      'productos_vendidos': productosVendidos,
      'num_anuladas': _toInt(r?['num_anuladas']),
      'total_anuladas': _toDouble(r?['total_anuladas']),
    };
  }

  /// Top productos: rankings por facturación y por cantidad, en paralelo.
  Future<({List<Map<String, dynamic>> porFacturacion, List<Map<String, dynamic>> porCantidad})>
      getTopProductosRankings({
    required DateTime desde,
    required DateTime hasta,
    int limit = 10,
  }) async {
    final fFacturacion = _topProductos(
        desde: desde, hasta: hasta, limit: limit, orden: _TopOrden.facturacion);
    final fCantidad = _topProductos(
        desde: desde, hasta: hasta, limit: limit, orden: _TopOrden.cantidad);
    final results = await Future.wait([fFacturacion, fCantidad]);
    return (porFacturacion: results[0], porCantidad: results[1]);
  }

  /// Top productos vendidos (agregación en SQL, sin N+1). Excluye anuladas.
  Future<List<Map<String, dynamic>>> getTopProductos({
    required DateTime desde,
    required DateTime hasta,
    int limit = 10,
  }) =>
      _topProductos(
          desde: desde, hasta: hasta, limit: limit, orden: _TopOrden.facturacion);

  Future<List<Map<String, dynamic>>> _topProductos({
    required DateTime desde,
    required DateTime hasta,
    required int limit,
    required _TopOrden orden,
  }) async {
    final rows = await _db.executeSql('''
      SELECT COALESCE(v.item->>'producto_id', v.item->>'id') AS producto_id,
             v.item->>'nombre' AS nombre,
             SUM((v.item->>'cantidad')::numeric) AS cantidad,
             SUM((v.item->>'cantidad')::numeric * COALESCE((v.item->>'precio')::numeric, 0)) AS total
      FROM pos_ventas p
      CROSS JOIN LATERAL json_array_elements(p.items_json::json) v(item)
      WHERE p.created_at >= \$1 AND p.created_at <= \$2
        AND COALESCE(p.estado, 'vigente') = 'vigente'
      GROUP BY COALESCE(v.item->>'producto_id', v.item->>'id'), v.item->>'nombre'
      ORDER BY ${orden.sql} DESC
      LIMIT \$3
    ''', params: [
      _inicioDiaLocal(desde),
      _finDiaLocal(hasta),
      limit,
    ]);

    return rows.map((r) => <String, dynamic>{
      'producto_id': int.tryParse('${r['producto_id']}') ?? 0,
      'nombre': r['nombre'] as String? ?? 'Producto #${r['producto_id']}',
      'cantidad': _toDouble(r['cantidad']),
      'total': _toDouble(r['total']),
    }).toList();
  }

  /// Tendencia de ventas por día (agregación en SQL, sin N+1).
  /// Excluye anuladas para que la curva refleje ventas reales.
  Future<List<Map<String, dynamic>>> getTendenciaVentas({
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final rows = await _db.executeSql('''
      SELECT substring(created_at, 1, 10) AS fecha, SUM(total) AS total
      FROM pos_ventas
      WHERE created_at >= \$1 AND created_at <= \$2
        AND COALESCE(estado, 'vigente') = 'vigente'
      GROUP BY substring(created_at, 1, 10)
      ORDER BY fecha ASC
    ''', params: [
      _inicioDiaLocal(desde),
      _finDiaLocal(hasta),
    ]);

    return rows.map((r) => <String, dynamic>{
      'fecha': r['fecha'] as String? ?? '',
      'total': _toDouble(r['total']),
    }).toList();
  }

  /// Ventas por hora del día (0-23) para detectar picos de venta.
  /// Excluye anuladas. `created_at` es texto ISO local (ej.
  /// `2026-10-18T14:32:54.475087`), así que la hora sale del substring 12-13.
  Future<List<Map<String, dynamic>>> getVentasPorHora({
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final rows = await _db.executeSql('''
      SELECT substring(created_at, 12, 2)::int AS hora,
             COALESCE(SUM(total), 0)::numeric AS total,
             COUNT(*) AS num_ventas
      FROM pos_ventas
      WHERE created_at >= \$1 AND created_at <= \$2
        AND COALESCE(estado, 'vigente') = 'vigente'
        AND substring(created_at, 12, 2) ~ '^[0-9]{2}\$'
      GROUP BY 1
      ORDER BY 1 ASC
    ''', params: [
      // created_at es TEXT en hora local: se compara en local (día completo).
      _inicioDiaLocal(desde),
      _finDiaLocal(hasta),
    ]);

    return rows.map((r) => <String, dynamic>{
      'hora': _toInt(r['hora']),
      'total': _toDouble(r['total']),
      'num_ventas': _toInt(r['num_ventas']),
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
      LEFT JOIN usuarios u ON u.id = v.usuario_id
      LEFT JOIN pos_mesas m ON m.id = v.mesa_id
      LEFT JOIN habitaciones h ON h.id = v.habitacion_id
      WHERE v.created_at >= \$1 AND v.created_at <= \$2
        AND COALESCE(item->>'producto_id', item->>'id') = \$3
      ORDER BY v.created_at DESC
    ''', params: [
      _inicioDiaLocal(desde),
      _finDiaLocal(hasta),
      productoId.toString(),
    ]);

    // Movimientos de inventario del producto.
    // Este reporte ordena por la fecha de negocio a proposito, y no es la misma
    // regla que el historial: aca no se pinta la cadena
    // `cantidad_anterior -> cantidad_nueva` (solo se selecciona), asi que el
    // listado puede ir en orden cronologico de negocio sin que la cuenta se vea
    // rota. Las vistas que si pintan la cadena ordenan por `id`; ver
    // tool/verificar_cadena_movimientos.py.
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
        COALESCE(m.fecha_traslado, m.fecha_movimiento) AS fecha_movimiento,
        m.registrado_por
      FROM movimientos m
      WHERE m.producto_id = \$1
        AND COALESCE(m.fecha_traslado, m.fecha_movimiento) >= \$2
        AND COALESCE(m.fecha_traslado, m.fecha_movimiento) <= \$3
      ORDER BY COALESCE(m.fecha_traslado, m.fecha_movimiento) DESC
    ''', params: [
      productoId,
      _inicioDiaUtc(desde),
      _finDiaUtc(hasta),
    ]);

    // Normalizar campos numéricos (Postgres devuelve `numeric` como String)
    final ventasNorm = ventasRows.map((v) {
      return <String, dynamic>{
        ...v,
        'total': _toDouble(v['total']),
        'cantidad': _toDouble(v['cantidad']),
        'precio': _toDouble(v['precio']),
        'subtotal': _toDouble(v['subtotal']),
      };
    }).toList();
    final movNorm = movRows.map((m) => <String, dynamic>{
      ...m,
      'cantidad': _toDouble(m['cantidad']),
      'cantidad_anterior': _toDouble(m['cantidad_anterior']),
      'cantidad_nueva': _toDouble(m['cantidad_nueva']),
      'peso_total': _toDouble(m['peso_total']),
    }).toList();

    // Calcular frecuencia de entradas (días promedio entre entradas)
    final entradas = movNorm.where((m) => m['tipo'] == 'entrada' || m['tipo'] == 'entrada_produccion').toList();
    double? frecuenciaEntradasDias;
    // `fecha_movimiento` puede llegar como texto (proxy) o como DateTime
    // (driver nativo, columna timestamptz): se normaliza con `tryParse`.
    final fechas = entradas
        .map((e) => DateTime.tryParse('${e['fecha_movimiento']}'))
        .whereType<DateTime>()
        .toList();
    if (fechas.length >= 2) {
      fechas.sort();
      final intervalos = <int>[];
      for (int i = 1; i < fechas.length; i++) {
        intervalos.add(fechas[i].difference(fechas[i - 1]).inDays);
      }
      frecuenciaEntradasDias =
          intervalos.reduce((a, b) => a + b) / intervalos.length;
    }

    return <String, dynamic>{
      'ventas': ventasNorm,
      'movimientos': movNorm,
      'frecuencia_entradas_dias': frecuenciaEntradasDias,
      'total_entradas': entradas.length,
    };
  }

  /// Buscar productos para autocomplete.
  ///
  /// El mismo valor va en dos columnas, pero no se puede repetir el `$1`: el
  /// proxy (`convert_placeholders` en tool/server.py) convierte cada aparición
  /// de `$n` en un `%s`, así que un placeholder repetido deja más `%s` que
  /// parámetros y psycopg rechaza la consulta. Por eso el patrón viaja dos
  /// veces, con su propio número.
  Future<List<Map<String, dynamic>>> buscarProductos(String query, {int limit = 20}) async {
    final patron = '%$query%';
    final rows = await _db.executeSql('''
      SELECT id, nombre, codigo, unidad_medida, es_pesable, stock_minimo
      FROM productos
      WHERE activo = true
        AND (nombre ILIKE \$1 OR codigo ILIKE \$2)
      ORDER BY nombre
      LIMIT \$3
    ''', params: [patron, patron, limit]);
    return rows;
  }
}

final reportesRepoProvider = Provider<ReportesRepository>((ref) {
  final db = ref.watch(postgresServiceProvider);
  if (db == null) throw Exception('PostgreSQL no configurado');
  return ReportesRepository(db);
});