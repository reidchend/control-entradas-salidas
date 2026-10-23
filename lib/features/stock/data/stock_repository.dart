import '../../../core/data/postgres_service.dart';
import '../../../core/models/categoria.dart';
import '../../../core/models/existencia.dart';
import '../../../core/models/movimiento.dart';
import '../../../core/models/producto.dart';
import 'vinculo_producto.dart';

class StockStats {
  const StockStats({this.total = 0, this.bajo = 0, this.agotado = 0});
  final int total;
  final int bajo;
  final int agotado;
}

class StockRepository {
  StockRepository(this._db);
  final PostgresService _db;

  /// Categorías para los filtros de stock.
  ///
  /// Devuelve **todas**, incluidas las inactivas: el borrado de categorías es
  /// lógico (`activo = false`), así que un producto puede seguir apuntando a
  /// una categoría desactivada. Si se filtraran aquí, ese producto mostraría
  /// "S/C" en vez del nombre real. La UI marca las inactivas con "(inactiva)".
  Future<List<Categoria>> loadCategorias() async {
    final rows = await _db.fetchAll(
      'categorias',
      orderBy: 'nombre',
    );
    return rows.map(Categoria.fromMap).toList();
  }

  Future<List<String>> getAlmacenes() async {
    final rows = await _db.executeSql(
      'SELECT DISTINCT almacen FROM existencias ORDER BY almacen',
    );
    return rows.map((r) => r['almacen'] as String).toList();
  }

