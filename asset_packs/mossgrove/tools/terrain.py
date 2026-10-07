"""Terrain tiles: 4 materials x (16 autotile pieces + 4 fill variants), 32 px.

Pieces are indexed by connected sides (1 right, 2 bottom, 4 left, 8 top), in a 4x4 block
per material, the layout MDS's "Make terrain (4x4)" and starter tileset use. A fifth
column holds fill variants (all sides connected) with details kept away from the edges,
so they swap in seamlessly.
"""
import numpy as np
from scipy import ndimage
from paint import S, hexc, lerp, smoothstep, ramp, fractal, fractal1d, voronoi, shade, glow, over, layer, mask_from

T = 32
N = T * S

MATERIALS = {
    "mossy_stone": {
        "name": "Mossy stone", "stones": 5,
        "ramp": ["#141a24", "#2a3442", "#46566a", "#6d8298"],
        "crevice": "#0b0f15", "outline": "#080b10", "bevel": "#9bb3c6", "rim": "#6fa7b8",
        "moss": ["#153823", "#2b6a33", "#58a83e", "#a6dc62", "#e2f79a"],
    },
    "pale_shell": {
        "name": "Pale shell", "stones": 3, "strata": 3,
        "ramp": ["#5c5663", "#8f8791", "#c9bcab", "#ece2d0"],
        "crevice": "#3b3542", "outline": "#221e2a", "bevel": "#fff7e8", "rim": "#b9c9e0",
    },
    "deep_rock": {
        "name": "Deep rock", "stones": 7,
        "ramp": ["#090c13", "#161c29", "#27324a", "#3e4e6d"],
        "crevice": "#04060a", "outline": "#030409", "bevel": "#7e95bd", "rim": "#4fd6c8",
        "crystal": "#6ff5e2",
    },
    "cave_wall": {
        "name": "Cave wall", "stones": 4, "background": True,
        "ramp": ["#0c151c", "#15232d", "#1f3340", "#2c4555"],
        "crevice": "#081016", "outline": None, "bevel": "#3d5d6e", "rim": "#2f5e66",
    },
}

SIDES = ["right", "bottom", "left", "top"]  # bit 0..3


