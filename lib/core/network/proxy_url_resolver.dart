import 'descubrimiento_servidor.dart';
import 'motivo_descubrimiento.dart';

/// Resuelve la URL del proxy que la app debe usar en este arranque.
///
/// El Gist manda sobre la URL guardada. Con el túnel rápido la URL cambia en
/// cada reinicio de la PC servidor, así que una app que se aferra a la que
/// guardó queda apuntando a un túnel que ya no existe: el síntoma es un error
/// de red genérico que no dice que hay que actualizar la URL.
///
/// La URL guardada queda como respaldo para el caso en que no hay red, y se
/// respeta tal cual cuando el usuario la escribió a mano ([urlManual]): esa es
/// la salida para cuando el servidor publica su URL por otro lado (túnel con
/// nombre propio, red de pruebas) y no por el Gist.
///
/// No tira por un Gist caído: sin internet la app tiene que poder seguir
/// trabajando con lo que ya sabía. Lo que sí devuelve es [fallo], con el motivo
/// de por qué no pudo leer el Gist. Antes ese motivo se perdía en un `catch`
/// vacío y quien veía el mensaje concluía que nunca se configuró la base, que
/// es justo la conclusión equivocada.
Future<({String url, FalloDescubrimiento? fallo})> resolverUrlProxy({
  required String urlGuardada,
  bool urlManual = false,
  DescubridorServidor? descubridor,
  bool forzar = false,
}) async {
  final guardada = urlGuardada.trim();

  if (urlManual) return (url: guardada, fallo: null);

  final servicio = descubridor ?? DescubridorServidor();
  try {
    final publicada = await servicio.obtenerUrl(forzar: forzar);
    if (publicada != null && publicada.trim().isNotEmpty) {
      return (url: publicada.trim(), fallo: servicio.ultimoFallo);
    }
  } on DescubrimientoError catch (e) {
    // El Gist publica algo ilegible. Reintentar no va a ayudar y la URL
    // guardada es mejor que quedarse sin conectar, pero el motivo es el que
    // dice que hay que ir a republicar en el servidor.
    servicio.ultimoFallo = FalloDescubrimiento(
      MotivoDescubrimiento.contenidoInvalido,
      detalle: e.mensaje,
    );
  } catch (_) {
    // Sin red. La cache del descubridor ya habra devuelto lo ultimo
    // conocido; si no hay nada, se cae en la guardada.
  }

  return (url: guardada, fallo: servicio.ultimoFallo);
}
