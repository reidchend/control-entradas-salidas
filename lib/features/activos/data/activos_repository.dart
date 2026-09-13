import '../../../core/data/postgres_service.dart';
import 'activo.dart';
import 'activos_categoria.dart';

/// Repositorio de activos — CRUD de bienes y sus categorías.
/// Opera contra las tablas `activos` y `activos_categorias`.
class ActivosRepository {
  ActivosRepository(this._db);

  final PostgresService _db;

  // ---------------------------------------------------------------------
  // Categorías
  // ---------------------------------------------------------------------

  Future<List<ActivosCategoria>> getCategorias() async {
    final rows = await _db.fetchAll(
      'activos_categorias',
      orderBy: 'nombre',
      filters: {'activo': true},
    );
    return rows.map(ActivosCategoria.fromMap).toList();
  }

  /// Categorías activas con su conteo de activos (para cards del grid).
  Future<List<Map<String, dynamic>>> getCategoriasConConteo() async {
    final rows = await _db.fetchAll(
      'activos_categorias',
      orderBy: 'nombre',
      filters: {'activo': true},
    );
    final conteos = <int, int>{};
    final activos = await _db.fetchAll('activos');
    for (final a in activos) {
      final cid = a['categoria_id'];
      if (cid is num) {
        conteos[cid.toInt()] = (conteos[cid.toInt()] ?? 0) + 1;
      }
    }
    return [
      for (final r in rows)
        {
          'categoria': ActivosCategoria.fromMap(r),
          'conteo': conteos[(r['id'] as num).toInt()] ?? 0,
        }
    ];
  }

  Future<int> createCategoria(String nombre, {String color = '#2196F3'}) {
    return _db.insert('activos_categorias', {
      'nombre': nombre,
      'color': color,
      'activo': true,
    });
  }

  Future<void> updateCategoria(ActivosCategoria categoria) {
    return _db.updateById(
        'activos_categorias', categoria.id, categoria.toMap());
  }

  Future<void> deactivateCategoria(int id) async {
    await _db.updateById('activos_categorias', id, {'activo': false});
  }

  Future<void> deleteCategoria(int id) async {
    // Los activos de la categoría quedan sin categoría.
    await _db.updateWhere(
      'activos',
      {'categoria_id': id},
      {'categoria_id': null},
    );
    await _db.deleteById('activos_categorias', id);
  }

  // ---------------------------------------------------------------------
  // Activos
  // ---------------------------------------------------------------------

  Future<List<Activo>> getActivos({
    int? categoriaId,
    String? search,
  }) async {
    final filters = <String, dynamic>{};
    if (categoriaId != null) {
      filters['categoria_id'] = categoriaId;
    }
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

  Future<int> createActivo(Activo activo) async {
    return _db.insert('activos', activo.toMap());
  }

  Future<void> updateActivo(int id, Activo activo) {
    return _db.updateById('activos', id, activo.toMap());
  }

  Future<void> deactivateActivo(int id) async {
    await _db.updateById('activos', id, {'activo': false});
  }

  Future<void> deleteActivo(int id) async {
    await _db.deleteById('activos', id);
  }
}