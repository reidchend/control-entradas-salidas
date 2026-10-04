"""Cuanto costaria corregir la fecha de los movimientos de requisicion.

Antes de fecharlos hacia atras hay que saber una cosa: el recalculo de stock
(configuracion_repository.dart:253-273) toma, por cada (producto_id, almacen),
el movimiento MAS RECIENTE por fecha_movimiento y usa su cantidad_nueva como
stock final. O sea que fecha_movimiento es el cursor del recalculo.

Si un movimiento se fecha hacia atras y era el ultimo de su producto, el
recalculo pasaria a leer el cantidad_nueva de otro movimiento y el stock
cambiaria. Este script mide cuantos de los movimientos a corregir estan en esa
posicion, y de cuanto seria el cambio.

Solo lee.
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
        # Archivos que el recalculo tambien lee.
        c.execute("""
            CREATE TEMP VIEW mov AS
            SELECT producto_id, almacen, tipo, cantidad, cantidad_anterior,
                   cantidad_nueva, fecha_movimiento, id, requisicion_id,
                   'activo' AS donde FROM movimientos
            UNION ALL
            SELECT producto_id, almacen, tipo, cantidad, cantidad_anterior,
                   cantidad_nueva, fecha_movimiento, id, requisicion_id,
                   'archivo' AS donde FROM movimientos_archivo
        """)

        print("=" * 78)
        print("1. cuantas requisiciones quedaron con el traslado en otro dia")
        print("=" * 78)
        print("   (compara el DIA CALENDARIO, no el intervalo: un traslado de las")
        print("    23:50 a las 00:30 cae en otro dia aunque el intervalo sea 0)")
        reqs = c.execute("""
            SELECT r.id, r.numero, r.origen, r.destino,
                   r.fecha_creacion::date, r.fecha_procesamiento::date,
                   (r.fecha_procesamiento::date - r.fecha_creacion::date) AS dias,
                   COUNT(m.id) AS movs
              FROM requisiciones r
              JOIN movimientos m ON m.requisicion_id = r.id
             WHERE r.fecha_creacion IS NOT NULL
               AND r.fecha_procesamiento IS NOT NULL
               AND r.fecha_procesamiento::date <> r.fecha_creacion::date
             GROUP BY 1,2,3,4,5,6,7
             ORDER BY 7 DESC, r.id
        """).fetchall()
        if not reqs:
            print("  ninguna. No habria que corregir nada.")
        total_movs = 0
        for rid, num, ori, des, fc, fp, dias, nm in reqs:
            total_movs += nm
            print(f"  {num}  {ori} -> {des}")
            print(f"      creada {fc}   totalizada {fp}   ({dias} dia/s de desvio)")
            print(f"      {nm} movimientos Generated")
        print()
        print(f"  total: {len(reqs)} requisiciones, {total_movs} movimientos")

        print()
        print("=" * 78)
        print("2. de esos movimientos, cuantos son el ULTIMO de su producto")
        print("   (o sea: los que, al fecharlos atras, cambian el recalculo)")
        print("=" * 78)
        # El ultimo actual de cada (producto_id, almacen), como lo decide el codigo.
        c.execute("""
            CREATE TEMP VIEW ultimo_actual AS
            SELECT DISTINCT ON (producto_id, almacen)
                   producto_id, almacen, id, cantidad_nueva, fecha_movimiento
              FROM mov
             ORDER BY producto_id, almacen, fecha_movimiento DESC, id DESC
        """)
        # El ultimo que quedaria si se fecharan hacia atras los de esas reqs.
        c.execute("""
            CREATE TEMP VIEW reqs_tarde AS
            SELECT DISTINCT id FROM requisiciones
             WHERE fecha_creacion IS NOT NULL AND fecha_procesamiento IS NOT NULL
               AND fecha_procesamiento::date <> fecha_creacion::date
        """)
        c.execute("""
            CREATE TEMP VIEW ultimo_corregido AS
            SELECT DISTINCT ON (m.producto_id, m.almacen)
                   m.producto_id, m.almacen, m.id, m.cantidad_nueva,
                   m.fecha_movimiento
              FROM mov m
              LEFT JOIN requisiciones r ON r.id = m.requisicion_id
             WHERE NOT (m.requisicion_id IN (SELECT id FROM reqs_tarde))
                OR r.fecha_creacion IS NULL
             ORDER BY m.producto_id, m.almacen, m.fecha_movimiento DESC, m.id DESC
        """)
        cambios = c.execute("""
            SELECT a.producto_id, COALESCE(p.nombre,'?') AS nombre, a.almacen,
                   a.id AS id_actual, a.cantidad_nueva AS stock_actual,
                   b.id AS id_corregido, b.cantidad_nueva AS stock_corregido,
                   (b.cantidad_nueva - a.cantidad_nueva) AS diferencia
              FROM ultimo_actual a
              JOIN ultimo_corregido b
                ON b.producto_id = a.producto_id AND b.almacen = a.almacen
             WHERE a.id IS DISTINCT FROM b.id
             ORDER BY ABS(b.cantidad_nueva - a.cantidad_nueva) DESC, a.producto_id
        """.replace("FROM ultimo_actual a", "FROM ultimo_actual a JOIN productos p ON p.id = a.producto_id")).fetchall()
        if not cambios:
            print("  NINGUNO. Corregir las fechas no cambiaria el stock recalculado.")
        else:
            print(f"  {len(cambios)} (producto, almacen) cambiarian de stock:")
            for pid, nom, alm, ia, sa, ic, sc, dif in cambios:
                print(f"    {nom:26} {alm:12} stock {sa:>9} -> {sc:>9}  (dif {dif:+})")
            print()
            print("  OJO: estas diferencias NO son un error del recalculo. Son")
            print("  consecuencia de leer un cantidad_nueva de otra fila. El valor")
            print("  correcto seria el de existencias (arriba se compara).")

        print()
        print("=" * 78)
        print("3. el stock guardado hoy en existencias (la verdad de campo)")
        print("=" * 78)
        # Que dice existencias para los mismos (producto, almacen).
        for pid, nom, alm, ia, sa, ic, sc, dif in cambios:
            ex = c.execute(
                "SELECT cantidad FROM existencias WHERE producto_id = %s "
                "AND almacen = %s",
                (pid, alm),
            ).fetchone()
            real = ex[0] if ex else None
            marca = ""
            if real is not None:
                if abs(float(real) - sa) < 0.001:
                    marca = "  (= stock actual del recalculo)"
                elif abs(float(real) - sc) < 0.001:
                    marca = "  (= stock que daria el recalculo corregido)"
                else:
                    marca = "  (ninguno de los dos)"
            print(f"    {nom:26} {alm:12} existencias={real}{marca}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
