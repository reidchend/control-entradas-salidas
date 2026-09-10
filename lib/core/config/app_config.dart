/// Configuración de la app, equivalente a `config/config.py` + `config/db_config.py`.
///
/// Fuente de valores:
/// - `--dart-define=DATABASE_URL=...` (connection string PostgreSQL con pooler)
///   (los define de compilación viajan en el bundle como `String.fromEnvironment`).
/// - Fallback a constante compilada (development).
class AppConfig {
  AppConfig._();

  /// Connection string PostgreSQL (pooler Neon) para conexión directa.
  /// Formato: postgresql://user:pass@host/db?sslmode=require&channel_binding=require
  static String get databaseUrl {
    const fromEnv = String.fromEnvironment('DATABASE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    return 'postgresql://neondb_owner:npg_hzl8u2rOLMQe@ep-fragrant-thunder-ayji1cvq-pooler.c-5.us-east-2.aws.neon.tech/neondb?sslmode=require&channel_binding=require';
  }

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

  static bool get hasDatabaseUrl => databaseUrl.isNotEmpty;
}