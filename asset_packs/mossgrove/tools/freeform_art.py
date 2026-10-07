"""Art for freeform terrain (MDSFreeform) and stamps (MDSStampSet).

- freeform/fill_*.png: 256 x 256 fills that repeat in both directions.
- freeform/edge_*.png: 512 x 64 strips that repeat horizontally. For top strips the top
  row is the outside (moss bulges up out of the shape); for bottom strips the top row is
  the inside (drips and roots hang below the shape).
- freeform/clumps.png: an atlas of 128 x 128 clumps (moss bubbles, leaves, ferns, hanging
  moss, background bubbles, foreground silhouettes), described in pack.json.
"""
import numpy as np
from scipy import ndimage
from paint import S, hexc, lerp, smoothstep, ramp, fractal, fractal1d, voronoi, shade, glow, over, layer, mask_from, down

MOSS = ["#12351f", "#23602d", "#3f9437", "#7cc84a", "#c4f07a"]
TEAL = ["#071a1e", "#0e2f33", "#1a4d4c", "#2f7466", "#5da58b"]


def _wrap_circles(w, h, circles, periodic_x=True, periodic_y=False):
    """Mask of circles (cx, cy, r) in supersampled px, wrapping around the edges."""
    yy, xx = np.mgrid[0:h, 0:w] + 0.5
    m = np.zeros((h, w), bool)
    for cx, cy, r in circles:
        for ox in ((-w, 0, w) if periodic_x else (0,)):
            for oy in ((-h, 0, h) if periodic_y else (0,)):
                x0, x1 = int(max(0, cx + ox - r)), int(min(w, cx + ox + r + 1))
                y0, y1 = int(max(0, cy + oy - r)), int(min(h, cy + oy + r + 1))
                if x0 >= x1 or y0 >= y1:
                    continue
                sub = (xx[y0:y1, x0:x1] - cx - ox) ** 2 + (yy[y0:y1, x0:x1] - cy - oy) ** 2 <= r * r
                m[y0:y1, x0:x1] |= sub
    return m


_GRAIN = {}


def _grain(h, w):
    """Fine speckle (periodic) that makes lit bubbles read as fluffy moss, not glossy balls."""
    if (h, w) not in _GRAIN:
        _GRAIN[(h, w)] = fractal(h, w, 0.5, 99)
    return _GRAIN[(h, w)]


def _bubbles(img, circles, colors, w, h, periodic_x=True, periodic_y=False, outline="#061410", light=(-0.5, -0.8)):
    """Paints bubbles one by one (later ones on top), each lit like a fluffy ball."""
    g = _grain(h, w)
    for cx, cy, r, tone in circles:
        m = _wrap_circles(w, h, [(cx, cy, r)], periodic_x, periodic_y)
        base = ramp([hexc(c) for c in colors], np.array(tone))
        sh = shade(m, np.append(base, 1.0), soft=r * 0.45, outline=hexc(outline), outline_w=0.8, light=light, diffuse=0.55)
        sh[..., :3] *= (0.8 + 0.4 * g)[..., None]
        over(img, sh)


# --- Fills (256 x 256, repeat both ways) -------------------------------------------------------

def fill_rock(seed=1, colors=("#0f141c", "#1b2330", "#2a3444"), stones=10):
    n = 256 * S
    f1, f2, cell = voronoi(n, stones, seed)
    r = np.random.default_rng(seed)
    tone = r.uniform(0.3, 0.8, stones)[cell]
    broad = fractal(n, n, 2.6, seed + 1)
    grain = fractal(n, n, 1.0, seed + 2)
    crev = smoothstep(0, 4 * S, f2 - f1)
    t = np.clip(0.15 + 0.55 * tone * (0.5 + 0.5 * broad) + (grain - 0.5) * 0.15, 0, 1)
    col = ramp([hexc(c) for c in colors], t)
    col = lerp(col * 0.78, col, crev)
    img = np.zeros((n, n, 4))
    img[..., :3] = col
    img[..., 3] = 1
    return img


def fill_shell(seed=2):
    img = fill_rock(seed, ("#6b6572", "#a69c9a", "#d8ccb8"), 7)
    n = img.shape[0]
    yy = np.mgrid[0:n, 0:n][0]
    warp = fractal(n, n, 2.2, seed + 5)
    bands = np.sin(2 * np.pi * (5 * yy / n + 0.6 * warp))
    img[..., :3] = lerp(img[..., :3], hexc("#5a5463")[:3], smoothstep(0.85, 1.0, bands) * 0.6)
    return img


