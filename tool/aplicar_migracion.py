"""Aplica las migraciones de hosteleria UNA POR UNA, con verificacion.

Cada migracion corre dentro de su propia transaccion: si la verificacion falla,
se hace ROLLBACK y el script se detiene. Las migraciones traen su propio
BEGIN/COMMIT, asi que se los quita para que la transaccion la maneje el script.

Uso:
    tool\\venv\\Scripts\\python.exe tool\\aplicar_migracion.py <numero>
    tool\\venv\\Scripts\\python.exe tool\\aplicar_migracion.py todas
"""
import os
import re
import sys

import psycopg

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MIG_DIR = os.path.join(RAIZ, "supabase", "migrations")

# En orden. El orden importa: M3 altera tablas que crea M1, y M4 renombra lo
# que crea M3 y lo que ya existia.
MIGRACIONES = [
    (1, "20261002000000_hosteleria.sql"),
    (2, "20261002010000_usuarios_centrales.sql"),
    (3, "20261002020000_hosteleria_checkin.sql"),
    (4, "20261002030000_habitaciones_estados_op.sql"),
    (5, "20261004090000_movimientos_fecha_traslado.sql"),
]


def leer_env():
    v = {}
    with open(os.path.join(RAIZ, ".env.local"), encoding="utf-8") as fh:
        for linea in fh:
            linea = linea.strip()
            if not linea or linea.startswith("#") or "=" not in linea:
                continue
            k, _, val = linea.partition("=")
            v[k.strip()] = val.strip().strip("'").strip('"')
    return v


def quitar_transaccion(sql):
    """Saca el BEGIN/COMMIT propio de la migracion."""
    limpio = re.sub(r"^\s*BEGIN\s*;\s*$", "", sql, flags=re.M | re.I)
    limpio = re.sub(r"^\s*COMMIT\s*;\s*$", "", limpio, flags=re.M | re.I)
    return limpio


