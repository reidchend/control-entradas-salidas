/// Backend de SQLite para el módulo Hostelería (pruebas locales).
///
/// Detecta/crea un archivo `.db` junto al ejecutable y ejecuta todo el
/// esquema necesario para que hostelería funcione sin tocar PostgreSQL.
///
/// Los placeholders `$1`, `$2` se traducen a `?` (sintaxis nativa de SQLite).
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'hostel_db_backend.dart';
import 'hostel_sqlite_schema.dart';

/// Traduce placeholders de PostgreSQL (`$1`, `$2`, …) a `?` de SQLite.
///
/// SQLite numera los parámetros por posición, así que se reconstruye la lista
/// en el orden en que aparecen los placeholders. Esto permite reutilizar el
/// mismo `$1` varias veces (p. ej. `col = $1 OR otra = $1`), algo que en
/// PostgreSQL es válido pero en SQLite requeriría dos parámetros.
({String sql, List<dynamic> params}) _translatePlaceholders(
  String sql,
  List<dynamic> params,
) {
  final bound = <dynamic>[];
  final translated = sql.replaceAllMapped(RegExp(r'\$(\d+)'), (m) {
    final index = int.parse(m.group(1)!) - 1;
    if (index < 0 || index >= params.length) {
      throw ArgumentError(
        'Placeholder ${m.group(0)} sin parámetro '
        '(${params.length} recibidos).',
      );
    }
    bound.add(params[index]);
    return '?';
  });
  return (
    sql: translated,
    params: bound.isEmpty ? params : bound,
  );
}

class SqliteDbBackend implements HostelDbBackend {
  SqliteDbBackend(this._dbPath);

  final String _dbPath;
  Database? _db;

  /// Inicializa la fábrica de FFI (requerido en desktop con sqflite_common_ffi).
  static void initFFI() {
    databaseFactory = databaseFactoryFfi;
  }

  /// Abre (o crea) la base de datos y ejecuta el esquema inicial.
  Future<void> open() async {
    final dir = p.dirname(_dbPath);
    if (!await Directory(dir).exists()) {
      await Directory(dir).create(recursive: true);
    }
    _db = await openDatabase(
      _dbPath,
      version: 1,
      onCreate: (db, version) async {
        for (final stmt in hosteleriaSqliteSchema) {
          await db.execute(stmt);
        }
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        for (final stmt in hosteleriaSqliteSchema) {
          await db.execute(stmt);
        }
      },
    );
  }

  Database get db {
    if (_db == null) {
      throw StateError(
        'SqliteDbBackend no está abierto. Llamá a open() antes de usarlo.',
      );
    }
    return _db!;
  }

  @override
  Future<List<Map<String, dynamic>>> executeSql(
    String sql, {
    List<dynamic> params = const [],
  }) async {
    final q = _translatePlaceholders(sql, params);
    return await db.rawQuery(q.sql, q.params);
  }

  @override
  Future<int> executeCommand(
    String sql, {
    List<dynamic> params = const [],
  }) async {
    final q = _translatePlaceholders(sql.trim(), params);
    final nSql = q.sql;
    final upper = nSql.toUpperCase();
    if (upper.startsWith('INSERT')) {
      return await db.rawInsert(nSql, q.params);
    } else if (upper.startsWith('UPDATE')) {
      return await db.rawUpdate(nSql, q.params);
    } else if (upper.startsWith('DELETE')) {
      return await db.rawDelete(nSql, q.params);
    }
    // Para cualquier otro comando (CREATE, etc.) no hay filas afectadas útiles.
    await db.execute(nSql, q.params);
    return 0;
  }

  @override
  Future<int> insert(String table, Map<String, dynamic> data) async {
    return await db.insert(table, data);
  }

  @override
  Future<void> updateById(
    String table,
    int id,
    Map<String, dynamic> data,
  ) async {
    await db.update(table, data, where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> deleteById(String table, int id) async {
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<Map<String, dynamic>?> fetchById(String table, int id) async {
    final rows = await db.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
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
    final where = <String>[];
    final args = <dynamic>[];

    if (filters != null) {
      filters.forEach((k, v) {
        where.add('$k = ?');
        args.add(v);
      });
    }
    if (search != null && search.isNotEmpty && searchColumn != null) {
      where.add('$searchColumn LIKE ?');
      args.add('%${search.toLowerCase()}%');
    }

    return await db.query(
      table,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: orderBy != null
          ? '$orderBy ${ascending ? 'ASC' : 'DESC'}'
          : null,
      limit: limit,
    );
  }

  @override
  Future<T> transaction<T>(Future<T> Function(HostelDbBackend tx) action) async {
    return await db.transaction((txn) async {
      final sqliteTx = _SqliteTx(txn);
      return await action(sqliteTx);
    });
  }
}

/// Wrapper de [Transaction] de sqflite que implementa [HostelDbBackend]
/// para usarse dentro de transacciones.
class _SqliteTx implements HostelDbBackend {
  _SqliteTx(this._txn);
  final Transaction _txn;

  @override
  Future<List<Map<String, dynamic>>> executeSql(
    String sql, {
    List<dynamic> params = const [],
  }) async {
    final q = _translatePlaceholders(sql, params);
    return await _txn.rawQuery(q.sql, q.params);
  }

  @override
  Future<int> executeCommand(
    String sql, {
    List<dynamic> params = const [],
  }) async {
    final q = _translatePlaceholders(sql.trim(), params);
    final nSql = q.sql;
    final upper = nSql.toUpperCase();
    if (upper.startsWith('INSERT')) {
      return await _txn.rawInsert(nSql, q.params);
    } else if (upper.startsWith('UPDATE')) {
      return await _txn.rawUpdate(nSql, q.params);
    } else if (upper.startsWith('DELETE')) {
      return await _txn.rawDelete(nSql, q.params);
    }
    await _txn.execute(nSql, q.params);
    return 0;
  }

  @override
  Future<int> insert(String table, Map<String, dynamic> data) async {
    return await _txn.insert(table, data);
  }

  @override
  Future<void> updateById(
    String table,
    int id,
    Map<String, dynamic> data,
  ) async {
    await _txn.update(table, data, where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> deleteById(String table, int id) async {
    await _txn.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<Map<String, dynamic>?> fetchById(String table, int id) async {
    final rows = await _txn.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
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
    final where = <String>[];
    final args = <dynamic>[];
    if (filters != null) {
      filters.forEach((k, v) {
        where.add('$k = ?');
        args.add(v);
      });
    }
    if (search != null && search.isNotEmpty && searchColumn != null) {
      where.add('$searchColumn LIKE ?');
      args.add('%${search.toLowerCase()}%');
    }
    return await _txn.query(
      table,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: orderBy != null
          ? '$orderBy ${ascending ? 'ASC' : 'DESC'}'
          : null,
      limit: limit,
    );
  }

  @override
  Future<T> transaction<T>(Future<T> Function(HostelDbBackend tx) action) {
    // Las transacciones anidadas en SQLite no son necesarias para este uso.
    return action(this);
  }
}
