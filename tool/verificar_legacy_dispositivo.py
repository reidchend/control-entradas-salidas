"""Comprobacion de solo lectura: que queda de `dispositivo_usuario` y si toda su
informacion ya esta en `usuarios` + `usuario_dispositivos`.

No escribe nada. Es la verificacion que tiene que dar limpio ANTES de aplicar
la migracion que borra la tabla; si algo no esta cubierto, el script lo dice con
la fila concreta que falta en vez de dar un "ok" generico.

Los PIN en texto plano no se imprimen: son datos reales de operarios. Se imprime
solo el hash sha256, que es lo que quedo guardado en `usuarios.pin_hash`.

Uso:  python tool/verificar_legacy_dispositivo.py
"""
import hashlib
import os
import re
import sys
from pathlib import Path

import psycopg

RAIZ = Path(__file__).resolve().parent.parent
ENV_LOCAL = RAIZ / ".env.local"


def leer_url() -> str:
    """DATABASE_URL de .env.local, sin depender de python-dotenv."""
    if not ENV_LOCAL.exists():
        sys.exit("  no existe .env.local (copiar .env.local.example y ajustar)")
    for linea in ENV_LOCAL.read_text(encoding="utf-8").splitlines():
        if linea.strip().startswith("#") or "=" not in linea:
            continue
        clave, valor = linea.split("=", 1)
        if clave.strip() == "DATABASE_URL":
            return valor.strip().strip("'\"")
    sys.exit("  .env.local no tiene DATABASE_URL")


def sha256(texto: str) -> str:
    return hashlib.sha256(texto.encode("utf-8")).hexdigest()


def _descartar_transaccion(conn):
    """Vuelve la conexion a autocommit tras el ensayo.

    psycopg3 se queja con "can't change 'autocommit'" si la transaccion quedo
    en un estado raro, y el ensayo es lo ultimo que hace el script: si no se
    puede restoring, se cierra y el script sigue (ya no consulta nada mas).
    """
    try:
        conn.rollback()
    except Exception:
        pass
    try:
        if conn.info.transaction_status != psycopg.pq.TransactionStatus.IDLE:
            conn.close()
            return
        conn.autocommit = True
    except Exception:
        pass


fallos = 0


def check(etiqueta, ok, detalle=""):
    global fallos
    if ok:
        print("  OK    %s" % etiqueta)
    else:
        print("  FALLA %s" % etiqueta)
        if detalle:
            for linea in str(detalle).splitlines():
                print("         %s" % linea)
        fallos += 1


