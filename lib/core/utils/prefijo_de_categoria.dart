/// Deriva el prefijo de la placa de inventario desde el nombre de una
/// categoría (ej: "Mesas de Centro" → "MDC", "Televisores" → "TELE").
///
/// Espejo Dart de la función `prefijo_de_categoria()` de la migración de
/// Activos, para que al crear una categoría desde la app el prefijo coincida
/// con el que se derive en la base sobre las categorías existentes.
String prefijoDeCategoria(String nombre) {
  final limpio = nombre.toUpperCase().replaceAll(RegExp('[^A-Z0-9 ]'), '');
  final palabras =
      limpio.split(' ').where((p) => p.isNotEmpty).toList(growable: false);

  if (palabras.length >= 2) {
    final siglas = palabras.take(3).map((p) => p.substring(0, 1)).join();
    if (siglas.length >= 2) return siglas;
  }

  final junto = palabras.join();
  if (junto.length >= 4) return junto.substring(0, 4);
  if (junto.isNotEmpty) return junto;
  return 'ACT';
}
