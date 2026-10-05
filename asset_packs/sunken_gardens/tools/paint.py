"""Painting helpers for the Mossgrove asset pack.

Everything is painted at SUPERSAMPLE times the final resolution with float RGBA arrays
and box-filtered down at the end, which gives soft painted gradients with clean
anti-aliased silhouettes. Noise is made periodic (FFT-filtered white noise) so tiles and
parallax layers repeat seamlessly.
"""
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

S = 4  # supersample factor


def hexc(h, a=1.0):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)] + [a])


def lerp(a, b, t):
    t = np.asarray(t)[..., None] if np.ndim(t) else t
    return a + (b - a) * t


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def ramp(colors, t):
    """Color ramp: colors spread evenly over t in 0..1 (rgb only)."""
    t = np.clip(t, 0, 1) * (len(colors) - 1)
    i = np.minimum(t.astype(int), len(colors) - 2)
    f = (t - i)[..., None]
    c = np.array([c[:3] for c in colors])
    return c[i] * (1 - f) + c[i + 1] * f


# --- Noise ---------------------------------------------------------------------------------

def fractal(h, w, beta=2.0, seed=0):
    """Periodic fractal noise in 0..1 (tiles seamlessly in both directions)."""
    r = np.random.default_rng(seed)
    F = np.fft.fft2(r.standard_normal((h, w)))
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    f = np.sqrt(fx ** 2 + fy ** 2)
    f[0, 0] = 1
    F /= f ** (beta / 2)
    F[0, 0] = 0
    out = np.real(np.fft.ifft2(F))
    out -= out.min()
    return out / max(out.max(), 1e-9)


def fractal1d(n, beta=2.0, seed=0, lowcut=1):
    """Periodic 1D noise in -1..1."""
    r = np.random.default_rng(seed)
    F = np.fft.fft(r.standard_normal(n))
    f = np.abs(np.fft.fftfreq(n))
    f[0] = 1
    F /= f ** (beta / 2)
    F[:lowcut] = 0
    F[-lowcut + 1:] = 0 if lowcut > 1 else F[-lowcut + 1:]
    out = np.real(np.fft.ifft(F))
    return out / max(np.abs(out).max(), 1e-9)


def voronoi(n, points, seed=0):
    """Periodic Voronoi on an n x n tile: F1, F2 distances and the nearest cell index."""
    r = np.random.default_rng(seed)
    pts = r.uniform(0, n, (points, 2))
    yy, xx = np.mgrid[0:n, 0:n] + 0.5
    d = np.full((points * 9, n, n), 1e9)
    k = 0
    for oy in (-n, 0, n):
        for ox in (-n, 0, n):
            for p in pts:
                d[k] = np.hypot(xx - p[0] - ox, yy - p[1] - oy)
                k += 1
    order = np.argsort(d, axis=0)
    f1 = np.take_along_axis(d, order[:1], 0)[0]
    f2 = np.take_along_axis(d, order[1:2], 0)[0]
    cell = order[0] % points
    return f1, f2, cell


# --- Canvases and output -----------------------------------------------------------------------

def canvas(w, h):
    return np.zeros((h, w, 4))


def over(dst, src):
    """Alpha-composite src over dst (both straight-alpha float RGBA), in place."""
    sa = src[..., 3:4]
    da = dst[..., 3:4]
    oa = sa + da * (1 - sa)
    rgb = (src[..., :3] * sa + dst[..., :3] * da * (1 - sa)) / np.maximum(oa, 1e-9)
    dst[..., :3] = np.where(oa > 1e-9, rgb, 0)
    dst[..., 3:4] = oa
    return dst


def layer(color_rgb, alpha):
    out = np.zeros(alpha.shape + (4,))
    out[..., :3] = color_rgb if np.ndim(color_rgb) == 3 else np.asarray(color_rgb)[:3]
    out[..., 3] = alpha
    return out


def down(rgba, s=S):
    """Box-filter down by s with premultiplied alpha."""
    h, w, _ = rgba.shape
    a = rgba[..., 3:4]
    pm = np.concatenate([rgba[..., :3] * a, a], -1)
    pm = pm.reshape(h // s, s, w // s, s, 4).mean((1, 3))
    al = pm[..., 3:4]
    pm[..., :3] = np.where(al > 1e-6, pm[..., :3] / np.maximum(al, 1e-6), 0)
    return pm


def save(arr, path):
    Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(path)


# --- Shapes -----------------------------------------------------------------------------------

def mask_from(w, h, draw_fn):
    """Boolean mask drawn with PIL: draw_fn(ImageDraw) paints with fill=255."""
    im = Image.new("L", (w, h), 0)
    draw_fn(ImageDraw.Draw(im))
    return np.asarray(im) > 127


def shade(mask, base, light=(-0.55, -0.8), soft=None, ambient=0.5, diffuse=0.75,
          outline=None, outline_w=1.3, rim=None, rim_w=3.0, rim_dir=(0.8, 0.3), shadow=None):
    """Paints a volume: the mask is lit like a rounded form (normals from its blurred
    silhouette), with an ink outline and an optional back rim light. Sizes in final px."""
    m = mask.astype(float)
    if soft is None:
        soft = max(2.0, 0.18 * np.sqrt(m.sum() / np.pi)) if m.any() else 2.0
    b = ndimage.gaussian_filter(m, soft)
    gy, gx = np.gradient(b)
    k = soft * 2.2
    nx, ny, nz = -gx * k, -gy * k, np.full_like(b, 0.55)
    ln = np.sqrt(nx ** 2 + ny ** 2 + nz ** 2)
    nx, ny, nz = nx / ln, ny / ln, nz / ln
    L = np.array([light[0], light[1], 0.75])
    L /= np.linalg.norm(L)
    lam = np.clip(nx * L[0] + ny * L[1] + nz * L[2], 0, 1)
    base = np.asarray(base)[:3]
    # Painted shading: cool, darker shadows and a warm-ish lifted light side.
    dark = np.asarray(shadow)[:3] if shadow is not None else base * np.array([0.38, 0.42, 0.55])
    light_c = np.minimum(base * 1.22 + 0.05, 1)
    col = ramp([dark, base, light_c], np.clip(lam * (ambient + diffuse) * 0.9, 0, 1))
    d = ndimage.distance_transform_edt(mask)
    if rim is not None:
        facing = np.clip(nx * rim_dir[0] + ny * rim_dir[1], 0, 1)
        t = (1 - smoothstep(0, rim_w * S, d)) * facing
        col = lerp(col, np.asarray(rim)[:3], t * 0.8)
    if outline is not None:
        t = 1 - smoothstep(outline_w * S * 0.6, outline_w * S, d)
        col = lerp(col, np.asarray(outline)[:3], t)
    return layer(col, m)


def glow(mask, color, radius, strength=1.0):
    """Soft glow around a mask (a separate layer to put under the shape)."""
    g = ndimage.gaussian_filter(mask.astype(float), radius * S)
    g = np.clip(g / max(g.max(), 1e-9) * strength, 0, 1)
    return layer(np.asarray(color)[:3], g * np.asarray(color)[3])
