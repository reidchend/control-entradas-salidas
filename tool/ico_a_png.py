"""Convierte un .ico de una sola imagen (DIB/BMP sin comprimir) a PNG, sin PIL.

Sirve para inspeccionar visualmente un .ico cuando PIL no esta instalado en la
maquina. Solo soporta el caso que se necesita aqui: una unica entrada, DIB de 32
bits sin comprimir.

Uso:  python tool/ico_a_png.py <entrada.ico> <salida.png>
"""
import struct
import sys
import zlib


def ico_a_png(ruta_ico, ruta_png):
    d = open(ruta_ico, "rb").read()
    res, typ, n = struct.unpack("<HHH", d[:6])
    if res != 0 or typ != 1:
        raise SystemExit("no es un .ico valido (reserved=%d type=%d)" % (res, typ))
    if n != 1:
        # Con varias entradas se toma la mas grande: es la que se ve al 100%.
        mejor, i = -1, 0
        for k in range(n):
            e = d[6 + k * 16:6 + (k + 1) * 16]
            kw, kh = e[0] or 256, e[1] or 256
            if kw * kh > mejor:
                mejor, i = kw * kh, k
        e = d[6 + i * 16:6 + (i + 1) * 16]
        w, h, bpp = e[0] or 256, e[1] or 256, struct.unpack("<H", e[6:8])[0]
        sz, off = struct.unpack("<II", e[8:16])
        print("  el .ico tiene %d entradas; se usa la mayor (%dx%d)" % (n, w, h))
    else:
        _w, _h, _c, _r, _p, bpp, sz, off = struct.unpack("<BBBBHHII", d[6:22])
        w = _w or 256
        h = _h or 256
    blob = d[off:off + sz]
    if blob[:8] == b"\x89PNG\r\n\x1a\n":
        # El .ico envuelve un PNG tal cual: solo se copia.
        open(ruta_png, "wb").write(blob)
        return w, h, "PNG embebido (copiado tal cual)"

    if bpp != 32:
        raise SystemExit("solo se soporta DIB de 32 bits; este es de %d" % bpp)

    # BITMAPINFOHEADER: 40 bytes, luego el bitmap XOR de abajo hacia arriba.
    # OJO: en un DIB de icono la altura del header viene DOBADA, porque cubre el
    # bitmap XOR mas la mascara AND. Por eso no se puede usar tal cual.
    hdr = struct.unpack("<IiiHHIIiiII", blob[:40])
    ancho_real = hdr[1]
    alto_real = abs(hdr[2]) // 2
    xor = blob[40:40 + ancho_real * alto_real * 4]
    and_mask = blob[40 + ancho_real * alto_real * 4:]
    ancho_fila = (ancho_real + 31) // 32 * 4  # la mascara AND va alineada a 4 bytes
    if len(and_mask) < ancho_fila * alto_real:
        raise SystemExit(
            "falta la mascara AND: hay %d bytes, se esperan %d"
            % (len(and_mask), ancho_fila * alto_real)
        )

    # BMP: canal BGRA, filas de abajo hacia arriba. PNG: RGBA, de arriba abajo.
    filas = []
    for y in range(alto_real):
        base = (alto_real - 1 - y) * ancho_real * 4
        fila = bytearray(b"\x00")  # filtro 0 (None) por scanline
        for x in range(ancho_real):
            b, g, r, a = xor[base + x * 4: base + x * 4 + 4]
            if a == 0:
                # Sin alfa: la mascara AND marca que pixel es transparente.
                byte_x, byte_y = x // 8, y
                bit = (and_mask[byte_y * ancho_fila + byte_x] >> (7 - x % 8)) & 1
                if bit:
                    a = 0
                else:
                    a = 255
            fila += bytes((r, g, b, a))
        filas.append(bytes(fila))
    raw = b"".join(filas)

    def chunk(tag, payload):
        return (struct.pack(">I", len(payload)) + tag + payload
                + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", ancho_real, alto_real, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    open(ruta_png, "wb").write(png)
    return ancho_real, alto_real, "DIB de 32 bits reconstruido"


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Uso: ico_a_png.py <entrada.ico> <salida.png>")
    ancho, alto, como = ico_a_png(sys.argv[1], sys.argv[2])
    print("  %dx%d  ->  %s  (%s)" % (ancho, alto, sys.argv[2], como))
