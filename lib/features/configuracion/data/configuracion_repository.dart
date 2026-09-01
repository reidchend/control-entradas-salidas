import '../../../core/auth/device_id_service.dart';
import '../../../core/data/cache_service.dart';
import '../../../core/data/supabase_service.dart';
import '../../../core/models/categoria.dart';
import '../../../core/models/producto.dart';
import '../../../core/models/proveedor.dart';
import '../../../core/models/periodo.dart';

/// Repositorio de configuracion — CRUD de catalogos y ajustes del sistema.
/// Implementa stale-while-revalidate: sirve cache si esta fresco, si no
/// refresca desde Supabase y actualiza cache.
class ConfiguracionRepository {
  ConfiguracionRepository(this._db, {CacheService? cache})
      : _cache = cache;

  final SupabaseService _db;
  final CacheService? _cache;

  /// TTL para catalogos: 5 minutos.
  static const _catalogTtl = Duration(minutes: 5);

  /// Cache key prefix.
  static const _k = 'cache_cfg';

  // ---------------------------------------------------------------------------
  // Categorias
  // ---------------------------------------------------------------------------

  Future<List<Categoria>> getCategorias({bool soloActivos = true}) async {
    final cacheKey = '${_k}_cats_${soloActivos ? "act" : "all"}';
    final cached = _cache?.get<List>(cacheKey, ttl: _catalogTtl);
    if (cached != null) {
      return (cached.data).map((e) => Categoria.fromMap(e as Map<String, dynamic>)).toList();
    }
    final filters = soloActivos ? {'activo': true} : null;
    final rows = await _db.fetchAll(
      'categorias',
      orderBy: 'nombre',
      ascending: true,
      filters: filters,
    );
    final result = rows.map(Categoria.fromMap).toList();
    _cache?.put(cacheKey, rows);
    return result;
  }

  Future<int> createCategoria(Map<String, dynamic> data) async {
    final id = await _db.upsert('categorias', data, conflictColumn: 'nombre');
    _invalidateCats();
    return id;
  }

  Future<void> updateCategoria(int id, Map<String, dynamic> data) async {
    await _db.updateById('categorias', id, data);
    _invalidateCats();
  }

  /// Soft-delete: desactiva la categoria en el server (activo=false).
  Future<void> deleteCategoria(int id) async {
    await _db.updateById('categorias', id, {'activo': 0});
    _invalidateCats();
  }

  void _invalidateCats() {
    _cache?.remove('${_k}_cats_act');
    _cache?.remove('${_k}_cats_all');
  }

  // ---------------------------------------------------------------------------
  // Productos
  // ---------------------------------------------------------------------------

  Future<List<Producto>> getProductos({
    bool soloActivos = true,
    int? categoriaId,
    String? search,
  }) async {
    final useCache = soloActivos && categoriaId == null && (search == null || search.isEmpty);
    if (useCache) {
      final cached = _cache?.get<List>('${_k}_prods', ttl: _catalogTtl);
      if (cached != null) {
        return (cached.data).map((e) => Producto.fromMap(e as Map<String, dynamic>)).toList();
      }
    }

    var builder = _db.client.from('productos').select();
    if (soloActivos) builder = builder.eq('activo', 1);
    if (categoriaId != null) builder = builder.eq('categoria_id', categoriaId);
    if (search != null && search.isNotEmpty) {
      builder = builder.ilike('nombre', '%$search%');
    }
    dynamic q = builder;
    q = q.order('nombre', ascending: true);
    final data = await q;
    final rows = (data as List).cast<Map<String, dynamic>>();
    final result = rows.map((r) => Producto.fromMap(r)).toList();
    if (useCache) _cache?.put('${_k}_prods', rows);
    return result;
  }

