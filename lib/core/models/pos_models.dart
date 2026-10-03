import 'usuario.dart';

export 'usuario.dart';
export 'habitacion_models.dart';

/// Alias histórico: el usuario del POS es el usuario central (`usuarios`).
typedef PosUsuario = Usuario;


class PosMesa {
  const PosMesa({
    required this.id,
    required this.numero,
    this.nombre,
    this.zona,
    this.activo = true,
    this.creadoEn,
    this.updatedAt,
  });

  final int id;
  final String numero;
  final String? nombre;
  final String? zona;
  final bool activo;
  final String? creadoEn;
  final DateTime? updatedAt;

  factory PosMesa.fromMap(Map<String, dynamic> m) => PosMesa(
        id: m['id'] as int,
        numero: m['numero'] as String,
        nombre: m['nombre'] as String?,
        zona: m['zona'] as String?,
        activo: (m['activo'] as int?) == 1,
        creadoEn: m['creado_en'] as String?,
        updatedAt: _parseDt(m['updated_at']),
      );

  Map<String, dynamic> toMap() => {
        if (id > 0) 'id': id,
        'numero': numero,
        'nombre': nombre,
        'zona': zona,
        'activo': activo ? 1 : 0,
        'creado_en': creadoEn,
      };

  static DateTime? _parseDt(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }
}


class PosSesion {
  const PosSesion({
    required this.id,
    required this.usuarioId,
    this.abiertaEn,
    this.cerradaEn,
    this.cajaInicial = 0,
    this.cajaFinal,
    this.syncUuid,
  });

  final int id;
  final int usuarioId;
  final String? abiertaEn;
  final String? cerradaEn;
  final double cajaInicial;
  final double? cajaFinal;
  final String? syncUuid;

  factory PosSesion.fromMap(Map<String, dynamic> m) => PosSesion(
        id: m['id'] as int,
        usuarioId: m['usuario_id'] as int,
        abiertaEn: m['abierta_en'] as String?,
        cerradaEn: m['cerrada_en'] as String?,
        cajaInicial: (m['caja_inicial'] as num?)?.toDouble() ?? 0,
        cajaFinal: (m['caja_final'] as num?)?.toDouble(),
        syncUuid: m['sync_uuid'] as String?,
      );

  Map<String, dynamic> toMap() => {
        if (id > 0) 'id': id,
        'usuario_id': usuarioId,
        'abierta_en': abiertaEn,
        'cerrada_en': cerradaEn,
        'caja_inicial': cajaInicial,
        'caja_final': cajaFinal,
        'sync_uuid': syncUuid,
      };
}

