import 'dart:async';

import 'pg_client.dart';
import 'sql_session.dart';

/// Servicio base para operaciones CRUD contra PostgreSQL directo (pooler Neon).
///
/// Provee métodos genéricos para select, insert, update, delete, upsert.
/// Los repositorios de cada feature usan este servicio o acceden a la
/// conexión raw para queries complejas.
class PostgresService {
  PostgresService(this._session);

  /// Sesión base: puede ser una sesión directa o una de transacción obtenida
  /// con `runTx`. En escritorio usa el pool nativo; en web el proxy HTTP.
  final SqlSession _session;

  /// Alias de compatibilidad: fachada con sintaxis `.from().select().eq()...`
  /// (estilo PostgREST) que los repositorios ya usan.
  PgClient get client => PgClient(_session);

  /// Cache de columnas boolean por tabla (consultado una sola vez).
  static final Map<String, Set<String>> _boolColsCache = {};

  /// Tipos reales (boolean vs integer) de `activo` y flags por tabla.
  /// Se resuelve desde `information_schema` la primera vez por tabla.
  Future<bool> _esBool(String table, String col) async {
    Set<String> bools;
    final cached = _boolColsCache[table];
    if (cached != null) {
      bools = cached;
    } else {
      final res = await _session.execute(
        "SELECT column_name FROM information_schema.columns "
        "WHERE table_name = \$1 AND (data_type = 'boolean')",
        parameters: [table],
      );
      bools = {for (final r in res.rows) '${r['column_name']}'};
      _boolColsCache[table] = bools;
    }
    return bools.contains(col);
  }

  /// Normaliza un valor según el tipo real de la columna (bool vs int).
  Future<dynamic> _normalizedValue(
    String table,
    String col,
    dynamic v,
  ) async {
    if (await _esBool(table, col)) {
      return v is bool ? v : (v == 1 || v == true);
    }
    return v is bool ? (v ? 1 : 0) : v;
  }

  /// Normaliza un map según el tipo real de cada columna de [table]:
  /// - columnas boolean: los int 1/0 pasan como bool (true/false).
  /// - columnas no boolean: los bool pasan como 1/0.
  Future<Map<String, dynamic>> _normalizedMap(
    String table,
    Map<String, dynamic> data,
  ) async {
    final out = <String, dynamic>{};
    for (final e in data.entries) {
      final v = e.value;
      if (await _esBool(table, e.key)) {
        out[e.key] = v is bool ? v : (v == 1 || v == true);
      } else {
        out[e.key] = v is bool ? (v ? 1 : 0) : v;
      }
    }
    return out;
  }

  /// Ejecuta una query y retorna lista de maps.
  Future<List<Map<String, dynamic>>> _query(
    String sql,
    List<dynamic> params,
  ) async {
    final result = await _session.execute(sql, parameters: params);
    return result.rows;
  }

  /// Ejecuta una query y retorna una sola fila (o null).
  Future<Map<String, dynamic>?> _queryOne(
    String sql,
    List<dynamic> params,
  ) async {
    final result = await _session.execute(sql, parameters: params);
    if (result.rows.isEmpty) return null;
    return result.rows.first;
  }

  /// Ejecuta un comando (INSERT/UPDATE/DELETE) y retorna filas afectadas.
  Future<int> _execute(String sql, List<dynamic> params) async {
    final result = await _session.execute(sql, parameters: params);
    return result.affectedRows;
  }

  // -------------------------------------------------------------------
  // SELECT
  // -------------------------------------------------------------------

