"""Prueba funcional: hace lo que la app hace, con el rol control_app.

Un has_table_privilege=True no garantiza que el SQL real de la app pase.
Esto ejecuta las consultas que login y hosteleria usan de verdad, y hace un
INSERT/UPDATE/DELETE real (dentro de ROLLBACK) para probar los permisos de
escritura y las secuencias SERIAL.
"""
import os
import sys

import psycopg

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

PRUEBAS = [
    # (etiqueta, sql, parametros)
    (
        "login: usuarios por nombre (pos_repository)",
        "SELECT id, nombre, pin_hash, activo FROM usuarios "
        "WHERE LOWER(TRIM(nombre)) = LOWER(TRIM(%s)) LIMIT 1",
        ("Reidchend",),
    ),
    (
        "login: usuario por id (usuarios_repository)",
        "SELECT id, nombre, nivel, activo FROM usuarios WHERE id = %s",
        (1,),
    ),
    (
        "login: modulos del usuario (columna real: modulo)",
        "SELECT modulo FROM usuario_modulos "
        "WHERE usuario_id = %s ORDER BY modulo",
        (1,),
    ),
    (
        "autodetectacion: usuario por device_id",
        "SELECT u.nombre FROM usuario_dispositivos d "
        "JOIN usuarios u ON u.id = d.usuario_id WHERE d.device_id = %s",
        ("dispositivo_de_prueba",),
    ),
    (
        "autodetectacion: device_id con formato largo",
        "SELECT u.nombre FROM usuario_dispositivos d "
        "JOIN usuarios u ON u.id = d.usuario_id WHERE d.device_id = %s",
        ("web-1234abcd5678-" + "0" * 32,),
    ),
    (
        "hosteleria: habitaciones (hosteleria_repository)",
        "SELECT id, numero, estado FROM habitaciones ORDER BY numero LIMIT 5",
        (),
    ),
    (
        "hosteleria: tipos_habitacion",
        "SELECT id, nombre, capacidad FROM tipos_habitacion ORDER BY nombre",
        (),
    ),
    (
        "pos: lista usuarios para el selector",
        "SELECT id, nombre, nivel FROM usuarios WHERE activo = 1 ORDER BY nombre",
        (),
    ),
    (
        "pos: habitacion libre por fecha",
        "SELECT COUNT(*) FROM habitaciones WHERE estado = 'disponible'",
        (),
    ),
    (
        "cierres: FK a usuarios sigue viva",
        "SELECT COUNT(*) FROM pos_cierres WHERE usuario_id = %s",
        (1,),
    ),
    # --- administracion de usuarios (commit 4d14354, usuarios_tab) ---
    (
        "admin: listarTodos (con GROUP BY u.id y array_agg)",
        "SELECT u.*, "
        "       COALESCE(array_agg(m.modulo) FILTER (WHERE m.modulo IS NOT NULL), "
        "                '{}') AS modulos "
        "FROM usuarios u LEFT JOIN usuario_modulos m ON m.usuario_id = u.id "
        "GROUP BY u.id ORDER BY u.nombre",
        (),
    ),
    (
        "admin: listarTodos solo activos",
        "SELECT u.*, "
        "       COALESCE(array_agg(m.modulo) FILTER (WHERE m.modulo IS NOT NULL), "
        "                '{}') AS modulos "
        "FROM usuarios u LEFT JOIN usuario_modulos m ON m.usuario_id = u.id "
        "WHERE u.activo = 1 GROUP BY u.id ORDER BY u.nombre",
        (),
    ),
    (
        "admin: dispositivosDe(usuario)",
        "SELECT device_id, configurado_en FROM usuario_dispositivos "
        "WHERE usuario_id = %s ORDER BY configurado_en DESC NULLS LAST",
        (2,),
    ),
    (
        "admin: getUsuarioDispositivo (desvincular el propio)",
        "SELECT u.id, u.nombre, u.pin_hash, d.configurado_en "
        "FROM usuario_dispositivos d JOIN usuarios u ON u.id = d.usuario_id "
        "WHERE d.device_id = %s "
        "ORDER BY d.configurado_en DESC NULLS LAST, d.id DESC LIMIT 1",
        ("acc2a6f6-18d2-479d-b926-dca36971d675",),
    ),
]


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
        rol = c.execute("SELECT current_user").fetchone()[0]
        print(f"=== rol de la app: {rol} ===\n")

        fallos = 0
        print("--- lecturas ---")
        for etiqueta, sql, params in PRUEBAS:
            # Un SAVEPOINT por prueba: sin esto, el primer error aborta la
            # transaccion entera y todas las demas pruebas mienten con
            # "transaccion abortada".
            c.execute("SAVEPOINT p")
            try:
                filas = c.execute(sql, params).fetchall()
                muestra = ", ".join(str(f[0]) for f in filas[:4])
                print(f"  [OK   ] {etiqueta:52} {len(filas)} filas  [{muestra}]")
            except Exception as e:
                fallos += 1
                print(f"  [FALLA] {etiqueta:52} {str(e).split(chr(10))[0][:70]}")
            finally:
                c.execute("ROLLBACK TO SAVEPOINT p")

        print("\n--- escrituras (ROLLBACK) ---")
        # INSERT en cada tabla con SERIAL, para probar la secuencia.
        # Los nombres de columna son los REALES de la base, no los supuestos:
        # usuarios usa updated_at (no actualizado_en), usuario_dispositivos
        # usa configurado_en (no creado_en), usuario_modulos no tiene id, y
        # hosteleria_reservas exige huesped_id y modalidad.
        # Los valores se sacan de la base con subconsultas en vez de a mano:
        # la habitacion 1 no existe y (1,'hosteleria') ya estaba en
        # usuario_modulos, y un id inventado rompe la FK.
        escrituras = [
            (
                "INSERT usuario_dispositivos (usuario_id, device_id)",
                "INSERT INTO usuario_dispositivos "
                "(usuario_id, device_id, configurado_en) "
                "VALUES (1, 'dispositivo_de_prueba', now()) RETURNING id",
                (),
            ),
            (
                "INSERT hosteleria_huespedes (nombre, cedula)",
                "INSERT INTO hosteleria_huespedes (nombre, cedula, creado_en) "
                "VALUES (%s, %s, now()) RETURNING id",
                ("Huesped Prueba", "999999999"),
            ),
            (
                "INSERT hosteleria_reservas (FKs reales, valores de enum reales)",
                "INSERT INTO hosteleria_reservas "
                "(habitacion_id, huesped_id, fecha_inicio, fecha_fin, estado, "
                "modalidad, creado_en) "
                "SELECT h.id, %s, CURRENT_DATE, CURRENT_DATE, 'reservada', "
                "'noche', now() FROM habitaciones h ORDER BY h.id LIMIT 1 "
                "RETURNING id",
                (1,),
            ),
            (
                "INSERT usuario_modulos (PK usuario_id+modulo, valor valido)",
                "INSERT INTO usuario_modulos (usuario_id, modulo) "
                "SELECT 1, 'pos' WHERE NOT EXISTS ("
                "  SELECT 1 FROM usuario_modulos "
                "  WHERE usuario_id = 1 AND modulo = 'pos') "
                "RETURNING usuario_id, modulo",
                (),
            ),
            (
                "UPDATE usuarios (columna real: updated_at)",
                "UPDATE usuarios SET updated_at = now() WHERE id = %s RETURNING id",
                (1,),
            ),
            (
                "INSERT en usuarios (SERIAL, no hay que poner id)",
                "INSERT INTO usuarios (nombre, pin_hash, nivel, activo, creado_en) "
                "VALUES (%s, %s, 'operador', 1, now()::text) RETURNING id",
                ("Prueba Escritura", "x" * 64),
            ),
            (
                "admin: desvincularDeUsuario (DELETE por usuario+device)",
                "DELETE FROM usuario_dispositivos "
                "WHERE usuario_id = 2 AND device_id = %s RETURNING device_id",
                ("device_que_no_existe_xyz",),
            ),
            (
                "admin: eliminar() de un usuario SIN cierres",
                "WITH u AS (SELECT id FROM usuarios "
                "  WHERE NOT EXISTS (SELECT 1 FROM pos_cierres WHERE usuario_id = usuarios.id) "
                "  ORDER BY id DESC LIMIT 1) "
                "DELETE FROM usuarios WHERE id IN (SELECT id FROM u) RETURNING id",
                (),
            ),
        ]
        for etiqueta, sql, params in escrituras:
            c.execute("SAVEPOINT p")
            try:
                # hosteleria_huespedes esta vacia, asi que la reserva necesita
                # su propio huesped primero para no romper la FK. El id se
                # toma del RETURNING: la secuencia ya avanzo y un id fijo
                # (1) no existe.
                if etiqueta.startswith("INSERT hosteleria_reservas"):
                    gid = c.execute(
                        "INSERT INTO hosteleria_huespedes (nombre, creado_en) "
                        "VALUES ('Huesped Escritura', now()) RETURNING id"
                    ).fetchone()[0]
                    params = (gid,) + params[1:]
                fila = c.execute(sql, params).fetchone()
                print(f"  [OK   ] {etiqueta:52} {fila}")
            except Exception as e:
                fallos += 1
                print(f"  [FALLA] {etiqueta:52} {str(e).split(chr(10))[0][:70]}")
            finally:
                c.execute("ROLLBACK TO SAVEPOINT p")

        print()
        print("--- los valores de enum de Dart pasan los CHECK de la BD ---")
        # HostelReservaEstado.toDb() y ModalidadEstancia.toDb() devuelven
        # enum.name. Si un valor no estuviera en el CHECK, la escritura
        # fallaria en produccion y aca se veria antes.
        combos = [
            ("reservada", "noche"), ("reservada", "horas"),
            ("ocupada", "noche"), ("ocupada", "horas"),
            ("cancelada", "noche"), ("finalizada", "horas"),
        ]
        huesped_id = None
        c.execute("SAVEPOINT p2")
        try:
            huesped_id = c.execute(
                "INSERT INTO hosteleria_huespedes (nombre, creado_en) "
                "VALUES ('Huesped Enum', now()) RETURNING id"
            ).fetchone()[0]
            print(f"  (huesped auxiliar id={huesped_id}, en su propio savepoint)")
        except Exception as e:
            fallos += 1
            print(f"  [FALLA] no se pudo crear el huesped: {str(e).split(chr(10))[0][:60]}")
        finally:
            # Se deja vivo para que los INSERT de reservas tengan una FK real.
            # El ROLLBACK final lo borra igual.
            pass

        for estado, modalidad in combos:
            c.execute("SAVEPOINT p")
            try:
                if huesped_id is None:
                    raise RuntimeError("no hay huesped auxiliar")
                c.execute(
                    "INSERT INTO hosteleria_reservas "
                    "(habitacion_id, huesped_id, fecha_inicio, fecha_fin, estado, "
                    "modalidad, creado_en) "
                    "SELECT h.id, %s, CURRENT_DATE, CURRENT_DATE, %s, %s, now() "
                    "FROM habitaciones h ORDER BY h.id LIMIT 1",
                    (huesped_id, estado, modalidad),
                )
                print(f"  [OK   ] estado={estado:11} modalidad={modalidad}")
            except Exception as e:
                fallos += 1
                msg = str(e).split("\n")[0][:60]
                print(f"  [FALLA] estado={estado:11} modalidad={modalidad}  {msg}")
            finally:
                c.execute("ROLLBACK TO SAVEPOINT p")

        print()
        print("--- modulos validos ---")
        for m in ("pos", "inventario", "hosteleria"):
            c.execute("SAVEPOINT p")
            try:
                c.execute(
                    "INSERT INTO usuario_modulos (usuario_id, modulo) "
                    "SELECT 1, %s WHERE NOT EXISTS ("
                    "  SELECT 1 FROM usuario_modulos "
                    "  WHERE usuario_id = 1 AND modulo = %s) RETURNING modulo",
                    (m, m),
                )
                print(f"  [OK   ] modulo={m}")
            except Exception as e:
                fallos += 1
                print(f"  [FALLA] modulo={m}  {str(e).split(chr(10))[0][:60]}")
            finally:
                c.execute("ROLLBACK TO SAVEPOINT p")

        c.execute("ROLLBACK")
        print("\n  ROLLBACK hecho: la base quedo como estaba.")

        print("\n--- confirmacion: nada quedo escrito ---")
        for etiqueta, sql in (
            ("usuario_dispositivos", "SELECT COUNT(*) FROM usuario_dispositivos"),
            ("hosteleria_huespedes", "SELECT COUNT(*) FROM hosteleria_huespedes"),
            ("hosteleria_reservas", "SELECT COUNT(*) FROM hosteleria_reservas"),
            ("usuarios", "SELECT COUNT(*) FROM usuarios"),
            ("usuario_modulos", "SELECT COUNT(*) FROM usuario_modulos"),
        ):
            n = c.execute(sql).fetchone()[0]
            print(f"  {etiqueta:26} {n} filas")

    print()
    if fallos:
        print(f"  {fallos} prueba(s) fallaron")
        return 1
    print(f"  todas las consultas de la app funcionan con {rol}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
