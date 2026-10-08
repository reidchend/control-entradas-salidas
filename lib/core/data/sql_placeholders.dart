/// Normalización de placeholders `$n` para las sentencias SQL **raw**.
///
/// El cliente tipado [PgClient] ya renumera sus placeholders en `_bindPlan`,
/// pero el SQL que llega crudo (`PostgresService.executeSql` /
/// `executeCommand`) no pasaba por ahí. Eso deja un hueco según el driver:
///
/// - **Nativo** ([NativeSqlSession], `package:postgres`): resuelve `$n` por
///   número, así que un `$1` repetido usa el mismo valor en cada aparición.
/// - **Proxy** ([HttpSqlSession] → `tool/server.py`): traduce cada aparición de
///   `$n` a `%s` y psycopg resuelve por **posición**. Un `$n` repetido genera
///   más marcadores que parámetros y psycopg revienta con
///   `the query has N placeholders but M parameters were passed`.
///
/// [normalizarPlaceholders] cierra el hueco: renumera cada aparición a un número
/// propio en orden textual (1..N) y devuelve los parámetros en ese mismo orden.
/// Así ambos drivers ven exactamente lo mismo y un `$n` repetido deja de romper
/// en el proxy. Sin placeholders, o con números ya únicos y en orden, el SQL y
/// los parámetros salen intactos.
({String sql, List<Object?> params}) normalizarPlaceholders(
  String sql,
  List<Object?> params,
) {
  final re = RegExp(r'\$(\d+)');
  if (!re.hasMatch(sql)) return (sql: sql, params: params);

  final out = StringBuffer();
  final outParams = <Object?>[];
  var last = 0;
  for (final m in re.allMatches(sql)) {
    final idx = int.parse(m.group(1)!);
    out.write(sql.substring(last, m.start));
    // Cada aparición recibe el siguiente número consecutivo.
    outParams.add(idx >= 1 && idx <= params.length ? params[idx - 1] : null);
    out.write('\$${outParams.length}');
    last = m.end;
  }
  out.write(sql.substring(last));
  return (sql: out.toString(), params: outParams);
}