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
        'activo': activo ? 1 : 0,
      };
}