class Chequeos:
    def __init__(self, conn):
        self.c = conn
        self.fallos = []
        self.ok = 0

    def _cualquiera(self, nombres):
        """Primer nombre de la lista que exista como tabla, o None.

        Necesario porque la migracion 4 renombra pos_habitaciones y
        pos_tipos_habitacion: un chequeo de la migracion 1 o 3 escrito con
        el nombre viejo daria falso negativo al correr 'estado' con las 4 ya
        aplicadas.
        """
        r = self.c.execute(
            "SELECT name FROM unnest(%s::text[]) AS name "
            "WHERE to_regclass('public.' || name) IS NOT NULL LIMIT 1",
            (list(nombres),),
        ).fetchone()
        return r[0] if r else None

    def tabla(self, nombre, debe_existir=True):
        nombres = [nombre] if isinstance(nombre, str) else list(nombre)
        r = self._cualquiera(nombres)
        bien = bool(r) == debe_existir
        etiqueta = " o ".join(nombres)
        if bien:
            self.ok += 1
            estado = r if r else "-"
            print(f"  [OK   ] {etiqueta:32} {estado}")
        else:
            self.fallos.append(f"{etiqueta} {'deberia existir' if debe_existir else 'no deberia existir'}")
            print(f"  [FALLA] {etiqueta:32} {'EXISTE (no deberia)' if r else 'FALTA'}")
        return bool(r)

    def columna(self, tabla, col, tipo_esperado=None):
        # `tabla` puede ser una lista de nombres equivalentes (ver _cualquiera).
        tablas = [tabla] if isinstance(tabla, str) else list(tabla)
        real = self._cualquiera(tablas)
        if real is None:
            self.fallos.append(f"{' o '.join(tablas)} no existe, no se puede leer {col}")
            print(f"  [FALLA] {' o '.join(tablas)}.{col:20} NO EXISTE LA TABLA")
            return
        r = self.c.execute(
            "SELECT data_type FROM information_schema.columns "
            "WHERE table_schema='public' AND table_name=%s AND column_name=%s",
            (real, col),
        ).fetchone()
        if r is None:
            self.fallos.append(f"{real}.{col} falta")
            print(f"  [FALLA] {real}.{col:26} FALTA")
            return
        if tipo_esperado and r[0] != tipo_esperado:
            self.fallos.append(f"{real}.{col} es {r[0]}, se esperaba {tipo_esperado}")
            print(f"  [FALLA] {real}.{col:26} es {r[0]}, se esperaba {tipo_esperado}")
        else:
            self.ok += 1
            print(f"  [OK   ] {real}.{col:26} {r[0]}")

    def trigger(self, nombre, tabla):
        """`tabla` puede ser una lista: el trigger se busca en cualquiera.

        Hace falta porque la migracion 4 renombra pos_habitaciones y
        pos_tipos_habitacion, y el trigger conserva su nombre viejo pero
        queda sobre la tabla nueva. Asi el chequeo sirve durante la secuencia
        y despues de terminarla.
        """
        tablas = [tabla] if isinstance(tabla, str) else list(tabla)
        r = self.c.execute(
            "SELECT c.relname FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid "
            "WHERE t.tgname=%s AND c.relname = ANY(%s) AND NOT t.tgisinternal",
            (nombre, tablas),
        ).fetchone()
        real = r[0] if r else None
        if real:
            self.ok += 1
            print(f"  [OK   ] trigger {nombre} sobre {real}")
        else:
            self.fallos.append(f"falta el trigger {nombre} sobre {' o '.join(tablas)}")
            print(f"  [FALLA] falta el trigger {nombre} sobre {' o '.join(tablas)}")

    def indice(self, nombre):
        r = self.c.execute(
            "SELECT COUNT(*) FROM pg_class WHERE relname=%s AND relkind='i'", (nombre,)
        ).fetchone()[0]
        if r:
            self.ok += 1
            print(f"  [OK   ] indice {nombre}")
        else:
            self.fallos.append(f"falta el indice {nombre}")
            print(f"  [FALLA] falta el indice {nombre}")

    def constraint(self, nombre):
        r = c.execute(
            "SELECT COUNT(*) FROM pg_constraint WHERE conname=%s", (nombre,)
        ).fetchone()[0]
        return r

    def filas(self, etiqueta, sql, minimo, maximo=None):
        n = self.c.execute(sql).fetchone()[0]
        bien = n >= minimo and (maximo is None or n <= maximo)
        rango = f">= {minimo}" if maximo is None else f"entre {minimo} y {maximo}"
        if bien:
            self.ok += 1
            print(f"  [OK   ] {etiqueta:32} {n} filas ({rango})")
        else:
            self.fallos.append(f"{etiqueta}: {n} filas, se esperaba {rango}")
            print(f"  [FALLA] {etiqueta:32} {n} filas (se esperaba {rango})")

    def fk_apunta(self, etiqueta, fk_tabla, fk_col, esperado):
        """`esperado` puede ser una lista: vale cualquiera de esos nombres.

        Una FK sigue al RENAME de la tabla a la que apunta, asi que el mismo
        chequeo tiene que servir antes y despues de la migracion 4.
        """
        r = self.c.execute(
            "SELECT c.relname FROM pg_constraint con "
            "JOIN pg_class c ON c.oid=con.confrelid "
            "JOIN pg_attribute a ON a.attrelid=con.conrelid AND a.attnum=con.conkey[1] "
            "WHERE con.contype='f' AND con.conrelid=%s::regclass AND a.attname=%s",
            (fk_tabla, fk_col),
        ).fetchone()
        real = r[0] if r else None
        aceptados = [esperado] if isinstance(esperado, str) else list(esperado)
        if real in aceptados:
            self.ok += 1
            print(f"  [OK   ] {etiqueta:32} {fk_tabla}.{fk_col} -> {real}")
        else:
            lista = " o ".join(aceptados)
            self.fallos.append(f"{fk_tabla}.{fk_col} apunta a {real}, se esperaba {lista}")
            print(f"  [FALLA] {etiqueta:32} {fk_tabla}.{fk_col} -> {real}, esperaba {lista}")


def verificar_1(ch):
    print("  -- tablas de hosteleria --")
    ch.tabla("hosteleria_huespedes")
    ch.tabla("hosteleria_reservas")
    print("  -- columnas --")
    for col in ("id", "nombre", "cedula", "telefono", "correo", "notas", "creado_en", "updated_at"):
        ch.columna("hosteleria_huespedes", col)
    for col in ("id", "habitacion_id", "huesped_id", "fecha_inicio", "fecha_fin", "estado"):
        ch.columna("hosteleria_reservas", col)
    print("  -- triggers e indices --")
    ch.trigger("trg_hosteleria_huespedes_updated_at", "hosteleria_huespedes")
    ch.trigger("trg_hosteleria_reservas_updated_at", "hosteleria_reservas")
    ch.indice("idx_hosteleria_reservas_habitacion")
    ch.indice("idx_hosteleria_reservas_estado")
    print("  -- FK --")
    ch.fk_apunta("reservas -> habitacion", "hosteleria_reservas", "habitacion_id",
                 ["pos_habitaciones", "habitaciones"])
    ch.fk_apunta("reservas -> huesped", "hosteleria_reservas", "huesped_id", "hosteleria_huespedes")


