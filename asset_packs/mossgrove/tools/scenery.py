"""Props and parallax backgrounds.

Props are single PNGs (bench, lamp, sign, shell pile, breakable wall). The parallax
layers are 1920 x 1080 and repeat horizontally: far (opaque misty cavern with light
shafts), mid (dark pillars, arches and roots) and near (foreground foliage framing the top
and bottom of the screen)."""
import numpy as np
from scipy import ndimage
from paint import S, hexc, lerp, smoothstep, ramp, fractal, fractal1d, shade, glow, over, layer, mask_from
from characters import Frame, INK, RIM

W, H = 1920, 1080


# --- Props --------------------------------------------------------------------------------------

def bench():
    f = Frame(96, 48, (48, 46))
    wood = hexc("#5b4a4a")
    for x in (-34, 30):
        leg = f.poly([(x, 0), (x + 5, 0), (x + 4, -16), (x + 1, -16)])
        f.put(shade(leg, wood, outline=INK, outline_w=0.9))
    seat = f.poly([(-40, -16), (40, -16), (37, -21), (-37, -21)])
    f.put(shade(seat, hexc("#7b6660"), outline=INK, outline_w=1.0, rim=RIM, rim_dir=(0.3, -0.9)))
    back = f.poly([(-36, -24), (36, -24)] + [(36 - 72 * t, -24 - 10 * np.sin(np.pi * t) - 6) for t in np.linspace(0, 1, 20)])
    f.put(shade(back, hexc("#6a5752"), outline=INK, outline_w=1.0))
    for k in range(5):
        x = -24 + k * 12
        hole = f.ellipse(x, -31 - 4 * np.sin(np.pi * (k + 1) / 6), 2.2, 2.8)
        f.put(layer(hexc("#1a1418")[:3], hole.astype(float)))
    return f.img


def lamp():
    f = Frame(64, 96, (24, 94))
    post = f.poly([(-2, 0), (2, 0), (1.3, -70), (-1.3, -70)])
    f.put(shade(post, hexc("#3a3f52"), outline=INK, outline_w=0.8, rim=RIM))
    base = f.poly([(-7, 0), (7, 0), (4, -5), (-4, -5)])
    f.put(shade(base, hexc("#454b60"), outline=INK, outline_w=0.8))
    hook = f.line([(0, -70), (5, -76), (7, -72)], 1.2)
    f.put(layer(INK[:3], hook.astype(float)))
    cage = f.ellipse(7, -64, 5.5, 7.5)
    f.put(glow(cage, hexc("#ffc861", 0.9), 5))
    f.put(shade(cage, hexc("#ffe7a8"), outline=hexc("#5a3a14"), outline_w=0.9))
    for k in (-2, 0, 2):
        bar = f.line([(7 + k * 1.5, -71), (7 + k * 1.8, -57)], 0.6)
        f.put(layer(hexc("#5a3a14")[:3], bar.astype(float)))
    return f.img


def sign():
    f = Frame(48, 64, (24, 62))
    post = f.poly([(-2, 0), (2, 0), (1.5, -44), (-1.5, -44)])
    f.put(shade(post, hexc("#4b3f3f"), outline=INK, outline_w=0.8))
    board = f.poly([(-17, -44), (15, -46), (21, -38), (15, -30), (-17, -30)])
    f.put(shade(board, hexc("#7b6a5c"), outline=INK, outline_w=1.0, rim=RIM))
    for k in range(3):
        line = f.line([(-12, -41 + k * 4), (8 - k * 3, -41 + k * 4)], 1.0)
        f.put(layer(hexc("#3a2e2c")[:3], line.astype(float) * 0.8))
    return f.img


def shell_pile():
    f = Frame(64, 32, (32, 30))
    r = np.random.default_rng(8)
    for k in range(9):
        x = r.uniform(-22, 22)
        y = -r.uniform(4, 9) + abs(x) * 0.08
        sh = f.ellipse(x, y, r.uniform(4, 7), r.uniform(2.5, 4), rot=r.uniform(-0.5, 0.5))
        f.put(shade(sh, hexc(["#e8dcc6", "#cfc1ab", "#b8a893"][k % 3]), outline=INK, outline_w=0.8, rim=RIM))
    return f.img


