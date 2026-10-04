"""Mide quanta logica duplicada hay en .github/workflows/release.yml.

Compara los jobs de Windows entre si y los tres bloques del job `release`, previa
normalizacion de los tokens que si son especificos de cada app (nombre de app,
version, icono, etiqueta). Lo que sobrevive a esa normalizacion es logica
copiada, no parametrizacion.

No modifica nada: solo lee y reporta.

Uso:  python tool/medir_duplicacion_workflow.py
"""
import difflib
import re
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
WF = RAIZ / ".github" / "workflows" / "release.yml"


def lineas():
    return WF.read_text(encoding="utf-8").splitlines()


def extraer_job(ls, nombre):
    """Devuelve las lineas del job `nombre` (sangria de 2 espacios)."""
    ini = fin = None
    for i, l in enumerate(ls):
        if re.match(rf"^  {re.escape(nombre)}:\s*$", l):
            ini = i
        elif ini is not None and re.match(r"^  [a-z0-9-]+:\s*$", l):
            fin = i
            break
    if ini is None:
        raise SystemExit("no existe el job %s" % nombre)
    return ls[ini: fin if fin is not None else len(ls)]


def normalizar(job):
    """Cambia por marcadores lo que es propio de cada app."""
    s = "\n".join(job)
    for app in ("pos", "inventario", "hosteleria"):
        s = s.replace(app, "APP")
    s = s.replace("APP_changed", "APP_changed")  # no-op, deja el sufijo visible
    for pat, rep in [
        (r"APP_version", "APP_VERSION"),
        (r"APP_VERSION", "VERSION"),
        (r"Lycoris(Control|Hostel|POS)", "BINARY"),
        (r"main_(pos|inventario|hosteleria)\.dart", "ENTRY"),
        (r"main\.dart", "ENTRY"),
        (r"APP\.dart", "ENTRY"),
        (r'APP_LABEL="[^"]*"', 'APP_LABEL="X"'),
        (r"windows-hosteleria", "windows-APP"),
        (r"Windows (POS|Inventario|Hostelería)", "Windows APP"),
        (r"Windows APP \(zip\)", "Windows APP (zip)"),
        (r"inv_version|pos_version|host_version", "VERSION"),
        (r"\binv_changed\b|\bpos_changed\b|\bhost_changed\b", "APP_changed"),
        (r"\binv\b", "APP"),
    ]:
        s = re.sub(pat, rep, s)
    # Quitar lineas en blanco: no cuentan como logica.
    return [l.rstrip() for l in s.splitlines() if l.strip()]


def comparar(a, b, nombre_a, nombre_b):
    sim = difflib.SequenceMatcher(None, a, b)
    ratio = sim.ratio()
    # get_matching_blocks devuelve tuplas (i, j, n): n es la longitud del bloque.
    iguales = sum(bl[2] for bl in sim.get_matching_blocks())
    print("  %-22s vs %-22s  %5.1f%% identico   (%d de %d lineas iguales)"
          % (nombre_a, nombre_b, ratio * 100, iguales, len(a)))
    return ratio, a, b, sim


def diferencias(a, b, sim):
    """Lista las lineas que realmente difieren (no solo por nombre)."""
    out = []
    for tag, i1, i2, j1, j2 in sim.get_opcodes():
        if tag == "equal":
            continue
        out.append(("  " + tag.upper()))
        for l in a[i1:i2]:
            out.append("    - " + l.strip())
        for l in b[j1:j2]:
            out.append("    + " + l.strip())
    return out


def main():
    ls = lineas()
    print("=== 1. Los 3 jobs de Windows entre si (normalizados por app) ===")
    jobs = {n: normalizar(extraer_job(ls, n))
            for n in ("windows-pos", "windows-inventario", "windows-hosteleria")}
    base = jobs["windows-pos"]
    print("  (cada job queda en ~%d lineas utiles)" % len(base))
    print("")
    res = []
    for n in ("windows-inventario", "windows-hosteleria"):
        res.append(comparar(base, jobs[n], "windows-pos", n))
    promedio = sum(r[0] for r in res) / len(res)
    print("")
    print("  PROMEDIO de duplicacion entre los 3 jobs de Windows: %.1f%%" % (promedio * 100))

    print("")
    print("=== 2. Diferencias reales que quedan tras normalizar ===")
    sim = res[0][3]
    diffs = diferencias(res[0][1], res[0][2], sim)
    if not diffs:
        print("  (ninguna: los 3 jobs son IDENTICOS tras normalizar)")
    for l in diffs:
        print(l)

    print("")
    print("=== 3. Bloques repetidos en todo el archivo ===")
    txt = "\n".join(ls)
    for pat, desc in [
        (r"- uses: actions/checkout@v4", "checkout del repo"),
        (r"- uses: actions/setup-java@v4", "instalar Java 17"),
        (r"- uses: subosito/flutter-action@v2", "instalar Flutter"),
        (r"Actualizar version en pubspec\.yaml|sed -i \"s/\^version", "reescribir version en pubspec"),
        (r"flutter pub get", "flutter pub get"),
        (r"Compress-Archive", "empaquetar zip"),
        (r"tar -czf", "empaquetar tar.gz"),
        (r"--dart-define=WHATSAPP_BOT_TOKEN", "pasear el token de WhatsApp"),
        (r"--dart-define=APP_LABEL", "APP_LABEL"),
    ]:
        n = len(re.findall(pat, txt))
        print("  %-42s x%d" % (desc, n))

    print("")
    print("=== 4. Peso total ===")
    total = len(ls)
    repetidas = 0
    # Aproximacion: cuanto del archivo son lineas de job identicas entre si.
    for n in ("windows-pos", "windows-inventario", "windows-hosteleria"):
        repetidas += len(jobs[n])
    print("  archivo completo:        %d lineas" % total)
    print("  los 3 jobs de Windows:   %d lineas (%.0f%% del archivo, "
          "con %.0f%% de duplicacion entre si)"
          % (repetidas, 100.0 * repetidas / total, promedio * 100))
    # Cuanto quedaria con una matriz.
    print("")
    print("  Estimacion con matriz (strategy.matrix):")
    print("    un solo job parametrizado por app -> %d lineas en vez de %d"
          % (len(base), repetidas))
    print("    ahorro aproximado: %d lineas (%.0f%% del archivo)"
          % (repetidas - len(base), 100.0 * (repetidas - len(base)) / total))


if __name__ == "__main__":
    main()