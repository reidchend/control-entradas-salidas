/// Vínculo de producción entre un producto y otro derivado de una receta.
///
/// [esDerivado] = true  → el producto vinculado se produce usando el producto
///                        consultado como insumo.
/// [esDerivado] = false → el producto vinculado es un insumo necesario para
///                        producir el producto consultado.
class VinculoProducto {
  const VinculoProducto({
    required this.productoId,
    required this.nombre,
    required this.tipo,
    required this.unidad,
    required this.stock,
    required this.esDerivado,
  });

  final int productoId;
  final String nombre;
  final String tipo;
  final String unidad;
  final double stock;
  final bool esDerivado;
}