class PosComanda {
  const PosComanda({
    required this.id,
    this.sesionId,
    this.mesaId,
    this.habitacionId,
    this.estado = 'abierta',
    this.total = 0,
    this.itemsJson,
    this.syncUuid,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int? sesionId;
  final int? mesaId;
  final int? habitacionId;
  final String estado;
  final double total;
  final String? itemsJson;
  final String? syncUuid;
  final String? createdAt;
  final String? updatedAt;

  factory PosComanda.fromMap(Map<String, dynamic> m) => PosComanda(
        id: m['id'] as int,
        sesionId: m['sesion_id'] as int?,
        mesaId: m['mesa_id'] as int?,
        habitacionId: m['habitacion_id'] as int?,
        estado: (m['estado'] as String?) ?? 'abierta',
        total: (m['total'] as num?)?.toDouble() ?? 0,
        itemsJson: m['items_json'] as String?,
        syncUuid: m['sync_uuid'] as String?,
        createdAt: m['created_at'] as String?,
        updatedAt: m['updated_at'] as String?,
      );

  Map<String, dynamic> toMap() => {
        if (id > 0) 'id': id,
        'sesion_id': sesionId,
        'mesa_id': mesaId,
        'habitacion_id': habitacionId,
        'estado': estado,
        'total': total,
        'items_json': itemsJson,
        'sync_uuid': syncUuid,
        'created_at': createdAt,
      };
}

class PosVenta {
  const PosVenta({
    required this.id,
    this.comandaId,
    this.correlativo,
    this.total = 0,
    this.itemsJson,
    this.mesaId,
    this.habitacionId,
    this.usuarioId,
    this.sesionId,
    this.estado = 'vigente',
    this.ventaAnulaId,
    this.motivoAnulacion,
    this.anuladaPor,
    this.anuladaEn,
    this.tasaBs,
    this.syncUuid,
    this.comandaSyncUuid,
    this.ventaAnulaSyncUuid,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int? comandaId;
  final int? correlativo;
  final double total;
  final String? itemsJson;
  final int? mesaId;
  final int? habitacionId;
  final int? usuarioId;
  final int? sesionId;
  final String estado;
  final int? ventaAnulaId;
  final String? motivoAnulacion;
  final String? anuladaPor;
  final String? anuladaEn;
  final double? tasaBs;
  final String? syncUuid;
  final String? comandaSyncUuid;
  final String? ventaAnulaSyncUuid;
  final String? createdAt;
  final String? updatedAt;

  factory PosVenta.fromMap(Map<String, dynamic> m) => PosVenta(
        id: m['id'] as int,
        comandaId: m['comanda_id'] as int?,
        correlativo: m['correlativo'] as int?,
        total: (m['total'] as num?)?.toDouble() ?? 0,
        itemsJson: m['items_json'] as String?,
        mesaId: m['mesa_id'] as int?,
        habitacionId: m['habitacion_id'] as int?,
        usuarioId: m['usuario_id'] as int?,
        sesionId: m['sesion_id'] as int?,
        estado: (m['estado'] as String?) ?? 'vigente',
        ventaAnulaId: m['venta_anula_id'] as int?,
        motivoAnulacion: m['motivo_anulacion'] as String?,
        anuladaPor: m['anulada_por'] as String?,
        anuladaEn: m['anulada_en'] as String?,
        tasaBs: (m['tasa_bs'] as num?)?.toDouble(),
        syncUuid: m['sync_uuid'] as String?,
        comandaSyncUuid: m['comanda_sync_uuid'] as String?,
        ventaAnulaSyncUuid: m['venta_anula_sync_uuid'] as String?,
        createdAt: m['created_at'] as String?,
        updatedAt: m['updated_at'] as String?,
      );

  Map<String, dynamic> toMap() => {
        if (id > 0) 'id': id,
        'comanda_id': comandaId,
        'correlativo': correlativo,
        'total': total,
        'items_json': itemsJson,
        'mesa_id': mesaId,
        'habitacion_id': habitacionId,
        'usuario_id': usuarioId,
        'sesion_id': sesionId,
        'estado': estado,
        'venta_anula_id': ventaAnulaId,
        'motivo_anulacion': motivoAnulacion,
        'anulada_por': anuladaPor,
        'anulada_en': anuladaEn,
        'tasa_bs': tasaBs,
        'sync_uuid': syncUuid,
        'comanda_sync_uuid': comandaSyncUuid,
        'venta_anula_sync_uuid': ventaAnulaSyncUuid,
        'created_at': createdAt,
      };
}

class PosCategoria {
  const PosCategoria({
    required this.id,
    required this.nombre,
    this.color = '#FF6F00',
    this.icono,
    this.activo = true,
    this.syncUuid,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String nombre;
  final String color;
  final String? icono;
  final bool activo;
  final String? syncUuid;
  final String? createdAt;
  final String? updatedAt;

  factory PosCategoria.fromMap(Map<String, dynamic> m) => PosCategoria(
        id: m['id'] as int,
        nombre: m['nombre'] as String,
        color: (m['color'] as String?) ?? '#FF6F00',
        icono: m['icono'] as String?,
        activo: (m['activo'] as int?) == 1,
        syncUuid: m['sync_uuid'] as String?,
        createdAt: m['created_at'] as String?,
        updatedAt: m['updated_at'] as String?,
      );

  Map<String, dynamic> toMap() => {
        if (id > 0) 'id': id,
        'nombre': nombre,
        'color': color,
        'icono': icono,
        'activo': activo ? 1 : 0,
        'sync_uuid': syncUuid,
        'created_at': createdAt,
      };
}

class PosPlato {
  const PosPlato({
    required this.id,
    required this.nombre,
    required this.categoriaId,
    this.precioVenta = 0,
    this.activo = true,
    this.esContorno = false,
    this.llevaContornos = false,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String nombre;
  final int categoriaId;
  final double precioVenta;
  final bool activo;
  final bool esContorno;
  final bool llevaContornos;
  final String? createdAt;
  final String? updatedAt;

  factory PosPlato.fromMap(Map<String, dynamic> m) => PosPlato(
        id: m['id'] as int,
        nombre: m['nombre'] as String,
        categoriaId: m['categoria_id'] as int,
        precioVenta: (m['precio_venta'] as num?)?.toDouble() ?? 0,
        activo: (m['activo'] as int?) == 1,
        esContorno: (m['es_contorno'] as int?) == 1,
        llevaContornos: (m['lleva_contornos'] as int?) == 1,
        createdAt: m['created_at'] as String?,
        updatedAt: m['updated_at'] as String?,
      );

  Map<String, dynamic> toMap() => {
        if (id > 0) 'id': id,
        'nombre': nombre,
        'categoria_id': categoriaId,
        'precio_venta': precioVenta,
        'activo': activo ? 1 : 0,
        'es_contorno': esContorno ? 1 : 0,
        'lleva_contornos': llevaContornos ? 1 : 0,
        'created_at': createdAt,
      };
}

class PlatoIngrediente {
  const PlatoIngrediente({
    required this.id,
    required this.platoId,
    required this.productoId,
    required this.cantidad,
    this.unidad = 'unidad',
  });

  final int id;
  final int platoId;
  final int productoId;
  final double cantidad;
  final String unidad;

  factory PlatoIngrediente.fromMap(Map<String, dynamic> m) =>
      PlatoIngrediente(
        id: m['id'] as int,
        platoId: m['plato_id'] as int,
        productoId: m['producto_id'] as int,
        cantidad: (m['cantidad'] as num?)?.toDouble() ?? 0,
        unidad: (m['unidad'] as String?) ?? 'unidad',
      );

  Map<String, dynamic> toMap() => {
        if (id > 0) 'id': id,
        'plato_id': platoId,
        'producto_id': productoId,
        'cantidad': cantidad,
        'unidad': unidad,
      };
}

class PosPlatoCategoria {
  const PosPlatoCategoria({
    required this.id,
    required this.nombre,
    this.color = '#FF6F00',
    this.activo = true,
    this.categoriaPadreId,
    this.posCategoriaPadreId,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String nombre;
  final String color;
  final bool activo;
  final int? categoriaPadreId;
  final int? posCategoriaPadreId;
  final String? createdAt;
  final String? updatedAt;

  factory PosPlatoCategoria.fromMap(Map<String, dynamic> m) =>
      PosPlatoCategoria(
        id: m['id'] as int,
        nombre: m['nombre'] as String,
        color: (m['color'] as String?) ?? '#FF6F00',
        activo: (m['activo'] as int?) == 1,
        categoriaPadreId: m['categoria_padre_id'] as int?,
        posCategoriaPadreId: m['pos_categoria_padre_id'] as int?,
        createdAt: m['created_at'] as String?,
        updatedAt: m['updated_at'] as String?,
      );

  Map<String, dynamic> toMap() => {
        if (id > 0) 'id': id,
        'nombre': nombre,
        'color': color,
        'activo': activo ? 1 : 0,
        'categoria_padre_id': categoriaPadreId,
        'pos_categoria_padre_id': posCategoriaPadreId,
        'created_at': createdAt,
      };
}

class PlatoContorno {
  const PlatoContorno({
    required this.id,
    required this.platoId,
    required this.contornoId,
    this.maxSeleccionar = 2,
  });

  final int id;
  final int platoId;
  final int contornoId;
  final int maxSeleccionar;

  factory PlatoContorno.fromMap(Map<String, dynamic> m) => PlatoContorno(
        id: m['id'] as int,
        platoId: m['plato_id'] as int,
        contornoId: m['contorno_id'] as int,
        maxSeleccionar: m['max_seleccionar'] as int? ?? 2,
      );

  Map<String, dynamic> toMap() => {
        if (id > 0) 'id': id,
        'plato_id': platoId,
        'contorno_id': contornoId,
        'max_seleccionar': maxSeleccionar,
      };
}
