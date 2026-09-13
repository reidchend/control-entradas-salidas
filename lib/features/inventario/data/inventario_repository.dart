import '../../../core/data/postgres_service.dart';
import '../../../core/models/categoria.dart';
import '../../../core/models/producto.dart';
import '../../../core/models/existencia.dart';

/// Repositorio de inventario — CRUD de productos, movimientos y lista de compra.
/// Opera directamente contra PostgreSQL (pooler Neon).
class InventarioRepository {
  InventarioRepository(this._db);

  final PostgresService _db;

  // ---------------------------------------------------------------------
  // Categorías
  // ---------------------------------------------------------------------

  Future<List<Categoria>> getAllCategorias() async {
    final rows = await _db.fetchAll('categorias', orderBy: 'nombre');
    return rows.map(Categoria.fromMap).toList();
  }

  Future<int> insertCategoria({
    required String nombre,
    String? descripcion,
    String color = '#2196F3',
  }) {
    return _db.upsert('categorias', {
      'nombre': nombre,
      'descripcion': descripcion,
      'color': color,
      'activo': true,
      'visible_en_pos': true,
    }, conflictColumn: 'nombre');
  }

  // ---------------------------------------------------------------------
  // Productos
  // ---------------------------------------------------------------------

  Future<List<Producto>> getAllProductos({String searchTerm = ''}) async {
    final rows = await _db.fetchAll(
      'productos',
      orderBy: 'nombre',
      ascending: true,
      filters: {'activo': true},
      search: searchTerm,
      searchColumn: 'nombre',
    );
    if (rows.isEmpty) return [];

    final ids = rows.map((r) => r['id'] as int).toList();
    final stockMap = await _db.getStockMapForProductos(ids);
    return rows.map((r) {
      final p = Producto.fromMap(r);
      return p.copyWith(stockActual: stockMap[p.id] ?? 0);
    }).toList();
  }

  Future<List<Producto>> getProductosByCategoria(int categoriaId) async {
    final rows = await _db.fetchAll('productos',
        orderBy: 'nombre', filters: {'categoria_id': categoriaId, 'activo': true});
    if (rows.isEmpty) return [];
    final ids = rows.map((r) => r['id'] as int).toList();
    final stockMap = await _db.getStockMapForProductos(ids);
    return rows.map((r) {
      final p = Producto.fromMap(r);
      return p.copyWith(stockActual: stockMap[p.id] ?? 0);
    }).toList();
  }

  Future<List<Producto>> getProductosConsumibles() async {
    final rows = await _db.fetchAll('productos',
        orderBy: 'nombre', ascending: true, filters: {'activo': true, 'tipo': 'Consumo'});
    return rows.map(Producto.fromMap).toList();
  }

  Future<List<Existencia>> getExistenciasByProducto(int productoId) async {
    final rows = await _db.fetchAll('existencias',
        filters: {'producto_id': productoId});
    return rows.map(Existencia.fromMap).toList();
  }

  /// Existencias de varios productos en **una sola query** agrupadas por producto.
  /// Sustituye el patrón N+1 al cargar el listado de consumibles.
  Future<Map<int, List<Existencia>>> getExistenciasDeProductos(
      List<int> productoIds) async {
    if (productoIds.isEmpty) return {};
    final rows = await _db.executeSql(
      'SELECT * FROM existencias WHERE producto_id = ANY(\$1) ORDER BY almacen',
      params: [productoIds],
    );
    final map = <int, List<Existencia>>{};
    for (final r in rows) {
      final pid = r['producto_id'] as int;
      map.putIfAbsent(pid, () => []).add(Existencia.fromMap(r));
    }
    return map;
  }

