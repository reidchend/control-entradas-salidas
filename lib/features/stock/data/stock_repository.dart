import '../../../core/data/postgres_service.dart';
import '../../../core/models/categoria.dart';
import '../../../core/models/existencia.dart';
import '../../../core/models/movimiento.dart';
import '../../../core/models/producto.dart';

class StockStats {
  const StockStats({this.total = 0, this.bajo = 0, this.agotado = 0});
  final int total;
  final int bajo;
  final int agotado;
}

class StockRepository {
  StockRepository(this._db);
  final PostgresService _db;

  Future<List<Categoria>> loadCategorias() async {
    final rows = await _db.fetchAll(
      'categorias',
      orderBy: 'nombre',
      filters: {'activo': true},
    );
    return rows.map(Categoria.fromMap).toList();
  }

  Future<List<String>> getAlmacenes() async {
    final rows = await _db.executeSql(
      'SELECT DISTINCT almacen FROM existencias ORDER BY almacen',
    );
    return rows.map((r) => r['almacen'] as String).toList();
  }

  Future<List<Producto>> loadProductos({int limit = 50}) async {
    final rows = await _db.fetchAll(
      'productos',
      orderBy: 'nombre',
      limit: limit,
      filters: {'activo': true},
    );
    return rows.map(Producto.fromMap).toList();
  }

  Future<Map<int, Map<String, double>>> getExistenciasMap(
      List<int> productoIds) async {
    final result = <int, Map<String, double>>{};
    if (productoIds.isEmpty) return result;
    final rows = await _db.fetchAll(
      'existencias',
      filters: {'producto_id': productoIds},
    );
    for (final e in rows) {
      final pid = e['producto_id'] as int;
      final almacen = e['almacen'] as String;
      final cant = (e['cantidad'] as num?)?.toDouble() ?? 0;
      result.putIfAbsent(pid, () => {});
      result[pid]![almacen] = cant;
    }
    return result;
  }

  Future<Map<int, double>> getStockTotal(List<int> productoIds) async {
    final map = await getExistenciasMap(productoIds);
    return {
      for (final e in map.entries)
        e.key: e.value.values.fold<double>(0, (a, b) => a + b),
    };
  }

  Future<List<Producto>> filterProductos({
    String search = '',
    int? categoriaId,
    String? almacen,
    String? stockStatus,
    int limit = 50,
  }) async {
    // Filtros de activo/categoría/búsqueda se aplican en SQL para que el
    // LIMIT no corte productos de la categoría seleccionada.
    final params = <dynamic>[];
    final conds = <String>['p.activo = TRUE'];
    if (categoriaId != null) {
      params.add(categoriaId);
      conds.add('p.categoria_id = \$${params.length}');
    }
    if (search.isNotEmpty) {
      params.add('%${search.toLowerCase()}%');
      conds.add('LOWER(p.nombre) LIKE \$${params.length}');
    }
    final where = conds.join(' AND ');

    final necesitaStock = almacen != null || stockStatus != null;
    List<Map<String, dynamic>> rows;
    if (necesitaStock) {
      String join;
      if (almacen != null) {
        params.add(almacen);
        // Solo productos con existencias en ese almacén.
        join = 'JOIN existencias e ON e.producto_id = p.id '
            'AND e.almacen = \$${params.length}';
      } else {
        join = 'LEFT JOIN existencias e ON e.producto_id = p.id';
      }
      final stockExpr = 'COALESCE(SUM(e.cantidad), 0) AS stock_prd';
      var sql = 'SELECT p.*, $stockExpr FROM productos p '
          '$join WHERE $where GROUP BY p.id ORDER BY p.nombre ASC';
      if (stockStatus == 'out') {
        sql += ' HAVING stock_prd <= 0';
      }
      rows = await _db.executeSql(sql, params: params);
    } else {
      rows = await _db.executeSql(
        'SELECT p.* FROM productos p WHERE $where '
        'ORDER BY p.nombre ASC LIMIT $limit',
        params: params,
      );
    }

    final productos = rows.map(Producto.fromMap).toList();

    // El stock ya viene calculado en cada fila cuando hubo JOIN.
    final stock = {
      for (final r in rows)
        if (r.containsKey('stock_prd') && r['stock_prd'] != null)
          r['id'] as int: (r['stock_prd'] as num).toDouble(),
    };

    if (stockStatus == 'low') {
      return productos
          .where((p) {
            final s = stock[p.id] ?? 0;
            return s > 0 &&
                s <= (p.stockMinimo > 0 ? p.stockMinimo : double.infinity);
          })
          .take(limit)
          .toList();
    }
    return productos.take(limit).toList();
  }

  Future<Map<int, double>> getStockTotalAlmacenBase(
      List<int> productoIds, String? almacen) async {
    if (productoIds.isEmpty) return {};
    final conds = <String>['producto_id = ANY(\$1)'];
    final params = <dynamic>[productoIds];
    if (almacen != null) {
      conds.add('almacen = \$2');
      params.add(almacen);
    }
    final sql = 'SELECT producto_id, SUM(cantidad) AS stock '
        'FROM existencias WHERE ${conds.join(' AND ')} GROUP BY producto_id';
    final rows = await _db.executeSql(sql, params: params);
    return {
      for (final r in rows)
        r['producto_id'] as int: (r['stock'] as num).toDouble(),
    };
  }