def breakable_wall():
    f = Frame(64, 96, (32, 96))
    slab = f.poly([(-26, 0), (26, 0), (28, -30), (24, -64), (27, -96), (-27, -96), (-24, -60), (-28, -28)])
    f.put(shade(slab, hexc("#3c4658"), outline=INK, outline_w=1.2, rim=RIM, shadow=hexc("#151a24")))
    r = np.random.default_rng(12)
    pts = [(-6, -90)]
    for k in range(9):
        pts.append((pts[-1][0] + r.uniform(-5, 5), pts[-1][1] + 9.5))
    crack = f.line(pts, 1.4)
    f.put(layer(hexc("#0c0f16")[:3], crack.astype(float)))
    glowc = f.line(pts[3:7], 0.6)
    f.put(glow(glowc, hexc("#7de9ff", 0.7), 2))
    return f.img


PROPS = {"bench": (bench, 96, 48), "lamp": (lamp, 64, 96), "sign": (sign, 48, 64),
         "shell_pile": (shell_pile, 64, 32), "breakable_wall": (breakable_wall, 64, 96)}


# --- Parallax -----------------------------------------------------------------------------------

def _wrap_dx(xx, x0):
    return (xx - x0 + W / 2) % W - W / 2


def far_layer(seed=1):
    yy, xx = np.mgrid[0:H, 0:W].astype(float)
    t = yy / H
    sky = ramp([hexc(c) for c in ["#081119", "#12303a", "#1f4a52", "#16323b", "#0a151c"]], np.clip(t * 1.05, 0, 1))
    mist = fractal(H, W, 3.0, seed)
    sky = lerp(sky, hexc("#3f7d80")[:3], (mist ** 2.2) * 0.25 * np.sin(np.pi * t) ** 0.8)
    img = np.zeros((H, W, 4))
    img[..., :3] = sky
    img[..., 3] = 1
    # Distant ceiling with stalactites and a far floor, lighter from the mist.
    xs = np.arange(W)
    ceil = 150 + 90 * fractal1d(W, 1.8, seed + 1, 2) + 120 * np.maximum(0, fractal1d(W, 0.2, seed + 2, 12)) ** 3
    floor = H - 190 - 70 * fractal1d(W, 1.8, seed + 3, 2)
    sil = (yy < ceil[None, :]) | (yy > floor[None, :])
    # Far spires between floor and ceiling.
    r = np.random.default_rng(seed + 4)
    for k in range(7):
        x0 = r.uniform(0, W)
        w0 = r.uniform(30, 70)
        prof = w0 * (0.6 + 0.4 * np.cos(np.pi * (yy / H - 0.5))) + 10 * fractal(H, 1, 2.0, seed + 10 + k)[:, :1]
        sil |= np.abs(_wrap_dx(xx, x0)) < prof * (0.55 + 0.45 * np.abs(np.sin(yy / 90 + k)))
    silc = lerp(hexc("#0f2530")[:3], hexc("#1b3b45")[:3], np.clip((yy - ceil[None, :]) / 300, 0, 1))
    sm = ndimage.gaussian_filter(sil.astype(float), 3.0)
    img[..., :3] = lerp(img[..., :3], silc, sm * 0.85)
    # Light shafts from openings in the ceiling.
    for k in range(4):
        x0 = r.uniform(0, W)
        slope = 0.35
        d = np.abs(_wrap_dx(xx - yy * slope, x0))
        shaft = np.exp(-(d / r.uniform(30, 70)) ** 2) * (1 - t) ** 1.2 * 0.22
        img[..., :3] = lerp(img[..., :3], hexc("#b7f2e6")[:3], shaft)
    # Drifting spores: points blurred into soft glows (wrapping horizontally).
    pts = np.zeros((H, W))
    for k in range(180):
        pts[r.integers(0, H), r.integers(0, W)] = r.uniform(0.4, 1.0)
    spores = ndimage.gaussian_filter(pts, 2.2, mode="wrap") * 30
    core = ndimage.gaussian_filter(pts, 0.8, mode="wrap") * 6
    img[..., :3] = np.clip(img[..., :3] + hexc("#9fffe6")[:3] * np.clip(spores + core, 0, 1)[..., None] * 0.7, 0, 1)
    return img