def fill_deep(seed=3):
    img = fill_rock(seed, ("#06080e", "#10151f", "#1c2536"), 12)
    n = img.shape[0]
    spark = fractal(n, n, 0.8, seed + 7) > 0.93
    g = ndimage.gaussian_filter(spark.astype(float), 2 * S, mode="wrap")
    img[..., :3] = lerp(img[..., :3], hexc("#4fd6c8")[:3], np.clip(g * 3, 0, 1) * 0.8)
    img[..., :3] = lerp(img[..., :3], np.ones(3), spark * 0.7)
    return img


def fill_foliage(seed=4):
    """Dense jungle bubbles for backgrounds."""
    n = 256 * S
    img = np.zeros((n, n, 4))
    img[..., :3] = hexc(TEAL[0])[:3]
    img[..., 3] = 1
    r = np.random.default_rng(seed)
    circles = [(r.uniform(0, n), r.uniform(0, n), r.uniform(14, 30) * S, r.uniform(0.25, 0.75)) for _ in range(46)]
    circles.sort(key=lambda c: c[1])
    _bubbles(img, circles, TEAL, n, n, True, True, outline="#04100f")
    return img


def fill_silhouette(seed=5):
    n = 256 * S
    img = np.zeros((n, n, 4))
    t = fractal(n, n, 2.0, seed)
    img[..., :3] = ramp([hexc("#020506"), hexc("#081214")], t * 0.8)
    img[..., 3] = 1
    return img


# --- Edge strips (512 x 64, repeat horizontally) ---------------------------------------------------

W_E, H_E = 512, 64


def edge_moss(seed=6):
    """Moss bulging up out of a top edge, with a dark root line and drips into the rock."""
    w, h = W_E * S, H_E * S
    img = np.zeros((h, w, 4))
    r = np.random.default_rng(seed)
    # Body band under the bubbles, fading into the rock below.
    yy, xx = np.mgrid[0:h, 0:w] + 0.5
    drip = np.maximum(0, fractal1d(w, 0.5, seed + 1, 8)) ** 2
    body_bottom = (40 + 12 * drip) * S
    body = (yy > 26 * S) & (yy < body_bottom[None, :])
    col = ramp([hexc(c) for c in MOSS], np.clip(1.0 - (yy - 26 * S) / (26 * S), 0, 1) * 0.7)
    fade = 1 - smoothstep(body_bottom[None, :] - 6 * S, body_bottom[None, :], yy)
    over(img, layer(col, body * fade))
    circles = []
    x = 0.0
    while x < w:
        rad = r.uniform(7, 15) * S
        circles.append((x, 34 * S - r.uniform(0, 6) * S, rad, r.uniform(0.45, 0.85)))
        x += rad * r.uniform(0.9, 1.4)
    # Some smaller bubbles higher up for a lumpy silhouette.
    for k in range(18):
        circles.append((r.uniform(0, w), r.uniform(18, 26) * S, r.uniform(4, 8) * S, r.uniform(0.7, 1.0)))
    circles.sort(key=lambda c: -c[1])
    _bubbles(img, circles, MOSS, w, h, True, False, outline="#0b2414")
    # Tiny bright tips.
    tips = np.zeros((h, w), bool)
    for k in range(40):
        cx, cy = r.uniform(0, w), r.uniform(14, 24) * S
        tips |= _wrap_circles(w, h, [(cx, cy, 1.4 * S)])
    over(img, layer(hexc(MOSS[4])[:3], tips.astype(float) * 0.9))
    return img


def edge_under(seed=7):
    """Underside of rock: dark rim on top (inside), then roots and moss drips hanging."""
    w, h = W_E * S, H_E * S
    img = np.zeros((h, w, 4))
    yy, xx = np.mgrid[0:h, 0:w] + 0.5
    rim = yy < 18 * S
    over(img, layer(ramp([hexc("#141a24"), hexc("#070a0f")], np.clip(yy / (18 * S), 0, 1)), rim.astype(float)))
    r = np.random.default_rng(seed)
    for k in range(34):
        x0 = r.uniform(0, w)
        ln = r.uniform(10, 40) * S
        wd = r.uniform(1.2, 3.5) * S
        wob = r.uniform(1, 4) * S
        for ox in (-w, 0, w):
            dx = xx - x0 - ox - wob * np.sin(yy / (6 * S) + k)
            width = wd * (1 - np.clip((yy - 14 * S) / ln, 0, 1))
            m = (np.abs(dx) < width) & (yy > 12 * S) & (yy < 14 * S + ln)
            if m.any():
                c = MOSS[1] if k % 3 == 0 else "#10161f"
                over(img, layer(ramp([hexc(c), hexc("#070a0f")], np.clip((yy - 14 * S) / ln, 0, 1)), m.astype(float)))
    drips = np.zeros((h, w), bool)
    for k in range(20):
        drips |= _wrap_circles(w, h, [(r.uniform(0, w), r.uniform(18, 30) * S, r.uniform(1.5, 3) * S)])
    over(img, layer(hexc("#7fd6e0")[:3], drips.astype(float) * 0.6))
    return img


