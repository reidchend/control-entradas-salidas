import '../../../core/data/postgres_service.dart';
import '../../../core/models/producto.dart';
import '../../../core/models/receta.dart';
import '../../../core/utils/supabase_cast.dart';

/// Componente de receta con datos del producto para la UI.
/// Porta el join `receta_componentes + productos` de `get_componentes_by_receta`.
class ComponenteInfo {
  const ComponenteInfo({
    required this.id,
    required this.recetaId,
    required this.productoId,
    required this.cantidad,
    required this.unidad,
    required this.tipoComponente,
    required this.pesoVariable,
    this.nombre = '',
    this.esPesable = false,
  });

  final int id;
  final int recetaId;
  final int productoId;
  final double cantidad;
  final String unidad;
  final String tipoComponente;
  final int pesoVariable;
  final String nombre;
  final bool esPesable;

  factory ComponenteInfo.fromMap(
    Map<String, dynamic> c,
    Map<String, dynamic>? p,
  ) {
    return ComponenteInfo(
      id: c['id'] as int,
      recetaId: c['receta_id'] as int,
      productoId: c['producto_id'] as int,
      cantidad: (c['cantidad'] as num?)?.toDouble() ?? 0,
      unidad: (c['unidad'] as String?) ?? 'unidad',
      tipoComponente: (c['tipo_componente'] as String?) ?? '',
      pesoVariable: (c['peso_variable'] == true) ? 1 : 0,
      nombre: (p?['nombre'] as String?) ?? '',
      esPesable: toBool(p?['es_pesable']),
    );
  }
}

/// Ingrediente/RESULTADO a descargar en una producción pendiente.
class DescargoItem {
  const DescargoItem({
    required this.productoId,
    required this.nombre,
    required this.cantidadSugerida,
    required this.pesoVariable,
    required this.unidad,
    required this.esPesable,
    required this.almacen,
  });

  final int productoId;
  final String nombre;
  final double cantidadSugerida;
  final bool pesoVariable;
  final String unidad;
  final bool esPesable;
  final String almacen;

  String get unidadLabel => esPesable ? 'kg' : unidad;
}

/// Producto resultante de una producción (detalle tipo 'entrada').
class Producido {
  const Producido({
    required this.productoId,
    required this.nombre,
    required this.cantidad,
    required this.unidad,
  });

  final int productoId;
  final String nombre;
  final double cantidad;
  final String unidad;
}

/// Producción con el nombre de su receta para las cards.
class ProduccionInfo {
  const ProduccionInfo({
    required this.id,
    required this.recetaId,
    required this.cantidad,
    required this.estado,
    required this.usuario,
    required this.observaciones,
    required this.cocineros,
    required this.fechaProduccion,
    required this.recetaNombre,
    required this.recetaTipo,
  });

  final int id;
  final int recetaId;
  final double cantidad;
  final String estado;
  final String? usuario;
  final String? observaciones;
  final String? cocineros;
  final DateTime? fechaProduccion;
  final String recetaNombre;
  final String recetaTipo;

  factory ProduccionInfo.fromMap(
    Map<String, dynamic> p,
    String recetaNombre,
    String recetaTipo,
  ) {
    final fechaRaw = p['fecha_produccion'];
    return ProduccionInfo(
      id: p['id'] as int,
      recetaId: p['receta_id'] as int,
      cantidad: (p['cantidad'] as num?)?.toDouble() ?? 0,
      estado: (p['estado'] as String?) ?? '',
      usuario: p['usuario'] as String?,
      observaciones: p['observaciones'] as String?,
      cocineros: p['cocineros'] as String?,
      fechaProduccion:
          fechaRaw == null ? null : DateTime.tryParse(fechaRaw.toString()),
      recetaNombre: recetaNombre.isEmpty ? '?' : recetaNombre,
      recetaTipo: recetaTipo,
    );
  }
}

/// Detalle de producción con el nombre del producto.
class DetalleInfo {
  const DetalleInfo({
    required this.id,
    required this.produccionId,
    required this.productoId,
    required this.tipo,
    required this.cantidad,
    required this.unidad,
    required this.movimientoId,
    required this.productoNombre,
  });

