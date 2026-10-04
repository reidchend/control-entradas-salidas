/// Implementacion web de [exportar_archivo.dart].
///
/// En web no existe el sistema de archivos: no hay rutas que elegir. El
/// navegador ya gestiona la descarga (la carpetade Descargas del usuario), que
/// es exactamente el comportamiento que se busca en nativo, asi que se
/// delegue en el guardado del paquete `excel`.
///
/// Se devuelve `null` como ruta porque en web no hay una ruta que mostrar: el
/// mensaje al usuario no debe inventar una.
library;

import 'package:excel/excel.dart';

/// Si la plataforma es movil. En web nunca: aqui solo se guarda en el
/// navegador.
bool get esMovil => false;

/// Guarda [excel] mediante la descarga del navegador.
///
/// Devuelve `null` siempre: en web no hay ruta de destino que informar.
/// [nombre] es el nombre del archivo (con extension), que el navegador usa
/// para Proposed el nombre en la descarga.
Future<String?> guardarExcel(Excel excel, String nombre) async {
  excel.save(fileName: nombre);
  return null;
}