def edge_shell(seed=8):
    w, h = W_E * S, H_E * S
    img = np.zeros((h, w, 4))
    r = np.random.default_rng(seed)
    circles = []
    x = 0.0
    while x < w:
        rad = r.uniform(6, 11) * S
        circles.append((x, 32 * S, rad, r.uniform(0.5, 0.95)))
        x += rad * 1.3
    _bubbles(img, circles, ["#6b6572", "#b3a79a", "#e6dccb", "#fff6e6"], w, h, True, False, outline="#2a2530")
    return img


def edge_crystal(seed=9):
    w, h = W_E * S, H_E * S
    img = np.zeros((h, w, 4))
    yy, xx = np.mgrid[0:h, 0:w] + 0.5
    rim = (yy > 30 * S) & (yy < 44 * S)
    over(img, layer(ramp([hexc("#3e4e6d"), hexc("#10151f")], np.clip((yy - 30 * S) / (14 * S), 0, 1)), rim.astype(float)))
    r = np.random.default_rng(seed)
    for k in range(22):
        x0 = r.uniform(0, w)
        ht = r.uniform(8, 26) * S
        wd = r.uniform(3, 6) * S
        a = r.uniform(-0.4, 0.4)
        base = np.array([x0, 34 * S])
        tip = base + np.array([np.sin(a), -np.cos(a)]) * ht
        for ox in (-w, 0, w):
            b = base + [ox, 0]
            t = tip + [ox, 0]
            m = mask_from(w, h, lambda d: d.polygon([(b[0] - wd, b[1]), tuple(t), (b[0] + wd, b[1])], fill=255))
            if m.any():
                over(img, glow(m, hexc("#3fe6d0", 0.5), 2.5))
                over(img, shade(m, hexc("#58e9d6"), outline=hexc("#0b2f36"), outline_w=0.7, rim=hexc("#eaffff"), rim_dir=(-0.6, -0.6)))
    return img


def edge_foliage(seed=10):
    """Bubbly outline for background foliage shapes."""
    w, h = W_E * S, H_E * S
    img = np.zeros((h, w, 4))
    r = np.random.default_rng(seed)
    circles = []
    x = 0.0
    while x < w:
        rad = r.uniform(10, 20) * S
        circles.append((x, 38 * S - r.uniform(0, 8) * S, rad, r.uniform(0.45, 0.9)))
        x += rad * r.uniform(0.8, 1.2)
    circles.sort(key=lambda c: -c[1])
    _bubbles(img, circles, TEAL, w, h, True, False, outline="#04100f")
    return img


def edge_silhouette(seed=11):
    """Leafy black fringe for foreground silhouettes."""
    w, h = W_E * S, H_E * S
    img = np.zeros((h, w, 4))
    yy, xx = np.mgrid[0:h, 0:w] + 0.5
    base = yy > 38 * S
    over(img, layer(hexc("#03070a")[:3], base.astype(float)))
    r = np.random.default_rng(seed)
    for k in range(46):
        x0 = r.uniform(0, w)
        ln = r.uniform(14, 34) * S
        ang = -np.pi / 2 + r.uniform(-0.9, 0.9)
        wd = ln * r.uniform(0.18, 0.3)
        for ox in (-w, 0, w):
            c = np.array([x0 + ox, 42 * S])
            ax = np.array([np.cos(ang), np.sin(ang)])
            nm = np.array([-ax[1], ax[0]])
            pts = []
            for side in (1, -1):
                for i in (range(0, 11) if side == 1 else range(10, -1, -1)):
                    t = i / 10
                    p = c + ax * t * ln + nm * side * wd * np.sin(np.pi * t) ** 0.8
                    pts.append((p[0], p[1]))
            m = mask_from(w, h, lambda d: d.polygon(pts, fill=255))
            if m.any():
                over(img, layer(ramp([hexc("#03070a"), hexc("#0a1519")], np.full((h, w), r.uniform(0, 1))), m.astype(float)))
    return img


