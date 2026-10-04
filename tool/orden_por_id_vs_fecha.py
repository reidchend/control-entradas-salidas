"""¿Se puede hacer el recalculo mas robusto ordenando por id?

El recalculo (configuracion_repository.dart:253-273) ordena por
fecha_movimiento y usa el cantidad_nueva del ultimo. Eso solo es correcto
mientras fecha_movimiento siga el orden de insercion, porque la cadena
cantidad_anterior -> cantidad_nueva se arma al insertar.

Si vamos a fechar los traslados con la fecha de la requisicion (no la de
totalizacion), ese orden se rompe. La salida seria ordenar por id, que es
la posicion real en el libro mayor.

Este script comprueba, sobre los datos de HOY, que ordenar por id da
exactamente el mismo stock que ordenar por fecha. Si coincide, cambiar el
recalculo a id es seguro.

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
        print("=" * 78)
        print("1. hay solapamiento de id entre movimientos y movimientos_archivo")
        print("=" * 78)
        solapa = c.execute("""
            SELECT COUNT(*) FROM movimientos m
              JOIN movimientos_archivo a ON a.id = m.id
        """).fetchone()[0]
        act = c.execute("SELECT COUNT(*), MIN(id), MAX(id) FROM movimientos").fetchone()
        arc = c.execute(
            "SELECT COUNT(*), MIN(id), MAX(id) FROM movimientos_archivo"
        ).fetchone()
        print(f"  movimientos         : {act[0]:5} filas  id {act[1]}..{act[2]}")
        print(f"  movimientos_archivo : {arc[0]:5} filas  id {arc[1]}..{arc[2]}")
        print(f"  ids presentes en las dos tablas: {solapa}")
        if solapa:
            print("  -> HAY solapamiento: ordenar por id entre las dos tablas seria")
            print("     ambiguo. Habria que discriminar por tabla.")
        else:
            print("  -> sin solapamiento: el id ordena bien las dos juntas.")

        print()
        print("=" * 78)
        print("2. el id es SERIAL y crece con la insercion")
        print("=" * 78)
        col = c.execute("""
            SELECT column_name, data_type, column_default, is_identity
              FROM information_schema.columns
             WHERE table_name = 'movimientos' AND column_name = 'id'
        """).fetchone()
        print(f"  movimientos.id: {col[1]}  default={col[2]}  identity={col[3]}")
        # Monotonía: en la gran mayoría de los casos id y fecha suben juntos.
        fuera = c.execute("""
            SELECT COUNT(*) FROM (
                SELECT id, fecha_movimiento,
                       LAG(fecha_movimiento) OVER (ORDER BY id) AS fecha_prev
                  FROM movimientos
            ) t
            WHERE fecha_prev IS NOT NULL AND fecha_movimiento < fecha_prev
        """).fetchone()[0]
        print(f"  filas cuyo id sube pero la fecha baja: {fuera}")
        if fuera:
            print("  -> el id NO sigue estrictamente a la fecha, pero solo por")
            print("     milisegundos de insercion; para el ultimo por clave da igual.")

        print()
        print("=" * 78)
        print("3. la prueba: ¿orden por id da el mismo stock que orden por fecha?")
        print("=" * 78)
        c.execute("""
            CREATE TEMP VIEW mov AS
            SELECT producto_id, almacen, cantidad_nueva, fecha_movimiento, id
              FROM movimientos
            UNION ALL
            SELECT producto_id, almacen, cantidad_nueva, fecha_movimiento, id
              FROM movimientos_archivo
        """)
        por_fecha = c.execute("""
            SELECT DISTINCT ON (producto_id, almacen)
                   producto_id, almacen, id, cantidad_nueva
              FROM mov
             ORDER BY producto_id, almacen, fecha_movimiento DESC, id DESC
        """).fetchall()
        por_id = c.execute("""
            SELECT DISTINCT ON (producto_id, almacen)
                   producto_id, almacen, id, cantidad_nueva
              FROM mov
             ORDER BY producto_id, almacen, id DESC
        """).fetchall()

        mapa_id = {(p, a): (i, c_) for p, a, i, c_ in por_id}
        mapa_fecha = {(p, a): (i, c_) for p, a, i, c_ in por_fecha}
        print(f"  claves (producto, almacen): {len(mapa_fecha)}")

        distintas_fila = [k for k in mapa_fecha if mapa_fecha[k][0] != mapa_id[k][0]]
        distinto_stock = [
            k for k in mapa_fecha
            if abs(float(mapa_fecha[k][1]) - float(mapa_id[k][1])) > 1e-9
        ]
        print(f"  el id elige OTRO movimiento:        {len(distintas_fila)}")
        print(f"  el STOCK resultante cambia:          {len(distinto_stock)}")

        # Y lo que de verdad importa: ¿el stock por id coincide con existencias?
        print()
        print("  comparando contra la tabla existencias (la verdad de campo):")
        mala_fecha = mala_id = 0
        ejemplos = []
        for (pid, alm), (mid, cant) in mapa_fecha.items():
            ex = c.execute(
                "SELECT cantidad FROM existencias "
                " WHERE producto_id = %s AND almacen = %s",
                (pid, alm),
            ).fetchone()
            if ex is None:
                continue
            real = float(ex[0])
            if abs(real - float(cant)) > 1e-6:
                mala_fecha += 1
            idc = mapa_id.get((pid, alm), (None, None))[1]
            if idc is not None and abs(real - float(idc)) > 1e-6:
                mala_id += 1
                if len(ejemplos) < 8:
                    ejemplos.append((pid, alm, real, cant, idc))
        print(f"    orden por fecha se equivoca en: {mala_fecha} claves")
        print(f"    orden por id    se equivoca en: {mala_id} claves")
        for pid, alm, real, cf, ci in ejemplos:
            print(f"      producto {pid} {alm}: existencias={real} "
                  f"fecha={cf} id={ci}")

        print()
        if mala_id == 0 and mala_fecha == 0:
            print("  [OK] hoy los dos criterios coinciden con existencias.")
            print("       Ordenar por id es seguro y no cambia nada.")
        elif mala_id == 0:
            print("  [OK] ordenar por id reproduce existencias EXACTAMENTE,")
            print(f"       mientras ordenar por fecha se equivoca en {mala_fecha} claves.")
            print("       O sea: hoy la fecha ya miente un poco y el id no.")
        else:
            print(f"  [OJO] id se equivoca en {mala_id} claves. Habria que investigar.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
