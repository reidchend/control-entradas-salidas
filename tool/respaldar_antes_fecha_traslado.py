"""Respaldo previo a la migracion 5 (movimientos.fecha_traslado).

La migracion es reversible con UPDATE ... SET fecha_traslado = NULL, pero
igual se guarda que filas se van a rellenar y con que fecha, para poder
auditar o deshacer fila por fila.
"""
import json
import os
import sys
from datetime import datetime, timezone

import psycopg

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESTINO = os.path.join(RAIZ, "tool", "respaldos")


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
    ruta = os.path.join(DESTINO, f"pre_fecha_traslado_{sello}.json")

    with psycopg.connect(url, connect_timeout=25) as c:
        # Exactamente las filas que la migracion va a tocar.
        filas = c.execute(
            "SELECT m.id, m.requisicion_id, m.producto_id, m.tipo, m.almacen, "
            "       m.fecha_movimiento, r.numero, r.fecha_creacion "
            "  FROM movimientos m "
            "  JOIN requisiciones r ON r.id = m.requisicion_id "
            " WHERE r.fecha_creacion IS NOT NULL "
            "   AND m.fecha_movimiento::date <> r.fecha_creacion::date "
            " ORDER BY m.id"
        ).fetchall()
        reqs = c.execute(
            "SELECT id, numero, fecha_creacion, fecha_procesamiento "
            "  FROM requisiciones "
            " WHERE fecha_creacion IS NOT NULL "
            "   AND fecha_procesamiento IS NOT NULL "
            "   AND fecha_procesamiento::date <> fecha_creacion::date "
            " ORDER BY id"
        ).fetchall()

    datos = {
        "generado": sello,
        "motivo": "migracion 5: rellenar fecha_traslado con la fecha_creacion "
                  "de la requisicion",
        "como_deshacer": "UPDATE movimientos SET fecha_traslado = NULL;",
        "requisiciones": [
            {
                "id": r[0],
                "numero": r[1],
                "fecha_creacion": r[2].isoformat(),
                "fecha_procesamiento": r[3].isoformat(),
            }
            for r in reqs
        ],
        "movimientos": [
            {
                "id": f[0],
                "requisicion_id": f[1],
                "producto_id": f[2],
                "tipo": f[3],
                "almacen": f[4],
                "fecha_movimiento": f[5].isoformat(),
                "requisicion_numero": f[6],
                "fecha_creacion_requisicion": f[7].isoformat(),
                "fecha_traslado_que_se_pondra": f[7].isoformat(),
            }
            for f in filas
        ],
    }
    with open(ruta, "w", encoding="utf-8") as fh:
        json.dump(datos, fh, ensure_ascii=False, indent=1)

    tam = os.path.getsize(ruta) / 1024
    print(f"  respaldo: {ruta}")
    print(f"  {len(reqs)} requisiciones, {len(filas)} movimientos  ({tam:.1f} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
