"""Characters and effects drawn with a small posable rig.

- player.png: "the Wanderer", an original moth-masked knight (64 x 64 frames).
- crawler.png: a moss-backed crawler (64 x 48 frames), moth.png: a lantern moth (64 x 64).
- vfx.png: needle slash, hit spark and dust (see ANIMS for frames).
Frames face right; flip the sprite for the other direction.
"""
import numpy as np
from scipy import ndimage
from paint import S, hexc, lerp, smoothstep, ramp, shade, glow, over, layer, mask_from

INK = hexc("#0b0b14")


class Frame:
    """A supersampled frame with a local coordinate system: origin at the feet, y down,
    in final pixels, with an optional lean (rotation around the hips)."""

    def __init__(self, w, h, origin, lean=0.0, pivot=(0, -12)):
        self.w, self.h = w, h
        self.img = np.zeros((h * S, w * S, 4))
        self.o = np.array(origin, float)
        self.lean = lean
        self.pivot = np.array(pivot, float)

    def p(self, x, y):
        v = np.array([x, y], float) - self.pivot
        c, s = np.cos(self.lean), np.sin(self.lean)
        v = np.array([v[0] * c - v[1] * s, v[0] * s + v[1] * c]) + self.pivot
        return tuple((self.o + v) * S)

    def mask(self, fn):
        return mask_from(self.w * S, self.h * S, fn)

    def poly(self, pts):
        return self.mask(lambda d: d.polygon([self.p(*q) for q in pts], fill=255))

    def ellipse(self, cx, cy, rx, ry, rot=0.0, n=28):
        pts = []
        for i in range(n):
            a = 2 * np.pi * i / n
            x, y = rx * np.cos(a), ry * np.sin(a)
            pts.append((cx + x * np.cos(rot) - y * np.sin(rot), cy + x * np.sin(rot) + y * np.cos(rot)))
        return self.poly(pts)

    def line(self, pts, width):
        return self.mask(lambda d: d.line([self.p(*q) for q in pts], fill=255, width=max(1, int(width * S)), joint="curve"))

    def tube(self, pts, w0, w1):
        """A tapered stroke along pts (final px widths)."""
        pts = np.array(pts, float)
        left, right = [], []
        for i, q in enumerate(pts):
            a = pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]
            a /= max(np.linalg.norm(a), 1e-6)
            nrm = np.array([-a[1], a[0]])
            w = (w0 + (w1 - w0) * i / (len(pts) - 1)) / 2
            left.append(q + nrm * w)
            right.append(q - nrm * w)
        return self.poly(left + right[::-1])

    def put(self, lay):
        over(self.img, lay)


# --- The Wanderer -------------------------------------------------------------------------------

CLOAK = hexc("#34365f")
CLOAK_DARK = hexc("#15152b")
LINING = hexc("#2a7f86")
MASK = hexc("#ece6d8")
MASK_SHADOW = hexc("#8a8aa6")
SCARF = hexc("#e3a44c")
SCARF_DARK = hexc("#7c3f1f")
LEGS = hexc("#17182a")
NEEDLE = hexc("#d9e6f2")
RIM = hexc("#8fe3dc")


