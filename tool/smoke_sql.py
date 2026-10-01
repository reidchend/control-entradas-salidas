"""Smoke test de la ruta SQL: app -> tool/server.py -> PostgreSQL.

Ejecuta lo mismo que HttpSqlSession hace en cada request (`POST /proxy-sql`
con `action: execute`) y verifica los puntos donde los bugs de agosto/2026
aparecieron:

1. Conectividad: el proxy responde y devuelve filas.
2. Seguridad: rechaza un token equivocado con 401.
3. Orden de los parametros en un `UPDATE` con condiciones. Los filtros se
   registran antes que los SET, asi que sin renumerar el texto sale
   `SET col = $2 WHERE id = $1` y cada valor cae en la columna de al lado.
4. Placeholder repetido. `convert_placeholders` convierte cada aparicion de
   `$n` en un `%s`, asi que un `$1` repetido deja mas `%s` que parametros y
   psycopg revienta la consulta.
5. La consulta real de `buscarProductos`, que repetia `$1` en dos `ILIKE`.
6. Las consultas del catalogo del POS. `categorias.activo`,
   `categorias.visible_en_pos` y `productos.activo` son **boolean** en
   PostgreSQL, pero el repositorio los filtraba con `.eq(campo, 1)`, que
   produce `boolean = smallint`. Como `_cargarCategorias` no tiene try/catch,
   el error dejaba el catalogo entero vacio al abrir una mesa o habitacion.
7. Lint estatico: ningun filtro `.eq()` compara una columna **boolean** con un
   numero. Sale de `information_schema`, asi que no hay lista de columnas que se
   pueda quedar vieja en silencio.

Replica el algoritmo de `_bindPlan` de lib/core/data/pg_client.dart para no
necesitar el SDK de Flutter, que no esta instalado en esta maquina.

Al terminar borra sus tablas. Sale con codigo 1 si algo falla.

Uso:
    tool\\venv\\Scripts\\python.exe tool\\smoke_sql.py
    (con tool/server.py corriendo en otro proceso)
"""
import json
import os
import re
import sys
import urllib.error
import urllib.request

try:
    import psycopg
except ImportError:
    sys.exit("Falta psycopg. Instalalo con: pip install -r tool/requirements.txt")

PROXY = os.environ.get("PROXY_URL", "http://127.0.0.1:8123") + "/proxy-sql"
PLACEHOLDER_RE = re.compile(r"(\$\d+)")
RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

TABLA_PRUEBA = "smoke_sql_params"
FALLOS = []


# --------------------------------------------------------------------- utils


