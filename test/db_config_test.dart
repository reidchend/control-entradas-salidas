import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:control_entradas_salidas/core/config/db_config.dart';

DbConfig _config({
  String host = '100.101.102.103',
  int port = 5432,
  String database = 'control_entradas',
  String user = 'control_app',
  String password = 's3cr3t',
  bool ssl = false,
  String proxyUrl = '',
  String proxyToken = '',
  bool proxyUrlManual = false,
}) =>
    DbConfig(
      host: host,
      port: port,
      database: database,
      user: user,
      password: password,
      ssl: ssl,
      proxyUrl: proxyUrl,
      proxyToken: proxyToken,
      proxyUrlManual: proxyUrlManual,
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('DbConfig.load', () {
    test('devuelve null si nunca se guardo', () async {
      expect(await DbConfig.load(), isNull);
    });

    test('reconstruye la configuracion guardada', () async {
      await DbConfig.save(
        _config(host: '10.0.0.5', port: 6000, ssl: true),
      );

      final loaded = await DbConfig.load();

      expect(loaded, isNotNull);
      expect(loaded!.host, '10.0.0.5');
      expect(loaded.port, 6000);
      expect(loaded.database, 'control_entradas');
      expect(loaded.user, 'control_app');
      expect(loaded.password, 's3cr3t');
      expect(loaded.ssl, isTrue);
    });

    test('sin host guardado devuelve null aunque queden otros campos', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('db_config_user', 'control_app');

      expect(await DbConfig.load(), isNull);
    });
  });

  group('DbConfig.save / clear', () {
    test('la contraseña NO queda en SharedPreferences', () async {
      await DbConfig.save(_config(password: 'p4ssw0rd-marcador'));

      final prefs = await SharedPreferences.getInstance();
      // Ningún valor de prefs debe contener la contraseña.
      for (final value in prefs.getKeys().map(prefs.get)) {
        expect(
          value?.toString(),
          isNot(contains('p4ssw0rd-marcador')),
          reason: 'la contraseña se filtró a SharedPreferences',
        );
      }
    });

    test('la contraseña queda en el almacén seguro', () async {
      await DbConfig.save(_config(password: 'p4ssw0rd-marcador'));

      final stored = await const FlutterSecureStorage().read(
        key: 'db_config_password',
      );
      expect(stored, 'p4ssw0rd-marcador');
    });

    test('clear borra de ambos almacenes', () async {
      await DbConfig.save(_config());
      expect(await DbConfig.load(), isNotNull);

      await DbConfig.clear();

      expect(await DbConfig.load(), isNull);
      final secret = await const FlutterSecureStorage().read(
        key: 'db_config_password',
      );
      expect(secret, isNull);
    });

    test('guardar de nuevo sobreescribe sin dejar restos', () async {
      await DbConfig.save(_config(password: 'primera', host: '10.0.0.1'));
      await DbConfig.save(_config(password: 'segunda', host: '10.0.0.2'));

      final loaded = await DbConfig.load();
      expect(loaded!.password, 'segunda');
      expect(loaded.host, '10.0.0.2');
    });
  });

  group('DbConfig.toUrl', () {
    test('arma una URL sin ssl por defecto', () {
      expect(
        _config().toUrl(),
        'postgresql://control_app:s3cr3t@100.101.102.103:5432/'
        'control_entradas?sslmode=disable',
      );
    });

    test('ssl=true produce sslmode=require', () {
      expect(_config(ssl: true).toUrl(), contains('sslmode=require'));
    });

    test('codifica usuario y contraseña con caracteres especiales', () {
      final url = _config(user: 'control@app', password: 'p@ss:w/rd').toUrl();
      // Sin codificar, el '@' y el ':' partirían la URL en el lugar Equivocado.
      expect(url, 'postgresql://control%40app:p%40ss%3Aw%2Frd@'
          '100.101.102.103:5432/control_entradas?sslmode=disable');
    });

    test('la URL resultante se puede parsear de vuelta', () {
      final uri = Uri.parse(_config().toUrl());
      expect(uri.host, '100.101.102.103');
      expect(uri.port, 5432);
      expect(uri.pathSegments.last, 'control_entradas');
      expect(uri.userInfo, 'control_app:s3cr3t');
    });
  });

  group('DbConfig.isComplete', () {
    test('true con host, base y usuario', () {
      expect(_config().isComplete, isTrue);
    });

    test('false si falta el host', () {
      expect(_config(host: '').isComplete, isFalse);
    });

    test('false si falta la base', () {
      expect(_config(database: '').isComplete, isFalse);
    });

    test('false si falta el usuario', () {
      expect(_config(user: '').isComplete, isFalse);
    });

    test('no exige contraseña', () {
      expect(_config(password: '').isComplete, isTrue);
    });
  });

  group('modo proxy', () {
    test('basta con el token para usar el proxy', () {
      // Es el flujo que se pidió: en cada equipo se escribe solo el token. La
      // URL la trae el Gist, así que exigirla guardada dejaba al usuario en
      // modo TCP directo, que no tiene a qué conectarse.
      expect(_config().usesProxy, isFalse);
      expect(_config(proxyUrl: '   ', proxyToken: '  ').usesProxy, isFalse);
      expect(_config(proxyToken: 'tok-abc').usesProxy, isTrue);
      expect(_config(proxyUrl: 'https://api.ejemplo.cl').usesProxy, isTrue);
    });

    test('isComplete con solo el token, sin URL ni host', () {
      const soloToken = DbConfig(
        host: '',
        port: 5432,
        database: '',
        user: '',
        password: '',
        proxyToken: 'tok-abc',
      );
      expect(soloToken.isComplete, isTrue);
    });

    test('load conserva una config que tiene solo el token', () async {
      // Antes load() devolvía null sin host ni URL, así que guardar el token y
      // nada más borraba la configuración del usuario al reiniciar la app.
      await DbConfig.save(
        _config(host: '', database: '', user: '', proxyToken: 'tok-abc'),
      );

      final loaded = await DbConfig.load();
      expect(loaded, isNotNull);
      expect(loaded!.usesProxy, isTrue);
      expect(loaded.proxyToken, 'tok-abc');
    });

    test('la URL manual se recuerda, para no pisarla con la del Gist', () async {
      await DbConfig.save(
        _config(
          host: '',
          database: '',
          user: '',
          proxyUrl: 'https://mi-tunel-propio.cl',
          proxyToken: 'tok-abc',
          proxyUrlManual: true,
        ),
      );

      final loaded = await DbConfig.load();
      expect(loaded!.proxyUrlManual, isTrue);
      expect(loaded.proxyUrl, 'https://mi-tunel-propio.cl');
    });

    test('endpointDe normaliza como proxyEndpoint', () {
      const base = 'https://api.ejemplo.cl';
      final esperado = Uri.parse('https://api.ejemplo.cl/proxy-sql');
      expect(DbConfig.endpointDe(base), esperado);
      expect(DbConfig.endpointDe('$base/'), esperado);
      expect(DbConfig.endpointDe('$base/inventario'), esperado);
      expect(DbConfig.endpointDe('  $base  '), esperado);
    });

    test('proxyEndpoint resuelve /proxy-sql contra la raiz', () {
      const base = 'https://api.ejemplo.cl';
      final esperado = Uri.parse('https://api.ejemplo.cl/proxy-sql');
      // Con barra, sin barra y con un sufijo copiado del navegador: los tres
      // casos son el mismo endpoint, no tres URLs distintas que fallan.
      expect(_config(proxyUrl: base).proxyEndpoint, esperado);
      expect(_config(proxyUrl: '$base/').proxyEndpoint, esperado);
      expect(_config(proxyUrl: '$base/inventario').proxyEndpoint, esperado);
    });

    test('isComplete con solo la URL, sin host de PostgreSQL', () {
      const soloProxy = DbConfig(
        host: '',
        port: 5432,
        database: '',
        user: '',
        password: '',
        proxyUrl: 'https://api.ejemplo.cl',
      );
      expect(soloProxy.isComplete, isTrue);
    });

    test('load recupera un modo proxy sin host guardado', () async {
      await DbConfig.save(
        _config(
          host: '',
          database: '',
          user: '',
          proxyUrl: 'https://api.ejemplo.cl',
          proxyToken: 'tok-abc',
        ),
      );

      final loaded = await DbConfig.load();
      expect(loaded, isNotNull);
      expect(loaded!.usesProxy, isTrue);
      expect(loaded.proxyUrl, 'https://api.ejemplo.cl');
      expect(loaded.proxyToken, 'tok-abc');
    });

    test('el token NO queda en SharedPreferences', () async {
      await DbConfig.save(
        _config(proxyUrl: 'https://api.ejemplo.cl', proxyToken: 'tok-marcador'),
      );

      final prefs = await SharedPreferences.getInstance();
      for (final value in prefs.getKeys().map(prefs.get)) {
        expect(
          value?.toString(),
          isNot(contains('tok-marcador')),
          reason: 'el token del proxy se filtró a SharedPreferences',
        );
      }
      expect(
        await const FlutterSecureStorage().read(key: 'db_config_proxy_token'),
        'tok-marcador',
      );
    });

    test('clear borra la URL y el token del proxy', () async {
      await DbConfig.save(
        _config(proxyUrl: 'https://api.ejemplo.cl', proxyToken: 'tok-abc'),
      );

      await DbConfig.clear();

      expect(await DbConfig.load(), isNull);
      expect(
        await const FlutterSecureStorage().read(key: 'db_config_proxy_token'),
        isNull,
      );
    });

    test('borrar un proxy no deja el modo TCP a medias', () async {
      // Guardar proxy y luego borrar debe dejar la config como si nunca se
      // hubiera configurado, no volver a un host vacío que rompe isComplete.
      await DbConfig.save(
        _config(proxyUrl: 'https://api.ejemplo.cl', proxyToken: 'tok-abc'),
      );
      await DbConfig.clear();

      expect(await DbConfig.load(), isNull);
    });
  });

  group('DbConfig.testProxy', () {
    late _ProxyStub stub;

    tearDown(() => stub.close());

    test('envía el token y valida contra un proxy sano', () async {
      stub = await _ProxyStub.start();
      final config = _config(
        proxyUrl: stub.url,
        proxyToken: 'tok-abc',
      );

      await config.testProxy();

      expect(stub.receivedTokens.single, 'tok-abc');
      final body = jsonDecode(stub.receivedBodies.single) as Map;
      expect(body['action'], 'execute');
      expect(body['sql'], 'SELECT 1');
    });

    test('sin token tampoco manda la cabecera', () async {
      stub = await _ProxyStub.start();
      await _config(proxyUrl: stub.url).testProxy();

      expect(stub.receivedTokens.single, isNull);
    });

    test('un 401 se reporta como token inválido, no como error de red', () async {
      stub = await _ProxyStub.start(
        status: 401,
        body: '{"error": "Token invalido."}',
      );

      await expectLater(
        _config(proxyUrl: stub.url, proxyToken: 'equivocado').testProxy(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Token inválido'),
          ),
        ),
      );
    });

    test('propaga el error del servidor para que sea diagnosticable', () async {
      stub = await _ProxyStub.start(
        status: 503,
        body: '{"error": "Proxy SQL sin token configurado."}',
      );

      await expectLater(
        _config(proxyUrl: stub.url, proxyToken: 'tok-abc').testProxy(),
        throwsA(
          isA<StateError>()
              .having((e) => e.message, 'message', contains('503'))
              .having((e) => e.message, 'message',
                  contains('Proxy SQL sin token configurado.')),
        ),
      );
    });
  });
}