def wanderer(pose):
    f = Frame(64, 64, (30, 60 + pose.get("bob", 0)), pose.get("lean", 0))
    ph = pose.get("phase", 0.0)
    # Scarf behind everything: flows back from the neck.
    droop, amp, length = pose.get("scarf", (1.4, 1.2, 1.0))
    pts = [(-1, -31)]
    for k in range(1, 9):
        pts.append((-1 - k * 2.3 * length, -31 + k * droop + np.sin(ph * 2 + k * 0.9) * amp * k / 8))
    sc = f.tube(pts, 5.2, 2.2)
    f.put(shade(sc, SCARF, outline=INK, outline_w=0.8, shadow=SCARF_DARK))
    # Back leg, cloak, front leg.
    feet = pose.get("feet", ((-3, 0), (3, 0)))
    knees = pose.get("knees", None)
    for i, foot in enumerate(feet):
        hip = (-1.5 + 3 * i, -11)
        knee = knees[i] if knees else ((hip[0] + foot[0]) / 2 + 1.5, (hip[1] + foot[1]) / 2)
        leg = f.line([hip, knee, foot], 2.4)
        tone = LEGS if i == 1 else LEGS * np.array([0.7, 0.7, 0.8, 1])
        f.put(layer(tone[:3], leg.astype(float)))
        toe = f.ellipse(foot[0] + 1.2, foot[1] - 0.6, 2.2, 1.2)
        f.put(layer(tone[:3], toe.astype(float)))
        if i == 0:
            cloak_layers(f, pose)
    # Needle.
    hilt = pose.get("hilt", (6, -17))
    ang = pose.get("blade", 1.25)
    tip = (hilt[0] + np.cos(ang) * 19, hilt[1] + np.sin(ang) * 19)
    guard = f.line([(hilt[0] - np.sin(ang) * 2, hilt[1] + np.cos(ang) * 2), (hilt[0] + np.sin(ang) * 2, hilt[1] - np.cos(ang) * 2)], 1.4)
    bl = f.tube([hilt, tip], 1.8, 0.4)
    f.put(glow(bl, hexc("#bff6ff", 0.35), 1.2))
    f.put(shade(bl, NEEDLE, outline=INK, outline_w=0.5, rim=hexc("#ffffff")))
    f.put(layer(hexc("#b7874a")[:3], guard.astype(float)))
    # Fur collar (a moth's ruff) under the head.
    ruff = f.ellipse(0.5, -32.5, 6.8, 2.8)
    f.put(shade(ruff, hexc("#e9dcc0"), outline=INK, outline_w=0.7, shadow=hexc("#8d7f75")))
    for k in range(5):
        tick = f.line([(-4 + k * 2.2, -33.5), (-4.5 + k * 2.2, -31.5)], 0.5)
        f.put(layer(hexc("#b9a88f")[:3], tick.astype(float) * 0.8))
    # Head: a moth mask with slanted eyes, and feathered plume antennae.
    head = (0.8, -40)
    sway = pose.get("antenna", 0.0)
    for side in (-1, 1):
        base = (head[0] + side * 2.2, head[1] - 6)
        a0 = -np.pi / 2 + side * 0.35 - 0.3 + sway
        pts = [base]
        for k in range(1, 8):
            a = a0 + side * 0.16 * k
            pts.append((pts[-1][0] + np.cos(a) * 1.7, pts[-1][1] + np.sin(a) * 1.7))
        left, right = [], []
        for k, q in enumerate(pts):
            t = k / (len(pts) - 1)
            nx_, ny_ = -np.sin(a0 + side * 0.16 * k), np.cos(a0 + side * 0.16 * k)
            w = 2.3 * np.sin(np.pi * min(1, t * 1.1)) ** 0.7 + 0.25
            left.append((q[0] + nx_ * w, q[1] + ny_ * w))
            right.append((q[0] - nx_ * w * 0.55, q[1] - ny_ * w * 0.55))
        plume = f.poly(left + right[::-1])
        f.put(shade(plume, hexc("#efe3c9"), outline=INK, outline_w=0.55, shadow=hexc("#9d8f86")))
        stalk = f.line(pts, 0.6)
        f.put(layer(hexc("#6b5b52")[:3], stalk.astype(float)))
    face = []
    for i in range(32):
        a = 2 * np.pi * i / 32
        chin = max(0.0, np.sin(a)) ** 3
        face.append((head[0] + 7.6 * np.cos(a) * (1 - 0.35 * chin), head[1] + 6.6 * np.sin(a) * (1 + 0.45 * chin)))
    m = f.poly(face)
    f.put(shade(m, MASK, outline=INK, outline_w=1.1, rim=RIM, rim_dir=(0.8, 0.2), shadow=MASK_SHADOW))
    for side in (-1, 1):
        ec = (head[0] + 1.4 + side * 3.0, head[1] + 0.6)
        eye = f.poly(_almond(ec, side * 0.45, 4.6, 1.35))
        f.put(layer(INK[:3], eye.astype(float)))
        pupil = f.ellipse(ec[0] + 0.5, ec[1] + 0.1, 0.75, 0.6)
        f.put(glow(pupil, hexc("#ffb347", 0.8), 0.8))
        f.put(layer(hexc("#ffd27a")[:3], pupil.astype(float)))
    mark = f.poly(_almond((head[0] + 1.0, head[1] - 4.2), np.pi / 2, 2.6, 0.7))
    f.put(layer(hexc("#b8a7c9")[:3], mark.astype(float) * 0.8))
    if pose.get("flash"):
        a = f.img[..., 3:4]
        f.img[..., :3] = lerp(f.img[..., :3], np.ones(3), pose["flash"])
    return f.img


