import '../../../core/data/postgres_service.dart';
import '../../../core/utils/prefijo_de_categoria.dart';
import 'activo.dart';
import 'activo_tipo.dart';
import 'activos_categoria.dart';

/// Repositorio de activos — CRUD del catálogo de tipos y sus unidades.
///
/// Opera contra cinco tablas:
/// - `activos_categorias`: agrupación de primer nivel (guarda el prefijo de
///   la placa de inventario).
/// - `activos_estados`: catálogo de estados de las unidades.
/// - `activos_tipos`: catálogo maestro (nombre, grupo, modelo, categoría).
/// - `activos`: una unidad física por fila (ubicación, estado, valor, ...),
///   referenciando su tipo con `tipo_id`.
/// - `activos_codigos`: contador atómico por prefijo, para numerar las placas.
class ActivosRepository {
  ActivosRepository(this._db);

  final PostgresService _db;

  /// Columnas base de una unidad más los campos resueltos por JOIN.
  static const _colsActivo =
      'a.id, a.tipo_id, a.ubicacion, a.estado, a.codigo, a.valor, a.fecha, '
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
      'LEFT JOIN activos a ON a.tipo_id = t.id AND a.activo = TRUE '
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

  /// Crea la categoría y le deriva el prefijo de placa desde el nombre si no
  /// viene explícito ([prefijo] queda guardado para que renombrar la categoría
  /// no cambie las placas ya emitidas).
  Future<int> createCategoria(
    String nombre, {
    String color = '#2196F3',
    String? prefijo,
  }) async {
    final n = nombre.trim();
    if (n.isEmpty) throw ArgumentError('El nombre de la categoría está vacío');
    // Dedupe como en `createTipo`: si ya existe (sin importar mayúsculas), se
    // devuelve el existente en vez de crear otra variante.
    final filas = await _db.executeSql(
      'SELECT id FROM activos_categorias '
      'WHERE LOWER(TRIM(nombre)) = LOWER(TRIM(\$1)) LIMIT 1',
      params: [n],
    );
    if (filas.isNotEmpty) return filas.first['id'] as int;

    return _db.insert('activos_categorias', {
      'nombre': n,
      'color': color,
      'prefijo': (prefijo?.trim().isEmpty ?? true)
          ? prefijoDeCategoria(n)
          : prefijo,
      'activo': true,
    });
  }

  Future<void> updateCategoria(ActivosCategoria categoria) async {
    if (await existeCategoria(categoria.nombre,
        ignorarId: categoria.id)) {
      throw StateError('Ya existe otra categoría con ese nombre');
    }
    final map = categoria.toMap();
    final p = (map['prefijo'] as String?)?.trim();
    if (p == null || p.isEmpty) {
      map['prefijo'] = prefijoDeCategoria(categoria.nombre);
    }
    await _db.updateById('activos_categorias', categoria.id, map);
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

  /// ¿Existe otra categoría con ese nombre?
  ///
  /// `activos_categorias.nombre` es UNIQUE, pero la base no distingue mayúsculas,
  /// así que `Sillas` y `sillas` pueden convivir. La comparación ignora
  /// mayúsculas a propósito: la pregunta es "¿queda otra con este nombre?", y
  /// responder que no por una diferencia de capitalización deja justo el
  /// duplicado que se quería evitar. [ignorarId] deja pasar la propia categoría
  /// cuando lo que se está es renombrando.
  Future<bool> existeCategoria(String nombre, {int? ignorarId}) async {
    // `ignorarId` va dos veces como `$2` y `$3`, no repetido: el proxy traduce
    // `$N` a `%s` una vez por aparición, así que un `$2` repetido llega al
    // servidor como tres placeholders con dos parámetros y PostgreSQL responde
    // "the query has 3 placeholders but 2 parameters were passed". La consulta
    // directa desde Dart sí toleraría el `$2` repetido, por eso el bug no se
    // veía en las pruebas contra la base.
    final filas = await _db.executeSql(
      'SELECT 1 FROM activos_categorias '
      'WHERE LOWER(nombre) = LOWER(\$1) '
      'AND (\$2::int IS NULL OR id <> \$3) '
      'LIMIT 1',
      params: [nombre, ignorarId, ignorarId],
    );
    return filas.isNotEmpty;
  }

  // ---------------------------------------------------------------------
  // Estados (catálogo de las unidades)
  // ---------------------------------------------------------------------

  /// Estados activos del catálogo, en el orden de visualización.
  Future<List<String>> getEstados() async {
    final rows = await _db.fetchAll(
      'activos_estados',
      orderBy: 'orden, nombre',
      filters: {'activo': true},
    );
    return [for (final r in rows) r['nombre'] as String];
  }

  /// Da de alta un estado nuevo (o devuelve el nombre canónico si ya existe,
  /// sin importar mayúsculas). El nombre vuelve normalizado para poder
  /// seleccionarlo en el formulario.
  Future<String> createEstado(String nombre) async {
    final n = nombre.trim();
    if (n.isEmpty) throw ArgumentError('El nombre del estado está vacío');
    final filas = await _db.executeSql(
      'SELECT nombre FROM activos_estados '
      'WHERE lower(nombre) = lower(\$1) LIMIT 1',
      params: [n],
    );
    if (filas.isNotEmpty) return filas.first['nombre'] as String;
    await _db.insert('activos_estados', {
      'nombre': n,
      'orden': 100,
      'activo': true,
    });
    return n;
  }

  /// Desactiva un estado (no se borra: las unidades que lo usan lo conservan).
  Future<void> desactivarEstado(String nombre) {
    return _db.updateWhere(
      'activos_estados',
      {'nombre': nombre},
      {'activo': false},
    );
  }

  // ---------------------------------------------------------------------
  // Tipos (catálogo)
  // ---------------------------------------------------------------------

  /// Tipos activos de una categoría (o todos) con su conteo de unidades y el
  /// nombre de su categoría (para agrupar en la grilla raíz).
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
      condiciones.add('(LOWER(t.nombre) LIKE \$${i++} OR '
          'LOWER(COALESCE(t.grupo, \'\')) LIKE \$${i++} OR '
          'LOWER(COALESCE(t.modelo, \'\')) LIKE \$${i++})');
      params
        ..add('%$q%')
        ..add('%$q%')
        ..add('%$q%');
    }

