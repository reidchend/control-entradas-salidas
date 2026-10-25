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
  });

  final int id;
  final String nombre;
  final String? grupo;
  final String? modelo;
  final int? categoriaId;
  final bool activo;

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
      );

  Map<String, dynamic> toMap() => {
        'nombre': nombre,
        'grupo': grupo,
        'modelo': modelo,
        'categoria_id': categoriaId,
        'activo': activo ? 1 : 0,
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
    );
    copia.puntaje = puntaje;
    return copia;
  }
}