def _almond(c, angle, length, width):
    ax = np.array([np.cos(angle), np.sin(angle)])
    nm = np.array([-ax[1], ax[0]])
    pts = []
    for side in (1, -1):
        rng = range(0, 11) if side == 1 else range(10, -1, -1)
        for i in rng:
            t = i / 10
            q = np.asarray(c) + ax * (t - 0.5) * length + nm * side * width * np.sin(np.pi * t) ** 0.9
            pts.append((q[0], q[1]))
    return pts


def cloak_layers(f, pose):
    flare = pose.get("flare", 1.0)
    hem_y = pose.get("hem", -7)
    back = pose.get("cloak_back", 0.0)  # hem swept backwards (run, dash)
    ph = pose.get("phase", 0.0)
    hem = []
    for k in range(7):
        t = k / 6
        x = -9.5 - flare - back + t * (19 + flare * 1.6 + back * 0.6)
        y = hem_y + (2.2 if k % 2 else 0) + np.sin(ph * 2 + k) * 0.6 - back * 0.25 * (1 - t) * 3
        hem.append((x, y))
    body = [(-4.5, -33), (4.5, -33), (7, -26)] + hem[::-1] + [(-7.5, -24)]
    # Lining peeks out under the hem.
    lin = f.poly([(-6, -22), (6, -22)] + [(x, y - 1.2) for x, y in hem[::-1]])
    f.put(shade(lin, LINING, outline=INK, outline_w=0.8))
    c = f.poly(body)
    f.put(shade(c, CLOAK, outline=INK, outline_w=1.1, rim=RIM, rim_dir=(0.9, 0.1), shadow=CLOAK_DARK))
    # Shoulder cape with a lighter fold.
    cape = f.poly([(-6, -32), (6, -32), (8.5, -25), (3, -22.5), (-2, -24), (-8, -23.5)])
    f.put(shade(cape, CLOAK * np.array([1.15, 1.15, 1.2, 1]), outline=INK, outline_w=0.9, rim=RIM, rim_dir=(0.9, 0.1), shadow=CLOAK_DARK))
    fold = f.line([(-1, -21), (-2.5 + flare * 0.3, hem_y - 1)], 0.8)
    f.put(layer(CLOAK_DARK[:3], fold.astype(float) * 0.7))
    # A clasp at the collar.
    cl = f.ellipse(3.0, -29.5, 1.3, 1.1)
    f.put(shade(cl, hexc("#e8c070"), outline=INK, outline_w=0.4))


def walk_feet(ph, stride=5.5, lift=3.0):
    a = (np.sin(ph) * stride, -max(0, np.cos(ph)) * lift)
    b = (-np.sin(ph) * stride, -max(0, -np.cos(ph)) * lift)
    return (b, a)


def player_anims():
    anims = {}
    fr = []
    for i in range(6):
        ph = 2 * np.pi * i / 6
        fr.append(wanderer({"phase": ph, "bob": np.sin(ph) * 0.7, "flare": 1 + np.sin(ph) * 0.4,
                            "antenna": np.sin(ph) * 0.08, "scarf": (1.6, 1.0, 0.9)}))
    anims["idle"] = (fr, 8, True)
    fr = []
    for i in range(8):
        ph = 2 * np.pi * i / 8
        fr.append(wanderer({"phase": ph * 1.5, "bob": -abs(np.sin(ph)) * 1.4, "lean": 0.2, "feet": walk_feet(ph),
                            "flare": 2.2, "cloak_back": 3.0, "scarf": (0.4, 1.8, 1.15), "antenna": -0.18, "blade": 1.55, "hilt": (4, -17)}))
    anims["run"] = (fr, 12, True)
    fr = []
    for i in range(3):
        fr.append(wanderer({"phase": i, "lean": -0.05, "feet": ((-3, -5 + i), (3, -6 + i)), "flare": 0.2, "hem": -9,
                            "scarf": (2.4, 0.8, 0.95), "antenna": -0.25, "blade": 1.4}))
    anims["jump"] = (fr, 10, False)
    fr = []
    for i in range(3):
        fr.append(wanderer({"phase": i * 1.3, "lean": 0.02, "feet": ((-3, 1), (3.5, 0)), "flare": 3.4 + i * 0.4, "hem": -10,
                            "scarf": (-1.6, 1.2, 0.95), "antenna": 0.25, "blade": 1.2}))
    anims["fall"] = (fr, 10, True)
    fr = []
    for i in range(4):
        fr.append(wanderer({"phase": i * 2, "lean": 0.5, "bob": 1, "feet": ((-7, -2), (-2, -1)), "flare": 1.0, "cloak_back": 6 + i,
                            "scarf": (0.0, 0.6, 1.4), "antenna": -0.4, "blade": 3.0, "hilt": (-2, -15)}))
    anims["dash"] = (fr, 16, False)
    fr = []
    sweep = [-2.5, -1.7, -0.3, 0.7, 1.15]
    for i, a in enumerate(sweep):
        fr.append(wanderer({"phase": i, "lean": [-0.1, -0.05, 0.18, 0.22, 0.12][i], "feet": ((-4, 0), (5, 0)), "flare": 1.6,
                            "cloak_back": 1.5, "scarf": (0.8, 1.0, 1.0), "blade": a, "hilt": (4 + i * 1.2, -21 + i * 1.5)}))
    anims["attack"] = (fr, 18, False)
    fr = []
    for i in range(2):
        fr.append(wanderer({"phase": i, "lean": -0.35, "bob": -1, "feet": ((-5, -1), (1, -2)), "flare": 2.5, "cloak_back": -2,
                            "scarf": (-0.5, 1.4, 1.0), "antenna": 0.4, "blade": 2.2, "flash": 0.55 if i == 0 else 0.0}))
    anims["hurt"] = (fr, 10, False)
    fr = []
    for i in range(2):
        fr.append(wanderer({"phase": i * 1.5, "lean": 0.0, "feet": ((1, -4), (4, 0)), "flare": 2.2, "hem": -9,
                            "scarf": (-1.0, 0.8, 0.9), "antenna": 0.15, "blade": 1.7, "hilt": (2, -16)}))
    anims["wall_slide"] = (fr, 6, True)
    return anims


