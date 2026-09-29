"""Chequeo burdo de balance de paréntesis en scripts de PowerShell.

No reemplaza a PowerShell: en una máquina Linux no hay forma de parsear
`.ps1` de verdad. Lo que hace es una revisión rápida de balance ignorando
here-strings (`@"..."@` y `@'...'@`), comentarios y cadenas, que es donde
se concentran los desbalances reales al escribir el script.

Uso:  python3 tool/windows/chequear_balance.py tool/windows/*.ps1
"""

import re
import sys
from pathlib import Path

PAREJAS = {"(": ")", "[": "]", "{": "}"}
CIERRES = {v: k for k, v in PAREJAS.items()}


def sin_here_strings(texto: str) -> str:
    """Reemplaza el contenido de los here-strings por espacios.

    Es un regex y por lo tanto no maneja here-strings anidados ni
    concatenación de cadenas en la frontera; para este uso alcanza.
    """
    patron = re.compile(r'@"(?P<d>.*?)"@|@\'(?P<s>.*?)\'@', re.DOTALL)
    return patron.sub(lambda m: " " * len(m.group(0)), texto)


def sin_cadenas(texto: str) -> str:
    # Comilla doble: escape por "" o por backtick.
    texto = re.sub(r'`"(?:[^"]|"")*"', '""', texto)
    texto = re.sub(r'"(?:""|[^"])*"', '""', texto)
    # Comilla simple: el '' es comilla escapada, no cierre.
    texto = re.sub(r"'(?:''|[^'])*'", "''", texto)
    return texto


def sin_comentarios(texto: str) -> str:
    return re.sub(r"#.*$", "", texto, flags=re.MULTILINE)


def revisar(ruta: Path) -> list[str]:
    crudo = ruta.read_text(encoding="utf-8")
    limpio = sin_comentarios(sin_cadenas(sin_here_strings(crudo)))

    pila: list[tuple[str, int]] = []
    problemas: list[str] = []
    linea = 1
    for ch in limpio:
        if ch == "\n":
            linea += 1
        elif ch in PAREJAS:
            pila.append((ch, linea))
        elif ch in CIERRES:
            if not pila:
                problemas.append(f"  cierre '{ch}' sin apertura (línea {linea})")
            elif pila[-1][0] != CIERRES[ch]:
                abrir, n = pila.pop()
                problemas.append(
                    f"  '{abrir}' abierto en línea {n} se cierra con '{ch}' "
                    f"en línea {linea}"
                )
            else:
                pila.pop()

    for abrir, n in pila:
        problemas.append(f"  '{abrir}' abierto en línea {n} nunca se cierra")
    return problemas


def main() -> int:
    rutas = [Path(a) for a in sys.argv[1:]]
    if not rutas:
        print(__doc__)
        return 2
    salida = 0
    for ruta in rutas:
        problemas = revisar(ruta)
        if problemas:
            salida = 1
            print(f"{ruta}: DESBALANCEADO")
            for p in problemas:
                print(p)
        else:
            print(f"{ruta}: balanceado")
    return salida


if __name__ == "__main__":
    raise SystemExit(main())
