import '../utils/supabase_cast.dart';

class Requisicion {
  const Requisicion({
    required this.id,
    required this.numero,
    required this.numeroSecuencial,
    required this.origen,
    required this.destino,
    this.estado = 'pendiente',
    this.observaciones,
    this.creadaPor,
    this.procesadaPor,
    this.fechaProcesamiento,
    this.fechaCreacion,
    this.actualizada,
  });

  final int id;
  final String numero;
  final int numeroSecuencial;
  final String origen;
  final String destino;
  final String estado;
  final String? observaciones;
  final String? creadaPor;
  final String? procesadaPor;
  final DateTime? fechaProcesamiento;
  final DateTime? fechaCreacion;
  final DateTime? actualizada;

  factory Requisicion.fromMap(Map<String, dynamic> m) => Requisicion(
        id: m['id'] as int,
        numero: m['numero'] as String,
        numeroSecuencial: (m['numero_secuencial'] as num?)?.toInt() ?? 0,
        origen: m['origen'] as String,
        destino: m['destino'] as String,
        estado: (m['estado'] as String?) ?? 'pendiente',
        observaciones: m['observaciones'] as String?,
        creadaPor: m['creada_por'] as String?,
        procesadaPor: m['procesada_por'] as String?,
        fechaProcesamiento: _parseDt(m['fecha_procesamiento']),
        fechaCreacion: _parseDt(m['fecha_creacion']),
        actualizada: _parseDt(m['actualizada']),
      );

  Map<String, dynamic> toMap() => {
        if (id > 0) 'id': id,
        'numero': numero,
        'numero_secuencial': numeroSecuencial,
        'origen': origen,
        'destino': destino,
        'estado': estado,
        'observaciones': observaciones,
        'creada_por': creadaPor,
        'procesada_por': procesadaPor,
        'fecha_procesamiento':
            fechaProcesamiento?.toUtc().toIso8601String(),
        'fecha_creacion': fechaCreacion?.toUtc().toIso8601String(),
        'actualizada': DateTime.now().toUtc().toIso8601String(),
      };

  Requisicion copyWith({
    int? id,
    String? numero,
    int? numeroSecuencial,
    String? origen,
    String? destino,
    String? estado,
    String? observaciones,
    String? creadaPor,
    String? procesadaPor,
    DateTime? fechaProcesamiento,
  }) =>
      Requisicion(
        id: id ?? this.id,
        numero: numero ?? this.numero,
        numeroSecuencial: numeroSecuencial ?? this.numeroSecuencial,
        origen: origen ?? this.origen,
        destino: destino ?? this.destino,
        estado: estado ?? this.estado,
        observaciones: observaciones ?? this.observaciones,
        creadaPor: creadaPor ?? this.creadaPor,
        procesadaPor: procesadaPor ?? this.procesadaPor,
        fechaProcesamiento: fechaProcesamiento ?? this.fechaProcesamiento,
        fechaCreacion: fechaCreacion,
        actualizada: actualizada,
      );

  static DateTime? _parseDt(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }
}

class RequisicionDetalle {
  const RequisicionDetalle({
    required this.id,
    required this.requisicionId,
    this.productoId,
    required this.ingrediente,
    required this.cantidad,
    this.unidad = 'unidad',
    this.cantidadSurtida = 0,
    this.verificado = false,
    this.peso = 0,
    this.esPesable = false,
  });

  final int id;
  final int requisicionId;
  final int? productoId;
  final String ingrediente;
  final double cantidad;
  final String unidad;
  final double cantidadSurtida;
  final bool verificado;
  final double peso;
  final bool esPesable;

  factory RequisicionDetalle.fromMap(Map<String, dynamic> m) =>
      RequisicionDetalle(
        id: m['id'] as int,
        requisicionId: m['requisicion_id'] as int,
        productoId: _toInt(m['producto_id']),
        ingrediente: m['ingrediente'] as String,
        cantidad: (m['cantidad'] as num?)?.toDouble() ?? 0,
        unidad: (m['unidad'] as String?) ?? 'unidad',
        cantidadSurtida: (m['cantidad_surtida'] as num?)?.toDouble() ?? 0,
        verificado: toBool(m['verificado']),
        peso: (m['peso'] as num?)?.toDouble() ?? 0,
        esPesable: toBool(m['es_pesable']),
      );

  Map<String, dynamic> toMap() => {
        if (id > 0) 'id': id,
        'requisicion_id': requisicionId,
        'producto_id': productoId,
        'ingrediente': ingrediente,
        'cantidad': cantidad,
        'unidad': unidad,
        'cantidad_surtida': cantidadSurtida,
        'verificado': verificado ? 1 : 0,
        'peso': peso,
        'es_pesable': esPesable,
      };

  RequisicionDetalle copyWith({
    int? id,
    int? requisicionId,
    int? productoId,
    String? ingrediente,
    double? cantidad,
    String? unidad,
    double? cantidadSurtida,
    bool? verificado,
    double? peso,
    bool? esPesable,
  }) =>
      RequisicionDetalle(
        id: id ?? this.id,
        requisicionId: requisicionId ?? this.requisicionId,
        productoId: productoId ?? this.productoId,
        ingrediente: ingrediente ?? this.ingrediente,
        cantidad: cantidad ?? this.cantidad,
        unidad: unidad ?? this.unidad,
        cantidadSurtida: cantidadSurtida ?? this.cantidadSurtida,
        verificado: verificado ?? this.verificado,
        peso: peso ?? this.peso,
        esPesable: esPesable ?? this.esPesable,
      );

  static int? _toInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v');
}
