"""Por que 578 y no 628.

El conteo de 628 que salio antes era el numero de movimientos que PERTENECEN a
las 10 requisiciones totalizadas tarde. Pero el relleno solo debe tocar los que
estaban en otro dia calendario: 578. Los otros 50 ya se veian en el dia
correcto y dejarlos en NULL no cambia nada de lo que se muestra.

Este script muestra esos 50 para confirmar que la diferencia es esa y no un
error de la condicion.
"""
import os
import sys

import psycopg

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    env = {}
    with open(os.path.join(RAIZ, ".env.local"), encoding="utf-8") as fh:
        for linea in fh:
            linea = linea.strip()
            if not linea or linea.startswith("#") or "=" not in linea:
                continue
            k, _, v = linea.partition("=")
            env[k.strip()] = v.strip().strip("'\"")
    url = env.get("DATABASE_URL_UNPOOLED") or env["DATABASE_URL"]

    with psycopg.connect(url, connect_timeout=25) as c:
        c.execute("""
            CREATE TEMP VIEW reqs_tarde AS
            SELECT id, numero, fecha_creacion, fecha_procesamiento
              FROM requisiciones
             WHERE fecha_creacion IS NOT NULL
               AND fecha_procesamiento IS NOT NULL
               AND fecha_procesamiento::date <> fecha_creacion::date
        """)
        total = c.execute(
            "SELECT COUNT(*) FROM movimientos m JOIN reqs_tarde r ON r.id=m.requisicion_id"
        ).fetchone()[0]
        cambian = c.execute(
            "SELECT COUNT(*) FROM movimientos m JOIN reqs_tarde r ON r.id=m.requisicion_id "
            " WHERE m.fecha_movimiento::date <> r.fecha_creacion::date"
        ).fetchone()[0]
        iguales = c.execute(
            "SELECT COUNT(*) FROM movimientos m JOIN reqs_tarde r ON r.id=m.requisicion_id "
            " WHERE m.fecha_movimiento::date = r.fecha_creacion::date"
        ).fetchone()[0]
        print(f"  movimientos de las 10 requisiciones       : {total}")
        print(f"    en otro dia calendario (se corrigen)     : {cambian}")
        print(f"    en el MISMO dia (ya se ven bien)          : {iguales}")
        print()
        if total != cambian + iguales:
            print("  [INCOHERENTE] los dos grupos no suman el total")
            return 1

        print("  los que ya estaban en el dia correcto, por requisicion:")
        for num, n, fmov in c.execute("""
            SELECT r.numero, COUNT(*), MIN(m.fecha_movimiento)
              FROM movimientos m JOIN reqs_tarde r ON r.id=m.requisicion_id
             WHERE m.fecha_movimiento::date = r.fecha_creacion::date
             GROUP BY r.numero ORDER BY 2 DESC
        """):
            print(f"    {num:24} {n:4} mov   primero {fmov}")

        print()
        print("  ejemplo de uno de esos movimientos:")
        fila = c.execute("""
            SELECT m.id, m.tipo, m.almacen, m.cantidad,
                   m.fecha_movimiento, r.fecha_creacion, r.numero
              FROM movimientos m JOIN reqs_tarde r ON r.id=m.requisicion_id
             WHERE m.fecha_movimiento::date = r.fecha_creacion::date
             ORDER BY m.id LIMIT 1
        """).fetchone()
        if fila:
            print(f"    mov {fila[0]} {fila[1]} {fila[2]} {fila[3]}")
            print(f"    fecha_movimiento = {fila[4]}")
            print(f"    fecha_creacion   = {fila[5]}  (req {fila[6]})")
            print()
            print("    -> con COALESCE(fecha_traslado, fecha_movimiento) se muestra")
            print("       fecha_movimiento, que ya cae en el dia correcto de la")
            print("       requisicion. Dejarlo en NULL no muestra nada mal.")
        return 0


if __name__ == "__main__":
    sys.exit(main())
