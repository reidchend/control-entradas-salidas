import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:postgres/postgres.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Error de almacenamiento de la configuracion, con un mensaje apto para
/// mostrar en la interfaz.
class DbConfigStorageError implements Exception {
  const DbConfigStorageError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Configuracion de conexion a PostgreSQL editable en runtime.
///
/// Permite cambiar host, puerto, usuario y base sin recompilar la app.
///
/// Donde se guarda cada campo:
/// - host, puerto, base, usuario y ssl van a SharedPreferences: no son
///   secretos y no importa que queden en texto plano.
/// - **la contraseña va a `flutter_secure_storage`** (keychain en Android,
///   DPAPI en Windows). SharedPreferences es un archivo legible y no es lugar
///   para una clave de base de datos.
///
/// Orden de precedencia de la URL:
/// 1. Valores guardados por el usuario (este store).
/// 2. `--dart-define=DATABASE_URL=...` embebido al compilar.
/// 3. Sin configurar -> la app avisa y no intenta conectar.
///
/// La app se conecta directo a PostgreSQL (sin proxy) en Windows y Android,
/// asi que en esos equipos es obligatorio apuntar a la base del servidor. En
/// web la conexion va por el proxy `/proxy-sql` y esta configuracion no aplica.
class DbConfig {
  const DbConfig({
    required this.host,
    required this.port,
    required this.database,
    required this.user,
    required this.password,
    this.ssl = false,
  });

  final String host;
  final int port;
  final String database;
  final String user;
  final String password;

  /// `ssl` activa `sslmode=require`. En la base local sobre Tailscale el
  /// trafico ya va cifrado, asi que lo normal es dejarlo en false.
  final bool ssl;

  // Claves de SharedPreferences (solo datos no sensibles).
  static const _kHost = 'db_config_host';
  static const _kPort = 'db_config_port';
  static const _kDatabase = 'db_config_database';
  static const _kUser = 'db_config_user';
  static const _kSsl = 'db_config_ssl';

  /// Clave en el almacen seguro.
  static const _kPassword = 'db_config_password';

  static const _storage = FlutterSecureStorage();

  /// Connection string equivalente a la configuracion actual.
  ///
  /// La contraseña y el usuario se codifican porque pueden llevar
  /// caracteres especiales (`@`, `:`, `/`) que romperian el parser de URI.
  String toUrl() {
    final u = Uri.encodeComponent(user);
    final p = Uri.encodeComponent(password);
    final sslmode = ssl ? 'require' : 'disable';
    return 'postgresql://$u:$p@$host:$port/$database?sslmode=$sslmode';
  }

  bool get isComplete =>
      host.isNotEmpty && database.isNotEmpty && user.isNotEmpty;

  /// Abre una conexión de prueba y la cierra.
  ///
  /// Lanza [Exception] con el mensaje del driver si no se puede conectar
  /// (host inalcanzable, credenciales incorrectas, base inexistente…).
  /// No deja conexiones abiertas.
  Future<void> test() async {
    final conn = await Connection.open(
      Endpoint(
        host: host,
        database: database,
        username: user,
        password: password,
        port: port,
      ),
      settings: ConnectionSettings(
        sslMode: ssl ? SslMode.require : SslMode.disable,
        // Falla rápido: si la base está caída no colgamos la interfaz.
        connectTimeout: const Duration(seconds: 8),
      ),
    );
    await conn.close();
  }

  DbConfig copyWith({
    String? host,
    int? port,
    String? database,
    String? user,
    String? password,
    bool? ssl,
  }) =>
      DbConfig(
        host: host ?? this.host,
        port: port ?? this.port,
        database: database ?? this.database,
        user: user ?? this.user,
        password: password ?? this.password,
        ssl: ssl ?? this.ssl,
      );

  /// Lee la configuracion guardada. Devuelve `null` si el usuario nunca la
  /// setteo, para que el llamador use el `dart-define` como fallback.
  static Future<DbConfig?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString(_kHost);
    if (host == null || host.isEmpty) return null;
    return DbConfig(
      host: host,
      port: prefs.getInt(_kPort) ?? 5432,
      database: prefs.getString(_kDatabase) ?? '',
      user: prefs.getString(_kUser) ?? '',
      password: await _readPassword(),
      ssl: prefs.getBool(_kSsl) ?? false,
    );
  }

  static Future<void> save(DbConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHost, config.host);
    await prefs.setInt(_kPort, config.port);
    await prefs.setString(_kDatabase, config.database);
    await prefs.setString(_kUser, config.user);
    await prefs.setBool(_kSsl, config.ssl);
    await _writePassword(config.password);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kHost);
    await prefs.remove(_kPort);
    await prefs.remove(_kDatabase);
    await prefs.remove(_kUser);
    await prefs.remove(_kSsl);
    await _deletePassword();
  }

  static Future<String> _readPassword() async {
    try {
      return await _storage.read(key: _kPassword) ?? '';
    } catch (e) {
      throw DbConfigStorageError(
        'No se pudo leer la contraseña del almacén seguro: $e',
      );
    }
  }

  static Future<void> _writePassword(String password) async {
    try {
      await _storage.write(key: _kPassword, value: password);
    } catch (e) {
      // A propósito NO cae de vuelta a SharedPreferences: guardar la clave en
      // texto plano para "que funcione" es peor que fallar con un mensaje.
      throw DbConfigStorageError(
        'No se pudo guardar la contraseña de forma segura. '
        'Verificá que el almacén seguro del sistema esté disponible. ($e)',
      );
    }
  }

  static Future<void> _deletePassword() async {
    try {
      await _storage.delete(key: _kPassword);
    } catch (e) {
      throw DbConfigStorageError('No se pudo borrar la contraseña: $e');
    }
  }
}
