// Verifica la logica del selector de almacenes del dialogo de movimientos.
//
// No se puede correr la app (no hay Flutter ni .dart_tool en esta maquina), asi
// que aqui se replican las DOS versiones de la eleccion de almacen con datos
// inventados y se comparan. Lo que se comprueba es la decision: que lista
// termina mostrando el dropdown y cual queda seleccionado.
//
// Lo que esto NO comprueba: que la consulta del catalogo devuelva lo que se
// espera. Eso se verifico leyendo el codigo (configuracion_repository.dart:
//357 lee la tabla `almacenes`, con fallback a los strings de los datos).
//
// Uso:  dart run tool/verificar_selector_almacenes.dart

class Existencia {
  Existencia(this.almacen);
  final String almacen;
}

/// Logica ORIGINAL: la lista sale de las existencias del propio producto.
/// Un producto sin movimientos solo tenia "principal".
List<String> listaVieja(List<Existencia> existencias) {
  final almacenes = existencias.map((e) => e.almacen).toSet().toList();
  if (!almacenes.contains('principal')) almacenes.add('principal');
  return almacenes;
}

/// Logica NUEVA: union del catalogo con las existencias del producto.
List<String> listaNueva(List<Existencia> existencias, List<String> catalogo) {
  final nombres = <String>{
    ...existencias.map((e) => e.almacen),
    ...catalogo,
  };
  if (nombres.isEmpty) nombres.add('principal');
  return nombres.toList()..sort();
}

/// Seleccion por defecto, comun a las dos versiones.
String seleccion(List<String> lista, String predeterminado) {
  return lista.contains(predeterminado) ? predeterminado : lista.first;
}

int fallos = 0;

void check(String etiqueta, bool condicion, String detalle) {
  if (condicion) {
    print('  OK   $etiqueta');
  } else {
    print('  FALLA $etiqueta');
    print('        $detalle');
    fallos++;
  }
}

void main() {
  const catalogoCompleto = ['principal', 'restaurante'];
  const catalogoVacio = <String>[]; // simula que la lectura del catalogo falla

  print('=== 1. Producto recien creado, sin ningun movimiento previo ===');
  final sinMovs = <Existencia>[];
  final vieja1 = listaVieja(sinMovs);
  final nueva1 = listaNueva(sinMovs, catalogoCompleto);
  print('  antes: $vieja1');
  print('  ahora: $nueva1');
  check('antes solo ofrece principal (el bug reportado)',
      vieja1.length == 1 && vieja1.single == 'principal',
      'la version vieja deberia dar solo [principal]');
  check('ahora ofrece todos los del catalogo',
      nueva1.toString() == '[principal, restaurante]',
      'esperaba [principal, restaurante], dio $nueva1');

  print('');
  print('=== 2. Producto con stock solo en "restaurante" ===');
  final soloRestaurante = [Existencia('restaurante')];
  final vieja2 = listaVieja(soloRestaurante);
  final nueva2 = listaNueva(soloRestaurante, catalogoCompleto);
  print('  antes: $vieja2');
  print('  ahora: $nueva2');
  check('la version nueva no pierde el almacen con stock',
      nueva2.contains('restaurante'), 'perdio el almacen con stock');
  check('la version nueva no pierde los demas',
      nueva2.contains('principal'), 'perdio principal');

  print('');
  print('=== 3. Producto con stock en un almacen que ya no esta en el catalogo ===');
  final huerfano = [Existencia('bodega'), Existencia('principal')];
  final vieja3 = listaVieja(huerfano);
  final nueva3 = listaNueva(huerfano, catalogoCompleto);
  print('  antes: ${vieja3.join(", ")}');
  print('  ahora: ${nueva3.join(", ")}');
  check('un almacen con stock pero fuera del catalogo NO se pierde',
      nueva3.contains('bodega'),
      'el stock en "bodega" quedaria inalcanzable si se perdiera');

  print('');
  print('=== 4. El catalogo no se puede leer (fallo de red/BD) ===');
  final nueva4 = listaNueva(sinMovs, catalogoVacio);
  print('  ahora: $nueva4');
  check('no queda con la lista vacia (si no, lista.first revienta)',
      nueva4.isNotEmpty, 'la lista quedaria vacia y lista.first lanzaria');
  check('degrada a principal, como la version vieja',
      nueva4.single == 'principal', 'degradaria a $nueva4');

  print('');
  print('=== 5. Ambos catalogs vacios y producto sin existencias ===');
  final nueva5 = listaNueva(sinMovs, catalogoVacio);
  check('la lista nunca queda vacia',
      nueva5.isNotEmpty, 'lista vacia: lista.first revienta al seleccionar');
  check('se puede seleccionar sin error',
      seleccion(nueva5, 'principal') == 'principal',
      'la seleccion por defecto fallaria');

  print('');
  print('=== 6. Seleccion por defecto ===');
  check('si el almacen predeterminado esta en la lista, se respeta',
      seleccion(nueva1, 'restaurante') == 'restaurante',
      'no respeto el predeterminado');
  check('si no esta en la lista, cae en el primero',
      seleccion(nueva1, 'bodega') == 'principal',
      'no cayo en el primero');

  print('');
  print('=== 7. Sin duplicados ===');
  final conDup = [Existencia('principal'), Existencia('restaurante')];
  final nueva7 = listaNueva(conDup, catalogoCompleto);
  check('no duplica principal aunque este en ambos lados',
      nueva7.toString() == '[principal, restaurante]',
      'duplico: $nueva7');

  print('');
  if (fallos == 0) {
    print('Todo OK: 8 verificaciones');
  } else {
    print('FALLARON $fallos verificaciones');
    throw StateError('la logica del selector no cumple lo esperado');
  }
}
