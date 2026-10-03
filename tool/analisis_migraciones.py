"""Analiza las 4 migraciones de hosteleria contra la base real, sin aplicar nada.

Responde: que falta, que va a fallar y en que orden. Todo de solo lectura.
"""
import os
import sys

import psycopg

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def leer_env():
    valores = {}
    with open(os.path.join(RAIZ, ".env.local"), encoding="utf-8") as fh:
        for linea in fh:
            linea = linea.strip()
            if not linea or linea.startswith("#") or "=" not in linea:
                continue
            k, _, v = linea.partition("=")
            valores[k.strip()] = v.strip().strip("'").strip('"')
    return valores


def main():
    env = leer_env()
    url = env.get("DATABASE_URL_UNPOOLED") or env.get("DATABASE_URL")
    if not url:
        print("no hay DATABASE_URL en .env.local")
        return 1

    problemas = []
    with psycopg.connect(url, connect_timeout=25) as c:
        def existe(objeto):
            return c.execute("SELECT to_regclass(%s)", (f"public.{objeto}",)).fetchone()[0]

        def columnas(tabla):
            return {
                r[0]: r[1]
                for r in c.execute(
                    "SELECT column_name, data_type FROM information_schema.columns "
                    "WHERE table_schema='public' AND table_name=%s",
                    (tabla,),
                ).fetchall()
            }

        def tiene_columna(tabla, col):
            return col in columnas(tabla)

        print("=== ESTADO ACTUAL DE LA BASE ===\n")
        print("Tablas que las migraciones tocan:")
        for t in (
            "pos_usuarios", "usuarios", "usuario_modulos", "usuario_dispositivos",
            "dispositivo_usuario", "pos_habitaciones", "habitaciones",
            "pos_tipos_habitacion", "tipos_habitacion",
            "hosteleria_huespedes", "hosteleria_reservas",
            "hosteleria_reserva_personas", "hosteleria_vehiculos",
        ):
            print(f"  {t:32} {'EXISTE' if existe(t) else '-'}")
        print()

        print("Precondiciones:")
        fn = c.execute(
            "SELECT COUNT(*) FROM pg_proc WHERE proname='set_pos_updated_at'"
        ).fetchone()[0]
        print(f"  set_pos_updated_at() existe: {fn > 0}  ({fn} overloads)")
        if fn == 0:
            problemas.append("falta set_pos_updated_at(): los triggers de las migraciones 1, 2 y 3 fallan")

        ext = c.execute(
            "SELECT COUNT(*) FROM pg_extension WHERE extname='pgcrypto'"
        ).fetchone()[0]
        print(f"  pgcrypto instalada: {ext > 0}")
        if ext == 0:
            problemas.append("falta pgcrypto: digest() no existiria (migracion 2, linea 124)")

        print()

        print("=== MIGRACION 1: 20261002000000_hosteleria.sql ===")
        m1 = []
        if not existe("pos_habitaciones"):
            m1.append("FALLA: hosteleria_reservas referenciecia pos_habitaciones(id) y esa tabla no esta")
        else:
            tipos = c.execute(
                "SELECT data_type FROM information_schema.columns "
                "WHERE table_name='pos_habitaciones' AND column_name='id'"
            ).fetchone()
            print(f"  pos_habitaciones.id es {tipos[0] if tipos else '?'} (la FK pide INTEGER)")
            if not tipos or tipos[0] != "integer":
                m1.append(f"FK incompatible: pos_habitaciones.id es {tipos[0] if tipos else '?'}, la FK pide integer")
        print(f"  hosteleria_huespedes: {'ya existe' if existe('hosteleria_huespedes') else 'se crea'}")
        print(f"  hosteleria_reservas:  {'ya existe' if existe('hosteleria_reservas') else 'se crea'}")
        problemas.extend(f"M1: {x}" for x in m1)
        print()

        print("=== MIGRACION 2: 20261002010000_usuarios_centrales.sql ===")
        m2 = []
        pu, us = existe("pos_usuarios"), existe("usuarios")
        print(f"  pos_usuarios={pu}  usuarios={us}  -> {'RENOMBRA' if pu and not us else 'sin renombrar'}")
        if not pu and not us:
            m2.append("NO existe pos_usuarios ni usuarios: el ALTER TABLE usuarios de la linea 30 falla")
        if pu and us:
            m2.append("existen AMBAS: la tabla de origem quedo a la mitad de una corrida anterior")

        if pu:
            cols = columnas("pos_usuarios")
            print(f"  columnas de pos_usuarios: {sorted(cols)}")
            for req in ("id", "nombre", "pin_hash"):
                if req not in cols:
                    m2.append(f"pos_usuarios no tiene {req}: la migracion lo necesita")
            print(f"  id es {cols.get('id')} (usuario_modulos pide INTEGER)")
            if cols.get("id") != "integer":
                m2.append(f"usuario_modulos.usuario_id es INTEGER pero pos_usuarios.id es {cols.get('id')}")
            for req in ("activo", "creado_en"):
                if req not in cols:
                    m2.append(f"pos_usuarios no tiene {req}: el INSERT de la linea 126 lo escribe")
            legacy = [c for c in ("es_admin", "es_desarrollador") if c in cols]
            print(f"  banderas viejas presentes: {legacy or 'ninguna (el backfill no hara nada)'}")
            if not legacy:
                print("    -> nivel queda en 'basico' para todos salvo que se backfille a mano")

            # Los PIN de pos_usuarios: el formato de pin_hash cambia de linea
            n = c.execute("SELECT COUNT(*) FROM pos_usuarios").fetchone()[0]
            muestra = c.execute(
                "SELECT nombre, left(coalesce(pin_hash,''), 12), length(coalesce(pin_hash,'')) "
                "FROM pos_usuarios ORDER BY id LIMIT 5"
            ).fetchall()
            print(f"  usuarios en pos_usuarios: {n}")
            for nom, pin, largo in muestra:
                print(f"    {nom!r:22} pin_hash={pin!r} len={largo}")

        du = c.execute("SELECT COUNT(*) FROM dispositivo_usuario").fetchone()[0]
        print(f"  filas en dispositivo_usuario a migrar: {du}")
        nombres = c.execute(
            "SELECT LOWER(TRIM(nombre)), COUNT(*), COUNT(DISTINCT device_id) "
            "FROM dispositivo_usuario GROUP BY 1 ORDER BY 2 DESC"
        ).fetchall()
        for clave, filas, devs in nombres:
            print(f"    {clave!r:22} filas={filas} devices={devs}")
        problemas.extend(f"M2: {x}" for x in m2)
        print()

        print("=== MIGRACION 3: 20261002020000_hosteleria_checkin.sql ===")
        m3 = []
        if not existe("pos_habitaciones"):
            m3.append("ALTER TABLE pos_habitaciones falla: no existe todavia (aplicar M1 antes)")
        else:
            n = c.execute(
                "SELECT COUNT(*), COUNT(*) FILTER (WHERE tipo IS NOT NULL AND TRIM(tipo)<>''), "
                "COUNT(DISTINCT TRIM(tipo)) FILTER (WHERE tipo IS NOT NULL AND TRIM(tipo)<>'') "
                "FROM pos_habitaciones"
            ).fetchone()
            print(f"  pos_habitaciones: {n[0]} filas, {n[1]} con tipo, {n[2]} tipos distintos")
            print("    -> se siembran como pos_tipos_habitacion y se enlazan por TRIM(tipo)")
        if not existe("hosteleria_huespedes"):
            m3.append("ALTER TABLE hosteleria_huespedes falla: no existe todavia (aplicar M1 antes)")
        if not existe("hosteleria_reservas"):
            m3.append("ALTER TABLE hosteleria_reservas falla: no existe todavia (aplicar M1 antes)")
        problemas.extend(f"M3: {x}" for x in m3)
        print()

        print("=== MIGRACION 4: 20261002030000_habitaciones_estados_op.sql ===")
        m4 = []
        for viejo, nuevo in (("pos_habitaciones", "habitaciones"),
                             ("pos_tipos_habitacion", "tipos_habitacion")):
            v, n = existe(viejo), existe(nuevo)
            print(f"  {viejo}={v}  {nuevo}={n}  -> {'RENOMBRA' if v and not n else 'OJO'}")
            if v and n:
                m4.append(f"{viejo} y {nuevo} coexisten: renombrar {viejo} a {nuevo} falla por colision")
            if not v and not n:
                m4.append(f"no existe {viejo} ni {nuevo}: el ALTER siguiente sobre {nuevo} falla")
        # Quiere el codigo viejo referring pos_habitaciones?
        print("  -> el codigo ya consulta 'habitaciones' y 'tipos_habitacion' (lib/features/hosteleria, pos_repository)")
        problemas.extend(f"M4: {x}" for x in m4)
        print()

        print("=== ORDEN REQUERIDO ===")
        print("  1 -> 2 -> 3 -> 4")
        print("  M1 define hosteleria_* que M3 altera.")
        print("  M2 renombra pos_usuarios; M4 renombra pos_habitaciones.")
        print("  M3 crea pos_tipos_habitacion que M4 renombra.")
        print("  M4 va LASTIMA porque el codigo nuevo ya usa los nombres finales.")

        if problemas:
            print()
            print("=== PROBLEMAS DETECTADOS ===")
            for p in problemas:
                print(f"  - {p}")
        else:
            print()
            print("Sin bloqueos. Las 4 se pueden aplicar en orden.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