def mid_layer(seed=2):
    yy, xx = np.mgrid[0:H, 0:W].astype(float)
    r = np.random.default_rng(seed)
    sil = np.zeros((H, W), bool)
    # Great pillars with organic sides.
    for k in range(4):
        x0 = (k + r.uniform(0.1, 0.9)) * W / 4
        w0 = r.uniform(55, 95)
        wob = 18 * fractal(H, 1, 2.0, seed + k)[:, :1] + 26 * (np.abs(yy / H - 0.5) * 2) ** 3
        sil |= np.abs(_wrap_dx(xx, x0)) < w0 + wob
    # Arches between pillars near the ceiling.
    ceil = 90 + 60 * fractal1d(W, 1.6, seed + 20, 2)
    arch = 250 + 70 * np.abs(np.sin(np.pi * xx / (W / 4) + 0.6))
    sil |= yy < np.minimum(ceil[None, :] + 50, arch)
    floor = H - 110 - 40 * fractal1d(W, 1.6, seed + 21, 2)
    sil |= yy > floor[None, :]
    a = ndimage.gaussian_filter(sil.astype(float), 1.4)
    base = ramp([hexc(c) for c in ["#070f14", "#0e1e26", "#132a33"]], np.clip(fractal(H, W, 2.2, seed + 30) * 0.8, 0, 1))
    # Rim light on the left edges of the pillars (light from the upper left).
    gx = ndimage.sobel(a, 1)
    rim = np.clip(-gx * 2.5, 0, 1)
    base = lerp(base, hexc("#3fa6a0")[:3], rim * 0.55)
    img = np.zeros((H, W, 4))
    img[..., :3] = base
    img[..., 3] = a
    # Hanging roots.
    for k in range(26):
        x0 = r.uniform(0, W)
        ln = r.uniform(120, 420)
        amp = r.uniform(4, 12)
        dx = _wrap_dx(xx, x0) - amp * np.sin(yy / r.uniform(30, 60) + k)
        width = 3.2 * (1 - np.clip(yy / ln, 0, 1)) + 0.6
        m = (np.abs(dx) < width) & (yy < ln)
        img[..., :3] = np.where(m[..., None], hexc("#0b1a20")[:3], img[..., :3])
        img[..., 3] = np.maximum(img[..., 3], m * 1.0)
    return img


def near_layer(seed=3):
    """Foreground foliage framing the screen's top and bottom (blurred like depth of field)."""
    yy, xx = np.mgrid[0:H, 0:W].astype(float)
    r = np.random.default_rng(seed)
    a = np.zeros((H, W))
    bottom = H - 70 - 60 * np.maximum(0, fractal1d(W, 1.4, seed + 1, 2)) - 40 * np.maximum(0, fractal1d(W, 0.6, seed + 2, 6))
    top = 30 + 70 * np.maximum(0, fractal1d(W, 1.4, seed + 3, 2))
    a[(yy > bottom[None, :]) | (yy < top[None, :])] = 1
    # Leaf blades along the edges, drawn in local windows on a canvas padded for wrapping.
    pad = 200
    wide = np.zeros((H, W + 2 * pad))
    wide[:, pad:pad + W] = a
    for k in range(140):
        at_top = k % 3 == 0
        x0 = r.uniform(0, W)
        ln = r.uniform(40, 140)
        ang = (np.pi / 2 if at_top else -np.pi / 2) + r.uniform(-0.7, 0.7)
        y0 = top[int(x0) % W] if at_top else bottom[int(x0) % W]
        wid0 = r.uniform(6, 16)
        x_lo, x_hi = int(x0 + pad - ln - 20), int(x0 + pad + ln + 20)
        y_lo, y_hi = max(0, int(y0 - ln - 20)), min(H, int(y0 + ln + 20))
        sy, sx = np.mgrid[y_lo:y_hi, x_lo:x_hi].astype(float)
        dx, dy = sx - (x0 + pad), sy - y0
        u = dx * np.cos(ang) + dy * np.sin(ang)
        v = -dx * np.sin(ang) + dy * np.cos(ang)
        wid = wid0 * np.sin(np.pi * np.clip(u / ln, 0, 1)) ** 0.8
        m = ((u > 0) & (u < ln) & (np.abs(v) < wid)).astype(float)
        wide[y_lo:y_hi, x_lo:x_hi] = np.maximum(wide[y_lo:y_hi, x_lo:x_hi], m)
    a = wide[:, pad:pad + W].copy()
    a[:, :pad] = np.maximum(a[:, :pad], wide[:, pad + W:])
    a[:, W - pad:] = np.maximum(a[:, W - pad:], wide[:, :pad])
    a = ndimage.gaussian_filter(a, 2.2, mode="wrap")
    img = np.zeros((H, W, 4))
    tone = fractal(H, W, 2.0, seed + 9)
    img[..., :3] = ramp([hexc("#02070a"), hexc("#081419")], tone)
    img[..., 3] = np.clip(a * 1.15, 0, 1)
    return img
