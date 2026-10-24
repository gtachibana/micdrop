"""Generates the 1024x1024 MicDrop app icon (opaque RGB PNG) with no dependencies."""
import math
import struct
import sys
import zlib

SIZE = 1024
SS = 3  # supersampling per axis for anti-aliasing


def lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


TOP = (40, 8, 74)
BOTTOM = (214, 24, 110)
HEAD = (236, 236, 244)
HEAD_SHADE = (170, 170, 190)
BODY = (34, 30, 48)
RING = (255, 255, 255)

HEAD_C = (560, 400)
HEAD_R = 190


def sample(x, y):
    """Colour at a (sub)pixel, or None for background."""
    # Microphone tilted 30 degrees: rotate the point into mic space around the head centre.
    ang = math.radians(-30)
    dx, dy = x - HEAD_C[0], y - HEAD_C[1]
    mx = dx * math.cos(ang) - dy * math.sin(ang)
    my = dx * math.sin(ang) + dy * math.cos(ang)

    # Handle: tapered body below the head.
    if HEAD_R * 0.75 < my < HEAD_R + 420:
        t = (my - HEAD_R * 0.75) / (420 + HEAD_R * 0.25)
        half = 95 - 45 * t
        if abs(mx) < half:
            if abs(my - (HEAD_R + 30)) < 14:
                return RING
            return BODY

    d = math.hypot(mx, my)
    if d < HEAD_R:
        # Grille: diagonal mesh with simple shading.
        shade = 1 - 0.35 * max(0.0, (mx + my) / (HEAD_R * 1.4))
        g = (abs((mx + my) % 46) < 6) or (abs((mx - my) % 46) < 6)
        base = HEAD_SHADE if g else HEAD
        return tuple(c * shade for c in base)
    if d < HEAD_R + 16:
        return BODY
    return None


def pixel(px, py):
    acc = [0.0, 0.0, 0.0]
    for sy in range(SS):
        for sx in range(SS):
            x = px + (sx + 0.5) / SS
            y = py + (sy + 0.5) / SS
            c = sample(x, y)
            if c is None:
                c = lerp(TOP, BOTTOM, y / SIZE)
            for i in range(3):
                acc[i] += c[i]
    n = SS * SS
    return bytes(max(0, min(255, int(a / n))) for a in acc)


def write_png(path, rows):
    raw = b"".join(b"\x00" + row for row in rows)

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def main():
    out = sys.argv[1]
    rows = []
    for y in range(SIZE):
        rows.append(b"".join(pixel(x, y) for x in range(SIZE)))
    write_png(out, rows)


if __name__ == "__main__":
    main()
