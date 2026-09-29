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

  /// URL del updater (equivalent a UPDATE_URL del .env).
  static String get updateUrl {
    const fromEnv = String.fromEnvironment('UPDATE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    return 'https://raw.githubusercontent.com/reidchend/control-entradas-salidas/main/version.json';
  }

  /// Repo GitHub de las releases de la app (`releases/latest`).
  static String get updateRepo {
    const fromEnv = String.fromEnvironment('UPDATE_REPO');
    if (fromEnv.isNotEmpty) return fromEnv;
    return 'reidchend/control-entradas-salidas';
  }

  /// Identificador de la app en el updater: `pos` o `inventario`.
  /// El POS se distribuye solo en Windows; el inventario en Windows y Android.
  static String get appId {
    const fromEnv = String.fromEnvironment('APP_ID');
    return fromEnv.isNotEmpty ? fromEnv : 'inventario';
  }

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