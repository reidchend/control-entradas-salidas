import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'sql_session.dart';

/// Sesión SQL para Flutter web.
///
/// Ejecuta las queries contra el proxy `/proxy-sql` del servidor (tool/server.py),
/// que habla con PostgreSQL server-side. El driver nativo usa `dart:io` (sockets),
/// que no existe en web, por eso las sentencias viajan por HTTP.
///
/// Transacciones: una sesión raíz (sin [txId]) hace `begin`, obtiene un txid y
/// crea una sesión hija; las sentencias se envían con ese txid y termina con
/// `commit`/`rollback` en el servidor.
class HttpSqlSession implements SqlSession {
  HttpSqlSession({
    String? baseUrl,
    this.txId,
    http.Client? client,
  })  : _baseUrl = baseUrl ?? Uri.base.resolve('/proxy-sql').toString(),
        _client = client ?? http.Client();

  final String _baseUrl;

  /// Identificador de la transacción abierta (null = sesión raíz).
  final String? txId;
  final http.Client _client;

  @override
  Future<SqlResult> execute(
    String sql, {
    List<Object?>? parameters,
  }) async {
    final payload = await _request(
      'execute',
      sql: sql,
      txid: txId,
      params: parameters,
    );
    final rows = (payload['rows'] as List<dynamic>? ?? const [])
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    return SqlResult(
      rows: rows,
      affectedRows: (payload['affectedRows'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<T> runTx<T>(Future<T> Function(SqlSession tx) action) async {
    if (txId != null) {
      throw StateError('Transacciones anidadas no soportadas por el proxy');
    }
    final begin = await _request('begin');
    final beginTxId = begin['txid'] as String?;
    if (beginTxId == null) {
      throw StateError('El proxy no devolvió txid');
    }
    final tx = HttpSqlSession(baseUrl: _baseUrl, txId: beginTxId);
    try {
      final result = await action(tx);
      await _request('commit', txid: beginTxId);
      return result;
    } catch (_) {
      try {
        await _request('rollback', txid: beginTxId);
      } catch (_) {
        // El rollback pudo fallar porque el proxy ya no existe (p. ej. expiró).
      }
      rethrow;
    }
  }

  /// Llama al proxy y parsea la respuesta JSON uniforme.
  Future<Map<String, dynamic>> _request(
    String action, {
    String? sql,
    String? txid,
    List<Object?>? params,
  }) async {
    final body = <String, dynamic>{
      'action': action,
      if (sql != null) 'sql': sql,
      if (txid != null) 'txid': txid,
      if (params != null) 'params': params.map(_encodeValue).toList(),
    };
    final res = await _client
        .post(
          Uri.parse(_baseUrl),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));

    final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw StateError('Proxy SQL: respuesta inválida (${res.statusCode})');
    }
    if (res.statusCode >= 400) {
      throw StateError('Proxy SQL error ${res.statusCode}: '
          '${decoded['error'] ?? res.body}');
    }
    return decoded;
  }

  /// Valores que el driver nativo aceptaría (DateTime, etc.) → JSON.
  static Object? _encodeValue(Object? v) {
    if (v is DateTime) return v.toUtc().toIso8601String();
    return v;
  }
}