    final rows = await _db.executeSql(
      'SELECT t.*, COUNT(a.id) AS unidades, '
      'COALESCE(c.nombre, \'Sin categoría\') AS categoria_nombre '
      'FROM activos_tipos t '
      'LEFT JOIN activos a ON a.tipo_id = t.id '
      'LEFT JOIN activos_categorias c ON c.id = t.categoria_id '
      'WHERE ${condiciones.join(' AND ')} '
      'GROUP BY t.id, c.nombre '
      'ORDER BY c.nombre, t.nombre',
      params: params,
    );
    return [
      for (final r in rows)
        {
          'tipo': ActivoTipo.fromMap(r),
          'unidades': (r['unidades'] as num?)?.toInt() ?? 0,
          'categoria_nombre':
              (r['categoria_nombre'] as String?) ?? 'Sin categoría',
        }
    ];
  }

  /// Crea un tipo, o devuelve el existente si ya hay uno con la misma
  /// categoría + grupo + nombre (sin importar mayúsculas ni espacios).
  ///
  /// Las escrituras canónicas de grupo/modelo ya registradas se reutilizan
  /// (televisores → Televisores) para no volver a partir el catálogo en
  /// variantes de capitalización.
  Future<int> createTipo(ActivoTipo tipo) async {
    final nombre = tipo.nombre.trim();
    if (nombre.isEmpty) {
      throw ArgumentError('El nombre del tipo no puede quedar vacío');
    }
    final grupo = (tipo.grupo ?? '').trim();
    final modelo = (tipo.modelo ?? '').trim();
    final grupoFinal = grupo.isEmpty ? '' : await _canonicoDe('grupo', grupo);
    final modeloFinal =
        modelo.isEmpty ? '' : await _canonicoDe('modelo', modelo);

    final rows = await _db.executeSql(
      'SELECT id FROM activos_tipos '
      'WHERE COALESCE(categoria_id, 0) = \$1 '
      'AND LOWER(TRIM(COALESCE(grupo, \'\'))) = LOWER(TRIM(\$2)) '
      'AND LOWER(TRIM(nombre)) = LOWER(TRIM(\$3)) LIMIT 1',
      params: [tipo.categoriaId ?? 0, grupoFinal, nombre],
    );
    if (rows.isNotEmpty) return rows.first['id'] as int;

    return _db.insert('activos_tipos', {
      'nombre': nombre,
      'grupo': grupoFinal.isEmpty ? null : grupoFinal,
      'modelo': modeloFinal.isEmpty ? null : modeloFinal,
      'categoria_id': tipo.categoriaId,
      'activo': tipo.activo ? 1 : 0,
    });
  }

  Future<void> updateTipo(int id, ActivoTipo tipo) async {
    final nombre = tipo.nombre.trim();
    if (nombre.isEmpty) {
      throw ArgumentError('El nombre del tipo no puede quedar vacío');
    }
    final grupo = (tipo.grupo ?? '').trim();
    final rows = await _db.executeSql(
      'SELECT id FROM activos_tipos '
      'WHERE id <> \$1 AND COALESCE(categoria_id, 0) = \$2 '
      'AND LOWER(TRIM(COALESCE(grupo, \'\'))) = LOWER(TRIM(\$3)) '
      'AND LOWER(TRIM(nombre)) = LOWER(TRIM(\$4)) LIMIT 1',
      params: [id, tipo.categoriaId ?? 0, grupo, nombre],
    );
    if (rows.isNotEmpty) {
      throw StateError('Ya existe otro tipo con el mismo nombre en este grupo');
    }
    await _db.updateById('activos_tipos', id, tipo.toMap());
  }

  /// La escritura canónica (menor id) de un grupo/modelo, para reutilizarla en
  /// vez de crear una variante de mayúsculas. Devuelve [valor] si no hay
  /// ninguna registrada todavía.
  Future<String> _canonicoDe(String col, String valor) async {
    final rows = await _db.executeSql(
      'SELECT $col FROM activos_tipos '
      'WHERE LOWER(TRIM(COALESCE($col, \'\'))) = LOWER(TRIM(\$1)) '
      'AND TRIM(COALESCE($col, \'\')) <> \'\' '
      'ORDER BY id LIMIT 1',
      params: [valor],
    );
    return rows.isEmpty ? valor : rows.first[col] as String;
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

  /// Fusiona [origenIds] en [destinoId]: mueve todas las unidades (activas e
  /// inactivas) de los tipos origen al tipo destino y elimina los tipos origen,
  /// que quedan vacíos.
  ///
  /// Se conservan las placas (`codigo`) de cada unidad: unificar el catálogo no
  /// debe renumerar inventario ya emitido/impreso, aunque la categoría del
  /// destino tenga otro prefijo. También se conservan ubicación, estado, valor,
  /// fecha y observaciones de cada unidad; lo único que cambia es su `tipo_id`.
  ///
  /// Todo corre en una transacción: la FK `activos.tipo_id` es ON DELETE
  /// RESTRICT, así que si el borrado fallara por alguna referencia, se revierte
  /// también el movimiento de unidades y el catálogo queda como estaba.
  /// Devuelve cuántas unidades se movieron.
  Future<int> mergeTipos(int destinoId, List<int> origenIds) async {
    final origenes = <int>{
      for (final id in origenIds)
        if (id != destinoId) id,
    }.toList();
    if (origenes.isEmpty) return 0;
    return _db.transaction<int>((tx) async {
      final movidas = await tx.executeCommand(
        'UPDATE activos SET tipo_id = \$1 WHERE tipo_id = ANY(\$2::int[])',
        params: [destinoId, origenes],
      );
      await tx.executeCommand(
        'DELETE FROM activos_tipos WHERE id = ANY(\$1::int[])',
        params: [origenes],
      );
      return movidas;
    });
  }

  // ---------------------------------------------------------------------
  // Unidades (activos físicos)
  // ---------------------------------------------------------------------

  /// Unidades de un tipo, con los campos del catálogo resueltos por JOIN.
  Future<List<Activo>> getUnidadesDeTipo(int tipoId, {String? search}) async {
    final q = search?.trim().toLowerCase();
    final list = q != null && q.isNotEmpty;
    final sql = 'SELECT $_colsActivo, '
        't.nombre AS tipo_nombre, t.grupo, t.modelo, t.categoria_id, '
        'COALESCE(c.nombre, \'Sin categoría\') AS categoria_nombre '
        'FROM activos a '
        'JOIN activos_tipos t ON t.id = a.tipo_id '
        'LEFT JOIN activos_categorias c ON c.id = t.categoria_id '
        'WHERE a.tipo_id = \$1'
        '${list ? ' AND (LOWER(COALESCE(a.ubicacion, \'\')) LIKE \$2 OR LOWER(COALESCE(a.observaciones, \'\')) LIKE \$2)' : ''} '
        'ORDER BY a.codigo';
    final rows = await _db.executeSql(
      sql,
      params: list ? [tipoId, '%$q%'] : [tipoId],
    );
    return rows.map(Activo.fromMap).toList();
  }

  /// ¿Ya existe una unidad activa de este tipo en esa ubicación?
  ///
  /// El ítem "¿agregar otra igual?" es una advertencia, no un bloqueo: dos
  /// unidades iguales en el mismo lugar pueden ser correctas (dos sillas
  /// idénticas en el comedor).
  Future<bool> existeUnidad(int tipoId, String ubicacion) async {
    final filas = await _db.executeSql(
      'SELECT 1 FROM activos '
      'WHERE tipo_id = \$1 AND COALESCE(ubicacion, \'\') = COALESCE(\$2, \'\') '
      'AND activo = TRUE LIMIT 1',
      params: [tipoId, ubicacion.trim()],
    );
    return filas.isNotEmpty;
  }

  /// Siguiente placa disponible para un prefijo, asignada de forma atómica.
  ///
  /// Formato `PREFIJO-NNNNN`. El `ON CONFLICT ... ultimo + 1` es el punto
  /// único donde el contador avanza, así que dos altas simultáneas no pueden
  /// emitir la misma placa.
  Future<String> nextCodigo(String prefijo) async {
    final p = prefijo.trim().toUpperCase();
    final filas = await _db.executeSql(
      'INSERT INTO activos_codigos (prefijo, ultimo) VALUES (\$1, 1) '
      'ON CONFLICT (prefijo) DO UPDATE SET ultimo = activos_codigos.ultimo + 1 '
      'RETURNING ultimo',
      params: [p],
    );
    final n = (filas.first['ultimo'] as num).toInt();
    return '$p-${n.toString().padLeft(5, '0')}';
  }

  /// Prefijo de la categoría del tipo (con 'ACT' de respaldo cuando el tipo no
  /// tiene categoría o la categoría no tiene prefijo).
  Future<String> _prefijoDeTipo(int tipoId) async {
    final filas = await _db.executeSql(
      'SELECT COALESCE(c.prefijo, \'\') AS prefijo '
      'FROM activos_tipos t '
      'LEFT JOIN activos_categorias c ON c.id = t.categoria_id '
      'WHERE t.id = \$1',
      params: [tipoId],
    );
    if (filas.isEmpty) return 'ACT';
    final p = (filas.first['prefijo'] as String?)?.trim();
    return (p == null || p.isEmpty) ? 'ACT' : p.toUpperCase();
  }

  /// Da de alta la unidad y le asigna la placa desde la categoría de su tipo.
  ///
  /// Devuelve el [Activo] persistido (con `id` y `codigo`) para que la
  /// interface pueda mostrar la placa recién emitida.
  Future<Activo> createActivo(Activo activo) async {
    final map = activo.toMap();
    final prefijo = await _prefijoDeTipo(activo.tipoId ?? 0);
    final codigo = await nextCodigo(prefijo);
    map['codigo'] = codigo;
    final id = await _db.insert('activos', map);
    return Activo.fromMap({
      ...map,
      'id': id,
      'codigo': codigo,
    });
  }

  Future<void> updateActivo(int id, Activo activo) async {
    final map = activo.toMap();
    if (activo.tipoId != null) {
      // Si cambia la categoría (y por tanto el prefijo de la placa), se emite
      // una placa nueva en vez de dejar la anterior desactualizada.
      final prefijo = await _prefijoDeTipo(activo.tipoId!);
      final filas = await _db.executeSql(
        'SELECT codigo FROM activos WHERE id = \$1',
        params: [id],
      );
      final codigo = filas.first['codigo'] as String?;
      final prefijoActual = (codigo == null || !codigo.contains('-'))
          ? null
          : codigo.split('-').first.trim().toUpperCase();
      if (prefijoActual != prefijo) {
        map['codigo'] = await nextCodigo(prefijo);
      }
    }
    await _db.updateById('activos', id, map);
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

  /// Renombra un valor de dimensión en todas las filas que lo usan.
  ///
  /// Si [hasta] ya existe, las dos filas quedan con el mismo valor: eso es justo
  /// lo que hace útil para corregir `hab01` contra `Hab01`.
  ///
  /// Para `estado` el valor no se toca fila por fila: se renombra el catálogo
  /// (`activos_estados`) y la FK con `ON UPDATE CASCADE` actualiza todas las
  /// unidades en un solo golpe.
  Future<void> renombrarValor(
      String columna, String desde, String hasta) async {
    final esEstado = columna == 'estado';
    final col = esEstado ? 'nombre' : columna;
    var destino = hasta;
    if ((columna == 'grupo' || columna == 'modelo') &&
        destino.trim().isNotEmpty) {
      destino = await _canonicoDe(columna, destino);
    }
    await _db.updateWhere(
      _tablaDeValor(columna),
      {col: desde},
      {col: destino},
    );
  }

  /// Le saca el valor a todas las filas que lo usan.
  ///
  /// Deja la columna en NULL, no borra la fila: quitar la ubicación de 10
  /// unidades no debería borrar 10 unidades del inventario. Para borrar
  /// unidades están los métodos de cada una. El estado no se puede quitar
  /// (las unidades siempre tienen uno); se desactiva en su catálogo.
  Future<void> quitarValor(String columna, String valor) {
    if (columna == 'estado') {
      throw ArgumentError(
          'El estado no se quita de las unidades; desactívalo en el catálogo');
    }
    return _db.updateWhere(
      _tablaDeValor(columna),
      {columna: valor},
      {columna: null},
    );
  }

  /// En qué tabla vive cada dimensión.
  ///
  /// El nombre de la columna va interpolado en el SQL (los placeholders no
  /// cubren identificadores), así que el `switch` es la lista cerrada que evita
  /// que un valor raro llegue a la consulta.
  String _tablaDeValor(String columna) {
    switch (columna) {
      case 'ubicacion':
        return 'activos';
      case 'estado':
        return 'activos_estados';
      case 'grupo':
      case 'modelo':
        return 'activos_tipos';
    }
    throw ArgumentError('Dimensión sin valores editables: $columna');
  }

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
  /// `estado` en las unidades. El estado se lee del catálogo `activos_estados`
  /// (incluye estados sin unidades, en el orden de visualización).
  Future<List<Map<String, dynamic>>> getValoresConConteo(String columna) async {
    if (columna == 'estado') {
      return _db.executeSql(
        'SELECT e.nombre AS valor, COUNT(a.id) AS n '
        'FROM activos_estados e '
        'LEFT JOIN activos a ON a.estado = e.nombre AND a.activo = TRUE '
        'WHERE e.activo = TRUE '
        'GROUP BY e.nombre, e.orden ORDER BY e.orden, e.nombre',
      );
    }
    if (columna == 'grupo' || columna == 'modelo') {
      return _db.executeSql(
        'SELECT t.$columna AS valor, COUNT(a.id) AS n '
        'FROM activos_tipos t '
        'LEFT JOIN activos a ON a.tipo_id = t.id AND a.activo = TRUE '
        'WHERE t.$columna IS NOT NULL AND t.$columna <> \'\' '
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
    if (grupo != null && grupo.trim().isNotEmpty) {
      add('t.grupo = \$${i++}', grupo.trim());
    }
    if (modelo != null && modelo.trim().isNotEmpty) {
      add('t.modelo = \$${i++}', modelo.trim());
    }
    if (ubicacion != null && ubicacion.trim().isNotEmpty) {
      add('a.ubicacion = \$${i++}', ubicacion.trim());
    }
    if (estado != null && estado.trim().isNotEmpty) {
      add('a.estado = \$${i++}', estado.trim());
    }

    final sql = 'SELECT $_colsActivo, '
        't.nombre AS tipo_nombre, t.grupo, t.modelo, t.categoria_id, '
        'COALESCE(c.nombre, \'Sin categoría\') AS categoria_nombre '
        'FROM activos a '
        'JOIN activos_tipos t ON t.id = a.tipo_id '
        'LEFT JOIN activos_categorias c ON c.id = t.categoria_id '
        'WHERE ${condiciones.isEmpty ? 'TRUE' : condiciones.join(' AND ')} '
        'ORDER BY categoria_nombre, t.grupo, t.nombre, a.codigo';
    return _db.executeSql(sql, params: params);
  }

  // ---------------------------------------------------------------------
  // Exportación (Excel)
  // ---------------------------------------------------------------------

  /// Todas las unidades (incluye desactivadas) con datos de su tipo y
  /// categoría resueltos por JOIN, en el mismo orden que la pantalla.
  Future<List<Map<String, dynamic>>> getActivosParaExportar() async {
    return _db.executeSql(
      'SELECT a.*, t.nombre, t.grupo, t.modelo, t.categoria_id, '
      'COALESCE(c.nombre, \'Sin categoría\') AS categoria_nombre '
      'FROM activos a '
      'JOIN activos_tipos t ON t.id = a.tipo_id '
      'LEFT JOIN activos_categorias c ON c.id = t.categoria_id '
      'ORDER BY categoria_nombre, t.grupo, t.nombre, a.codigo',
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