def verificar_2(ch):
    print("  -- directorio central --")
    ch.tabla("usuarios")
    ch.tabla("pos_usuarios", debe_existir=False)
    ch.columna("usuarios", "nivel")
    ch.columna("usuarios", "activo")
    print("  -- banderas viejas eliminadas --")
    for vieja in ("es_admin", "es_desarrollador"):
        r = ch.c.execute(
            "SELECT COUNT(*) FROM information_schema.columns "
            "WHERE table_name='usuarios' AND column_name=%s", (vieja,)
        ).fetchone()[0]
        if r == 0:
            ch.ok += 1
            print(f"  [OK   ] usuarios.{vieja} eliminada")
        else:
            ch.fallos.append(f"usuarios.{vieja} sigue existiendo")
            print(f"  [FALLA] usuarios.{vieja} sigue existiendo")
    print("  -- membresias y equipos --")
    ch.tabla("usuario_modulos")
    ch.tabla("usuario_dispositivos")
    ch.indice("uq_usuario_dispositivos_usuario_device")
    ch.indice("idx_usuario_dispositivos_device")
    ch.indice("idx_usuario_modulos_modulo")
    print("  -- datos migrados --")
    ch.filas("usuarios totales", "SELECT COUNT(*) FROM usuarios", 7, 20)
    ch.filas("usuarios con nivel desarrollador",
             "SELECT COUNT(*) FROM usuarios WHERE nivel='desarrollador'", 1)
    ch.filas("usuario_modulos", "SELECT COUNT(*) FROM usuario_modulos", 7)
    ch.filas("usuario_dispositivos", "SELECT COUNT(*) FROM usuario_dispositivos", 9, 20)
    print("  -- SIN duplicados por nombre --")
    dup = ch.c.execute(
        "SELECT COUNT(*) FROM (SELECT LOWER(TRIM(nombre)) k FROM usuarios "
        "GROUP BY 1 HAVING COUNT(*)>1) d"
    ).fetchone()[0]
    if dup == 0:
        ch.ok += 1
        print("  [OK   ] no hay nombres duplicados")
    else:
        ch.fallos.append(f"{dup} nombres duplicados en usuarios")
        print(f"  [FALLA] {dup} nombres duplicados en usuarios")
    print("  -- PIN hasheado --")
    planas = ch.c.execute(
        "SELECT COUNT(*) FROM usuarios WHERE pin_hash IS NOT NULL AND pin_hash <> '' "
        "AND length(pin_hash) <> 64"
    ).fetchone()[0]
    if planas == 0:
        ch.ok += 1
        print("  [OK   ] todo pin_hash no vacio tiene 64 chars (sha256)")
    else:
        ch.fallos.append(f"{planas} pin_hash no son sha256")
        print(f"  [FALLA] {planas} pin_hash no son sha256")
    print("  -- dispositivo_usuario intacta --")
    ch.filas("dispositivo_usuario (no se borra)", "SELECT COUNT(*) FROM dispositivo_usuario", 16)


