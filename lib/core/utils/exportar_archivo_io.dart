/// Implementacion para escritorio (Windows/Linux) de [exportar_archivo.dart].
///
/// Abre el dialogo de guardado del sistema para que el usuario elija la ruta,
/// y escribe los bytes del Excel ahi.
///
/// Se usa `Excel.encode()` y NO `Excel.save()` a proposito: `encode()` solo
/// devuelve los bytes, mientras que `save()` ademas escribe el archivo en una
/// ruta relativa al directorio de trabajo del proceso. Si se usara `save()`
/// para armar los bytes, cada exportacion dejaria ademas un archivo suelto en
/// el directorio del `.exe`, que es justo el problema que se viene a
/// corregir.
library;

import 'dart:io';

import 'package:excel/excel.dart';
import 'package:file_selector/file_selector.dart';

/// Si la plataforma es movil, donde `getSaveLocation` no existe.
bool get esMovil => Platform.isAndroid || Platform.isIOS;

/// Abre el dialogo de guardado y escribe [excel] en la ruta elegida.
///
/// [nombre] es el nombre sugerido del archivo, con extension. Devuelve la ruta
/// completa donde se guardo, para poder mostrarla al usuario. Devuelve `null`
/// si el usuario cancela el dialogo, en cuyo caso no se escribe nada.
///
/// Lanza [FileSystemException] si la escritura falla (permisos, disco lleno,
/// ruta que ya existe como carpeta).
Future<String?> guardarExcel(Excel excel, String nombre) async {
  final ubicacion = await getSaveLocation(
    suggestedName: nombre,
    acceptedTypeGroups: [
      const XTypeGroup(label: 'Excel', extensions: ['xlsx']),
    ],
  );

  // El usuario cancelo. No se escribe nada.
  if (ubicacion == null) return null;

  final bytes = excel.encode();
  if (bytes == null) {
    throw StateError('No se pudo generar el contenido del archivo Excel');
  }

  final archivo = File(ubicacion.path);
  await archivo.writeAsBytes(bytes, flush: true);
  return archivo.path;
}