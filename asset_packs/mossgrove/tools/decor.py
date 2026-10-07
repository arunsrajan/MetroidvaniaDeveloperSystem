"""Decoration tiles (32 px) tagged with MDS kinds, so Auto-decorate and Generate cave use
them: grass, fern, flower, mushroom, hanging_moss, vine_top/mid/end, stalactite_small/
large, and foliage (opaque background tiles that tile seamlessly)."""
import numpy as np
from scipy import ndimage
from paint import S, hexc, lerp, smoothstep, ramp, fractal, shade, glow, over, layer, mask_from

T = 32
N = T * S
COLS = 8

GREENS = ["#0f2a1c", "#1f4f2c", "#3f8a3a", "#7cc24e", "#c9ef7c"]
TEAL = ["#0b2227", "#15414a", "#2a6f73", "#5fb3a4", "#bff0de"]
STONE = ["#0e131c", "#222b3a", "#3c4a61", "#7187a6"]


def leaf_poly(c, angle, length, width, s=S):
    """Pointed leaf outline (both ends taper), from its base point c along angle."""
    pts = []
    ax = np.array([np.cos(angle), np.sin(angle)])
    nm = np.array([-ax[1], ax[0]])
    for side in (1, -1):
        rng = range(0, 11) if side == 1 else range(10, -1, -1)
        for i in rng:
            t = i / 10
            p = np.asarray(c) + ax * t * length + nm * side * width * np.sin(np.pi * t) ** 0.8
            pts.append((p[0] * s, p[1] * s))
    return pts


def blank():
    return np.zeros((N, N, 4))


def blade(img, x0, h, bend, width, colors, seed):
    """A curved grass blade growing up from the tile bottom at x0 (final px)."""
    r = np.random.default_rng(seed)
    pts_l, pts_r = [], []
    steps = 10
    for i in range(steps + 1):
        t = i / steps
        x = x0 + bend * t * t
        y = T - t * h
        w = width * (1 - t) ** 0.8
        pts_l.append(((x - w / 2) * S, y * S))
        pts_r.append(((x + w / 2) * S, y * S))
    poly = pts_l + pts_r[::-1]
    m = mask_from(N, N, lambda d: d.polygon(poly, fill=255))
    yy = np.mgrid[0:N, 0:N][0] / S
    t = np.clip((T - yy) / max(h, 1), 0, 1)
    col = ramp([hexc(c) for c in colors], t * (0.85 + 0.15 * r.random()))
    over(img, layer(col, m.astype(float)))


def grass(seed):
    img = blank()
    r = np.random.default_rng(seed)
    for k in range(r.integers(13, 18)):
        x0 = r.uniform(3, T - 3)
        blade(img, x0, r.uniform(7, 17), r.uniform(-5, 5), r.uniform(1.6, 2.6), GREENS, seed * 50 + k)
    return img


def fern(seed):
    img = blank()
    r = np.random.default_rng(seed)
    for f in range(3):
        base = np.array([T / 2 + r.uniform(-3, 3), T])
        ang = -np.pi / 2 + r.uniform(-0.8, 0.8)
        length = r.uniform(14, 20)
        curl = r.uniform(-0.05, 0.05) + (0.04 if ang < -np.pi / 2 else -0.04)
        p = base.copy()
        pts = [p.copy()]
        a = ang
        for i in range(14):
            a += curl
            p = p + np.array([np.cos(a), np.sin(a)]) * length / 14
            pts.append(p.copy())
        stem = mask_from(N, N, lambda d: d.line([tuple(q * S) for q in pts], fill=255, width=int(1.2 * S)))
        over(img, layer(hexc(GREENS[1])[:3], stem.astype(float)))
        for i in range(2, 14, 2):
            q = pts[i]
            size = (1 - i / 14) * 4.0 + 1.5
            for side in (-1, 1):
                leaf = mask_from(N, N, lambda d: d.polygon(leaf_poly(q, a + side * 1.05, size, 0.55), fill=255))
                col = ramp([hexc(x) for x in GREENS], np.full((N, N), 0.3 + 0.6 * (i / 14) + side * 0.05))
                over(img, layer(col, leaf.astype(float)))
    return img


def flower(seed, bloom):
    img = grass(seed + 7)
    r = np.random.default_rng(seed)
    for k in range(2):
        x = T / 2 + (k - 0.5) * 9 + r.uniform(-2, 2)
        top = r.uniform(8, 13)
        stem = mask_from(N, N, lambda d: d.line([(x * S, T * S), ((x + r.uniform(-2, 2)) * S, top * S)], fill=255, width=int(1.0 * S)))
        over(img, layer(hexc(GREENS[2])[:3], stem.astype(float)))
        head = mask_from(N, N, lambda d: d.ellipse([(x - 3) * S, (top - 3) * S, (x + 3) * S, (top + 2.5) * S], fill=255))
        over(img, glow(head, hexc(bloom, 0.9), 3.0))
        over(img, shade(head, hexc(bloom), rim=hexc("#ffffff"), rim_dir=(-0.5, -0.8)))
    return img


