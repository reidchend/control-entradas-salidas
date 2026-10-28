import '../../../core/utils/supabase_cast.dart';

/// Tipo de activo del catálogo maestro (tabla `activos_tipos`).
///
/// Centraliza la identidad de cada modelo (nombre, grupo, modelo y
/// categoría). Las unidades físicas (`activos`) apuntan aquí con `tipo_id`,
/// de modo que al agregar existencias nunca se reescribe la especificación.
class ActivoTipo {
  ActivoTipo({
    required this.id,
    required this.nombre,
    this.grupo,
    this.modelo,
    this.categoriaId,
    this.activo = true,
    this.precioReferencia,
    this.precioOrigen,
    this.precioActualizadoAt,
  });

  final int id;
  final String nombre;
  final String? grupo;
  final String? modelo;
  final int? categoriaId;
  final bool activo;
  final double? precioReferencia;
  final String? precioOrigen;
  final DateTime? precioActualizadoAt;

  /// Puntaje de coincidencia interno (usado solo en `buscarTiposSimilares`).
  int? puntaje;

  factory ActivoTipo.fromMap(Map<String, dynamic> m) => ActivoTipo(
        id: m['id'] as int,
        nombre: (m['nombre'] as String?) ?? '',
        grupo: m['grupo'] as String?,
        modelo: m['modelo'] as String?,
        categoriaId: m['categoria_id'] == null
            ? null
            : (m['categoria_id'] as num).toInt(),
        activo: toBool(m['activo'], fallback: true),
        precioReferencia: m['precio_referencia'] == null
            ? null
            : (m['precio_referencia'] as num).toDouble(),
        precioOrigen: m['precio_origen'] as String?,
        precioActualizadoAt: m['precio_actualizado_at'] == null
            ? null
            : DateTime.tryParse(m['precio_actualizado_at'].toString()),
      );

  Map<String, dynamic> toMap() => {
        'nombre': nombre,
        'grupo': grupo,
        'modelo': modelo,
        'categoria_id': categoriaId,
        'activo': activo ? 1 : 0,
        'precio_referencia': precioReferencia,
        'precio_origen': precioOrigen,
        'precio_actualizado_at': precioActualizadoAt?.toIso8601String(),
      };

  /// Copia con otro valor de puntaje.
  ActivoTipo copyWithPuntaje(int? puntaje) {
    final copia = ActivoTipo(
      id: id,
      nombre: nombre,
      grupo: grupo,
      modelo: modelo,
      categoriaId: categoriaId,
      activo: activo,
      precioReferencia: precioReferencia,
      precioOrigen: precioOrigen,
      precioActualizadoAt: precioActualizadoAt,
    );
    copia.puntaje = puntaje;
    return copia;
  }
}
