"""Hashea los PIN en texto plano que quedaron en los respaldos de tool/respaldos/.

La migracion 20261004170000 hasheo los PIN en la base, asi que un dump nuevo ya
no lleva credenciales. Los respaldos que se hicieron antes siguen con el PIN en
claro, y son archivos sueltos en el disco (ignorado por git, pero el disco es
del equipo).

Reemplaza cada PIN por su sha256, que es el mismo valor que quedo en
`usuarios.pin_hash`. No borra el PIN de la base: lo cambia por su hash en el
archivo, asi que el respaldo sigue sirviendo para auditar y comparar.

Lo que NO se puede recuperar despues es el PIN en claro de un operador. Por eso
el script exige `--aplicar`: sin ese flag solo informa.

Uso:
    python tool/hashear_pin_respaldos.py            # simulacro
    python tool/hashear_pin_respaldos.py --aplicar  # escribe
"""
import hashlib
import json
import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
RESPALDOS = RAIZ / "tool" / "respaldos"

SHA256 = re.compile(r"^[0-9a-f]{64}$")

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


def sha256(texto: str) -> str:
    return hashlib.sha256(texto.encode("utf-8")).hexdigest()


def recorrer(valor, ruta, hallazgo):
    """Junta todo lo que parezca un PIN en texto plano.

    Solo mira claves con 'pin' en el nombre, y solo valores de texto que no sean
    un sha256: asi no toca un campo que se llame pin o algo asi.
    """
    if isinstance(valor, dict):
        for clave, hijo in valor.items():
            if "pin" in clave.lower() and isinstance(hijo, str):
                if hijo and not SHA256.match(hijo):
                    hallazgo.append(("%s.%s" % (ruta, clave), hijo))
            recorrer(hijo, "%s.%s" % (ruta, clave), hallazgo)
    elif isinstance(valor, list):
        for i, hijo in enumerate(valor):
            recorrer(hijo, "%s[%d]" % (ruta, i), hallazgo)


def reemplazar(valor, hashes):
    """Devuelve una copia con los PIN ya hasheados."""
    if isinstance(valor, dict):
        nuevo = {}
        for clave, hijo in valor.items():
            if ("pin" in clave.lower() and isinstance(hijo, str)
                    and hijo and not SHA256.match(hijo) and hijo in hashes):
                nuevo[clave] = hashes[hijo]
            else:
                nuevo[clave] = reemplazar(hijo, hashes)
        return nuevo
    if isinstance(valor, list):
        return [reemplazar(v, hashes) for v in valor]
    return valor


def main():
    aplicar = "--aplicar" in sys.argv
    print("=== %s ===" % ("APLICANDO" if aplicar else "SIMULACRO (nada se escribe)"))
    print("")

    archivos = sorted(RESPALDOS.glob("*.json"))
    if not archivos:
        print("  no hay respaldos en %s" % RESPALDOS)
        return

    # Los PIN distintos de todo el arbol, con su hash.
    todos = {}
    por_archivo = {}
    for ruta in archivos:
        try:
            datos = json.loads(ruta.read_text(encoding="utf-8"))
        except Exception as exc:
            print("  %-44s ilegible: %s" % (ruta.name, exc))
            continue
        hallados = []
        recorrer(datos, "", hallados)
        por_archivo[ruta] = (datos, hallados)
        for _, pin in hallados:
            todos[pin] = sha256(pin)

    print("=== PIN en texto plano por archivo ===")
    if not todos:
        print("  ninguno: ningun respaldo tiene PIN en claro")
    else:
        print("  %d PIN distinto(s) en todo el arbol. No se imprimen: son"
              % len(todos))
        print("  credenciales de operario. Cada uno tiene %d digitos."
              % len(next(iter(todos))))
        print("")
        for ruta, (_, hallados) in por_archivo.items():
            if not hallados:
                print("  %-44s sin PIN en claro" % ruta.name)
            else:
                print("  %-44s %d PIN en claro" % (ruta.name, len(hallados)))

    print("")
    print("=== Cruzado contra `usuarios.pin_hash` ===")
    # Si el hash del respaldo ya es el pin_hash de un usuario, el cambio es
    # consistente con lo que quedo en la base.
    try:
        import psycopg
        url = None
        for linea in (RAIZ / ".env.local").read_text(encoding="utf-8").splitlines():
            if linea.startswith("DATABASE_URL="):
                url = linea.split("=", 1)[1].strip().strip("'\"")
        con = psycopg.connect(url, autocommit=True)
        cur = con.cursor()
        cur.execute("SELECT DISTINCT pin_hash FROM usuarios "
                    "WHERE pin_hash IS NOT NULL AND pin_hash <> ''")
        en_base = {f[0] for f in cur.fetchall()}
        con.close()
        comunes = set(todos.values()) & en_base
        print("  %d de %d hash(es) del respaldo coinciden con un pin_hash de"
              " `usuarios`" % (len(comunes), len(todos)))
        if not todos:
            pass
        elif not comunes:
            check("los hashes coinciden con la base", False,
                  "ninguno coincide: el respaldo y la base no son el mismo estado")
        else:
            check("los hashes coinciden con la base", True)
    except ImportError:
        print("  (sin psycopg: no se puede cruzar contra la base)")
    except Exception as exc:
        print("  no se pudo cruzar contra la base: %s" % exc)

    if not aplicar or not todos:
        print("")
        print("  Nada escrito. Con --aplicar se reescriben los archivos.")
        return

    print("")
    print("=== Escribiendo ===")
    hashes = todos
    for ruta, (datos, hallados) in por_archivo.items():
        if not hallados:
            continue
        # Se releen los hashes por si otro archivo los agrego.
        archivo_hashes = {pin: hashes[pin] for _, pin in hallados}
        nuevo = reemplazar(datos, archivo_hashes)

        # No se escribe a ciegas: se comprueba que el resultado ya no tiene
        # ningun PIN en claro.
        quedan = []
        recorrer(nuevo, "", quedan)
        if quedan:
            check("  %s quedo sin PIN en claro" % ruta.name, False,
                  "quedaron %d" % len(quedan))
            continue

        # Sin salto de linea final y con el mismo `indent=2` que usa
        # `tool/respaldar_antes_migrar.py`, para que el unico cambio en el
        # archivo sean los hashes.
        ruta.write_text(
            json.dumps(nuevo, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        check("  %s reescrito (%d PIN -> hash)" % (ruta.name, len(hallados)), True)

    print("")
    print("=== Reverificando en disco ===")
    for ruta in archivos:
        try:
            datos = json.loads(ruta.read_text(encoding="utf-8"))
        except Exception:
            continue
        hallados = []
        recorrer(datos, "", hallados)
        check("  %-44s sin PIN en claro" % ruta.name, not hallados,
              "quedaron %d" % len(hallados))

    print("")
    print("  Lo que no se recupera: el PIN en claro de un operador. Para")
    print("  obtenerlo hay que pedir que lo cambie; el hash no se puede volver")
    print("  a PIN.")


if __name__ == "__main__":
    main()
    sys.exit(1 if fallos else 0)