def mushroom(seed, cap):
    img = blank()
    r = np.random.default_rng(seed)
    for k in range(r.integers(2, 4)):
        x = r.uniform(8, T - 8)
        h = r.uniform(7, 14)
        w = r.uniform(5, 9)
        stem = mask_from(N, N, lambda d: d.rounded_rectangle([(x - w * 0.18) * S, (T - h) * S, (x + w * 0.18) * S, T * S], radius=int(1 * S), fill=255))
        over(img, shade(stem, hexc("#d8d6c8"), outline=hexc("#2a2e33"), outline_w=0.7))
        capm = mask_from(N, N, lambda d: d.chord([(x - w) * S, (T - h - w * 0.7) * S, (x + w) * S, (T - h + w * 0.7) * S], 180, 360, fill=255))
        over(img, glow(capm, hexc(cap, 0.8), 3.5))
        over(img, shade(capm, hexc(cap), outline=hexc("#1c2a33"), outline_w=0.7, rim=hexc("#ffffff"), rim_dir=(-0.6, -0.7)))
    return img


def hanging_moss(seed):
    img = blank()
    r = np.random.default_rng(seed)
    for k in range(18):
        x = r.uniform(1, T - 1)
        ln = r.uniform(6, 22)
        pts = [(x, 0)]
        for i in range(1, 8):
            pts.append((x + np.sin(i * 0.9 + k) * 1.2, ln * i / 7))
        m = mask_from(N, N, lambda d: d.line([(p[0] * S, p[1] * S) for p in pts], fill=255, width=int(r.uniform(0.9, 1.8) * S)))
        yy = np.mgrid[0:N, 0:N][0] / S
        col = ramp([hexc(c) for c in TEAL[1:]], np.clip(yy / 22 + r.uniform(-0.1, 0.2), 0, 1))
        over(img, layer(col, m.astype(float)))
    top = mask_from(N, N, lambda d: d.rectangle([0, 0, N, 2.5 * S], fill=255))
    over(img, layer(hexc(TEAL[2])[:3], top.astype(float)))
    return img


def vine(part, seed):
    """Vines hang from a ceiling: top attaches, mid repeats, end finishes. The stem enters
    and leaves at the tile's center so the pieces stack."""
    img = blank()
    r = np.random.default_rng(seed)
    y_end = T if part != "end" else r.uniform(18, 24)
    pts = []
    for i in range(13):
        y = y_end * i / 12
        x = T / 2 + np.sin(np.pi * y / T) * 2.2 * (1 if part != "end" else 0.6)
        pts.append((x, y))
    stem = mask_from(N, N, lambda d: d.line([(p[0] * S, p[1] * S) for p in pts], fill=255, width=int(1.6 * S)))
    over(img, shade(stem, hexc(GREENS[1]), outline=hexc("#0a1a12"), outline_w=0.5))
    leaves = 4 if part != "top" else 7
    for k in range(leaves):
        y = r.uniform(2, y_end - 2)
        x = T / 2 + np.sin(np.pi * y / T) * 2.2
        side = 1 if k % 2 else -1
        c = (x + side * 3.2, y + 1)
        m = mask_from(N, N, lambda d: d.ellipse([(c[0] - 3.2) * S, (c[1] - 1.6) * S, (c[0] + 3.2) * S, (c[1] + 1.6) * S], fill=255))
        over(img, shade(m, hexc(GREENS[3]), outline=hexc(GREENS[0]), outline_w=0.5))
    if part == "top":
        m = mask_from(N, N, lambda d: d.ellipse([6 * S, -5 * S, 26 * S, 6 * S], fill=255))
        over(img, shade(m, hexc(GREENS[2]), outline=hexc(GREENS[0]), outline_w=0.6))
    if part == "end":
        b = (T / 2, y_end)
        m = mask_from(N, N, lambda d: d.ellipse([(b[0] - 2.5) * S, (b[1] - 1) * S, (b[0] + 2.5) * S, (b[1] + 4) * S], fill=255))
        over(img, glow(m, hexc("#b8f5a0", 0.7), 2.0))
        over(img, shade(m, hexc("#a8e27a")))
    return img


