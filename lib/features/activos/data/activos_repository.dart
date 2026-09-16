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

  /// Todos los activos (incluye desactivados) con el nombre de su categoría
  /// resuelto por JOIN, listos para exportar.
  Future<List<Map<String, dynamic>>> getActivosParaExportar() async {
    return _db.executeSql(
      'SELECT a.*, COALESCE(c.nombre, \'Sin categoría\') AS categoria_nombre '
      'FROM activos a '
      'LEFT JOIN activos_categorias c ON c.id = a.categoria_id '
      'ORDER BY categoria_nombre, a.grupo, a.nombre',
    );
  }

  /// Totales por grupo (por categoría): nº de activos, unidades y valor total.
  Future<List<Map<String, dynamic>>> getTotalesPorGrupo() async {
    return _db.executeSql(
      'SELECT COALESCE(c.nombre, \'Sin categoría\') AS categoria_nombre, '
      'COALESCE(NULLIF(a.grupo, \'\'), \'Sin grupo\') AS grupo, '
      'COUNT(*) AS n_activos, '
      'COALESCE(SUM(a.cantidad), 0) AS unidades, '
      'COALESCE(SUM(a.valor), 0) AS valor_total '
      'FROM activos a '
      'LEFT JOIN activos_categorias c ON c.id = a.categoria_id '
      'GROUP BY c.nombre, a.grupo '
      'ORDER BY categoria_nombre, a.grupo',
    );
  }

  /// Grupos existentes (distintos) entre todos los activos, ordenados.
  Future<List<String>> getGrupos() async {
    try {
      final rows = await _db.executeSql(
        'SELECT DISTINCT grupo FROM activos '
        'WHERE grupo IS NOT NULL AND grupo <> \'\' '
        'ORDER BY grupo',
      );
      return [for (final r in rows) r['grupo'] as String];
    } catch (_) {
      return const [];
    }
  }

  /// Ubicaciones existentes (distintas) entre todos los activos, ordenadas.
  Future<List<String>> getUbicaciones() async {
    try {
      final rows = await _db.executeSql(
        'SELECT DISTINCT ubicacion FROM activos '
        'WHERE ubicacion IS NOT NULL AND ubicacion <> \'\' '
        'ORDER BY ubicacion',
      );
      return [for (final r in rows) r['ubicacion'] as String];
    } catch (_) {
      return const [];
    }
  }

  /// Modelos existentes (distintos) entre todos los activos, ordenados.
  Future<List<String>> getModelos() async {
    try {
      final rows = await _db.executeSql(
        'SELECT DISTINCT modelo FROM activos '
        'WHERE modelo IS NOT NULL AND modelo <> \'\' '
        'ORDER BY modelo',
      );
      return [for (final r in rows) r['modelo'] as String];
    } catch (_) {
      return const [];
    }
  }

  /// Valores de una columna (ubicacion, grupo, modelo, estado...) con el nº
  /// de activos activos que lo usan, para el grid de valores.
  Future<List<Map<String, dynamic>>> getValoresConConteo(String columna) async {
    return _db.executeSql(
      'SELECT a.$columna AS valor, COUNT(*) AS n '
      'FROM activos a '
      'WHERE a.$columna IS NOT NULL AND a.$columna <> \'\' AND a.activo = TRUE '
      'GROUP BY a.$columna ORDER BY a.$columna',
    );
  }

  /// Activos que cumplen los filtros seleccionados (todos los campos
  /// opcionales), con nombre de categoría resuelto por JOIN.
  Future<List<Map<String, dynamic>>> getActivosConFiltros({
    int? categoriaId,
    String? grupo,
    String? ubicacion,
    String? modelo,
    String? estado,
  }) async {
    final condiciones = <String>[];
    final params = <dynamic>[];
    var i = 1;
    void add(String col, dynamic v) {
      condiciones.add('a.$col = \$$i');
      params.add(v);
      i++;
    }

    if (categoriaId != null) add('categoria_id', categoriaId);
    if (grupo != null && grupo.trim().isNotEmpty) add('grupo', grupo.trim());
    if (ubicacion != null && ubicacion.trim().isNotEmpty) {
      add('ubicacion', ubicacion.trim());
    }
    if (modelo != null && modelo.trim().isNotEmpty) add('modelo', modelo.trim());
    if (estado != null && estado.trim().isNotEmpty) add('estado', estado.trim());

    final where =
        condiciones.isEmpty ? '' : ' WHERE ${condiciones.join(' AND ')}';
    final sql =
        'SELECT a.*, COALESCE(c.nombre, \'Sin categoría\') AS categoria_nombre '
        'FROM activos a '
        'LEFT JOIN activos_categorias c ON c.id = a.categoria_id'
        '$where '
        'ORDER BY categoria_nombre, a.grupo, a.nombre';
    return _db.executeSql(sql, params: params);
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