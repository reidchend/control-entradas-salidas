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

    def tabla(self, nombre, debe_existir=True):
        r = self.c.execute("SELECT to_regclass(%s)", (f"public.{nombre}",)).fetchone()[0]
        bien = bool(r) == debe_existir
        if bien:
            self.ok += 1
            estado = r if r else "-"
            print(f"  [OK   ] {nombre:32} {estado}")
        else:
            self.fallos.append(f"{nombre} {'deberia existir' if debe_existir else 'no deberia existir'}")
            print(f"  [FALLA] {nombre:32} {'EXISTE (no deberia)' if r else 'FALTA'}")
        return bool(r)

    def columna(self, tabla, col, tipo_esperado=None):
        r = self.c.execute(
            "SELECT data_type FROM information_schema.columns "
            "WHERE table_schema='public' AND table_name=%s AND column_name=%s",
            (tabla, col),
        ).fetchone()
        if r is None:
            self.fallos.append(f"{tabla}.{col} falta")
            print(f"  [FALLA] {tabla}.{col:26} FALTA")
            return
        if tipo_esperado and r[0] != tipo_esperado:
            self.fallos.append(f"{tabla}.{col} es {r[0]}, se esperaba {tipo_esperado}")
            print(f"  [FALLA] {tabla}.{col:26} es {r[0]}, se esperaba {tipo_esperado}")
        else:
            self.ok += 1
            print(f"  [OK   ] {tabla}.{col:26} {r[0]}")

    def trigger(self, nombre, tabla):
        r = self.c.execute(
            "SELECT COUNT(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid "
            "WHERE t.tgname=%s AND c.relname=%s AND NOT t.tgisinternal",
            (nombre, tabla),
        ).fetchone()[0]
        if r:
            self.ok += 1
            print(f"  [OK   ] trigger {nombre} sobre {tabla}")
        else:
            self.fallos.append(f"falta el trigger {nombre} sobre {tabla}")
            print(f"  [FALLA] falta el trigger {nombre} sobre {tabla}")

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
        r = self.c.execute(
            "SELECT c.relname FROM pg_constraint con "
            "JOIN pg_class c ON c.oid=con.confrelid "
            "JOIN pg_attribute a ON a.attrelid=con.conrelid AND a.attnum=con.conkey[1] "
            "WHERE con.contype='f' AND con.conrelid=%s::regclass AND a.attname=%s",
            (fk_tabla, fk_col),
        ).fetchone()
        real = r[0] if r else None
        if real == esperado:
            self.ok += 1
            print(f"  [OK   ] {etiqueta:32} {fk_tabla}.{fk_col} -> {real}")
        else:
            self.fallos.append(f"{fk_tabla}.{fk_col} apunta a {real}, se esperaba {esperado}")
            print(f"  [FALLA] {etiqueta:32} {fk_tabla}.{fk_col} -> {real}, esperaba {esperado}")


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
    ch.fk_apunta("reservas -> habitacion", "hosteleria_reservas", "habitacion_id", "pos_habitaciones")
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
    print("  -- catalogo de tipos --")
    ch.tabla("pos_tipos_habitacion")
    ch.columna("pos_tipos_habitacion", "capacidad")
    ch.columna("pos_tipos_habitacion", "nombre")
    ch.trigger("trg_pos_tipos_habitacion_updated_at", "pos_tipos_habitacion")
    ch.columna("pos_habitaciones", "tipo_id")
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
    ch.fk_apunta("reservas -> habitacion", "hosteleria_reservas", "habitacion_id", "pos_habitaciones")
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


VERIFICADORES = {1: verificar_1, 2: verificar_2, 3: verificar_3, 4: verificar_4}


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
            print("usar: verificar <1|2|3|4>")
            return 2
        return 0 if solo_verificar(int(args[1]), url) else 1

    if args[0] == "todas":
        for n, _ in MIGRACIONES:
            if not aplicar(n, url):
                print()
                print(f"=== Se detiene en la migracion {n}. La base queda como estaba antes de ella. ===")
                return 1
        print()
        print("=== Las 4 migraciones aplicadas y verificadas. ===")
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
