import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:control_entradas_salidas/core/config/db_config.dart';
import 'package:control_entradas_salidas/core/data/http_sql_session.dart';
import 'package:control_entradas_salidas/core/network/descubrimiento_servidor.dart';
import 'package:control_entradas_salidas/core/network/postgres_client.dart';

void main() {
  late HttpServer gist;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    gist = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() => gist.close(force: true));

  /// Gist local que publica [url], igual que el que escribe el túnel.
  DescubridorServidor publicando(String url) {
    unawaited(gist.forEach((request) async {
      await request.drain<void>();
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'files': {
            'api_url.json': {
              'content': jsonEncode({'url': url, 'puerto': 8501, 'rapido': true}),
            },
          },
        }));
      await request.response.close();
    }));
    return DescubridorServidor(
      endpoint: Uri.parse('http://${gist.address.host}:${gist.port}/gist'),
    );
  }

  /// Gist local caído: no sirve, como cuando no hay internet.
  DescubridorServidor caido() {
    unawaited(gist.forEach((request) async {
      await request.drain<void>();
      request.response.statusCode = 404;
      await request.response.close();
    }));
    return DescubridorServidor(
      endpoint: Uri.parse('http://${gist.address.host}:${gist.port}/gist'),
    );
  }

  group('resolveDatabaseUrl', () {
    test('sin nada configurado devuelve vacia', () async {
      // En un binario compilado sin --dart-define y sin configuracion del
      // usuario no hay contra que conectarse. La app lo reporta con
      // "Ajustes → Sistema → Configurar conexión".
      expect(await resolveDatabaseUrl(), isEmpty);
    });

    test('usa la configuracion guardada por el usuario', () async {
      await DbConfig.save(
        const DbConfig(
          host: '100.101.102.103',
          port: 5432,
          database: 'control_entradas',
          user: 'control_app',
          password: 's3cr3t',
        ),
      );

      expect(
        await resolveDatabaseUrl(),
        'postgresql://control_app:s3cr3t@100.101.102.103:5432/'
        'control_entradas?sslmode=disable',
      );
    });

    test('respeta ssl=true de la configuracion guardada', () async {
      await DbConfig.save(
        const DbConfig(
          host: '100.101.102.103',
          port: 5432,
          database: 'control_entradas',
          user: 'control_app',
          password: 's3cr3t',
          ssl: true,
        ),
      );

      expect(await resolveDatabaseUrl(), contains('sslmode=require'));
    });

    test('ignora una configuracion incompleta y no la usa a medias', () async {
      // Quedó guardado el host pero el usuario está vacío: `isComplete` da
      // false, así que no debe construir una URL que va a fallar al conectar.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('db_config_host', '100.101.102.103');
      await prefs.setString('db_config_database', 'control_entradas');

      expect(await resolveDatabaseUrl(), isEmpty);
    });

    test('tras borrar la configuracion vuelve a quedar sin URL', () async {
      await DbConfig.save(
        const DbConfig(
          host: '100.101.102.103',
          port: 5432,
          database: 'control_entradas',
          user: 'control_app',
          password: 's3cr3t',
        ),
      );
      expect(await resolveDatabaseUrl(), isNotEmpty);

      await DbConfig.clear();

      expect(await resolveDatabaseUrl(), isEmpty);
    });

    test('la URL resuelta es parseable por el driver', () async {
      await DbConfig.save(
        const DbConfig(
          host: '100.101.102.103',
          port: 5432,
          database: 'control_entradas',
          user: 'control_app',
          password: 'p@ss:w/rd',
        ),
      );

      final uri = Uri.parse(await resolveDatabaseUrl());
      expect(uri.scheme, 'postgresql');
      expect(uri.host, '100.101.102.103');
      expect(uri.pathSegments.last, 'control_entradas');
      expect(uri.userInfo, contains('control_app'));
    });

    test('en modo proxy no devuelve URL de PostgreSQL', () async {
      // La app no habla con el 5432: habla HTTPS con el proxy. Devolver una
      // URL de PostgreSQL acá haría que `initializePostgres` abriera un pool
      // nativo contra un host que no existe en el equipo del cliente.
      await DbConfig.save(
        const DbConfig(
          host: '',
          port: 5432,
          database: '',
          user: '',
          password: '',
          proxyUrl: 'https://api.ejemplo.cl',
          proxyToken: 'tok-abc',
        ),
      );

      expect(await resolveDatabaseUrl(), isEmpty);
    });
  });

  group('initializePostgres', () {
    test('con proxy configurado devuelve una sesión HTTP con el token',
        () async {
      // Es la ruta que usan las apps Windows y Android detrás del túnel: no
      // se abre ningún socket a PostgreSQL. La URL va como manual, que es el
      // caso de quien tiene su propio túnel y no publica en el Gist.
      await DbConfig.save(
        const DbConfig(
          host: '',
          port: 5432,
          database: '',
          user: '',
          password: '',
          proxyUrl: 'https://api.ejemplo.cl',
          proxyToken: 'tok-abc',
          proxyUrlManual: true,
        ),
      );

      final session = await initializePostgres();

      expect(session, isA<HttpSqlSession>());
      expect((session as HttpSqlSession).token, 'tok-abc');
      expect(session.baseUrlForTest, 'https://api.ejemplo.cl/proxy-sql');
    });

    test('el Gist manda sobre una URL guardada que quedó vieja', () async {
      // El túnel rápido cambia de URL cada vez que se reinicia la PC servidor.
      // Si la app se aferra a la guardada, al segundo reinicio queda hablando
      // con un túnel que ya no existe y el error es un fallo de red genérico.
      await DbConfig.save(
        const DbConfig(
          host: '',
          port: 5432,
          database: '',
          user: '',
          password: '',
          proxyUrl: 'https://tunel-viejo.trycloudflare.com',
          proxyToken: 'tok-abc',
        ),
      );

      final session = await initializePostgres(
        descubridor: publicando('https://tunel-nuevo.trycloudflare.com'),
      );

      expect((session as HttpSqlSession).baseUrlForTest,
          'https://tunel-nuevo.trycloudflare.com/proxy-sql');
    });

    test('con solo el token ya usa el proxy, sin URL guardada', () async {
      // Es el flujo que se pidió: en cada equipo se escribe únicamente el
      // token. Antes, sin URL guardada, usesProxy daba falso y la app caía en
      // el driver nativo, que no tiene a qué conectarse.
      await DbConfig.save(
        const DbConfig(
          host: '',
          port: 5432,
          database: '',
          user: '',
          password: '',
          proxyToken: 'tok-solo',
        ),
      );

      final session = await initializePostgres(
        descubridor: publicando('https://solo-token.trycloudflare.com'),
      );

      expect(session, isA<HttpSqlSession>());
      expect((session as HttpSqlSession).token, 'tok-solo');
      expect(session.baseUrlForTest,
          'https://solo-token.trycloudflare.com/proxy-sql');
    });

    test('sin Gist ni URL guardada avisa en vez de fallar al conectar',
        () async {
      // Con solo el token pero sin red no hay a qué conectarse. El error va
      // tipado para que el login ofrezca "Configurar conexión" en vez de un
      // fallo técnico.
      await DbConfig.save(
        const DbConfig(
          host: '',
          port: 5432,
          database: '',
          user: '',
          password: '',
          proxyToken: 'tok-solo',
        ),
      );

      await expectLater(
        initializePostgres(descubridor: caido()),
        throwsA(isA<DbNotConfiguredError>()),
      );
    });

    test('sin configurar nada avisa en vez de fallar al conectar', () async {
      // Un binario compilado sin --dart-define y sin Ajustes guardados no tiene
      // a qué conectarse. El error va tipado para que el login ofrezca
      // "Configurar conexión" en vez de un fallo técnico.
      await expectLater(
        initializePostgres(),
        throwsA(
          isA<DbNotConfiguredError>().having(
            (e) => e.detalle,
            'detalle',
            contains('Configuración'),
          ),
        ),
      );
    });
  });
}
