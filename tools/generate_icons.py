#!/usr/bin/env python3
"""
Generate PNG app icons from the same artwork as icon.svg, with no external
dependencies (pure stdlib: zlib + struct + math).

Artwork (in a 512x512 coordinate space, matching icon.svg):
  - rounded blue tile background (#0ea5e9)
  - two rounded check-boxes, a checkmark, and two lines, stroked in #04121f

Outputs:
  icon-192.png            192x192, rounded tile           (manifest "any")
  icon-512.png            512x512, rounded tile           (manifest "any")
  icon-512-maskable.png   512x512, full-bleed + safe zone (manifest "maskable")
  apple-touch-icon.png    180x180, full-bleed             (iOS home screen)

Each is rendered at an integer supersample factor and box-downsampled with
premultiplied alpha for clean, fringe-free anti-aliasing.
"""
import math
import os
import struct
import zlib

BG = (14, 165, 233)   # #0ea5e9
DARK = (4, 18, 31)     # #04121f

STROKE = 34.0
BG_RX = 96.0
BOX1 = (118.0, 118.0, 120.0, 120.0, 26.0)   # x, y, w, h, r
BOX2 = (118.0, 288.0, 120.0, 120.0, 26.0)
CHECK = [(140.0, 178.0), (168.0, 206.0), (220.0, 150.0)]
LINE1 = ((290.0, 178.0), (404.0, 178.0))
LINE2 = ((290.0, 348.0), (404.0, 348.0))


def rrect_sdf(px, py, x, y, w, h, r):
    cx, cy = x + w / 2.0, y + h / 2.0
    hx, hy = w / 2.0, h / 2.0
    qx = abs(px - cx) - (hx - r)
    qy = abs(py - cy) - (hy - r)
    outside = math.hypot(max(qx, 0.0), max(qy, 0.0))
    inside = min(max(qx, qy), 0.0)
    return outside + inside - r


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    l2 = dx * dx + dy * dy
    if l2 == 0.0:
        return math.hypot(px - ax, py - ay)
    t = ((px - ax) * dx + (py - ay) * dy) / l2
    t = 0.0 if t < 0.0 else 1.0 if t > 1.0 else t
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def render_master(n, maskable):
    """Render an n x n RGBA buffer (list of (r,g,b,a)) in 512-space scaled to n."""
    s = n / 512.0
    k = 0.78 if maskable else 1.0          # content scale for maskable safe zone
    half = STROKE * s * k / 2.0

    def tx(X, Y):
        return (256.0 + (X - 256.0) * k) * s, (256.0 + (Y - 256.0) * k) * s

    # Transformed primitives (pixel space).
    def box(b):
        x, y = tx(b[0], b[1])
        return (x, y, b[2] * s * k, b[3] * s * k, b[4] * s * k)
    b1, b2 = box(BOX1), box(BOX2)
    chk = [tx(*p) for p in CHECK]
    l1 = (tx(*LINE1[0]), tx(*LINE1[1]))
    l2 = (tx(*LINE2[0]), tx(*LINE2[1]))

    # Bounding boxes (expanded by stroke half) for quick rejection.
    def bbox_rect(b):
        return (b[0] - half, b[1] - half, b[0] + b[2] + half, b[1] + b[3] + half)

    def bbox_seg(a, c):
        return (min(a[0], c[0]) - half, min(a[1], c[1]) - half,
                max(a[0], c[0]) + half, max(a[1], c[1]) + half)
    boxes_bb = [bbox_rect(b1), bbox_rect(b2)]
    segs = [(chk[0], chk[1]), (chk[1], chk[2]), l1, l2]
    segs_bb = [bbox_seg(a, c) for (a, c) in segs]

    bg_r = BG_RX * s
    buf = bytearray(n * n * 4)
    bgr, bgg, bgb = BG
    dr, dg, db = DARK
    i = 0
    for py in range(n):
        pyf = py + 0.5
        for px in range(n):
            pxf = px + 0.5
            inside_bg = True if maskable else (rrect_sdf(pxf, pyf, 0.0, 0.0, n, n, bg_r) <= 0.0)
            if not inside_bg:
                i += 4
                continue
            dark = False
            # boxes (stroked border)
            for (bb, b) in ((boxes_bb[0], b1), (boxes_bb[1], b2)):
                if bb[0] <= pxf <= bb[2] and bb[1] <= pyf <= bb[3]:
                    if abs(rrect_sdf(pxf, pyf, b[0], b[1], b[2], b[3], b[4])) <= half:
                        dark = True
                        break
            if not dark:
                for (bb, (a, c)) in zip(segs_bb, segs):
                    if bb[0] <= pxf <= bb[2] and bb[1] <= pyf <= bb[3]:
                        if seg_dist(pxf, pyf, a[0], a[1], c[0], c[1]) <= half:
                            dark = True
                            break
            if dark:
                buf[i] = dr; buf[i + 1] = dg; buf[i + 2] = db; buf[i + 3] = 255
            else:
                buf[i] = bgr; buf[i + 1] = bgg; buf[i + 2] = bgb; buf[i + 3] = 255
            i += 4
    return buf


def downsample(buf, n, ss):
    """Box-downsample an n x n RGBA buffer by factor ss using premultiplied alpha."""
    out_n = n // ss
    out = bytearray(out_n * out_n * 4)
    area = ss * ss
    oi = 0
    for oy in range(out_n):
        for ox in range(out_n):
            ar = ag = ab = aa = 0
            base = (oy * ss) * n + (ox * ss)
            for dy in range(ss):
                row = (base + dy * n) * 4
                for dx in range(ss):
                    p = row + dx * 4
                    a = buf[p + 3]
                    ar += buf[p] * a
                    ag += buf[p + 1] * a
                    ab += buf[p + 2] * a
                    aa += a
            if aa:
                out[oi] = round(ar / aa)
                out[oi + 1] = round(ag / aa)
                out[oi + 2] = round(ab / aa)
            out[oi + 3] = round(aa / area)
            oi += 4
    return out, out_n


def write_png(path, buf, n):
    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data +
                struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff))
    raw = bytearray()
    for y in range(n):
        raw.append(0)                      # filter type 0 (None)
        raw += buf[y * n * 4:(y + 1) * n * 4]
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", n, n, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def make(path, size, ss, maskable=False):
    master = render_master(size * ss, maskable)
    small, n = downsample(master, size * ss, ss)
    write_png(path, small, n)
    print("wrote", path, f"{n}x{n}")


if __name__ == "__main__":
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    make(os.path.join(here, "icon-192.png"), 192, 4)
    make(os.path.join(here, "icon-512.png"), 512, 3)
    make(os.path.join(here, "icon-512-maskable.png"), 512, 3, maskable=True)
    make(os.path.join(here, "apple-touch-icon.png"), 180, 4, maskable=True)
    print("done")
