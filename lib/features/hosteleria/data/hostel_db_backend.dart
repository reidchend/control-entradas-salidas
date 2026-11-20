/// Interfaz de acceso a datos para el módulo Hostelería.
///
/// Permite usar el mismo `HosteleriaRepository` tanto con PostgreSQL
/// (producción) como con SQLite (pruebas locales sin tocar la BD real).
///
/// Los placeholders en SQL siguen el estilo PostgreSQL (`$1`, `$2`, …).
/// Cada backend es responsable de traducirlos a su sintaxis nativa
/// (Postgres los usa tal cual; SQLite los convierte a `?`).
abstract class HostelDbBackend {
  /// Ejecuta una consulta SELECT y devuelve las filas.
  Future<List<Map<String, dynamic>>> executeSql(
    String sql, {
    List<dynamic> params = const [],
  });

  /// Ejecuta un comando INSERT/UPDATE/DELETE y devuelve filas afectadas.
  Future<int> executeCommand(
    String sql, {
    List<dynamic> params = const [],
  });

  /// Inserta una fila y retorna el ID generado.
  Future<int> insert(String table, Map<String, dynamic> data);

  /// Actualiza una fila por ID.
  Future<void> updateById(String table, int id, Map<String, dynamic> data);

  /// Elimina una fila por ID.
  Future<void> deleteById(String table, int id);

  /// Lee una fila por ID.
  Future<Map<String, dynamic>?> fetchById(String table, int id);

  /// Lee filas de una tabla con filtros opcionales.
  Future<List<Map<String, dynamic>>> fetchAll(
    String table, {
    String? orderBy,
    bool ascending = true,
    int? limit,
    Map<String, dynamic>? filters,
    String? search,
    String? searchColumn,
  });

  /// Ejecuta [action] dentro de una transacción. [tx] es el mismo backend
  /// dentro de la transacción (para usar `tx.insert`, `tx.updateById`, etc.).
  Future<T> transaction<T>(Future<T> Function(HostelDbBackend tx) action);
}
