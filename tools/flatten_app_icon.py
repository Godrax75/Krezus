#!/usr/bin/env python3
"""Aplatit l'icône d'app sur un fond opaque, sans dépendance externe.

App Store Connect refuse toute icône 1024×1024 porteuse d'un canal alpha
(ITMS-90717), même si l'image est visuellement pleine : c'est le canal lui-même
qui est interdit. `sips` sait convertir des formats mais pas composer un fond,
d'où ce décodeur/encodeur PNG minimal.

    python3 tools/flatten_app_icon.py [chemin.png]

Le fond est échantillonné dans le coin supérieur gauche de l'icône — c'est la
couleur de marque sur laquelle le dessin a été composé à l'origine.
"""

import pathlib
import struct
import sys
import zlib

DEFAULT = (pathlib.Path(__file__).resolve().parent.parent
           / "Krezus/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png")


def read_chunks(data: bytes):
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "ce n'est pas un PNG"
    pos = 8
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        ctype = data[pos + 4:pos + 8]
        yield ctype, data[pos + 8:pos + 8 + length]
        pos += 12 + length


def unfilter(raw: bytes, width: int, height: int, channels: int) -> bytearray:
    """Applique les filtres PNG ligne à ligne (§9.2 de la spécification)."""
    stride = width * channels
    out = bytearray()
    previous = bytearray(stride)
    pos = 0
    for _ in range(height):
        filter_type = raw[pos]
        line = bytearray(raw[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        for i in range(stride):
            left = line[i - channels] if i >= channels else 0
            up = previous[i]
            upleft = previous[i - channels] if i >= channels else 0
            if filter_type == 1:
                line[i] = (line[i] + left) & 0xFF
            elif filter_type == 2:
                line[i] = (line[i] + up) & 0xFF
            elif filter_type == 3:
                line[i] = (line[i] + (left + up) // 2) & 0xFF
            elif filter_type == 4:
                p = left + up - upleft
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - upleft)
                nearest = left if (pa <= pb and pa <= pc) else (up if pb <= pc else upleft)
                line[i] = (line[i] + nearest) & 0xFF
        out += line
        previous = line
    return out


def chunk(ctype: bytes, payload: bytes) -> bytes:
    return (struct.pack(">I", len(payload)) + ctype + payload
            + struct.pack(">I", zlib.crc32(ctype + payload) & 0xFFFFFFFF))


def flatten(path: pathlib.Path) -> bool:
    data = path.read_bytes()
    idat = b""
    width = height = depth = color = None
    for ctype, payload in read_chunks(data):
        if ctype == b"IHDR":
            width, height, depth, color = struct.unpack(">IIBB", payload[:10])
        elif ctype == b"IDAT":
            idat += payload

    if color != 6:
        print(f"{path.name} : déjà sans canal alpha (type {color}), rien à faire.")
        return False
    if depth != 8:
        raise SystemExit(f"Profondeur {depth} bits non gérée — réexporter en 8 bits.")

    pixels = unfilter(zlib.decompress(idat), width, height, 4)

    # Couleur de fond = premier pixel, ramené à l'opacité pleine.
    br, bg, bb = pixels[0], pixels[1], pixels[2]
    print(f"Fond échantillonné : #{br:02X}{bg:02X}{bb:02X}")

    rgb = bytearray()
    partial = 0
    for y in range(height):
        rgb.append(0)                                  # filtre « None »
        base = y * width * 4
        for x in range(width):
            i = base + x * 4
            r, g, b, a = pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]
            if a != 255:
                partial += 1
                r = (r * a + br * (255 - a)) // 255
                g = (g * a + bg * (255 - a)) // 255
                b = (b * a + bb * (255 - a)) // 255
            rgb += bytes((r, g, b))

    print(f"{partial} pixel(s) non opaques composés sur le fond.")

    out = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(bytes(rgb), 9))
           + chunk(b"IEND", b""))
    path.write_bytes(out)
    print(f"→ {path} réécrit en RGB opaque ({len(out) // 1024} Kio)")
    return True


if __name__ == "__main__":
    target = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
    flatten(target)
