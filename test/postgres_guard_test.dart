import 'package:control_entradas_salidas/core/config/db_config.dart';
import 'package:control_entradas_salidas/core/data/postgres_guard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:control_entradas_salidas/core/network/postgres_client.dart';

/// Cubre el bloqueo del primer arranque.
///
/// El login lee los cajeros de la base, y la base se configuraba en un panel
/// que estaba detrás del login. Con la base sin configurar, `postgresPoolProvider`
/// falla con [DbNotConfiguredError] y los repositorios devuelven `null`; el
/// estado tiene que quedar distinguible para que la UI ofrezca configurar en vez
/// de romper.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('estadoBdProvider', () {
    test('noConfigurada cuando no hay nada guardado', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Se espera el error del pool: sin configuración no hay a qué conectar.
      await expectLater(
        container.read(postgresPoolProvider.future),
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
        container.read(postgresPoolProvider.future),
        throwsA(isA<DbNotConfiguredError>()),
      );

      expect(container.read(estadoBdProvider), EstadoBd.noConfigurada);
    });

    test('conectando mientras el pool todavía no resolvió', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Sin esperar el future: el provider está en vuelo.
      expect(container.read(estadoBdProvider), EstadoBd.conectando);
    });

    test('lista con config completa, aunque el host no responda', () async {
      // `Pool.withUrl` es perezoso: crea el pool sin abrir el socket, así que
      // un host caído no hace fallar el provider. El error real aparece en la
      // primera query, que es la rama `error` del login.
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

      final session = await container.read(postgresPoolProvider.future);
      expect(session, isNotNull);
      expect(container.read(estadoBdProvider), EstadoBd.lista);
      expect(container.read(errorConexionBdProvider), isNull);
    });
  });
}
