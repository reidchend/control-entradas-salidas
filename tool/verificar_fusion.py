"""Verifica la fusion con las consultas que la app usa de verdad:
la autodeteccion por device_id y el login por nombre."""
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

    fallos = 0
    with psycopg.connect(url, connect_timeout=25) as c:
        print("=== autodeteccion por device_id (lo que hace login al abrir) ===")
        for dev, nombre_esperado in (
            ("c287299f-6989-4081-833b-272309aed6d7", "Reidchend"),
            ("33ac9f07-373b-44dd-9700-756b23980f10", "Reidchend"),
            ("acc2a6f6-18d2-479d-b926-dca36971d675", "Reidchend"),
        ):
            r = c.execute(
                "SELECT u.nombre FROM usuario_dispositivos d "
                "JOIN usuarios u ON u.id=d.usuario_id WHERE d.device_id=%s",
                (dev,),
            ).fetchone()
            real = r[0] if r else None
            if real == nombre_esperado:
                print(f"  [OK   ] {dev[:8]}... -> {real}")
            else:
                fallos += 1
                print(f"  [FALLA] {dev[:8]}... -> {real}, esperaba {nombre_esperado}")

        print("\n=== el nombre mal escrito ya no existe ===")
        n = c.execute(
            "SELECT COUNT(*) FROM usuarios WHERE LOWER(nombre)='reidched'"
        ).fetchone()[0]
        if n == 0:
            print("  [OK   ] 'reidched' no esta en usuarios")
        else:
            fallos += 1
            print(f"  [FALLA] 'reidched' sigue en usuarios ({n} filas)")

        print("\n=== login por nombre (pos_repository) ===")
        for nombre in ("Reidchend", "reidched", "REIDCHEND"):
            r = c.execute(
                "SELECT id, nivel FROM usuarios "
                "WHERE LOWER(TRIM(nombre)) = LOWER(TRIM(%s))", (nombre,)
            ).fetchone()
            print(f"  {nombre:12} -> {r[0] if r else 'SIN MATCH'}")

        print("\n=== integridad de las 3 tablas ===")
        for etiqueta, sql, esperado in (
            ("usuarios duplicados por nombre",
             "SELECT COUNT(*) FROM (SELECT LOWER(TRIM(nombre)) k FROM usuarios "
             "GROUP BY 1 HAVING COUNT(*)>1) d", 0),
            ("device_id en mas de una fila",
             "SELECT COUNT(*) FROM (SELECT device_id FROM usuario_dispositivos "
             "GROUP BY 1 HAVING COUNT(*)>1) d", 0),
            ("dispositivos sin usuario",
             "SELECT COUNT(*) FROM usuario_dispositivos d "
             "WHERE NOT EXISTS (SELECT 1 FROM usuarios u WHERE u.id=d.usuario_id)", 0),
            ("modulos sin usuario",
             "SELECT COUNT(*) FROM usuario_modulos m "
             "WHERE NOT EXISTS (SELECT 1 FROM usuarios u WHERE u.id=m.usuario_id)", 0),
            ("usuarios sin pin y sin modulo (inutilizables)",
             "SELECT COUNT(*) FROM usuarios u "
             "WHERE (u.pin_hash IS NULL OR u.pin_hash='') "
             "  AND NOT EXISTS (SELECT 1 FROM usuario_modulos m WHERE m.usuario_id=u.id)", 0),
        ):
            n = c.execute(sql).fetchone()[0]
            marca = "OK   " if n == esperado else "FALLA"
            if n != esperado:
                fallos += 1
            print(f"  [{marca}] {etiqueta:46} {n}")

        print("\n=== como quedo el usuario 2 ===")
        r = c.execute(
            "SELECT id, nombre, nivel, activo, pin_hash FROM usuarios WHERE id=2"
        ).fetchone()
        print(f"  {r[0]} {r[1]} nivel={r[2]} activo={r[3]}")
        print(f"  pin_hash={r[4][:20]}...")
        print(f"  modulos: "
              f"{[x[0] for x in c.execute('SELECT modulo FROM usuario_modulos WHERE usuario_id=2 ORDER BY modulo').fetchall()]}")
        print(f"  devices: {c.execute('SELECT COUNT(*) FROM usuario_dispositivos WHERE usuario_id=2').fetchone()[0]}")

    print()
    if fallos:
        print(f"  {fallos} verificacion(es) fallaron")
        return 1
    print("  la fusion quedo consistente")
    return 0


if __name__ == "__main__":
    sys.exit(main())
