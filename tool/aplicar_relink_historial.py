# -*- coding: utf-8 -*-
"""Aplicar arreglo historial inventario (relink + ajustes de conciliacion).

--dry-run (default): calcula y VERIFICA dentro de una transaccion que se
    revierte. No escribe nada.
--aplicar: ejecuta el UPDATE relink + los INSERT de conciliacion en una
    transaccion; verifica que el invariante quede en cero y que el stock
    recalculado quede identico antes de commit. Si la verificacion falla,
    rollback y salida con error.

Que hace exactamente:
  A) UPDATE movimientos SET cantidad_anterior = (cantidad_nueva del previo
     en la misma producto_id+almacen, orden id). Solo las filas cuyo anterior
     no coincidia. No toca cantidad_nueva, ni fechas, ni existencias.
  B) INSERT 3 movimientos tipo 'ajuste' al final de las 3 claves cuyo ultimo
     movimiento por id no dejaba la existencia actual (CARAOTA, CALAMARES,
     CARNE PARA MEDALLONES), con cantidad_nueva = existencias. El recalculado
     ya daba ese valor (por fecha), asi que el stock no cambia.
"""
import os
import sys

import psycopg

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EPS = 1e-7
AUTOR = "sistema_arreglo_historial"

PRODUCTOS_AJUSTE = {  # nombre -> almacen
    "CARAOTA": "restaurante",
    "CALAMARES": "restaurante",
    "CARNE PARA MEDALLONES": "restaurante",
}


def leer_url():
    with open(os.path.join(RAIZ, ".env.local"), encoding="utf-8") as fh:
        for linea in fh:
            linea = linea.strip()
            if not linea or linea.startswith("#") or "=" not in linea:
                continue
            k, _, v = linea.partition("=")
            if k.strip() in ("DATABASE_URL_UNPOOLED", "DATABASE_URL"):
                return v.strip().strip("'\"")
    raise SystemExit("sin DATABASE_URL en .env.local")


def snapshot_recalculo(cur):
    """Por cada (producto, almacen): cantidad_nueva del ultimo por fecha."""
    cur.execute("""
        SELECT DISTINCT ON (m.producto_id, COALESCE(m.almacen,'principal'))
               m.producto_id, COALESCE(m.almacen,'principal'), m.cantidad_nueva
          FROM movimientos m
         ORDER BY m.producto_id, COALESCE(m.almacen,'principal'),
                  m.fecha_movimiento DESC NULLS LAST, m.id DESC
    """)
    return {(f[0], f[1]): float(f[2]) for f in cur.fetchall()}


def rotas_por_id(cur):
    cur.execute(
        "SELECT m.producto_id, COALESCE(m.almacen, '~'), m.id "
        "  FROM movimientos m "
        "  LEFT JOIN LATERAL ("
        "    SELECT m2.cantidad_nueva FROM movimientos m2 "
        "     WHERE m2.producto_id = m.producto_id "
        "       AND COALESCE(m2.almacen,'~') = COALESCE(m.almacen,'~') "
        "       AND m2.id < m.id ORDER BY m2.id DESC LIMIT 1) p ON true "
        " WHERE m.producto_id IS NOT NULL "
        "   AND p.cantidad_nueva IS NOT NULL "
        "   AND abs(m.cantidad_anterior - p.cantidad_nueva) > 1e-7"
    )
    return cur.fetchall()


def descuadres(cur):
    """Secuencias cuyo ultimo por id no deja la existencia actual."""
    cur.execute("""
        SELECT m.producto_id, COALESCE(m.almacen,'principal'), m.id,
               m.cantidad_nueva, e.cantidad
          FROM movimientos m
          JOIN existencias e
            ON e.producto_id = m.producto_id
           AND COALESCE(e.almacen,'principal') = COALESCE(m.almacen,'principal')
         WHERE m.id = (SELECT max(m2.id) FROM movimientos m2
                        WHERE m2.producto_id = m.producto_id
                          AND COALESCE(m2.almacen,'principal') =
                              COALESCE(m.almacen,'principal'))
           AND abs(m.cantidad_nueva - e.cantidad) > 1e-7
         ORDER BY m.producto_id
    """)
    return cur.fetchall()