  /// Lee todas las filas de una tabla.
  Future<List<Map<String, dynamic>>> fetchAll(
    String table, {
    String? orderBy,
    bool ascending = true,
    int? limit,
    Map<String, dynamic>? filters,
    String? search,
    String? searchColumn,
  }) async {
    final buffer = StringBuffer('SELECT * FROM $table');
    final params = <dynamic>[];
    var paramIndex = 1;

    final filterList = [
      ...(filters?.entries ?? const <MapEntry<String, dynamic>>[])
    ];
    if (search != null && search.isNotEmpty && searchColumn != null) {
      filterList.add(MapEntry(searchColumn, '%${search.toLowerCase()}%'));
    }

    if (filterList.isNotEmpty) {
      buffer.write(' WHERE ');
      var first = true;
      for (final e in filterList) {
        if (!first) buffer.write(' AND ');
        first = false;
        final esLike = searchColumn != null && e.key == searchColumn;
        final v =
            esLike ? e.value : await _normalizedValue(table, e.key, e.value);
        buffer.write('${e.key} ${esLike ? 'ILIKE' : '='} \$$paramIndex');
        params.add(v);
        paramIndex++;
      }
    }

    if (orderBy != null) {
      buffer.write(' ORDER BY $orderBy ${ascending ? 'ASC' : 'DESC'}');
    }
    if (limit != null) {
      buffer.write(' LIMIT $limit');
    }

    return _query(buffer.toString(), params);
  }

  /// Lee filas con filtro `gte` (>=) en una columna.
  Future<List<Map<String, dynamic>>> fetchWhereGte(
    String table,
    String column,
    String value, {
    String? orderBy,
    bool ascending = true,
  }) async {
    final buffer = StringBuffer('SELECT * FROM $table WHERE $column >= \$1');
    final params = [value];
    if (orderBy != null) {
      buffer.write(' ORDER BY $orderBy ${ascending ? 'ASC' : 'DESC'}');
    }
    return _query(buffer.toString(), params);
  }

  /// Lee filas con filtro `or` (complejo) - usa SQL OR.
  Future<List<Map<String, dynamic>>> fetchWhereOr(
    String table,
    String orFilter, {
    String? orderBy,
    bool ascending = true,
  }) async {
    // orFilter viene como "col1.eq.val1,col2.eq.val2" (formato PostgREST)
    // Lo convertimos a SQL WHERE (col1 = val1 OR col2 = val2)
    final buffer = StringBuffer('SELECT * FROM $table WHERE ');
    final params = <dynamic>[];
    var paramIndex = 1;

    final parts = orFilter.split(',');
    var first = true;
    for (final part in parts) {
      if (!first) buffer.write(' OR ');
      first = false;
      // Parse "col.eq.val" o "col.neq.val", etc.
      final match =
          RegExp(r'^(\w+)\.(eq|neq|gt|gte|lt|lte)\.(.+)$').firstMatch(part);
      if (match != null) {
        final col = match.group(1)!;
        final op = match.group(2)!;
        final val = match.group(3)!;
        final sqlOp = switch (op) {
          'eq' => '=',
          'neq' => '!=',
          'gt' => '>',
          'gte' => '>=',
          'lt' => '<',
          'lte' => '<=',
          _ => '=',
        };
        buffer.write('$col $sqlOp \$$paramIndex');
        params.add(val);
        paramIndex++;
      }
    }

    if (orderBy != null) {
      buffer.write(' ORDER BY $orderBy ${ascending ? 'ASC' : 'DESC'}');
    }
    return _query(buffer.toString(), params);
  }

  /// Lee una fila por ID.
  Future<Map<String, dynamic>?> fetchById(String table, int id) async {
    return _queryOne('SELECT * FROM $table WHERE id = \$1', [id]);
  }

  /// Lee una fila por un campo arbitrario.
  Future<Map<String, dynamic>?> fetchByField(
    String table,
    String field,
    dynamic value,
  ) async {
    return _queryOne('SELECT * FROM $table WHERE $field = \$1',
        [await _normalizedValue(table, field, value)]);
  }

  /// Lee una fila con filtro compuesto (dos campos).
  Future<Map<String, dynamic>?> fetchByTwoFields(
    String table,
    String field1,
    dynamic value1,
    String field2,
    dynamic value2,
  ) async {
    return _queryOne(
      'SELECT * FROM $table WHERE $field1 = \$1 AND $field2 = \$2',
      [
        await _normalizedValue(table, field1, value1),
        await _normalizedValue(table, field2, value2),
      ],
    );
  }

