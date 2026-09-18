import 'dart:async';

import 'sql_session.dart';

/// Cliente PostgreSQL compatible con la sintaxis PostgREST usada por los
/// repositorios:
///
///   _db.client.from('productos').select().eq('id', 1).limit(1)
///   _db.client.from('movimientos').insert({...}).select('id').single()
///
/// Internamente traduce la cadena a SQL parametrizado sobre la [SqlSession].
class PgClient {
  PgClient(this._session);

  final SqlSession _session;

  PgQueryBuilder from(String table) => PgQueryBuilder(_session, table);
}

/// Builder encadenado que se ejecuta al ser `await`eado.
///
/// El resultado depende del modo final:
/// - [single] retorna `Map<String, dynamic>` (lanza si vacío).
/// - [maybeSingle] retorna `Map<String, dynamic>?`.
/// - insert/upsert con [select] y [single] retorna la fila (con `RETURNING`).
/// - por defecto retorna `List<Map<String, dynamic>>` (o `void` en writes).
class PgQueryBuilder implements Future<dynamic> {
  PgQueryBuilder(this._session, this._table);

  final SqlSession _session;
  final String _table;

  String? _columns;
  final List<String> _conds = [];
  final Map<int, Object?> _bindings = {};
  int _paramSeq = 0;
  String? _orderBy;
  bool _ascending = true;
  String? _orderTable;
  int? _limit;
  bool _single = false;
  bool _maybeSingle = false;

  _PgWrite? _write;
  String? _onConflict;

  // -------------------------------------------------------------------
  // SELECT
  // -------------------------------------------------------------------

  PgQueryBuilder select([String? columns]) {
    _columns = columns;
    return this;
  }

  PgQueryBuilder eq(String column, Object? value) {
    final id = _nextParam();
    _conds.add('$column = \$$id');
    return _bind(id, value);
  }

  PgQueryBuilder neq(String column, Object? value) {
    final id = _nextParam();
    _conds.add('$column != \$$id');
    return _bind(id, value);
  }

  PgQueryBuilder gt(String column, Object? value) {
    final id = _nextParam();
    _conds.add('$column > \$$id');
    return _bind(id, value);
  }

  PgQueryBuilder gte(String column, Object? value) {
    final id = _nextParam();
    _conds.add('$column >= \$$id');
    return _bind(id, value);
  }

  PgQueryBuilder lt(String column, Object? value) {
    final id = _nextParam();
    _conds.add('$column < \$$id');
    return _bind(id, value);
  }

  PgQueryBuilder lte(String column, Object? value) {
    final id = _nextParam();
    _conds.add('$column <= \$$id');
    return _bind(id, value);
  }

  PgQueryBuilder ilike(String column, Object? value) {
    final id = _nextParam();
    _conds.add('$column ILIKE \$$id');
    return _bind(id, value);
  }

  PgQueryBuilder like(String column, Object? value) {
    final id = _nextParam();
    _conds.add('$column LIKE \$$id');
    return _bind(id, value);
  }

  PgQueryBuilder isFilter(String column, Object? value) {
    if (value == null) {
      _conds.add('$column IS NULL');
    } else {
      final id = _nextParam();
      _conds.add('$column IS NOT DISTINCT FROM \$$id');
      _bind(id, value);
    }
    return this;
  }

  PgQueryBuilder inFilter(String column, List<Object?> values) {
    if (values.isEmpty) {
      _conds.add('1 = 0');
      return this;
    }
    final ph = <String>[];
    for (final v in values) {
      final id = _nextParam();
      ph.add('\$$id');
      _bind(id, v);
    }
    _conds.add('$column IN (${ph.join(', ')})');
    return this;
  }

  PgQueryBuilder not(String column, String op, Object? value) {
    if (op == 'is') {
      if (value == null) {
        _conds.add('NOT ($column IS NULL)');
      } else {
        final id = _nextParam();
        _conds.add('($column IS NOT DISTINCT FROM \$$id)');
        _bind(id, value);
      }
    } else {
      final sqlOp = switch (op) {
        'eq' => '=',
        'neq' => '!=',
        'gt' => '>',
        'gte' => '>=',
        'lt' => '<',
        'lte' => '<=',
        'ilike' => 'ILIKE',
        'like' => 'LIKE',
        _ => '=',
      };
      final id = _nextParam();
      _conds.add('NOT ($column $sqlOp \$$id)');
      _bind(id, value);
    }
    return this;
  }

