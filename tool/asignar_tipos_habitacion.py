"""Asigna un tipo a las 39 habitaciones y deja el texto 'tipo' consistente.

El usuario eligio: todas Matrimonial (capacidad 2).

Se escriben las dos columnas porque la app lo hace igual
(habitacion_config_dialog.dart:89 -> `tipo: tipo.nombre, tipoId: tipo.id`):
`tipo` es el texto legacy y `tipo_id` el que hace el LEFT JOIN con
tipos_habitacion para traer la capacidad. Si se escribiera solo una, el
formulario de habitacion mostraria datos que no coinciden entre si.
"""
import os
import sys

import psycopg

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

TIPO = "Matrimonial"
CAPACIDAD_ESPERADA = 2


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
        tipo_id = c.execute(
            "SELECT id, capacidad FROM tipos_habitacion WHERE nombre=%s", (TIPO,)
        ).fetchone()
        if not tipo_id:
            print(f"  [FALLA] el tipo {TIPO!r} no existe en tipos_habitacion")
            print("          corri primero tool/cargar_tipos_habitacion.py")
            return 1
        if tipo_id[1] != CAPACIDAD_ESPERADA:
            print(f"  [AVISO] {TIPO} tiene capacidad {tipo_id[1]}, "
                  f"se esperaban {CAPACIDAD_ESPERADA}")
        print(f"  tipo a asignar: {TIPO} (id={tipo_id[0]}, capacidad={tipo_id[1]})")

        antes = c.execute(
            "SELECT COUNT(*) FILTER (WHERE tipo_id IS NOT NULL), "
            "       COUNT(*) FILTER (WHERE tipo_id IS NULL) FROM habitaciones"
        ).fetchone()
        print(f"  antes: {antes[0]} con tipo, {antes[1]} sin tipo")
        print()

        c.execute("BEGIN")
        try:
            r = c.execute(
                "UPDATE habitaciones SET tipo_id=%s, tipo=%s, updated_at=now() "
                "WHERE tipo_id IS DISTINCT FROM %s OR tipo IS DISTINCT FROM %s "
                "RETURNING id",
                (tipo_id[0], TIPO, tipo_id[0], TIPO),
            ).fetchall()
            print(f"  Actualizadas: {len(r)} habitaciones")
        except Exception as e:
            c.execute("ROLLBACK")
            print(f"\n  EXCEPCION: {str(e)[:300]}")
            print("  ROLLBACK: no se toco nada.")
            return 1

        # --- verificacion: la consulta que hace la app ---
        print("\n=== como lo ve la app (el LEFT JOIN de hosteleria_repository) ===")
        filas = c.execute(
            "SELECT h.numero, h.piso, h.tipo, h.tipo_id, t.capacidad "
            "FROM habitaciones h LEFT JOIN tipos_habitacion t ON t.id = h.tipo_id "
            "ORDER BY h.piso NULLS LAST, h.numero"
        ).fetchall()
        for numero, piso, tipo, tid, cap in filas:
            marca = "OK" if tid and cap else "FALTA"
            print(f"  [{marca:5}] {str(piso):4} {numero:4}  tipo={tipo!r:16} "
                  f"tipo_id={tid} capacidad={cap}")

        sin_tipo = [f for f in filas if f[3] is None]
        if sin_tipo:
            print(f"\n  [FALLA] {len(sin_tipo)} habitaciones sin tipo")
            c.execute("ROLLBACK")
            return 1

        # maxPersonas del modelo: capacidad < 1 cae a 1
        caps = {f[4] for f in filas}
        if caps != {CAPACIDAD_ESPERADA}:
            print(f"\n  [FALLA] las capacidades no son uniformes: {caps}")
            c.execute("ROLLBACK")
            return 1

        total = c.execute("SELECT COUNT(*) FROM habitaciones").fetchone()[0]
        if len(filas) != total:
            print(f"\n  [FALLA] el JOIN devolvio {len(filas)} de {total}")
            c.execute("ROLLBACK")
            return 1

        print(f"\n  Las {total} habitaciones quedan con {TIPO} "
              f"(capacidad {CAPACIDAD_ESPERADA}) -> COMMIT")
        print("  Antes maxPersonas caia a 1; ahora es 2, asi que el check-in")
        print("  admite titular + 1 acompanante.")
        c.execute("COMMIT")
        return 0


if __name__ == "__main__":
    sys.exit(main())