# --- Enemies ----------------------------------------------------------------------------------

def crawler(i):
    f = Frame(64, 48, (32, 44))
    ph = 2 * np.pi * i / 4
    for k, off in enumerate((-9, -1, 7)):
        swing = np.sin(ph + k * 2.1) * 3
        lift = max(0, np.cos(ph + k * 2.1)) * 2
        leg = f.line([(off, -8), (off + swing + 3, -5 - lift), (off + swing + 4.5, -lift * 0.6)], 1.9)
        f.put(layer(hexc("#1a1c24")[:3], leg.astype(float)))
    head = f.ellipse(16, -9, 5.5, 4.8)
    f.put(shade(head, hexc("#d9d2c2"), outline=INK, outline_w=0.9, shadow=hexc("#7f7a8e")))
    eye = f.ellipse(18, -9.5, 1.3, 1.9)
    f.put(layer(INK[:3], eye.astype(float)))
    bob = np.sin(ph * 2) * 0.6
    shell = f.poly([(-17, -7 + bob)] + [(-17 + 34 * t, -7 + bob - np.sin(np.pi * t) ** 0.8 * 18) for t in np.linspace(0, 1, 16)] + [(17, -7 + bob)])
    f.put(shade(shell, hexc("#4a5566"), outline=INK, outline_w=1.1, rim=RIM, rim_dir=(0.8, 0.2), shadow=hexc("#1c212c")))
    for k in range(3):
        x = -9 + k * 9
        plate = f.line([(x, -6 + bob), (x + 1.5, -19 + bob + abs(k - 1) * 4)], 0.9)
        f.put(layer(hexc("#232a36")[:3], plate.astype(float)))
    moss = f.poly([(-12, -15 + bob)] + [(-12 + 22 * t, -15 + bob - np.sin(np.pi * t) * 8 - (np.sin(t * 40) > 0) * 1.2) for t in np.linspace(0, 1, 24)] + [(10, -16 + bob)])
    f.put(shade(moss, hexc("#5aa845"), outline=hexc("#153823"), outline_w=0.7, shadow=hexc("#1f4d2b")))
    return f.img


def moth(i):
    f = Frame(64, 64, (32, 36))
    ph = 2 * np.pi * i / 4
    flap = np.cos(ph)
    for side in (-1, 1):
        for k, (ln, wd, base) in enumerate(((17, 8, -0.35), (12, 6, 0.55))):
            a = -np.pi / 2 + side * (np.pi / 2 + base) - side * flap * 0.55
            c = (side * 3 + np.cos(a) * ln * 0.55, np.sin(a) * ln * 0.55)
            w = f.ellipse(c[0], c[1], ln * 0.6, wd * (0.55 + 0.45 * abs(flap) if k == 0 else 1), rot=a)
            wl = shade(w, hexc("#c9b8e8" if k == 0 else "#a893d0"), outline=INK, outline_w=0.8, rim=hexc("#fff3c0"))
            wl[..., 3] *= 0.9
            f.put(wl)
    body = f.ellipse(0, 0, 4.5, 7.5)
    f.put(glow(body, hexc("#ffcf6a", 0.9), 6))
    f.put(shade(body, hexc("#ffd98a"), outline=hexc("#5a3a14"), outline_w=0.8, rim=hexc("#ffffff")))
    head = f.ellipse(0, -9, 3.8, 3.4)
    f.put(shade(head, hexc("#e9e2d2"), outline=INK, outline_w=0.8))
    for side in (-1, 1):
        e = f.ellipse(side * 1.5, -9, 0.9, 1.4)
        f.put(layer(INK[:3], e.astype(float)))
        ant = f.line([(side * 1.5, -12), (side * 4, -17), (side * 6, -18)], 0.8)
        f.put(layer(INK[:3], ant.astype(float)))
    return f.img