  final int id;
  final int produccionId;
  final int productoId;
  final String tipo;
  final double cantidad;
  final String unidad;
  final int? movimientoId;
  final String productoNombre;

  factory DetalleInfo.fromMap(
    Map<String, dynamic> d,
    Map<String, dynamic>? p,
  ) {
    return DetalleInfo(
      id: d['id'] as int,
      produccionId: d['produccion_id'] as int,
      productoId: d['producto_id'] as int,
      tipo: (d['tipo'] as String?) ?? '',
      cantidad: (d['cantidad'] as num?)?.toDouble() ?? 0,
      unidad: (d['unidad'] as String?) ?? 'unidad',
      movimientoId: d['movimiento_id'] as int?,
      productoNombre: (p?['nombre'] as String?) ?? '?',
    );
  }
}

/// Entrada para `saveReceta`.
class RecetaComponenteInput {
  const RecetaComponenteInput({
    required this.productoId,
    required this.cantidad,
    required this.tipoComponente,
    this.unidad = 'unidad',
    this.pesoVariable = 0,
  });

  final int productoId;
  final double cantidad;
  final String tipoComponente;
  final String unidad;
  final int pesoVariable;

  Map<String, dynamic> toMap(int recetaId) => {
        'receta_id': recetaId,
        'producto_id': productoId,
        'cantidad': cantidad,
        'unidad': unidad.isEmpty ? 'unidad' : unidad,
        'tipo_componente': tipoComponente,
        'peso_variable': pesoVariable,
      };
}

/// Repositorio de producciones — porta `usr/views/producciones/data.py`
/// (recetas, producciones, descargo). Opera directamente contra Supabase.
class ProduccionesRepository {
  ProduccionesRepository(this._db);

  final PostgresService _db;

  // ---------------------------------------------------------------------
  // Helpers de joins en Dart
  // ---------------------------------------------------------------------

  /// Mapa de recetas por id (reemplaza el leftOuterJoin con `recetas`).
  Future<Map<int, Map<String, dynamic>>> _recetasPorIds(List<int> ids) async {
    final unique = ids.toSet().toList();
    if (unique.isEmpty) return {};
    final rows = await _db.client.from('recetas').select().inFilter('id', unique);
    return {
      for (final r in (rows as List).cast<Map<String, dynamic>>())
        r['id'] as int: r,
    };
  }

  /// Mapa de productos por id (reemplaza los joins con `productos`).
  Future<Map<int, Map<String, dynamic>>> _productosPorIds(
    List<int> ids,
  ) async {
    final unique = ids.toSet().toList();
    if (unique.isEmpty) return {};
    final rows =
        await _db.client.from('productos').select().inFilter('id', unique);
    return {
      for (final r in (rows as List).cast<Map<String, dynamic>>())
        r['id'] as int: r,
    };
  }

  // ---------------------------------------------------------------------
  // Recetas
  // ---------------------------------------------------------------------

  Future<List<Receta>> getRecetas({bool activo = true}) async {
    final rows = await _db.fetchAll(
      'recetas',
      orderBy: 'nombre',
      filters: activo ? {'activo': true} : null,
    );
    return rows.map(Receta.fromMap).toList();
  }

  Future<Receta?> getReceta(int id) async {
    final row = await _db.fetchById('recetas', id);
    return row == null ? null : Receta.fromMap(row);
  }

  Future<int> contarComponentes(int recetaId) {
    return _db.count('receta_componentes', filters: {'receta_id': recetaId});
  }

  Future<int> contarTipoComponente(int recetaId, String tipo) {
    return _db.count('receta_componentes',
        filters: {'receta_id': recetaId, 'tipo_componente': tipo});
  }

  Future<int> contarPesoVariable(int recetaId) {
    return _db.count('receta_componentes',
        filters: {'receta_id': recetaId, 'peso_variable': true});
  }

  /// Componentes con nombre y flag pesable (porta `get_componentes_by_receta`).
  Future<List<ComponenteInfo>> getComponentes(int recetaId) async {
    final comps = await _db.fetchAll('receta_componentes',
        filters: {'receta_id': recetaId}, orderBy: 'id');
    final prods = await _productosPorIds(
      comps.map((c) => c['producto_id'] as int).toList(),
    );
    return comps
        .map((c) => ComponenteInfo.fromMap(c, prods[c['producto_id'] as int]))
        .toList();
  }

