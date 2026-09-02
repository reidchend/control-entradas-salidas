import '../../../core/data/supabase_service.dart';

class EntradaPorFecha {
  const EntradaPorFecha({
    required this.id,
    required this.productoId,
    required this.nombre,
    required this.unidad,
    required this.esPesable,
    required this.cantidad,
    required this.pesoTotal,
    required this.fecha,
  });

  final int id;
  final int productoId;
  final String nombre;
  final String unidad;
  final bool esPesable;
  final double cantidad;
  final double pesoTotal;
  final DateTime? fecha;

  String get cantidadTexto {
    if (esPesable && pesoTotal > 0) return '${pesoTotal.toStringAsFixed(3)} kg';
    return '${cantidad.toStringAsFixed(0)} $unidad';
  }
}

class FacturaDetalleItem {
  const FacturaDetalleItem({
    required this.productoId,
    required this.nombre,
    required this.cantidad,
    required this.pesoTotal,
    required this.archivado,
  });

  final int productoId;
  final String nombre;
  final double cantidad;
  final double pesoTotal;
  final bool archivado;

  String get cantidadTexto {
    if (pesoTotal > 0) {
      return 'Cant: ${cantidad.toStringAsFixed(0)} | Peso: ${pesoTotal.toStringAsFixed(3)} kg';
    }
    return 'Cant: ${cantidad.toStringAsFixed(0)}';
  }
}

class FacturaDetalle {
  const FacturaDetalle({
    required this.factura,
    required this.items,
    required this.pagos,
  });

  final Map<String, dynamic> factura;
  final List<FacturaDetalleItem> items;
  final List<Map<String, dynamic>> pagos;
}

class LibroComprasRow {
  const LibroComprasRow({
    required this.factura,
    required this.efectivo,
    required this.transferencia,
    required this.divisasUsd,
    this.tasa,
  });

  final Map<String, dynamic> factura;
  final double efectivo;
  final double transferencia;
  final double divisasUsd;
  final double? tasa;
}

class HistorialRepository {
  HistorialRepository(this._db);
  final SupabaseService _db;

  Future<List<Map<String, dynamic>>> getFacturas({
    DateTime? desde,
    DateTime? hasta,
    String search = '',
  }) async {
    dynamic builder = _db.client.from('facturas').select();
    if (desde != null) {
      builder = builder.gte('fecha_factura', desde.toUtc().toIso8601String());
    }
    if (hasta != null) {
      final fin = hasta.add(const Duration(days: 1));
      builder = builder.lt('fecha_factura', fin.toUtc().toIso8601String());
    }
    builder = builder.order('fecha_factura', ascending: false).limit(100);
    final facturas = await builder;

    final term = search.trim().toLowerCase();
    if (term.isEmpty) return facturas;

    return facturas.where((f) {
      final num = (f['numero_factura'] as String? ?? '').toLowerCase();
      final prov = (f['proveedor'] as String? ?? '').toLowerCase();
      return num.contains(term) || prov.contains(term);
    }).toList();
  }

  Future<int> countFacturas({DateTime? desde, DateTime? hasta}) async {
    dynamic builder = _db.client.from('facturas').select('id');
    if (desde != null) {
      builder = builder.gte('fecha_factura', desde.toUtc().toIso8601String());
    }
    if (hasta != null) {
      final fin = hasta.add(const Duration(days: 1));
      builder = builder.lt('fecha_factura', fin.toUtc().toIso8601String());
    }
    final rows = await builder;
    return rows.length;
  }

  Future<List<EntradaPorFecha>> getEntradasPorFecha(
      DateTime ini, DateTime fin) async {
    final movimientos = await _db.client
        .from('movimientos')
        .select()
        .eq('tipo', 'entrada')
        .gte('fecha_movimiento', ini.toUtc().toIso8601String())
        .lt('fecha_movimiento', fin.toUtc().toIso8601String())
        .order('fecha_movimiento', ascending: false)
        .limit(200);

    if (movimientos.isEmpty) return const [];

    final productoIds = movimientos
        .map((m) => m['producto_id'] as int)
        .toSet()
        .toList();
    final productos = await _db.client
        .from('productos')
        .select('id, nombre, unidad_medida, es_pesable')
        .inFilter('id', productoIds);
    final prodMap = <int, Map<String, dynamic>>{
      for (final p in productos) p['id'] as int: p,
    };

    final result = <EntradaPorFecha>[];
    for (final m in movimientos) {
      final p = prodMap[m['producto_id'] as int];
      result.add(EntradaPorFecha(
        id: m['id'] as int,
        productoId: m['producto_id'] as int,
        nombre: (p?['nombre'] as String?) ?? '',
        unidad: (p?['unidad_medida'] as String?) ?? '',
        esPesable: p?['es_pesable'] == 1,
        cantidad: (m['cantidad'] as num?)?.toDouble() ?? 0,
        pesoTotal: (m['peso_total'] as num?)?.toDouble() ?? 0,
        fecha: DateTime.tryParse(m['fecha_movimiento']?.toString() ?? ''),
      ));
    }
    return result;
  }

