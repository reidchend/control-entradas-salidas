"""Dos cosas sobre la migracion 5, ya aplicada.

1. Tu caso: el historial de AGUA GRANDE tiene que mostrar el traslado el dia en
   que se creo la requisicion, no el dia en que se totalizo.

2. Valida que los CHEQUEOS DE DATOS del verificadorDetectan de verdad un
   relleno incompleto. Antes de aplicar solo se vio en rojo el "falta la
   columna"; los chequeos de datos nunca se llegaron a ejecutar. Aqui se
   comprueban de verdad, deshaciendo el relleno de UNA fila dentro de una
   transaccion que se revierte: si la consulta del verificador devuelve 1, el
   verificador la veria en rojo.

No deja nada escrito.
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
        print("1. tu caso: AGUA GRANDE y REQ-20260928150024")
        print("=" * 78)
        pid = c.execute(
            "SELECT id FROM productos WHERE LOWER(nombre) = 'agua grande'"
        ).fetchone()
        if not pid:
            print("  no existe AGUA GRANDE")
            return 1
        pid = pid[0]
        req = c.execute(
            "SELECT id, fecha_creacion, fecha_procesamiento FROM requisiciones "
            " WHERE numero = 'REQ-20260928150024'"
        ).fetchone()
        print(f"  AGUA GRANDE id={pid}")
        print(f"  REQ-20260928150024: creada {req[1]}, totalizada {req[2]}")
        print()
        print("  como lo ve la app ahora (COALESCE, que es lo que pintan las vistas):")
        for fm, real, num, tipo, cant in c.execute("""
            SELECT COALESCE(fecha_traslado, fecha_movimiento),
                   fecha_movimiento, r.numero, m.tipo, m.cantidad
              FROM movimientos m
              LEFT JOIN requisiciones r ON r.id = m.requisicion_id
             WHERE m.producto_id = %s
             ORDER BY COALESCE(fecha_traslado, fecha_movimiento) DESC, m.id DESC
             LIMIT 12
        """, (pid,)):
            marca = ""
            if num == "REQ-20260928150024":
                marca = "   <== tu requisicion"
            print(f"    {fm:%d/%m/%Y}  {tipo:10} {cant:>6}  {num or '-':24}"
                  f"  (registro: {real:%d/%m/%Y}){marca}")

        print()
        print("=" * 78)
        print("2. los chequeos de datos detectan un relleno incompleto")
        print("=" * 78)
        # Filas que la migracion relleno: sirve una para romperla un ratito.
        objetivo = c.execute("""
            SELECT m.id, m.fecha_traslado
              FROM movimientos m JOIN requisiciones r ON r.id = m.requisicion_id
             WHERE m.fecha_movimiento::date <> r.fecha_creacion::date
               AND m.fecha_traslado IS NOT NULL
             ORDER BY m.id LIMIT 1
        """).fetchone()
        if not objetivo:
            print("  no hay nada que deshacer: el relleno esta vacio")
            return 1
        mid = objetivo[0]

        # La consulta EXACTA del verificador, antes de romper nada.
        SQL_HUECOS = (
            "SELECT COUNT(*) FROM movimientos m "
            "  JOIN requisiciones r ON r.id = m.requisicion_id "
            " WHERE r.fecha_creacion IS NOT NULL "
            "   AND m.fecha_movimiento::date <> r.fecha_creacion::date "
            "   AND m.fecha_traslado IS NULL"
        )
        antes = c.execute(SQL_HUECOS).fetchone()[0]
        print(f"  mov {mid} tiene fecha_traslado = {objetivo[1]}")
        print(f"  huecos antes de romperlo: {antes}  -> el verificador dira [OK]")

        c.execute("SAVEPOINT p")
        c.execute("UPDATE movimientos SET fecha_traslado = NULL WHERE id = %s", (mid,))
        durante = c.execute(SQL_HUECOS).fetchone()[0]
        print(f"  huecos con esa fila sin rellenar: {durante}"
              f"  -> el verificador dira [FALLA]")
        c.execute("ROLLBACK TO SAVEPOINT p")

        despues = c.execute(SQL_HUECOS).fetchone()[0]
        restaurado = c.execute(
            "SELECT fecha_traslado FROM movimientos WHERE id = %s", (mid,)
        ).fetchone()[0]
        print(f"  huecos tras revertir: {despues}")
        print(f"  fecha_traslado restaurada: {restaurado}")

        print()
        if durante == antes + 1 and despues == antes and restaurado is not None:
            print("  [OK] el chequeo ve la fila faltante y la ve desaparecer al")
            print("       revertir. El detector funciona en las dos direcciones.")
            return 0
        print("  [FALLA] el chequeo no reacciono como deberia")
        return 1


if __name__ == "__main__":
    sys.exit(main())
