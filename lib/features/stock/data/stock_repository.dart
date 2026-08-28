import '../../../core/data/supabase_service.dart';
import '../../../core/models/categoria.dart';
import '../../../core/models/existencia.dart';
import '../../../core/models/movimiento.dart';
import '../../../core/models/producto.dart';
import '../../../core/utils/supabase_cast.dart';

class StockStats {
  const StockStats({this.total = 0, this.bajo = 0, this.agotado = 0});
  final int total;
  final int bajo;
  final int agotado;
}

class StockRepository {
  StockRepository(this._db);
  final SupabaseService _db;

  Future<List<Categoria>> loadCategorias() async {
    final rows = await _db.client
        .from('categorias')
        .select()
        .eq('activo', 1)
        .order('nombre');
    return rows.map(Categoria.fromMap).toList();
  }

  Future<List<String>> getAlmacenes() async {
    final rows =
        await _db.client.from('existencias').select('almacen');
    final almacenes =
        rows.map((r) => r['almacen'] as String).toSet().toList();
    almacenes.sort();
    return almacenes;
  }

  Future<List<Producto>> loadProductos({int limit = 50}) async {
    final rows = await _db.client
        .from('productos')
        .select()
        .eq('activo', 1)
        .order('nombre')
        .limit(limit);
    return rows.map(Producto.fromMap).toList();
  }

  Future<Map<int, Map<String, double>>> getExistenciasMap(
      List<int> productoIds) async {
    final result = <int, Map<String, double>>{};
    if (productoIds.isEmpty) return result;
    final rows = await _db.client
        .from('existencias')
        .select('producto_id, almacen, cantidad')
        .filter('producto_id', 'in', productoIds);
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
    var query = _db.client.from('productos').select().eq('activo', 1);
    if (search.isNotEmpty) {
      query = query.ilike('nombre', '%$search%');
    }
    if (categoriaId != null) {
      query = query.eq('categoria_id', categoriaId);
    }
    final rows = await query.order('nombre');
    var productos = rows.map(Producto.fromMap).toList();

    if (almacen == null && stockStatus == null) {
      return productos.take(limit).toList();
    }

    final ids = [for (final p in productos) p.id];
    final existenciasMap = await getExistenciasMap(ids);
    final stockTotal = <int, double>{
      for (final e in existenciasMap.entries)
        e.key: e.value.values.fold<double>(0, (a, b) => a + b),
    };

    final result = <Producto>[];
    for (final p in productos) {
      // Al filtrar por almacén, el nivel se decide con las existencias de ese
      // almacén; sin filtro, con la suma de todos los almacenes.
      final stock = almacen != null
          ? (existenciasMap[p.id]?[almacen] ?? 0)
          : (stockTotal[p.id] ?? 0);
      if (almacen != null &&
          !(existenciasMap[p.id]?.containsKey(almacen) ?? false)) {
        continue;
      }
      if (stockStatus == 'out' && !(stock <= 0)) continue;
      if (stockStatus == 'low' &&
          !(stock > 0 &&
              stock <= (p.stockMinimo > 0 ? p.stockMinimo : double.infinity))) {
        continue;
      }
      result.add(p);
      if (result.length >= limit) break;
    }
    return result;
  }

  Future<StockStats> getStockStats({String? almacen}) async {
    final productos = await loadProductos(limit: 99999);
    final ids = [for (final p in productos) p.id];
    Map<int, double> stockMap;
    Map<int, Map<String, double>>? existenciasMap;
    if (almacen != null) {
      existenciasMap = await getExistenciasMap(ids);
      stockMap = {
        for (final e in existenciasMap.entries)
          e.key: e.value[almacen] ?? 0,
      };
    } else {
      stockMap = await getStockTotal(ids);
    }
    var total = 0, bajo = 0, agotado = 0;
    for (final p in productos) {
      if (almacen != null) {
        final porAlmacen = existenciasMap![p.id];
        if (porAlmacen == null || !porAlmacen.containsKey(almacen)) continue;
      }
      final stock = stockMap[p.id] ?? 0;
      total++;
      if (stock <= 0) {
        agotado++;
      } else if (p.stockMinimo > 0 && stock <= p.stockMinimo) {
        bajo++;
      }
    }
    return StockStats(total: total, bajo: bajo, agotado: agotado);
  }

  Future<List<Existencia>> getExistenciasProducto(int productoId) async {
    final rows = await _db.client
        .from('existencias')
        .select()
        .eq('producto_id', productoId)
        .order('almacen');
    return rows.map(Existencia.fromMap).toList();
  }

  Future<List<Movimiento>> getProductoHistorial(int productoId,
      {int limit = 100}) async {
    final rows = await _db.client
        .from('movimientos')
        .select()
        .eq('producto_id', productoId)
        .order('fecha_movimiento', ascending: false)
        .limit(limit);
    return rows.map(Movimiento.fromMap).toList();
  }

  Future<bool> ajustarExistencia({
    required int productoId,
    required String almacen,
    required double nuevaCantidad,
    String? motivo,
    String usuario = 'sistema',
  }) async {
    final rows = await _db.client
        .from('existencias')
        .select('id, cantidad')
        .eq('producto_id', productoId)
        .eq('almacen', almacen)
        .order('id', ascending: false)
        .limit(1);
    final actual =
        rows.isNotEmpty ? (rows.first['cantidad'] as num?)?.toDouble() ?? 0 : 0.0;

    if ((nuevaCantidad - actual).abs() < 1e-9) return false;

    final pRows = await _db.client
        .from('productos')
        .select('es_pesable, unidad_medida')
        .eq('id', productoId)
        .limit(1);
    final esPesable = pRows.isNotEmpty && toBool(pRows.first['es_pesable']);
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
