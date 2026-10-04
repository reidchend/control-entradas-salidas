class Movimiento {
  const Movimiento({
    required this.id,
    required this.productoId,
    required this.tipo,
    required this.cantidad,
    this.facturaId,
    this.requisicionId,
    this.ventaId,
    this.ventaSyncUuid,
    this.cantidadAnterior = 0,
    this.cantidadNueva = 0,
    this.pesoTotal = 0,
    this.registradoPor,
    this.observaciones,
    this.almacen,
    this.fechaMovimiento,
    this.createdAt,
  });

  final int id;
  final int productoId;
  final int? facturaId;
  final int? requisicionId;
  final int? ventaId;
  final String? ventaSyncUuid;
  final String tipo;
  final double cantidad;
  final double cantidadAnterior;
  final double cantidadNueva;
  final double pesoTotal;
  final String? registradoPor;
  final String? observaciones;
  final String? almacen;
  final DateTime? fechaMovimiento;
  final DateTime? createdAt;

  factory Movimiento.fromMap(Map<String, dynamic> m) => Movimiento(
        id: m['id'] as int,
        productoId: m['producto_id'] as int,
        facturaId: _toInt(m['factura_id']),
        requisicionId: _toInt(m['requisicion_id']),
        ventaId: _toInt(m['venta_id']),
        ventaSyncUuid: m['venta_sync_uuid'] as String?,
        tipo: m['tipo'] as String,
        cantidad: (m['cantidad'] as num?)?.toDouble() ?? 0,
        cantidadAnterior: (m['cantidad_anterior'] as num?)?.toDouble() ?? 0,
        cantidadNueva: (m['cantidad_nueva'] as num?)?.toDouble() ?? 0,
        pesoTotal: (m['peso_total'] as num?)?.toDouble() ?? 0,
        registradoPor: m['registrado_por'] as String?,
        observaciones: m['observaciones'] as String?,
        almacen: m['almacen'] as String?,
        // `fecha_traslado` es la fecha de negocio del traslado (la fecha en que
        // se creó la requisición) y solo existe en los traslados. Cuando está,
        // es la que hay que mostrar y ordenar: la mercadería se movió ese día,
        // aunque el operador totalizara la requisición días después.
        // `fecha_movimiento` sigue siendo la fecha de registro, y la que usa el
        // recálculo de stock, así que no se toca.
        fechaMovimiento: _parseDt(m['fecha_traslado'] ?? m['fecha_movimiento']),
        createdAt: _parseDt(m['created_at']),
      );

  Map<String, dynamic> toMap() => {
        if (id > 0) 'id': id,
        'producto_id': productoId,
        'factura_id': facturaId,
        'requisicion_id': requisicionId,
        'venta_id': ventaId,
        'venta_sync_uuid': ventaSyncUuid,
        'tipo': tipo,
        'cantidad': cantidad,
        'cantidad_anterior': cantidadAnterior,
        'cantidad_nueva': cantidadNueva,
        'peso_total': pesoTotal,
        'registrado_por': registradoPor,
        'observaciones': observaciones,
        'almacen': almacen,
        'fecha_movimiento': fechaMovimiento?.toUtc().toIso8601String(),
      };

  Movimiento copyWith({
    int? id,
    int? productoId,
    int? facturaId,
    int? requisicionId,
    int? ventaId,
    String? tipo,
    double? cantidad,
    double? cantidadAnterior,
    double? cantidadNueva,
    double? pesoTotal,
    String? registradoPor,
    String? observaciones,
    String? almacen,
    DateTime? fechaMovimiento,
  }) =>
      Movimiento(
        id: id ?? this.id,
        productoId: productoId ?? this.productoId,
        facturaId: facturaId ?? this.facturaId,
        requisicionId: requisicionId ?? this.requisicionId,
        ventaId: ventaId ?? this.ventaId,
        ventaSyncUuid: ventaSyncUuid,
        tipo: tipo ?? this.tipo,
        cantidad: cantidad ?? this.cantidad,
        cantidadAnterior: cantidadAnterior ?? this.cantidadAnterior,
        cantidadNueva: cantidadNueva ?? this.cantidadNueva,
        pesoTotal: pesoTotal ?? this.pesoTotal,
        registradoPor: registradoPor ?? this.registradoPor,
        observaciones: observaciones ?? this.observaciones,
        almacen: almacen ?? this.almacen,
        fechaMovimiento: fechaMovimiento ?? this.fechaMovimiento,
        createdAt: createdAt,
      );

  static int? _toInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v');
  static DateTime? _parseDt(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }
}