/// Proxy mínimo en loopback para probar `testProxy` contra algo real.
///
/// Se usa un servidor de verdad en vez de un mock porque lo que importa es
/// que la cabecera `X-Proxy-Token` viaje de verdad por HTTP.
class _ProxyStub {
  _ProxyStub._(this._server, this.status, this.body);

  static Future<_ProxyStub> start({
    int status = 200,
    String body = '{"rows": [{"one": 1}], "affectedRows": 1}',
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final stub = _ProxyStub._(server, status, body);
    unawaited(server.forEach((request) async {
      final text = await utf8.decoder.bind(request).join();
      stub._receivedTokens.add(request.headers.value('X-Proxy-Token'));
      stub._receivedBodies.add(text);
      request.response
        ..statusCode = stub.status
        ..headers.contentType = ContentType.json
        ..write(stub.body);
      await request.response.close();
    }));
    return stub;
  }

  final HttpServer _server;
  final int status;
  final String body;
  final List<String?> _receivedTokens = [];
  final List<String> _receivedBodies = [];

  String get url => 'http://${_server.address.host}:${_server.port}';
  List<String?> get receivedTokens => List.unmodifiable(_receivedTokens);
  List<String> get receivedBodies => List.unmodifiable(_receivedBodies);

  Future<void> close() => _server.close(force: true);
}
