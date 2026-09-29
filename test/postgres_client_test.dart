import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:control_entradas_salidas/core/config/db_config.dart';
import 'package:control_entradas_salidas/core/network/postgres_client.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

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
  });
}
