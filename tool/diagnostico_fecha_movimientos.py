"""Diagnostico: los movimientos de una requisicion se fechan al totalizar, no
al crearla.

El usuario reporta que la requisicion REQ-20260928150024 se creo el 28/09 pero
el traslado del producto "agua grande" aparece con fecha 2/10 en el historial
de stock, y que eso rompe la secuencia del historial.

Este script:
  1. muestra la requisicion y sus movimientos con las dos fechas
  2. cuenta cuantos movimientos de todo el historico quedaron mal fechados
  3. dice cuantos dias de desvio hay en cada caso

Solo lee. No escribe nada.
"""
import os
import sys

import psycopg

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NUMERO = "REQ-20260928150024"


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
        print(f"1. la requisicion {NUMERO}")
        print("=" * 78)
        req = c.execute(
            "SELECT id, numero, origen, destino, estado, creada_por, procesada_por,"
            "       fecha_creacion, fecha_procesamiento "
            "  FROM requisiciones WHERE numero = %s",
            (NUMERO,),
        ).fetchone()
        if not req:
            print("  NO EXISTE esa requisicion. Los numeros que si existen:")
            for n, fc in c.execute(
                "SELECT numero, fecha_creacion FROM requisiciones "
                "ORDER BY fecha_creacion DESC LIMIT 15"
            ):
                print(f"    {n:28} {fc}")
            return 1
        (rid, numero, origen, destino, estado, creada_por, procesada_por,
         f_cre, f_proc) = req
        print(f"  id={rid}  {numero}")
        print(f"  {origen} -> {destino}   estado={estado}")
        print(f"  creada_por={creada_por}   procesada_por={procesada_por}")
        print(f"  fecha_creacion      = {f_cre}")
        print(f"  fecha_procesamiento = {f_proc}")
        if f_cre and f_proc:
            print(f"  --> se totalizo {(f_proc - f_cre).days} dia(s) despues de crearla")

        print()
        print("=" * 78)
        print("2. los movimientos que genero esa requisicion")
        print("=" * 78)
        mvs = c.execute(
            "SELECT m.id, m.tipo, m.cantidad, m.almacen, m.fecha_movimiento, "
            "       COALESCE(p.nombre, d.ingrediente) AS que "
            "  FROM movimientos m "
            "  LEFT JOIN productos p ON p.id = m.producto_id "
            "  LEFT JOIN requisicion_detalles d "
            "         ON d.producto_id = m.producto_id AND d.requisicion_id = %s "
            " WHERE m.requisicion_id = %s "
            " ORDER BY m.id",
            (rid, rid),
        ).fetchall()
        if not mvs:
            print("  (no hay movimientos con esa requisicion_id)")
        for mid, tipo, cant, alm, fm, que in mvs:
            marca = ""
            if f_cre and fm and fm != f_cre:
                dias = (fm - f_cre).days
                marca = f"   <-- {dias} dia(s) tarde (deberia ser {f_cre:%d/%m/%Y})"
            print(f"  mov {mid}  {tipo:10} {cant:>8}  {alm:12} {que:26} {fm}{marca}")

        print()
        print("=" * 78)
        print('3. el historial de stock de "agua grande"')
        print("=" * 78)
        prods = c.execute(
            "SELECT id, nombre FROM productos "
            "WHERE LOWER(nombre) LIKE %s ORDER BY id",
            ("%agua grande%",),
        ).fetchall()
        if not prods:
            print('  no hay producto que se llame "agua grande". Productos con "agua":')
            for pid, nom in c.execute(
                "SELECT id, nombre FROM productos WHERE LOWER(nombre) LIKE %s "
                "ORDER BY id LIMIT 20",
                ("%agua%",),
            ):
                print(f"    id={pid:4} {nom}")
            return 1
        for pid, pnombre in prods:
            print(f"  --- producto id={pid} {pnombre} ---")
            filas = c.execute(
                "SELECT m.id, m.tipo, m.cantidad, m.almacen, m.fecha_movimiento, "
                "       r.numero, r.fecha_creacion "
                "  FROM movimientos m "
                "  LEFT JOIN requisiciones r ON r.id = m.requisicion_id "
                " WHERE m.producto_id = %s "
                " ORDER BY m.fecha_movimiento DESC, m.id DESC LIMIT 25",
                (pid,),
            ).fetchall()
            for mid, tipo, cant, alm, fm, rnum, fcr in filas:
                desvio = ""
                if rnum and fcr and fm and fm != fcr:
                    desvio = f"  [req del {fcr:%d/%m/%Y}, mov del {fm:%d/%m/%Y}]"
                print(f"    {fm:%d/%m/%Y}  {tipo:10} {cant:>8}  {alm:12} "
                      f"{rnum or '(sin requisicion)':26}{desvio}")

        print()
        print("=" * 78)
        print("4. cuanto hay de esto en todo el historico")
        print("=" * 78)
        tot = c.execute("SELECT COUNT(*) FROM movimientos").fetchone()[0]
        con_req = c.execute(
            "SELECT COUNT(*) FROM movimientos WHERE requisicion_id IS NOT NULL"
        ).fetchone()[0]
        mal = c.execute(
            "SELECT COUNT(*) FROM movimientos m "
            "  JOIN requisiciones r ON r.id = m.requisicion_id "
            " WHERE m.fecha_movimiento IS DISTINCT FROM r.fecha_creacion"
        ).fetchone()[0]
        print(f"  movimientos totales                 : {tot}")
        print(f"  de ellos, con requisicion_id         : {con_req}")
        print(f"  con fecha != fecha_creacion de su req: {mal}")
        print()
        if con_req and mal == con_req:
            print("  TODOS los movimientos de requisicion quedaron mal fechados:")
            print("  el bug no es de un caso aislado, es la regla del codigo.")
        elif mal:
            print(f"  {mal} de {con_req} quedaron mal fechados.")
        print()
        print("  desvio en dias, de los que se desviaron:")
        for dias, n in c.execute(
            "SELECT EXTRACT(DAY FROM (m.fecha_movimiento - r.fecha_creacion))::int, "
            "       COUNT(*) "
            "  FROM movimientos m JOIN requisiciones r ON r.id = m.requisicion_id "
            " WHERE m.fecha_movimiento IS DISTINCT FROM r.fecha_creacion "
            " GROUP BY 1 ORDER BY 1"
        ):
            print(f"    {int(dias):4} dia(s) tarde : {n} movimiento(s)")
        print()
        print("  requisiciones totalizadas tarde (por cuanto):")
        for dias, n in c.execute(
            "SELECT EXTRACT(DAY FROM (fecha_procesamiento - fecha_creacion))::int, "
            "       COUNT(*) FROM requisiciones "
            " WHERE fecha_procesamiento IS NOT NULL "
            "   AND fecha_procesamiento <> fecha_creacion "
            " GROUP BY 1 ORDER BY 1"
        ):
            print(f"    {int(dias):4} dia(s) tarde : {n} requisicion(es)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
