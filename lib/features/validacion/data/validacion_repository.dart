import '../../../core/data/supabase_service.dart';
import '../../../core/utils/supabase_cast.dart';

class EntradaPendiente {
  const EntradaPendiente({
    required this.id,
    required this.productoId,
    required this.nombre,
    required this.unidad,
    required this.esPesable,
    required this.cantidad,
    required this.pesoTotal,
    required this.almacen,
    required this.fecha,
    required this.cantidadAnterior,
    required this.cantidadNueva,
  });

  final int id;
  final int productoId;
  final String nombre;
  final String unidad;
  final bool esPesable;
  final double cantidad;
  final double pesoTotal;
  final String almacen;
  final DateTime? fecha;
  final double cantidadAnterior;
  final double cantidadNueva;

  String get cantidadTexto {
    if (esPesable && pesoTotal > 0) return '${pesoTotal.toStringAsFixed(3)} kg';
    return '${cantidad.toStringAsFixed(0)} $unidad';
  }
}

class PagoData {
  const PagoData({
    required this.tipo,
    required this.monto,
    this.ref = '',
    this.tasa = 1,
  });

  final String tipo;
  final double monto;
  final String ref;
  final double tasa;
}

class ResultadoValidacion {
  const ResultadoValidacion({
    required this.facturaId,
    required this.movimientosCount,
    required this.usuario,
  });

  final int facturaId;
  final int movimientosCount;
  final String usuario;
}

class ValidacionRepository {
  ValidacionRepository(this._db);
  final SupabaseService _db;