  /// Genera el siguiente código numérico (auto-incremental).
  Future<String> proximoCodigoProducto() async {
    final rows = await _db.fetchAll(
      'productos',
      filters: {'activo': true},
    );
    final numericos = <int>[];
    var longitud = 4;
    for (final r in rows) {
      final c = (r['codigo'] as String? ?? '').trim();
      final n = int.tryParse(c);
      if (n != null) {
        numericos.add(n);
        if (c.length > longitud) longitud = c.length;
      }
    }
    if (numericos.isEmpty) return '0001';
    final siguiente = numericos.reduce((a, b) => a > b ? a : b) + 1;
    return siguiente.toString().padLeft(longitud, '0');
  }

  Future<int> createProducto(Map<String, dynamic> data) async {
    final id = await _db.insert('productos', data);
    _cache?.remove('${_k}_prods');
    return id;
  }

  Future<void> updateProducto(int id, Map<String, dynamic> data) async {
    await _db.updateById('productos', id, data);
    _cache?.remove('${_k}_prods');
  }

  /// Soft-delete: desactiva el producto en el server (activo=false).
  Future<void> deleteProducto(int id) async {
    await _db.updateById('productos', id, {'activo': 0});
    _cache?.remove('${_k}_prods');
  }

  // ---------------------------------------------------------------------------
  // Proveedores
  // ---------------------------------------------------------------------------

  Future<List<Proveedor>> getProveedores({String estado = 'Activo'}) async {
    final cacheKey = '${_k}_prov_$estado';
    final cached = _cache?.get<List>(cacheKey, ttl: _catalogTtl);
    if (cached != null) {
      return (cached.data).map((e) => Proveedor.fromMap(e as Map<String, dynamic>)).toList();
    }
    final rows = await _db.fetchAll(
      'proveedores',
      orderBy: 'nombre',
      ascending: true,
      filters: {'estado': estado},
    );
    final result = rows.map(Proveedor.fromMap).toList();
    _cache?.put(cacheKey, rows);
    return result;
  }

  Future<int> createProveedor(Map<String, dynamic> data) async {
    final id = await _db.upsert('proveedores', data, conflictColumn: 'nombre');
    _cache?.remove('${_k}_prov_Activo');
    return id;
  }

  Future<void> updateProveedor(int id, Map<String, dynamic> data) async {
    await _db.updateById('proveedores', id, data);
    _cache?.remove('${_k}_prov_Activo');
  }

  Future<void> deleteProveedor(int id) async {
    await _db.deleteById('proveedores', id);
    _cache?.remove('${_k}_prov_Activo');
  }

  // ---------------------------------------------------------------------------
  // Periodos
  // ---------------------------------------------------------------------------

  Future<List<Periodo>> getPeriodos() async {
    final cached = _cache?.get<List>('${_k}_periodos', ttl: _catalogTtl);
    if (cached != null) {
      return (cached.data).map((e) => Periodo.fromMap(e as Map<String, dynamic>)).toList();
    }
    final rows = await _db.fetchAll(
      'periodos',
      orderBy: 'fecha_apertura',
      ascending: false,
    );
    final result = rows.map(Periodo.fromMap).toList();
    _cache?.put('${_k}_periodos', rows);
    return result;
  }

  Future<bool> periodoExiste(String periodo) async {
    final row = await _db.fetchByField('periodos', 'periodo', periodo);
    return row != null;
  }

  Future<int> crearPeriodo(String periodo, {String? registradoPor}) {
    return _db.insert('periodos', {
      'periodo': periodo,
      'fecha_apertura': DateTime.now().toIso8601String(),
      if (registradoPor != null) 'registrado_por': registradoPor,
    });
  }

  // ---------------------------------------------------------------------------
  // Existencias / Recálculo
  // ---------------------------------------------------------------------------

  Future<void> recalcularExistencias() async {
    // Borrado total explícito: id >= 0 cubre todos los seriales positivos
    await _db.client.from('existencias').delete().gte('id', 0);
    await _recalcularExistenciasDesdeMovimientos();
  }