  /// Filtro genérico estilo PostgREST: `.filter(col, 'eq', v)`,
  /// `.filter(col, 'in', [..])` o `.filter(col, 'is', null)`.
  PgQueryBuilder filter(String column, String op, Object? value) {
    if (op == 'in') {
      return inFilter(column, value as List<Object?>);
    }
    if (op == 'is') {
      return isFilter(column, value);
    }
    return eq(column, value);
  }

  /// Operador OR estilo PostgREST: `"col1.eq.v1,col2.eq.v2"`.
  PgQueryBuilder or(String filter) {
    final parts = filter.split(',');
    final sqlParts = <String>[];
    for (final part in parts) {
      final match =
          RegExp(r'^(\w+)\.(eq|neq|gt|gte|lt|lte|ilike|like)\.(.+)$')
              .firstMatch(part);
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
          'ilike' => 'ILIKE',
          'like' => 'LIKE',
          _ => '=',
        };
        final id = _nextParam();
        sqlParts.add('$col $sqlOp \$$id');
        _bind(id, val);
      }
    }
    if (sqlParts.isEmpty) {
      _conds.add('1 = 1');
    } else {
      _conds.add('(${sqlParts.join(' OR ')})');
    }
    return this;
  }

  PgQueryBuilder order(String column,
      {bool ascending = true, String? table}) {
    _orderBy = column;
    _ascending = ascending;
    _orderTable = table;
    return this;
  }

  PgQueryBuilder limit(int n) {
    _limit = n;
    return this;
  }

  PgQueryBuilder single() {
    _single = true;
    return this;
  }

  PgQueryBuilder maybeSingle() {
    _maybeSingle = true;
    return this;
  }

  // -------------------------------------------------------------------
  // WRITES
  // -------------------------------------------------------------------

  PgQueryBuilder insert(Map<String, dynamic> data) {
    _write = _PgWrite.insert(data);
    return this;
  }

  PgQueryBuilder upsert(Map<String, dynamic> data, {String? onConflict}) {
    _write = _PgWrite.upsert(data);
    _onConflict = onConflict;
    return this;
  }

  PgQueryBuilder update(Map<String, dynamic> data) {
    _write = _PgWrite.update(data);
    return this;
  }

  PgQueryBuilder delete() {
    _write = const _PgWrite.delete();
    return this;
  }

  int _nextParam() => ++_paramSeq;

  /// Registra [value] en el índice de bind [id] y devuelve [id].
  PgQueryBuilder _bind(int id, Object? value) {
    _bindings[id] = value;
    return this;
  }

  // -------------------------------------------------------------------
  // EXECUCIÓN
  // -------------------------------------------------------------------

  Future<dynamic> _execute() async {
    final w = _write;
    if (w == null) {
      return _executeSelect();
    }
    return _executeWrite(w);
  }

  Future<dynamic> _executeSelect() async {
    final cols = _columns == null || _columns!.isEmpty || _columns == '*'
        ? '*'
        : _columns!;
    final sql = StringBuffer('SELECT $cols FROM $_table');
    _appendWhere(sql);
    if (_orderBy != null) {
      final t = _orderTable ?? _table;
      sql.write(' ORDER BY $t.${_orderBy!} ${_ascending ? 'ASC' : 'DESC'}');
    }
    if (_limit != null) {
      sql.write(' LIMIT $_limit');
    }
    final rows = await _query(sql.toString());
    return _wrapResult(rows);
  }

  Future<dynamic> _executeWrite(_PgWrite w) async {
    final returning =
        _columns == null || _columns!.isEmpty || _columns == '*'
            ? '*'
            : _columns!;
    final hasReturning = _columns != null;

    switch (w.kind) {
      case _PgWriteKind.insert:
      case _PgWriteKind.upsert:
        final data = w.data ?? {};
        final cols = data.keys.join(', ');
        final ph = _registerValues(data.values.toList()).join(', ');
        final onConflict = _onConflict ?? _inferConflict(data);
        final isUpsert = w.kind == _PgWriteKind.upsert && onConflict != null;
        var sql = 'INSERT INTO $_table ($cols) VALUES ($ph)';
        if (isUpsert) {
          final conflictCols = onConflict.split(',');
          final updates = data.keys
              .where((k) => !conflictCols.contains(k))
              .map((k) => '$k = EXCLUDED.$k')
              .join(', ');
          sql += ' ON CONFLICT ($onConflict) DO UPDATE SET $updates';
        }
        if (!hasReturning) {
          await _run(sql);
          return null;
        }
        sql += ' RETURNING $returning';
        final rows = await _query(sql);
        return _wrapResult(rows);
      case _PgWriteKind.update:
        final data = w.data ?? {};
        if (data.isEmpty) return null;
        final sets = <String>[];
        final setValues = <Object?>[];
        for (final e in data.entries) {
          setValues.add(e.value);
          sets.add('${e.key} = ${_register(setValues.last)}');
        }
        final sql = StringBuffer('UPDATE $_table SET ${sets.join(', ')}');
        _appendWhere(sql);
        await _run(sql.toString());
        return null;
      case _PgWriteKind.delete:
        final sql = StringBuffer('DELETE FROM $_table');
        _appendWhere(sql);
        await _run(sql.toString());
        return null;
    }
  }

  /// Registra los [values] en los binds consecutivos y devuelve los
  /// placeholders `$n` correspondientes.
  List<String> _registerValues(List<Object?> values) {
    return [for (final v in values) _register(v)];
  }

  /// Registra [value] en el siguiente bind y devuelve su placeholder `$n`.
  String _register(Object? value) {
    final id = _nextParam();
    _bindings[id] = value;
    return '\$$id';
  }

  String? _inferConflict(Map<String, dynamic> data) {
    if (data.containsKey('id')) return 'id';
    if (data.containsKey('producto_id') && data.containsKey('almacen')) {
      return 'producto_id,almacen';
    }
    return null;
  }

  dynamic _wrapResult(List<Map<String, dynamic>> rows) {
    if (_single) {
      if (rows.isEmpty) {
        throw StateError('single() devolvió vacío');
      }
      return rows.first;
    }
    if (_maybeSingle) {
      return rows.isEmpty ? null : rows.first;
    }
    return rows;
  }

  void _appendWhere(StringBuffer sql) {
    if (_conds.isNotEmpty) {
      sql.write(' WHERE ${_conds.join(' AND ')}');
    }
  }

  Future<List<Map<String, dynamic>>> _query(String sql) async {
    final result = await _session.execute(sql, parameters: _orderedParams());
    return result.rows;
  }

  Future<void> _run(String sql) async {
    await _session.execute(sql, parameters: _orderedParams());
  }

  /// Parámetros en orden de su placeholder `$1..$N`.
  List<Object?> _orderedParams() {
    return [for (var i = 1; i <= _paramSeq; i++) _bindings[i]];
  }

  // -------------------------------------------------------------------
  // INTERFAZ FUTURE
  // -------------------------------------------------------------------

  @override
  Future<R> then<R>(
    FutureOr<R> Function(dynamic value) onValue, {
    Function? onError,
  }) {
    return _execute().then<R>(onValue, onError: onError);
  }

  @override
  Future<dynamic> catchError(Function onError, {bool Function(Object)? test}) {
    return _execute().catchError(onError, test: test);
  }

  @override
  Future<dynamic> whenComplete(FutureOr<void> Function() action) {
    return _execute().whenComplete(action);
  }

  @override
  Stream<dynamic> asStream() => _execute().asStream();

  @override
  Future<dynamic> timeout(Duration timeLimit,
      {FutureOr<dynamic> Function()? onTimeout}) {
    return _execute().timeout(timeLimit, onTimeout: onTimeout);
  }
}

enum _PgWriteKind { insert, upsert, update, delete }

class _PgWrite {
  const _PgWrite._(this.kind, this.data);

  const _PgWrite.insert(Map<String, dynamic> data)
      : this._(_PgWriteKind.insert, data);
  const _PgWrite.upsert(Map<String, dynamic> data)
      : this._(_PgWriteKind.upsert, data);
  const _PgWrite.update(Map<String, dynamic> data)
      : this._(_PgWriteKind.update, data);
  const _PgWrite.delete() : this._(_PgWriteKind.delete, null);

  final _PgWriteKind kind;
  final Map<String, dynamic>? data;
}