def stalactite(large, seed):
    img = blank()
    r = np.random.default_rng(seed)
    specs = [(T / 2, 28 if large else 15, 9 if large else 6)]
    specs.append((T / 2 + (-8 if r.random() < 0.5 else 8), 11 if large else 8, 4))
    for x, h, w in specs:
        poly = [((x - w) * S, 0), ((x + w) * S, 0), ((x + w * 0.35) * S, h * 0.55 * S), (x * S, h * S), ((x - w * 0.4) * S, h * 0.5 * S)]
        m = mask_from(N, N, lambda d: d.polygon(poly, fill=255))
        over(img, shade(m, hexc(STONE[2]), outline=hexc("#06080d"), outline_w=0.9, rim=hexc("#6fa7b8"), rim_dir=(0.8, 0.2)))
    drip = mask_from(N, N, lambda d: d.ellipse([(T / 2 - 1) * S, (specs[0][1] + 1) * S, (T / 2 + 1) * S, (specs[0][1] + 3.5) * S], fill=255))
    over(img, layer(hexc("#bfe9f0")[:3], drip.astype(float) * 0.9))
    return img


_FOLIAGE_BASE = None


def foliage(seed):
    """Opaque background leaves. A shared periodic base keeps variants seamless; each
    variant only adds clusters away from the edges."""
    global _FOLIAGE_BASE
    if _FOLIAGE_BASE is None:
        base = np.zeros((N, N, 4))
        n = fractal(N, N, 2.2, 404)
        base[..., :3] = ramp([hexc(c) for c in ["#07151a", "#0d2328", "#143238"]], n)
        base[..., 3] = 1
        r = np.random.default_rng(405)
        leaf_cols = [hexc(c) for c in ["#0d2a2f", "#143c40", "#1d4f50", "#2a6660"]]
        for k in range(34):
            c = r.uniform(0, T, 2)
            ang = r.uniform(0, 2 * np.pi)
            ln = r.uniform(7, 12)
            col = leaf_cols[r.integers(0, 4)]
            for ox in (-T, 0, T):
                for oy in (-T, 0, T):
                    cc = c + np.array([ox, oy])
                    m = mask_from(N, N, lambda d: d.polygon(leaf_poly(cc, ang, ln, ln * 0.28), fill=255))
                    if m.any():
                        over(base, shade(m, col, soft=1.6 * S, outline=hexc("#051012"), outline_w=0.45, light=(-0.3, -0.9)))
        _FOLIAGE_BASE = base
    img = _FOLIAGE_BASE.copy()
    r = np.random.default_rng(seed)
    for k in range(3):
        c = r.uniform(11, T - 11, 2)
        ang = r.uniform(0, 2 * np.pi)
        m = mask_from(N, N, lambda d: d.polygon(leaf_poly(c - 3 * np.array([np.cos(ang), np.sin(ang)]), ang, 7, 2.0), fill=255))
        over(img, shade(m, hexc(["#1d4f50", "#2a6660", "#357a70"][k]), soft=1.6 * S, outline=hexc("#051012"), outline_w=0.45, light=(-0.3, -0.9)))
    return img


# (kind, painter) in sheet order, 8 per row.
TILES = [
    ("grass", lambda: grass(1)), ("grass", lambda: grass(2)), ("grass", lambda: grass(3)),
    ("fern", lambda: fern(4)), ("fern", lambda: fern(5)),
    ("flower", lambda: flower(6, "#8fe8ff")), ("flower", lambda: flower(7, "#ffd27a")),
    ("mushroom", lambda: mushroom(8, "#6fe3d0")),
    ("mushroom", lambda: mushroom(9, "#c9a6ff")),
    ("hanging_moss", lambda: hanging_moss(10)), ("hanging_moss", lambda: hanging_moss(11)),
    ("vine_top", lambda: vine("top", 12)), ("vine_mid", lambda: vine("mid", 13)), ("vine_mid", lambda: vine("mid", 14)),
    ("vine_end", lambda: vine("end", 15)), ("stalactite_small", lambda: stalactite(False, 16)),
    ("stalactite_small", lambda: stalactite(False, 17)), ("stalactite_large", lambda: stalactite(True, 18)),
    ("foliage", lambda: foliage(19)), ("foliage", lambda: foliage(20)), ("foliage", lambda: foliage(21)), ("foliage", lambda: foliage(22)),
]


def sheet():
    rows = (len(TILES) + COLS - 1) // COLS
    img = np.zeros((rows * N, COLS * N, 4))
    kinds = []
    for i, (kind, fn) in enumerate(TILES):
        x, y = (i % COLS) * N, (i // COLS) * N
        img[y:y + N, x:x + N] = fn()
        kinds.append({"kind": kind, "coords": [i % COLS, i // COLS]})
    return img, kinds