# --- Clumps atlas -----------------------------------------------------------------------------------

CELL = 128


def _cell():
    return np.zeros((CELL * S, CELL * S, 4))


def clump_moss(seed):
    img = _cell()
    n = CELL * S
    r = np.random.default_rng(seed)
    circles = []
    for k in range(r.integers(6, 11)):
        rad = r.uniform(12, 26) * S
        cx = n / 2 + r.uniform(-34, 34) * S
        cy = n - rad - r.uniform(0, 30) * S - abs(cx - n / 2) * 0.3
        circles.append((cx, cy, rad, r.uniform(0.45, 0.95)))
    circles.sort(key=lambda c: -c[1])
    _bubbles(img, circles, MOSS, n, n, False, False, outline="#0b2414")
    tips = np.zeros((n, n), bool)
    for cx, cy, rad, _ in circles:
        for k in range(3):
            a = r.uniform(-2.6, -0.5)
            tips |= _wrap_circles(n, n, [(cx + np.cos(a) * rad * 0.8, cy + np.sin(a) * rad * 0.8, 1.6 * S)], False)
    over(img, layer(hexc(MOSS[4])[:3], tips.astype(float) * 0.9))
    return img


def clump_leaf(seed):
    img = _cell()
    n = CELL * S
    r = np.random.default_rng(seed)
    for k in range(r.integers(7, 12)):
        ang = -np.pi / 2 + r.uniform(-1.2, 1.2)
        ln = r.uniform(30, 60) * S
        wd = ln * r.uniform(0.2, 0.3)
        c = np.array([n / 2 + r.uniform(-10, 10) * S, n - 4 * S])
        ax = np.array([np.cos(ang), np.sin(ang)])
        nm = np.array([-ax[1], ax[0]])
        pts = []
        for side in (1, -1):
            for i in (range(0, 11) if side == 1 else range(10, -1, -1)):
                t = i / 10
                p = c + ax * t * ln + nm * side * wd * np.sin(np.pi * t) ** 0.8
                pts.append((p[0], p[1]))
        m = mask_from(n, n, lambda d: d.polygon(pts, fill=255))
        base = ramp([hexc(c) for c in MOSS], np.array(r.uniform(0.35, 0.8)))
        over(img, shade(m, np.append(base, 1.0), outline=hexc("#0b2414"), outline_w=0.7, soft=wd * 0.4))
        vein = mask_from(n, n, lambda d: d.line([tuple(c), tuple(c + ax * ln * 0.85)], fill=255, width=int(1.0 * S)))
        over(img, layer(hexc(MOSS[1])[:3], vein.astype(float) * 0.8))
    return img


def clump_fern(seed):
    img = _cell()
    n = CELL * S
    r = np.random.default_rng(seed)
    for f in range(4):
        base = np.array([n / 2 + r.uniform(-6, 6) * S, n - 2 * S])
        a = -np.pi / 2 + r.uniform(-1.0, 1.0)
        curl = 0.05 if a < -np.pi / 2 else -0.05
        length = r.uniform(70, 100) * S
        pts = [base.copy()]
        for i in range(20):
            a += curl
            pts.append(pts[-1] + np.array([np.cos(a), np.sin(a)]) * length / 20)
        stem = mask_from(n, n, lambda d: d.line([tuple(p) for p in pts], fill=255, width=int(1.6 * S)))
        over(img, layer(hexc(MOSS[1])[:3], stem.astype(float)))
        for i in range(2, 20, 2):
            q = pts[i]
            ang = np.arctan2(*(pts[i + 1] - pts[i - 1])[::-1])
            size = (1 - i / 20) * 16 * S + 4 * S
            for side in (-1, 1):
                aa = ang + side * 1.1
                ax = np.array([np.cos(aa), np.sin(aa)])
                nm = np.array([-ax[1], ax[0]])
                poly = []
                for sd in (1, -1):
                    for j in (range(0, 9) if sd == 1 else range(8, -1, -1)):
                        t = j / 8
                        p = q + ax * t * size + nm * sd * size * 0.18 * np.sin(np.pi * t)
                        poly.append((p[0], p[1]))
                m = mask_from(n, n, lambda d: d.polygon(poly, fill=255))
                over(img, layer(ramp([hexc(c) for c in MOSS], np.full((n, n), 0.4 + 0.5 * i / 20)), m.astype(float)))
    return img


