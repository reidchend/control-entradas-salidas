/// Por qué la app no pudo leer la URL del servidor en el Gist.
///
/// Antes estos casos se fundían todos en un `null`: un 403 por límite de tasa
/// de GitHub —60 consultas por hora sin autenticar, y el límite es por IP, así
/// que lo comparten todos los equipos de la oficina— era indistinguible de "no
/// hay internet". Con todo igualado, la pantalla terminaba diciendo "base de
/// datos sin configurar", que manda a reconfigurar algo que ya estaba
/// configurado.
///
/// Acá no hay I/O: el texto y el mapeo de estados HTTP se ejercitan con Dart
/// puro, sin depender de Flutter ni de la red.
library;

/// Cuánto se espera al Gist antes de dar la consulta por perdida.
///
/// Corto a propósito: la alternativa es que la app arranque mostrando la base
/// caída y el usuario espere. Doce segundos alcanza de sobra para leer un JSON
/// chico, y si no alcanza el problema no se arregla esperando más.
const esperaGist = Duration(seconds: 12);

enum MotivoDescubrimiento {
  /// No hubo respuesta: sin internet, DNS que no resuelve, proxy del sistema o
  /// cortafuegos en ese equipo.
  sinRed,

  /// El Gist no respondió dentro de [esperaGist].
  ///
  /// En un equipo donde Chrome sí abre la misma dirección, lo más probable es
  /// IPv6 roto: Dart no corre las direcciones en paralelo como hace Chrome, así
  /// que si el v6 resuelve y no enruta, se queda esperando hasta el timeout.
  tiempoAgotado,

  /// El TLS se rechazó: el certificado no se pudo validar.
  ///
  /// Es el caso del antivirus con inspección HTTPS. En el navegador no aparece
  /// porque Chrome confía en la raíz que el antivirus instaló en la tienda del
  /// sistema, mientras que el cliente HTTP de Dart no siempre la ve: el mismo
  /// equipo abre la página y la app no.
  certificadoRechazado,

  /// GitHub limitó las consultas desde esta conexión (403/429). El límite sin
  /// token es de 60 por hora y se comparte por IP, así que puede caer en
  /// varios equipos a la vez.
  limiteGitHub,

  /// El Gist no existe (404) o la app apunta a un id equivocado.
  gistNoEncontrado,

  /// GitHub respondió con otro error (500, 502, ...). Suele ser del lado de
  /// ellos: reintentar más tarde sí sirve.
  gistFallido,

  /// El Gist respondió, pero publica algo que no es una URL utilizable.
  ///
  /// No es transitorio: reintentarlo da exactamente lo mismo. Casi siempre
  /// significa que falta correr `tool/iniciar_tunnel_api.js` en la PC
  /// servidor, o que quedó publicada una URL de un túnel anterior.
  contenidoInvalido,
}

/// Un fallo de lectura del Gist, con lo necesario para explicárselo a quien
/// lo va a ver en pantalla.
class FalloDescubrimiento {
  const FalloDescubrimiento(this.motivo, {this.status, this.pendiente, this.detalle});

  final MotivoDescubrimiento motivo;

  /// Código HTTP, cuando hubo respuesta. `null` si el problema fue de red.
  final int? status;

  /// Cuántas consultas de la hora quedan, si GitHub lo dice.
  ///
  /// Cuando llega en 0 la lectura va a seguir fallando hasta que se resetea:
  /// reintentar no sirve y el texto tiene que avisar eso, no sugerir esperar.
  final int? pendiente;

  /// Error crudo del sistema operativo, para quien tiene que depurar.
  ///
  /// Va aparte del [mensaje] a propósito: el texto tiene que servirle a quien
  /// lo lee, no volcarle un `CERTIFICATE_VERIFY_FAILED` encima. En la pantalla
  /// se muestra solo si el mensaje no alcanza.
  final String? detalle;

  /// Texto apto para mostrar. Es el detalle que antes se perdía.
  String get mensaje {
    final texto = switch (motivo) {
      MotivoDescubrimiento.sinRed =>
        'Este equipo no pudo conectarse a GitHub. Revisá internet, el proxy '
            'del sistema o el cortafuegos.',
      MotivoDescubrimiento.tiempoAgotado =>
        'GitHub no respondió en ${esperaGist.inSeconds} s. Si en el navegador '
            'esa misma dirección sí abre, probá desactivar IPv6 en este '
            'equipo: la app no prueba las dos versiones en paralelo como hace '
            'el navegador.',
      MotivoDescubrimiento.certificadoRechazado =>
        'No se pudo validar el certificado de GitHub. Suele ser un antivirus '
            'con inspección HTTPS: el navegador confía en él porque usa la '
            'tienda de certificados de Windows y la app no. Se arregla '
            'excluyendo la app de la inspección, o escribiendo la URL del '
            'servidor a mano.',
      MotivoDescubrimiento.limiteGitHub => pendiente == 0
          ? 'GitHub agotó la cuota de consultas de esta conexión y se reinicia '
              'sola en un rato. Como el límite sin token es de 60 por hora y se '
              'comparte por IP, puede pasar en varios equipos a la vez.'
          : 'GitHub está limitando las consultas desde esta conexión '
              '(HTTP $status).',
      MotivoDescubrimiento.gistNoEncontrado =>
        'El Gist con la URL no existe (HTTP $status). Hay que revisar el id '
            'en AppConfig.apiUrlEndpoint.',
      MotivoDescubrimiento.gistFallido =>
        'GitHub respondió con un error (HTTP $status). Suele ser del lado de '
            'ellos: se puede reintentar en un momento.',
      MotivoDescubrimiento.contenidoInvalido =>
        'El Gist no publica una URL que la app pueda usar.',
    };
    return detalle == null ? texto : '$texto ($detalle)';
  }
}

/// Traduce un estado HTTP de GitHub al motivo que le corresponde.
///
/// Un 403 se separa del resto porque es el único que no se arregla esperando y
/// el único que golpea a varios equipos juntos.
FalloDescubrimiento falloPorStatus(int status, {int? pendiente}) =>
    switch (status) {
      403 || 429 => FalloDescubrimiento(
          MotivoDescubrimiento.limiteGitHub,
          status: status,
          pendiente: pendiente,
        ),
      404 => FalloDescubrimiento(
          MotivoDescubrimiento.gistNoEncontrado,
          status: status,
        ),
      _ => FalloDescubrimiento(
          MotivoDescubrimiento.gistFallido,
          status: status,
        ),
    };

/// Lo que quedó resuelto al buscar la URL: cuál se va a usar y, si el Gist no
/// respondió, por qué.
class ResultadoDescubrimiento {
  const ResultadoDescubrimiento({
    this.url,
    this.fallo,
    this.desdeCache = false,
  });

  /// La URL a usar, o `null` si no se pudo determinar ninguna.
  final String? url;

  /// Por qué no se leyó el Gist. `null` cuando la lectura salió bien.
  ///
  /// Se informa aunque [url] no sea `null`: la app puede estar funcionando con
  /// una URL cacheada y aun así conviene saber que el Gist no contesta, porque
  /// cuando esa URL muera no queda de dónde recuperar la nueva.
  final FalloDescubrimiento? fallo;

  /// La URL viene de la cache, no del Gist.
  final bool desdeCache;
}