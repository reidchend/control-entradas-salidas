"""Prueba la logica del job `prepare` de .github/workflows/release.yml.

No reimplementa nada: extrae el bloque `run:` del paso "Calcular versiones" del
propio YAML, reemplaza las expresiones `${{ github.event.inputs.* }}` por valores
de prueba y lo corre con bash de verdad. Si el workflow cambia, esta prueba
cambia con el; no puede quedar outdated.

Casos:
  1. apps=all, sin bridge          -> las tres, cada una con su versión
  2. apps=inventario,pos           -> solo esas dos
  3. bridge=true, versiones iguales -> las tres y bridge_version = esa
  4. bridge=true, version forzado  -> bridge_version = la del input
  5. bridge=true, versiones distintas -> debe FALLAR con error explicito
  6. bridge=false (default)        -> bridge=false, bridge_version vacío

Uso:  python tool/verificar_prepare_workflow.py
"""
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
WF = RAIZ / ".github" / "workflows" / "release.yml"
BASH = r"C:\Program Files\Git\bin\bash.exe"

VERSIONES_IGUALES = {"inventario": "2.1.11", "pos": "2.1.11", "hosteleria": "2.1.11"}
DIVERGENTES = {"inventario": "2.1.12", "pos": "2.1.11", "hosteleria": "2.1.11"}


def extraer_script():
    """Saca el `run:` del paso 'Calcular versiones' sin depender de PyYAML."""
    lineas = WF.read_text(encoding="utf-8").splitlines()
    ini = fin = None
    for i, l in enumerate(lineas):
        if re.match(r"^\s+- name: Calcular versiones\s*$", l):
            ini = i
        elif ini is not None and re.match(r"^\s+- (name|uses):", l) and i > ini:
            fin = i
            break
    if ini is None:
        raise SystemExit("no se encontro el paso 'Calcular versiones'")
    bloque = lineas[ini: fin if fin is not None else len(lineas)]
    # El script arranca en la linea `run: |` y sigue mientras la sangria
    # sea mayor que la de ese `run:`.
    j = next(k for k, l in enumerate(bloque) if re.match(r"^\s*run: \|\s*$", l))
    sangria = len(bloque[j]) - len(bloque[j].lstrip())
    script = []
    for l in bloque[j + 1:]:
        if not l.strip():
            script.append("")
            continue
        if len(l) - len(l.lstrip()) <= sangria:
            break
        script.append(l)
    return "\n".join(script)


def _jq_shim(destino, python):
    """Escribe un `jq` mínimo para que el script real se pueda correr aquí.

    En el runner de GitHub `jq` viene instalado. En esta máquina no, y sin él el
    script moriría en la línea 18 antes de llegar a la lógica del puente. El shim
    cubre lo único que usa el paso "Calcular versiones": `jq -r '.a.b' archivo`.
    """
    destino.mkdir(parents=True, exist_ok=True)
    py = destino / "jq_impl.py"
    py.write_text(
        "import json, sys\n"
        "args = [a for a in sys.argv[1:] if a != '-r']\n"
        "filtro, archivo = args[0], (args[1] if len(args) > 1 else None)\n"
        "dato = json.load(open(archivo, encoding='utf-8'))\n"
        "for clave in filtro.lstrip('.').split('.'):\n"
        "    dato = dato[clave]\n"
        "print(dato)\n",
        encoding="utf-8",
    )
    (destino / "jq").write_text(
        '#!/bin/sh\nexec "%s" "%s" "$@"\n' % (python, py.as_posix()),
        encoding="utf-8",
        newline="\n",
    )
    (destino / "jq").chmod(0o755)


def correr(script, apps, version, bridge, versiones):
    """Ejecuta el script con los inputs dados y devuelve (outputs, returncode)."""
    s = script
    s = s.replace("${{ github.event.inputs.apps }}", apps)
    s = s.replace("${{ github.event.inputs.version }}", version)
    s = s.replace("${{ github.event.inputs.bridge }}", bridge)
    # Si quedara alguna expresión suelta, que no rompa el shell.
    s = re.sub(r"\$\{\{[^}]*\}\}", "", s)

    d = Path(tempfile.mkdtemp(prefix="prep_"))
    (d / "versions.json").write_text(
        json.dumps({k: {"version": v} for k, v in versiones.items()}), encoding="utf-8"
    )
    salida = d / "out.txt"
    salida.write_text("", encoding="utf-8")

    bindir = d / "bin"
    _jq_shim(bindir, sys.executable)

    # En Windows, PATH usa ';' como separador.
    sep = ";" if os.name == "nt" else ":"
    env = {
        **os.environ,
        "GITHUB_OUTPUT": str(salida),
        "PATH": str(bindir) + sep + os.environ.get("PATH", ""),
    }
    p = subprocess.run(
        [BASH, "-c", s],
        cwd=str(d),
        capture_output=True,
        text=True,
        env=env,
    )
    outputs = {}
    for line in salida.read_text(encoding="utf-8").splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            outputs[k.strip()] = v.strip()
    return outputs, p.returncode, (p.stdout or "") + (p.stderr or "")


fallos = 0


def check(etiqueta, condicion, detalle=""):
    global fallos
    if condicion:
        print("  OK    %s" % etiqueta)
    else:
        print("  FALLA %s" % etiqueta)
        if detalle:
            print("         %s" % detalle)
        fallos += 1