  /// Todos los componentes con nombre (para precargar counts sin N+1).
  Future<List<ComponenteInfo>> getAllComponentes() async {
    final comps = await _db.fetchAll('receta_componentes', orderBy: 'id');
    final prods = await _productosPorIds(
      comps.map((c) => c['producto_id'] as int).toList(),
    );
    return comps
        .map((c) => ComponenteInfo.fromMap(c, prods[c['producto_id'] as int]))
        .toList();
  }

  /// Guarda receta + reemplaza componentes (porta `guardar_receta` +
  /// `save_receta` + `save_componentes`). Devuelve el id de la receta.
  Future<int> saveReceta({
    required String nombre,
    required String tipo,
    required double cantidadProducida,
    int? productoBaseId,
    int? productoFinalId,
    List<RecetaComponenteInput> componentes = const [],
    int? recetaId,
    int activo = 1,
  }) async {
    final now = DateTime.now().toIso8601String();
    final data = {
      'nombre': nombre,
      'tipo': tipo,
      'producto_base_id': productoBaseId,
      'producto_final_id': productoFinalId,
      'cantidad_producida': cantidadProducida,
      'activo': activo,
      'updated_at': now,
    };

    late int rid;
    if (recetaId != null) {
      await _db.updateById('recetas', recetaId, data);
      rid = recetaId;
    } else {
      rid = await _db.insert('recetas', {...data, 'created_at': now});
    }
    await _db.deleteWhere('receta_componentes', {'receta_id': rid});
    await _db.insertBatch(
      'receta_componentes',
      componentes.map((c) => c.toMap(rid)).toList(),
    );
    return rid;
  }

  Future<void> eliminarReceta(int recetaId) async {
    await _db.deleteWhere('receta_componentes', {'receta_id': recetaId});
    await _db.deleteById('recetas', recetaId);
  }

  // ---------------------------------------------------------------------
  // Productos y stock
  // ---------------------------------------------------------------------

  Future<List<Producto>> getProductosActivos({int limit = 500}) async {
    final rows = await _db.fetchAll('productos',
        filters: {'activo': true}, orderBy: 'nombre', limit: limit);
    return rows.map(Producto.fromMap).toList();
  }

  Future<Producto?> getProducto(int id) async {
    final row = await _db.fetchById('productos', id);
    return row == null ? null : Producto.fromMap(row);
  }

  Future<double> stockTotalProducto(int productoId) async {
    final rows =
        await _db.fetchAll('existencias', filters: {'producto_id': productoId});
    var total = 0.0;
    for (final e in rows) {
      total += (e['cantidad'] as num?)?.toDouble() ?? 0;
    }
    return total;
  }

  /// Stock total (todos los almacenes) por producto, en una sola consulta.
  Future<Map<int, double>> stockTotalPorProducto() async {
    final rows = await _db.executeSql(
        'SELECT producto_id, SUM(cantidad) AS total FROM existencias '
        'WHERE producto_id IS NOT NULL GROUP BY producto_id');
    return {
      for (final e in rows)
        e['producto_id'] as int: (e['total'] as num).toDouble(),
    };
  }

  Future<double> getExistencia(int productoId, String almacen) async {
    final e = await _db.fetchByTwoFields(
        'existencias', 'producto_id', productoId, 'almacen', almacen);
    return (e?['cantidad'] as num?)?.toDouble() ?? 0;
  }

  /// Existencias de varios productos en un almacén, en una sola consulta.
  Future<Map<int, double>> getExistenciasParaDescargo(
      List<int> productoIds, String almacen) async {
    if (productoIds.isEmpty) return {};
    final rows = await _db.executeSql(
      'SELECT producto_id, cantidad FROM existencias '
      'WHERE producto_id = ANY(\$1) AND almacen = \$2',
      params: [productoIds, almacen],
    );
    return {
      for (final r in rows)
        r['producto_id'] as int: (r['cantidad'] as num).toDouble(),
    };
  }

  Future<List<String>> getAlmacenes() async {
    final data = await _db.client.from('existencias').select('almacen');
    final almacenes = {
      for (final r in (data as List).cast<Map<String, dynamic>>())
        if (r['almacen'] != null) r['almacen'] as String,
    };
    almacenes
      ..add('principal')
      ..add('restaurante');
    return almacenes.toList()..sort();
  }

