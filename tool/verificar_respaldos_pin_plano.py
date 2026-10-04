"""Busca PIN en texto plano en los respaldos locales de la base.

La migracion 20261004170000 hasheo los PIN en `dispositivo_usuario`, asi que la
base ya no los tiene legibles. Los respaldos que se hicieron antes siguen
guardandolos en claro, y son archivos sueltos en el disco.

No imprime ningun PIN: solo cuenta cuantos hay y en que archivo.

Uso:  python tool/verificar_respaldos_pin_plano.py
"""
import json
import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent

# Un sha256 son 64 hex. Un PIN de operario son 4 digitos.
SHA256 = re.compile(r"^[0-9a-f]{64}$")


def en_json(valor):
    """Cuantos PIN en texto plano hay dentro de una estructura JSON."""
    pines = set()

    def recorrer(v):
        if isinstance(v, dict):
            for clave, valor in v.items():
                # Solo los campos que guardan PIN, por no marcar de mas.
                if "pin" in clave.lower() and isinstance(valor, str):
                    if valor and not SHA256.match(valor):
                        pines.add(valor)
                recorrer(valor)
        elif isinstance(v, list):
            for item in v:
                recorrer(item)

    recorrer(valor)
    return pines


def _trackeado(ruta: Path, raiz: Path):
    """True si git tiene el archivo versionado."""
    import subprocess

    try:
        salida = subprocess.run(
            ["git", "-C", str(raiz), "ls-files", "--error-unmatch",
             str(ruta.relative_to(raiz)).replace("\\", "/")],
            capture_output=True,
        )
        return salida.returncode == 0
    except Exception:
        return None


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


print("=== Respaldos de tool/respaldos/ ===")
respaldos = sorted((RAIZ / "tool" / "respaldos").glob("*.json"))
if not respaldos:
    print("  (no hay archivos .json)")
for ruta in respaldos:
    try:
        datos = json.loads(ruta.read_text(encoding="utf-8"))
    except Exception as exc:
        print("  %-42s ilegible: %s" % (ruta.name, exc))
        continue
    pines = en_json(datos)
    if pines:
        print("  %-42s %d PIN en texto plano" % (ruta.name, len(pines)))
        fallos += 1
    else:
        print("  %-42s sin PIN en texto plano" % ruta.name)

print("")
print("=== neon.dump ===")
dump = RAIZ / "neon.dump"
if not dump.exists():
    print("  no existe")
else:
    crudo = dump.read_bytes()
    # pg_dump en formato custom empieza con la cadena PGDMP; si no, es SQL.
    es_custom = crudo[:5] == b"PGDMP"
    print("  formato: %s" % ("custom de pg_dump (binario)" if es_custom else "SQL texto plano"))
    if es_custom:
        print("  no se puede leer el contenido sin pg_restore, pero el archivo")
        print("  contiene los datos de la tabla, incluidos los PIN de la epoca.")
        fallos += 1
    else:
        texto = crudo.decode("utf-8", errors="replace")
        # Busca el bloque de COPY/INSERT de dispositivo_usuario y mira los PIN.
        filas = re.findall(r"^.*dispositivo_usuario.*$", texto, re.M)
        print("  lineas que mencionan la tabla: %d" % len(filas))
        pines = set()
        for linea in texto.splitlines():
            if not linea.startswith(("COPY ", "INSERT INTO")):
                continue
            for campo in re.findall(r"\t([^\t\n]*)", linea):
                if campo and not SHA256.match(campo) and re.fullmatch(r"\d{3,8}", campo):
                    pines.add(campo)
        if pines:
            print("  PIN en texto plano: %d distintos" % len(pines))
            fallos += 1
        else:
            print("  sin PIN en texto plano")

print("")
print("=== Archivos sueltos que tambien guardan la base ===")
for nombre in ("neon.dump",):
    ruta = RAIZ / nombre
    if ruta.exists():
        print("  %s  %.1f MB  %s" % (
            nombre,
            ruta.stat().st_size / 1048576,
            "ignorado por git" if not _trackeado(ruta, RAIZ) else "TRACKEADO POR GIT",
        ))

print("")
if fallos:
    print("  %d archivo(s) todavia tienen PIN de operario en texto plano." % fallos)
    print("  Se pueden borrar sin perder nada: la base tiene los PIN hasheados")
    print("  desde la migracion 20261004170000, y para recuperar un PIN alcanza")
    print("  con que el operario lo cambie. Antes de borrar, conviene confirmar")
    print("  que no hacen falta como registro.")
else:
    print("  Ningun respaldo tiene PIN en texto plano.")

sys.exit(1 if fallos else 0)