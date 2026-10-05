"""Freeform art of the Sunken Gardens asset pack for the Metroidvania Developer System.

Writes the PNGs in ../freeform/ (run it from anywhere):

    python asset_packs/sunken_gardens/tools/sunken_gardens.py

- fill_limestone.png, fill_ruin.png, fill_deep.png, fill_silhouette.png: 256 x 256 fills that
  repeat both ways. Warm limestone courses with moss creeping over them (the level's ground, as
  terrain.gdshader paints it), the darker sunken ruin behind the play area, the near-black rock deep
  inside the ground, and the leaf black of the foreground.
- edge_*.png: 512 x 64 strips repeating horizontally, for IDPFreeformStyle's top and bottom edges.
  Top strips have the outside on their top row (grass stands up out of the ground); bottom strips
  have the inside on their top row (roots, ivy and drips hang below the rock).
- clumps.png: a 128 x 128 atlas of grass tufts, flowers, ferns, moss, hanging ivy, background
  leaves and foreground silhouettes, described by sunken_gardens.stamps.tres.

Everything is painted at paint.S times the final size and filtered down (paint.py, the
Mossgrove asset pack's helpers), so it is soft and anti-aliased. Fixed seeds: a run always paints
the same art. The .tres resources next to the PNGs are written by hand and only need the regions
printed below.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from paint import (S, hexc, lerp, smoothstep, ramp, fractal, fractal1d, shade, over, layer,  # noqa: E402
                   mask_from, down, save)
from PIL import Image, ImageDraw  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "freeform")

# Warm limestone, dark to light (the level's stone is Color(0.538, 0.507, 0.349)).
LIME = ["#2f2a1c", "#4f4630", "#7a6d4b", "#a39469", "#cbbd91"]
GRASS = ["#13290d", "#255016", "#3f7d26", "#72b03b", "#b6de68"]
IVY = ["#0d200d", "#1b3f18", "#2f6326", "#4f9038", "#8cc75e"]
# Solid ground deep inside the rock (a room's notches): almost black, the stone's courses just showing.
DEEP = ["#060504", "#0b0906", "#110e09", "#17130d", "#1e1911"]
# The sunken ruin behind the rooms: the same stone, sunk into green shadow.
RUIN = ["#151a12", "#20271b", "#2d3624", "#3d4930", "#53613f"]
FLOWERS = ["#f3e6a6", "#ee8fae", "#b9a3f0", "#ffd36b", "#f6f1e6"]
ROOT = ["#130d07", "#2a1d10", "#4a3520", "#6b5131"]
INK = "#120f08"

W_E, H_E = 512, 64
CELL = 128


def rng(seed):
    return np.random.default_rng(seed)


def _wrap_draw(w, h, draw_fn, periodic=True):
    """Mask drawn with PIL three times, shifted by -w, 0 and +w, so strips repeat seamlessly."""
    im = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(im)
    for ox in ((-w, 0, w) if periodic else (0,)):
        draw_fn(d, ox)
    return np.asarray(im) > 127


def _blade(cx, base_y, height, lean, width):
    """A tapering, slightly curved grass blade as a polygon (supersampled px)."""
    pts_l, pts_r = [], []
    for i in range(9):
        t = i / 8
        x = cx + lean * t * t
        y = base_y - height * t
        wd = width * (1 - t) ** 0.9
        pts_l.append((x - wd, y))
        pts_r.append((x + wd, y))
    return pts_l + pts_r[::-1]


def _leaf(c, ang, ln, wd):
    ax = np.array([np.cos(ang), np.sin(ang)])
    nm = np.array([-ax[1], ax[0]])
    pts = []
    for side in (1, -1):
        for i in (range(0, 11) if side == 1 else range(10, -1, -1)):
            t = i / 10
            p = c + ax * t * ln + nm * side * wd * np.sin(np.pi * t) ** 0.8
            pts.append((p[0], p[1]))
    return pts


def _floret(d, x, y, r, ox=0):
    for k in range(5):
        a = k * 2 * np.pi / 5
        px, py = x + ox + np.cos(a) * r * 0.9, y + np.sin(a) * r * 0.9
        d.ellipse([px - r * 0.7, py - r * 0.7, px + r * 0.7, py + r * 0.7], fill=255)


def _wrap_circles(w, h, circles, periodic_x=True):
    yy, xx = np.mgrid[0:h, 0:w] + 0.5
    m = np.zeros((h, w), bool)
    for cx, cy, r in circles:
        for ox in ((-w, 0, w) if periodic_x else (0,)):
            x0, x1 = int(max(0, cx + ox - r)), int(min(w, cx + ox + r + 1))
            y0, y1 = int(max(0, cy - r)), int(min(h, cy + r + 1))
            if x0 >= x1 or y0 >= y1:
                continue
            m[y0:y1, x0:x1] |= (xx[y0:y1, x0:x1] - cx - ox) ** 2 + (yy[y0:y1, x0:x1] - cy) ** 2 <= r * r
    return m


def _bubbles(img, circles, colors, w, h, periodic_x=True, outline="#0b1a08"):
    g = fractal(h, w, 0.5, 99)
    for cx, cy, r, tone in circles:
        m = _wrap_circles(w, h, [(cx, cy, r)], periodic_x)
        base = ramp([hexc(c) for c in colors], np.array(tone))
        sh = shade(m, np.append(base, 1.0), soft=r * 0.45, outline=hexc(outline), outline_w=0.8,
                   light=(-0.5, -0.8), diffuse=0.55)
        sh[..., :3] *= (0.82 + 0.36 * g)[..., None]
        over(img, sh)


# --- Fills (256 x 256, repeat both ways) -------------------------------------------------------

def _ashlar(seed, colors, mortar, moss_amount, rows=4, crack_amount=0.5, moss_colors=GRASS[:4]):
    """Coursed blocks with rounded corners, bevelled edges, weathering, cracks and moss."""
    n = 256 * S
    r = rng(seed)
    yy, xx = np.mgrid[0:n, 0:n] + 0.5
    rh = n / rows
    sdf = np.zeros((n, n))
    tone = np.zeros((n, n))
    fy = np.zeros((n, n))      # 0 at a block's top, 1 at its bottom
    fx = np.zeros((n, n))
    gap, rad = 2.2 * S, 7 * S
    for row in range(rows):
        widths = []
        while sum(widths) < n * 0.82:
            widths.append(r.uniform(58, 128) * S)
        widths = np.array(widths) * n / sum(widths)
        edges = np.cumsum(widths)
        starts = np.concatenate([[0], edges[:-1]])
        tones = r.uniform(0.2, 0.9, len(widths))
        off = r.uniform(0, n)
        ys = slice(int(row * rh), int((row + 1) * rh))
        lx = (xx[ys] + off) % n
        idx = np.minimum(np.searchsorted(edges, lx, side="right"), len(widths) - 1)
        bx = lx - starts[idx]
        bw = widths[idx]
        by = yy[ys] - row * rh
        px = np.abs(bx - bw / 2) - (bw / 2 - gap) + rad
        py = np.abs(by - rh / 2) - (rh / 2 - gap) + rad
        sdf[ys] = np.hypot(np.maximum(px, 0), np.maximum(py, 0)) + np.minimum(np.maximum(px, py), 0) - rad
        tone[ys] = tones[idx]
        fy[ys] = by / rh
        fx[ys] = bx / bw
    broad = fractal(n, n, 2.6, seed + 1)
    grain = fractal(n, n, 1.0, seed + 2)
    t = np.clip(0.18 + 0.55 * tone * (0.55 + 0.45 * broad) + (grain - 0.5) * 0.22 - 0.18 * fy, 0, 1)
    col = ramp([hexc(c) for c in colors], t)
    inside = -sdf
    edge = 1 - smoothstep(0, 6 * S, inside)
    lit = (0.5 - fy) + (0.5 - fx) * 0.5           # top-left edges catch the light
    col = col * (1 + 0.35 * edge * np.clip(lit, -1, 1))[..., None]
    # Pits and cracks.
    pits = fractal(n, n, 0.6, seed + 3) > 0.86
    col = lerp(col, col * 0.62, pits * 0.8)
    crack_n = fractal(n, n, 2.2, seed + 4)
    crack = (np.abs(crack_n - 0.5) < 0.006 * S / 4 + 0.004) & (fractal(n, n, 3.0, seed + 5) > 1 - crack_amount * 0.6)
    col = lerp(col, hexc(mortar)[:3], crack * 0.85)
    # Mortar joints.
    joint = smoothstep(-0.8 * S, 0.8 * S, sdf)
    col = lerp(col, hexc(mortar)[:3], joint)
    img = np.zeros((n, n, 4))
    img[..., :3] = col
    img[..., 3] = 1
    if moss_amount > 0:
        m = fractal(n, n, 2.3, seed + 9)
        near_joint = 1 - smoothstep(0, 10 * S, inside)
        cover = smoothstep(1 - moss_amount - 0.06, 1 - moss_amount + 0.08, m + 0.12 * near_joint + 0.08 * (1 - fy))
        mg = fractal(n, n, 0.7, seed + 10)
        moss = ramp([hexc(c) for c in moss_colors], np.clip(0.25 + 0.55 * mg + 0.25 * (1 - fy), 0, 1))
        img[..., :3] = lerp(img[..., :3], moss, cover * (0.75 + 0.25 * mg))
    return img


def fill_limestone(seed=11):
    return _ashlar(seed, LIME, "#1a160c", 0.24)


def fill_ruin(seed=12):
    return _ashlar(seed, RUIN, "#0a0d08", 0.3, rows=3, crack_amount=0.8, moss_colors=[RUIN[1], IVY[1], IVY[2]])


def fill_deep(seed=14):
    return _ashlar(seed, DEEP, "#030302", 0.0, rows=3, crack_amount=0.3)


def fill_silhouette(seed=13):
    n = 256 * S
    img = np.zeros((n, n, 4))
    t = fractal(n, n, 2.0, seed)
    img[..., :3] = ramp([hexc("#030503"), hexc("#0b120a")], t * 0.8)
    img[..., 3] = 1
    return img


# --- Edge strips (512 x 64, repeat horizontally) ---------------------------------------------------

def edge_grass(seed=21):
    """Garden turf on a top edge: a moss lip over the stone, grass standing above it, a few flowers."""
    w, h = W_E * S, H_E * S
    r = rng(seed)
    img = np.zeros((h, w, 4))
    yy, xx = np.mgrid[0:h, 0:w] + 0.5
    surf = 30 * S + 1.5 * S * fractal1d(w, 1.6, seed + 1, 3)[None, :]
    depth = (11 + 7 * np.abs(fractal1d(w, 1.2, seed + 2, 6)))[None, :] * S
    t = np.clip((yy - surf) / depth, 0, 1)
    body = (yy >= surf - 1 * S) & (yy < surf + depth)
    col = ramp([hexc(GRASS[3]), hexc(GRASS[2]), hexc(GRASS[1]), hexc(GRASS[0])], t)
    over(img, layer(col, body * (1 - smoothstep(0.7, 1.0, t))))
    # Soft shadow the turf throws on the stone under it.
    sh = (yy >= surf + depth * 0.7) & (yy < surf + depth + 7 * S)
    over(img, layer(hexc(INK)[:3], sh * 0.35 * (1 - np.clip((yy - surf - depth * 0.7) / (8 * S), 0, 1))))
    # Blades, back (dark) to front (light).
    for bucket in range(6):
        tone = 0.15 + bucket * 0.16
        blades = []
        for k in range(70):
            x0 = r.uniform(0, w)
            sy = 30 * S + 1.5 * S * fractal1d(w, 1.6, seed + 1, 3)[int(x0) % w]
            tall = r.uniform(6, 15) if r.random() < 0.8 else r.uniform(15, 25)
            blades.append(_blade(x0, sy + 3 * S, tall * S, r.uniform(-7, 7) * S, r.uniform(1.4, 2.4) * S))
        m = _wrap_draw(w, h, lambda d, ox: [d.polygon([(x + ox, y) for x, y in b], fill=255) for b in blades])
        c = ramp([hexc(c) for c in GRASS], np.clip(tone + 0.25 * (1 - yy / (32 * S)), 0, 1))
        over(img, layer(c, m.astype(float)))
    # Flowers among the blades.
    for k in range(16):
        x0, y0 = r.uniform(0, w), r.uniform(10, 22) * S
        petals = _wrap_draw(w, h, lambda d, ox: _floret(d, x0, y0, r.uniform(1.6, 2.4) * S, ox))
        over(img, shade(petals, hexc(FLOWERS[k % len(FLOWERS)]), soft=1.0, outline=hexc("#3d2a1a"), outline_w=0.4))
        heart = _wrap_circles(w, h, [(x0, y0, 0.9 * S)])
        over(img, layer(hexc("#ffcf4a")[:3], heart.astype(float)))
    return img


def edge_roots(seed=22):
    """Underside of the limestone: a shadowed rim inside, then roots, ivy and drips hanging below."""
    w, h = W_E * S, H_E * S
    r = rng(seed)
    img = np.zeros((h, w, 4))
    yy, xx = np.mgrid[0:h, 0:w] + 0.5
    surf = 24 * S
    rim = yy < surf + 1 * S
    over(img, layer(ramp([hexc("#3a3322"), hexc("#1a160d")], np.clip(yy / surf, 0, 1)),
                    rim * smoothstep(0, 8 * S, yy)))
    # Roots: brown, tapering, wandering.
    for k in range(26):
        x0 = r.uniform(0, w)
        ln = r.uniform(10, 36) * S
        wd = r.uniform(1.4, 3.2) * S
        ph = r.uniform(0, 6)
        pts_l, pts_r = [], []
        for i in range(12):
            t = i / 11
            x = x0 + np.sin(t * 3 + ph) * 3 * S * t
            y = surf - 3 * S + ln * t
            ww = wd * (1 - t) + 0.3 * S
            pts_l.append((x - ww, y))
            pts_r.append((x + ww, y))
        poly = pts_l + pts_r[::-1]
        m = _wrap_draw(w, h, lambda d, ox: d.polygon([(x + ox, y) for x, y in poly], fill=255))
        over(img, layer(ramp([hexc(c) for c in ROOT[::-1]], np.clip((yy - surf) / ln, 0, 1)), m.astype(float)))
    # Ivy strands with small leaves.
    for k in range(14):
        x0 = r.uniform(0, w)
        ln = r.uniform(18, 38) * S
        stem = [(x0 + np.sin(i * 0.9 + k) * 2 * S, surf - 2 * S + ln * i / 10) for i in range(11)]
        m = _wrap_draw(w, h, lambda d, ox: d.line([(x + ox, y) for x, y in stem], fill=255, width=int(1.2 * S)))
        over(img, layer(hexc(IVY[1])[:3], m.astype(float)))
        for i in range(2, 11, 2):
            sx, sy = stem[i]
            side = 1 if i % 4 else -1
            leaf = _leaf(np.array([sx, sy]), np.pi / 2 + side * 0.9, r.uniform(5, 8) * S, r.uniform(2.2, 3.2) * S)
            lm = _wrap_draw(w, h, lambda d, ox: d.polygon([(x + ox, y) for x, y in leaf], fill=255))
            over(img, shade(lm, hexc(IVY[r.integers(2, 5)]), soft=1.2, outline=hexc(IVY[0]), outline_w=0.5))
    # Water beading under the stone (the gardens are sunken: everything drips).
    drips = _wrap_circles(w, h, [(r.uniform(0, w), r.uniform(26, 44) * S, r.uniform(1.2, 2.2) * S) for _ in range(18)])
    over(img, shade(drips, hexc("#a8e2dc"), soft=1.0, outline=hexc("#2e5a57"), outline_w=0.4))
    return img


def edge_hedge(seed=23):
    """Leafy crown on the ruin behind the rooms."""
    w, h = W_E * S, H_E * S
    r = rng(seed)
    img = np.zeros((h, w, 4))
    circles, x = [], 0.0
    while x < w:
        rad = r.uniform(9, 18) * S
        circles.append((x, 38 * S - r.uniform(0, 9) * S, rad, r.uniform(0.25, 0.7)))
        x += rad * r.uniform(0.8, 1.2)
    circles.sort(key=lambda c: -c[1])
    _bubbles(img, circles, IVY[:4], w, h, True, outline="#081208")
    return img


def edge_silhouette(seed=24):
    """Leaf-black fringe on foreground shapes."""
    w, h = W_E * S, H_E * S
    r = rng(seed)
    img = np.zeros((h, w, 4))
    yy = np.mgrid[0:h, 0:w][0] + 0.5
    over(img, layer(hexc("#040604")[:3], (yy > 38 * S).astype(float)))
    for k in range(50):
        x0 = r.uniform(0, w)
        ln = r.uniform(14, 34) * S
        leaf = _leaf(np.array([x0, 42 * S]), -np.pi / 2 + r.uniform(-0.9, 0.9), ln, ln * r.uniform(0.18, 0.3))
        m = _wrap_draw(w, h, lambda d, ox: d.polygon([(x + ox, y) for x, y in leaf], fill=255))
        over(img, layer(ramp([hexc("#030503"), hexc("#0c150b")], np.full((h, w), r.uniform(0, 1))), m.astype(float)))
    return img


# --- Clumps atlas (128 x 128 cells) --------------------------------------------------------------

def _cell():
    return np.zeros((CELL * S, CELL * S, 4))


def clump_grass(seed):
    """A tuft of garden grass, sometimes flowering, growing up from the bottom centre."""
    img = _cell()
    n = CELL * S
    r = rng(seed)
    yy = np.mgrid[0:n, 0:n][0] + 0.5
    for bucket in range(4):
        blades = []
        for k in range(r.integers(12, 20)):
            x0 = n / 2 + r.normal(0, 13) * S
            blades.append(_blade(x0, n - 2 * S, r.uniform(26, 70) * S, r.uniform(-22, 22) * S, r.uniform(2.0, 3.4) * S))
        m = mask_from(n, n, lambda d: [d.polygon(b, fill=255) for b in blades])
        c = ramp([hexc(c) for c in GRASS], np.clip(0.2 + bucket * 0.2 + 0.2 * (1 - yy / n), 0, 1))
        over(img, layer(c, m.astype(float)))
    if seed % 2 == 0:
        for k in range(r.integers(3, 6)):
            x0, y0 = n / 2 + r.uniform(-30, 30) * S, n - r.uniform(40, 80) * S
            m = mask_from(n, n, lambda d: _floret(d, x0, y0, r.uniform(3, 4.5) * S))
            over(img, shade(m, hexc(FLOWERS[(seed + k) % len(FLOWERS)]), soft=1.5, outline=hexc("#3d2a1a"), outline_w=0.5))
            over(img, layer(hexc("#ffcf4a")[:3], _wrap_circles(n, n, [(x0, y0, 1.6 * S)], False).astype(float)))
    return img


def clump_flower(seed):
    """Tall stems with bell flowers, like foxgloves gone wild in the sunken beds."""
    img = _cell()
    n = CELL * S
    r = rng(seed)
    petal = FLOWERS[seed % 3 + 1]
    for f in range(r.integers(2, 4)):
        base = np.array([n / 2 + r.uniform(-14, 14) * S, n - 2 * S])
        a = -np.pi / 2 + r.uniform(-0.35, 0.35)
        length = r.uniform(80, 116) * S
        pts = [base.copy()]
        for i in range(16):
            a += r.uniform(-0.04, 0.04)
            pts.append(pts[-1] + np.array([np.cos(a), np.sin(a)]) * length / 16)
        stem = mask_from(n, n, lambda d: d.line([tuple(p) for p in pts], fill=255, width=int(2.0 * S)))
        over(img, layer(hexc(GRASS[1])[:3], stem.astype(float)))
        for i in range(3, 9, 2):
            leaf = _leaf(pts[i], -np.pi / 2 + (0.9 if i % 4 == 1 else -0.9), r.uniform(14, 22) * S, r.uniform(4, 6) * S)
            m = mask_from(n, n, lambda d: d.polygon(leaf, fill=255))
            over(img, shade(m, hexc(GRASS[r.integers(2, 4)]), outline=hexc(GRASS[0]), outline_w=0.6))
        for i in range(9, 17):
            p = pts[i]
            rad = (4.5 - (i - 9) * 0.35) * S
            side = 1 if i % 2 else -1
            m = _wrap_circles(n, n, [(p[0] + side * rad * 0.9, p[1] + rad * 0.3, rad)], False)
            over(img, shade(m, hexc(petal), outline=hexc("#40243a"), outline_w=0.5, soft=rad * 0.5))
    return img


def clump_fern(seed):
    img = _cell()
    n = CELL * S
    r = rng(seed)
    for f in range(5):
        base = np.array([n / 2 + r.uniform(-6, 6) * S, n - 2 * S])
        a = -np.pi / 2 + r.uniform(-1.1, 1.1)
        curl = 0.05 if a < -np.pi / 2 else -0.05
        length = r.uniform(70, 104) * S
        pts = [base.copy()]
        for i in range(20):
            a += curl
            pts.append(pts[-1] + np.array([np.cos(a), np.sin(a)]) * length / 20)
        stem = mask_from(n, n, lambda d: d.line([tuple(p) for p in pts], fill=255, width=int(1.6 * S)))
        over(img, layer(hexc(GRASS[1])[:3], stem.astype(float)))
        for i in range(2, 20, 2):
            q = pts[i]
            ang = np.arctan2(*(pts[i + 1] - pts[i - 1])[::-1])
            size = (1 - i / 20) * 16 * S + 4 * S
            for side in (-1, 1):
                leaf = _leaf(q, ang + side * 1.1, size, size * 0.2)
                m = mask_from(n, n, lambda d: d.polygon(leaf, fill=255))
                over(img, layer(ramp([hexc(c) for c in GRASS], np.full((n, n), 0.35 + 0.5 * i / 20)), m.astype(float)))
    return img


def clump_moss(seed):
    img = _cell()
    n = CELL * S
    r = rng(seed)
    circles = []
    for k in range(r.integers(6, 10)):
        rad = r.uniform(11, 22) * S
        cx = n / 2 + r.uniform(-32, 32) * S
        cy = n - rad - r.uniform(0, 22) * S - abs(cx - n / 2) * 0.3
        circles.append((cx, cy, rad, r.uniform(0.4, 0.95)))
    circles.sort(key=lambda c: -c[1])
    _bubbles(img, circles, GRASS, n, n, False)
    return img


def clump_ivy(seed):
    """Ivy hanging from an overhang (anchored at the top)."""
    img = _cell()
    n = CELL * S
    r = rng(seed)
    for k in range(r.integers(5, 8)):
        x = n / 2 + r.uniform(-40, 40) * S
        ln = r.uniform(50, 122) * S
        stem = [(x + np.sin(i * 0.7 + k) * 5 * S, ln * i / 14) for i in range(15)]
        m = mask_from(n, n, lambda d: d.line(stem, fill=255, width=int(1.6 * S)))
        over(img, layer(hexc(IVY[1])[:3], m.astype(float)))
        for i in range(1, 15):
            sx, sy = stem[i]
            side = 1 if i % 2 else -1
            sz = r.uniform(7, 11) * S * (1 - 0.35 * i / 14)
            leaf = _leaf(np.array([sx, sy]), np.pi / 2 + side * 1.0, sz, sz * 0.45)
            lm = mask_from(n, n, lambda d: d.polygon(leaf, fill=255))
            over(img, shade(lm, hexc(IVY[r.integers(2, 5)]), outline=hexc(IVY[0]), outline_w=0.6, soft=sz * 0.3))
    return img


def clump_leaf_bg(seed):
    """Dark round foliage for behind the play area."""
    img = _cell()
    n = CELL * S
    r = rng(seed)
    circles = []
    for k in range(r.integers(7, 12)):
        rad = r.uniform(14, 30) * S
        circles.append((n / 2 + r.uniform(-30, 30) * S, n / 2 + r.uniform(-24, 30) * S, rad, r.uniform(0.2, 0.65)))
    circles.sort(key=lambda c: -c[1])
    _bubbles(img, circles, RUIN[1:] + [IVY[2]], n, n, False, outline="#070b06")
    return img


def clump_silhouette(seed):
    img = _cell()
    n = CELL * S
    r = rng(seed)
    for k in range(r.integers(9, 15)):
        leaf = _leaf(np.array([n / 2 + r.uniform(-14, 14) * S, n - 2 * S]), -np.pi / 2 + r.uniform(-1.4, 1.4),
                     r.uniform(30, 64) * S, r.uniform(6, 14) * S)
        m = mask_from(n, n, lambda d: d.polygon(leaf, fill=255))
        over(img, layer(ramp([hexc("#030503"), hexc("#0c150b")], np.full((n, n), r.uniform(0, 1))), m.astype(float)))
    return img


# Order matters: sunken_gardens.stamps.tres lists the regions in this order.
CLUMPS = (
    [("grass", lambda s=s: clump_grass(s), (0.5, 0.98)) for s in range(6)]
    + [("flower", lambda s=s: clump_flower(10 + s), (0.5, 0.98)) for s in range(3)]
    + [("fern", lambda s=s: clump_fern(20 + s), (0.5, 0.98)) for s in range(2)]
    + [("moss", lambda s=s: clump_moss(30 + s), (0.5, 0.95)) for s in range(3)]
    + [("ivy", lambda s=s: clump_ivy(40 + s), (0.5, 0.02)) for s in range(3)]
    + [("leaf_bg", lambda s=s: clump_leaf_bg(50 + s), (0.5, 0.5)) for s in range(3)]
    + [("silhouette", lambda s=s: clump_silhouette(60 + s), (0.5, 0.98)) for s in range(4)]
)

FILLS = {"limestone": fill_limestone, "ruin": fill_ruin, "deep": fill_deep, "silhouette": fill_silhouette}
EDGES = {"grass": edge_grass, "roots": edge_roots, "hedge": edge_hedge, "silhouette": edge_silhouette}


def clumps_atlas(cols=8):
    rows = (len(CLUMPS) + cols - 1) // cols
    img = np.zeros((rows * CELL * S, cols * CELL * S, 4))
    table = []
    for i, (cat, fn, anchor) in enumerate(CLUMPS):
        x, y = (i % cols) * CELL * S, (i // cols) * CELL * S
        img[y:y + CELL * S, x:x + CELL * S] = fn()
        table.append((cat, (i % cols) * CELL, (i // cols) * CELL, anchor))
    return img, table


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, fn in FILLS.items():
        save(down(fn()), os.path.join(OUT, "fill_%s.png" % name))
        print("fill", name)
    for name, fn in EDGES.items():
        save(down(fn()), os.path.join(OUT, "edge_%s.png" % name))
        print("edge", name)
    img, table = clumps_atlas()
    save(down(img), os.path.join(OUT, "clumps.png"))
    for cat, x, y, anchor in table:
        print("clump %-10s Rect2(%d, %d, %d, %d) anchor %s" % (cat, x, y, CELL, CELL, anchor))


if __name__ == "__main__":
    main()