  Future<String> almacenProduccionDefault() async {
    try {
      final row = await _db.client
          .from('pos_settings')
          .select('value')
          .eq('key', 'almacen_produccion')
          .maybeSingle();
      final v = (row?['value'] as String?)?.trim();
      return (v == null || v.isEmpty) ? 'restaurante' : v;
    } catch (_) {
      return 'restaurante';
    }
  }

  // ---------------------------------------------------------------------
  // Producciones (lectura)
  // ---------------------------------------------------------------------

  /// Historial de producciones con nombre de receta, fecha desc, límite.
  Future<List<ProduccionInfo>> getProducciones({int limit = 50}) async {
    final rows = await _db.fetchAll('producciones',
        orderBy: 'fecha_produccion', ascending: false, limit: limit);
    final recetas = await _recetasPorIds(
      rows.map((r) => r['receta_id'] as int).toList(),
    );
    return rows.map((p) {
      final rec = recetas[p['receta_id'] as int];
      return ProduccionInfo.fromMap(
        p,
        (rec?['nombre'] as String?) ?? '',
        (rec?['tipo'] as String?) ?? '',
      );
    }).toList();
  }

  /// Producciones de un estado (porta `load_pendientes`).
  Future<List<ProduccionInfo>> getProduccionesPorEstado(String estado) async {
    final all = await getProducciones(limit: 200);
    return all.where((p) => p.estado == estado).toList();
  }

  Future<ProduccionInfo?> getProduccion(int id) async {
    final p = await _db.fetchById('producciones', id);
    if (p == null) return null;
    final rec = await _db.fetchById('recetas', p['receta_id'] as int);
    return ProduccionInfo.fromMap(
      p,
      (rec?['nombre'] as String?) ?? '',
      (rec?['tipo'] as String?) ?? '',
    );
  }

  /// Detalles de una producción con nombre de producto (porta
  /// `get_detalles_by_produccion`).
  Future<List<DetalleInfo>> getDetalles(int produccionId) async {
    final dets = await _db.fetchAll('produccion_detalles',
        filters: {'produccion_id': produccionId}, orderBy: 'id');
    final prods = await _productosPorIds(
      dets.map((d) => d['producto_id'] as int).toList(),
    );
    return dets
        .map((d) => DetalleInfo.fromMap(d, prods[d['producto_id'] as int]))
        .toList();
  }

  /// Productos resultantes de una producción (detalles tipo 'entrada').
  Future<List<Producido>> productosProducidos(int produccionId) async {
    final detalles = await getDetalles(produccionId);
    return detalles
        .where((d) => d.tipo == 'entrada')
        .map((d) => Producido(
              productoId: d.productoId,
              nombre: d.productoNombre,
              cantidad: d.cantidad,
              unidad: d.unidad,
            ))
        .toList();
  }

  // ---------------------------------------------------------------------
  // Flujo de 2 etapas
  // ---------------------------------------------------------------------

  /// Etapa 1: registra `entrada_produccion` + producción pendiente + detalle.
  /// Si `produccionId` es no nulo, la entrada se VINCULA a ese lote y su
  /// cantidad pasa a ser la suma de todas las entradas (porta
  /// `registrar_produccion_pendiente`). Devuelve (produccion_id, movimiento_id).
  Future<({int? produccionId, int? movimientoId})>
      registrarProduccionPendiente({
    required Producto producto,
    required Receta receta,
    required double cantidad,
    double pesoTotal = 0,
    String? almacen,
    int? produccionId,
    String usuario = 'Sistema',
    String? observaciones,
  }) async {
    return _registrarProduccionPendienteInternal(
      productoId: producto.id,
      esPesable: producto.esPesable,
      unidadMedida: producto.unidadMedida,
      receta: receta,
      cantidad: cantidad,
      pesoTotal: pesoTotal,
      almacen: almacen,
      produccionId: produccionId,
      usuario: usuario,
      observaciones: observaciones,
    );
  }