def verificar_3(ch):
    # La 4 renombra estas dos, asi que se aceptan los dos nombres: el chequeo
    # tiene que servir durante la secuencia y con las 4 ya aplicadas.
    tipos = ["pos_tipos_habitacion", "tipos_habitacion"]
    habs = ["pos_habitaciones", "habitaciones"]
    print("  -- catalogo de tipos --")
    ch.tabla(tipos)
    ch.columna(tipos, "capacidad")
    ch.columna(tipos, "nombre")
    ch.trigger("trg_pos_tipos_habitacion_updated_at", tipos)
    ch.columna(habs, "tipo_id")
    print("  -- huespedes ampliados --")
    for col in ("apellido", "tipo_documento", "numero_documento", "fecha_nacimiento",
                "estado_civil", "nacionalidad", "profesion", "procedencia", "destino"):
        ch.columna("hosteleria_huespedes", col)
    print("  -- reservas con hora --")
    for col in ("hora_entrada", "hora_salida"):
        ch.columna("hosteleria_reservas", col)
    print("  -- personas y vehiculos --")
    ch.tabla("hosteleria_reserva_personas")
    ch.tabla("hosteleria_vehiculos")
    ch.indice("idx_hosteleria_reserva_personas_reserva")
    ch.indice("idx_hosteleria_vehiculos_reserva")
    print("  -- FK --")
    ch.fk_apunta("reservas -> habitacion", "hosteleria_reservas", "habitacion_id",
                 ["pos_habitaciones", "habitaciones"])
    ch.fk_apunta("reservas -> huesped", "hosteleria_reservas", "huesped_id", "hosteleria_huespedes")


def verificar_4(ch):
    print("  -- renombres --")
    ch.tabla("habitaciones")
    ch.tabla("pos_habitaciones", debe_existir=False)
    ch.tabla("tipos_habitacion")
    ch.tabla("pos_tipos_habitacion", debe_existir=False)
    print("  -- estados de habitacion --")
    ch.columna("habitaciones", "estado")
    ch.columna("habitaciones", "estado_notas")
    ch.columna("habitaciones", "estado_actualizado_en")
    ch.indice("idx_habitaciones_estado")
    print("  -- modalidad en reservas --")
    ch.columna("hosteleria_reservas", "modalidad")
    ch.columna("hosteleria_reservas", "bloque_horas")
    ch.columna("hosteleria_reservas", "hora_limite")
    print("  -- datos conservados --")
    ch.filas("habitaciones", "SELECT COUNT(*) FROM habitaciones", 39)
    print("  -- la FK sigue apuntando tras el rename --")
    ch.fk_apunta("reservas -> habitaciones", "hosteleria_reservas", "habitacion_id", "habitaciones")
    print("  -- pos_cierres sigue referenciando usuarios --")
    ch.fk_apunta("cierres -> usuarios", "pos_cierres", "usuario_id", "usuarios")
    print("  -- constraint del estado --")
    r = ch.c.execute(
        "SELECT COUNT(*) FROM pg_constraint WHERE conname='habitaciones_estado_check'"
    ).fetchone()[0]
    if r:
        ch.ok += 1
        print("  [OK   ] constraint habitaciones_estado_check")
    else:
        ch.fallos.append("falta habitaciones_estado_check")
        print("  [FALLA] falta habitaciones_estado_check")