def _textures(mat, seed):
    """Per-material periodic height and color fields shared by all its tiles."""
    f1, f2, cell = voronoi(N, mat["stones"], seed)
    r = np.random.default_rng(seed + 1)
    cell_v = r.uniform(0.75, 1.1, mat["stones"])[cell]
    broad = fractal(N, N, 2.4, seed + 2)
    grain = fractal(N, N, 1.1, seed + 3)
    crev = smoothstep(0, 2.4 * S, f2 - f1)
    cell_r = np.sqrt(N * N / mat["stones"] / np.pi)
    dome = 1 - np.clip(f1 / cell_r, 0, 1) ** 2
    height = crev * (0.55 + 0.45 * dome) + 0.25 * broad
    if mat.get("strata"):
        yy = np.mgrid[0:N, 0:N][0]
        bands = np.sin(2 * np.pi * (mat["strata"] * yy / N + 0.35 * broad))
        height = 0.6 * height + 0.25 * smoothstep(-0.2, 0.6, bands) + 0.15 * broad
        crev = np.minimum(crev, 0.25 + 0.75 * smoothstep(0.02, 0.18, np.abs(bands)))
    # Light from the upper left on the height field (periodic gradient).
    gx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * N / 18
    gy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * N / 18
    n = np.stack([-gx, -gy, np.ones_like(gx)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    L = np.array([-0.5, -0.7, 0.6])
    L /= np.linalg.norm(L)
    lam = np.clip(n @ L, 0, 1)
    tone = np.clip(0.15 + 0.85 * lam * cell_v + (grain - 0.5) * 0.12, 0, 1)
    col = ramp([hexc(c) for c in mat["ramp"]], tone)
    col = lerp(hexc(mat["crevice"])[:3], col, 0.25 + 0.75 * crev)
    # The rock mass far from any surface: dark and quiet, only broad painterly strokes.
    strokes = fractal(N, N, 2.8, seed + 4)
    mass = ramp([hexc(mat["ramp"][0]), hexc(mat["ramp"][1])], 0.25 + 0.5 * strokes + (grain - 0.5) * 0.1)
    return {"col": col, "grain": grain, "broad": broad, "mass": mass}


def _profiles(seed):
    """Periodic edge contours (inward offsets, in supersampled px) per side."""
    out = {}
    for i, side in enumerate(SIDES):
        p = fractal1d(N, 1.6, seed + 10 + i, lowcut=2)
        out[side] = (0.5 + 0.5 * p) * 3.0 * S + 0.6 * S
    return out


def tile(mat_key, mask, variant=-1, seed=0):
    mat = MATERIALS[mat_key]
    tex = _TEX[mat_key]
    prof = _PROF[mat_key]
    yy, xx = np.mgrid[0:N, 0:N] + 0.5
    xi = np.clip(xx.astype(int), 0, N - 1)
    yi = np.clip(yy.astype(int), 0, N - 1)
    INF = 1e9
    exposed = {s: not (mask & (1 << i)) for i, s in enumerate(SIDES)}
    d = {
        "top": yy - prof["top"][xi] if exposed["top"] else np.full((N, N), INF),
        "bottom": (N - yy) - prof["bottom"][xi] if exposed["bottom"] else np.full((N, N), INF),
        "left": xx - prof["left"][yi] if exposed["left"] else np.full((N, N), INF),
        "right": (N - xx) - prof["right"][yi] if exposed["right"] else np.full((N, N), INF),
    }
    sdf = np.minimum.reduce(list(d.values()))
    r = 7.0 * S
    for a, b in (("top", "left"), ("top", "right"), ("bottom", "left"), ("bottom", "right")):
        if exposed[a] and exposed[b]:
            corner = r - np.hypot(np.maximum(r - d[a], 0), np.maximum(r - d[b], 0))
            sdf = np.minimum(sdf, corner)
    inside = sdf > 0
    col = tex["col"].copy()
    background = mat.get("background", False)
    # Detail lives near surfaces; deeper in, the stones melt into the dark rock mass.
    depth = smoothstep(2 * S, 9 * S, sdf)
    col = lerp(col, tex["mass"], depth * 0.45) * (1 - 0.22 * depth)[..., None]
    nearest = np.argmin(np.stack([d[s] for s in ("top", "bottom", "left", "right")]), 0)
    band = lambda w0, w1: smoothstep(w0 * S, w1 * S, sdf) * (1 - smoothstep(w1 * S, (w1 + 2.5) * S, sdf))
    # Top: sunlit bevel. Sides: cool rim light. Bottom: shadowed underside.
    col = lerp(col, hexc(mat["bevel"])[:3], band(1.0, 2.2) * (nearest == 0) * (0.55 if not background else 0.3))
    col = lerp(col, hexc(mat["rim"])[:3], band(1.0, 1.8) * ((nearest == 2) | (nearest == 3)) * 0.35)
    col = lerp(col, np.array([0.02, 0.03, 0.05]), band(1.0, 3.0) * (nearest == 1) * 0.45)
    if mat.get("crystal"):
        spark = tex["grain"] > 0.9
        sp = ndimage.gaussian_filter(spark.astype(float), 1.2 * S)
        col = lerp(col, hexc(mat["crystal"])[:3], np.clip(sp * 2.2, 0, 1) * inside)
        col = lerp(col, np.array([0.9, 1, 1]), spark * 0.8)
    if variant >= 0:
        col = _detail(mat_key, col, variant, seed)
    alpha = inside.astype(float)
    if background:
        alpha = smoothstep(0, 6 * S, sdf)
    elif mat["outline"]:
        col = lerp(col, hexc(mat["outline"])[:3], 1 - smoothstep(0.6 * S, 1.3 * S, sdf))
    if mat.get("moss") and exposed["top"]:
        col, alpha = _moss(mat, col, alpha, d, exposed, xx, yy, xi, yi)
    out = np.zeros((N, N, 4))
    out[..., :3] = col
    out[..., 3] = alpha
    return out


def _moss(mat, col, alpha, d, exposed, xx, yy, xi, yi):
    """Moss cap on exposed tops, with drips and creeping moss on exposed sides."""
    p = _PROF["moss"]
    thick = (5.0 + 3.0 * p["thick"][xi]) * S
    drips = np.maximum(0, p["drip"][xi]) ** 2 * 11 * S
    # Rounded clumps rising above the rock contour.
    fluff = (0.8 + 2.6 * np.abs(p["fluff"][xi]) ** 0.7) * S
    dt = d["top"]
    moss_depth = thick + drips
    side_moss = np.zeros_like(dt, dtype=bool)
    for s in ("left", "right"):
        if exposed[s]:
            creep = (8 + 5 * p["side"][yi]) * S
            side_moss |= (d[s] < (2.2 + 1.2 * p["fluff"][yi]) * S) & (dt < creep)
    in_moss = ((dt > -fluff) & (dt < moss_depth) | side_moss) & (dt > -fluff)
    # Keep moss within the other sides' silhouettes.
    for s in ("bottom", "left", "right"):
        in_moss &= d[s] > -0.3 * S
    t = np.clip((dt + fluff) / np.maximum(moss_depth + fluff, 1), 0, 1)
    grain = _TEX["mossy_stone"]["grain"]
    moss_col = ramp([hexc(c) for c in reversed(mat["moss"])], np.clip(t * 1.1 + (grain - 0.5) * 0.35, 0, 1))
    edge = in_moss & ~ndimage.binary_erosion(in_moss, iterations=int(0.9 * S))
    moss_col = lerp(moss_col, hexc(mat["moss"][0])[:3], edge * (t > 0.35) * 0.9)
    tips = in_moss & (dt < -fluff + 1.2 * S)
    moss_col = lerp(moss_col, hexc(mat["moss"][4])[:3], tips * 0.8)
    col = np.where(in_moss[..., None], moss_col, col)
    alpha = np.maximum(alpha, in_moss.astype(float))
    return col, alpha


def _detail(mat_key, col, variant, seed):
    """Center details for fill variants (inside a radius that never reaches the edges)."""
    r = np.random.default_rng(seed * 31 + variant)
    c = N / 2 + r.uniform(-3, 3, 2) * S
    img = np.zeros((N, N, 4))
    img[..., :3] = col
    img[..., 3] = 1
    if mat_key == "pale_shell" and variant in (0, 2):
        # Fossil spiral shell.
        m = mask_from(N, N, lambda dr: dr.ellipse([c[0] - 9 * S, c[1] - 7 * S, c[0] + 9 * S, c[1] + 7 * S], fill=255))
        sh = shade(m, hexc("#efe4d2"), outline=hexc("#6c6272"), outline_w=0.9)
        yy, xx = np.mgrid[0:N, 0:N] + 0.5
        ang = np.arctan2(yy - c[1], xx - c[0])
        rad = np.hypot((xx - c[0]) / 9, (yy - c[1]) / 7) / S
        spiral = np.abs(np.sin(ang * 0.5 + rad * 3.2 * np.pi)) < 0.22
        sh[..., :3] = lerp(sh[..., :3], hexc("#8d8190")[:3], (spiral & m) * 0.8)
        over(img, sh)
    elif mat_key == "deep_rock" and variant in (0, 1):
        for k in range(4 + variant):
            a = r.uniform(-1.2, -0.3) if k % 2 else r.uniform(-2.8, -1.9)
            ln = r.uniform(5, 9) * S
            base = c + r.uniform(-4, 4, 2) * S
            tip = base + np.array([np.cos(a), np.sin(a)]) * ln
            nrm = np.array([-np.sin(a), np.cos(a)]) * 1.8 * S
            m = mask_from(N, N, lambda dr: dr.polygon([tuple(base + nrm), tuple(tip), tuple(base - nrm)], fill=255))
            over(img, glow(m, hexc("#3fe6d0", 0.6), 2.5))
            over(img, shade(m, hexc("#58e9d6"), outline=hexc("#0b2f36"), outline_w=0.8, rim=hexc("#eaffff"), rim_dir=(-0.6, -0.6)))
    else:
        # Faint cracks and root lines in the rock mass.
        if variant == 3:
            return img[..., :3]
        if True:
            pts = [c + np.array([-9, -6]) * S]
            for k in range(5):
                pts.append(pts[-1] + np.array([r.uniform(2.5, 4.5), r.uniform(-1.5, 3.0)]) * S)
            m = mask_from(N, N, lambda dr: dr.line([tuple(p) for p in pts], fill=255, width=int(1.1 * S)))
            img[..., :3] = lerp(img[..., :3], hexc(MATERIALS[mat_key]["crevice"])[:3], m * 0.9)
    return img[..., :3]


_TEX = {}
_PROF = {}


def init(seed=11):
    for i, key in enumerate(MATERIALS):
        _TEX[key] = _textures(MATERIALS[key], seed + i * 100)
        _PROF[key] = _profiles(seed + i * 100)
    _PROF["moss"] = {
        "thick": fractal1d(N, 1.8, seed + 900, 2), "drip": fractal1d(N, 0.6, seed + 901, 3),
        "fluff": fractal1d(N, 0.9, seed + 902, 3), "side": fractal1d(N, 1.5, seed + 903, 2),
    }


def sheet():
    """terrain.png: materials side by side, each 5 columns x 4 rows."""
    init()
    keys = list(MATERIALS)
    img = np.zeros((4 * N, len(keys) * 5 * N, 4))
    for mi, key in enumerate(keys):
        for m in range(16):
            x, y = (mi * 5 + m % 4) * N, (m // 4) * N
            img[y:y + N, x:x + N] = tile(key, m)
        for v in range(4):
            x, y = (mi * 5 + 4) * N, v * N
            img[y:y + N, x:x + N] = tile(key, 15, v, seed=mi)
    return img, keys