  /// Versión con parámetros primitivos (para llamar desde UI migrada a modelos de dominio).
  Future<({int? produccionId, int? movimientoId})>
      registrarProduccionPendienteRaw({
    required int productoId,
    required bool esPesable,
    required String unidadMedida,
    required Receta receta,
    required double cantidad,
    double pesoTotal = 0,
    String? almacen,
    int? produccionId,
    String usuario = 'Sistema',
    String? observaciones,
  }) async {
    return _registrarProduccionPendienteInternal(
      productoId: productoId,
      esPesable: esPesable,
      unidadMedida: unidadMedida,
      receta: receta,
      cantidad: cantidad,
      pesoTotal: pesoTotal,
      almacen: almacen,
      produccionId: produccionId,
      usuario: usuario,
      observaciones: observaciones,
    );
  }

  Future<({int? produccionId, int? movimientoId})>
      _registrarProduccionPendienteInternal({
    required int productoId,
    required bool esPesable,
    required String unidadMedida,
    required Receta receta,
    required double cantidad,
    double pesoTotal = 0,
    String? almacen,
    int? produccionId,
    String usuario = 'Sistema',
    String? observaciones,
  }) async {
    final obsExtra = (observaciones ?? '').trim();
    final obsAuto = produccionId == null
        ? "Producción pendiente - Receta '${receta.nombre}'"
        : "Entrada vinculada al lote #$produccionId - Receta '${receta.nombre}'";
    final obs = obsExtra.isEmpty
        ? obsAuto
        : '$obsAuto | $obsExtra';

    final movimientoId = await _registrarMovimientoRaw(
      productoId: productoId,
      esPesable: esPesable,
      unidadMedida: unidadMedida,
      tipo: 'entrada_produccion',
      cantidad: cantidad,
      pesoTotal: pesoTotal,
      almacen: almacen,
      observaciones: obs,
      registradoPor: usuario,
    );
    if (movimientoId == null) return (produccionId: null, movimientoId: null);

    int pid;
    if (produccionId == null) {
      pid = await _insertProduccion(
        recetaId: receta.id,
        cantidad: cantidad,
        estado: 'pendiente',
        usuario: usuario,
        observaciones: obs,
        fechaProduccion: DateTime.now(),
      );
    } else {
      pid = produccionId;
      final entradas =
          (await getDetalles(pid)).where((d) => d.tipo == 'entrada');
      var total = cantidad;
      for (final d in entradas) {
        total += d.cantidad;
      }
      await _updateProduccionCantidad(pid, total);
      _appendProduccionObservaciones(pid, obsExtra);
    }

    await _insertProduccionDetalle(
      produccionId: pid,
      productoId: productoId,
      tipo: 'entrada',
      cantidad: cantidad,
      unidad: (pesoTotal > 0 || esPesable) ? 'kg' : unidadMedida,
      movimientoId: movimientoId,
    );

    return (produccionId: pid, movimientoId: movimientoId);
  }

  /// Calcula los ingredientes a descargar (porta `planificar_descargo`).
  /// Recetas compuestas → INGREDIENTEs; simples → producto_base.
  Future<List<DescargoItem>> planificarDescargo(
      ProduccionInfo produccion, Receta receta) async {
    final esCompuesta = receta.tipo == 'compuesta';
    final produccionCantidad = produccion.cantidad;
    final cantidadBase = receta.cantidadProducida <= 0
        ? 1.0
        : receta.cantidadProducida;
    final factor = produccionCantidad / cantidadBase;
    final almacenDescargo = await almacenProduccionDefault();

    final items = <DescargoItem>[];
    if (esCompuesta) {
      final componentes = await getComponentes(receta.id);
      for (final comp in componentes) {
        if (comp.tipoComponente != 'INGREDIENTE') continue;
        final prod = await getProducto(comp.productoId);
        if (prod == null) continue;
        items.add(DescargoItem(
          productoId: prod.id,
          nombre: prod.nombre,
          cantidadSugerida: comp.cantidad * factor,
          pesoVariable: false,
          unidad: comp.unidad.isEmpty ? prod.unidadMedida : comp.unidad,
          esPesable: prod.esPesable,
          almacen: almacenDescargo,
        ));
      }
    } else if (receta.productoBaseId != null) {
      final prod = await getProducto(receta.productoBaseId!);
      if (prod != null) {
        final pesable = prod.esPesable;
        items.add(DescargoItem(
          productoId: prod.id,
          nombre: prod.nombre,
          cantidadSugerida: pesable ? 0.0 : produccionCantidad,
          pesoVariable: pesable,
          unidad: pesable ? 'kg' : prod.unidadMedida,
          esPesable: pesable,
          almacen: almacenDescargo,
        ));
      }
    }
    return items;
  }

