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
}) =>
    DbConfig(
      host: host,
      port: port,
      database: database,
      user: user,
      password: password,
      ssl: ssl,
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
}
