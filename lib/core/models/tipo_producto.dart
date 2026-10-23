/// Tipo de producto del catálogo administrable (`tipos_producto`).
///
/// [protegido] marca los tipos de los que depende la lógica de la app
/// ('producción', 'feria', 'Productos para la venta', 'ninguno'): no se
/// pueden renombrar ni inactivar. [enUso] es cuántos productos usan el tipo
/// (calculado con un subquery al listar el catálogo).
class TipoProducto {
  const TipoProducto({
    required this.id,
    required this.nombre,
    this.protegido = false,
    this.activo = true,
    this.orden = 0,
    this.enUso = 0,
  });

  final int id;
  final String nombre;
  final bool protegido;
  final bool activo;
  final int orden;
  final int enUso;

  factory TipoProducto.fromMap(Map<String, dynamic> m) => TipoProducto(
        id: m['id'] as int,
        nombre: m['nombre'] as String,
        protegido: m['protegido'] == true,
        activo: m['activo'] == true,
        orden: (m['orden'] as num?)?.toInt() ?? 0,
        enUso: (m['en_uso'] as num?)?.toInt() ?? 0,
      );
}