  /// Tipos de producto reales (DISTINCT de la tabla) para el filtro de la
  /// vista de stock. Solo trae los no vacíos: "Todos" los incluye igual.
  ///
  /// Agrupa por mayúsculas/minúsculas: en la BD conviven "PRODUCTO PARA USO
  /// INTERNO" y "productos para uso Interno" como tipos distintos, y
  /// mostrarlos por separado confundiría (filtrar uno dejaría fuera al
  /// otro). Devuelve el representante más frecuente de cada grupo; el
  /// filtro de `filterProductos` compara en LOWER para atrapar todas las
  /// variantes de escritura.
  Future<List<String>> getTiposProducto() async {
    final rows = await _db.executeSql(
      "SELECT tipo FROM ("
      "  SELECT tipo, ROW_NUMBER() OVER ("
      "    PARTITION BY LOWER(tipo) ORDER BY COUNT(*) DESC, tipo) AS rn"
      "  FROM productos"
      "  WHERE activo = TRUE AND COALESCE(tipo, '') <> ''"
      "  GROUP BY tipo"
      ") t WHERE rn = 1 ORDER BY LOWER(tipo)",
    );
    return rows.map((r) => r['tipo'] as String).toList();
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
    String? tipo,
    int limit = 50,
    int offset = 0,
  }) async {
    // Filtros de activo/categoría/búsqueda/tipo se aplican en SQL para que el
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
    if (tipo != null) {
      params.add(tipo);
      // LOWER de ambos lados: los tipos conviven con mayúsculas
      // inconsistentes en la BD ("PRODUCTO PARA USO INTERNO" vs
      // "productos para uso Interno") y el filtro debe atrapar todas.
      conds.add('LOWER(p.tipo) = LOWER(\$${params.length})');
    }
    final where = conds.join(' AND ');

    final necesitaStock = almacen != null || stockStatus != null;
    List<Map<String, dynamic>> rows;
    if (necesitaStock) {
      String join;
      if (almacen != null) {
        params.add(almacen);
        if (stockStatus != null) {
          // Con filtro de estado, LEFT JOIN: un producto sin fila de
          // existencias en ese almacén también está agotado ahí; el INNER
          // lo dejaba fuera del filtro "Agotado".
          join = 'LEFT JOIN existencias e ON e.producto_id = p.id '
              'AND e.almacen = \$${params.length}';
        } else {
          // Solo almacén: productos con existencias en ese almacén.
          join = 'JOIN existencias e ON e.producto_id = p.id '
              'AND e.almacen = \$${params.length}';
        }
      } else {
        join = 'LEFT JOIN existencias e ON e.producto_id = p.id';
      }
      const stockSum = 'COALESCE(SUM(e.cantidad), 0)';
      // El orden de las cláusulas SQL es GROUP BY → HAVING → ORDER BY. El
      // HAVING se concatenaba DESPUÉS del ORDER BY, que es un error de
      // sintaxis: la consulta reventaba, el catch de la pantalla conservaba
      // la lista anterior y el filtro "Agotado" parecía no hacer nada.
      var sql = 'SELECT p.*, $stockSum AS stock_prd FROM productos p '
          '$join WHERE $where GROUP BY p.id';
      if (stockStatus == 'out') {
        sql += ' HAVING $stockSum <= 0';
      }
      sql += ' ORDER BY p.nombre ASC';
      rows = await _db.executeSql(sql, params: params);
    } else {
      rows = await _db.executeSql(
        'SELECT p.* FROM productos p WHERE $where '
        'ORDER BY p.nombre ASC LIMIT $limit OFFSET $offset',
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
            // Misma definición que las estadísticas del encabezado: hay
            // stock (> 0) y no supera el mínimo definido. Antes este filtro
            // metía también a los agotados (s <= 0) y a los productos sin
            // stock_minimo, que comparados contra infinito pasaban siempre:
            // el botón decía 15 y la lista mostraba 59.
            return s > 0 && p.stockMinimo > 0 && s <= p.stockMinimo;
          })
          .skip(offset)
          .take(limit)
          .toList();
    }
    return productos.skip(offset).take(limit).toList();
  }

  /// Vínculos de producción de varios productos en una sola consulta.
  ///
  /// Devuelve, por cada producto pedido, la lista de productos relacionados por
  /// recetas: los que se producen usándolo como insumo ([esDerivado] true) y los
  /// insumos necesarios para producirlo ([esDerivado] false). El stock se toma
  /// de `existencias` (total, o del [almacen] si se especifica).
  Future<Map<int, List<VinculoProducto>>> getVinculosDeProductos(
    List<int> productoIds, {
    String? almacen,
  }) async {
    final result = <int, List<VinculoProducto>>{};
    if (productoIds.isEmpty) return result;

    // Receta simple: insumo en `producto_base_id`, producido = componente
    // RESULTADO. Receta compuesta: producto terminado en `producto_final_id`,
    // insumos = componentes INGREDIENTE.
    const sql = '''
      SELECT DISTINCT origen_id, vinculado_id, nombre, tipo, unidad, direccion
      FROM (
        SELECT r.producto_base_id AS origen_id, p.id AS vinculado_id,
               p.nombre AS nombre, p.tipo AS tipo,
               p.unidad_medida AS unidad, 'derivado' AS direccion
        FROM recetas r
        JOIN receta_componentes rc
          ON rc.receta_id = r.id AND rc.tipo_componente = 'RESULTADO'
        JOIN productos p ON p.id = rc.producto_id AND p.activo = TRUE
        WHERE r.activo = TRUE

        UNION ALL

        SELECT rc.producto_id AS origen_id, pf.id AS vinculado_id,
               pf.nombre AS nombre, pf.tipo AS tipo,
               pf.unidad_medida AS unidad, 'derivado' AS direccion
        FROM recetas r
        JOIN receta_componentes rc
          ON rc.receta_id = r.id AND rc.tipo_componente = 'INGREDIENTE'
        JOIN productos pf ON pf.id = r.producto_final_id AND pf.activo = TRUE
        WHERE r.activo = TRUE

        UNION ALL

        SELECT rc.producto_id AS origen_id, pb.id AS vinculado_id,
               pb.nombre AS nombre, pb.tipo AS tipo,
               pb.unidad_medida AS unidad, 'insumo' AS direccion
        FROM receta_componentes rc
        JOIN recetas r ON r.id = rc.receta_id AND r.activo = TRUE
        JOIN productos pb ON pb.id = r.producto_base_id AND pb.activo = TRUE
        WHERE rc.tipo_componente = 'RESULTADO'

        UNION ALL

        SELECT r.producto_final_id AS origen_id, pi.id AS vinculado_id,
               pi.nombre AS nombre, pi.tipo AS tipo,
               pi.unidad_medida AS unidad, 'insumo' AS direccion
        FROM recetas r
        JOIN receta_componentes rc
          ON rc.receta_id = r.id AND rc.tipo_componente = 'INGREDIENTE'
        JOIN productos pi ON pi.id = rc.producto_id AND pi.activo = TRUE
        WHERE r.activo = TRUE
      ) t
      WHERE origen_id = ANY(\$1)
      ORDER BY origen_id, direccion, nombre
    ''';
    final rows = await _db.executeSql(sql, params: [productoIds]);

    final linkedIds = <int>{
      for (final r in rows)
        if (r['vinculado_id'] != null) r['vinculado_id'] as int,
    };
    // Existencias por producto y almacén en una sola consulta: alimenta el
    // stock destacado (total o del almacén filtrado) y el desglose por
    // almacén que muestra el tile de vínculos.
    final exMap = await getExistenciasDeProductos(linkedIds.toList());

    for (final r in rows) {
      final origenId = r['origen_id'] as int;
      final vinculadoId = r['vinculado_id'] as int;
      final exis = exMap[vinculadoId] ?? const <Existencia>[];
      final porAlmacen = <String, double>{
        for (final e in exis) e.almacen: e.cantidad,
      };
      final stock = almacen == null
          ? porAlmacen.values.fold<double>(0, (a, b) => a + b)
          : (porAlmacen[almacen] ?? 0);
      result.putIfAbsent(origenId, () => []).add(
            VinculoProducto(
              productoId: vinculadoId,
              nombre: r['nombre'] as String,
              tipo: (r['tipo'] as String?) ?? '',
              unidad: (r['unidad'] as String?) ?? '',
              stock: stock,
              esDerivado: r['direccion'] == 'derivado',
              stockPorAlmacen: porAlmacen,
            ),
          );
    }
    return result;
  }

  Future<StockStats> getStockStats({String? almacen}) async {
    final params = <dynamic>[];
    String sql;
    if (almacen == null) {
      sql = '''
        SELECT COUNT(DISTINCT p.id) AS total,
          COUNT(DISTINCT p.id) FILTER (WHERE COALESCE(s.stock, 0) <= 0) AS agotado,
          COUNT(DISTINCT p.id) FILTER (
            WHERE COALESCE(s.stock, 0) > 0 AND p.stock_minimo > 0
              AND COALESCE(s.stock, 0) <= p.stock_minimo
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
          COUNT(DISTINCT p.id) FILTER (WHERE COALESCE(s.stock, 0) <= 0) AS agotado,
          COUNT(DISTINCT p.id) FILTER (
            WHERE COALESCE(s.stock, 0) > 0 AND p.stock_minimo > 0
              AND COALESCE(s.stock, 0) <= p.stock_minimo
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
      // El historial se ordena por `id` (orden de registro) y NO por
      // COALESCE(fecha_traslado, fecha_movimiento). La cadena
      // `cantidad_anterior -> cantidad -> cantidad_nueva` que pinta cada tarjeta
      // se calculó en el momento de insertar, en orden de `id`: el `anterior`
      // de un movimiento es el `nueva` del que se grabó justo antes. Reordenar
      // por la fecha de negocio del traslado mete ese movimiento entre dos que
      // sí se encadenan y la cuenta deja de cerrar (la mercadería se movió el
      // día que se creó la requisición, aunque el operador la totalizara días
      // después; para eso la tarjeta ya muestra `fecha_traslado` como fecha).
      // Medido con tool/verificar_cadena_movimientos.py: ordenar por la fecha
      // rompía 419 movimientos; por `id`, solo 85 (y esos 85 son datos, no
      // orden: hay entradas que se grabaron sin efecto sobre el stock).
      orderBy: 'id',
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