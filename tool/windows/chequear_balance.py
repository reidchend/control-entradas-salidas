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


def revisar_here_strings(texto: str) -> list[str]:
    """Dentro de un here-string no hay procesado de escapes.

    ``""`` no es un escape de comilla: llega literal a PostgreSQL. Dos bugs
    reales salieron de acá, así que se avisa en vez de dejar pasar.
    """
    problemas: list[str] = []
    patron = re.compile(r'@"(?P<d>.*?)"@|@\'(?P<s>.*?)\'@', re.DOTALL)
    for m in patron.finditer(texto):
        cuerpo = m.group("d") if m.group("d") is not None else m.group("s")
        es_doble = m.group("d") is not None
        if es_doble and '""' in cuerpo:
            linea = texto[: m.start()].count("\n") + 1
            problemas.append(
                f"  here-string con \"\" en la línea {linea}: dentro de @\"...\"@ "
                f"no es escape, llega literal. Usar comillas simples."
            )
    return problemas


def revisar_llamadas(texto: str) -> list[str]:
    """Detecta el patron `(& $var ...)` con salto de linea antes del cierre.

    En PowerShell, un parentesis seguido de & $var sin cerrar en la misma
    linea no parsea: el & de llamada dentro de la subexpresion se
    interpreta distinto y se desarma la expresion entera. Ya rompio dos
    veces, asi que se avisa.
    """
    problemas: list[str] = []
    lineas = texto.splitlines()
    for i, linea in enumerate(lineas):
        s = linea.strip()
        if s.startswith("#"):
            continue
        # (& $var ... seguido de algo que no cierra en la misma linea
        if re.search(r'\(\s*&\s*\$', linea) and not re.search(r'\)\s*(;|$|2>)', linea):
            problemas.append(
                f"  línea {i + 1}: '(' seguido de '& $var' sin cierre en la misma "
                f"línea. Mover el cierre o sacar el paréntesis."
            )
    return problemas


def revisar(ruta: Path) -> list[str]:
    crudo = ruta.read_text(encoding="utf-8")
    problemas_here = revisar_here_strings(crudo)
    limpio = sin_comentarios(sin_cadenas(sin_here_strings(crudo)))

    pila: list[tuple[str, int]] = []
    problemas: list[str] = problemas_here + revisar_llamadas(crudo)
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
