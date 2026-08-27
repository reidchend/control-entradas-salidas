/// Configuración de la app, equivalente a `config/config.py` + `config/db_config.py`.
///
/// Fuente de valores:
/// - `--dart-define=SUPABASE_URL=...`, `--dart-define=SUPABASE_ANON_KEY=...`
///   (los define de compilación viajan en el bundle como `String.fromEnvironment`).
/// - Fallback a constantes compiladas (como el `db_config.py` empaquetado).
///
/// El ref de Supabase se deriva de `DB_USER` = `postgres.<ref>` del .env actual
/// (`uyyyveojjvbxhuhbnype`). La anon key solo se inyecta en CI (GitHub Secrets),
/// de forma análoga al workflow build_apk.yml que sobreescribe db_config.py.
class AppConfig {
  AppConfig._();

  /// URL REST de la Neon Data API (PostgREST-compatible).
  /// Sustituye al proxy local: accesible desde cualquier dispositivo con
  /// internet, sin depender de una máquina local encendida.
  static String get supabaseUrl {
    const fromEnv = String.fromEnvironment('SUPABASE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    return 'https://ep-fragrant-thunder-ayji1cvq.apirest.c-5.us-east-2.aws.neon.tech/neondb';
  }

  /// JWT firmado (role `authenticated`) que la app inyecta como
  /// `apikey` + `Authorization: Bearer <token>`. La Neon Data API valida
  /// este token contra el JWKS servido por una Neon Function.
  static String get supabaseAnonKey {
    const fromEnv = String.fromEnvironment('SUPABASE_ANON_KEY');
    if (fromEnv.isNotEmpty) return fromEnv;
    return dotenvJwt;
  }

  /// JWT de aplicación (firmado offline con clave privada propia).
  /// No va en el APK compilado público por defecto; se inyecta con
  /// `--dart-define=SUPABASE_ANON_KEY=...` en CI/releases.
  static const String dotenvJwt = 'eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6ImNjel9VdERDNmNS'
      'MlJGUFRtbmQ5WWR3ZktxZjdSOGpsaVR6b3RJWUdBa3cifQ.eyJyb2xlIjoiY'
      'XV0aGVudGljYXRlZCIsInN1YiI6Imx5Y29yaXMtYXBwIiwiaWF0IjoxNzg3O'
      'DQ1NjMwLCJleHAiOjIxMDMyMDU2MzB9.jEM3e_fvimuG2pPcw-61HB7rHIyN'
      'AFOgu8t0afszNGqfaQYFH7DBOGM9zPrZYBk-GV6skIzB8go47nS7l69wvUK3'
      'OLNMlcj6iG5UUmlFyIiEDMltR-vRT49se7IlsCZehb9Rdgq8011BLMOIdl8K'
      'C1QZVtU9rQPAtCVJ_xt9NWkWLjXi5RizAdZYV68FmEU2OWWTJgbCMutki8bR'
      'PJpj9o6h7c7ksOAGFA8n23PonJeFkNCEmyWuV0KH9jm6Hmm0YG4VPMyOMInt'
      'NlFT7A_5Gbn7URDUV8b1zOywkUb2PpRyvtz6ZRItsHUD-I_Lp1YsOM7RZufS'
      'KbfmfkDuI9-GcV-jTnxZQyYE2unz77XgudkmbWcEn26iiZmZbjj5byAXCAUI'
      '4FF476r_41GcPsbivZYuexlnwfWokExcPIJWXJCd5702Ixtf2Woz2ynhv7io'
      'Zm4NESutttKjYrYOy5DPfbuf_jYyU5pIhI--PEt63Fi22od-MO-1WnVFD1aj'
      'HCTI55g2EtuPUN7uOf3Ax8cHyweVL5RhEkJWWcm3x1mPrsn7yv31Tp-cP3TW'
      'c9hwKH6uCQnw_g-3zSqJdlGeenT8QI6kJPa9Cz-LZ3kUkqsjPqOypQ0l_C_V'
      'jFJh443xo1zdJChp6M7MRHoQhFK2C_yr3aZEslsoSVlkJ4zC2OEOkBk';

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

  static bool get hasSupabaseKey => supabaseAnonKey.isNotEmpty;
}