  Future<void> _recalcularExistenciasDesdeMovimientos() async {
    // 1) Leer checkpoints existentes como base (snapshot de aperturas anteriores)
    final Map<String, double> stock = {};
    final cpRows = await _db.client
        .from('stock_checkpoint')
        .select('producto_id, almacen, cantidad');
    for (final r in cpRows) {
      final key = '${r['producto_id']}|${r['almacen']}';
      stock[key] = (r['cantidad'] as num?)?.toDouble() ?? 0;
    }

    // 2) Replay SOLO movimientos posteriores al último checkpoint
    // (si no hay checkpoints, desde el inicio)
    DateTime? desde;
    if (stock.isNotEmpty) {
      // Buscar fecha del último checkpoint (aproximación: último período)
      final ultPeriodo = await _db.client
          .from('periodos')
          .select('fecha_apertura')
          .order('fecha_apertura', ascending: false)
          .limit(1);
      if (ultPeriodo.isNotEmpty) {
        desde = DateTime.tryParse(ultPeriodo.first['fecha_apertura'] as String);
      }
    }

    var query = _db.client
        .from('movimientos')
        .select()
        .or('tipo.eq.entrada,tipo.eq.salida,tipo.eq.ajuste,tipo.eq.tr_salida,tipo.eq.tr_entrada');
    if (desde != null) {
      query = query.gte('fecha_movimiento', desde.toIso8601String());
    }
    final movs = (await query.order('fecha_movimiento', ascending: true) as List)
        .cast<Map<String, dynamic>>();

    for (final m in movs) {
      final key = '${m['producto_id']}|${m['almacen'] ?? 'principal'}';
      final tipo = m['tipo'] as String;
      double delta;
      if (tipo == 'ajuste') {
        // Ajuste REEMPLAZA el stock: delta firmado = nueva - anterior
        final ant = (m['cantidad_anterior'] as num?)?.toDouble() ?? 0;
        final nue = (m['cantidad_nueva'] as num?)?.toDouble() ?? 0;
        delta = nue - ant;
      } else if (tipo == 'tr_salida' || tipo == 'tr_entrada') {
        // Traslados: cantidad YA viene firmada (tr_salida negativo, tr_entrada positivo)
        delta = (m['cantidad'] as num?)?.toDouble() ?? 0;
      } else {
        // Entrada/salida: cantidad positiva, signo según tipo
        final signo = (tipo == 'salida') ? -1.0 : 1.0;
        final cant = (m['cantidad'] as num?)?.toDouble() ?? 0;
        delta = cant * signo;
      }
      stock[key] = (stock[key] ?? 0) + delta;
    }

    // 3) Persistir + actualizar checkpoints
    for (final entry in stock.entries) {
      final parts = entry.key.split('|');
      final productoId = int.parse(parts[0]);
      final almacen = parts[1];
      final cantFinal = entry.value;

      final rows = await _db.client
          .from('existencias')
          .select('id')
          .eq('producto_id', productoId)
          .eq('almacen', almacen)
          .limit(1);
      if (rows.isNotEmpty) {
        await _db.updateById('existencias', rows.first['id'] as int, {'cantidad': cantFinal});
      } else {
        await _db.insert('existencias', {
          'producto_id': productoId,
          'almacen': almacen,
          'cantidad': cantFinal,
          'unidad': 'unidad',
        });
      }

      // Upsert checkpoint
      await _db.client.from('stock_checkpoint').upsert({
        'producto_id': productoId,
        'almacen': almacen,
        'cantidad': cantFinal,
      });
    }
  }

  Future<void> clearCheckpoints() async {
    // Borra existencias Y checkpoints (snapshot)
    await _db.client.from('existencias').delete().gte('id', 0);
    await _db.client.from('stock_checkpoint').delete().gte('producto_id', 0);
  }

  // ---------------------------------------------------------------------------
  // Sistema / Ajustes POS
  // ---------------------------------------------------------------------------

  Future<String?> getPosSetting(String key, {String? def}) async {
    final cacheKey = '${_k}_setting_$key';
    final cached = _cache?.get<String>(cacheKey, ttl: _catalogTtl);
    if (cached != null) return cached.data;
    final row = await _db.fetchByField('pos_settings', 'key', key);
    final value = (row?['value'] as String?) ?? def;
    if (value != null) _cache?.put(cacheKey, value);
    return value;
  }