  /// Etapa 2: registra `salida_produccion` por cada ingrediente y marca
  /// completado (porta `ejecutar_descargo`). Devuelve (ok, errores).
  Future<(bool, List<String>)> ejecutarDescargo({
    required ProduccionInfo produccion,
    required Receta receta,
    required List<DescargoItem> items,
    String? cocineros,
    String usuario = 'Sistema',
  }) async {
    try {
      final (ok, errs) = await _db.transaction((tx) async {
        final errores = <String>[];

        // Resolver productos de todos los items en una sola consulta.
        final pids = [
          for (final i in items)
            if (i.cantidadSugerida > 0) i.productoId,
        ];
        final prodRows = pids.isEmpty
            ? <Map<String, dynamic>>[]
            : await tx.executeSql(
                'SELECT * FROM productos WHERE id = ANY(\$1)',
                params: [pids],
              );
        final prods = <int, Producto>{
          for (final r in prodRows) r['id'] as int: Producto.fromMap(r),
        };

        // Items procesables con campos resueltos (nombre, almacén, unidad).
        final procesables = <DescargoItem>[];
        for (final item in items) {
          if (item.cantidadSugerida <= 0) continue;
          final prod = prods[item.productoId];
          if (prod == null) {
            errores.add('Producto ${item.productoId} no encontrado');
            continue;
          }
          final esPesable = item.esPesable || prod.esPesable;
          procesables.add(DescargoItem(
            productoId: item.productoId,
            nombre: item.nombre.isEmpty ? prod.nombre : item.nombre,
            cantidadSugerida: item.cantidadSugerida,
            pesoVariable: item.pesoVariable || esPesable,
            unidad: esPesable
                ? 'kg'
                : (item.unidad.isEmpty ? prod.unidadMedida : item.unidad),
            esPesable: esPesable,
            almacen: item.almacen.isEmpty
                ? (prod.almacenPredeterminado.isEmpty
                    ? 'principal'
                    : prod.almacenPredeterminado)
                : item.almacen,
          ));
        }
        if (errores.isNotEmpty) return (false, errores);
        if (procesables.isEmpty) return (true, <String>[]);

        // Existencias actuales de todos los items en una sola consulta.
        final exRows = await tx.executeSql(
          'SELECT * FROM existencias WHERE producto_id = ANY(\$1)',
          params: [pids],
        );
        final existencias = <String, Map<String, dynamic>>{
          for (final r in exRows) '${r['producto_id']}|${r['almacen']}': r,
        };

        // Construir lotes de movimientos, existencias y detalles.
        final ahora = DateTime.now();
        final movimientos = <Map<String, dynamic>>[];
        final upserts = <Map<String, dynamic>>[];
        final detalles = <Map<String, dynamic>>[];

        for (final item in procesables) {
          final pesoTotal = item.esPesable ? item.cantidadSugerida : 0.0;
          final unidad = item.esPesable ? 'kg' : item.unidad;
          final k = '${item.productoId}|${item.almacen}';
          final prev = existencias[k];
          final cantAnterior = (prev?['cantidad'] as num?)?.toDouble() ?? 0;
          if (cantAnterior < item.cantidadSugerida) {
            errores.add('Stock insuficiente para ${item.nombre}');
            continue;
          }
          final cantNueva = cantAnterior - item.cantidadSugerida;

          movimientos.add({
            'producto_id': item.productoId,
            'tipo': 'salida_produccion',
            'cantidad': item.cantidadSugerida,
            'cantidad_anterior': cantAnterior,
            'cantidad_nueva': cantNueva,
            'peso_total': pesoTotal,
            'registrado_por': usuario,
            'observaciones':
                "Descargo Producción #${produccion.id} - ${receta.nombre}",
            'almacen': item.almacen,
            'fecha_movimiento': ahora.toIso8601String(),
          });
          upserts.add({
            'producto_id': item.productoId,
            'almacen': item.almacen,
            'cantidad': cantNueva,
            'unidad': unidad,
          });
          detalles.add({
            'produccion_id': produccion.id,
            'producto_id': item.productoId,
            'tipo': 'salida',
            'cantidad': item.cantidadSugerida,
            'unidad': unidad,
            'movimiento_id': -1,
          });
        }
        if (errores.isNotEmpty) return (false, errores);

        // Insertar movimientos (batch) y vincular los ids a los detalles.
        final movIds = await tx.insertBatch('movimientos', movimientos);
        for (var i = 0; i < detalles.length; i++) {
          detalles[i]['movimiento_id'] = movIds[i];
        }
        await tx.insertBatch('produccion_detalles', detalles);
        await tx.upsertBatch(
          'existencias',
          upserts,
          conflictColumns: ['producto_id', 'almacen'],
        );

        // Marcar la producción completada dentro de la misma transacción.
        final p = await tx.fetchById('producciones', produccion.id);
        if (p == null) {
          throw StateError('Producción ${produccion.id} no encontrada');
        }
        await tx.updateById('producciones', produccion.id, {
          'estado': 'completado',
          'observaciones':
              'Descargado por $usuario el ${_fechaTexto(ahora)}',
          'cocineros': cocineros ?? (p['cocineros'] as String?),
        });
        return (true, <String>[]);
      });
      return (ok, errs);
    } catch (e) {
      return (false, ['Error en transacción: $e']);
    }
  }

