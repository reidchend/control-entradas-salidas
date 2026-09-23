import '../../../core/data/postgres_service.dart';
import 'activo.dart';
import 'activo_tipo.dart';
import 'activos_categoria.dart';

/// Repositorio de activos — CRUD del catálogo de tipos y sus unidades.
///
/// Opera contra tres tablas:
/// - `activos_categorias`: agrupación de primer nivel.
/// - `activos_tipos`: catálogo maestro (nombre, grupo, modelo, categoría).
/// - `activos`: una unidad física por fila (ubicación, estado, valor, ...),
///   referenciando su tipo con `tipo_id`.
class ActivosRepository {
  ActivosRepository(this._db);

  final PostgresService _db;

  /// Columnas base de una unidad más los campos resueltos por JOIN.
  static const _colsActivo =
      'a.id, a.tipo_id, a.ubicacion, a.estado, a.valor, a.fecha, '
      'a.observaciones, a.activo, a.created_at, a.updated_at';

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

  /// Categorías activas con su conteo de unidades (vía tipos), para las
  /// cards del grid.
  Future<List<Map<String, dynamic>>> getCategoriasConConteo() async {
    final rows = await _db.executeSql(
      'SELECT c.*, COUNT(a.id) AS n '
      'FROM activos_categorias c '
      'LEFT JOIN activos_tipos t ON t.categoria_id = c.id '
      'LEFT JOIN activos a ON a.tipo_id = t.id '
      'WHERE c.activo = TRUE '
      'GROUP BY c.id '
      'ORDER BY c.nombre',
    );
    return [
      for (final r in rows)
        {
          'categoria': ActivosCategoria.fromMap(r),
          'conteo': (r['n'] as num?)?.toInt() ?? 0,
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
    await _db.updateWhere(
      'activos_tipos',
      {'categoria_id': id},
      {'categoria_id': null},
    );
    await _db.deleteById('activos_categorias', id);
  }

  // ---------------------------------------------------------------------
  // Tipos (catálogo)
  // ---------------------------------------------------------------------

  /// Tipos activos de una categoría (o todos) con su conteo de unidades.
  /// [search] filtra por nombre, grupo o modelo (insensible a mayúsculas).
  Future<List<Map<String, dynamic>>> getTipos({
    int? categoriaId,
    String? search,
  }) async {
    final condiciones = <String>['t.activo = TRUE'];
    final params = <dynamic>[];
    var i = 1;
    if (categoriaId != null) {
      condiciones.add('t.categoria_id = \$${i++}');
      params.add(categoriaId);
    }
    final q = search?.trim().toLowerCase();
    if (q != null && q.isNotEmpty) {
      condiciones.add(
          '(LOWER(t.nombre) LIKE \$${i++} OR '
          'LOWER(COALESCE(t.grupo, \'\')) LIKE \$${i++} OR '
          'LOWER(COALESCE(t.modelo, \'\')) LIKE \$${i++})');
      params
        ..add('%$q%')
        ..add('%$q%')
        ..add('%$q%');
    }

    final rows = await _db.executeSql(
      'SELECT t.*, COUNT(a.id) AS unidades '
      'FROM activos_tipos t '
      'LEFT JOIN activos a ON a.tipo_id = t.id '
      'WHERE ${condiciones.join(' AND ')} '
      'GROUP BY t.id '
      'ORDER BY t.nombre',
      params: params,
    );
    return [
      for (final r in rows)
        {
          'tipo': ActivoTipo.fromMap(r),
          'unidades': (r['unidades'] as num?)?.toInt() ?? 0,
        }
    ];
  }

  Future<int> createTipo(ActivoTipo tipo) {
    return _db.insert('activos_tipos', tipo.toMap());
  }

  Future<void> updateTipo(int id, ActivoTipo tipo) {
    return _db.updateById('activos_tipos', id, tipo.toMap());
  }

  Future<void> deactivateTipo(int id) async {
    await _db.updateById('activos_tipos', id, {'activo': false});
  }

  /// Elimina el tipo y sus unidades (transacción atómica).
  Future<void> deleteTipo(int id) {
    return _db.transaction((tx) async {
      await tx.deleteWhere('activos', {'tipo_id': id});
      await tx.deleteById('activos_tipos', id);
    });
  }

  // ---------------------------------------------------------------------
  // Unidades (activos físicos)
  // ---------------------------------------------------------------------

  /// Unidades de un tipo, con los campos del catálogo resueltos por JOIN.
  Future<List<Activo>> getUnidadesDeTipo(int tipoId, {String? search}) async {
    final q = search?.trim().toLowerCase();
    final list = q != null && q.isNotEmpty;
    final sql =
        'SELECT $_colsActivo, '
        't.nombre AS tipo_nombre, t.grupo, t.modelo, t.categoria_id, '
        'COALESCE(c.nombre, \'Sin categoría\') AS categoria_nombre '
        'FROM activos a '
        'JOIN activos_tipos t ON t.id = a.tipo_id '
        'LEFT JOIN activos_categorias c ON c.id = t.categoria_id '
        'WHERE a.tipo_id = \$1'
        '${list ? ' AND (LOWER(COALESCE(a.ubicacion, \'\')) LIKE \$2 OR LOWER(COALESCE(a.observaciones, \'\')) LIKE \$2)' : ''} '
        'ORDER BY a.ubicacion NULLS LAST, a.id';
    final rows = await _db.executeSql(
      sql,
      params: list ? [tipoId, '%$q%'] : [tipoId],
    );
    return rows.map(Activo.fromMap).toList();
  }

  Future<int> createActivo(Activo activo) {
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

  // ---------------------------------------------------------------------
  // Valores de dimensión (grid "por valor")
  // ---------------------------------------------------------------------

  Future<List<String>> getGrupos() => _distintosTipos('grupo');

  Future<List<String>> getModelos() => _distintosTipos('modelo');

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

  Future<List<String>> _distintosTipos(String col) async {
    try {
      final rows = await _db.executeSql(
        'SELECT DISTINCT t.$col FROM activos_tipos t '
        'WHERE t.$col IS NOT NULL AND t.$col <> \'\' AND t.activo = TRUE '
        'ORDER BY t.$col',
      );
      return [for (final r in rows) r[col] as String];
    } catch (_) {
      return const [];
    }
  }

  /// Valores de una columna con el nº de unidades activas que lo usan.
  /// `grupo` y `modelo` viven en el catálogo (tipos); `ubicacion` y
  /// `estado` en las unidades.
  Future<List<Map<String, dynamic>>> getValoresConConteo(String columna) async {
    if (columna == 'grupo' || columna == 'modelo') {
      return _db.executeSql(
        'SELECT t.$columna AS valor, COUNT(a.id) AS n '
        'FROM activos_tipos t '
        'LEFT JOIN activos a ON a.tipo_id = t.id '
        'WHERE t.$columna IS NOT NULL AND t.$columna <> \'\' '
        'AND a.activo = TRUE '
        'GROUP BY t.$columna ORDER BY t.$columna',
      );
    }
    return _db.executeSql(
      'SELECT a.$columna AS valor, COUNT(*) AS n '
      'FROM activos a '
      'WHERE a.$columna IS NOT NULL AND a.$columna <> \'\' AND a.activo = TRUE '
      'GROUP BY a.$columna ORDER BY a.$columna',
    );
  }

  /// Unidades que cumplen los filtros (categoría/grupo/modelo desde el
  /// catálogo; ubicación/estado desde la unidad), con campos resueltos.
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
    void add(String cond, dynamic v) {
      condiciones.add(cond);
      params.add(v);
      i++;
    }

    if (categoriaId != null) add('t.categoria_id = \$${i++}', categoriaId);
    if (grupo != null && grupo.trim().isNotEmpty) add('t.grupo = \$${i++}', grupo.trim());
    if (modelo != null && modelo.trim().isNotEmpty) add('t.modelo = \$${i++}', modelo.trim());
    if (ubicacion != null && ubicacion.trim().isNotEmpty) {
      add('a.ubicacion = \$${i++}', ubicacion.trim());
    }
    if (estado != null && estado.trim().isNotEmpty) add('a.estado = \$${i++}', estado.trim());

    final where =
        condiciones.isEmpty ? '' : ' WHERE ${condiciones.join(' AND ')}';
    final sql =
        'SELECT $_colsActivo, '
        't.nombre AS tipo_nombre, t.grupo, t.modelo, t.categoria_id, '
        'COALESCE(c.nombre, \'Sin categoría\') AS categoria_nombre '
        'FROM activos a '
        'JOIN activos_tipos t ON t.id = a.tipo_id '
        'LEFT JOIN activos_categorias c ON c.id = t.categoria_id'
        '$where '
        'ORDER BY categoria_nombre, t.grupo, t.nombre, a.id';
    return _db.executeSql(sql, params: params);
  }

  // ---------------------------------------------------------------------
  // Exportación (Excel)
  // ---------------------------------------------------------------------

  /// Todas las unidades (incluye desactivadas) con datos de su tipo y
  /// categoría resueltos por JOIN.
  Future<List<Map<String, dynamic>>> getActivosParaExportar() async {
    return _db.executeSql(
      'SELECT a.*, t.nombre, t.grupo, t.modelo, t.categoria_id, '
      'COALESCE(c.nombre, \'Sin categoría\') AS categoria_nombre '
      'FROM activos a '
      'JOIN activos_tipos t ON t.id = a.tipo_id '
      'LEFT JOIN activos_categorias c ON c.id = t.categoria_id '
      'ORDER BY categoria_nombre, t.grupo, t.nombre, a.id',
    );
  }

  /// Totales por grupo (por categoría): nº de unidades y valor total.
  Future<List<Map<String, dynamic>>> getTotalesPorGrupo() async {
    return _db.executeSql(
      'SELECT COALESCE(c.nombre, \'Sin categoría\') AS categoria_nombre, '
      'COALESCE(NULLIF(t.grupo, \'\'), \'Sin grupo\') AS grupo, '
      'COUNT(a.id) AS n_activos, '
      'COUNT(a.id) AS unidades, '
      'COALESCE(SUM(a.valor), 0) AS valor_total '
      'FROM activos a '
      'JOIN activos_tipos t ON t.id = a.tipo_id '
      'LEFT JOIN activos_categorias c ON c.id = t.categoria_id '
      'GROUP BY c.nombre, t.grupo '
      'ORDER BY categoria_nombre, t.grupo',
    );
  }
}