  Future<FacturaDetalle> getFacturaDetalle(int facturaId) async {
    final factura = (await _db.fetchById('facturas', facturaId))!;

    final movimientos = await _db.client
        .from('movimientos')
        .select()
        .eq('factura_id', facturaId);

    final archivados = await _db.client
        .from('movimientos_archivo')
        .select()
        .eq('factura_id', facturaId);

    final allMoves = [...movimientos, ...archivados];
    final productoIds = allMoves
        .map((m) => m['producto_id'] as int)
        .toSet()
        .toList();
    final prodMap = <int, String>{};
    if (productoIds.isNotEmpty) {
      final productos = await _db.client
          .from('productos')
          .select('id, nombre')
          .inFilter('id', productoIds);
      for (final p in productos) {
        prodMap[p['id'] as int] = (p['nombre'] as String?) ?? '';
      }
    }

    final items = <FacturaDetalleItem>[];
    for (final m in movimientos) {
      items.add(FacturaDetalleItem(
        productoId: m['producto_id'] as int,
        nombre: prodMap[m['producto_id'] as int] ?? '',
        cantidad: (m['cantidad'] as num?)?.toDouble() ?? 0,
        pesoTotal: (m['peso_total'] as num?)?.toDouble() ?? 0,
        archivado: false,
      ));
    }

    for (final m in archivados) {
      items.add(FacturaDetalleItem(
        productoId: m['producto_id'] as int,
        nombre: prodMap[m['producto_id'] as int] ?? '',
        cantidad: (m['cantidad'] as num?)?.toDouble() ?? 0,
        pesoTotal: (m['peso_total'] as num?)?.toDouble() ?? 0,
        archivado: true,
      ));
    }

    final pagos = await _db.fetchAll(
      'factura_pagos',
      filters: {'factura_id': facturaId},
    );

    return FacturaDetalle(factura: factura, items: items, pagos: pagos);
  }

  Future<List<LibroComprasRow>> getLibroCompras(
    DateTime fechaInicio,
    DateTime fechaFin, {
    String? tipoDocumento,
  }) async {
    dynamic builder = _db.client
        .from('facturas')
        .select()
        .gte('fecha_factura', fechaInicio.toUtc().toIso8601String())
        .lte('fecha_factura', fechaFin.toUtc().toIso8601String())
        .eq('estado', 'Validada');
    if (tipoDocumento != null && tipoDocumento.isNotEmpty) {
      builder = builder.eq('tipo_documento', tipoDocumento);
    }
    builder = builder.order('fecha_factura', ascending: true);

    final facturas = await builder;
    if (facturas.isEmpty) return const [];

    final facturaIds = facturas.map((f) => f['id'] as int).toList();
    final allPagos = await _db.client
        .from('factura_pagos')
        .select()
        .inFilter('factura_id', facturaIds);
    final pagosMap = <int, List<Map<String, dynamic>>>{};
    for (final p in allPagos) {
      final fid = p['factura_id'] as int;
      (pagosMap[fid] ??= []).add(p);
    }

    final rows = <LibroComprasRow>[];
    for (final f in facturas) {
      final pagos = pagosMap[f['id'] as int] ?? const [];
      var efectivo = 0.0;
      var transferencia = 0.0;
      var divisasUsd = 0.0;
      double? tasa;
      for (final p in pagos) {
        switch (p['tipo_pago'] as String?) {
          case 'efectivo':
            efectivo = (p['monto'] as num?)?.toDouble() ?? 0;
          case 'transferencia':
            transferencia = (p['monto'] as num?)?.toDouble() ?? 0;
          case 'divisas':
            divisasUsd = (p['monto'] as num?)?.toDouble() ?? 0;
            tasa = (p['tasa_cambio'] as num?)?.toDouble();
        }
      }
      rows.add(LibroComprasRow(
        factura: f,
        efectivo: efectivo,
        transferencia: transferencia,
        divisasUsd: divisasUsd,
        tasa: tasa,
      ));
    }
    return rows;
  }
}
