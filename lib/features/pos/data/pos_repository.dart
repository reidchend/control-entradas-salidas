import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../../core/data/supabase_service.dart';
import '../../../core/models/categoria.dart';
import '../../../core/models/pos_cierre_models.dart';
import '../../../core/models/pos_models.dart';
import '../../../core/models/producto.dart';
import 'pos_ventas_repository.dart';

class PosRepository {
  PosRepository(this._db);

  final SupabaseService _db;

  static const Uuid _uuid = Uuid();

  static String _pinHash(String pin) =>
      sha256.convert(utf8.encode(pin.trim())).toString();

  // Settings

  Future<String?> getSetting(String key) async {
    final rows = await _db.client
        .from('pos_settings')
        .select('value')
        .eq('key', key)
        .limit(1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    await _db.client.from('pos_settings').upsert(
      {'key': key, 'value': value},
      onConflict: 'key',
    );
  }

  // Sesiones / turnos / caja

  Future<int> abrirSesion(int usuarioId) async {
    final now = DateTime.now().toIso8601String();
    final syncUuid = _uuid.v4();
    return await _db.insert('pos_sesiones', {
      'usuario_id': usuarioId,
      'abierta_en': now,
      'caja_inicial': 0,
      'sync_uuid': syncUuid,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> cerrarSesion(int sesionId) async {
    final rows = await _db.client
        .from('pos_sesiones')
        .select()
        .eq('id', sesionId)
        .limit(1);
    if (rows.isEmpty) return;
    final s = rows.first;
    final now = DateTime.now().toIso8601String();
    final caja = await _totalVigenteDeSesion(sesionId);
    await _db.updateById('pos_sesiones', sesionId, {
      'cerrada_en': now,
      'caja_final': (s['caja_inicial'] as num? ?? 0).toDouble() + caja,
      'updated_at': now,
    });
  }

  Future<void> forzarCerrarSesion(int sesionId) async {
    final rows = await _db.client
        .from('pos_sesiones')
        .select()
        .eq('id', sesionId)
        .limit(1);
    if (rows.isEmpty) return;
    final s = rows.first;
    if (s['cerrada_en'] != null) return;
    final now = DateTime.now().toIso8601String();
    final caja = await _totalVigenteDeSesion(sesionId);
    await _db.updateById('pos_sesiones', sesionId, {
      'cerrada_en': now,
      'caja_final': (s['caja_inicial'] as num? ?? 0).toDouble() + caja,
      'updated_at': now,
    });
  }

  Future<double> _totalVigenteDeSesion(int sesionId) async {
    final rows = await _db.client
        .from('pos_ventas')
        .select('total')
        .eq('sesion_id', sesionId)
        .eq('estado', 'vigente');
    return rows.fold<double>(
        0, (sum, r) => sum + (r['total'] as num? ?? 0).toDouble());
  }

  Future<List<int>> cerrarSesionesStale({int horas = 8}) async {
    final limite =
        DateTime.now().subtract(Duration(hours: horas)).toIso8601String();
    final rows = await _db.client
        .from('pos_sesiones')
        .select()
        .filter('cerrada_en', 'is', null)
        .lt('abierta_en', limite);
    if (rows.isEmpty) return [];
    final now = DateTime.now().toIso8601String();
    final ids = <int>[];
    for (final s in rows) {
      final id = s['id'] as int;
      final caja = await _totalVigenteDeSesion(id);
      await _db.updateById('pos_sesiones', id, {
        'cerrada_en': now,
        'caja_final': (s['caja_inicial'] as num? ?? 0).toDouble() + caja,
        'updated_at': now,
      });
      ids.add(id);
    }
    return ids;
  }

  /// Devuelve el turno de caja ACTIVO de un cajero concreto (si lo tiene).
  ///
  /// Soporta múltiples turnos abiertos simultáneos (uno por cajero) en el
  /// mismo dispositivo: cada cajero retoma o abre SU propio turno sin cerrar
  /// el de los demás.
  Future<({PosSesion sesion, String? usuarioNombre})?> getSesionActivaDeUsuario(
      int usuarioId) async {
    final rows = await _db.client
        .from('pos_sesiones')
        .select()
        .eq('usuario_id', usuarioId)
        .filter('cerrada_en', 'is', null)
        .order('abierta_en', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    final s = rows.first;
    final u = await _db.client
        .from('pos_usuarios')
        .select('nombre')
        .eq('id', s['usuario_id'] as int)
        .limit(1);
    return (
      sesion: PosSesion.fromMap(s),
      usuarioNombre: u.isNotEmpty ? u.first['nombre'] as String? : null,
    );
  }

  /// IDs de los cajeros que tienen un turno abierto en este momento (para
  /// marcarlos en la pantalla de login).
  Future<Set<int>> getUsuariosConTurnoActivo() async {
    final rows = await _db.client
        .from('pos_sesiones')
        .select('usuario_id')
        .filter('cerrada_en', 'is', null);
    return rows.map((r) => r['usuario_id'] as int).toSet();
  }

  Future<List<({PosSesion sesion, String? usuarioNombre, int ventas, double totalVentas})>>
      getSesiones({int limit = 50, int? beforeId}) async {
    var query = _db.client.from('pos_sesiones').select();
    if (beforeId != null) query = query.lt('id', beforeId);
    final sesiones = await query.order('id', ascending: false).limit(limit);

    final ventRows = await _db.client
        .from('pos_ventas')
        .select('sesion_id, total')
        .eq('estado', 'vigente');
    final resumenMap = <int, ({int ventas, double total})>{};
    for (final v in ventRows) {
      final sid = v['sesion_id'] as int;
      final prev = resumenMap[sid] ?? (ventas: 0, total: 0.0);
      resumenMap[sid] = (
        ventas: prev.ventas + 1,
        total: prev.total + (v['total'] as num? ?? 0).toDouble(),
      );
    }

    final result = <({PosSesion sesion, String? usuarioNombre, int ventas, double totalVentas})>[];
    for (final s in sesiones) {
      final r = resumenMap[s['id'] as int] ?? (ventas: 0, total: 0.0);
      final u = await _db.client
          .from('pos_usuarios')
          .select('nombre')
          .eq('id', s['usuario_id'] as int)
          .limit(1);
      result.add((
        sesion: PosSesion.fromMap(s),
        usuarioNombre: u.isNotEmpty ? u.first['nombre'] as String? : null,
        ventas: r.ventas,
        totalVentas: r.total,
      ));
    }
    return result;
  }

  // Usuarios (PIN)

  Future<List<PosUsuario>> getUsuarios({bool soloActivos = true}) async {
    var query = _db.client.from('pos_usuarios').select();
    if (soloActivos) query = query.eq('activo', 1);
    final rows = await query.order('nombre');
    return rows.map(PosUsuario.fromMap).toList();
  }

  Future<PosUsuario?> getUsuario(int usuarioId) async {
    final rows = await _db.client
        .from('pos_usuarios')
        .select()
        .eq('id', usuarioId)
        .limit(1);
    return rows.isEmpty ? null : PosUsuario.fromMap(rows.first);
  }

  Future<int> crearUsuario(String nombre,
      {String? pin, bool esAdmin = false, bool esDesarrollador = false}) async {
    return await _db.insert('pos_usuarios', {
      'nombre': nombre.trim(),
      'pin_hash': pin != null && pin.trim().isNotEmpty ? _pinHash(pin) : null,
      'es_admin': esAdmin,
      'es_desarrollador': esDesarrollador,
      'activo': true,
      'creado_en': DateTime.now().toIso8601String(),
    });
  }

  Future<void> actualizarUsuario(
    int usuarioId, {
    String? nombre,
    String? pin,
    bool? esAdmin,
    bool? esDesarrollador,
    bool? activo,
  }) async {
    final rows = await _db.client
        .from('pos_usuarios')
        .select()
        .eq('id', usuarioId)
        .limit(1);
    if (rows.isEmpty) return;
    final actual = rows.first;
    await _db.updateById('pos_usuarios', usuarioId, {
      if (nombre != null) 'nombre': nombre.trim(),
      'pin_hash': pin == null
          ? actual['pin_hash']
          : pin.isEmpty
              ? null
              : _pinHash(pin),
      if (esAdmin != null) 'es_admin': esAdmin,
      if (esDesarrollador != null) 'es_desarrollador': esDesarrollador,
      if (activo != null) 'activo': activo,
    });
  }

  Future<void> eliminarUsuario(int usuarioId) async {
    await _db.deleteById('pos_usuarios', usuarioId);
  }

  Future<bool> verificarPin(int usuarioId, String pin) async {
    final rows = await _db.client
        .from('pos_usuarios')
        .select('pin_hash')
        .eq('id', usuarioId)
        .limit(1);
    if (rows.isEmpty) return false;
    final hash = rows.first['pin_hash'] as String?;
    if (hash == null || hash.isEmpty) return false;
    return hash == _pinHash(pin);
  }

  // Mesas

  Future<List<PosMesa>> getMesas({bool soloActivos = false}) async {
    var query = _db.client.from('pos_mesas').select();
    if (soloActivos) query = query.eq('activo', 1);
    final rows = await query.order('zona').order('numero');
    return rows.map(PosMesa.fromMap).toList();
  }

  Future<PosMesa?> getMesaById(int mesaId) async {
    final rows = await _db.client
        .from('pos_mesas')
        .select()
        .eq('id', mesaId)
        .limit(1);
    return rows.isEmpty ? null : PosMesa.fromMap(rows.first);
  }

  Future<int> crearMesa(String numero, {String? nombre, String? zona}) async {
    return await _db.insert('pos_mesas', {
      'numero': numero.trim(),
      'nombre': nombre?.trim(),
      'zona': zona?.trim(),
      'activo': true,
      'creado_en': DateTime.now().toIso8601String(),
    });
  }

  Future<void> actualizarMesa(int mesaId,
      {String? numero, String? nombre, String? zona, bool? activo}) async {
    final rows = await _db.client
        .from('pos_mesas')
        .select()
        .eq('id', mesaId)
        .limit(1);
    if (rows.isEmpty) return;
    final actual = rows.first;
    await _db.updateById('pos_mesas', mesaId, {
      'numero': numero?.trim() ?? actual['numero'],
      'nombre': nombre?.trim() ?? actual['nombre'],
      'zona': zona?.trim() ?? actual['zona'],
      if (activo != null) 'activo': activo,
    });
  }

  Future<void> eliminarMesa(int mesaId) async {
    await _db.deleteById('pos_mesas', mesaId);
  }

  // Habitaciones

  Future<List<PosHabitacion>> getHabitaciones({bool soloActivos = false}) async {
    var query = _db.client.from('pos_habitaciones').select();
    if (soloActivos) query = query.eq('activo', 1);
    final rows = await query.order('numero');
    return rows.map(PosHabitacion.fromMap).toList();
  }

  Future<PosHabitacion?> getHabitacionById(int habId) async {
    final rows = await _db.client
        .from('pos_habitaciones')
        .select()
        .eq('id', habId)
        .limit(1);
    return rows.isEmpty ? null : PosHabitacion.fromMap(rows.first);
  }

  Future<int> crearHabitacion(String numero,
      {String? piso, String? tipo}) async {
    return await _db.insert('pos_habitaciones', {
      'numero': numero.trim(),
      'piso': piso?.trim(),
      'tipo': tipo?.trim(),
      'activo': true,
      'creado_en': DateTime.now().toIso8601String(),
    });
  }

  Future<void> actualizarHabitacion(int habId,
      {String? numero, String? piso, String? tipo, bool? activo}) async {
    final rows = await _db.client
        .from('pos_habitaciones')
        .select()
        .eq('id', habId)
        .limit(1);
    if (rows.isEmpty) return;
    final actual = rows.first;
    await _db.updateById('pos_habitaciones', habId, {
      'numero': numero?.trim() ?? actual['numero'],
      'piso': piso?.trim() ?? actual['piso'],
      'tipo': tipo?.trim() ?? actual['tipo'],
      if (activo != null) 'activo': activo,
    });
  }

  Future<void> eliminarHabitacion(int habId) async {
    await _db.deleteById('pos_habitaciones', habId);
  }

  // Categorias POS

  Future<List<PosCategoria>> getPosCategorias({bool soloActivas = false}) async {
    var query = _db.client.from('pos_categorias').select();
    if (soloActivas) query = query.eq('activo', 1);
    final rows = await query.order('nombre');
    return rows.map(PosCategoria.fromMap).toList();
  }

  Future<int> crearPosCategoria(String nombre,
      {String color = '#FF6F00', String? icono}) async {
    return await _db.insert('pos_categorias', {
      'nombre': nombre.trim(),
      'color': color,
      'icono': icono,
      'activo': true,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> actualizarPosCategoria(int catId, String nombre,
      {String? color, String? icono, bool? activo}) async {
    final rows = await _db.client
        .from('pos_categorias')
        .select()
        .eq('id', catId)
        .limit(1);
    if (rows.isEmpty) return;
    final actual = rows.first;
    await _db.updateById('pos_categorias', catId, {
      'nombre': nombre.trim(),
      'color': color ?? actual['color'],
      'icono': icono ?? actual['icono'],
      if (activo != null) 'activo': activo,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> eliminarPosCategoria(int catId) async {
    await _db.deleteById('pos_categorias', catId);
  }

  // Sub-categorias (platos_categorias)

  Future<List<PosPlatoCategoria>> getPlatosCategorias(
      {bool soloActivas = false}) async {
    var query = _db.client.from('platos_categorias').select();
    if (soloActivas) query = query.eq('activo', 1);
    final rows = await query.order('nombre');
    return rows.map(PosPlatoCategoria.fromMap).toList();
  }

  Future<int> guardarPlatoCategoria(
    String nombre, {
    int? id,
    String color = '#FF6F00',
    bool activo = true,
    int? categoriaPadreId,
    int? posCategoriaPadreId,
  }) async {
    final now = DateTime.now().toIso8601String();
    final data = {
      'nombre': nombre.trim(),
      'color': color,
      'activo': activo,
      'categoria_padre_id': categoriaPadreId,
      'pos_categoria_padre_id': posCategoriaPadreId,
      'updated_at': now,
    };
    if (id != null) {
      await _db.updateById('platos_categorias', id, data);
      return id;
    }
    return await _db.insert('platos_categorias', {
      ...data,
      'created_at': now,
    });
  }

  Future<void> eliminarPlatoCategoria(int catId) async {
    await _db.deleteById('platos_categorias', catId);
  }

  // Platos + ingredientes + contornos

  Future<List<PosPlato>> getPlatos({
    bool soloActivos = false,
    int? categoriaId,
    bool? esContorno,
  }) async {
    var query = _db.client.from('platos').select();
    if (soloActivos) query = query.eq('activo', 1);
    if (categoriaId != null) query = query.eq('categoria_id', categoriaId);
    if (esContorno != null) query = query.eq('es_contorno', esContorno ? 1 : 0);
    final rows = await query.order('nombre');
    return rows.map(PosPlato.fromMap).toList();
  }

  Future<List<PosPlato>> getPlatosPos() =>
      getPlatos(soloActivos: true, esContorno: false);

  Future<List<PosPlato>> getContornosActivos() =>
      getPlatos(soloActivos: true, esContorno: true);

  Future<List<Categoria>> getCategoriasPos() async {
    final rows = await _db.client
        .from('categorias')
        .select()
        .eq('activo', 1)
        .eq('visible_en_pos', 1)
        .order('nombre');
    return rows.map(Categoria.fromMap).toList();
  }

  Future<List<Producto>> getProductosPos({int? categoriaId}) async {
    var query = _db.client
        .from('productos')
        .select()
        .eq('activo', 1)
        .eq('tipo', 'Productos para la venta');
    if (categoriaId != null) query = query.eq('categoria_id', categoriaId);
    final rows = await query.order('nombre');
    return rows.map(Producto.fromMap).toList();
  }

  Future<List<PosPlatoCategoria>> getSubcategorias({
    int? categoriaPadreId,
    int? posCategoriaPadreId,
  }) async {
    var query = _db.client
        .from('platos_categorias')
        .select()
        .eq('activo', 1);
    if (categoriaPadreId != null) {
      query = query.eq('categoria_padre_id', categoriaPadreId);
    }
    if (posCategoriaPadreId != null) {
      query = query.eq('pos_categoria_padre_id', posCategoriaPadreId);
    }
    final rows = await query.order('nombre');
    return rows.map(PosPlatoCategoria.fromMap).toList();
  }

  // Tasa de cambio

  Future<double> getTasaCambio() async {
    final v = await getSetting('tasa_cambio');
    return double.tryParse(v ?? '') ?? 0;
  }

  Future<String> getTasaCambioFecha() async =>
      await getSetting('tasa_cambio_actualizada_en') ?? '';

  Future<void> setTasaCambio(double tasa) async {
    await setSetting('tasa_cambio', tasa.toStringAsFixed(4));
    await setSetting('tasa_cambio_actualizada_en',
        DateTime.now().toIso8601String());
  }

  Future<List<PlatoIngrediente>> getIngredientes(int platoId) async {
    final rows = await _db.client
        .from('plato_ingredientes')
        .select()
        .eq('plato_id', platoId);
    return rows.map(PlatoIngrediente.fromMap).toList();
  }

  Future<List<PlatoContorno>> getContornos(int platoId) async {
    final rows = await _db.client
        .from('plato_contornos')
        .select()
        .eq('plato_id', platoId);
    return rows.map(PlatoContorno.fromMap).toList();
  }

  Future<int> crearPlato(
    String nombre, {
    required int categoriaId,
    double precioVenta = 0,
    bool esContorno = false,
    bool llevaContornos = false,
    List<({int productoId, double cantidad, String unidad})>? ingredientes,
    List<({int contornoId, int maxSeleccionar})>? contornos,
  }) async {
    final now = DateTime.now().toIso8601String();
    final id = await _db.insert('platos', {
      'nombre': nombre.trim(),
      'categoria_id': categoriaId,
      'precio_venta': precioVenta,
      'activo': true,
      'es_contorno': esContorno,
      'lleva_contornos': llevaContornos,
      'created_at': now,
      'updated_at': now,
    });
    await _reemplazarRelaciones(id,
        ingredientes: ingredientes, contornos: contornos);
    return id;
  }

  Future<void> actualizarPlato(
    int platoId, {
    String? nombre,
    int? categoriaId,
    double? precioVenta,
    bool? activo,
    bool? esContorno,
    bool? llevaContornos,
    List<({int productoId, double cantidad, String unidad})>? ingredientes,
    List<({int contornoId, int maxSeleccionar})>? contornos,
  }) async {
    final rows = await _db.client
        .from('platos')
        .select()
        .eq('id', platoId)
        .limit(1);
    if (rows.isEmpty) return;
    final actual = rows.first;
    await _db.updateById('platos', platoId, {
      'nombre': nombre?.trim() ?? actual['nombre'],
      'categoria_id': categoriaId ?? actual['categoria_id'],
      'precio_venta': precioVenta ?? actual['precio_venta'],
      if (activo != null) 'activo': activo,
      if (esContorno != null) 'es_contorno': esContorno,
      if (llevaContornos != null) 'lleva_contornos': llevaContornos,
      'updated_at': DateTime.now().toIso8601String(),
    });
    if (ingredientes != null || contornos != null) {
      await _reemplazarRelaciones(platoId,
          ingredientes: ingredientes, contornos: contornos);
    }
  }

  Future<void> _reemplazarRelaciones(
    int platoId, {
    List<({int productoId, double cantidad, String unidad})>? ingredientes,
    List<({int contornoId, int maxSeleccionar})>? contornos,
  }) async {
    if (ingredientes != null) {
      await _db.deleteWhere('plato_ingredientes', {'plato_id': platoId});
      for (final ing in ingredientes) {
        await _db.insert('plato_ingredientes', {
          'plato_id': platoId,
          'producto_id': ing.productoId,
          'cantidad': ing.cantidad,
          'unidad': ing.unidad,
        });
      }
    }
    if (contornos != null) {
      await _db.deleteWhere('plato_contornos', {'plato_id': platoId});
      for (final c in contornos) {
        await _db.insert('plato_contornos', {
          'plato_id': platoId,
          'contorno_id': c.contornoId,
          'max_seleccionar': c.maxSeleccionar,
        });
      }
    }
  }

  Future<void> eliminarPlato(int platoId) async {
    await _db.deleteWhere('plato_ingredientes', {'plato_id': platoId});
    await _db.deleteWhere('plato_contornos', {'plato_id': platoId});
    await _db.deleteById('platos', platoId);
  }

  /// Genera el cierre de caja completo (caja + reportes) para una sesión
  Future<CierreCaja> generarCierre(int sesionId) async {
    final ventasRepo = PosVentasRepository(_db);

    // 1. Obtener sesión y usuario
    final sRows = await _db.client
        .from('pos_sesiones')
        .select()
        .eq('id', sesionId)
        .limit(1);
    if (sRows.isEmpty) throw Exception('Sesión no encontrada: $sesionId');
    final s = sRows.first;

    final uRows = await _db.client
        .from('pos_usuarios')
        .select('nombre')
        .eq('id', s['usuario_id'] as int)
        .limit(1);
    final usuarioNombre = uRows.isNotEmpty ? uRows.first['nombre'] as String : 'Desconocido';

    // 2. Totales de caja
    final cajaInicial = (s['caja_inicial'] as num? ?? 0).toDouble();
    final totalVentas = await _totalVigenteDeSesion(sesionId);
    final cajaFinal = cajaInicial + totalVentas;

    // 3. Reporte simple: movimientos de venta agregados por producto/plato
    final movs = await ventasRepo.movimientosVentaDeSesion(sesionId);
    final Map<String, LineaVenta> lineasMap = {};
    for (final m in movs) {
      final key = m['producto_id'].toString();
      final precio = (m['precio_venta'] as num?)?.toDouble() ?? 0;
      final cant = (m['cantidad'] as num?)?.toDouble() ?? 0;
      final cat = m['categoria'] as String? ?? 'Sin categoría';
      final nombre = m['producto_nombre'] as String? ?? 'Producto #${m['producto_id']}';
      if (lineasMap.containsKey(key)) {
        final existing = lineasMap[key]!;
        lineasMap[key] = LineaVenta(
          nombre: existing.nombre,
          categoria: existing.categoria,
          cantidad: existing.cantidad + cant,
          precioUnitario: existing.precioUnitario,
          total: existing.total + (cant * precio),
        );
      } else {
        lineasMap[key] = LineaVenta(
          nombre: nombre,
          categoria: cat,
          cantidad: cant,
          precioUnitario: precio,
          total: cant * precio,
        );
      }
    }
    final lineas = lineasMap.values.toList()
      ..sort((a, b) => a.nombre.compareTo(b.nombre));
    final reporteSimple = ReporteSimple(
      lineas: lineas,
      totalGeneral: lineas.fold(0.0, (s, l) => s + l.total),
    );

    // 4. Reporte detallado: desglose por ingrediente
    final desglosesRaw = await ventasRepo.desgloseIngredientesDeSesion(sesionId);
    final desgloses = desglosesRaw.map((d) => DesgloseIngrediente(
      ingrediente: d['ingrediente'] as String,
      totalConsumido: (d['total_consumido'] as num?)?.toDouble() ?? 0,
      stockFinal: (d['stock_final'] as num?)?.toDouble() ?? 0,
      usos: (d['usos'] as List)
          .map((u) => UsoIngrediente(
                plato: u['plato'] as String,
                cantidad: (u['cantidad'] as num?)?.toDouble() ?? 0,
              ))
          .toList(),
    )).toList();
    final reporteDetallado = ReporteDetallado(desgloses: desgloses);

    // 5. Construir CierreCaja
    return CierreCaja(
      sesionId: sesionId,
      usuarioId: s['usuario_id'] as int,
      usuarioNombre: usuarioNombre,
      abiertaEn: s['abierta_en'] as String,
      cerradaEn: DateTime.now().toIso8601String(),
      cajaInicial: cajaInicial,
      totalVentas: totalVentas,
      cajaFinal: cajaFinal,
      reporteSimple: reporteSimple,
      reporteDetallado: reporteDetallado,
      syncUuid: _uuid.v4(),
    );
  }

  /// Guarda el cierre en la tabla histórica pos_cierres
  Future<int> guardarCierre(CierreCaja cierre) async {
    final now = DateTime.now().toIso8601String();
    return await _db.insert('pos_cierres', {
      'sesion_id': cierre.sesionId,
      'usuario_id': cierre.usuarioId,
      'abierta_en': cierre.abiertaEn,
      'cerrada_en': cierre.cerradaEn,
      'caja_inicial': cierre.cajaInicial,
      'total_ventas': cierre.totalVentas,
      'caja_final': cierre.cajaFinal,
      'reporte_simple_json': jsonEncode(cierre.reporteSimple.toJson()),
      'reporte_detallado_json': jsonEncode(cierre.reporteDetallado.toJson()),
      'sync_uuid': cierre.syncUuid,
      'created_at': now,
      'updated_at': now,
    });
  }
}