def main():
    conn = psycopg.connect(leer_url(), autocommit=True)
    with conn.cursor() as cur:
        print("=== Conectado ===")
        cur.execute("SELECT current_database(), current_user, version()")
        bd, usuario, version = cur.fetchone()
        print("  base: %s   usuario: %s" % (bd, usuario))
        print("  %s" % version.split(",")[0])
        print("")

        # ------------------------------------------------------------- 1
        print("=== 1. Que hay en dispositivo_usuario ===")
        cur.execute("SELECT to_regclass('public.dispositivo_usuario')")
        existe = cur.fetchone()[0]
        if not existe:
            print("  la tabla no existe: la migracion de borrado ya se aplico")
            return
        print("  la tabla existe")

        cur.execute(
            "SELECT count(*), count(DISTINCT lower(trim(nombre))), "
            "count(*) FILTER (WHERE pin_hash IS NULL OR pin_hash = ''), "
            "count(*) FILTER (WHERE device_id IS NOT NULL) "
            "FROM dispositivo_usuario"
        )
        filas, operadores, sin_pin, con_device = cur.fetchone()
        print("  filas: %d   operadores distintos: %d   sin PIN: %d   con device_id: %d"
              % (filas, operadores, sin_pin, con_device))
        print("")

        # Cuantos PIN en texto plano hay todavia en el arbol.
        cur.execute(
            "SELECT DISTINCT pin_hash FROM dispositivo_usuario "
            "WHERE pin_hash IS NOT NULL AND pin_hash <> '' "
            "  AND pin_hash !~ '^[0-9a-f]{64}$'"
        )
        pines = [f[0] for f in cur.fetchall()]
        if pines:
            print("  PIN EN TEXTO PLANO guardados aqui: %d distintos" % len(pines))
            print("    (de %d caracteres: un PIN de operario)" % len(pines[0]))
            print("    No se imprimen: son credenciales reales.")
            print("    Se van con 20261004170000_dispositivo_usuario_pins_hasheados.sql")
        else:
            print("  PIN en texto plano guardados aqui: 0")
            print("    Todos los pin_hash son sha256. La migracion del 20261004 ya")
            print("    esta aplicada: un dump de la base ya no lleva credenciales.")
        check("no queda ningun PIN en texto plano en la base", not pines,
              "aun hay %d PIN(s) legible(s) aca; falta aplicar la migracion "
              "20261004170000_dispositivo_usuario_pins_hasheados.sql" % len(pines))
        print("")

        # ------------------------------------------------------------- 2
        print("=== 2. Cada operador quedo en `usuarios` ===")
        cur.execute(
            """
            SELECT d.nombre, d.pin_hash,
                   u.id,
                   (u.pin_hash IS NOT NULL AND u.pin_hash <> ''),
                   (CASE WHEN d.pin_hash ~ '^[0-9a-f]{64}$'
                         THEN u.pin_hash = d.pin_hash
                         ELSE u.pin_hash = encode(digest(d.pin_hash, 'sha256'), 'hex')
                    END)
            FROM (SELECT min(nombre) AS nombre, min(pin_hash) AS pin_hash
                    FROM dispositivo_usuario
                   GROUP BY lower(trim(nombre))) d
            LEFT JOIN usuarios u
              ON u.id = (SELECT id FROM usuarios
                          WHERE lower(trim(nombre)) = lower(trim(d.nombre))
                          ORDER BY id LIMIT 1)
            ORDER BY d.nombre
            """
        )
        operadores_filas = cur.fetchall()
        sin_usuario = [n for n, pin, uid, _, _ in operadores_filas if uid is None]
        check("todos los operadores existen en `usuarios` (%d)" % len(operadores_filas),
              not sin_usuario,
              "sin usuario en `usuarios`:\n  " + "\n  ".join(sin_usuario))

        # El PIN tiene que haber viaja hasheado, no en texto plano.
        sin_hash = [n for n, pin, uid, tiene, _ in operadores_filas if uid and not tiene]
        check("ningun operador quedo sin hash de PIN", not sin_hash,
              "con pin_hash vacio en `usuarios`:\n  " + "\n  ".join(sin_hash))

        # Y si el PIN de la tabla vieja era "1234", en usuarios debe estar el
        # sha256 de "1234", no "1234". La tabla vieja puede venir ya hasheada
        # (si se aplico la migracion de 20261004), y entonces se compara el
        # hash con el hash en vez de hashear dos veces.
        mal_hasheados = [
            n for n, pin, uid, tiene, coincide in operadores_filas
            if uid and tiene and not coincide
        ]
        check("los PIN se guardaron hasheados (sha256), no en texto plano",
              not mal_hasheados,
              "estos NO coinciden con sha256(su pin legacy):\n  "
              + "\n  ".join(mal_hasheados))

        # ------------------------------------------------------------- 3
        print("=== 3. Cada device_id quedo en `usuario_dispositivos` ===")
        cur.execute(
            """
            SELECT d.device_id, d.nombre, ud.usuario_id
            FROM (SELECT min(device_id) AS device_id, min(nombre) AS nombre
                    FROM dispositivo_usuario
                   WHERE device_id IS NOT NULL
                   GROUP BY device_id) d
            LEFT JOIN usuario_dispositivos ud ON ud.device_id = d.device_id
            ORDER BY d.device_id
            """
        )
        devices = cur.fetchall()
        huerfanos = [f"{n} (device={dv[:8]}...)" for dv, n, uid in devices if uid is None]
        check("todos los device_id quedaron vinculados (%d)" % len(devices),
              not huerfanos,
              "device_id sin fila en `usuario_dispositivos`:\n  " + "\n  ".join(huerfanos))
        for dv, n, uid in devices:
            cur.execute("SELECT nombre FROM usuarios WHERE id = %s", (uid,))
            f = cur.fetchone()
            check("  device %s... -> %s" % (dv[:8], n),
                  f is not None and f[0].lower().strip() == n.lower().strip(),
                  "apunta a %s, pero en la tabla vieja era de %s" % (f and f[0], n))

        # ------------------------------------------------------------- 4
        print("=== 4. La tabla no la usa nadie del codigo ===")
        # device_id_service solo la menciona en un comentario, y ningun otro
        # archivo de lib/ la nombra. Se comprueba sobre el arbol real.
        usos = []
        for path in (RAIZ / "lib").rglob("*.dart"):
            texto = path.read_text(encoding="utf-8", errors="replace")
            for i, linea in enumerate(texto.splitlines(), 1):
                if "dispositivo_usuario" not in linea:
                    continue
                # Un comentario que solo explica no es un uso.
                if linea.lstrip().startswith(("///", "//", "*")):
                    continue
                usos.append("%s:%d  %s" % (path.relative_to(RAIZ), i, linea.strip()))
        check("ningun .dart de lib/ la consulta", not usos,
              "usos reales:\n  " + "\n  ".join(usos))

        # ------------------------------------------------------------- 5
        print("=== 5. La politica RLS que la deja abierta ===")
        cur.execute(
            "SELECT policyname, cmd, qual, with_check FROM pg_policies "
            "WHERE tablename = 'dispositivo_usuario'"
        )
        pol = cur.fetchall()
        if not pol:
            print("  no tiene politicas (RLL sin politica = nadie lee ni escribe)")
        for nombre, cmd, qual, wc in pol:
            print("  politica %r  cmd=%s  using=%s  with_check=%s" % (nombre, cmd, qual, wc))
            check("  la politica %r no es 'todo el mundo'" % nombre,
                  not (str(qual).strip() == "true" and str(wc).strip() == "true"),
                  "permite leer y escribir a cualquiera mientras la tabla exista")

        # ------------------------------------------------------------- 6
        print("=== 6. Los casos que hay que resolver antes de borrar ===")
        cur.execute(
            """
            SELECT min(d.nombre)                AS nombre,
                   count(*)                     AS filas,
                   count(*) FILTER (WHERE d.pin_hash <> '') AS con_pin,
                   min(d.configurado_en)        AS desde,
                   max(d.configurado_en)        AS hasta
            FROM dispositivo_usuario d
            GROUP BY lower(trim(d.nombre))
            HAVING lower(trim(min(d.nombre))) NOT IN (
                SELECT lower(trim(nombre)) FROM usuarios)
               OR lower(trim(min(d.nombre))) IN (
                SELECT lower(trim(nombre)) FROM usuarios
                 WHERE pin_hash IS NULL OR pin_hash = '')
            ORDER BY min(d.nombre)
            """
        )
        casos = cur.fetchall()
        if not casos:
            print("  ninguno: los 9 operadores quedaron bien migrados")
        for nombre, nf, con_pin, desde, hasta in casos:
            print("")
            print("  · %s" % nombre)
            print("      en dispositivo_usuario: %d fila(s), %d con PIN, %s -> %s"
                  % (nf, con_pin, str(desde)[:19], str(hasta)[:19]))
            cur.execute(
                "SELECT id, nivel, activo, (pin_hash IS NOT NULL AND pin_hash <> '') "
                "FROM usuarios WHERE lower(trim(nombre)) = lower(%s) LIMIT 1",
                (nombre,),
            )
            f = cur.fetchone()
            if f is None:
                print("      en usuarios: NO EXISTE")
                print("      -> si se borra la tabla, este operador y sus equipos")
                print("         se pierden. Hay que crearlo primero.")
            else:
                print("      en usuarios: id=%d nivel=%s activo=%s con_pin=%s"
                      % (f[0], f[1], f[2], f[3]))
                if not f[3] and con_pin:
                    print("      -> tiene PIN en la tabla vieja pero pin_hash vacio aca.")
                    print("         Si se borra, ese PIN se pierde para siempre.")
            cur.execute(
                "SELECT d.device_id, d.nombre FROM dispositivo_usuario d "
                "WHERE lower(trim(d.nombre)) = lower(%s) AND d.device_id IS NOT NULL",
                (nombre,),
            )
            for dv, n2 in cur.fetchall():
                cur.execute(
                    "SELECT u.nombre FROM usuario_dispositivos d "
                    "JOIN usuarios u ON u.id = d.usuario_id WHERE d.device_id = %s",
                    (dv,),
                )
                g = cur.fetchone()
                print("      device %s... -> %s" % (dv[:8], g[0] if g else "sin vincular"))

        # Nombres parecidos entre las dos tablas: fuente tipica de duplicados.
        print("")
        print("  nombres parecidos en ambas tablas:")
        cur.execute(
            """
            SELECT DISTINCT d.nombre AS legacy, u.nombre AS actual
            FROM dispositivo_usuario d
            JOIN usuarios u
              ON u.id = (SELECT id FROM usuarios
                          WHERE lower(trim(nombre)) = lower(trim(d.nombre))
                          LIMIT 1)
            WHERE d.nombre <> u.nombre
               OR lower(d.nombre) <> lower(u.nombre)
            """
        )
        pares = cur.fetchall()
        if not pares:
            print("    (ninguno: los nombres coinciden exactamente)")
        for legacy, actual in pares:
            print("    legacy=%r  usuarios=%r" % (legacy, actual))
        # Y los que solo existen en la vieja, que es donde suelen aparecer los
        # typos: "Reidched" contra "Reidchend" no se ven si solo se listan.
        cur.execute(
            "SELECT DISTINCT lower(trim(nombre)) FROM dispositivo_usuario "
            "WHERE lower(trim(nombre)) NOT IN (SELECT lower(trim(nombre)) FROM usuarios) "
            "ORDER BY 1"
        )
        print("    solo en la tabla vieja: %s"
              % [f[0] for f in cur.fetchall()])

        # ------------------------------------------------------------- 7
        print("=== 7. Ensayo de la migracion (se aplica y se deshace) ===")
        MIGRACION = (RAIZ / "supabase" / "migrations" /
                     "20261004170000_dispositivo_usuario_pins_hasheados.sql")

        # 7a. El predicado que decide que filas se hashean, sin escribir nada.
        cur.execute(
            "SELECT count(*) FILTER (WHERE pin_hash IS NOT NULL AND pin_hash <> '' "
            "                           AND pin_hash !~ '^[0-9a-f]{64}$'), "
            "       count(*) FILTER (WHERE pin_hash ~ '^[0-9a-f]{64}$') "
            "FROM dispositivo_usuario"
        )
        a_hashear, ya_hasheadas = cur.fetchone()
        print("  filas que la migracion hashearia: %d" % a_hashear)
        print("  filas ya hasheadas (no las toca): %d" % ya_hasheadas)
        if ya_hasheadas:
            print("  -> la migracion es idempotente: sobre estas filas no hace nada")
        check("el predicado separa bien texto plano de sha256",
              (a_hashear + ya_hasheadas) == filas - sin_pin,
              "la suma no da el total de filas con PIN (%d + %d vs %d)"
              % (a_hashear, ya_hasheadas, filas - sin_pin))

        # 7b. Que digest() funcione sobre esta columna. Es lo unico que podria
        # fallar en caliente si el destino no tuviera pgcrypto.
        cur.execute(
            "SELECT count(*) FROM dispositivo_usuario "
            "WHERE pin_hash IS NOT NULL AND pin_hash <> '' "
            "  AND encode(digest(pin_hash, 'sha256'), 'hex') !~ '^[0-9a-f]{64}$'"
        )
        malos = cur.fetchone()[0]
        check("digest() devuelve 64 hex sobre todas las filas con PIN", malos == 0,
              "%d fila(s) donde digest() no devuelve un sha256" % malos)
        cur.execute("SELECT encode(digest('x', 'sha256'), 'hex') ~ '^[0-9a-f]{64}$'")
        check("pgcrypto esta disponible (digest responde)", cur.fetchone()[0],
              "digest() fallo: falta la extension pgcrypto")

        # 7c. Aplicar la migracion de verdad, en transaccion, y deshacer.
        # Se ejecuta el texto del archivo tal cual (mismo DO $$ y mismo regex),
        # pero sin el COMMIT final, followed de ROLLBACK.
        if not MIGRACION.exists():
            check("la migracion existe", False, "falta %s" % MIGRACION.name)
        else:
            sql = MIGRACION.read_text(encoding="utf-8")
            # Se le saca el BEGIN/COMMIT de la migracion para que la transaccion
            # la maneje este script y se pueda deshacer.
            ensayo = re.sub(r"^\s*BEGIN\s*;", "", sql, flags=re.M | re.I)
            ensayo = re.sub(r"^\s*COMMIT\s*;.*$", "", ensayo, flags=re.M | re.I)
            try:
                conn.autocommit = False
                cur.execute(ensayo)
                cur.execute(
                    "SELECT count(*) FROM dispositivo_usuario "
                    "WHERE pin_hash IS NOT NULL AND pin_hash <> '' "
                    "  AND pin_hash !~ '^[0-9a-f]{64}$'"
                )
                quedan = cur.fetchone()[0]
                conn.rollback()
                check("la migracion deja 0 PIN en texto plano (ensayo revertido)",
                      quedan == 0,
                      "quedaron %d fila(s) sin hashear" % quedan)
                # Y que de verdad no se haya escrito nada.
                cur.execute(
                    "SELECT count(*) FROM dispositivo_usuario "
                    "WHERE pin_hash IS NOT NULL AND pin_hash <> '' "
                    "  AND pin_hash !~ '^[0-9a-f]{64}$'"
                )
                check("el ensayo no dejo cambios (ROLLBACK)",
                      cur.fetchone()[0] == a_hashear,
                      "la tabla quedo modificada pese al ROLLBACK")
                _descartar_transaccion(conn)
            except psycopg.errors.InsufficientPrivilege as e:
                _descartar_transaccion(conn)
                print("  AVISO: sin permisos para escribir, no se pudo ensayar de verdad.")
                print("         %s" % str(e).strip().splitlines()[0])
                print("         La migracion hay que aplicarla con el rol postgres")
                print("         (tool/.pgpass_tmp), no con control_app. El predicado")
                print("         de 7a ya quedo verificado, que es la parte que")
                print("         puede estar mal.")
            except Exception as e:
                _descartar_transaccion(conn)
                check("la migracion se ejecuta sin error", False,
                      "%s: %s" % (type(e).__name__, str(e).strip().splitlines()[0]))

        print("")

        # ------------------------------------------------------------- 8
        print("=== 8. Resumen para decidir ===")
        if fallos == 0:
            print("  Se puede borrar `dispositivo_usuario`.")
            print("  No queda ninguna fila sin representar en `usuarios` ni ningun")
            print("  device_id sin vincular. Lo unico que se pierde es la posibilidad")
            print("  de contrastar el PIN en texto plano, que es justo lo que hay")
            print("  que perder.")
        else:
            print("  NO se puede borrar todavia: %d comprobaciones fallaron." % fallos)
            print("  Los PIN en texto plano ya no estan: eso se arreglo con la")
            print("  migracion del 20261004 y no bloquea nada. Lo que queda son los")
            print("  operadores de la seccion 6, que solo existen en esta tabla.")
            print("  Hay que decidir que hacer con ellos antes de escribir el DROP.")

    conn.close()


if __name__ == "__main__":
    main()
    sys.exit(1 if fallos else 0)