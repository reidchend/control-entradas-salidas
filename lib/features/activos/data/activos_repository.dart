import '../../../core/data/postgres_service.dart';
import 'activo.dart';

/// Repositorio de activos — CRUD de bienes del inventario.
/// Opera contra la tabla `activos` en PostgreSQL.
class ActivosRepository {
  ActivosRepository(this._db);

  final PostgresService _db;

  /// Lista activos con filtros opcionales (por categoría/estado/ubicación/búsqueda).
  Future<List<Activo>> getActivos({
    String? categoria,
    String? estado,
    bool? soloActivos = true,
    String? search,
  }) async {
    final filters = <String, dynamic>{
      if (categoria != null && categoria.isNotEmpty)
        'categoria': categoria,
      if (estado != null && estado.isNotEmpty) 'estado': estado,
      if (soloActivos == true) 'activo': true,
    };
    final rows = await _db.fetchAll(
      'activos',
      orderBy: 'nombre',
      ascending: true,
      filters: filters,
      search: (search == null || search.isEmpty) ? null : search,
      searchColumn: 'nombre',
    );
    return rows.map(Activo.fromMap).toList();
  }

  /// Categorías distintas (para filtros), ordenadas por uso descendente.
  Future<List<String>> getCategorias() async {
    final rows = await _db.fetchAll('activos');
    final map = <String, int>{};
    for (final r in rows) {
      final c = (r['categoria'] as String?)?.trim();
      if (c != null && c.isNotEmpty) {
        map[c] = (map[c] ?? 0) + 1;
      }
    }
    final list = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list.map((e) => e.key).toList();
  }

  /// Ubicaciones distintas (para filtros).
  Future<List<String>> getUbicaciones() async {
    final rows = await _db.fetchAll('activos');
    final set = <String>{};
    for (final r in rows) {
      final u = (r['ubicacion'] as String?)?.trim();
      if (u != null && u.isNotEmpty) set.add(u);
    }
    final list = set.toList()..sort();
    return list;
  }

  Future<int> createActivo(Activo activo) async {
    return _db.insert('activos', activo.toMap());
  }

  Future<void> updateActivo(int id, Activo activo) {
    return _db.updateById('activos', id, activo.toMap());
  }

  /// Baja lógica: activo=false (el registro permanece como histórico).
  Future<void> deactivateActivo(int id) async {
    await _db.updateById('activos', id, {'activo': false});
  }

  Future<void> deleteActivo(int id) async {
    await _db.deleteById('activos', id);
  }
}