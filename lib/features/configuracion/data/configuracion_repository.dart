import '../../../core/auth/device_id_service.dart';
import '../../../core/data/cache_service.dart';
import '../../../core/data/supabase_service.dart';
import '../../../core/models/categoria.dart';
import '../../../core/models/producto.dart';
import '../../../core/models/proveedor.dart';
import '../../../core/models/periodo.dart';

/// Callback de progreso para operaciones largas (archivo/recalculo).
typedef ProgresoCallback = void Function(double progreso, String etapa);

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

  Future<void> recalcularExistencias({ProgresoCallback? onProgreso}) async {
    // Recálculo ABSOLUTO: ignora el checkpoint como base. Reproduce el stock
    // real desde todos los movimientos (activos + archivados).
    onProgreso?.call(0.05, 'Eliminando existencias anteriores...');
    await _db.client.from('existencias').delete().gte('id', 0);
    await _db.client.from('stock_checkpoint').delete().gte('producto_id', 0);
    await _recalcularExistenciasDesdeMovimientos(onProgreso: onProgreso);
  }

  Future<void> _recalcularExistenciasDesdeMovimientos(
      {ProgresoCallback? onProgreso}) async {
    // Todos los tipos de movimiento que modifican stock. La delta se deriva de
    // `cantidad_nueva - cantidad_anterior`, que TODAS las operaciones escriben
    // de forma consistente con el valor real que actualizaron en `existencias`
    // (entrada/salida/venta/devolución/producción/traslado/ajuste), así el
    // recálculo reproduce exactamente lo que hizo cada operación en tiempo real.
    const tipos =
        'tipo.eq.entrada,tipo.eq.salida,tipo.eq.ajuste,tipo.eq.tr_salida,tipo.eq.tr_entrada,tipo.eq.entrada_produccion,tipo.eq.salida_produccion,tipo.eq.venta,tipo.eq.devolucion';
    onProgreso?.call(0.10, 'Leyendo movimientos...');
    final activos = (await _db.client
            .from('movimientos')
            .select()
            .or(tipos) as List)
        .cast<Map<String, dynamic>>();
    final archivados = (await _db.client
            .from('movimientos_archivo')
            .select()
            .or(tipos) as List)
        .cast<Map<String, dynamic>>();

    final todas = [...archivados, ...activos];
    final Map<String, double> stock = {};
    for (var i = 0; i < todas.length; i++) {
      final m = todas[i];
      final key = '${m['producto_id']}|${m['almacen'] ?? 'principal'}';
      final ant = (m['cantidad_anterior'] as num?)?.toDouble() ?? 0;
      final nue = (m['cantidad_nueva'] as num?)?.toDouble() ?? 0;
      stock[key] = (stock[key] ?? 0) + (nue - ant);
      if (todas.isNotEmpty && i % 250 == 0) {
        onProgreso?.call(
            0.15 + (i / todas.length) * 0.45, 'Calculando stock ($i/${todas.length})...');
      }
    }
    if (todas.isEmpty) onProgreso?.call(0.60, 'Sin movimientos, stock vacío');

    // Persistir existencias + checkpoint como snapshot del stock real
    final now = DateTime.now().toIso8601String();
    final entries = stock.entries.toList();
    for (var j = 0; j < entries.length; j++) {
      final entry = entries[j];
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

      // Upsert checkpoint (snapshot para cálculos en tiempo real)
      await _db.client.from('stock_checkpoint').upsert({
        'producto_id': productoId,
        'almacen': almacen,
        'cantidad': cantFinal,
        'fecha_checkpoint': now,
      });
      if (j % 25 == 0 || j == entries.length - 1) {
        onProgreso?.call(
            0.60 + ((j + 1) / entries.length) * 0.40, 'Guardando existencias (${j + 1}/${entries.length})...');
      }
    }
    onProgreso?.call(1.0, 'Recálculo completado');
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

  /// Archiva movimientos anteriores a `mesesActivos` (por defecto 3).
  /// Nunca elimina: todo pasa a `movimientos_archivo` para conservar el
  /// historial completo y que el recálculo absoluto de existencias siga siendo
  /// fiel. Devuelve la cantidad archivada.
  Future<int> archivarMovimientos(
      {int mesesActivos = 3, ProgresoCallback? onProgreso}) async {
    final now = DateTime.now();
    final cutoffActivo = now
        .subtract(Duration(days: mesesActivos * 30))
        .toIso8601String();

    final builder = _db.client
        .from('movimientos')
        .select()
        .lt('fecha_movimiento', cutoffActivo)
        .order('fecha_movimiento', ascending: true);
    final movs = (await builder as List).cast<Map<String, dynamic>>();
    if (movs.isEmpty) {
      onProgreso?.call(1.0, 'Sin movimientos por archivar');
      return 0;
    }

    int archivados = 0;
    for (var i = 0; i < movs.length; i++) {
      final m = movs[i];
      await _db.upsertById('movimientos_archivo', m);
      await _db.deleteById('movimientos', m['id'] as int);
      archivados++;
      if (i % 10 == 0 || i == movs.length - 1) {
        onProgreso?.call(
            (i + 1) / movs.length, 'Archivando movimientos (${i + 1}/${movs.length})...');
      }
    }
    return archivados;
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