def verificar_5(ch):
    """Migracion 5: `fecha_traslado`, la fecha de negocio del traslado.

    Lo importante NO es solo que la columna exista, sino que el recálculo de
    stock siga dando lo mismo. El recalculo (configuracion_repository.dart:266)
    toma por cada producto/almacen el movimiento mas reciente por
    `fecha_movimiento` y se cree su `cantidad_nueva`; como la migracion no toca
    `fecha_movimiento`, ese resultado no puede cambiar. Eso se comprueba contra
    la tabla `existencias`, que es la verdad de campo.
    """
    print("  -- la columna existe en las dos tablas --")
    # El archivado copia la fila completa con upsertById, asi que sin la
    # columna en movimientos_archivo, archivarMovimientos() falla.
    ch.columna("movimientos", "fecha_traslado", "timestamp with time zone")
    ch.columna("movimientos_archivo", "fecha_traslado", "timestamp with time zone")

    # Los chequeos de datos leen la columna. Si todavia no existe, abortarian
    # con UndefinedColumn y el verificador no listaria el resto de los fallos,
    # que es justo cuando mas falta verlos.
    existe = ch.c.execute(
        "SELECT COUNT(*) FROM information_schema.columns "
        " WHERE table_name='movimientos' AND column_name='fecha_traslado'"
    ).fetchone()[0]
    if not existe:
        print("  (la columna todavia no existe: se saltan los chequeos de datos)")
        return

    print("  -- el relleno termino --")
    # Ningun traslado puede quedar con la fecha de negocio sin rellenar si su
    # requisicion cambio de dia calendario. Sin esto, el historial sigue
    # mostrando el dia equivocado para esas requisiciones.
    r = ch.c.execute(
        "SELECT COUNT(*) FROM movimientos m "
        "  JOIN requisiciones r ON r.id = m.requisicion_id "
        " WHERE r.fecha_creacion IS NOT NULL "
        "   AND m.fecha_movimiento::date <> r.fecha_creacion::date "
        "   AND m.fecha_traslado IS NULL"
    ).fetchone()[0]
    if r:
        ch.fallos.append(
            f"{r} movimientos con el traslado en otro dia siguen sin fecha_traslado"
        )
        print(f"  [FALLA] {r} movimientos en otro dia sin fecha_traslado")
    else:
        ch.ok += 1
        print("  [OK   ] ningun traslado en otro dia quedo sin fecha_traslado")

    # Al reves: nada puede tener fecha_traslado distinta de la de su requisicion.
    r = ch.c.execute(
        "SELECT COUNT(*) FROM movimientos m "
        "  JOIN requisiciones r ON r.id = m.requisicion_id "
        " WHERE m.fecha_traslado IS NOT NULL "
        "   AND m.fecha_traslado IS DISTINCT FROM r.fecha_creacion"
    ).fetchone()[0]
    if r:
        ch.fallos.append(f"{r} movimientos con fecha_traslado que no es la de su requisicion")
        print(f"  [FALLA] {r} con fecha_traslado distinta de su requisicion")
    else:
        ch.ok += 1
        print("  [OK   ] fecha_traslado coincide con fecha_creacion de su requisicion")

    # Solo los traslados llevan fecha de negocio. Ventas, ajustes y produccion
    # ocurren cuando se registran, asi que deben seguir en NULL.
    r = ch.c.execute(
        "SELECT COUNT(*) FROM movimientos "
        " WHERE fecha_traslado IS NOT NULL AND tipo NOT IN ('tr_salida','tr_entrada')"
    ).fetchone()[0]
    if r:
        ch.fallos.append(f"{r} movimientos que no son traslados tienen fecha_traslado")
        print(f"  [FALLA] {r} no-traslados con fecha_traslado")
    else:
        ch.ok += 1
        print("  [OK   ] solo los traslados llevan fecha_traslado")

    print("  -- el historial de un traslado conocido queda en su dia real --")
    # El caso que reporto el usuario: el traslado tiene que verse en el dia en
    # que se creo la requisicion, no en el dia en que se totalizo.
    r = ch.c.execute(
        "SELECT COUNT(*) FROM movimientos m "
        "  JOIN requisiciones r ON r.id = m.requisicion_id "
        " WHERE COALESCE(m.fecha_traslado, m.fecha_movimiento)::date "
        "       <> r.fecha_creacion::date"
    ).fetchone()[0]
    if r:
        ch.fallos.append(f"{r} movimientos se verian en un dia distinto al de su requisicion")
        print(f"  [FALLA] {r} movimientos se verian en el dia equivocado")
    else:
        ch.ok += 1
        print("  [OK   ] ningun traslado se ve en un dia distinto al de su requisicion")

    print("  -- el recalculo de stock no cambia (esto es lo critico) --")
    # El recalculo ordena por fecha_movimiento, que la migracion no toca, y se
    # queda con la cantidad_nueva del ultimo. Si eso sigue coincidiendo con
    # existencias en todas las claves, el stock no se altera.
    ch.filas(
        "claves (producto, almacen)",
        "SELECT COUNT(*) FROM (SELECT producto_id, almacen FROM existencias) t",
        1,
    )
    desalineadas = ch.c.execute(
        "SELECT COUNT(*) FROM existencias e "
        " WHERE ABS(e.cantidad - ("
        "   SELECT m.cantidad_nueva FROM movimientos m "
        "    WHERE m.producto_id = e.producto_id AND m.almacen = e.almacen "
        "    ORDER BY m.fecha_movimiento DESC, m.id DESC LIMIT 1"
        " )) > 1e-6"
    ).fetchone()[0]
    if desalineadas:
        ch.fallos.append(
            f"{desalineadas} claves de existencias no coinciden con el recalculo por "
            f"fecha_movimiento: el stock se moveria"
        )
        print(f"  [FALLA] {desalineadas} claves desalineadas con el recalculo")
    else:
        ch.ok += 1
        print("  [OK   ] existencias coincide con el recalculo en todas las claves")

    ch.filas(
        "movimientos con fecha_traslado",
        "SELECT COUNT(*) FROM movimientos WHERE fecha_traslado IS NOT NULL",
        1,
    )


