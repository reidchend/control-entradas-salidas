"""Genera los íconos web de Lycoris Hostelería (dorado/ámbar) desde el logo del POS.

Recolorea `web_pos/icons/Icon-512.png` con un mapa de degradado dorado que
preserva el sombreado, y produce:
  - web_hosteleria/icons/*.png                        (192/512 + maskable)
  - web_hosteleria/favicon.png                         (64x64)

NO genera `windows/runner/resources/app_icon_hosteleria.ico`. Ese archivo se
mantiene a mano: se reemplazó por un diseño propio (fondo claro pleno, no el
glifo dorado sobre fondo transparente que produce este script) y regenerarlo lo
habría destruido sin avisar. Para regenerarlo hay que pedirlo explícitamente con
`--ico`, y solo tiene sentido si además se va a rehacer desde la misma fuente.

Requiere Pillow, que no viene en tool/venv:  pip install Pillow

Uso:
    python3 tool/generar_icono_hosteleria.py          # solo web (no toca el .ico)
    python3 tool/generar_icono_hosteleria.py --ico    # además el .ico de Windows
"""

import argparse
from pathlib import Path

# PIL se carga perezoso y no al importar el modulo: si se cargara aqui, hasta
# `--help` fallaria asking por Pillow, y `--help` es justamente donde se
# descubre que existe el flag `--ico`.
Image = None


def _cargar_pil():
    global Image
    if Image is None:
        try:
            from PIL import Image as _img
        except ImportError:
            raise SystemExit(
                "Falta Pillow. Se instala con:  pip install Pillow\n"
                "No viene en tool/venv, hay que instalarlo a mano."
            )
        Image = _img
    return Image

RAIZ = Path(__file__).resolve().parent.parent
BASE = RAIZ / "web_pos" / "icons" / "Icon-512.png"

# Degradado dorado: bronce oscuro -> ámbar -> oro claro
STOPS = [
    (0.0, (120, 70, 0)),
    (0.35, (200, 130, 0)),
    (0.65, (240, 175, 20)),
    (0.9, (255, 210, 70)),
    (1.0, (255, 240, 180)),
]
NORM = 0.72  # la base azul es oscura; normalizar para que el dorado brille


def _lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def dorado(t):
    t = max(0.0, min(1.0, t))
    for i in range(len(STOPS) - 1):
        p0, c0 = STOPS[i]
        p1, c1 = STOPS[i + 1]
        if t <= p1:
            f = (t - p0) / (p1 - p0) if p1 > p0 else 0
            return _lerp(c0, c1, f)
    return STOPS[-1][1]


def recolorear(imagen):
    im = imagen.convert("RGBA")
    w, h = im.size
    px = im.load()
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    op = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255
            gr, gg, gb = dorado(lum / NORM)
            op[x, y] = (gr, gg, gb, a)
    return out


def main():
    ap = argparse.ArgumentParser(
        description="Genera los iconos web de Hosteleria desde el logo del POS."
    )
    ap.add_argument(
        "--ico",
        action="store_true",
        help="Regenerar tambien windows/runner/resources/app_icon_hosteleria.ico. "
        "LO SOBRESCRIBE. Por defecto ese archivo no se toca.",
    )
    args = ap.parse_args()
    _cargar_pil()

    # Web
    web = RAIZ / "web_hosteleria"
    icons = web / "icons"
    icons.mkdir(parents=True, exist_ok=True)
    for nombre in ["Icon-192.png", "Icon-512.png", "Icon-maskable-192.png", "Icon-maskable-512.png"]:
        lado = 192 if "192" in nombre else 512
        origen = RAIZ / "web_pos" / "icons" / nombre
        destino = icons / nombre
        icono_n = recolorear(Image.open(origen))
        if icono_n.size != (lado, lado):
            icono_n = icono_n.resize((lado, lado), Image.LANCZOS)
        icono_n.save(destino)
        print("web  ->", destino.relative_to(RAIZ))

    fav = recolorear(Image.open(RAIZ / "web_pos" / "favicon.png"))
    fav.save(web / "favicon.png")
    print("fav  ->", (web / "favicon.png").relative_to(RAIZ))

    # Windows. Solo con --ico, porque el archivo se mantiene a mano.
    ico = RAIZ / "windows" / "runner" / "resources" / "app_icon_hosteleria.ico"
    if args.ico:
        icono = recolorear(Image.open(BASE))
        icono.resize((256, 256), Image.LANCZOS).save(
            ico, format="ICO", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
        )
        print("ico  ->", ico.relative_to(RAIZ), "REGENERADO (se sobrescribio el anterior)")
    else:
        print("ico  ->", ico.relative_to(RAIZ), "intacto (--ico lo regeneraria y lo sobrescribiria)")


if __name__ == "__main__":
    main()
