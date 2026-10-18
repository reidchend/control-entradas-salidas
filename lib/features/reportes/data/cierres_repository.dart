import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/postgres_providers.dart';
import '../../../core/data/postgres_service.dart';
import '../../../core/models/pos_cierre_models.dart';

/// Repositorio para consultar cierres de caja guardados
class CierresRepository {
  CierresRepository(this._db);
  final PostgresService _db;

  /// FROM compartido: `pos_cierres` no guarda el nombre del cajero, solo el
  /// `usuario_id`, así que se resuelve con un LEFT JOIN a `usuarios`.
  ///
  /// Ojo: no usar el embed de PostgREST `select('*, usuarios(nombre)')` —
  /// la fachada `PgClient` no lo traduce y lo manda literal al SQL
  /// (`SELECT *, usuarios(nombre) ...`), que Postgres rechaza con error 500.
  static const _fromJoin =
      'SELECT c.*, u.nombre AS usuario_nombre FROM pos_cierres c '
      'LEFT JOIN usuarios u ON u.id = c.usuario_id';

  /// Fila de `pos_cierres` con el nombre del cajero (columna
  /// `usuario_nombre` del JOIN; vacío si el usuario ya no existe).
  CierreCaja _fromRow(Map<String, dynamic> r) {
    return CierreCaja.fromJson({
      'sesion_id': r['sesion_id'],
      'usuario_id': r['usuario_id'],
      'usuario_nombre': r['usuario_nombre'] as String? ?? '',
      'abierta_en': r['abierta_en'],
      'cerrada_en': r['cerrada_en'],
      'caja_inicial': (r['caja_inicial'] as num?)?.toDouble() ?? 0,
      'total_ventas': (r['total_ventas'] as num?)?.toDouble() ?? 0,
      'caja_final': (r['caja_final'] as num?)?.toDouble() ?? 0,
      'reporte_simple_json': r['reporte_simple_json'] is String
          ? jsonDecode(r['reporte_simple_json'])
          : r['reporte_simple_json'],
      'reporte_detallado_json': r['reporte_detallado_json'] is String
          ? jsonDecode(r['reporte_detallado_json'])
          : r['reporte_detallado_json'],
      'sync_uuid': r['sync_uuid'],
    });
  }

  /// Lista cierres con filtros opcionales
  Future<List<CierreCaja>> getCierres({
    DateTime? desde,
    DateTime? hasta,
    int? usuarioId,
    int limit = 50,
  }) async {
    final params = <dynamic>[];
    final conds = <String>[];
    void addCond(String sql, dynamic valor) {
      params.add(valor);
      conds.add(sql.replaceAll('@', '\$${params.length}'));
    }

    if (desde != null) addCond('c.cerrada_en >= @', desde.toIso8601String());
    if (hasta != null) addCond('c.cerrada_en <= @', hasta.toIso8601String());
    if (usuarioId != null) addCond('c.usuario_id = @', usuarioId);

    final sql = StringBuffer(_fromJoin);
    if (conds.isNotEmpty) sql.write(' WHERE ${conds.join(' AND ')}');
    // `limit` es int controlado por el caller (no proviene del usuario) y
    // Postgres no admite placeholders en LIMIT, por eso se interpolan.
    sql.write(' ORDER BY c.cerrada_en DESC LIMIT $limit');

    final rows = await _db.executeSql(sql.toString(), params: params);
    return rows.map(_fromRow).toList();
  }

  /// Obtiene un cierre por ID
  Future<CierreCaja?> getCierreById(int id) async {
    final rows = await _db.executeSql(
      '$_fromJoin WHERE c.id = \$1',
      params: [id],
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }
}

final cierresRepoProvider = Provider<CierresRepository>((ref) {
  final db = ref.watch(postgresServiceProvider);
  if (db == null) throw Exception('Supabase no configurado');
  return CierresRepository(db);
});

/// Provider con filtros para lista de cierres
final cierresHistorialProvider = FutureProvider.family<List<CierreCaja>, ({
  DateTime? desde,
  DateTime? hasta,
  int? usuarioId,
  int limit,
})>((ref, params) {
  return ref.watch(cierresRepoProvider).getCierres(
    desde: params.desde,
    hasta: params.hasta,
    usuarioId: params.usuarioId,
    limit: params.limit,
  );
});