  Future<StockStats> getStockStats({String? almacen}) async {
    final params = <dynamic>[];
    String sql;
    if (almacen == null) {
      sql = '''
        SELECT COUNT(DISTINCT p.id) AS total,
          COUNT(DISTINCT p.id) FILTER (WHERE stock <= 0) AS agotado,
          COUNT(DISTINCT p.id) FILTER (
            WHERE stock > 0 AND p.stock_minimo > 0 AND stock <= p.stock_minimo
          ) AS bajo
        FROM productos p
        LEFT JOIN (
          SELECT producto_id, SUM(cantidad) AS stock
          FROM existencias GROUP BY producto_id
        ) s ON s.producto_id = p.id
        WHERE p.activo = TRUE
      ''';
    } else {
      params.add(almacen);
      sql = '''
        SELECT COUNT(DISTINCT p.id) AS total,
          COUNT(DISTINCT p.id) FILTER (WHERE stock <= 0) AS agotado,
          COUNT(DISTINCT p.id) FILTER (
            WHERE stock > 0 AND p.stock_minimo > 0 AND stock <= p.stock_minimo
          ) AS bajo
        FROM productos p
        LEFT JOIN (
          SELECT producto_id, SUM(cantidad) AS stock
          FROM existencias WHERE almacen = \$1 GROUP BY producto_id
        ) s ON s.producto_id = p.id
        WHERE p.activo = TRUE
      ''';
    }
    final rows = await _db.executeSql(sql, params: params);
    final r = rows.isNotEmpty ? rows.first : <String, dynamic>{};
    return StockStats(
      total: (r['total'] as num?)?.toInt() ?? 0,
      bajo: (r['bajo'] as num?)?.toInt() ?? 0,
      agotado: (r['agotado'] as num?)?.toInt() ?? 0,
    );
  }

  Future<List<Existencia>> getExistenciasProducto(int productoId) async {
    final rows = await _db.fetchAll(
      'existencias',
      filters: {'producto_id': productoId},
      orderBy: 'almacen',
    );
    return rows.map(Existencia.fromMap).toList();
  }

  /// Existencias de varios productos en **una sola query** (`producto_id = ANY`)
  /// agrupadas por producto. Sustituye el patrón N+1 de la rejilla de stock.
  Future<Map<int, List<Existencia>>> getExistenciasDeProductos(
      List<int> productoIds) async {
    if (productoIds.isEmpty) return {};
    final rows = await _db.executeSql(
      'SELECT * FROM existencias WHERE producto_id = ANY(\$1) '
      'ORDER BY almacen',
      params: [productoIds],
    );
    final map = <int, List<Existencia>>{};
    for (final r in rows) {
      final pid = r['producto_id'] as int;
      map.putIfAbsent(pid, () => []).add(Existencia.fromMap(r));
    }
    return map;
  }

  Future<List<Movimiento>> getProductoHistorial(int productoId,
      {int limit = 100}) async {
    final rows = await _db.fetchAll(
      'movimientos',
      filters: {'producto_id': productoId},
      orderBy: 'fecha_movimiento',
      ascending: false,
      limit: limit,
    );
    return rows.map(Movimiento.fromMap).toList();
  }

  Future<bool> ajustarExistencia({
    required int productoId,
    required String almacen,
    required double nuevaCantidad,
    String? motivo,
    String usuario = 'sistema',
  }) async {
    final rows = await _db.fetchAll(
      'existencias',
      filters: {'producto_id': productoId, 'almacen': almacen},
      orderBy: 'id',
      ascending: false,
      limit: 1,
    );
    final actual =
        rows.isNotEmpty ? (rows.first['cantidad'] as num?)?.toDouble() ?? 0 : 0.0;

    if ((nuevaCantidad - actual).abs() < 1e-9) return false;

    final pRows = await _db.fetchAll(
      'productos',
      filters: {'id': productoId},
      limit: 1,
    );
    final esPesable =
        pRows.isNotEmpty && (pRows.first['es_pesable'] == true || pRows.first['es_pesable'] == 1);
    final unidad =
        pRows.isNotEmpty ? (pRows.first['unidad_medida'] as String?) ?? 'unidad' : 'unidad';
    final now = DateTime.now().toIso8601String();

    await _db.insert('movimientos', {
      'producto_id': productoId,
      'tipo': 'ajuste',
      'cantidad': (nuevaCantidad - actual).abs(),
      'cantidad_anterior': actual,
      'cantidad_nueva': nuevaCantidad,
      'peso_total': esPesable ? nuevaCantidad : 0.0,
      'registrado_por': usuario,
      'observaciones': motivo ?? '',
      'almacen': almacen,
      'fecha_movimiento': now,
      'created_at': now,
    });

    if (rows.isNotEmpty) {
      await _db.updateById('existencias', rows.first['id'] as int, {
        'cantidad': nuevaCantidad,
      });
    } else {
      await _db.insert('existencias', {
        'producto_id': productoId,
        'almacen': almacen,
        'cantidad': nuevaCantidad,
        'unidad': unidad,
      });
    }
    return true;
  }
}