"""Fusiona el usuario duplicado Reidched (13) dentro de Reidchend (2).

Por que es la misma persona: los dos tienen EXACTAMENTE el mismo pin_hash
(03ac6742..., que es sha256 de '1234'). La fila 13 la creo la migracion 2 a
partir de dispositivo_usuario, donde ese device figuraba con el nombre mal
escrito 'reidched' y el mismo PIN que 'reidchend'.

Que hace, todo en una transaccion:
  1. mueve los dispositivos de 13 a 2
  2. mueve los modulos de 13 a 2 (los que 2 ya tiene se omiten: la PK es
     (usuario_id, modulo))
  3. borra el usuario 13

pos_cierres tiene FK a usuarios SIN cascade, asi que si 13 tuviera cierres el
borrado fallaria. El script lo comprueba antes y aborta si los hay.
"""
import os
import sys

import psycopg

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

ORIGEN = 13   # Reidched  (typo)
DESTINO = 2  # Reidchend (admin)


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
        print(f"=== fusion {ORIGEN} (Reidched) -> {DESTINO} (Reidchend) ===\n")

        # --- precondiciones ---
        a = c.execute(
            "SELECT nombre, pin_hash, nivel FROM usuarios WHERE id=%s", (ORIGEN,)
        ).fetchone()
        b = c.execute(
            "SELECT nombre, pin_hash, nivel FROM usuarios WHERE id=%s", (DESTINO,)
        ).fetchone()
        if not a or not b:
            print("  [FALLA] alguno de los dos usuarios no existe")
            return 1
        print(f"  origen  {ORIGEN}: {a[0]!r} nivel={a[2]}")
        print(f"  destino {DESTINO}: {b[0]!r} nivel={b[2]}")
        if a[1] != b[1]:
            print(f"  [FALLA] los PIN no coinciden:")
            print(f"          {ORIGEN}: {a[1]}")
            print(f"          {DESTINO}: {b[1]}")
            print("          Si son PIN distintos, NO son la misma persona:")
            print("          no se fusiona. Fijate antes de seguir.")
            return 1
        print(f"  PIN identico en los dos: {a[1][:16]}...  (ok, es la misma persona)")

        cierres = c.execute(
            "SELECT COUNT(*) FROM pos_cierres WHERE usuario_id=%s", (ORIGEN,)
        ).fetchone()[0]
        if cierres:
            print(f"  [FALLA] el usuario {ORIGEN} tiene {cierres} filas en pos_cierres.")
            print("          La FK no tiene ON DELETE CASCADE, borrarlo fallaria.")
            return 1
        print(f"  pos_cierres del {ORIGEN}: 0 filas  (ok, el borrado no rompe la FK)")
        print()

        # --- antes ---
        def foto(uid):
            d = c.execute(
                "SELECT device_id FROM usuario_dispositivos WHERE usuario_id=%s ORDER BY id",
                (uid,),
            ).fetchall()
            m = c.execute(
                "SELECT modulo FROM usuario_modulos WHERE usuario_id=%s ORDER BY modulo",
                (uid,),
            ).fetchall()
            return [x[0] for x in d], [x[0] for x in m]

        devs_o, mods_o = foto(ORIGEN)
        devs_d, mods_d = foto(DESTINO)
        print(f"  ANTES  {ORIGEN}: {len(devs_o)} devices, {len(mods_o)} modulos {mods_o}")
        print(f"         {DESTINO}: {len(devs_d)} devices, {len(mods_d)} modulos {mods_d}")
        print()

        # --- la operacion ---
        c.execute("BEGIN")
        try:
            movidos = c.execute(
                "UPDATE usuario_dispositivos SET usuario_id=%s "
                "WHERE usuario_id=%s AND NOT EXISTS ("
                "  SELECT 1 FROM usuario_dispositivos d2 "
                "  WHERE d2.usuario_id=%s AND d2.device_id=usuario_dispositivos.device_id"
                ") RETURNING device_id",
                (DESTINO, ORIGEN, DESTINO),
            ).fetchall()
            print(f"  dispositivos movidos: {len(movidos)}")
            for d in movidos:
                print(f"    {d[0]}")

            # Los que ya estaban en el destino no se mueven: el destino ya
            # tiene ese device.
            huerfanos = c.execute(
                "SELECT device_id FROM usuario_dispositivos WHERE usuario_id=%s",
                (ORIGEN,),
            ).fetchall()
            if huerfanos:
                print(f"  [AVISO] {len(huerfanos)} devices ya estaban en el destino:")
                for d in huerfanos:
                    print(f"    {d[0]}  (se borran con el usuario)")

            mods = c.execute(
                "INSERT INTO usuario_modulos (usuario_id, modulo) "
                "SELECT %s, modulo FROM usuario_modulos WHERE usuario_id=%s "
                "ON CONFLICT DO NOTHING RETURNING modulo",
                (DESTINO, ORIGEN),
            ).fetchall()
            print(f"  modulos agregados: {[m[0] for m in mods] or '(ninguno nuevo)'}")

            borrado = c.execute(
                "DELETE FROM usuarios WHERE id=%s RETURNING nombre", (ORIGEN,)
            ).fetchone()
            print(f"  usuario borrado: {borrado[0]!r}")
        except Exception as e:
            c.execute("ROLLBACK")
            print(f"\n  EXCEPCION: {str(e)[:300]}")
            print("  ROLLBACK: no se toco nada.")
            return 1

        # --- despues, en la misma transaccion ---
        devs_n, mods_n = foto(DESTINO)
        sigue = c.execute(
            "SELECT COUNT(*) FROM usuarios WHERE id=%s", (ORIGEN,)
        ).fetchone()[0]
        sueltos = c.execute(
            "SELECT COUNT(*) FROM usuario_dispositivos d "
            "WHERE NOT EXISTS (SELECT 1 FROM usuarios u WHERE u.id=d.usuario_id)"
        ).fetchone()[0]
        total_devs = c.execute(
            "SELECT COUNT(*) FROM usuario_dispositivos"
        ).fetchone()[0]
        total_usuarios = c.execute("SELECT COUNT(*) FROM usuarios").fetchone()[0]

        print(f"\n  DESPUES {DESTINO}: {len(devs_n)} devices, {len(mods_n)} modulos {mods_n}")
        for d in devs_n:
            print(f"    {d}")
        print(f"  usuario {ORIGEN} existe: {bool(sigue)}")
        print(f"  dispositivos sin usuario: {sueltos}")
        print(f"  totales: {total_usuarios} usuarios, {total_devs} dispositivos")
        print()

        # --- que verificamos antes de confirmar ---
        esperado = set(devs_d) | set(devs_o)
        problemas = []
        if set(devs_n) != esperado:
            problemas.append(f"los devices no son los esperados: {set(devs_n)} vs {esperado}")
        if sigue:
            problemas.append(f"el usuario {ORIGEN} sigue existiendo")
        if sueltos:
            problemas.append(f"{sueltos} dispositivos quedaron sin usuario")
        if not set(mods_d).issubset(set(mods_n)):
            problemas.append("se perdio un modulo del destino")
        dup = c.execute(
            "SELECT COUNT(*) FROM (SELECT device_id FROM usuario_dispositivos "
            "GROUP BY device_id HAVING COUNT(*)>1) d"
        ).fetchone()[0]
        if dup:
            problemas.append(f"{dup} device_id quedaron en mas de una fila")

        if problemas:
            print("  PROBLEMAS:")
            for p in problemas:
                print(f"    - {p}")
            c.execute("ROLLBACK")
            print("\n  ROLLBACK: la base quedo como estaba.")
            return 1

        c.execute("COMMIT")
        print(f"  {len(devs_n)} devices, {len(mods_n)} modulos, sin problemas -> COMMIT")
        return 0


if __name__ == "__main__":
    sys.exit(main())