def main():
    aplicar = "--aplicar" in sys.argv
    url = leer_url()
    with psycopg.connect(url) as c:
        c.autocommit = False
        cur = c.cursor()

        # ---- estado antes ----
        recalc_antes = snapshot_recalculo(cur)
        rotas_antes = rotas_por_id(cur)
        desc_antes = descuadres(cur)
        ex_antes = {(f[0], f[1]): f[2] for f in cur.execute(
            "SELECT producto_id, COALESCE(almacen,'principal'), cantidad FROM existencias"
        ).fetchall()}

        print("ANTES: %d movs relink, %d claves descuadradas, %d claves stock" %
              (len(rotas_antes), len(desc_antes), len(ex_antes)))

        # ---- A) relink ----
        cur.execute("""
            UPDATE movimientos m SET cantidad_anterior = prev.nueva
              FROM (
                SELECT id, LAG(cantidad_nueva) OVER (
                         PARTITION BY producto_id, COALESCE(almacen,'principal')
                         ORDER BY id) AS nueva
                  FROM movimientos
              ) prev
             WHERE m.id = prev.id AND prev.nueva IS NOT NULL
               AND abs(m.cantidad_anterior - prev.nueva) > 1e-7
        """)
        n_relink = cur.rowcount

        # ---- B) ajustes de conciliacion ----
        ajustes = []
        for nombre, alm in PRODUCTOS_AJUSTE.items():
            cur.execute("SELECT id, es_pesable FROM productos WHERE LOWER(nombre)=LOWER(%s)", (nombre,))
            r = cur.fetchone()
            if not r:
                raise SystemExit("producto no encontrado: %s" % nombre)
            pid, es_pesable = r
            ex = ex_antes.get((pid, alm))
            if ex is None:
                raise SystemExit("sin existencia para %s/%s" % (nombre, alm))
            cur.execute(
                """SELECT id, cantidad_nueva FROM movimientos m
                    WHERE m.producto_id=%s AND COALESCE(m.almacen,'principal')=%s
                    ORDER BY m.id DESC LIMIT 1""",
                (pid, alm),
            )
            ult = cur.fetchone()
            ant = float(ult[1])
            cant = abs(ex - ant)
            cur.execute(
                """INSERT INTO movimientos
                     (producto_id, tipo, cantidad, cantidad_anterior,
                      cantidad_nueva, peso_total, registrado_por, observaciones,
                      almacen, fecha_movimiento, created_at)
                   VALUES (%s,'ajuste',%s,%s,%s,%s,%s,%s,%s, now(), now())
                   RETURNING id""",
                (pid, cant, ant, ex, ex if es_pesable else 0.0, AUTOR,
                 "Conciliacion stock (arreglo historial cadenas)", alm),
            )
            nuevo_id = cur.fetchone()[0]
            ajustes.append((nombre, alm, nuevo_id, ex))

        # ---- verificacion ----
        recalc_despues = snapshot_recalculo(cur)
        rotas_despues = rotas_por_id(cur)
        desc_despues = descuadres(cur)
        ex_despues = {(f[0], f[1]): f[2] for f in cur.execute(
            "SELECT producto_id, COALESCE(almacen,'principal'), cantidad FROM existencias"
        ).fetchall()}

        # stock recalulado identico (por construccion no deberia moverse nada)
        dif = {k: (recalc_antes[k], recalc_despues.get(k))
               for k in recalc_antes
               if abs(recalc_antes[k] - recalc_despues.get(k, -1e9)) > EPS}
        dif.update({k: (None, recalc_despues[k]) for k in recalc_despues if k not in recalc_antes})
        # existencias sin tocar
        dif_ex = {k: (ex_antes[k], ex_despues.get(k)) for k in ex_antes
                  if abs(float(ex_antes[k]) - float(ex_despues.get(k, -1e9))) > EPS}
        dif_ex.update({k: (None, ex_despues[k]) for k in ex_despues if k not in ex_antes})

        ok = (not rotas_despues and not desc_despues and not dif and not dif_ex)

        print("DESPUES: %d movs relinkados, %d claves descuadradas (%s)" %
              (n_relink, len(desc_despues), "OK 0" if not desc_despues else "NO"))
        print("  cadenas rotas por id: %d (%s)" % (len(rotas_despues), "OK 0" if not rotas_despues else "NO"))
        print("  recalculo identico:   %s" % ("OK" if not dif else "NO -> %s" % dif))
        print("  existencias intacta:  %s" % ("OK" if not dif_ex else "NO -> %s" % dif_ex))
        if ajustes:
            print("  ajustes insertados:")
            for nombre, alm, nid, ex in ajustes:
                print("    %s/%s -> id %s = %s" % (nombre, alm, nid, ex))

        if not ok:
            c.rollback()
            print()
            print("VERIFICACION FALLIDA -> rollback. Nada se escribio.")
            return 2
        if not aplicar:
            c.rollback()
            print()
            print("DRY-RUN ok (rollback hecho). Revisar y ejecutar con --aplicar")
            return 0
        c.commit()
        print()
        print("APLICADO y verificado (commit hecho).")
        return 0


if __name__ == "__main__":
    sys.exit(main())