def leer_env_local():
    env_path = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".env.local"
    )
    values = {}
    if os.path.exists(env_path):
        with open(env_path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, _, value = line.partition("=")
                values[key.strip()] = value.strip().strip("'").strip('"')
    return values


def db_url(env):
    for key in ("DATABASE_URL_UNPOOLED", "DATABASE_URL"):
        if env.get(key):
            return env[key]
    return None


def proxy(token, sql, params=None, timeout=60):
    """POST a /proxy-sql, identico a HttpSqlSession.execute."""
    body = json.dumps({"action": "execute", "sql": sql, "params": params or []})
    req = urllib.request.Request(
        PROXY,
        data=body.encode("utf-8"),
        headers={"Content-Type": "application/json", "X-Proxy-Token": token},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as res:
            return res.status, json.loads(res.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        cuerpo = e.read().decode("utf-8", "replace")
        try:
            return e.code, json.loads(cuerpo)
        except json.JSONDecodeError:
            return e.code, {"error": cuerpo}
    except urllib.error.URLError as e:
        return 0, {"error": str(e.reason)}


def reportar(titulo, ok, detalle=""):
    marca = "OK " if ok else "FALLA"
    print(f"  [{marca}] {titulo}")
    if detalle:
        for linea in detalle.splitlines():
            print(f"         {linea}")
    if not ok:
        FALLOS.append(titulo)
    return ok


# ------------------------------------------------- replica de _bindPlan (Dart)


def bind_plan(sql, bindings):
    """Port de `_bindPlan` de lib/core/data/pg_client.dart.

    El driver Dart registra los placeholders en orden de construccion, que no
    es el orden del texto. Esta funcion renumera por orden de aparicion y
    devuelve los parametros en ese mismo orden, dando a cada aparicion un
    numero propio.

    No escapa los `%` literales: eso lo hace `convert_placeholders` del lado del
    servidor, sobre el SQL ya renumerado.
    """
    # PLACEHOLDER_RE tiene grupo de captura, asi que `split` devuelve los
    # `$n` intercalados: indice par = texto, impar = placeholder.
    partes = PLACEHOLDER_RE.split(sql)
    if len(partes) == 1:
        return sql, []

    numeros, i = [], 1
    for original in partes[1::2]:
        numeros.append(i)
        i += 1

    salida, params, i = [], [], 0
    for parte in partes:
        if PLACEHOLDER_RE.fullmatch(parte):
            salida.append(f"${numeros[i]}")
            params.append(bindings[int(parte[1:]) - 1])
            i += 1
        else:
            salida.append(parte)
    return "".join(salida), params


def construir_update(tabla, filtros, sets):
    """SQL y bindings tal como los arma PgQueryBuilder.

    Los filtros del WHERE se registran primero (por eso `eq`/`inFilter` se
    llaman antes de que el builder ejecute el UPDATE) y los SET despues, asi
    que los numeros del SET quedan mas altos y aparecen antes en el texto.
    """
    bindings, cond, sets_sql, seq = [], [], [], 0
    for columna, valores in filtros:
        numeros = []
        for valor in valores:
            seq += 1
            numeros.append(seq)
            bindings.append(valor)
        cond.append(f"{columna} IN ({', '.join(f'${n}' for n in numeros)})")
    for columna, valor in sets:
        seq += 1
        sets_sql.append(f"{columna} = ${seq}")
        bindings.append(valor)
    where = " AND ".join(cond)
    return f"UPDATE {tabla} SET {', '.join(sets_sql)} WHERE {where}", bindings


# -------------------------------------------------------------------- pruebas


def prueba_conectividad(token):
    status, res = proxy(token, "SELECT 1 AS probe", [])
    return reportar(
        "el proxy responde y devuelve filas",
        status == 200 and res.get("rows") == [{"probe": 1}],
        f"status={status} rows={res.get('rows')}",
    )


def prueba_token(token):
    status, _ = proxy("token-incorrecto", "SELECT 1", [])
    return reportar(
        "rechaza un token equivocado",
        status in (401, 403),
        f"status={status} (esperado 401 o 403)",
    )


def prueba_orden_update(conn, token):
    """El UPDATE de `_vincularMovimientos`: SET factura_id, WHERE id IN."""
    movimientos, factura_id = [45, 46], 12

    sql_crudo, bindings = construir_update(
        TABLA_PRUEBA, [("id", movimientos)], [("factura_id", factura_id)]
    )
    sql, params = bind_plan(sql_crudo, bindings)

    with conn.cursor() as cur:
        cur.execute(f"DROP TABLE IF EXISTS {TABLA_PRUEBA}")
        cur.execute(
            f"CREATE TABLE {TABLA_PRUEBA} (id BIGINT PRIMARY KEY, factura_id BIGINT)"
        )
        # 12 es el id de la factura: un descuido lo escribe como movimiento.
        for id_ in (12, 45, 46, 99):
            cur.execute(f"INSERT INTO {TABLA_PRUEBA} VALUES (%s, NULL)", (id_,))
    conn.commit()

    status, res = proxy(token, sql, params)
    with conn.cursor() as cur:
        cur.execute(f"SELECT id, factura_id FROM {TABLA_PRUEBA} ORDER BY id")
        filas = {r[0]: r[1] for r in cur.fetchall()}

    detail = f"sql={sql_crudo}\nparams={params}\nstatus={status} affected={res.get('affectedRows')}\ntabla={filas}"
    return reportar(
        "el UPDATE con WHERE no cruza los valores",
        status == 200 and filas.get(45) == 12 and filas.get(46) == 12 and filas.get(12) is None,
        detail,
    )


def prueba_placeholder_repetido(conn, token):
    """Un `$1` en dos columnas: el proxy lo traduce a dos `%s`."""
    conn_placeholder = "%cafe%"
    # SQL tal como estaba antes del arreglo, con `$1` repetido.
    sql_malo = f"SELECT id FROM {TABLA_PRUEBA} WHERE id = $1 OR id = $1"
    status_malo, res_malo = proxy(token, sql_malo, [45])

    status_ok, res_ok = proxy(token, f"SELECT id FROM {TABLA_PRUEBA} WHERE id = $1 OR id = $2", [45, 45])

    detalle = (
        f"con $1 repetido  -> status={status_malo} error={res_malo.get('error', '-')}\n"
        f"con $1 y $2      -> status={status_ok} rows={res_ok.get('rows')}"
    )
    # La version repetida tiene que fallar (documenta el limite); la corregida
    # tiene que responder.
    return reportar(
        "un placeholder repetido falla; con numeros separados funciona",
        status_malo != 200 and status_ok == 200 and len(res_ok.get("rows", [])) == 1,
        detalle,
    )


def prueba_buscar_productos(conn, token):
    """La consulta de `ReportesRepository.buscarProductos`."""
    with conn.cursor() as cur:
        cur.execute("SELECT count(*) FROM productos")
        if cur.fetchone()[0] == 0:
            return reportar(
                "buscarProductos (sin datos de prueba)", True, "tabla productos vacia, omitida"
            )

    patron = "%cafe%"
    sql, params = bind_plan(
        "SELECT id, nombre, codigo FROM productos "
        "WHERE activo = true AND (nombre ILIKE $1 OR codigo ILIKE $1) "
        "ORDER BY nombre LIMIT $2",
        [patron, 20],
    )
    status, res = proxy(token, sql, params)
    return reportar(
        "buscarProducts con el patron en dos columnas",
        status == 200,
        f"status={status} rows={len(res.get('rows', []))} error={res.get('error', '-')}",
    )


def prueba_catalogo_pos(token):
    """Las consultas de `getCategoriasPos` y `getProductosPos`.

    Se mandan las dos formas a proposito: la que usa numeros tiene que fallar y
    la que usa boolean tiene que responder. Asi queda documentado en el test por
    que el valor importa, y no solo que "anda".
    """
    casos = [
        (
            "categorias del POS",
            "SELECT id, nombre FROM categorias WHERE activo = $1 AND visible_en_pos = $2 ORDER BY nombre",
            [True, True],
        ),
        (
            "productos de venta del POS",
            "SELECT id, nombre FROM productos WHERE activo = $1 AND tipo = $2 ORDER BY nombre",
            [True, "Productos para la venta"],
        ),
        (
            "subcategorias de platos",
            "SELECT id, nombre FROM platos_categorias WHERE activo = $1 AND categoria_padre_id = $2 ORDER BY nombre",
            [1, 5],
        ),
    ]

    detalles, todo_ok = [], True
    for etiqueta, sql, params in casos:
        status, res = proxy(token, sql, params)
        filas = res.get("rows") or []
        ok = status == 200
        todo_ok &= ok
        detalles.append(f"{etiqueta}: status={status} filas={len(filas)}")

    # La forma con numeros tiene que ser la que falla, si no el chequeo de arriba
    # no probaria nada (pasaria igual con cualquier valor).
    status_malo, res_malo = proxy(
        token,
        "SELECT id FROM categorias WHERE activo = $1 AND visible_en_pos = $2",
        [1, 1],
    )
    error_malo = (res_malo.get("error") or "").replace("\n", " ")[:90]
    details_ok = status_malo != 200
    detalles.append(
        f"con 1 en vez de true: status={status_malo} error={error_malo or '-'}"
    )

    return reportar(
        "el catalogo del POS filtra booleanos con true/false, no con 1/0",
        todo_ok and details_ok,
        "\n".join(detalles),
    )


def prueba_limpieza(conn):
    with conn.cursor() as cur:
        cur.execute(
            "SELECT table_name FROM information_schema.tables "
            "WHERE table_schema = 'public' AND table_name LIKE 'diag%'"
        )
        sobrantes = [r[0] for r in cur.fetchall()]
    return reportar("no quedan tablas de diagnostico", not sobrantes, f"sobrantes={sobrantes}")


# ------------------------------------------------- lint estatico del SQL Dart
#
# El SQL crudo que la app manda al proxy no pasa por `_bindPlan`, asi que un
# `$n` repetido se escapa del renumerado y revienta la consulta. Esta parte no
# necesita base: recorre lib/ y avisa antes de que llegue a produccion.

LLAMADAS_SQL = ("executeSql", "executeCommand")


def extraer_argumentos(texto, inicio):
    """Bloque de argumentos de una llamada que abre en [inicio]."""
    profundidad, i, n = 1, inicio, len(texto)
    while i < n and profundidad > 0:
        c = texto[i]
        if c in "([{":
            profundidad += 1
        elif c in ")]}":
            profundidad -= 1
        elif c == "'" and texto[i:i + 3] == "'''":
            fin = texto.find("'''", i + 3)
            if fin == -1:
                return None
            i = fin + 3
            continue
        elif c in "'\"":
            i += 1
            while i < n:
                if texto[i] == "\\":
                    i += 2
                    continue
                if texto[i] == c:
                    break
                i += 1
        i += 1
    return texto[inicio:i - 1] if profundidad == 0 else None


def prueba_placeholders_en_dart():
    repetidos, revisados = [], 0
    for carpeta, _, nombres in os.walk(os.path.join(RAIZ, "lib")):
        for nombre in nombres:
            if not nombre.endswith(".dart"):
                continue
            ruta = os.path.join(carpeta, nombre)
            with open(ruta, encoding="utf-8") as fh:
                texto = fh.read()
            for func in LLAMADAS_SQL:
                # Sin el punto en el lookbehind: los call sites reales son
                # `_db.executeSql(...)`.
                for m in re.finditer(rf"(?<![\w]){func}\s*\(", texto):
                    bloque = extraer_argumentos(texto, m.end())
                    if not bloque:
                        continue
                    literales = re.findall(r"'''(.*?)'''|'([^']*)'", bloque, re.S)
                    sql = "".join(grupo[0] or grupo[1] for grupo in literales)
                    if "$" not in sql:
                        continue
                    revisados += 1
                    numeros = PLACEHOLDER_RE.findall(sql)
                    malos = sorted({x for x in numeros if numeros.count(x) > 1},
                                   key=int)
                    if malos:
                        linea = texto[:m.start()].count("\n") + 1
                        repetidos.append(
                            f"{os.path.relpath(ruta, RAIZ)}:{linea} -> "
                            f"${', $'.join(malos)}"
                        )

    detalle = f"SQL crudo revisados: {revisados}"
    if repetidos:
        detalle += "\n" + "\n".join(repetidos)
        detalle += "\nRepetir un $n rompe el proxy: usar numeros separados."
    return reportar(
        "ningun SQL crudo repite un placeholder", not repetidos, detalle
    )


# ------------------------------------------- lint de booleanos con numeros
#
# En PostgreSQL `boolean = integer` no existe: da error 42883. El driver de
# Dart manda el valor tal cual, asi que `.eq('activo', 1)` contra una columna
# boolean revienta la consulta en tiempo de ejecucion, no al compilar.
#
# Que la columna sea boolean o integer se decide mirando `information_schema`,
# no una lista escrita a mano: las tablas `pos_*` y `platos*` tienen `activo`
# integer y `categorias`/`productos` lo tienen boolean, asi que la misma
# llamada `.eq('activo', 1)` es correcta en una y incorrecta en otra.

# `X.eq('col', 1)` / `.eq('col', 0)`. El segundo grupo acepta tambien `1.0`.
EQ_NUMERICO_RE = re.compile(
    r"""\.\s*(?:eq|neq|lt|gt|lte|gte|inFilter|notInFilter)\s*\(\s*['"](\w+)['"]\s*,\s*(\d+(?:\.\d+)?)\b"""
)

# Asignacion que guarda el builder: `var query = _db.client.from('x').select();`
DESDE_RE = re.compile(r"""from\(\s*['"](\w+)['"]\s*\)""")

# Un `;` o una llave abre/cierra un ambito: corta la busqueda hacia atras.
LIMITE_RE = re.compile(r"[;{}]")

# `q = _db.client.from('x')...` -> `q` es el builder de la tabla `x`.
VARIABLE_RE = re.compile(
    r"""([A-Za-z_]\w*)\s*=\s*[^;]*?from\(\s*['"](\w+)['"]\s*\)"""
)

# El identificador del que cuelga la llamada: el final de `... q.eq` o `... .eq`.
COLGANDO_RE = re.compile(r"([A-Za-z_]\w*)\s*\.?\s*$")


def columnas_booleanas(conn):
    """`{tabla: {columnas}}` de todas las columnas boolean del schema public."""
    with conn.cursor() as cur:
        cur.execute(
            "SELECT table_name, column_name FROM information_schema.columns "
            "WHERE table_schema = 'public' AND data_type = 'boolean'"
        )
        tablas = {}
        for tabla, columna in cur.fetchall():
            tablas.setdefault(tabla, set()).add(columna)
    return tablas


def indexar_builders(texto):
    """`{variable: tabla}` para las asignaciones `q = ...from('x')`."""
    return {m.group(1): m.group(2) for m in VARIABLE_RE.finditer(texto)}


def resolver_tabla(texto, hasta, variables):
    """De que tabla es el builder que se esta usando en la posicion [hasta].

    Hay dos formas en el codigo y las dos aparecen:

        _db.client.from('x').select().eq('activo', true)   # cadena
        var q = _db.client.from('x').select();
        q = q.eq('activo', 1);                            # variable

    Se resuelve mirando hacia atras hasta el ultimo `;`, `{` o `}`:

    - Si en ese tramo hay un `from('x')`, esa es la tabla (forma de cadena).
    - Si no, se toma el identificador del que cuelga la llamada y se busca en el
      mapa de variables (forma con variable).
    """
    limites = [m.start() for m in LIMITE_RE.finditer(texto, 0, hasta)]
    inicio = (limites[-1] + 1) if limites else 0
    tramo = texto[inicio:hasta]

    for m in DESDE_RE.finditer(texto, inicio, hasta):
        return m.group(1)

    colgando = COLGANDO_RE.search(tramo)
    if colgando:
        return variables.get(colgando.group(1))
    return None


def prueba_booleanos_en_dart(conn):
    """Ningun `.eq()` numérico sobre una columna boolean."""
    tablas = columnas_booleanas(conn)
    if not tablas:
        return reportar(
            "columnas boolean detectadas", False, "information_schema no devolvio ninguna"
        )

    malos, revisados = [], 0
    for carpeta, _, nombres in os.walk(os.path.join(RAIZ, "lib")):
        for nombre in nombres:
            if not nombre.endswith(".dart"):
                continue
            ruta = os.path.join(carpeta, nombre)
            with open(ruta, encoding="utf-8") as fh:
                texto = fh.read()

            variables = indexar_builders(texto)
            for m in EQ_NUMERICO_RE.finditer(texto):
                columna, valor = m.group(1), m.group(2)
                tabla = resolver_tabla(texto, m.start(), variables)
                if tabla is None:
                    continue
                if columna not in tablas.get(tabla, ()):
                    continue
                revisados += 1
                linea = texto[:m.start()].count("\n") + 1
                malos.append(
                    f"{os.path.relpath(ruta, RAIZ)}:{linea} -> "
                    f"{tabla}.{columna} = {valor} (boolean, usar true/false)"
                )

    total = sum(len(c) for c in tablas.values())
    detalle = (
        f"columnas boolean en el esquema: {total} en {len(tablas)} tablas; "
        f"filtros numericos sobre ellas revisados: {revisados}"
    )
    if malos:
        detalle += "\n" + "\n".join(malos)
        detalle += "\nPostgreSQL rechaza `boolean = integer` (42883)."
    return reportar(
        "ningun filtro numerico compara una columna boolean", not malos, detalle
    )


def main():
    env = leer_env_local()
    token = env.get("PROXY_SQL_TOKEN")
    url = db_url(env)
    if not token:
        sys.exit("Falta PROXY_SQL_TOKEN en .env.local")
    if not url:
        sys.exit("Falta DATABASE_URL en .env.local")

    print(f"Proxy: {PROXY}\n")
    conn = psycopg.connect(url, prepare_threshold=None)
    conn.autocommit = True
    try:
        prueba_conectividad(token)
        prueba_token(token)
        prueba_orden_update(conn, token)
        prueba_placeholder_repetido(conn, token)
        prueba_buscar_productos(conn, token)
        prueba_catalogo_pos(token)
        with conn.cursor() as cur:
            cur.execute(f"DROP TABLE IF EXISTS {TABLA_PRUEBA}")
        prueba_limpieza(conn)
        prueba_booleanos_en_dart(conn)
    finally:
        conn.close()

    # No necesita la base, asi que va aparte del `try`.
    prueba_placeholders_en_dart()

    print()
    if FALLOS:
        print(f"{len(FALLOS)} prueba(s) fallaron:")
        for f in FALLOS:
            print(f"  - {f}")
        return 1
    print("Todo OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