  Future<void> setPosSetting(String key, String value) async {
    await _db.upsert('pos_settings', {'key': key, 'value': value},
        conflictColumn: 'key');
    _cache?.remove('${_k}_setting_$key');
  }

  Future<bool> getPermitirStockNegativo() async {
    final v = await getPosSetting('permitir_stock_negativo', def: '0');
    return v == '1';
  }

  Future<void> setPermitirStockNegativo(bool v) {
    return setPosSetting('permitir_stock_negativo', v ? '1' : '0');
  }

  Future<String> getAlmacenProduccionDefault() async {
    final v = await getPosSetting('almacen_produccion', def: 'restaurante');
    return v ?? 'restaurante';
  }

  Future<void> setAlmacenProduccionDefault(String almacen) {
    return setPosSetting('almacen_produccion', almacen);
  }

  Future<List<String>> getAlmacenes() async {
    final existencias = await _db.fetchAll('existencias');
    final movimientos = await _db.fetchAll('movimientos');
    final Set<String> almacenes = {};
    for (final r in existencias) {
      final a = r['almacen'] as String?;
      if (a != null && a.isNotEmpty) almacenes.add(a);
    }
    for (final r in movimientos) {
      final a = r['almacen'] as String?;
      if (a != null && a.isNotEmpty) almacenes.add(a);
    }
    return almacenes.toList()..sort();
  }

  // ---------------------------------------------------------------------------
  // Dispositivo / Usuario
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>?> getUsuarioDispositivo() async {
    final deviceId = await DeviceIdService.instance.id;
    final rows = await _db.client
        .from('dispositivo_usuario')
        .select('id, nombre, pin_hash, configurado_en')
        .eq('device_id', deviceId)
        .limit(1);
    if (rows.isEmpty) return null;
    final u = rows.first;
    return {
      'id': u['id'],
      'nombre': u['nombre'],
      'pinHash': u['pin_hash'],
      'configuradoEn': u['configurado_en'],
    };
  }

  Future<int> crearUsuarioDispositivo(Map<String, dynamic> data) {
    return _db.insert('dispositivo_usuario', data);
  }

  Future<void> eliminarUsuarioDispositivo() async {
    final deviceId = await DeviceIdService.instance.id;
    await _db.client
        .from('dispositivo_usuario')
        .delete()
        .eq('device_id', deviceId);
  }

  Future<bool> verificarPin(String pin) async {
    final user = await getUsuarioDispositivo();
    if (user == null || user['pinHash'] == null) return true;
    return user['pinHash'] == pin;
  }

  // ---------------------------------------------------------------------------
  // Archive / Periodos (funciones avanzadas)
  // ---------------------------------------------------------------------------

  /// Archiva movimientos > 3 meses activos y > 7 meses retención.
  Future<(int archivados, int eliminados)> archivarMovimientos({
    int mesesActivos = 3,
    int mesesRetencion = 7,
  }) async {
    final now = DateTime.now();
    final cutoffActivo = now
        .subtract(Duration(days: mesesActivos * 30))
        .toIso8601String();
    final cutoffRetencion = now
        .subtract(Duration(days: mesesRetencion * 30))
        .toIso8601String();

    final builder = _db.client
        .from('movimientos')
        .select()
        .lt('fecha_movimiento', cutoffActivo)
        .order('fecha_movimiento', ascending: true);
    final movs = (await builder as List).cast<Map<String, dynamic>>();

    int archivados = 0, eliminados = 0;
    for (final m in movs) {
      final fecha = m['fecha_movimiento'] as String?;
      final isOld = fecha != null && fecha.compareTo(cutoffRetencion) < 0;
      if (isOld) {
        await _db.deleteById('movimientos', m['id'] as int);
        eliminados++;
      } else {
        await _db.upsertById('movimientos_archivo', m);
        await _db.deleteById('movimientos', m['id'] as int);
        archivados++;
      }
    }
    return (archivados, eliminados);
  }

  Future<bool> testLocalConnection() async {
    try {
      await _db.fetchAll('categorias', limit: 1);
      return true;
    } catch (_) {
      return false;
    }
  }
}