  /// Descarga en lote de consumibles dentro de una transacción.
  ///
  /// Una sola lectura de existencias + un INSERT batch de movimientos + un
  /// UPSERT batch de existencias, en lugar de 4 queries por consumible.
  /// Devuelve cuántos se descargaron y cuáles fallaron por stock insuficiente.
  Future<ResultadoDescargo> descargarConsumibles({
    required List<DescargoItemInput> items,
    required String registradoPor,
    String observaciones = 'Descargo consumible',
  }) async {
    if (items.isEmpty) return const ResultadoDescargo(ok: 0);
    return _db.transaction((tx) async {
      final ids = {for (final i in items) i.productoId}.toList();
      final exRows = await tx.executeSql(
        'SELECT * FROM existencias WHERE producto_id = ANY(\$1)',
        params: [ids],
      );
      final previos = <String, Map<String, dynamic>>{
        for (final r in exRows) '${r['producto_id']}|${r['almacen']}': r,
      };

      final movimientos = <Map<String, dynamic>>[];
      final upserts = <Map<String, dynamic>>[];
      final fallos = <String>[];
      final ahora = DateTime.now();

      for (final item in items) {
        final k = '${item.productoId}|${item.almacen}';
        final prev = previos[k];
        final cantAnterior =
            prev == null ? 0.0 : (prev['cantidad'] as num?)?.toDouble() ?? 0;
        final cantAMover =
            (item.esPesable && item.pesoTotal > 0) ? item.pesoTotal : item.cantidad;
        if (cantAnterior < cantAMover) {
          fallos.add('${item.nombre} (${item.almacen})');
          continue;
        }
        final cantNueva = cantAnterior - cantAMover;
        final unidad = item.esPesable ? 'kg' : item.unidadMedida;

        movimientos.add({
          'producto_id': item.productoId,
          'tipo': 'consumo',
          'cantidad': item.cantidad,
          'cantidad_anterior': cantAnterior,
          'cantidad_nueva': cantNueva,
          'peso_total': item.pesoTotal,
          'registrado_por': registradoPor,
          'observaciones': observaciones,
          'almacen': item.almacen,
          'fecha_movimiento': ahora.toIso8601String(),
        });
        upserts.add({
          'producto_id': item.productoId,
          'almacen': item.almacen,
          'cantidad': cantNueva,
          'unidad': unidad,
        });
      }

      if (movimientos.isNotEmpty) {
        await tx.insertBatch('movimientos', movimientos);
      }
      if (upserts.isNotEmpty) {
        await tx.upsertBatch(
          'existencias',
          upserts,
          conflictColumns: ['producto_id', 'almacen'],
        );
      }
      return ResultadoDescargo(ok: movimientos.length, fallos: fallos);
    });
  }

  Future<void> insertProducto({
    required String nombre,
    String? codigo,
    String? descripcion,
    int? categoriaId,
    double precioVenta = 0,
    String unidadMedida = 'unidad',
    double stockMinimo = 0,
    String tipo = 'ninguno',
    String almacenPredeterminado = 'principal',
    bool esPesable = false,
  }) {
    return _db.insert('productos', {
      'nombre': nombre,
      'codigo': codigo,
      'descripcion': descripcion,
      'categoria_id': categoriaId,
      'precio_venta': precioVenta,
      'unidad_medida': unidadMedida,
      'stock_minimo': stockMinimo,
      'tipo': tipo,
      'almacen_predeterminado': almacenPredeterminado,
      'es_pesable': esPesable ? 1 : 0,
      'activo': true,
    });
  }

  /// Registra un movimiento y actualiza la existencia.
  /// Devuelve `false` si el stock no alcanza (salidas/ajustes negativos).
  Future<bool> registrarMovimiento({
    required int productoId,
    required String tipo,
    required double cantidad,
    double pesoTotal = 0,
    String? almacen,
    String? observaciones,
    String registradoPor = 'sistema',
    bool esPesable = false,
    String unidadMedida = 'unidad',
  }) async {
    final almacenSel =
        (almacen ?? '').trim().isNotEmpty ? almacen!.trim() : 'principal';

    // Obtener existencia actual
    final existRows = await _db.fetchAll('existencias',
        filters: {'producto_id': productoId, 'almacen': almacenSel});
    final existActual = existRows.isEmpty ? null : existRows.first;
    final cantAnterior =
        (existActual?['cantidad'] as num?)?.toDouble() ?? 0;

    final esPorPeso = esPesable && pesoTotal > 0;
    final cantAMover = esPorPeso ? pesoTotal : cantidad;
    final unidad = esPesable ? 'kg' : unidadMedida;

    double cantNueva;
    if (tipo == 'entrada' || tipo == 'entrada_produccion' || tipo == 'ajuste') {
      cantNueva = cantAnterior + cantAMover;
    } else {
      if (cantAnterior < cantAMover) return false;
      cantNueva = cantAnterior - cantAMover;
    }

    // Insertar movimiento
    await _db.insert('movimientos', {
      'producto_id': productoId,
      'tipo': tipo,
      'cantidad': cantidad,
      'cantidad_anterior': cantAnterior,
      'cantidad_nueva': cantNueva,
      'peso_total': pesoTotal,
      'registrado_por': registradoPor,
      'observaciones': observaciones ?? '',
      'almacen': almacenSel,
      'fecha_movimiento': DateTime.now().toIso8601String(),
    });

    // Upsert existencia
    await upsertExistencia(
      productoId: productoId,
      almacen: almacenSel,
      cantidad: cantNueva,
      unidad: unidad,
    );

    return true;
  }

