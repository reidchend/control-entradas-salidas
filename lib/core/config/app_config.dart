/// Configuración de la app, equivalente a `config/config.py` + `config/db_config.py`.
///
/// Fuente de valores:
/// - `--dart-define=DATABASE_URL=...` (connection string PostgreSQL).
///   (los define de compilación viajan en el bundle como `String.fromEnvironment`).
/// - Configuración guardada por el usuario en Ajustes → Base de datos
///   (tiene prioridad; ver `DbConfig`).
///
/// No hay fallback embebido: las credenciales no se versionan ni se
/// distribuyen dentro del binario.
class AppConfig {
  AppConfig._();

  /// Connection string PostgreSQL embebido al compilar, o vacío.
  ///
  /// Windows y Android conectan directo a PostgreSQL; en la instalacion de
  /// produccion apunta a la base local del servidor. Web usa el proxy
  /// `/proxy-sql` y no lee este valor.
  static String get databaseUrl =>
      const String.fromEnvironment('DATABASE_URL');

  /// Token del proxy embebido al compilar, o vacío.
  ///
  /// `tool/server.py` rechaza `/proxy-sql` sin token, así que el build web
  /// tiene que mandarlo:
  ///
  /// ```
  /// flutter build web --dart-define=PROXY_SQL_TOKEN=<token>
  /// ```
  ///
  /// En Windows y Android no se usa: el token se guarda en el almacen seguro
  /// del equipo desde Ajustes → Base de datos, para poder rotarlo sin
  /// recompilar.
  static String get proxyToken =>
      const String.fromEnvironment('PROXY_SQL_TOKEN');

  /// Gist donde `tool/iniciar_tunnel_api.js` publica la URL del túnel.
  ///
  /// La app lo lee al arrancar para no tener que escribir la URL en cada
  /// equipo: si el túnel cambia, alcanza con republicar. Solo contiene la URL
  /// (dato público), nunca el token.
  static String get gistId => const String.fromEnvironment('GIST_ID',
      defaultValue: '5b37693a243d8d2235eea0647396b8d3');

  /// Clave del token de GitHub, para cuando el Gist es privado.
  ///
  /// Vacío por defecto: el Gist es público y se lee sin autenticar. Rellenar
  /// solo si el Gist se hizo privado (un token de solo lectura).
  static String get gistToken =>
      const String.fromEnvironment('GIST_TOKEN');

  /// Archivo dentro del Gist con la URL de la API.
  static const String apiUrlFile = 'api_url.json';

  /// URL desde la que se consulta la dirección del servidor.
  ///
  /// Se usa la API de GitHub en vez de la URL "raw" porque no necesita el
  /// nombre de usuario del dueño del Gist: solo el ID, que ya está escrito en
  /// el repo.
  static Uri get apiUrlEndpoint =>
      Uri.https('api.github.com', '/gists/$gistId');

  /// Cabeceras para esa consulta. Vacío si el Gist es público.
  static Map<String, String> get apiUrlHeaders {
    final token = gistToken;
    return {
      'Accept': 'application/vnd.github+json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// URL del manifiesto de actualizaciones (`versions.json`).
  ///
  /// Contiene la versión vigente de **cada** app
  /// (`inventario`/`pos`/`hosteleria`) para que el updater solo avise a la app
  /// que realmente cambió. Ver `versions.json` en la raíz del repo.
  static String get updateUrl {
    const fromEnv = String.fromEnvironment('UPDATE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    return 'https://raw.githubusercontent.com/reidchend/control-entradas-salidas/main/versions.json';
  }

  /// Repo GitHub de las releases de la app (tag `<appId>-vX.Y.Z`).
  static String get updateRepo {
    const fromEnv = String.fromEnvironment('UPDATE_REPO');
    if (fromEnv.isNotEmpty) return fromEnv;
    return 'reidchend/control-entradas-salidas';
  }

  /// Identificador de la app en el updater: `pos`, `inventario` o `hosteleria`.
  /// inventario: Windows/Linux/Android; pos y hosteleria: Windows/Linux.
  static String get appId {
    const fromEnv = String.fromEnvironment('APP_ID');
    return fromEnv.isNotEmpty ? fromEnv : 'inventario';
  }

  /// Versión de **esta** app, sellada al compilar con
  /// `--dart-define=APP_VERSION=x.y.z` (la del `versions.json` de su entrada).
  ///
  /// Tiene prioridad sobre `PackageInfo.version` para que cada app siga su
  /// propio ciclo de release sin depender de la versión global de `pubspec`.
  /// Si está vacía (build sin el define), `AppUpdater` cae a `PackageInfo`.
  static String get appVersion =>
      const String.fromEnvironment('APP_VERSION');

  /// Etiqueta legible de la app (título del diálogo de actualización).
  static String get appLabel {
    const fromEnv = String.fromEnvironment('APP_LABEL');
    if (fromEnv.isNotEmpty) return fromEnv;
    return appId == 'pos' ? 'Lycoris POS' : 'Control de Entradas y Salidas';
  }

  /// Puerto web para desarrollo (FLET_WEB_PORT legacy = 8502).
  static String get webPort => const String.fromEnvironment('WEB_PORT',
      defaultValue: '8502');

  /// Intervalo del sync background en segundos (sync.py start_background_sync).
  /// Subido de 20s a 300s para no exceder la cuota de egress de Supabase.
  static const int syncIntervalSeconds = 300;
}