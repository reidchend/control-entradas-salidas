import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:control_entradas_salidas/core/config/db_config.dart';
import 'package:control_entradas_salidas/core/data/postgres_guard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:control_entradas_salidas/core/network/postgres_client.dart';

/// Cubre el estado que la UI usa para decidir qué pantalla mostrar.
///
/// Lo que importa acá es la diferencia entre "hay una sesión construida" y "el
/// servidor contestó". [postgresPoolProvider] solo construye el objeto, así que
/// durante un tiempo la app se reportaba conectada con la base apagada y el
/// fallo aparecía recién en la primera query, como un error sin contexto.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('estadoBdProvider', () {
    test('noConfigurada cuando no hay nada guardado', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await expectLater(
        container.read(sesionVerificadaProvider.future),
        throwsA(isA<DbNotConfiguredError>()),
      );

      expect(container.read(estadoBdProvider), EstadoBd.noConfigurada);
    });

    test('noConfigurada cuando quedó guardado solo el host a medias', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('db_config_host', '100.101.102.103');
      await prefs.setString('db_config_database', 'control_entradas');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await expectLater(
        container.read(sesionVerificadaProvider.future),
        throwsA(isA<DbNotConfiguredError>()),
      );

      expect(container.read(estadoBdProvider), EstadoBd.noConfigurada);
    });

    test('conectando mientras el chequeo todavía no terminó', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Sin esperar el future: el provider está en vuelo.
      expect(container.read(estadoBdProvider), EstadoBd.conectando);
    });

    test('error cuando el host configurado no responde', () async {
      // El cambio de fondo: `Pool.withUrl` es perezoso y arma el pool sin abrir
      // el socket, así que antes esto daba `lista` con la base apagada.
      await DbConfig.save(
        const DbConfig(
          host: '127.0.0.1',
          port: 1,
          database: 'control_entradas',
          user: 'control_app',
          password: 'x',
        ),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await expectLater(
        container.read(sesionVerificadaProvider.future),
        throwsA(isA<DbNoDisponibleError>()),
      );

      expect(container.read(estadoBdProvider), EstadoBd.error);
      expect(container.read(errorConexionBdProvider), isA<DbNoDisponibleError>());
    });

    test('error cuando el proxy responde con un fallo', () async {
      // El proxy caído (túnel muerto, token viejo, PC servidor apagada) tiene
      // que verse igual que un host inalcanzable: la UI ofrece Reintentar.
      final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => proxy.close(force: true));
      unawaited(proxy.forEach((request) async {
        await request.drain<void>();
        request.response.statusCode = 502;
        await request.response.close();
      }));

      await DbConfig.save(
        DbConfig(
          host: '',
          port: 5432,
          database: '',
          user: '',
          password: '',
          // Manual para que no se consulte el Gist: el URL base es el local.
          proxyUrl: 'http://${proxy.address.host}:${proxy.port}',
          proxyToken: 'tok-abc',
          proxyUrlManual: true,
        ),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await expectLater(
        container.read(sesionVerificadaProvider.future),
        throwsA(isA<DbNoDisponibleError>()),
      );

      expect(container.read(estadoBdProvider), EstadoBd.error);
    });

    test('lista cuando el proxy sí responde', () async {
      // El otro lado del chequeo: que `lista` sea alcanzable y no un estado
      // imposible. Si esto se rompe, la app queda trabada en la pantalla de
      // "no disponible" aunque el servidor esté perfecto.
      final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => proxy.close(force: true));
      unawaited(proxy.forEach((request) async {
        await request.drain<void>();
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'rows': [
              {'?column?': 1}
            ],
            'affectedRows': 0,
          }));
        await request.response.close();
      }));

      await DbConfig.save(
        DbConfig(
          host: '',
          port: 5432,
          database: '',
          user: '',
          password: '',
          proxyUrl: 'http://${proxy.address.host}:${proxy.port}',
          proxyToken: 'tok-abc',
          proxyUrlManual: true,
        ),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final session = await container.read(sesionVerificadaProvider.future);
      expect(session, isNotNull);
      expect(container.read(estadoBdProvider), EstadoBd.lista);
      expect(container.read(errorConexionBdProvider), isNull);
    });

    test('reintentar vuelve a comprobar la conexión', () async {
      // El botón "Reintentar" invalida el pool. Como el provider verificado es
      // su dependiente, tiene que volver a comprobar, no quedarse con el
      // fallo anterior para siempre.
      await DbConfig.save(
        const DbConfig(
          host: '',
          port: 5432,
          database: '',
          user: '',
          password: '',
          proxyUrl: 'http://127.0.0.1:1',
          proxyToken: 'tok-abc',
          proxyUrlManual: true,
        ),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await expectLater(
        container.read(sesionVerificadaProvider.future),
        throwsA(isA<DbNoDisponibleError>()),
      );
      expect(container.read(estadoBdProvider), EstadoBd.error);

      // Ahora el servidor responde en otro lado.
      final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => proxy.close(force: true));
      unawaited(proxy.forEach((request) async {
        await request.drain<void>();
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'rows': [], 'affectedRows': 0}));
        await request.response.close();
      }));
      await DbConfig.save(
        DbConfig(
          host: '',
          port: 5432,
          database: '',
          user: '',
          password: '',
          proxyUrl: 'http://${proxy.address.host}:${proxy.port}',
          proxyToken: 'tok-abc',
          proxyUrlManual: true,
        ),
      );
      container.invalidate(postgresPoolProvider);

      await container.read(sesionVerificadaProvider.future);
      expect(container.read(estadoBdProvider), EstadoBd.lista);
    });
  });
}