  Future<void> upsertExistencia({
    required int productoId,
    required String almacen,
    required double cantidad,
    String unidad = 'unidad',
  }) async {
    // Buscar existencia actual
    final rows = await _db.fetchAll('existencias',
        filters: {'producto_id': productoId, 'almacen': almacen});
    if (rows.isNotEmpty) {
      await _db.updateById('existencias', rows.first['id'] as int, {
        'cantidad': cantidad,
        'unidad': unidad,
      });
    } else {
      await _db.insert('existencias', {
        'producto_id': productoId,
        'almacen': almacen,
        'cantidad': cantidad,
        'unidad': unidad,
      });
    }
  }

  // ---------------------------------------------------------------------
  // Lista de compra (compras_lista)
  // ---------------------------------------------------------------------

  Future<List<ComprasListaItem>> getComprasListaConProductos() async {
    final rows = await _db.fetchAll('compras_lista',
        orderBy: 'created_at', ascending: false);
    if (rows.isEmpty) return [];

    final productoIds =
        rows.map((r) => r['producto_id'] as int).toSet();
    final productosRaw = await _db.fetchAll(
      'productos',
      filters: {'id': productoIds.toList()},
    );
    final prodMap = {
      for (final p in productosRaw) (p['id'] as int): Producto.fromMap(p)
    };

    final catIds = prodMap.values
        .map((p) => p.categoriaId)
        .whereType<int>()
        .toSet();
    final categoriasRaw = catIds.isEmpty
        ? <Map<String, dynamic>>[]
        : await _db.fetchAll(
            'categorias',
            filters: {'id': catIds.toList()},
          );
    final catMap = {
      for (final c in categoriasRaw) (c['id'] as int): Categoria.fromMap(c)
    };

    return rows.map((row) {
      final p = prodMap[row['producto_id'] as int];
      if (p == null) return null;
      final cat = p.categoriaId != null ? catMap[p.categoriaId] : null;
      return ComprasListaItem(
        id: row['id'] as int,
        productoId: p.id,
        nombre: p.nombre,
        precioVenta: p.precioVenta,
        stockActual: p.stockActual,
        unidadMedida: p.unidadMedida,
        categoriaId: p.categoriaId ?? 0,
        categoriaNombre: cat?.nombre ?? '',
        categoriaColor: cat?.color ?? '#2196F3',
        esPesable: p.esPesable,
      );
    }).whereType<ComprasListaItem>().toList();
  }

  Future<void> toggleComprasLista(int productoId) async {
    final rows = await _db.fetchAll('compras_lista',
        filters: {'producto_id': productoId});
    if (rows.isNotEmpty) {
      await _db.deleteById('compras_lista', rows.first['id'] as int);
    } else {
      await _db.insert('compras_lista', {
        'producto_id': productoId,
      });
    }
  }

  Future<void> deleteComprasLista(int productoId) async {
    final rows = await _db.fetchAll('compras_lista',
        filters: {'producto_id': productoId});
    for (final r in rows) {
      await _db.deleteById('compras_lista', r['id'] as int);
    }
  }
}

/// Item para la UI de lista de compra (join Producto + Categoría).
class ComprasListaItem {
  ComprasListaItem({
    required this.id,
    required this.productoId,
    required this.nombre,
    required this.precioVenta,
    required this.stockActual,
    required this.unidadMedida,
    required this.categoriaId,
    required this.categoriaNombre,
    required this.categoriaColor,
    required this.esPesable,
  });

  final int id;
  final int productoId;
  final String nombre;
  final double precioVenta;
  final double stockActual;
  final String unidadMedida;
  final int categoriaId;
  final String categoriaNombre;
  final String categoriaColor;
  final bool esPesable;
}

/// Item de descargo (producto + cantidades + almacén de origen).
class DescargoItemInput {
  const DescargoItemInput({
    required this.productoId,
    required this.nombre,
    required this.cantidad,
    required this.pesoTotal,
    required this.almacen,
    required this.esPesable,
    required this.unidadMedida,
  });

  final int productoId;
  final String nombre;
  final double cantidad;
  final double pesoTotal;
  final String almacen;
  final bool esPesable;
  final String unidadMedida;
}

/// Resultado de un descargo batch.
class ResultadoDescargo {
  const ResultadoDescargo({required this.ok, this.fallos = const []});
  final int ok;
  final List<String> fallos;
}