  /// Revierte todas las entradas del lote y marca la producción cancelada
  /// (porta `cancelar_produccion`). Mantiene audit trail.
  Future<void> cancelarProduccion(
      ProduccionInfo produccion, Receta receta) async {
    final entradas =
        (await getDetalles(produccion.id)).where((d) => d.tipo == 'entrada');

    for (final entrada in entradas) {
      final prod = await getProducto(entrada.productoId);
      if (prod == null) continue;

      final cantidad = entrada.cantidad;
      final esPesable = prod.esPesable;
      var pesoTotal = 0.0;
      var almacen = prod.almacenPredeterminado.isEmpty
          ? 'principal'
          : prod.almacenPredeterminado;

      if (entrada.movimientoId != null) {
        final mov =
            await _db.fetchById('movimientos', entrada.movimientoId!);
        if (mov != null) {
          if (esPesable) {
            pesoTotal = (mov['peso_total'] as num?)?.toDouble() ?? 0;
          }
          final movAlmacen = mov['almacen'] as String?;
          if (movAlmacen != null && movAlmacen.isNotEmpty) {
            almacen = movAlmacen;
          }
        }
      }

      await _registrarMovimiento(
        producto: prod,
        tipo: 'devolucion_produccion',
        cantidad: cantidad,
        pesoTotal: pesoTotal,
        almacen: almacen,
        observaciones:
            "Cancelación Producción #${produccion.id} - ${receta.nombre}",
        registradoPor: 'Sistema',
      );
    }

    await _updateProduccionEstado(produccion.id, 'cancelada');
  }

  // ---------------------------------------------------------------------
  // Internos
  // ---------------------------------------------------------------------

