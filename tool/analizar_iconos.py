"""Compara iconos entre plataformas sin depender de PIL.

PIL no esta instalado en esta maquina, asi que este script decodifica PNG e ICO
a mano para responder una pregunta concreta: si los archivos de icono de las
distintas plataformas realmente muestran el mismo diseno.

Decodifica PNG con los 5 filtros (0-4), que es lo que usan los PNG reales, e ICO
con una o varias entradas (toma la mayor).

Uso:
    python tool/analizar_iconos.py                       # compara los del proyecto
    python tool/analizar_iconos.py a.png b.png          # compara dos archivos
"""
import collections
import struct
import sys
import zlib
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent


# --------------------------------------------------------------------------- PNG
def _paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def leer_png(ruta):
    """Devuelve (ancho, alto, [(r,g,b,a), ...]) en orden de filas."""
    d = Path(ruta).read_bytes()
    if d[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit("%s no es un PNG" % ruta)
    i, idat, w = 8, b"", 0
    h = bd = ct = interlace = 0
    while i < len(d):
        ln = struct.unpack(">I", d[i:i + 4])[0]
        tag = d[i + 4:i + 8]
        pay = d[i + 8:i + 8 + ln]
        if tag == b"IHDR":
            # IHDR: ancho, alto, profundidad, tipo color, compresion, filtro, entrelazado
            w, h, bd, ct, _comp, _filt, interlace = struct.unpack(">IIBBBBB", pay[:13])
        elif tag == b"IDAT":
            idat += pay
        elif tag == b"IEND":
            break
        i += 12 + ln
    if bd != 8 or interlace != 0:
        raise SystemExit("%s: solo se soporta 8 bits sin entrelazado" % ruta)
    canales = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ct]
    raw = zlib.decompress(idat)
    bpp = canales
    paso = w * bpp
    px, prev = [], bytearray(paso)
    for y in range(h):
        off = y * (paso + 1)
        filtro = raw[off]
        linea = bytearray(raw[off + 1:off + 1 + paso])
        for x in range(paso):
            a = linea[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if filtro == 1:
                linea[x] = (linea[x] + a) & 0xFF
            elif filtro == 2:
                linea[x] = (linea[x] + b) & 0xFF
            elif filtro == 3:
                linea[x] = (linea[x] + (a + b) // 2) & 0xFF
            elif filtro == 4:
                linea[x] = (linea[x] + _paeth(a, b, c)) & 0xFF
        px.append(bytes(linea))
        prev = linea
    out = []
    for fila in px:
        for x in range(w):
            if ct == 6:
                out.append(tuple(fila[x * 4:x * 4 + 4]))
            elif ct == 2:
                out.append((fila[x * 3], fila[x * 3 + 1], fila[x * 3 + 2], 255))
            else:
                g = fila[x]
                out.append((g, g, g, 255))
    return w, h, out


# --------------------------------------------------------------------------- ICO
def leer_ico(ruta):
    """Devuelve (ancho, alto, [(r,g,b,a), ...]) de la entrada mas grande."""
    d = Path(ruta).read_bytes()
    _res, typ, n = struct.unpack("<HHH", d[:6])
    if typ != 1:
        raise SystemExit("%s no es un .ico" % ruta)
    mejor, i = -1, 0
    for k in range(n):
        e = d[6 + k * 16:6 + (k + 1) * 16]
        dim = (e[0] or 256) * (e[1] or 256)
        if dim > mejor:
            mejor, i = dim, k
    e = d[6 + i * 16:6 + (i + 1) * 16]
    w, h = e[0] or 256, e[1] or 256
    sz, off = struct.unpack("<II", e[8:16])
    blob = d[off:off + sz]
    if blob[:8] == b"\x89PNG\r\n\x1a\n":
        import io
        import tempfile
        tmp = Path(tempfile.gettempdir()) / ("_ico_tmp_%d.png" % i)
        tmp.write_bytes(blob)
        return leer_png(tmp)
    bpp = struct.unpack("<H", e[6:8])[0]
    if bpp != 32:
        raise SystemExit("%s: solo .ico de 32 bits sin comprimir" % ruta)
    hdr = struct.unpack("<IiiHHIIiiII", blob[:40])
    w, h = hdr[1], abs(hdr[2]) // 2
    xor = blob[40:40 + w * h * 4]
    and_fila = (w + 31) // 32 * 4
    mascara = blob[40 + w * h * 4:]
    out = []
    for y in range(h):
        base = (h - 1 - y) * w * 4  # BMP va de abajo hacia arriba
        for x in range(w):
            b, g, r, a = xor[base + x * 4:base + x * 4 + 4]
            if a == 0:
                bit = (mascara[y * and_fila + x // 8] >> (7 - x % 8)) & 1
                a = 0 if bit else 255
            out.append((r, g, b, a))
    return w, h, out


def leer(ruta):
    return leer_ico(ruta) if str(ruta).lower().endswith(".ico") else leer_png(ruta)


# ----------------------------------------------------------------------- analisis
def perfil(ruta):
    w, h, px = leer(ruta)
    opacos = [p for p in px if p[3] > 200]
    cnt = collections.Counter(
        (p[0] // 40 * 40, p[1] // 40 * 40, p[2] // 40 * 40) for p in opacos
    )
    return {
        "ruta": ruta,
        "tam": (w, h),
        "cobertura": 100.0 * len(opacos) / len(px),
        "colores": cnt.most_common(4),
        "claro": sum(p[0] + p[1] + p[2] for p in opacos) / (3 * max(1, len(opacos))),
    }


def fmt(p):
    return ("  %-46s %4dx%-4d opaco=%5.1f%%  brillo=%5.1f  col=%s"
            % (p["ruta"], p["tam"][0], p["tam"][1], p["cobertura"], p["claro"],
               " ".join("(%d,%d,%d):%.0f%%" % (c[0], c[1], c[2],
                                              100.0 * n / max(1, p["cobertura"] * p["tam"][0] * p["tam"][1] / 100))
                        for c, n in p["colores"][:3])))


def comparar(a, b):
    """Dos perfiles se consideran distintos si el brillo medio difiere mucho."""
    pa, pb = perfil(a), perfil(b)
    print(fmt(pa))
    print(fmt(pb))
    db = abs(pa["claro"] - pb["claro"])
    ca = [c[:3] for c, _ in pa["colores"][:3]]
    cb = [c[:3] for c, _ in pb["colores"][:3]]
    iguales = db < 12 and ca == cb
    print("  -> brillo difiere %.1f, colores principales %s"
          % (db, "iguales" if ca == cb else "DISTINTOS"))
    print("  -> %s" % ("mismo diseno" if iguales else "DISENOS DISTINTOS"))
    return not iguales


if __name__ == "__main__":
    if len(sys.argv) >= 3:
        comparar(sys.argv[1], sys.argv[2])
        sys.exit(0)

    print("=== Iconos que usa el build de Windows (el .ico se copia a app_icon.ico) ===")
    for n in ["app_icon_hosteleria.ico", "app_icon_inventario.ico", "app_icon_pos.ico"]:
        print(fmt(perfil(RAIZ / "windows" / "runner" / "resources" / n)))

    print("")
    print("=== web_hosteleria (iconos que el navegador usaria) ===")
    for n in ["icons/Icon-512.png", "icons/Icon-192.png", "favicon.png"]:
        print(fmt(perfil(RAIZ / "web_hosteleria" / n)))

    print("")
    print("=== el .ico nuevo de hosteleria vs el PNG web de hosteleria ===")
    comparar(RAIZ / "windows" / "runner" / "resources" / "app_icon_hosteleria.ico",
             RAIZ / "web_hosteleria" / "icons" / "Icon-512.png")

    print("")
    print("=== el .ico nuevo de hosteleria vs el de POS (de donde se derivo antes) ===")
    comparar(RAIZ / "windows" / "runner" / "resources" / "app_icon_hosteleria.ico",
             RAIZ / "windows" / "runner" / "resources" / "app_icon_pos.ico")
