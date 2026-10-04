"""Prueba el caso que la UI nueva puede tocar: eliminar un usuario que tiene
cierros de caja.

UsuariosRepository.eliminar() hace DELETE FROM usuarios WHERE id = $1, pero
pos_cierres tiene FK a usuarios con ON DELETE NO ACTION (no hay CASCADE). Si un
operador cerro caja alguna vez, el borrado tiene que fallar. Esta prueba lo
confirma con datos reales, y de paso mira que.users_tab avise o no.
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
            env[k.strip()] = v.strip().strip("'\"").strip('"')
    url = env.get("DATABASE_URL_UNPOOLED") or env["DATABASE_URL"]

    with psycopg.connect(url, connect_timeout=25) as c:
        print("=== quien tiene cierros de caja ===")
        filas = c.execute(
            "SELECT u.id, u.nombre, u.nivel, COUNT(pc.id) cierres "
            "FROM usuarios u JOIN pos_cierres pc ON pc.usuario_id = u.id "
            "GROUP BY u.id, u.nombre, u.nivel ORDER BY 3 DESC, u.id"
        ).fetchall()
        if not filas:
            print("  (ningun usuario tiene cierros: no se puede probar)")
            return 0
        for i, n, lv, k in filas:
            print(f"  id={i:3} {n:22} {lv:14} {k} cierres")
        objetivo = filas[0]
        uid, nombre = objetivo[0], objetivo[1]
        print(f"\n  objetivo: id={uid} {nombre!r} con {objetivo[3]} cierros")
        print()

        print("=== DELETE FROM usuarios sobre ese usuario ===")
        c.execute("SAVEPOINT p")
        try:
            c.execute("DELETE FROM usuarios WHERE id = %s RETURNING id", (uid,))
            c.execute("ROLLBACK TO SAVEPOINT p")
            print("  [SE BORRO] la FK ya NO bloquea el borrado.")
            print("  (revertido)")
            print()
            print("  El esquema cambio: la FK de pos_cierres ahora permite el")
            print("  borrado. Revisar que la UI y el repository sigan suponiendo")
            print("  que eliminar() falla, y ajustar el dialogo de confirmacion.")
            return 1
        except Exception as e:
            sqlstate = getattr(e, "sqlstate", "?")
            msg = str(e).split("\n")[0]
            bloqueado = sqlstate == "23503"
            print(f"  [{'BLOQUEADO' if bloqueado else 'OTRO ERROR'}]  sqlstate={sqlstate}")
            print(f"           {msg[:150]}")
            c.execute("ROLLBACK TO SAVEPOINT p")
            print("  (revertido)")
            print()
            if bloqueado:
                print("  Comportamiento actual de la base (el esperado por ahora):")
                print("    pos_cierres -> usuarios es FK con ON DELETE NO ACTION, sin")
                print("    CASCADE. Un operador que cerro caja no se puede borrar.")
                print()
                print("  CONSECUENCIA EN LA APP: UsuariosRepository.eliminar() lanza la")
                print("  excepcion y usuarios_tab.dart:53 la llama sin try/catch, asi")
                print("  que al tocar 'Eliminar' el dialogo se cierra y no pasa nada,")
                print("  sin explicar por que. Afecta a estos usuarios:")
                for i, n, lv, k in filas:
                    print(f"    id={i:3} {n:22} {k} cierres")
                return 0
            return 1


if __name__ == "__main__":
    sys.exit(main())