  /// Registra un movimiento tipo producción + actualiza la existencia
  /// (porta `registrar_movimiento` de inventario/movements.py). Devuelve el
  /// id del movimiento, o `null` si el stock no alcanza (solo salidas).
  Future<int?> _registrarMovimiento({
    required Producto producto,
    required String tipo,
    required double cantidad,
    double pesoTotal = 0,
    String? almacen,
    String? observaciones,
    String registradoPor = 'Sistema',
  }) async {
    final almacenSel = (almacen ?? '').trim().isNotEmpty
        ? almacen!.trim()
        : 'principal';

    final existActual = await getExistencia(producto.id, almacenSel);
    final cantAnterior = existActual;

    final esPesable = producto.esPesable;
    final esPorPeso = esPesable && pesoTotal > 0;
    final cantAMover = esPorPeso ? pesoTotal : cantidad;
    final unidad = esPesable ? 'kg' : producto.unidadMedida;

    double cantNueva;
    if (tipo == 'entrada' ||
        tipo == 'entrada_produccion' ||
        tipo == 'ajuste') {
      cantNueva = cantAnterior + cantAMover;
    } else {
      if (cantAnterior < cantAMover) return null;
      cantNueva = cantAnterior - cantAMover;
    }

    final movId = await _db.insert('movimientos', {
      'producto_id': producto.id,
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

    await _upsertExistencia(
      productoId: producto.id,
      almacen: almacenSel,
      cantidad: cantNueva,
      unidad: unidad,
    );

    return movId;
  }

  /// Versión con parámetros primitivos de [_registrarMovimiento].
  Future<int?> _registrarMovimientoRaw({
    required int productoId,
    required bool esPesable,
    required String unidadMedida,
    required String tipo,
    required double cantidad,
    double pesoTotal = 0,
    String? almacen,
    String? observaciones,
    String registradoPor = 'Sistema',
  }) async {
    final almacenSel = (almacen ?? '').trim().isNotEmpty
        ? almacen!.trim()
        : 'principal';

    final existActual = await getExistencia(productoId, almacenSel);
    final cantAnterior = existActual;

    final esPorPeso = esPesable && pesoTotal > 0;
    final cantAMover = esPorPeso ? pesoTotal : cantidad;
    final unidad = esPesable ? 'kg' : unidadMedida;

    double cantNueva;
    if (tipo == 'entrada' ||
        tipo == 'entrada_produccion' ||
        tipo == 'ajuste') {
      cantNueva = cantAnterior + cantAMover;
    } else {
      if (cantAnterior < cantAMover) return null;
      cantNueva = cantAnterior - cantAMover;
    }

    final movId = await _db.insert('movimientos', {
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

    await _upsertExistencia(
      productoId: productoId,
      almacen: almacenSel,
      cantidad: cantNueva,
      unidad: unidad,
    );

    return movId;
  }

  /// Upsert de existencia (busca por producto+almacén, luego update o insert).
  Future<void> _upsertExistencia({
    required int productoId,
    required String almacen,
    required double cantidad,
    required String unidad,
  }) async {
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

  Future<int> _insertProduccion({
    required int recetaId,
    required double cantidad,
    required String estado,
    required String usuario,
    required String observaciones,
    required DateTime fechaProduccion,
  }) async {
    return _db.insert('producciones', {
      'receta_id': recetaId,
      'cantidad': cantidad,
      'estado': estado,
      'usuario': usuario,
      'observaciones': observaciones,
      'fecha_produccion': fechaProduccion.toIso8601String(),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _updateProduccionCantidad(int id, double cantidad) async {
    await _db.updateById('producciones', id, {'cantidad': cantidad});
  }

  /// Agrega las observaciones del usuario a una producción existente
  /// (sin duplicar texto ya presente).
  Future<void> _appendProduccionObservaciones(int id, String texto) async {
    if (texto.trim().isEmpty) return;
    final p = await _db.fetchById('producciones', id);
    if (p == null) return;
    final actual = (p['observaciones'] as String?) ?? '';
    if (actual.contains(texto.trim())) return;
    final combinado = actual.trim().isEmpty
        ? texto.trim()
        : '$actual | ${texto.trim()}';
    await _db.updateById('producciones', id, {'observaciones': combinado});
  }

  Future<void> _updateProduccionEstado(
    int id,
    String estado, {
    String? observaciones,
    String? cocineros,
  }) async {
    final p = await _db.fetchById('producciones', id);
    if (p == null) return;

    await _db.updateById('producciones', id, {
      'estado': estado,
      'observaciones': observaciones ?? (p['observaciones'] as String?),
      'cocineros': cocineros ?? (p['cocineros'] as String?),
    });
  }

  Future<int> _insertProduccionDetalle({
    required int produccionId,
    required int productoId,
    required String tipo,
    required double cantidad,
    required String unidad,
    int? movimientoId,
  }) async {
    return _db.insert('produccion_detalles', {
      'produccion_id': produccionId,
      'producto_id': productoId,
      'tipo': tipo,
      'cantidad': cantidad,
      'unidad': unidad.isEmpty ? 'unidad' : unidad,
      'movimiento_id': movimientoId,
    });
  }

  String _fechaTexto(DateTime dt) {
    String p(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${p(dt.month)}-${p(dt.day)}T${p(dt.hour)}:${p(dt.minute)}:${p(dt.second)}';
  }
}
