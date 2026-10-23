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
    this.stockPorAlmacen = const {},
  });

  final int productoId;
  final String nombre;
  final String tipo;
  final String unidad;
  final double stock;
  final bool esDerivado;

  /// Desglose del stock por almacén (siempre completo, sin filtro):
  /// `{'principal': 5.0, 'restaurante': 2.5}`. [stock] es el total o el del
  /// almacén filtrado en la pantalla; este mapa muestra dónde está cada cosa.
  final Map<String, double> stockPorAlmacen;
}