  /// Cuenta filas que cumplen un filtro.
  Future<int> count(String table, {Map<String, dynamic>? filters}) async {
    final buffer = StringBuffer('SELECT COUNT(*) FROM $table');
    final params = <dynamic>[];
    var paramIndex = 1;

    if (filters != null && filters.isNotEmpty) {
      buffer.write(' WHERE ');
      var first = true;
      for (final e in filters.entries) {
        if (!first) buffer.write(' AND ');
        first = false;
        final v = await _normalizedValue(table, e.key, e.value);
        buffer.write('${e.key} = \$$paramIndex');
        params.add(v);
        paramIndex++;
      }
    }

    final result =
        await _session.execute(buffer.toString(), parameters: params);
    return (result.rows.first['count'] as num).toInt();
  }

  // -------------------------------------------------------------------
  // INSERT
  // -------------------------------------------------------------------

  /// Inserta una fila y retorna el ID asignado por el server.
  Future<int> insert(String table, Map<String, dynamic> data) async {
    final encoded = await _normalizedMap(table, data);
    final columns = encoded.keys.join(', ');
    final placeholders =
        List.generate(encoded.length, (i) => '\$${i + 1}').join(', ');
    final params = encoded.values.toList();

    final sql =
        'INSERT INTO $table ($columns) VALUES ($placeholders) RETURNING id';
    final result = await _session.execute(sql, parameters: params);
    return (result.rows.first['id'] as num).toInt();
  }

  /// Inserta múltiples filas en lote.
  Future<void> insertBatch(
    String table,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return;
    final encoded = <Map<String, dynamic>>[];
    for (final row in rows) {
      encoded.add(await _normalizedMap(table, row));
    }
    final columns = encoded.first.keys.join(', ');

    final buffer = StringBuffer('INSERT INTO $table ($columns) VALUES ');
    final allParams = <dynamic>[];
    var paramIndex = 1;

    for (var i = 0; i < encoded.length; i++) {
      if (i > 0) buffer.write(', ');
      buffer.write('(');
      var first = true;
      for (final v in encoded[i].values) {
        if (!first) buffer.write(', ');
        first = false;
        buffer.write('\$$paramIndex');
        allParams.add(v);
        paramIndex++;
      }
      buffer.write(')');
    }

    await _session.execute(buffer.toString(), parameters: allParams);
  }

  // -------------------------------------------------------------------
  // UPDATE
  // -------------------------------------------------------------------

  /// Actualiza una fila por ID.
  Future<void> updateById(
    String table,
    int id,
    Map<String, dynamic> data,
  ) async {
    final encoded = await _normalizedMap(table, data);
    final buffer = StringBuffer('UPDATE $table SET ');
    final params = <dynamic>[];
    var paramIndex = 1;
    var first = true;

    for (final e in encoded.entries) {
      if (!first) buffer.write(', ');
      first = false;
      buffer.write('${e.key} = \$$paramIndex');
      params.add(e.value);
      paramIndex++;
    }
    buffer.write(' WHERE id = \$$paramIndex');
    params.add(id);

    await _session.execute(buffer.toString(), parameters: params);
  }

  /// Actualiza filas por filtro.
  Future<void> updateWhere(
    String table,
    Map<String, dynamic> filters,
    Map<String, dynamic> data,
  ) async {
    final encoded = await _normalizedMap(table, data);
    final buffer = StringBuffer('UPDATE $table SET ');
    final params = <dynamic>[];
    var paramIndex = 1;
    var first = true;

    for (final e in encoded.entries) {
      if (!first) buffer.write(', ');
      first = false;
      buffer.write('${e.key} = \$$paramIndex');
      params.add(e.value);
      paramIndex++;
    }

    buffer.write(' WHERE ');
    first = true;
    for (final e in filters.entries) {
      if (!first) buffer.write(' AND ');
      first = false;
      final v = await _normalizedValue(table, e.key, e.value);
      buffer.write('${e.key} = \$$paramIndex');
      params.add(v);
      paramIndex++;
    }

    await _session.execute(buffer.toString(), parameters: params);
  }

