/// Catálogo de almacenes (tabla `almacenes`).
class Almacen {
  const Almacen({
    required this.id,
    required this.nombre,
    this.descripcion,
    this.activo = true,
    this.orden = 0,
  });

  final int id;
  final String nombre;
  final String? descripcion;
  final bool activo;
  final int orden;

  factory Almacen.fromMap(Map<String, dynamic> m) => Almacen(
        id: m['id'] as int,
        nombre: m['nombre'] as String,
        descripcion: m['descripcion'] as String?,
        activo: (m['activo'] as bool?) ?? (m['activo'] == 1),
        orden: (m['orden'] as num?)?.toInt() ?? 0,
      );

  Almacen copyWith({
    String? nombre,
    String? descripcion,
    bool? activo,
    int? orden,
  }) =>
      Almacen(
        id: id,
        nombre: nombre ?? this.nombre,
        descripcion: descripcion ?? this.descripcion,
        activo: activo ?? this.activo,
        orden: orden ?? this.orden,
      );
}