"""Respaldo de las tablas que tocan las 4 migraciones de hosteleria.

Guardo datos y definicion en tool/respaldos/ con timestamp. Solo las tablas que
las migraciones renombran, crean o de las que leen datos: pos_usuarios,
dispositivo_usuario y pos_habitaciones son chicas (7 + 16 + 39 filas).
"""
import json
import os
import sys
from datetime import datetime

import psycopg

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESTINO = os.path.join(RAIZ, "tool", "respaldos")

TABLAS = ["pos_usuarios", "dispositivo_usuario", "pos_habitaciones", "pos_cierres"]


def leer_env():
    v = {}
    with open(os.path.join(RAIZ, ".env.local"), encoding="utf-8") as fh:
        for linea in fh:
            linea = linea.strip()
            if not linea or linea.startswith("#") or "=" not in linea:
                continue
            k, _, val = linea.partition("=")
            v[k.strip()] = val.strip().strip("'").strip('"')
    return v


def jsonable(v):
    if isinstance(v, (str, int, float, bool)) or v is None:
        return v
    return str(v)


def main():
    env = leer_env()
    url = env.get("DATABASE_URL_UNPOOLED") or env.get("DATABASE_URL")
    os.makedirs(DESTINO, exist_ok=True)
    marca = datetime.now().strftime("%Y%m%d_%H%M%S")
    ruta = os.path.join(DESTINO, f"pre_hosteleria_{marca}.json")

    salida = {"generado": datetime.now().isoformat(), "tablas": {}}
    with psycopg.connect(url, connect_timeout=25) as c:
        for t in TABLAS:
            existe = c.execute("SELECT to_regclass(%s)", (f"public.{t}",)).fetchone()[0]
            if not existe:
                salida["tablas"][t] = {"existe": False}
                print(f"  {t}: no existe, se omite")
                continue
            cols = c.execute(
                "SELECT column_name FROM information_schema.columns "
                "WHERE table_schema='public' AND table_name=%s ORDER BY ordinal_position",
                (t,),
            ).fetchall()
            nombres = [r[0] for r in cols]
            filas = c.execute(f'SELECT * FROM public."{t}"').fetchall()
            datos = [
                {n: jsonable(v) for n, v in zip(nombres, fila)} for fila in filas
            ]
            salida["tablas"][t] = {
                "existe": True,
                "columnas": nombres,
                "filas": datos,
            }
            print(f"  {t}: {len(datos)} filas, {len(nombres)} columnas")

    with open(ruta, "w", encoding="utf-8") as fh:
        json.dump(salida, fh, ensure_ascii=False, indent=2)

    print()
    print(f"Respaldo: {os.path.relpath(ruta, RAIZ)}")
    print(f"Tamano: {os.path.getsize(ruta)} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
