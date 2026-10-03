"""Da a control_app los mismos permisos que tiene en el resto de la base.

Las migraciones corrieron como postgres, y en esta base el patron es
"postgres duena, control_app recibe GRANT". Sin estos GRANT la app no puede
leer ni escribir las tablas nuevas aunque las migraciones esten aplicadas.

Permisos: arwdDxtm = INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES,
TRIGGER, USAGE de secuencia. Es exactamente el ACL que ya tienen las tablas
viejas, e incluye 'S' porque las columnas SERIAL necesitan secuencia.
"""
import os
import sys

import psycopg

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROL_APP = "control_app"
PERMISOS = "arwdDxtm"

# Tablas que crean o renombran las 4 migraciones de hosteleria.
TABLAS = [
    "usuarios",
    "usuario_modulos",
    "usuario_dispositivos",
    "tipos_habitacion",
    "hosteleria_huespedes",
    "hosteleria_reservas",
    "hosteleria_reserva_personas",
    "hosteleria_vehiculos",
]


def leer_env():
    v = {}
    with open(os.path.join(RAIZ, ".env.local"), encoding="utf-8") as fh:
        for linea in fh:
            linea = linea.strip()
            if not linea or linea.startswith("#") or "=" not in linea:
                continue
            k, _, val = linea.partition("=")
            v[k.strip()] = val.strip().strip("'\"").strip('"')
    return v


def conectar_postgres(url):
    ruta = os.path.join(RAIZ, "tool", ".pgpass_tmp")
    if not os.path.exists(ruta):
        print("falta tool/.pgpass_tmp: no puedo conectar como postgres")
        return None
    with open(ruta, encoding="utf-8") as fh:
        clave = fh.read().strip()
    info = psycopg.conninfo.conninfo_to_dict(url)
    return psycopg.connect(
        host=info.get("host"), port=info.get("port"), dbname=info.get("dbname"),
        user="postgres", password=clave, connect_timeout=25,
    )


def main():
    env = leer_env()
    url = env.get("DATABASE_URL_UNPOOLED") or env.get("DATABASE_URL")
    c = conectar_postgres(url)
    if c is None:
        return 1

    # El estado de permisos se consulta con el rol de la app, que es quien
    # sufre la falta de acceso.
    app = psycopg.connect(url, connect_timeout=25)

    print(f"=== permisos de {ROL_APP} ANTES ===")
    faltantes = []
    for t in TABLAS:
        existe = c.execute("SELECT to_regclass(%s)", (f"public.{t}",)).fetchone()[0]
        if not existe:
            print(f"  {t:30} NO EXISTE")
            continue
        puede = app.execute(
            f"SELECT has_table_privilege('{ROL_APP}', 'public.{t}', "
            "'SELECT,INSERT,UPDATE,DELETE')"
        ).fetchone()[0]
        dueno = c.execute(
            "SELECT tableowner FROM pg_tables WHERE schemaname='public' AND tablename=%s",
            (t,),
        ).fetchone()[0]
        marca = "ok" if puede else "FALTA PERMISOS"
        print(f"  {t:30} dueno={dueno:12} {marca}")
        if not puede:
            faltantes.append(t)

    if not faltantes:
        print("\n  control_app ya tiene permisos en todas. Nada que hacer.")
        app.close()
        return 0

    print(f"\n=== dando {PERMISOS} en {len(faltantes)} tabla(s) ===")
    with c:
        with c.cursor() as cur:
            for t in faltantes:
                cur.execute(
                    f'GRANT {PERMISOS} ON TABLE public."{t}" TO "{ROL_APP}"'
                )
                # Las secuencias de las columnas SERIAL tambien.
                cur.execute(
                    "SELECT pg_get_serial_sequence(%s, 'id')", (f"public.{t}",)
                )
                seq = cur.fetchone()[0]
                if seq:
                    cur.execute(f'GRANT USAGE, SELECT ON SEQUENCE {seq} TO "{ROL_APP}"')
                    print(f"  GRANT en {t} + secuencia {seq}")
                else:
                    print(f"  GRANT en {t}")

    print(f"\n=== permisos de {ROL_APP} DESPUES ===")
    fallos = 0
    for t in TABLAS:
        existe = c.execute("SELECT to_regclass(%s)", (f"public.{t}",)).fetchone()[0]
        if not existe:
            print(f"  {t:30} NO EXISTE")
            fallos += 1
            continue
        puede = app.execute(
            f"SELECT has_table_privilege('{ROL_APP}', 'public.{t}', "
            "'SELECT,INSERT,UPDATE,DELETE')"
        ).fetchone()[0]
        sel = app.execute(
            f"SELECT has_table_privilege('{ROL_APP}', 'public.{t}', 'SELECT')"
        ).fetchone()[0]
        ins = app.execute(
            f"SELECT has_table_privilege('{ROL_APP}', 'public.{t}', 'INSERT')"
        ).fetchone()[0]
        upd = app.execute(
            f"SELECT has_table_privilege('{ROL_APP}', 'public.{t}', 'UPDATE')"
        ).fetchone()[0]
        print(f"  {t:30} S={int(sel)} I={int(ins)} U={int(upd)}")
        if not (sel and ins and upd):
            fallos += 1

    app.close()
    c.close()

    print()
    if fallos:
        print(f"  {fallos} tabla(s) siguen incompletas")
        return 1
    print(f"  {len(TABLAS)} tablas con permisos completos para {ROL_APP}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