def main():
    script = extraer_script()
    print("=== Script extraido del YAML (%d lineas) ===" % len(script.splitlines()))
    print("  verificado sobre el archivo real: %s" % WF.relative_to(RAIZ))
    print("")

    # ---------------------------------------------------------------- caso 1
    print("=== 1. apps=all, sin bridge ===")
    o, rc, log = correr(script, "all", "", "false", VERSIONES_IGUALES)
    check("exit 0", rc == 0, log.strip())
    for k, v in [("any", "true"), ("inv_changed", "true"), ("pos_changed", "true"),
                 ("host_changed", "true"), ("inv_version", "2.1.11"),
                 ("pos_version", "2.1.11"), ("host_version", "2.1.11"),
                 ("bridge", "false"), ("bridge_version", "")]:
        check("  %s = %r" % (k, v), o.get(k) == v, "obtenido %r" % o.get(k))
    print("")

    # ---------------------------------------------------------------- caso 2
    print("=== 2. apps=inventario,pos (hosteleria no se publica) ===")
    o, rc, log = correr(script, "inventario,pos", "", "false", VERSIONES_IGUALES)
    check("exit 0", rc == 0, log.strip())
    check("  inv_changed = true", o.get("inv_changed") == "true", repr(o.get("inv_changed")))
    check("  pos_changed = true", o.get("pos_changed") == "true", repr(o.get("pos_changed")))
    check("  host_changed = false", o.get("host_changed") == "false", repr(o.get("host_changed")))
    check("  any = true", o.get("any") == "true", repr(o.get("any")))
    print("")

    # ---------------------------------------------------------------- caso 3
    print("=== 3. bridge=true, las tres versiones iguales ===")
    o, rc, log = correr(script, "all", "", "true", VERSIONES_IGUALES)
    check("exit 0", rc == 0, log.strip())
    check("  bridge = true", o.get("bridge") == "true", repr(o.get("bridge")))
    check("  bridge_version = 2.1.11", o.get("bridge_version") == "2.1.11",
          repr(o.get("bridge_version")))
    print("  ^ bridge fuerza las tres apps aunque `apps` no las pida:")
    check("  aunque se pida solo pos, bridge compila las tres",
          (lambda o2: o2.get("inv_changed") == "true" and o2.get("host_changed") == "true")(
              correr(script, "pos", "", "true", VERSIONES_IGUALES)[0]))
    print("")

    # ---------------------------------------------------------------- caso 4
    print("=== 4. bridge=true con 'version' forzada ===")
    o, rc, log = correr(script, "all", "2.2.0", "true", DIVERGENTES)
    check("exit 0", rc == 0, log.strip())
    check("  bridge_version = 2.2.0", o.get("bridge_version") == "2.2.0",
          repr(o.get("bridge_version")))
    check("  inv_version = 2.2.0 (se_override con el input)",
          o.get("inv_version") == "2.2.0", repr(o.get("inv_version")))
    print("")

    # ---------------------------------------------------------------- caso 5
    print("=== 5. bridge=true con versiones divergentes y sin 'version' ===")
    print("  (no se puede: un unico tag no representa tres versiones)")
    o, rc, log = correr(script, "all", "", "true", DIVERGENTES)
    check("exit distinto de 0 (falla a proposito)", rc != 0, "exit %d" % rc)
    check("  el error explica el motivo",
          "bridge" in log and "version" in log, log.strip()[:200])
    print("  mensaje: %s" % next(
        (l for l in log.splitlines() if "::error" in l), "(no encontrado)").strip())
    print("")

    # ---------------------------------------------------------------- caso 6
    print("=== 6. default: bridge vacio (input no enviado) ===")
    o, rc, log = correr(script, "all", "", "", VERSIONES_IGUALES)
    check("exit 0", rc == 0, log.strip())
    check("  bridge = false", o.get("bridge") == "false", repr(o.get("bridge")))
    check("  bridge_version = ''", o.get("bridge_version") == "", repr(o.get("bridge_version")))
    check("  no se publica ninguna release legada", o.get("bridge") != "true")
    print("")

    # ---------------------------------------------------------------- caso 7
    print("=== 7. apps vacio cae a 'all' ===")
    o, rc, log = correr(script, "", "", "false", VERSIONES_IGUALES)
    check("exit 0", rc == 0, log.strip())
    check("  las tres apps", o.get("inv_changed") == "true" and o.get("pos_changed") == "true"
          and o.get("host_changed") == "true", repr(o))
    print("")

    print("=== La release legada va AL FINAL del job release ===")
    yml = WF.read_text(encoding="utf-8")
    i_host = yml.find('create_release "hosteleria-v')
    i_bridge = yml.find('create_release "v${{ needs.prepare.outputs.bridge_version }}"')
    check("el bloque bridge existe", i_bridge != -1)
    check("esta despues del de hosteleria", i_bridge > i_host > 0,
          "host=%d bridge=%d" % (i_host, i_bridge))
    # Y que este dentro del paso de releases, no del de versions.json.
    check("esta antes de 'Actualizar versions.json'",
          yml.find("Actualizar versions.json") > i_bridge)
    print("")

    if fallos == 0:
        print("Todo OK: la logica del prepare y el orden de las releases son correctos")
    else:
        print("FALLARON %d verificaciones" % fallos)
    sys.exit(1 if fallos else 0)


if __name__ == "__main__":
    main()