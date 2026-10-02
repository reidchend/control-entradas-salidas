class ActivosCategoria {
  const ActivosCategoria({
    required this.id,
    required this.nombre,
    this.color = '#2196F3',
    this.activo = true,
  });

  final int id;
  final String nombre;
  final String color;
  final bool activo;

  factory ActivosCategoria.fromMap(Map<String, dynamic> m) =>
      ActivosCategoria(
        id: m['id'] as int,
        nombre: m['nombre'] as String,
        color: (m['color'] as String?) ?? '#2196F3',
        activo: (m['activo'] ?? true) == true ||
            (m['activo'] == 1),
      );

  Map<String, dynamic> toMap() => {
        'nombre': nombre,
        'color': color,
        // Boolean, no 1/0: la columna es boolean en PostgreSQL. `PostgresService`
        // lo normaliza igual, pero escribir el tipo real evita que el próximo
        // método que use este map rompa al mandarlo directo.
        'activo': activo,
      };
}