# --- Effects ------------------------------------------------------------------------------------

def slash(i, n=5):
    f = Frame(96, 64, (40, 34))
    yy, xx = np.mgrid[0:64 * S, 0:96 * S] / S
    cx, cy = 40, 34
    u, v = (xx - cx) / 38, (yy - cy) / 25
    outer = u * u + v * v <= 1
    u2, v2 = (xx - cx + 9) / 34, (yy - cy + 3) / 20
    inner = u2 * u2 + v2 * v2 <= 1
    crescent = outer & ~inner & (xx > cx - 6)
    ang = np.arctan2(yy - cy, xx - cx)
    reveal = -1.9 + 3.6 * min(1.0, (i + 1) / 3)
    fade = 1.0 if i < 3 else (1 - (i - 2) / (n - 1)) ** 1.3
    m = crescent & (ang < reveal)
    t = np.clip((ang + 1.9) / 3.6, 0, 1)
    edge = np.clip((u * u + v * v - 0.62) / 0.38, 0, 1)
    col = lerp(hexc("#7fe9ff")[:3], np.ones(3), edge ** 0.6)
    alpha = m * (0.55 + 0.45 * edge) * (0.45 + 0.55 * t) * fade
    halo = layer(hexc("#7fe9ff")[:3], np.clip(ndimage.gaussian_filter(alpha, 2.5 * S) * 1.4, 0, 1) * 0.6)
    f.put(halo)
    f.put(layer(col, alpha))
    return f.img


def spark(i):
    f = Frame(64, 64, (32, 32))
    size = [8, 15, 20, 23][i]
    alpha = [1, 1, 0.7, 0.35][i]
    r = np.random.default_rng(3)
    for k in range(8):
        a = k * np.pi / 4 + r.uniform(-0.2, 0.2)
        ln = size * (1 if k % 2 == 0 else 0.6)
        ray = f.tube([(np.cos(a) * size * 0.2, np.sin(a) * size * 0.2), (np.cos(a) * ln, np.sin(a) * ln)], 2.6 - i * 0.4, 0.2)
        f.put(glow(ray, hexc("#9ff7ff", 0.8 * alpha), 2))
        f.put(layer(np.ones(3), ray * alpha))
    core = f.ellipse(0, 0, 6 - i * 1.2, 6 - i * 1.2)
    f.put(layer(np.ones(3), core * alpha))
    return f.img


def dust(i):
    f = Frame(48, 32, (24, 28))
    r = np.random.default_rng(5)
    for k in range(5):
        d = r.uniform(-1, 1)
        x = d * (4 + i * 4)
        y = -2 - i * 1.5 - abs(d) * 2
        rad = 3 + i * 1.3 + r.uniform(0, 1.5)
        c = f.ellipse(x, y, rad, rad * 0.8)
        l = shade(c, hexc("#9fb2bf"), shadow=hexc("#4a5a68"))
        l[..., 3] *= max(0, 0.85 - i * 0.18)
        f.put(l)
    return f.img


def strip_sheet(frames_by_anim, w, h, cols=8):
    """Rows per animation (wrapping after cols). Returns image and frame table."""
    rows = sum((len(fr) + cols - 1) // cols for fr, _, _ in frames_by_anim.values())
    img = np.zeros((rows * h * S, cols * w * S, 4))
    table = {}
    row = 0
    for name, (frames, fps, loop) in frames_by_anim.items():
        cells = []
        for k, fr in enumerate(frames):
            cx, cy = k % cols, row + k // cols
            img[cy * h * S:(cy + 1) * h * S, cx * w * S:(cx + 1) * w * S] = fr
            cells.append([cx * w, cy * h, w, h])
        row += (len(frames) + cols - 1) // cols
        table[name] = {"fps": fps, "loop": loop, "frames": cells}
    return img, table