  Future<List<EntradaPendiente>> getEntradasPendientes(
      {String search = ''}) async {
    final movimientos = await _db.client
        .from('movimientos')
        .select()
        .eq('tipo', 'entrada')
        .isFilter('factura_id', null)
        .order('fecha_movimiento', ascending: false);

    if (movimientos.isEmpty) return [];

    final productoIds = movimientos
        .map((m) => m['producto_id'] as int)
        .toSet()
        .toList();

    final productosRows = await _db.client
        .from('productos')
        .select('id, nombre, unidad_medida, es_pesable')
        .inFilter('id', productoIds);
    final productosMap = <int, Map<String, dynamic>>{
      for (final p in productosRows) p['id'] as int: p,
    };

    final List<EntradaPendiente> result = [];
    for (final m in movimientos) {
      final productoId = m['producto_id'] as int;
      final producto = productosMap[productoId];
      final nombre = (producto?['nombre'] as String?) ?? '';
      final term = search.trim().toLowerCase();
      if (term.isNotEmpty && !nombre.toLowerCase().contains(term)) continue;
      result.add(EntradaPendiente(
        id: m['id'] as int,
        productoId: productoId,
        nombre: nombre,
        unidad: (producto?['unidad_medida'] as String?) ?? '',
        esPesable: toBool(producto?['es_pesable']),
        cantidad: (m['cantidad'] as num?)?.toDouble() ?? 0,
        pesoTotal: (m['peso_total'] as num?)?.toDouble() ?? 0,
        almacen: (m['almacen'] as String?) ?? 'principal',
        fecha: DateTime.tryParse(m['fecha_movimiento']?.toString() ?? ''),
        cantidadAnterior:
            (m['cantidad_anterior'] as num?)?.toDouble() ?? 0,
        cantidadNueva: (m['cantidad_nueva'] as num?)?.toDouble() ?? 0,
      ));
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> getProveedores(
      {String estado = 'Activo'}) async {
    final rows = await _db.fetchAll('proveedores', filters: {'estado': estado});
    rows.sort((a, b) =>
        (a['nombre'] as String).compareTo(b['nombre'] as String));
    return rows;
  }

  Future<Map<String, dynamic>?> buscarProveedor(
      {String rif = '', String nombre = ''}) async {
    if (rif.isNotEmpty) {
      final p = await _db.fetchByField('proveedores', 'rif', rif);
      if (p != null) return p;
    }
    if (nombre.isNotEmpty) {
      return _db.fetchByField('proveedores', 'nombre', nombre);
    }
    return null;
  }

  Future<Map<String, dynamic>> crearProveedor({
    required String nombre,
    String rif = '',
  }) async {
    final id = await _db.insert('proveedores', {
      'nombre': nombre,
      'rif': rif.isEmpty ? null : rif,
      'estado': 'Activo',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    return (await _db.fetchById('proveedores', id))!;
  }

  Future<String> getNextEntradaCorrelativo() async {
    final rows = await _db.client
        .from('facturas')
        .select('numero_factura')
        .like('numero_factura', 'EV-%')
        .order('numero_factura', ascending: false)
        .limit(5);
    var maxNum = 0;
    for (final r in rows) {
      final part =
          (r['numero_factura'] as String? ?? '').replaceFirst('EV-', '').trim();
      final n = int.tryParse(part);
      if (n != null && n > maxNum) maxNum = n;
    }
    return 'EV-${(maxNum + 1).toString().padLeft(4, '0')}';
  }

  Future<ResultadoValidacion> procesar({
    required Set<int> selectedEntradas,
    required String proveedor,
    String rif = '',
    required String factura,
    double monto = 0,
    required DateTime fecha,
    String tipoDocumento = 'Factura',
    List<PagoData> pagos = const [],
    String usuario = 'Sistema',
  }) async {
    if (proveedor != 'Varios' && proveedor.isNotEmpty) {
      var prov = await buscarProveedor(rif: rif, nombre: proveedor);
      prov ??= await crearProveedor(nombre: proveedor, rif: rif);
    }

    final refFact =
        factura.trim().isEmpty ? 'EV-${_tsStamp()}' : factura.trim();

    final existente = await _db.client
        .from('facturas')
        .select('id')
        .eq('numero_factura', refFact)
        .maybeSingle();

    int facturaId;
    if (existente != null) {
      facturaId = existente['id'] as int;
      await _vincularMovimientos(facturaId, selectedEntradas);
      await _db.updateById('facturas', facturaId, {
        'numero_factura': refFact,
        'proveedor': proveedor,
        'tipo_documento': tipoDocumento,
        'total_bruto': monto,
        'total_neto': monto,
        'estado': 'Validada',
        'validada_por': usuario,
        'fecha_validacion': DateTime.now().toUtc().toIso8601String(),
      });
    } else {
      final now = DateTime.now().toUtc().toIso8601String();
      facturaId = await _db.insert('facturas', {
        'numero_factura': refFact,
        'tipo_documento': tipoDocumento,
        'proveedor': proveedor == 'Varios' ? null : proveedor,
        'fecha_factura': fecha.toUtc().toIso8601String(),
        'fecha_recepcion': now,
        'total_bruto': monto,
        'total_impuestos': 0,
        'total_neto': monto,
        'estado': 'Validada',
        'validada_por': usuario,
        'fecha_validacion': now,
      });
      await _vincularMovimientos(facturaId, selectedEntradas);
    }

    for (final p in pagos) {
      if (p.monto <= 0) continue;
      final montoVes = p.tipo == 'divisas' ? p.monto * p.tasa : p.monto;
      await _db.insert('factura_pagos', {
        'factura_id': facturaId,
        'tipo_pago': p.tipo,
        'monto': montoVes,
        'referencia': p.ref.isEmpty ? null : p.ref,
        'tasa_cambio': p.tipo == 'divisas' ? p.tasa : null,
        'fecha_pago': DateTime.now().toUtc().toIso8601String(),
      });
    }

    return ResultadoValidacion(
      facturaId: facturaId,
      movimientosCount: selectedEntradas.length,
      usuario: usuario,
    );
  }

  Future<void> _vincularMovimientos(int facturaId, Set<int> ids) async {
    if (ids.isEmpty) return;
    await _db.client
        .from('movimientos')
        .update({'factura_id': facturaId})
        .inFilter('id', ids.toList());
  }

  /// Elimina una entrada pendiente (movimiento 'entrada' sin validar) y
  /// revierte el stock que esa entrada sumó a la existencia del producto en
  /// su almacén. Se resta la cantidad neta (`cantidadNueva - cantidadAnterior`)
  /// que la entrada agregó, para no pisar otros movimientos posteriores.
  Future<void> eliminarEntrada(EntradaPendiente entrada) async {
    final neto = entrada.cantidadNueva - entrada.cantidadAnterior;
    if (neto != 0) {
      final exRows = await _db.fetchAll('existencias', filters: {
        'producto_id': entrada.productoId,
        'almacen': entrada.almacen,
      });
      if (exRows.isNotEmpty) {
        final id = exRows.first['id'] as int;
        final actual =
            (exRows.first['cantidad'] as num?)?.toDouble() ?? 0;
        final nueva = actual - neto;
        await _db.updateById('existencias', id, {
          'cantidad': nueva < 0 ? 0 : nueva,
        });
      }
    }
    await _db.deleteById('movimientos', entrada.id);
  }

  String _tsStamp() {
    final now = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${p(now.month)}${p(now.day)}${p(now.hour)}${p(now.minute)}${p(now.second)}';
  }
}
