import 'package:postgres/postgres.dart';

import 'sql_session.dart';

/// Sesión SQL nativa sobre `package:postgres` (escritorio/móvil).
///
/// Envuelve un [SessionExecutor] (Pool o Connection). Para transacciones usa
/// `runTx`, que entrega un `TxSession` envuelto en otro [NativeSqlSession].
class NativeSqlSession implements SqlSession {
  NativeSqlSession(this._session);

  final Session _session;

  @override
  Future<SqlResult> execute(
    String sql, {
    List<Object?>? parameters,
  }) async {
    final result = await _session.execute(sql, parameters: parameters);
    return SqlResult(
      rows: result.map((row) => row.toColumnMap()).toList(),
      affectedRows: result.affectedRows,
    );
  }

  @override
  Future<T> runTx<T>(Future<T> Function(SqlSession tx) action) {
    if (_session is SessionExecutor) {
      return (_session as SessionExecutor).runTx((session) {
        return action(NativeSqlSession(session));
      });
    }
    throw StateError('runTx requiere un Pool o Connection');
  }
}