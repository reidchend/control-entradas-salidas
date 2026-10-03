"""Respaldo de las 3 tablas que toca la fusion de usuarios, con los nombres
NUEVOS (post migracion 4). respaldar_antes_migrar.py usa los nombres viejos y
por eso no cubre usuarios ni habitaciones."""
import json
import os
import sys
from datetime import datetime

import psycopg

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESTINO = os.path.join(RAIZ, "tool", "respaldos")
TABLAS = ["usuarios", "usuario_modulos", "usuario_dispositivos"]


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

    os.makedirs(DESTINO, exist_ok=True)
    marca = datetime.now().strftime("%Y%m%d_%H%M%S")
    ruta = os.path.join(DESTINO, f"pre_fusion_{marca}.json")

    salida = {"generado": datetime.now().isoformat(), "tablas": {}}
    with psycopg.connect(url, connect_timeout=25) as c:
        for t in TABLAS:
            cols = [r[0] for r in c.execute(
                "SELECT column_name FROM information_schema.columns "
                "WHERE table_schema='public' AND table_name=%s ORDER BY ordinal_position",
                (t,),
            ).fetchall()]
            filas = c.execute(f'SELECT * FROM public."{t}"').fetchall()
            salida["tablas"][t] = {
                "columnas": cols,
                "filas": [{n: (str(v) if v is not None and not isinstance(v, (str, int, float, bool)) else v)
                           for n, v in zip(cols, f)} for f in filas],
            }
            print(f"  {t:24} {len(filas):3} filas, {len(cols)} columnas")

    with open(ruta, "w", encoding="utf-8") as fh:
        json.dump(salida, fh, ensure_ascii=False, indent=2)

    print(f"\nRespaldo: {os.path.relpath(ruta, RAIZ)}")
    print(f"Tamano: {os.path.getsize(ruta)} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
