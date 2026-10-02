"""Genera los íconos de Lycoris Hostelería (dorado/ámbar) a partir del logo del POS.

Recolorea `web_pos/icons/Icon-512.png` con un mapa de degradado dorado que
preserva el sombreado, y produce:
  - windows/runner/resources/app_icon_hosteleria.ico  (multi-resolución)
  - web_hosteleria/icons/*.png                        (192/512 + maskable)
  - web_hosteleria/favicon.png                         (64x64)

Uso:  python3 tool/generar_icono_hosteleria.py
"""

from pathlib import Path

from PIL import Image

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
    base = Image.open(BASE)
    icono = recolorear(base)

    # Windows: .ico multi-resolución
    ico = RAIZ / "windows" / "runner" / "resources" / "app_icon_hosteleria.ico"
    icono.resize((256, 256), Image.LANCZOS).save(
        ico, format="ICO", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    )
    print("ico  ->", ico.relative_to(RAIZ))

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


if __name__ == "__main__":
    main()
