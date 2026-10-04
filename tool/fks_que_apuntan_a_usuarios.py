"""Lista todas las FK que apuntan a `usuarios` y cuantas filas bloquean.

Sirve para no hardcodear el nombre de una sola constraint en el arreglo de
`UsuariosRepository.eliminar()`: si manana alguien agrega otra tabla que
referencia `usuarios`, el mensaje de la app tendria que decirlo bien.
"""
import os
import sys

import psycopg

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# confdeltype de pg_constraint a lo que dice la FK
ACCION = {
    "a": "NO ACTION",
    "r": "RESTRICT",
    "c": "CASCADE",
    "n": "SET NULL",
    "d": "SET DEFAULT",
}


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
        filas = c.execute(
            "SELECT cl.relname, con.conname, con.confdeltype, "
            "       (SELECT a.attname FROM pg_attribute a "
            "         WHERE a.attrelid = con.conrelid AND a.attnum = con.conkey[1]) "
            "  FROM pg_constraint con "
            "  JOIN pg_class cl ON cl.oid = con.conrelid "
            " WHERE con.contype = 'f' AND con.confrelid = 'usuarios'::regclass "
            " ORDER BY con.confdeltype, cl.relname"
        ).fetchall()
        if not filas:
            print("  ninguna FK apunta a usuarios")
            return 0

        print("=== FKs que apuntan a usuarios ===")
        for tabla, fk, det, col in filas:
            accion = ACCION.get(det, det)
            candado = "" if det == "c" else "  <- BLOQUEA el borrado"
            print(f"  {tabla:22} {col:12} {fk:42} {accion}{candado}")

        print("\n=== filas que dependen de usuarios, por tabla ===")
        total_bloquea = 0
        for tabla, fk, det, col in filas:
            n = c.execute(f"SELECT count(*) FROM {tabla}").fetchone()[0]
            marcas = f"  <- {n} filas" if det != "c" else ""
            print(f"  {tabla:22} {n:5} filas  {ACCION.get(det, det)}{marcas}")
            if det != "c":
                total_bloquea += n

        print()
        if total_bloquea:
            print(f"  {total_bloquea} filas en total bloquean el hard-delete.")
            print("  El arreglo de eliminar() debe contemplarlas todas, no solo pos_cierres.")
        else:
            print("  Nada bloquea el borrado: eliminar() podria ser total.")
        return 0


if __name__ == "__main__":
    sys.exit(main())
