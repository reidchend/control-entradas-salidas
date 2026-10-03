"""Crea el catalogo de tipos de habitación con las capacidades que indico el
usuario. Idempotente: si un tipo ya existe con ese nombre, lo actualiza en vez
de duplicarlo.

Capacidades (las dio el usuario):
    Matrimonial 2 | Doble 3 | Triple 4 | Quintuple 5 | Individual 1 | Suite 2
"""
import os
import sys

import psycopg

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

CATALOGO = [
    ("Individual", 1),
    ("Matrimonial", 2),
    ("Suite", 2),
    ("Doble", 3),
    ("Triple", 4),
    ("Quintuple", 5),
]


def main():
    env = {}
    with open(os.path.join(RAIZ, ".env.local"), encoding="utf-8") as fh:
        for linea in fh:
            linea = linea.strip()
            if not linea or linea.startswith("#") or "=" not in linea:
                continue
            k, _, v = linea.partition("=")
            env[k.strip()] = v.strip().strip("'\"").strip('"')
    url = env.get("DATABASE_URL_UNPOOLED") or env["DATABASE_URL"]

    with psycopg.connect(url, connect_timeout=25) as c:
        print("=== constraints de tipos_habitacion ===")
        for r in c.execute(
            "SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint "
            "WHERE conrelid='tipos_habitacion'::regclass ORDER BY conname"
        ).fetchall():
            print(f"  {r[0]}: {r[1]}")
        print()

        ya = {r[0]: r[1] for r in c.execute(
            "SELECT nombre, capacidad FROM tipos_habitacion"
        ).fetchall()}
        print(f"  tipos existentes antes: {len(ya)} {ya if ya else ''}")
        print()

        c.execute("BEGIN")
        try:
            for nombre, capacidad in CATALOGO:
                anterior = ya.get(nombre)
                if anterior is None:
                    r = c.execute(
                        "INSERT INTO tipos_habitacion "
                        "(nombre, capacidad, activo, creado_en) "
                        "VALUES (%s, %s, 1, now()::text) RETURNING id, capacidad",
                        (nombre, capacidad),
                    ).fetchone()
                    print(f"  [NUEVO] {nombre:14} capacidad={r[1]}  id={r[0]}")
                elif anterior != capacidad:
                    r = c.execute(
                        "UPDATE tipos_habitacion SET capacidad=%s, updated_at=now() "
                        "WHERE nombre=%s RETURNING id, capacidad",
                        (capacidad, nombre),
                    ).fetchone()
                    print(f"  [AJUSTE] {nombre:14} {anterior} -> {r[1]}  id={r[0]}")
                else:
                    r = c.execute(
                        "SELECT id, capacidad FROM tipos_habitacion WHERE nombre=%s",
                        (nombre,),
                    ).fetchone()
                    print(f"  [IGUAL]  {nombre:14} capacidad={r[1]}  id={r[0]}")
        except Exception as e:
            c.execute("ROLLBACK")
            print(f"\n  EXCEPCION: {str(e)[:300]}")
            print("  ROLLBACK: no se toco nada.")
            return 1

        # --- verificacion ---
        print("\n=== catalogo resultante ===")
        filas = c.execute(
            "SELECT id, nombre, capacidad, activo FROM tipos_habitacion "
            "ORDER BY capacidad, nombre"
        ).fetchall()
        for i, n, cap, act in filas:
            print(f"  id={i:3} {n:14} capacidad={cap}  activo={act}")

        print()
        for nombre, capacidad in CATALOGO:
            r = c.execute(
                "SELECT capacidad FROM tipos_habitacion WHERE nombre=%s", (nombre,)
            ).fetchone()
            if not r:
                print(f"  [FALLA] falta {nombre}")
                c.execute("ROLLBACK")
                return 1
            if r[0] != capacidad:
                print(f"  [FALLA] {nombre} tiene {r[0]}, se esperaba {capacidad}")
                c.execute("ROLLBACK")
                return 1
        dup = c.execute(
            "SELECT COUNT(*) FROM (SELECT LOWER(TRIM(nombre)) k FROM tipos_habitacion "
            "GROUP BY 1 HAVING COUNT(*)>1) d"
        ).fetchone()[0]
        if dup:
            print(f"  [FALLA] {dup} nombres de tipo duplicados")
            c.execute("ROLLBACK")
            return 1

        print(f"  {len(CATALOGO)} tipos con la capacidad indicada, sin duplicados -> COMMIT")
        c.execute("COMMIT")
        return 0


if __name__ == "__main__":
    sys.exit(main())
