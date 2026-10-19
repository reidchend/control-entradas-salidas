/// Utilidades para comparar y presentar cantidades de stock.
///
/// Postgres guarda `existencias.cantidad` como `double precision`, así que
/// tras muchas sumas y restas en coma flotante el valor acumulado queda con
/// ruido (ej. `1.9999999999999996` en vez de `2`). La app muestra 3
/// decimales, y comparar ese valor "mostrado" contra el real exacto hacía
/// rechazar descargos que sí tienen stock: el usuario teclea lo que el modal
/// muestra (2.000) y el `if (cantAnterior < cantidad)` ve `1.9999… < 2` →
/// "Stock insuficiente".
///
/// Por eso:
/// - las comparaciones usan [toleranciaStock] (medio último decimal que se
///   muestra, 0.0005), que absorbe tanto el ruido de flotantes como el
///   redondeo del formato de 3 decimales;
/// - [restarStock] nunca devuelve negativo (un ruido de ±0.0005 no puede
///   dejar el stock en -0.0004);
/// - [formatearCantidad] redondea a 3 decimales y quita ceros sobrantes
///   ("2.000" → "2", "1.9999" → "2").
library;

/// Medio último decimal del formato de 3 decimales que muestra la app.
const double toleranciaStock = 0.0005;

/// ¿Hay stock suficiente para [requerido] dado [disponible]?
///
/// [requerido] <= 0 siempre pasa (no descarga nada).
bool stockSuficiente(double disponible, double requerido) =>
    requerido <= 0 || disponible + toleranciaStock >= requerido;

/// Resta [requerido] a [disponible] sin dejar la cantidad en negativo.
double restarStock(double disponible, double requerido) {
  final restado = disponible - requerido;
  return restado > toleranciaStock ? restado : 0;
}

/// Cantidad con hasta 3 decimales y sin ceros sobrantes al final.
///
/// `2.000` → `2`, `1.500` → `1.5`, `1.2345` → `1.235`. Un negativo mínimo
/// por ruido de flotante (ej. `-4.4e-16`) se muestra como `0`, nunca `-0`.
String formatearCantidad(double v) {
  if (v < 0 && v.abs() < toleranciaStock) return '0';
  var s = v.toStringAsFixed(3);
  if (s.contains('.')) {
    s = s.replaceAll(RegExp(r'0+$'), '');
    s = s.replaceAll(RegExp(r'\.$'), '');
  }
  return s;
}
