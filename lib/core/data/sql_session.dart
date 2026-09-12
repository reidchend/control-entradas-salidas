/// Resultado de una consulta SQL, independiente del driver.
class SqlResult {
  const SqlResult({required this.rows, required this.affectedRows});

  final List<Map<String, dynamic>> rows;
  final int affectedRows;

  bool get isEmpty => rows.isEmpty;
}

/// Sesión de base de datos abstracta.
///
/// En desktop/mobile la implementa [NativeSqlSession] sobre `package:postgres`
/// (pool TCP directo). En web usa [HttpSqlSession], que delega en el proxy
/// `/proxy-sql` del servidor (el driver nativo usa `dart:io`, inexistente en
/// Flutter web).
abstract class SqlSession {
  /// Ejecuta una query y devuelve filas + filas afectadas.
  Future<SqlResult> execute(String sql, {List<Object?>? parameters});

  /// Ejecuta [action] dentro de una transacción. Si lanza, se hace rollback.
  Future<T> runTx<T>(Future<T> Function(SqlSession tx) action);
}