  // -------------------------------------------------------------------
  // UPSERT
  // -------------------------------------------------------------------

  /// Upsert por conflicto en una columna natural (ej: `nombre`, `codigo`).
  Future<int> upsert(
    String table,
    Map<String, dynamic> data, {
    required String conflictColumn,
  }) async {
    final encoded = await _normalizedMap(table, data);
    final columns = encoded.keys.join(', ');
    final placeholders =
        List.generate(encoded.length, (i) => '\$${i + 1}').join(', ');
    final updates = encoded.keys
        .where((k) => k != 'id')
        .map((k) => '$k = EXCLUDED.$k')
        .join(', ');
    final params = encoded.values.toList();

    final sql = '''
      INSERT INTO $table ($columns) VALUES ($placeholders)
      ON CONFLICT ($conflictColumn) DO UPDATE SET $updates
      RETURNING id
    ''';

    final result = await _session.execute(sql, parameters: params);
    return (result.rows.first['id'] as num).toInt();
  }

  /// Upsert por ID.
  Future<int> upsertById(String table, Map<String, dynamic> data) async {
    return upsert(table, data, conflictColumn: 'id');
  }

  // -------------------------------------------------------------------
  // DELETE
  // -------------------------------------------------------------------

  /// Elimina una fila por ID.
  Future<void> deleteById(String table, int id) async {
    await _session
        .execute('DELETE FROM $table WHERE id = \$1', parameters: [id]);
  }

  /// Elimina filas por filtro.
  Future<void> deleteWhere(
    String table,
    Map<String, dynamic> filters,
  ) async {
    final buffer = StringBuffer('DELETE FROM $table WHERE ');
    final params = <dynamic>[];
    var paramIndex = 1;
    var first = true;

    for (final e in filters.entries) {
      if (!first) buffer.write(' AND ');
      first = false;
      final v = await _normalizedValue(table, e.key, e.value);
      buffer.write('${e.key} = \$$paramIndex');
      params.add(v);
      paramIndex++;
    }

    await _session.execute(buffer.toString(), parameters: params);
  }

  // -------------------------------------------------------------------
  // TRANSACTIONS
  // -------------------------------------------------------------------

  /// Ejecuta una función dentro de una transacción.
  Future<T> transaction<T>(Future<T> Function(PostgresService tx) action) {
    return _session.runTx((session) {
      return action(PostgresService._fromSession(session));
    });
  }

  PostgresService._fromSession(this._session);

  // -------------------------------------------------------------------
  // RPC / RAW SQL
  // -------------------------------------------------------------------

  /// Ejecuta SQL raw y retorna filas.
  Future<List<Map<String, dynamic>>> executeSql(
    String sql, {
    List<dynamic> params = const [],
  }) async {
    return _query(sql, params);
  }

  /// Suma stock por producto (grupo de ids) en una sola consulta SQL.
  Future<Map<int, double>> getStockMapForProductos(
      List<int> productoIds) async {
    if (productoIds.isEmpty) return {};
    final rows = await _query(
      'SELECT producto_id, SUM(cantidad) AS total FROM existencias '
      'WHERE producto_id = ANY(\$1) GROUP BY producto_id',
      [productoIds],
    );
    return {
      for (final e in rows)
        e['producto_id'] as int: (e['total'] as num).toDouble(),
    };
  }

  /// Ejecuta SQL raw (comando) y retorna filas afectadas.
  Future<int> executeCommand(
    String sql, {
    List<dynamic> params = const [],
  }) async {
    return _execute(sql, params);
  }
}
