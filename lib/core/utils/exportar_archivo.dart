/// Guardado de archivos exportados con dialogo de ruta.
///
/// El paquete `excel` no resuelve esto solo: `excel.save(fileName: nombre)`
/// escribe en RUTA RELATIVA, y lo relativo se resuelve contra el directorio de
/// trabajo del proceso. En una app instalada eso suele ser el directorio del
/// `.exe`, dentro de una carpeta de programa: el archivo se guarda, pero el
/// usuario no tiene por donde encontrarlo y el mensaje solo dice el nombre.
///
/// Este helper hace dos cosas que `excel.save()` no hace:
///   1. pregunta la ruta con el dialogo del sistema (`getSaveLocation`), asi el
///      usuario ve donde va a caer el archivo antes de confirmar
///   2. devuelve la ruta final, para poder mostrarla en el mensaje de exito
///
/// No todas las plataformas tienen dialogo de guardado. Segun la matriz de
/// `file_selector`, "elegir donde guardar" NO existe en Android ni en iOS (solo
/// en Windows, Linux y macOS), y en web la descarga la gestiona el navegador.
/// Por eso hay tres implementaciones y no dos: en movil se guarda en la
/// carpeta de la app y se informa de la ruta, sin dialogo.
library;

export 'exportar_archivo_mobile.dart'
    if (dart.library.io) 'exportar_archivo_io.dart';