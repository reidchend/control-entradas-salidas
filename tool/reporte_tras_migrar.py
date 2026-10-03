"""Como quedaron los datos despues de las 4 migraciones, y los 3 avisos
que quedaron abiertos: tipos_habitacion vacia, usuarios con typos y
dispositivo_usuario huerfana."""
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
        print("=== 1. tipos_habitacion ===")
        n = c.execute("SELECT COUNT(*) FROM tipos_habitacion").fetchone()[0]
        print(f"  {n} filas")
        if n == 0:
            print("  AVISO: el catalogo de tipos quedo vacio. Las 39 habitaciones")
            print("         tienen tipo_id NULL, y el selector de tipo en la UI")
            print("         no tendra nada que mostrar.")
        sin_tipo = c.execute(
            "SELECT COUNT(*) FROM habitaciones WHERE tipo_id IS NULL"
        ).fetchone()[0]
        print(f"  habitaciones sin tipo_id: {sin_tipo}")
        tipos_texto = c.execute(
            "SELECT tipo, COUNT(*) FROM habitaciones WHERE tipo IS NOT NULL "
            "GROUP BY tipo ORDER BY 2 DESC LIMIT 10"
        ).fetchall()
        print(f"  columna legacy tipo (text): {tipos_texto if tipos_texto else 'todos NULL'}")
        print()

        print("=== 2. estado de las habitaciones (columna nueva) ===")
        for estado, n in c.execute(
            "SELECT estado, COUNT(*) FROM habitaciones GROUP BY estado ORDER BY 2 DESC"
        ).fetchall():
            print(f"  {estado:16} {n}")
        print()

        total_usuarios = c.execute("SELECT COUNT(*) FROM usuarios").fetchone()[0]
        print(f"=== 3. usuarios: los {total_usuarios} ===")
        for r in c.execute(
            "SELECT id, nombre, nivel, activo, "
            "CASE WHEN pin_hash IS NULL OR pin_hash='' THEN 'sin PIN' "
            "     ELSE 'sha256' END "
            "FROM usuarios ORDER BY id"
        ).fetchall():
            print(f"  {r[0]:3} {r[1]:26} {r[2]:14} activo={r[3]}  {r[4]}")
        print()

        print("=== 4. los 7 creados desde dispositivo_usuario (typos) ===")
        nuevos = c.execute(
            "SELECT u.id, u.nombre, "
            "(SELECT COUNT(*) FROM usuario_modulos m WHERE m.usuario_id=u.id) mods "
            "FROM usuarios u ORDER BY u.id"
        ).fetchall()
        for i, nombre, mods in nuevos[7:]:
            print(f"  {i:3} {nombre:26} modulos={mods}")
        print()

        print("=== 5. usuario_dispositivos vs dispositivo_usuario ===")
        a = c.execute("SELECT COUNT(*) FROM usuario_dispositivos").fetchone()[0]
        b = c.execute("SELECT COUNT(*) FROM dispositivo_usuario").fetchone()[0]
        print(f"  usuario_dispositivos  {a} filas  (sistema nuevo, PIN hasheado)")
        print(f"  dispositivo_usuario   {b} filas  (sistema viejo, PIN en texto plano)")
        huerf = c.execute(
            "SELECT COUNT(*) FROM dispositivo_usuario d "
            "WHERE NOT EXISTS (SELECT 1 FROM usuarios u "
            "  WHERE LOWER(TRIM(u.nombre)) = LOWER(TRIM(d.nombre)))"
        ).fetchone()[0]
        print(f"  filas de la vieja cuyo nombre no matchea ningun usuario: {huerf}")
        sin_match = c.execute(
            "SELECT COUNT(*) FROM dispositivo_usuario d "
            "WHERE NOT EXISTS (SELECT 1 FROM usuario_dispositivos ud "
            "  JOIN usuarios u ON u.id=ud.usuario_id "
            "  WHERE LOWER(TRIM(u.nombre)) = LOWER(TRIM(d.nombre)))"
        ).fetchone()[0]
        print(f"  filas de la vieja sin equivalente en la nueva: {sin_match}")
        if huerf or sin_match:
            print("  (esperado: las filas cuyo nombre se fusiono o se borro. La tabla")
            print("   vieja ya no la lee la app; queda solo como registro.)")
            for r in c.execute(
                "SELECT DISTINCT d.nombre FROM dispositivo_usuario d "
                "WHERE NOT EXISTS (SELECT 1 FROM usuarios u "
                "  WHERE LOWER(TRIM(u.nombre)) = LOWER(TRIM(d.nombre)))"
            ).fetchall():
                n = c.execute(
                    "SELECT COUNT(*) FROM dispositivo_usuario WHERE nombre=%s", (r[0],)
                ).fetchone()[0]
                print(f"    {r[0]!r}  ({n} fila(s) en la tabla vieja)")
        print()

        print("=== 6. hosteleria: todo vacio todavia ===")
        for t in ("hosteleria_huespedes", "hosteleria_reservas",
                  "hosteleria_reserva_personas", "hosteleria_vehiculos"):
            print(f"  {t:28} {c.execute(f'SELECT COUNT(*) FROM {t}').fetchone()[0]} filas")

    return 0


if __name__ == "__main__":
    sys.exit(main())
