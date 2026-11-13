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

/// Resumen informativo de un contorno servido con platos (no suma al total,
/// su precio ya está incluido en el plato base).
class ResumenContorno {
  const ResumenContorno({
    required this.nombre,
    required this.cantidad,
  });

  final String nombre;
  final double cantidad;

  Map<String, dynamic> toJson() => {
        'nombre': nombre,
        'cantidad': cantidad,
      };

  factory ResumenContorno.fromJson(Map<String, dynamic> j) => ResumenContorno(
        nombre: j['nombre'] as String,
        cantidad: (j['cantidad'] as num).toDouble(),
      );
}

/// Resumen de la actividad de un usuario dentro del turno compartido.
class ResumenUsuario {
  const ResumenUsuario({
    required this.usuarioId,
    required this.nombre,
    this.esAperturista = false,
    this.esCerrador = false,
    this.ventas = 0,
    this.total = 0,
  });

  final int usuarioId;
  final String nombre;
  final bool esAperturista;
  final bool esCerrador;
  final int ventas;
  final double total;

  Map<String, dynamic> toJson() => {
        'usuario_id': usuarioId,
        'nombre': nombre,
        'es_aperturista': esAperturista,
        'es_cerrador': esCerrador,
        'ventas': ventas,
        'total': total,
      };

  factory ResumenUsuario.fromJson(Map<String, dynamic> j) => ResumenUsuario(
        usuarioId: (j['usuario_id'] as num?)?.toInt() ?? 0,
        nombre: j['nombre'] as String? ?? '',
        esAperturista: j['es_aperturista'] as bool? ?? false,
        esCerrador: j['es_cerrador'] as bool? ?? false,
        ventas: (j['ventas'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toDouble() ?? 0,
      );
}

/// Reporte simple: agregado por producto/plato + categoría + total
class ReporteSimple {
  const ReporteSimple({
    required this.lineas,
    required this.totalGeneral,
    this.contornos = const [],
    this.ventasFueraTurno = 0,
    this.montoFueraTurno = 0,
    this.porUsuario = const [],
  });

  final List<LineaVenta> lineas;
  final double totalGeneral;
  final List<ResumenContorno> contornos;

  /// Desglose de ventas por usuario del turno compartido. Vacío en cierres
  /// anteriores al modelo de turnos compartidos.
  final List<ResumenUsuario> porUsuario;

  /// Ventas de la franja del turno hechas con otra sesión que ya estaba
  /// cerrada: NO están incluidas en este cierre. Se reportan como aviso para
  /// que el cierre no quede incompleto en silencio.
  final int ventasFueraTurno;
  final double montoFueraTurno;

  Map<String, dynamic> toJson() => {
        'lineas': lineas.map((l) => l.toJson()).toList(),
        'total_general': totalGeneral,
        if (contornos.isNotEmpty)
          'contornos': contornos.map((c) => c.toJson()).toList(),
        if (porUsuario.isNotEmpty)
          'por_usuario': porUsuario.map((u) => u.toJson()).toList(),
        if (ventasFueraTurno > 0) ...{
          'ventas_fuera_turno': ventasFueraTurno,
          'monto_fuera_turno': montoFueraTurno,
        },
      };

  factory ReporteSimple.fromJson(Map<String, dynamic> j) => ReporteSimple(
        lineas: (j['lineas'] as List).map((e) => LineaVenta.fromJson(e)).toList(),
        totalGeneral: (j['total_general'] as num).toDouble(),
        contornos: (j['contornos'] as List?)
                ?.map((e) => ResumenContorno.fromJson(e))
                .toList() ??
            const [],
        ventasFueraTurno: (j['ventas_fuera_turno'] as num?)?.toInt() ?? 0,
        montoFueraTurno: (j['monto_fuera_turno'] as num?)?.toDouble() ?? 0,
        porUsuario: (j['por_usuario'] as List?)
                ?.map((e) => ResumenUsuario.fromJson(
                    e as Map<String, dynamic>))
                .toList() ??
            const [],
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
    this.cerradoPorId,
    this.cerradoPorNombre = '',
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

  /// Usuario que ejecutó el cierre (en el modelo compartido puede coincidir
  /// con el aperturista; en cierres viejos queda nulo).
  final int? cerradoPorId;
  final String cerradoPorNombre;

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
        if (cerradoPorId != null) 'cerrado_por_usuario_id': cerradoPorId,
        if (cerradoPorNombre.isNotEmpty) 'cerrado_por_nombre': cerradoPorNombre,
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
        cerradoPorId: (j['cerrado_por_usuario_id'] as num?)?.toInt(),
        cerradoPorNombre: j['cerrado_por_nombre'] as String? ?? '',
      );
}