def clump_hanging(seed):
    img = _cell()
    n = CELL * S
    r = np.random.default_rng(seed)
    yy = np.mgrid[0:n, 0:n][0]
    for k in range(20):
        x = n / 2 + r.uniform(-40, 40) * S
        ln = r.uniform(40, 120) * S
        pts = [(x, 0)]
        for i in range(1, 12):
            pts.append((x + np.sin(i * 0.8 + k) * 4 * S, ln * i / 11))
        m = mask_from(n, n, lambda d: d.line(pts, fill=255, width=int(r.uniform(1.5, 3.0) * S)))
        col = ramp([hexc(c) for c in (MOSS[2], MOSS[3], "#5fb3a4", "#bff0de")], np.clip(yy / ln + r.uniform(-0.2, 0.1), 0, 1))
        over(img, layer(col, m.astype(float)))
    # Small moss knots where the strands attach.
    for d in (-28, -10, 9, 27):
        knot = _wrap_circles(n, n, [(n / 2 + d * S, 5 * S, r.uniform(5, 8) * S)], False)
        over(img, shade(knot, hexc(MOSS[2]), outline=hexc("#0b2414"), outline_w=0.7))
    return img


def clump_bubble_bg(seed):
    img = _cell()
    n = CELL * S
    r = np.random.default_rng(seed)
    circles = []
    for k in range(r.integers(7, 12)):
        rad = r.uniform(14, 30) * S
        circles.append((n / 2 + r.uniform(-30, 30) * S, n / 2 + r.uniform(-24, 30) * S, rad, r.uniform(0.3, 0.8)))
    circles.sort(key=lambda c: -c[1])
    _bubbles(img, circles, TEAL, n, n, False, False, outline="#04100f")
    return img


def clump_silhouette(seed):
    img = _cell()
    n = CELL * S
    r = np.random.default_rng(seed)
    for k in range(r.integers(9, 15)):
        ang = -np.pi / 2 + r.uniform(-1.4, 1.4)
        ln = r.uniform(30, 64) * S
        wd = ln * r.uniform(0.15, 0.28)
        c = np.array([n / 2 + r.uniform(-14, 14) * S, n - 2 * S])
        ax = np.array([np.cos(ang), np.sin(ang)])
        nm = np.array([-ax[1], ax[0]])
        pts = []
        for side in (1, -1):
            for i in (range(0, 11) if side == 1 else range(10, -1, -1)):
                t = i / 10
                p = c + ax * t * ln + nm * side * wd * np.sin(np.pi * t) ** 0.8
                pts.append((p[0], p[1]))
        m = mask_from(n, n, lambda d: d.polygon(pts, fill=255))
        over(img, layer(ramp([hexc("#020506"), hexc("#0b171b")], np.full((n, n), r.uniform(0, 1))), m.astype(float)))
    return img


CLUMPS = (
    [("moss", lambda s=s: clump_moss(s), (0.5, 0.95)) for s in range(6)]
    + [("leaf", lambda s=s: clump_leaf(20 + s), (0.5, 0.97)) for s in range(3)]
    + [("fern", lambda s=s: clump_fern(30 + s), (0.5, 0.98)) for s in range(2)]
    + [("hanging", lambda s=s: clump_hanging(40 + s), (0.5, 0.02)) for s in range(3)]
    + [("bubble_bg", lambda s=s: clump_bubble_bg(50 + s), (0.5, 0.5)) for s in range(4)]
    + [("silhouette", lambda s=s: clump_silhouette(60 + s), (0.5, 0.98)) for s in range(4)]
)

FILLS = {"rock": fill_rock, "shell": fill_shell, "deep": fill_deep, "foliage": fill_foliage, "silhouette": fill_silhouette}
EDGES = {"moss": edge_moss, "under": edge_under, "shell": edge_shell, "crystal": edge_crystal, "foliage": edge_foliage, "silhouette": edge_silhouette}


def clumps_atlas(cols=8):
    rows = (len(CLUMPS) + cols - 1) // cols
    img = np.zeros((rows * CELL * S, cols * CELL * S, 4))
    table = []
    for i, (cat, fn, anchor) in enumerate(CLUMPS):
        x, y = (i % cols) * CELL * S, (i // cols) * CELL * S
        img[y:y + CELL * S, x:x + CELL * S] = fn()
        table.append({"category": cat, "region": [(i % cols) * CELL, (i // cols) * CELL, CELL, CELL], "anchor": list(anchor)})
    return img, table
