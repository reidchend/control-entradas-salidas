import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:control_entradas_salidas/core/network/descubrimiento_servidor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cubre la lectura de `api_url.json` del Gist.
///
/// Es la pieza que evita configurar la URL equipo por equipo: el túnel publica
/// la URL y la app la toma sola. Si el formato del Gist cambia, el arranque de
/// todas las apps se rompe, así que los casos raros quedan fijados acá.
void main() {
  late HttpServer gist;
  late DescubridorServidor descubridor;
  var status = 200;
  var responder = '';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    status = 200;
    responder = '';
    gist = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(gist.forEach((request) async {
      await request.drain<void>();
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(responder);
      await request.response.close();
    }));
    descubridor = DescubridorServidor(
      endpoint: Uri.parse('http://${gist.address.host}:${gist.port}/gist'),
    );
  });

  tearDown(() => gist.close(force: true));

  /// Gist con el mismo formato que escribe `update_gist.js`.
  String gistCon(String url) => jsonEncode({
        'files': {
          'api_url.json': {
            'content': jsonEncode({
              'url': url,
              'actualizado': '2026-09-29T12:00:00.000Z',
              'puerto': 8501,
              'rapido': false,
            }),
          },
        },
      });

  group('obtenerUrl', () {
    test('extrae la URL publicada y la cachea', () async {
      responder = gistCon('https://api.lycoris.cl');

      expect(await descubridor.obtenerUrl(), 'https://api.lycoris.cl');
      expect(await descubridor.urlCacheada(), 'https://api.lycoris.cl');
    });

    test('la segunda lectura usa la caché sin volver a pedirla', () async {
      responder = gistCon('https://api.lycoris.cl');
      await descubridor.obtenerUrl();

      // Si el Gist pasa a estar caído, la caché mantiene la app funcionando.
      status = 500;
      responder = '';
      expect(await descubridor.obtenerUrl(), 'https://api.lycoris.cl');
    });

    test('forzar ignora la caché y trae la URL nueva', () async {
      responder = gistCon('https://api-antigua.lycoris.cl');
      await descubridor.obtenerUrl();

      // El túnel cambió de URL: sin `forzar` seguiría con la vieja.
      responder = gistCon('https://api-nueva.lycoris.cl');
      expect(await descubridor.obtenerUrl(forzar: true),
          'https://api-nueva.lycoris.cl');
    });

    test('sin Gist y sin caché devuelve null', () async {
      status = 404;
      expect(await descubridor.obtenerUrl(), isNull);
    });
  });

  group('validación', () {
    test('rechaza una URL que no es https', () async {
      // HTTP plano no viaja cifrado y Android 9+ lo bloquea: propagarlo
      // produciría una app que no conecta en el celular.
      responder = gistCon('http://api.lycoris.cl');

      await expectLater(
        descubridor.obtenerUrl(),
        throwsA(isA<DescubrimientoError>()
            .having((e) => e.mensaje, 'mensaje', contains('https'))),
      );
    });

    test('avisa si falta el archivo api_url.json', () async {
      responder = jsonEncode({'files': {'otro.json': {'content': '{}'}}});

      await expectLater(
        descubridor.obtenerUrl(),
        throwsA(isA<DescubrimientoError>()
            .having((e) => e.mensaje, 'mensaje',
                contains('iniciar_tunnel_api.js'))),
      );
    });

    test('avisa si api_url.json no tiene el campo url', () async {
      responder = jsonEncode({
        'files': {
          'api_url.json': {'content': jsonEncode({'puerto': 8501})}
        },
      });

      await expectLater(
        descubridor.obtenerUrl(),
        throwsA(isA<DescubrimientoError>()
            .having((e) => e.mensaje, 'mensaje', contains('url'))),
      );
    });

    test('avisa si el Gist devuelve basura', () async {
      responder = 'no soy json';

      await expectLater(
        descubridor.obtenerUrl(),
        throwsA(isA<DescubrimientoError>()),
      );
    });

    test('un Gist caido se resuelve con la cache, sin error', () async {
      // Caida de GitHub es transitoria: la app tiene que seguir funcionando
      // con la URL que ya tenia, no mostrar un error.
      responder = gistCon('https://api.lycoris.cl');
      await descubridor.obtenerUrl();

      status = 503;
      expect(await descubridor.obtenerUrl(forzar: true),
          'https://api.lycoris.cl');
    });
  });

  test('olvidar borra la caché', () async {
    responder = gistCon('https://api.lycoris.cl');
    await descubridor.obtenerUrl();
    expect(await descubridor.urlCacheada(), isNotNull);

    await descubridor.olvidar();
    expect(await descubridor.urlCacheada(), isNull);
  });

  test('entiende el contenido que escribe update_gist.js', () async {
    // String exacto producido por `updateApiUrl('https://api.lycoris.cl',
    // { puerto: 8501, rapido: false })`. Si del otro lado cambia una clave o
    // se agrega un campo mal formado, este test lo ve.
    const contenidoReal =
        '{"url":"https://api.lycoris.cl",'
        '"actualizado":"2026-09-29T21:06:36.032Z",'
        '"puerto":8501,"rapido":false}';
    responder = jsonEncode({
      'files': {
        'api_url.json': {'content': contenidoReal}
      },
    });

    expect(await descubridor.obtenerUrl(), 'https://api.lycoris.cl');
  });
}
