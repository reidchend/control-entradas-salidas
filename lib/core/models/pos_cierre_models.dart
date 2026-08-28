library pos_cierre_models;

/// Modelos para el Cierre de Caja con Corte de Inventario (Fase 3+)

/// Línea de venta individual (producto o plato servido)
class LineaVenta {
  const LineaVenta({
    required this.nombre,
    required this.categoria,
    required this.cantidad,
    required this.precioUnitario,
    required this.total,
  });

  final String nombre;
  final String categoria;
  final double cantidad;
  final double precioUnitario;
  final double total;

  Map<String, dynamic> toJson() => {
        'nombre': nombre,
        'categoria': categoria,
        'cantidad': cantidad,
        'precio_unitario': precioUnitario,
        'total': total,
      };

  factory LineaVenta.fromJson(Map<String, dynamic> j) => LineaVenta(
        nombre: j['nombre'] as String,
        categoria: j['categoria'] as String,
        cantidad: (j['cantidad'] as num).toDouble(),
        precioUnitario: (j['precio_unitario'] as num).toDouble(),
        total: (j['total'] as num).toDouble(),
      );
}

/// Reporte simple: agregado por producto/plato + categoría + total
class ReporteSimple {
  const ReporteSimple({
    required this.lineas,
    required this.totalGeneral,
  });

  final List<LineaVenta> lineas;
  final double totalGeneral;

  Map<String, dynamic> toJson() => {
        'lineas': lineas.map((l) => l.toJson()).toList(),
        'total_general': totalGeneral,
      };

  factory ReporteSimple.fromJson(Map<String, dynamic> j) => ReporteSimple(
        lineas: (j['lineas'] as List).map((e) => LineaVenta.fromJson(e)).toList(),
        totalGeneral: (j['total_general'] as num).toDouble(),
      );
}

/// Uso de un ingrediente en un plato específico
class UsoIngrediente {
  const UsoIngrediente({
    required this.plato,
    required this.cantidad,
  });

  final String plato;
  final double cantidad;

  Map<String, dynamic> toJson() => {
        'plato': plato,
        'cantidad': cantidad,
      };

  factory UsoIngrediente.fromJson(Map<String, dynamic> j) => UsoIngrediente(
        plato: j['plato'] as String,
        cantidad: (j['cantidad'] as num).toDouble(),
      );
}

/// Desglose por ingrediente: total consumido, stock final, y usos por plato
class DesgloseIngrediente {
  const DesgloseIngrediente({
    required this.ingrediente,
    required this.totalConsumido,
    required this.stockFinal,
    required this.usos,
  });

  final String ingrediente;
  final double totalConsumido;
  final double stockFinal;
  final List<UsoIngrediente> usos;

  Map<String, dynamic> toJson() => {
        'ingrediente': ingrediente,
        'total_consumido': totalConsumido,
        'stock_final': stockFinal,
        'usos': usos.map((u) => u.toJson()).toList(),
      };

  factory DesgloseIngrediente.fromJson(Map<String, dynamic> j) =>
      DesgloseIngrediente(
        ingrediente: j['ingrediente'] as String,
        totalConsumido: (j['total_consumido'] as num).toDouble(),
        stockFinal: (j['stock_final'] as num).toDouble(),
        usos: (j['usos'] as List).map((e) => UsoIngrediente.fromJson(e)).toList(),
      );
}

/// Reporte detallado: lista de desgloses por ingrediente
class ReporteDetallado {
  const ReporteDetallado({
    required this.desgloses,
  });

  final List<DesgloseIngrediente> desgloses;

  Map<String, dynamic> toJson() => {
        'desgloses': desgloses.map((d) => d.toJson()).toList(),
      };

  factory ReporteDetallado.fromJson(Map<String, dynamic> j) => ReporteDetallado(
        desgloses: (j['desgloses'] as List).map((e) => DesgloseIngrediente.fromJson(e)).toList(),
      );
}

/// Cierre de caja completo: datos de caja + ambos reportes + metadatos
class CierreCaja {
  const CierreCaja({
    required this.sesionId,
    required this.usuarioId,
    required this.usuarioNombre,
    required this.abiertaEn,
    required this.cerradaEn,
    required this.cajaInicial,
    required this.totalVentas,
    required this.cajaFinal,
    required this.reporteSimple,
    required this.reporteDetallado,
    required this.syncUuid,
  });

  final int sesionId;
  final int usuarioId;
  final String usuarioNombre;
  final String abiertaEn;
  final String cerradaEn;
  final double cajaInicial;
  final double totalVentas;
  final double cajaFinal;
  final ReporteSimple reporteSimple;
  final ReporteDetallado reporteDetallado;
  final String syncUuid;

  Map<String, dynamic> toJson() => {
        'sesion_id': sesionId,
        'usuario_id': usuarioId,
        'usuario_nombre': usuarioNombre,
        'abierta_en': abiertaEn,
        'cerrada_en': cerradaEn,
        'caja_inicial': cajaInicial,
        'total_ventas': totalVentas,
        'caja_final': cajaFinal,
        'reporte_simple_json': reporteSimple.toJson(),
        'reporte_detallado_json': reporteDetallado.toJson(),
        'sync_uuid': syncUuid,
      };

  factory CierreCaja.fromJson(Map<String, dynamic> j) => CierreCaja(
        sesionId: j['sesion_id'] as int,
        usuarioId: j['usuario_id'] as int,
        usuarioNombre: j['usuario_nombre'] as String,
        abiertaEn: j['abierta_en'] as String,
        cerradaEn: j['cerrada_en'] as String,
        cajaInicial: (j['caja_inicial'] as num).toDouble(),
        totalVentas: (j['total_ventas'] as num).toDouble(),
        cajaFinal: (j['caja_final'] as num).toDouble(),
        reporteSimple: ReporteSimple.fromJson(j['reporte_simple_json']),
        reporteDetallado: ReporteDetallado.fromJson(j['reporte_detallado_json']),
        syncUuid: j['sync_uuid'] as String,
      );
}