VERIFICADORES = {
    1: verificar_1, 2: verificar_2, 3: verificar_3, 4: verificar_4, 5: verificar_5,
}


def aplicar(numero, url):
    nombre = dict(MIGRACIONES)[numero]
    ruta = os.path.join(MIG_DIR, nombre)
    with open(ruta, encoding="utf-8") as fh:
        sql_original = fh.read()
    sql = quitar_transaccion(sql_original)

    print("=" * 72)
    print(f"MIGRACION {numero}: {nombre}")
    print("=" * 72)

    with conectar(url) as c:
        c.execute("BEGIN")
        try:
            c.execute(sql)
            print("  SQL ejecutado. Verificando...\n")
            ch = Chequeos(c)
            VERIFICADORES[numero](ch)
            print()
            if ch.fallos:
                print(f"  {len(ch.fallos)} verificacion(es) fallaron -> ROLLBACK:")
                for f in ch.fallos:
                    print(f"    - {f}")
                c.execute("ROLLBACK")
                return False
            print(f"  {ch.ok} verificaciones OK -> COMMIT")
            c.execute("COMMIT")
            return True
        except Exception as e:
            try:
                c.execute("ROLLBACK")
            except Exception:
                pass
            print(f"  EXCEPCION: {str(e)[:400]}")
            print("  ROLLBACK hecho.")
            return False


def conectar(url):
    """Conecta como postgres si hay contrasena guardada; si no, como control_app.

    El RENAME de las migraciones 2 y 4 exige ser dueno de la tabla, y
    pos_usuarios / pos_habitaciones las duena el rol postgres. Con control_app
    no hay SET ROLE ni ALTER OWNER: es un bloqueo sin atajo.
    """
    ruta = os.path.join(RAIZ, "tool", ".pgpass_tmp")
    info = psycopg.conninfo.conninfo_to_dict(url)
    if os.path.exists(ruta):
        with open(ruta, encoding="utf-8") as fh:
            clave = fh.read().strip()
        print(f"  conectando como postgres en {info.get('host')}:{info.get('port')}")
        return psycopg.connect(
            host=info.get("host"), port=info.get("port"),
            dbname=info.get("dbname"), user="postgres", password=clave,
            connect_timeout=25,
        )
    print(f"  conectando como {info.get('user')} (sin tool/.pgpass_tmp)")
    return psycopg.connect(url, connect_timeout=25)


def solo_verificar(numero, url):
    """Corre los chequeos sin tocar nada, para auditar el estado actual."""
    nombre = dict(MIGRACIONES)[numero]
    print("=" * 72)
    print(f"VERIFICACION (solo lectura) — MIGRACION {numero}: {nombre}")
    print("=" * 72)
    with psycopg.connect(url, connect_timeout=25) as c:
        ch = Chequeos(c)
        VERIFICADORES[numero](ch)
    print()
    if ch.fallos:
        print(f"  {len(ch.fallos)} pendientes:")
        for f in ch.fallos:
            print(f"    - {f}")
        return False
    print(f"  {ch.ok} verificaciones OK")
    return True


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 2
    env = leer_env()
    url = env.get("DATABASE_URL_UNPOOLED") or env.get("DATABASE_URL")
    if not url:
        print("no hay DATABASE_URL en .env.local")
        return 1

    if args[0] == "estado":
        for n, _ in MIGRACIONES:
            solo_verificar(n, url)
            print()
        return 0

    if args[0] == "verificar":
        if len(args) < 2:
            print("usar: verificar <1|2|3|4|5>")
            return 2
        return 0 if solo_verificar(int(args[1]), url) else 1

    if args[0] == "todas":
        for n, _ in MIGRACIONES:
            if not aplicar(n, url):
                print()
                print(f"=== Se detiene en la migracion {n}. La base queda como estaba antes de ella. ===")
                return 1
        print()
        print(f"=== Las {len(MIGRACIONES)} migraciones aplicadas y verificadas. ===")
        return 0

    try:
        numero = int(args[0])
    except ValueError:
        print(f"numero invalido: {args[0]}")
        return 2
    if numero not in VERIFICADORES:
        print(f"no hay migracion {numero}. Disponibles: 1-4, verificar <n>, estado")
        return 2

    return 0 if aplicar(numero, url) else 1


if __name__ == "__main__":
    sys.exit(main())
