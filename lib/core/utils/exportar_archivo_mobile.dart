/// Implementacion movil (Android/iOS) de [exportar_archivo.dart].
///
/// En movil NO se puede pedir la ruta: la matriz de soporte de `file_selector`
/// marca "elegir donde guardar" como no soportado en Android e iOS, y llamar a
/// `getSaveLocation` ahi lanza `UnimplementedError`. Este proyecto compila un
/// APK desde `lib/main.dart`, que monta la pantalla de Activos, asi que la
/// llamada tenia que estar guarded o el export reventaba en Android.
///
/// Que se guarde: en la carpeta de la propia app, que es el unico sitio donde
/// el proceso tiene permiso de escritura sin pedir permisos extra al usuario.
/// Se usa `path_provider`, que ya es dependencia.
///
/// La ruta se devuelve igual, para que el mensaje al usuario la muestre: es
/// el unico modo de que sepa donde quedo el archivo.
library;

import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Si la plataforma es movil. En nativo siempre lo es: este archivo solo se
/// carga en Android/iOS, no en escritorio.
bool get esMovil => true;

/// Guarda [excel] en la carpeta de la app y devuelve la ruta completa.
///
/// En movil no hay dialogo de ruta, asi que [nombre] es el nombre final del
/// archivo. Si ya existe, se sobreescribe: el nombre incluye la fecha, y una
/// reexportacion del mismo dia se espera que deje el archivo al dia.
///
/// Lanza [FileSystemException] si la escritura falla.
Future<String?> guardarExcel(Excel excel, String nombre) async {
  final bytes = excel.encode();
  if (bytes == null) {
    throw StateError('No se pudo generar el contenido del archivo Excel');
  }

  final dir = await getApplicationDocumentsDirectory();
  final archivo = File(p.join(dir.path, nombre));
  await archivo.writeAsBytes(bytes, flush: true);
  return archivo.path;
}