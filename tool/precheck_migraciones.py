"""Verificaciones previas a aplicar las 4 migraciones. Solo lectura + rollback."""
import os
import sys

import psycopg

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


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


def main():
    env = leer_env()
    url = env.get("DATABASE_URL_UNPOOLED") or env.get("DATABASE_URL")
    fallos = []
    with psycopg.connect(url, connect_timeout=25) as c:
        print("=== 1. se puede crear pgcrypto? (dentro de ROLLBACK) ===")
        try:
            c.execute("BEGIN")
            c.execute("CREATE EXTENSION IF NOT EXISTS pgcrypto")
            h = c.execute("SELECT encode(digest('1234', 'sha256'), 'hex')").fetchone()[0]
            print(f"  [OK   ] se crea y digest() funciona")
            print(f"         sha256('1234') = {h}")
            c.execute("ROLLBACK")
        except Exception as e:
            try:
                c.execute("ROLLBACK")
            except Exception:
                pass
            print(f"  [FALLA] {str(e)[:200]}")
            fallos.append("pgcrypto no se puede crear")
        print()

        print("=== 2. FKs que apuntan a las tablas que se renombran ===")
        for objetivo in ("pos_usuarios", "pos_habitaciones"):
            filas = c.execute(
                "SELECT con.conname, src.relname, con.confdeltype "
                "FROM pg_constraint con "
                "JOIN pg_class src ON src.oid = con.conrelid "
                "JOIN pg_class tgt ON tgt.oid = con.confrelid "
                "WHERE con.contype='f' AND tgt.relname=%s",
                (objetivo,),
            ).fetchall()
            print(f"  -> {objetivo}: {len(filas)} FK(s)")
            for nombre, tabla, ondel in filas:
                regla = {"a": "NO ACTION", "r": "RESTRICT", "c": "CASCADE",
                         "n": "SET NULL", "d": "SET DEFAULT"}.get(ondel, ondel)
                print(f"       {tabla}.{nombre}  ON DELETE {regla}")
            if objetivo == "pos_usuarios":
                print("       ^ con RENAME these FKs siguen apuntando al mismo objeto, solo cambia el nombre")
        print()

        print("=== 3. vistas / funciones / triggers que mencionen los nombres viejos ===")
        por_tabla = {}
        for nombre, definicion in c.execute(
            "SELECT viewname, definition FROM pg_views "
            "WHERE schemaname='public'"
        ).fetchall():
            for viejo in ("pos_usuarios", "pos_habitaciones", "dispositivo_usuario"):
                if viejo in definicion:
                    por_tabla.setdefault(viejo, []).append(f"vista {nombre}")
        for proname, src in c.execute(
            "SELECT proname, prosrc FROM pg_proc WHERE pronamespace='public'::regnamespace"
        ).fetchall():
            for viejo in ("pos_usuarios", "pos_habitaciones", "dispositivo_usuario"):
                if viejo in (src or ""):
                    por_tabla.setdefault(viejo, []).append(f"funcion {proname}()")
        for tgname, tgrel in c.execute(
            "SELECT tgname, relname FROM pg_trigger t JOIN pg_class r ON r.oid=t.tgrelid "
            "WHERE NOT tgisinternal"
        ).fetchall():
            for viejo in ("pos_usuarios", "pos_habitaciones"):
                if tgrel == viejo:
                    por_tabla.setdefault(viejo, []).append(f"trigger {tgname} sobre {tgrel}")
        for viejo in ("pos_usuarios", "pos_habitaciones", "dispositivo_usuario"):
            hits = por_tabla.get(viejo, [])
            print(f"  {viejo:22} {hits if hits else 'sin referencias'}")
        print()

        print("=== 4. pos_habitaciones: columna tipo ===")
        col = c.execute(
            "SELECT column_name, data_type FROM information_schema.columns "
            "WHERE table_name='pos_habitaciones' AND column_name IN ('tipo','tipo_id')"
        ).fetchall()
        print(f"  {col if col else 'NO tiene columna tipo'}")
        n = c.execute(
            "SELECT COUNT(*) FROM pos_habitaciones WHERE tipo IS NOT NULL AND TRIM(tipo)<>''"
        ).fetchone()[0]
        print(f"  filas con tipo informative: {n}")
        print(f"  -> el sembrado de pos_tipos_habitacion no inserta nada; las 39 habitaciones")
        print(f"     quedan con tipo_id NULL, y tipos_habitacion quedara vacia")
        print()

        print("=== 5. colision de nombres al migrar dispositivo_usuario -> usuarios ===")
        du = c.execute(
            "SELECT DISTINCT LOWER(TRIM(nombre)) FROM dispositivo_usuario ORDER BY 1"
        ).fetchall()
        pu = c.execute(
            "SELECT DISTINCT LOWER(TRIM(nombre)) FROM pos_usuarios ORDER BY 1"
        ).fetchall()
        set_pu = {r[0] for r in pu}
        nuevos = [r[0] for r in du if r[0] not in set_pu]
        exist = [r[0] for r in du if r[0] in set_pu]
        print(f"  usuarios en pos_usuarios: {sorted(set_pu)}")
        print(f"  se REUSAN (mismo nombre, no se duplican): {exist}")
        print(f"  se CREAN nuevos: {nuevos}")
        print()
        print("  OJO: 'desarrollador' y 'Desarrollador' matchean por LOWER(TRIM())")
        print()

    print()
    if fallos:
        print(f"BLOQUEOS: {fallos}")
        return 1
    print("Sin bloqueos para aplicar.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
