import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/supabase_providers.dart';
import '../../../core/data/supabase_service.dart';
import '../../../core/models/pos_cierre_models.dart';

/// Repositorio para consultar cierres de caja guardados
class CierresRepository {
  CierresRepository(this._db);
  final SupabaseService _db;

  /// Lista cierres con filtros opcionales
  Future<List<CierreCaja>> getCierres({
    DateTime? desde,
    DateTime? hasta,
    int? usuarioId,
    int limit = 50,
  }) async {
    dynamic query = _db.client
        .from('pos_cierres')
        .select();

    if (desde != null) {
      query = query.gte('cerrada_en', desde.toIso8601String());
    }
    if (hasta != null) {
      query = query.lte('cerrada_en', hasta.toIso8601String());
    }
    if (usuarioId != null) {
      query = query.eq('usuario_id', usuarioId);
    }

    query = query
        .order('cerrada_en', ascending: false)
        .limit(limit);

    final rows = (await query) as List<Map<String, dynamic>>;
    return rows.map((r) => CierreCaja.fromJson({
      'sesion_id': r['sesion_id'],
      'usuario_id': r['usuario_id'],
      'usuario_nombre': r['usuario_nombre'] ?? '',
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
    })).toList();
  }

  /// Obtiene un cierre por ID
  Future<CierreCaja?> getCierreById(int id) async {
    final rows = await _db.client
        .from('pos_cierres')
        .select()
        .eq('id', id)
        .limit(1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return CierreCaja.fromJson({
      'sesion_id': r['sesion_id'],
      'usuario_id': r['usuario_id'],
      'usuario_nombre': r['usuario_nombre'] ?? '',
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
}

final cierresRepoProvider = Provider<CierresRepository>((ref) {
  final db = ref.watch(supabaseServiceProvider);
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