import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
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

/// La app todavía no sabe a qué base conectarse.
///
/// Es distinto de "la base está caída": este error significa que el usuario
/// tiene que abrir Configuración → Base de datos y llenar los datos. La UI
/// lo trata mostrando el acceso directo a esa pantalla, en vez de un error
/// técnico.
class DbNotConfiguredError implements Exception {
  const DbNotConfiguredError([
    this.detalle = 'Base de datos no configurada.',
  ]);

  final String detalle;

  @override
  String toString() => detalle;
}

/// La base está configurada pero el servidor no responde.
///
/// Distinto de [DbNotConfiguredError]: acá no falta nada por completar, hay que
/// esperar a que la PC servidor vuelva (o revisar el túnel y el token). La UI
/// lo trata mostrando "Reintentar" en vez de un error técnico.
class DbNoDisponibleError implements Exception {
  const DbNoDisponibleError([
    this.detalle = 'El servidor de base de datos no respondió.',
  ]);

  final String detalle;

  @override
  String toString() => detalle;
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
    this.proxyUrl = '',
    this.proxyToken = '',
    this.proxyUrlManual = false,
  });

  final String host;
  final int port;
  final String database;
  final String user;
  final String password;

  /// `ssl` activa `sslmode=require`. En la base local sobre Tailscale el
  /// trafico ya va cifrado, asi que lo normal es dejarlo en false.
  final bool ssl;

  /// URL base del proxy HTTP (`https://host`). Vacio = conexion TCP directa
  /// a PostgreSQL, que es lo que usa el driver nativo.
  ///
  /// Con proxy no hace falta abrir el 5432 ni instalar Tailscale en el
  /// equipo: la app habla HTTPS con `tool/server.py` y este habla con la
  /// base. A cambio, cada query es un viaje HTTP en vez de una instruccion
  /// sobre la conexion ya abierta.
  final String proxyUrl;

  /// Token que valida `tool/server.py` en cada request a `/proxy-sql`.
  /// Sin esto el proxy responde 401.
  final String proxyToken;

  /// El usuario escribió la URL a mano en vez de que la trajera el Gist.
  ///
  /// Mientras sea falso, la app relee la URL del Gist en cada arranque, que es
  /// lo que hace que el túnel pueda cambiar sin tocar los equipos. Con el
  /// túnel rápido la URL cambia cada vez que se reinicia la PC servidor, así
  /// que aferrarse a la guardada deja la app apuntando a un túnel muerto.
  ///
  /// Es la salida para cuando el Gist no se puede usar (túnel propio, URL
  /// estable, TestingLab): ahí la URL es estable y no hay nada que actualizar.
  final bool proxyUrlManual;

  /// ¿Usa el proxy HTTP en vez del driver nativo?
  ///
  /// Basta con tener el token. La URL no hace falta: se descubre sola desde el
  /// Gist al arrancar. Exigir la URL hacía que el flujo previsto (escribir solo
  /// el token) no activara el modo proxy, y la app caía en el driver nativo.
  ///
  /// Es seguro confundir "tiene token" con "quiere proxy" porque [save]
  /// reemplaza la configuración entera: al guardar en modo TCP directo el
  /// token queda vacío, así que un perfil TCP nunca queda pegado en proxy.
  bool get usesProxy =>
      proxyToken.trim().isNotEmpty || proxyUrl.trim().isNotEmpty;

  // Claves de SharedPreferences (solo datos no sensibles).
  static const _kHost = 'db_config_host';
  static const _kPort = 'db_config_port';
  static const _kDatabase = 'db_config_database';
  static const _kUser = 'db_config_user';
  static const _kSsl = 'db_config_ssl';
  static const _kProxyUrl = 'db_config_proxy_url';
  static const _kProxyUrlManual = 'db_config_proxy_url_manual';

  /// Claves en el almacen seguro.
  static const _kPassword = 'db_config_password';
  static const _kProxyToken = 'db_config_proxy_token';

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

  /// Endpoint de `/proxy-sql` a partir de una URL base.
  ///
  /// Vive acá y no en la clase para que el resto del código pueda armarlo sin
  /// tener que construir un [DbConfig] entero: la URL efectiva la resuelve el
  /// descubridor, no viene guardada.
  ///
  /// Acepta `https://host`, `https://host/` y `https://host/loquesea`; siempre
  /// resuelve contra la raiz para no duplicar la ruta si el usuario copio la
  /// URL del navegador con un sufijo.
  static Uri endpointDe(String baseUrl) {
    final base = baseUrl.trim();
    final normalized = base.endsWith('/') ? base : '$base/';
    return Uri.parse(normalized).resolve('/proxy-sql');
  }

  /// Endpoint de `/proxy-sql` a partir de [proxyUrl].
  Uri get proxyEndpoint => endpointDe(proxyUrl);

  bool get isComplete {
    if (usesProxy) return true;
    return host.isNotEmpty && database.isNotEmpty && user.isNotEmpty;
  }

  /// Abre una conexión de prueba y la cierra.
  ///
  /// Lanza [Exception] con el mensaje del driver si no se puede conectar
  /// (host inalcanzable, credenciales incorrectas, base inexistente…).
  /// No deja conexiones abiertas.
  Future<void> test() async {
    if (usesProxy) {
      await testProxy();
      return;
    }
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

  /// Prueba el proxy HTTP con la misma consulta que usaría la app.
  ///
  /// Un `SELECT 1` verifica las tres capas de una: que la URL responde, que el
  /// token es aceptado y que el proxy alcanza la base.
  Future<void> testProxy() async {
    final uri = proxyEndpoint;
    final res = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            if (proxyToken.isNotEmpty) 'X-Proxy-Token': proxyToken,
          },
          body: jsonEncode({'action': 'execute', 'sql': 'SELECT 1'}),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 401) {
      throw StateError('Token inválido o ausente. Revisá el token del proxy.');
    }
    if (res.statusCode >= 400) {
      String detalle = res.body;
      try {
        detalle = (jsonDecode(res.body) as Map)['error']?.toString() ?? res.body;
      } catch (_) {
        // Respuesta no-JSON: se muestra tal cual.
      }
      throw StateError('Proxy respondió ${res.statusCode}: $detalle');
    }
  }

  DbConfig copyWith({
    String? host,
    int? port,
    String? database,
    String? user,
    String? password,
    bool? ssl,
    String? proxyUrl,
    String? proxyToken,
    bool? proxyUrlManual,
  }) =>
      DbConfig(
        host: host ?? this.host,
        port: port ?? this.port,
        database: database ?? this.database,
        user: user ?? this.user,
        password: password ?? this.password,
        ssl: ssl ?? this.ssl,
        proxyUrl: proxyUrl ?? this.proxyUrl,
        proxyToken: proxyToken ?? this.proxyToken,
        proxyUrlManual: proxyUrlManual ?? this.proxyUrlManual,
      );

  /// Lee la configuracion guardada. Devuelve `null` si el usuario nunca la
  /// setteo, para que el llamador use el `dart-define` como fallback.
  static Future<DbConfig?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString(_kHost) ?? '';
    final proxyUrl = prefs.getString(_kProxyUrl) ?? '';
    final proxyToken = await _readProxyToken();
    // Con proxy basta el token: la URL se descubre sola del Gist y todavia no
    // esta guardada. Antes el criterio era host o URL, asi que una config con
    // solo token se daba por inexistente y el usuario perdia su configuracion.
    if (host.isEmpty && proxyUrl.isEmpty && proxyToken.isEmpty) return null;
    return DbConfig(
      host: host,
      port: prefs.getInt(_kPort) ?? 5432,
      database: prefs.getString(_kDatabase) ?? '',
      user: prefs.getString(_kUser) ?? '',
      password: await _readPassword(),
      ssl: prefs.getBool(_kSsl) ?? false,
      proxyUrl: proxyUrl,
      proxyToken: proxyToken,
      proxyUrlManual: prefs.getBool(_kProxyUrlManual) ?? false,
    );
  }

  static Future<void> save(DbConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHost, config.host);
    await prefs.setInt(_kPort, config.port);
    await prefs.setString(_kDatabase, config.database);
    await prefs.setString(_kUser, config.user);
    await prefs.setBool(_kSsl, config.ssl);
    await prefs.setString(_kProxyUrl, config.proxyUrl);
    await prefs.setBool(_kProxyUrlManual, config.proxyUrlManual);
    await _writePassword(config.password);
    await _writeProxyToken(config.proxyToken);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kHost);
    await prefs.remove(_kPort);
    await prefs.remove(_kDatabase);
    await prefs.remove(_kUser);
    await prefs.remove(_kSsl);
    await prefs.remove(_kProxyUrl);
    await prefs.remove(_kProxyUrlManual);
    await _deletePassword();
    await _deleteProxyToken();
  }

  static Future<String> _readProxyToken() async {
    try {
      return await _storage.read(key: _kProxyToken) ?? '';
    } catch (e) {
      throw DbConfigStorageError(
        'No se pudo leer el token del proxy del almacén seguro: $e',
      );
    }
  }

  static Future<void> _writeProxyToken(String token) async {
    try {
      await _storage.write(key: _kProxyToken, value: token);
    } catch (e) {
      throw DbConfigStorageError(
        'No se pudo guardar el token del proxy de forma segura. '
        'Verificá que el almacén seguro del sistema esté disponible. ($e)',
      );
    }
  }

  static Future<void> _deleteProxyToken() async {
    try {
      await _storage.delete(key: _kProxyToken);
    } catch (_) {
      // Borrar un token que no está no es un error que valga la pena mostrar.
    }
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
