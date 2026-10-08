"""Respaldo previo al arreglo del historial de inventario.

Que se va a hacer y como se deshace:

  A) RELINK de 86 movimientos: `cantidad_anterior` = `cantidad_nueva` del
     movimiento previo (misma producto_id + almacen, orden `id`). No cambia
     `cantidad_nueva` ni `existencias`, asi que el stock recalculado (el
     `cantidad_nueva` del ultimo por fecha) queda identico. Deshacer:
     UPDATE movimientos SET cantidad_anterior = <valor_anterior> WHERE id = ...;

  B) INSERT de 3 movimientos `ajuste` de conciliacion para que el ultimo
     movimiento por `id` deje la existencia actual (CARAOTA -4.6,
     CALAMARES 7.965, CARNE PARA MEDALLONES 3.215). Deshacer:
     DELETE FROM movimientos WHERE id IN (...);
"""
import json
import os
from datetime import datetime, timezone

import psycopg

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESTINO = os.path.join(RAIZ, "tool", "respaldos")
EPS = 1e-7


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

    os.makedirs(DESTINO, exist_ok=True)
    sello = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    ruta = os.path.join(DESTINO, f"pre_relink_historial_{sello}.json")

    with psycopg.connect(url, connect_timeout=25) as c:
        # A) las 86 filas a relinkear, con el valor viejo y el nuevo.
        filas = c.execute(
            """
            SELECT m.producto_id, COALESCE(p.nombre,'?') AS nombre,
                   COALESCE(m.almacen,'principal') AS alm, m.id, m.tipo,
                   m.cantidad_anterior, prev.nueva AS cantidad_anterior_nuevo,
                   m.cantidad_nueva
              FROM movimientos m
              JOIN (
                   SELECT id, producto_id,
                          COALESCE(almacen,'principal') AS alm,
                          LAG(cantidad_nueva) OVER (
                            PARTITION BY producto_id, COALESCE(almacen,'principal')
                            ORDER BY id) AS nueva
                     FROM movimientos
                   ) prev ON prev.id = m.id
              LEFT JOIN productos p ON p.id = m.producto_id
             WHERE prev.nueva IS NOT NULL
               AND abs(m.cantidad_anterior - prev.nueva) > 1e-7
             ORDER BY m.producto_id, COALESCE(m.almacen,'principal'), m.id
            """
        ).fetchall()
        # B) las claves descuadradas (ultimo por id no deja la existencia actual).
        desc = c.execute(
            """
            SELECT m.producto_id, p.nombre, COALESCE(m.almacen,'principal'),
                   m.id, m.cantidad_nueva, e.cantidad
              FROM movimientos m
              JOIN existencias e
                ON e.producto_id = m.producto_id
               AND COALESCE(e.almacen,'principal') = COALESCE(m.almacen,'principal')
              LEFT JOIN productos p ON p.id = m.producto_id
             WHERE m.id = (SELECT max(m2.id) FROM movimientos m2
                            WHERE m2.producto_id = m.producto_id
                              AND COALESCE(m2.almacen,'principal') =
                                  COALESCE(m.almacen,'principal'))
               AND abs(m.cantidad_nueva - e.cantidad) > 1e-7
             ORDER BY m.producto_id
            """
        ).fetchall()

    datos = {
        "generado": sello,
        "motivo": "arreglo historial inventario: relink cantidad_anterior "
                  "+ ajustes de conciliacion",
        "como_deshacer": {
            "A": "UPDATE movimientos SET cantidad_anterior = <anterior_viejo> "
                 "WHERE id IN (...)",
            "B": "DELETE FROM movimientos WHERE id IN (...)",
        },
        "relink": [
            {
                "id": f[3],
                "producto_id": f[0],
                "producto": f[1],
                "almacen": f[2],
                "tipo": f[4],
                "cantidad_anterior_viejo": f[5],
                "cantidad_anterior_nuevo": f[6],
                "cantidad_nueva_sin_cambiar": f[7],
            }
            for f in filas
        ],
        "ajustes_conciliacion": [
            {
                "producto_id": d[0],
                "producto": d[1],
                "almacen": d[2],
                "ultimo_mov_id": d[3],
                "ultimo_mov_deja": d[4],
                "existencias": d[5],
                "ajuste_a_insertar_cantidad_nueva": d[5],
            }
            for d in desc
        ],
    }
    with open(ruta, "w", encoding="utf-8") as fh:
        json.dump(datos, fh, ensure_ascii=False, indent=1)

    tam = os.path.getsize(ruta) / 1024
    print(f"  respaldo: {ruta}")
    print(f"  {len(filas)} movimientos relink, {len(desc)} claves descuadradas ({tam:.1f} KB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())