/// Adaptador de `PostgresService` a `HostelDbBackend`.
///
/// Permite usar `HosteleriaRepository` con PostgreSQL en producción sin
/// modificar sus queries SQL (siguen usando `$1`, `$2`, …).
library;

import 'package:control_entradas_salidas/core/data/postgres_service.dart';

import 'hostel_db_backend.dart';

class PostgresDbBackend implements HostelDbBackend {
  PostgresDbBackend(this._pg);

  final PostgresService _pg;

  @override
  Future<List<Map<String, dynamic>>> executeSql(
    String sql, {
    List<dynamic> params = const [],
  }) async {
    return _pg.executeSql(sql, params: params);
  }

  @override
  Future<int> executeCommand(
    String sql, {
    List<dynamic> params = const [],
  }) async {
    return _pg.executeCommand(sql, params: params);
  }

  @override
  Future<int> insert(String table, Map<String, dynamic> data) async {
    return _pg.insert(table, data);
  }

  @override
  Future<void> updateById(
    String table,
    int id,
    Map<String, dynamic> data,
  ) async {
    return _pg.updateById(table, id, data);
  }

  @override
  Future<void> deleteById(String table, int id) async {
    return _pg.deleteById(table, id);
  }

  @override
  Future<Map<String, dynamic>?> fetchById(String table, int id) async {
    return _pg.fetchById(table, id);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchAll(
    String table, {
    String? orderBy,
    bool ascending = true,
    int? limit,
    Map<String, dynamic>? filters,
    String? search,
    String? searchColumn,
  }) async {
    return _pg.fetchAll(
      table,
      orderBy: orderBy,
      ascending: ascending,
      limit: limit,
      filters: filters,
      search: search,
      searchColumn: searchColumn,
    );
  }

  @override
  Future<T> transaction<T>(Future<T> Function(HostelDbBackend tx) action) {
    return _pg.transaction((pgTx) {
      final backend = PostgresDbBackend(pgTx);
      return action(backend);
    });
  }
}
