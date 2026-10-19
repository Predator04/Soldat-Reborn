#!/usr/bin/env python3
"""Paint the "Operator" soldier sprite set (#280 / #281) into assets/gostek-hd/.

The classic gostek is a chibi: a 9 px head and limbs as thick as they are long.
This set keeps the SAME skeleton (.poa joints), animations, weapon anchors and
hit boxes, but every body part gets its own modern-proportioned sprite: a
smaller head, slim tapered limbs, a real torso with shoulders, proper boots and
hands. Each part is designed in game pixels ("units") around its bone and
painted at 18 px per unit (6x the classic sprites' 3 px per unit), so it holds
up on big screens and in the kill cam.

Layers per part, drawn in order with one transform by scripts/gostek.gd:
  <part>.png         base — tinted like the classic part (team colour,
                     trousers, skin, helmet / vest paint); parts listed in
                     gostek.gd HD_UNTINTED (gloves, hair) are real colours
  <part>_trim.png    gear in real colours (plate carrier, belt, pads, headset)
  <part>_acc.png     accents tinted with the bright team colour (visor slit,
                     shoulder stripe, chest patch, IR strobe, jetpack light)
  <part>_wound.png   blood, faded in below 60 HP
  <name>_n.png       normal map of each of those (OpenGL convention, green =
                     up) for the dynamic lighting pass (#282)
  <name>2.png        mirrors (vertical flips; normal maps get green flipped)
plus rig.json: each part's pivot (cx, cy) in its rect; the rect size is the
texture size / px_per_unit (18). Shapes are vectors on a supersampled canvas, extruded into a
height field (bevels, seams, folds), lit, given ambient occlusion and a thin
outline, then downsampled. Deterministic: re-running gives the same bytes.

  python3 tools/gen_operator_gfx.py              # write assets/gostek-hd/
  python3 tools/gen_operator_gfx.py klata helm   # just those parts
  python3 tools/gen_operator_gfx.py --sheet F    # also save a contact sheet

Design frames (all upright, facing right, y down, origin = the bone's first joint):
  "id"   torso / hips / boot / jetpack: x along the bone, y down the bone's normal
  "limb" arms and legs hanging down: x = front, y = down the limb
  "head" head pieces: x = front, y = down (the neck joint is the origin)
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "gostek-hd")
PX = 18         # output pixels per game pixel (unit) — "ultra HD" (#281)
SS = 3          # supersampling
K = PX * SS     # canvas pixels per unit
LIGHT = np.array([0.5, -0.7, 0.52])
LIGHT = LIGHT / np.linalg.norm(LIGHT)

# Real-colour materials (sRGB 0..1)
CARRIER = (0.19, 0.2, 0.19)
POUCH = (0.24, 0.245, 0.23)
WEB = (0.12, 0.125, 0.12)
METAL = (0.52, 0.54, 0.57)
COYOTE = (0.36, 0.3, 0.22)
COYOTE_D = (0.25, 0.21, 0.155)
GLOVE = (0.17, 0.165, 0.16)
GLOVE_D = (0.1, 0.1, 0.1)
RUBBER = (0.07, 0.07, 0.075)
PAD = (0.14, 0.145, 0.15)
HEADSET = (0.11, 0.115, 0.12)
LENS = (0.04, 0.05, 0.06)
HAIR = (0.15, 0.105, 0.075)
SILVER = (0.72, 0.74, 0.78)
GOLD = (0.95, 0.74, 0.3)
BLOOD = (0.42, 0.02, 0.03)
GREY = lambda v: (v, v, v)


def smooth(m, r):
    """Round a mask's corners by r units."""
    if r <= 0:
        return m
    b = ndimage.gaussian_filter(m, r * K * 0.6)
    return np.clip((b - 0.5) * 4.0 + 0.5, 0, 1)


class Layer:
    """One sprite layer. Coordinates are units in the part's design frame;
    (x0, y0) is the top-left of the canvas."""

    def __init__(self, x0, x1, y0, y1):
        self.x0, self.y0 = x0, y0
        self.W, self.H = x1 - x0, y1 - y0
        self.w, self.h = int(round(self.W * K)), int(round(self.H * K))
        self.alb = np.zeros((self.h, self.w, 3), np.float32)
        self.a = np.zeros((self.h, self.w), np.float32)
        self.z = np.zeros((self.h, self.w), np.float32)
        self.spec = np.zeros((self.h, self.w), np.float32)
        self.emit = np.zeros((self.h, self.w), np.float32)

    def like(self):
        return Layer(self.x0, self.x0 + self.W, self.y0, self.y0 + self.H)

    def _p(self, x, y):
        return ((x - self.x0) * K, (y - self.y0) * K)

    def _img(self):
        return Image.new("L", (self.w, self.h), 0)

    def _m(self, im):
        return np.asarray(im, np.float32) / 255.0

    # ── masks ──
    def poly(self, pts, r=0.0):
        im = self._img()
        ImageDraw.Draw(im).polygon([self._p(x, y) for x, y in pts], fill=255)
        return smooth(self._m(im), r)

    def ell(self, cx, cy, rx, ry):
        im = self._img()
        a = self._p(cx - rx, cy - ry)
        b = self._p(cx + rx, cy + ry)
        ImageDraw.Draw(im).ellipse([a[0], a[1], b[0], b[1]], fill=255)
        return self._m(im)

    def rrect(self, x0, y0, x1, y1, r):
        im = self._img()
        a = self._p(x0, y0)
        b = self._p(x1, y1)
        ImageDraw.Draw(im).rounded_rectangle([a[0], a[1], b[0], b[1]], radius=max(0, r * K), fill=255)
        return self._m(im)

    def line(self, pts, width):
        im = self._img()
        d = ImageDraw.Draw(im)
        q = [self._p(x, y) for x, y in pts]
        d.line(q, fill=255, width=max(1, int(width * K)), joint="curve")
        r = width * K * 0.5
        for x, y in (q[0], q[-1]):
            d.ellipse([x - r, y - r, x + r, y + r], fill=255)
        return self._m(im)

    def band(self, y0, y1):
        m = np.zeros((self.h, self.w), np.float32)
        a = int(np.clip((y0 - self.y0) * K, 0, self.h))
        b = int(np.clip((y1 - self.y0) * K, 0, self.h))
        m[a:b, :] = 1.0
        return m

    def vband(self, x0, x1):
        m = np.zeros((self.h, self.w), np.float32)
        a = int(np.clip((x0 - self.x0) * K, 0, self.w))
        b = int(np.clip((x1 - self.x0) * K, 0, self.w))
        m[:, a:b] = 1.0
        return m

    def erode(self, m, u):
        return ndimage.grey_erosion(m, size=max(1, int(u * K * 2))) * (m > 0)

    def dilate(self, m, u):
        return ndimage.grey_dilation(m, size=max(1, int(u * K * 2)))

    # ── paint ──
    def fill(self, m, col, z=0.0, height=1.0, bevel=0.3, spec=0.0, emit=0.0, stack=False):
        m = np.clip(m, 0, 1)
        if m.max() <= 0:
            return
        d = ndimage.distance_transform_edt(m > 0.5) / K
        prof = np.clip(d / max(bevel, 0.005), 0, 1)
        prof = np.sqrt(1 - (1 - prof) ** 2)          # rounded (quarter-circle) edge
        base = self.z if stack else z
        zz = base + prof * height
        c = np.array(col, np.float32).reshape(1, 1, 3)
        mm = m[..., None]
        self.alb = self.alb * (1 - mm) + c * mm
        self.z = self.z * (1 - m) + zz * m
        self.spec = self.spec * (1 - m) + spec * m
        self.emit = self.emit * (1 - m) + emit * m
        self.a = np.maximum(self.a, m)

    def carve(self, m, depth=0.15, dark=0.75, soft=0.06):
        m = ndimage.gaussian_filter(np.clip(m, 0, 1), soft * K) * (self.a > 0.01)
        self.z -= m * depth
        self.alb *= (1 - m * (1 - dark))[..., None]

    def bump(self, m, amount=0.15, soft=0.15):
        m = ndimage.gaussian_filter(np.clip(m, 0, 1), soft * K) * (self.a > 0.01)
        self.z += m * amount

    def tone(self, m, mul):
        m = np.clip(m, 0, 1)[..., None] * (self.a > 0.01)[..., None]
        self.alb = self.alb * (1 - m) + self.alb * mul * m

    def paint(self, m, col, amount=1.0):
        m = (np.clip(m, 0, 1) * amount)[..., None] * (self.a > 0.01)[..., None]
        self.alb = self.alb * (1 - m) + np.array(col, np.float32).reshape(1, 1, 3) * m

    def noise(self, amount=0.04, scale=0.08, zamount=0.02, seed=1):
        rng = np.random.default_rng(seed)
        n = ndimage.gaussian_filter(rng.standard_normal((self.h, self.w)).astype(np.float32), scale * K)
        n /= max(1e-6, n.std())
        self.alb *= (1 + n * amount)[..., None]
        self.z += n * zamount

    def camo(self, amount=0.08, seed=7, scale=0.7):
        rng = np.random.default_rng(seed)
        out = np.zeros((self.h, self.w), np.float32)
        for lvl, s in ((1.0, scale), (-1.0, scale * 0.7)):
            n = ndimage.gaussian_filter(rng.standard_normal((self.h, self.w)).astype(np.float32), s * K)
            n /= max(1e-6, n.std())
            out += lvl * np.clip((n - 0.55) * 3.0, 0, 1)
        out = ndimage.gaussian_filter(out, 0.05 * K)
        self.alb *= (1 + out * amount)[..., None]

    # ── fine detail (reads at 18 px / unit) ──
    def _grid(self):
        yy, xx = np.mgrid[0:self.h, 0:self.w].astype(np.float32)
        return xx / K, yy / K

    def weave(self, m, amount=0.06, period=0.1, zamt=0.006):
        """Twill fabric texture."""
        x, y = self._grid()
        pat = np.sin((x + y) * math.tau / period) * 0.6 + np.sin((x - y * 0.4) * math.tau / (period * 2.3)) * 0.4
        mm = np.clip(m, 0, 1) * (self.a > 0.01)
        self.alb *= (1 + pat * amount * mm)[..., None]
        self.z += pat * zamt * mm

    def webbing(self, m, amount=0.08, period=0.07):
        """Nylon webbing: fine stripes along x."""
        x, y = self._grid()
        pat = np.sin(y * math.tau / period)
        mm = np.clip(m, 0, 1) * (self.a > 0.01)
        self.alb *= (1 + pat * amount * mm)[..., None]
        self.z += pat * 0.004 * mm

    def stitch(self, pts, dash=0.11, gap=0.07, width=0.035, light=1.3, depth=0.03):
        """A dashed seam along a polyline: a groove with lighter thread dashes."""
        groove = self.line(pts, width * 1.6)
        self.carve(groove, depth, 0.8, 0.01)
        im = self._img()
        d = ImageDraw.Draw(im)
        acc = 0.0
        for (xa, ya), (xb, yb) in zip(pts[:-1], pts[1:]):
            L = math.hypot(xb - xa, yb - ya)
            t = 0.0
            while t < L:
                if (acc % (dash + gap)) < dash:
                    e = min(L, t + min(dash - (acc % (dash + gap)), L - t))
                    p0 = self._p(xa + (xb - xa) * t / L, ya + (yb - ya) * t / L)
                    p1 = self._p(xa + (xb - xa) * e / L, ya + (yb - ya) * e / L)
                    d.line([p0, p1], fill=255, width=max(1, int(width * K)))
                    acc += e - t
                    t = e
                else:
                    step = min(gap - ((acc % (dash + gap)) - dash), L - t)
                    acc += step
                    t += step
        th = self._m(im) * (self.a > 0.01)
        self.alb = self.alb * (1 - th[..., None]) + self.alb * light * th[..., None]
        self.z += th * depth * 0.6

    def scratches(self, m, n=24, seed=1, length=(0.15, 0.6), width=0.02, bright=1.45):
        rng = np.random.default_rng(seed)
        ys, xs = np.nonzero(m > 0.5)
        if len(xs) == 0:
            return
        im = self._img()
        d = ImageDraw.Draw(im)
        for i in range(n):
            j = rng.integers(len(xs))
            x, y = xs[j] / K + self.x0, ys[j] / K + self.y0
            a = rng.uniform(0, math.tau)
            l = rng.uniform(*length)
            pts = [self._p(x, y), self._p(x + math.cos(a) * l, y + math.sin(a) * l)]
            d.line(pts, fill=int(rng.uniform(120, 255)), width=max(1, int(width * K)))
        sc = self._m(im) * np.clip(m, 0, 1)
        self.alb *= (1 + sc * (bright - 1))[..., None]

    def edgewear(self, m, width=0.07, amount=1.35):
        """Lighter, worn edges on hard gear."""
        mm = np.clip(m, 0, 1)
        d = ndimage.distance_transform_edt(mm > 0.5) / K
        band = np.clip(1 - d / width, 0, 1) * (mm > 0.5)
        rng = np.random.default_rng(int(mm.sum()) % 9973)
        n = ndimage.gaussian_filter(rng.standard_normal(mm.shape).astype(np.float32), 0.03 * K)
        band *= np.clip(0.5 + n * 2.0, 0, 1)
        self.alb *= (1 + band * (amount - 1))[..., None]

    def molle(self, m, y0, y1, rows, loop=0.42):
        """Rows of MOLLE webbing loops (bands with bar-tack slits)."""
        x, y = self._grid()
        h = (y1 - y0) / rows
        for r in range(rows):
            band = self.band(y0 + r * h + h * 0.18, y0 + r * h + h * 0.82) * np.clip(m, 0, 1)
            self.webbing(band, 0.1)
            self.bump(band, 0.05, 0.01)
            slit = ((np.mod(x - self.x0, loop) < 0.035).astype(np.float32)) * band
            self.carve(slit, 0.05, 0.55, 0.005)

    def velcro(self, m, amount=0.14, seed=5):
        rng = np.random.default_rng(seed)
        n = ndimage.gaussian_filter(rng.standard_normal((self.h, self.w)).astype(np.float32), 0.012 * K)
        n /= max(1e-6, n.std())
        mm = np.clip(m, 0, 1) * (self.a > 0.01)
        self.alb *= (1 + n * amount * mm)[..., None]
        self.z += n * 0.006 * mm

    def rivet(self, x, y, r=0.06, col=METAL, z=None):
        self.fill(self.ell(x, y, r, r), col, z=(self.z.max() if z is None else z), height=r * 0.8, bevel=r, spec=0.9)

    def shadow_from(self, other, dx=-0.15, dy=0.22, strength=0.45, blur=0.18):
        sh = ndimage.shift(other.a, (dy * K, dx * K), order=1)
        sh = ndimage.gaussian_filter(sh, blur * K)
        self.alb *= (1 - strength * sh * (1 - other.a))[..., None]

    def render(self, light=LIGHT, ambient=0.48, diffuse=0.66, outline=0.6, ao=0.6):
        """-> (RGBA image, normals HxWx3 float in design image space (x right, y down))"""
        if self.a.max() <= 0:
            return None, None
        zs = ndimage.gaussian_filter(self.z, 0.06 * K)
        gy, gx = np.gradient(zs)
        n = np.dstack([-gx * K * 0.9, -gy * K * 0.9, np.ones_like(zs)])
        n /= np.linalg.norm(n, axis=2, keepdims=True)
        lam = np.clip((n * light).sum(axis=2), 0, 1)
        hv = light + np.array([0, 0, 1.0])
        hv /= np.linalg.norm(hv)
        sp = np.clip((n * hv).sum(axis=2), 0, 1) ** 26 * self.spec * 0.85
        occ = np.clip((ndimage.gaussian_filter(self.z, 0.5 * K) - self.z) * 1.6, 0, 1) * ao
        shade = (ambient + diffuse * lam) * (1 - occ)
        rgb = self.alb * shade[..., None] + sp[..., None]
        rgb = rgb * (1 - self.emit[..., None]) + self.alb * self.emit[..., None]
        inner = ndimage.grey_erosion(self.a, size=max(1, int(0.24 * K)))
        edge = np.clip(self.a - inner, 0, 1)
        rgb *= (1 - outline * edge)[..., None]
        a = self.a[..., None]
        ow, oh = self.w // SS, self.h // SS

        def down(arr):
            im = Image.fromarray(arr.astype(np.float32), "F") if arr.ndim == 2 else None
            return np.asarray(im.resize((ow, oh), Image.BOX), np.float32)

        pr = [down(np.clip(rgb[..., i], 0, 1) * self.a) for i in range(3)]
        al = down(self.a)
        rgb_o = np.dstack([np.where(al > 1e-4, c / np.maximum(al, 1e-4), 0) for c in pr])
        rgba = np.dstack([np.clip(rgb_o, 0, 1), np.clip(al, 0, 1)])
        img = Image.fromarray((rgba * 255).round().astype(np.uint8), "RGBA")
        nn = np.dstack([down(n[..., i] * self.a) for i in range(3)])
        nn = np.where(al[..., None] > 1e-4, nn / np.maximum(al[..., None], 1e-4), np.array([0, 0, 1.0]))
        nn /= np.maximum(np.linalg.norm(nn, axis=2, keepdims=True), 1e-6)
        return img, nn


# ───────────────────────────── part designs ─────────────────────────────
# Each returns {suffix: Layer}. Bounds are given in BOUNDS below.


def fabric(L, m, seed, shade=0.84, bevel=0.55, height=0.6):
    L.fill(m, GREY(shade), height=height, bevel=bevel)
    L.noise(0.02, 0.05, 0.01, seed=seed)
    L.camo(seed=seed + 500)
    L.weave(m)


def wound_layer(base, seed, n=5):
    w = base.like()
    rng = np.random.default_rng(seed)
    m = np.zeros((w.h, w.w), np.float32)
    ys, xs = np.nonzero(base.erode(base.a, 0.2) > 0.5)
    if len(xs) == 0:
        return w
    for i in range(n):
        j = rng.integers(len(xs))
        cx, cy = xs[j] / K + w.x0, ys[j] / K + w.y0
        r = rng.uniform(0.18, 0.45)
        m = np.maximum(m, w.ell(cx, cy, r * rng.uniform(0.8, 1.4), r))
        for k in range(3):   # splatter drops
            a = rng.uniform(0, math.tau)
            dd = r * rng.uniform(1.2, 2.2)
            m = np.maximum(m, w.ell(cx + math.cos(a) * dd, cy + math.sin(a) * dd, r * 0.22, r * 0.22))
    m = smooth(m, 0.05) * base.a
    w.fill(m, BLOOD, height=0.12, bevel=0.1, spec=0.9)
    w.paint(ndimage.gaussian_filter(m, 0.06 * K) * 0.0 + base.erode(m, 0.06), (0.3, 0.0, 0.01), 0.7)
    return w


def d_klata():
    b = Layer(*BOUNDS["klata"])
    torso = b.poly([(-0.45, -0.3), (-0.62, 1.3), (-0.48, 3.8), (-0.12, 6.1), (2.4, 6.45), (4.8, 6.25), (5.25, 4.9),
                    (5.72, 2.9), (5.82, 1.3), (5.5, 0.15), (4.8, -0.52), (3.85, -0.95), (3.25, -1.3), (2.05, -1.3),
                    (0.8, -0.98), (0.0, -0.72)], r=0.25)
    fabric(b, torso, 11, bevel=1.1, height=0.9)
    b.carve(b.line([(2.2, -1.25), (2.7, -0.6), (3.3, -1.25)], 0.12) * torso, 0.08, 0.7)       # collar
    b.carve(b.line([(1.0, 1.4), (1.6, 2.6)], 0.1) * torso, 0.06, 0.82)                         # folds
    b.carve(b.line([(2.0, 4.9), (3.0, 5.8)], 0.1) * torso, 0.06, 0.82)
    b.stitch([(0.15, -0.6), (1.2, -0.95), (2.0, -1.2)])
    b.stitch([(3.4, -1.2), (4.6, -0.6), (5.45, 0.2)])
    b.stitch([(-0.5, 1.6), (-0.4, 4.0), (-0.05, 6.0)])
    t = b.like()
    body = b.erode(torso, 0.06)
    front = b.rrect(3.4, 0.3, 5.98, 4.6, 0.45) * b.dilate(torso, 0.15)
    back = b.rrect(-0.72, 0.2, 0.75, 4.3, 0.4) * b.dilate(torso, 0.12)
    cumm = body * b.band(2.9, 4.6)
    t.fill(np.clip(cumm, 0, 1), CARRIER, z=0.5, height=0.45, bevel=0.25)
    t.carve(cumm * t.band(3.35, 3.48), 0.06, 0.6)
    t.carve(cumm * t.band(3.95, 4.08), 0.06, 0.6)
    t.fill(back, CARRIER, z=0.6, height=0.6, bevel=0.3)
    t.fill(front, CARRIER, z=0.7, height=0.75, bevel=0.35)
    t.molle(front, 0.55, 2.4, 3)
    t.stitch([(3.55, 0.45), (5.82, 0.45), (5.82, 4.45), (3.55, 4.45), (3.55, 0.45)], light=1.5)
    t.stitch([(-0.6, 0.35), (0.62, 0.35), (0.62, 4.15)], light=1.5)
    t.molle(cumm, 2.95, 4.55, 2)
    t.edgewear(front, 0.06, 1.45)
    t.edgewear(back, 0.06, 1.4)
    t.scratches(front, 14, seed=13)
    strap = t.line([(0.2, 0.35), (1.35, -0.62), (3.1, -0.68), (4.15, 0.45)], 0.7) * b.dilate(torso, 0.1)
    t.fill(strap, WEB, z=0.6, height=0.35, bevel=0.15)
    t.webbing(strap)
    t.fill(t.rrect(2.15, -0.84, 2.7, -0.5, 0.08), METAL, z=1.0, height=0.12, bevel=0.06, spec=0.9)   # buckle
    for x0 in (3.55, 4.78):   # mag pouches
        pm = t.rrect(x0, 2.55, x0 + 1.12, 4.75, 0.22)
        t.fill(pm, POUCH, z=1.15, height=0.45, bevel=0.2)
        t.carve(t.rrect(x0 + 0.08, 2.55, x0 + 1.04, 2.98, 0.12), 0.07, 0.6)
        t.velcro(t.rrect(x0 + 0.2, 2.62, x0 + 0.92, 2.9, 0.06), 0.2, seed=int(x0 * 10))
        t.stitch([(x0 + 0.1, 3.05), (x0 + 0.1, 4.62), (x0 + 1.02, 4.62), (x0 + 1.02, 3.05)], light=1.45)
        t.edgewear(pm, 0.05, 1.3)
    radio = t.rrect(-0.98, 0.85, 0.22, 3.3, 0.3)
    t.fill(radio, POUCH, z=1.0, height=0.5, bevel=0.22)            # radio
    t.stitch([(-0.88, 1.0), (0.12, 1.0)], light=1.45)
    t.fill(t.rrect(-0.75, 1.25, -0.05, 1.7, 0.08), (0.06, 0.06, 0.07), z=1.5, height=0.08, bevel=0.04, spec=0.6)
    t.fill(t.ell(-0.25, 1.45, 0.05, 0.05), (0.2, 1.0, 0.35), z=1.6, height=0.03, bevel=0.02, emit=0.9)
    t.fill(t.line([(-0.42, 0.95), (-0.62, -1.2), (-0.82, -2.45)], 0.16), WEB, z=1.2, height=0.12, bevel=0.06)
    t.fill(t.ell(-0.82, -2.45, 0.12, 0.12), WEB, z=1.2, height=0.12, bevel=0.06)
    t.noise(0.05, 0.04, 0.008, seed=12)
    acc = b.like()
    acc.fill(acc.rrect(3.85, 0.55, 5.45, 1.22, 0.12), GREY(1.0), height=0.1, bevel=0.05, emit=0.75)
    acc.fill(acc.rrect(-0.6, 0.38, 0.55, 0.62, 0.08), GREY(1.0), height=0.06, bevel=0.04, emit=0.75)
    b.shadow_from(t)
    return {"": b, "_trim": t, "_acc": acc, "_wound": wound_layer(b, 111, 6)}


def d_kamizelka():
    b = Layer(*BOUNDS["kamizelka"])
    front = b.rrect(3.1, -0.2, 6.25, 5.3, 0.55)
    back = b.rrect(-0.95, -0.1, 0.95, 5.1, 0.5)
    cumm = b.poly([(-0.6, 2.6), (5.8, 2.6), (5.6, 5.5), (-0.3, 5.5)], r=0.2)
    collar = b.poly([(0.0, -0.7), (1.4, -1.45), (3.4, -1.5), (4.6, -0.8), (3.9, -0.2), (2.6, -0.75), (1.0, -0.2)], r=0.15)
    b.fill(cumm, GREY(0.86), height=0.6, bevel=0.3)
    b.fill(back, GREY(0.86), z=0.4, height=0.8, bevel=0.35)
    b.fill(front, GREY(0.9), z=0.5, height=1.0, bevel=0.45)
    b.fill(collar, GREY(0.8), z=0.9, height=0.5, bevel=0.25)
    for y in (1.2, 2.6, 4.0):
        b.carve(front * b.band(y, y + 0.12), 0.1, 0.62)
    b.noise(0.03, 0.05, 0.01, seed=21)
    t = b.like()
    for i in range(4):
        t.fill(t.ell(5.9, 0.4 + i * 1.3, 0.13, 0.13), METAL, z=1.6, height=0.1, bevel=0.06, spec=0.9)
    t.fill(t.rrect(3.6, 0.2, 5.6, 0.75, 0.1), WEB, z=1.6, height=0.12, bevel=0.05)
    b.shadow_from(t)
    return {"": b, "_trim": t}


def d_biodro():
    b = Layer(*BOUNDS["biodro"])
    pelvis = b.poly([(-0.75, -1.45), (4.5, -1.45), (4.7, 0.0), (4.1, 0.95), (2.6, 1.25), (0.4, 1.15), (-0.7, 0.4)], r=0.35)
    fabric(b, pelvis, 31, bevel=0.9, height=0.7)
    t = b.like()
    belt = b.dilate(pelvis, 0.05) * b.band(-0.95, 0.1)
    t.fill(belt, WEB, z=0.7, height=0.4, bevel=0.15)
    t.webbing(belt)
    t.stitch([(-0.9, -0.85), (4.6, -0.85)], light=1.4)
    t.stitch([(-0.9, 0.0), (4.6, 0.0)], light=1.4)
    t.carve(belt * t.band(-0.48, -0.4), 0.05, 0.6)
    buckle = t.rrect(3.75, -1.0, 4.55, 0.15, 0.12)
    t.fill(buckle, METAL, z=1.1, height=0.15, bevel=0.07, spec=0.9)
    t.scratches(buckle, 6, seed=33, length=(0.08, 0.3), width=0.015)
    t.fill(t.rrect(3.92, -0.78, 4.38, -0.08, 0.06), WEB, z=1.25, height=0.05, bevel=0.03)
    t.fill(t.rrect(-0.95, -0.65, 0.55, 1.2, 0.4), POUCH, z=1.0, height=0.55, bevel=0.3)            # dump pouch
    t.carve(t.rrect(-0.85, -0.65, 0.45, -0.25, 0.15), 0.08, 0.65)
    t.fill(t.rrect(1.6, -0.5, 2.6, 0.75, 0.22), POUCH, z=1.0, height=0.4, bevel=0.2)
    t.carve(t.rrect(1.67, -0.5, 2.53, -0.15, 0.1), 0.06, 0.65)
    t.noise(0.05, 0.04, 0.008, seed=32)
    b.shadow_from(t)
    return {"": b, "_trim": t, "_wound": wound_layer(b, 131, 3)}


def d_udo():
    b = Layer(*BOUNDS["udo"])
    thigh = b.poly([(-1.5, -0.7), (-0.6, -1.0), (0.7, -1.0), (1.5, -0.62), (1.58, 1.5), (1.32, 3.8), (1.15, 5.2),
                    (0.45, 5.6), (-0.6, 5.55), (-1.22, 5.0), (-1.42, 3.0), (-1.58, 1.0)], r=0.3)
    fabric(b, thigh, 41, bevel=1.2, height=0.9)
    pk = b.rrect(-0.95, 1.55, 0.85, 3.55, 0.22) * thigh
    b.bump(pk, 0.18, 0.06)
    b.carve(b.rrect(-0.98, 1.52, 0.88, 3.58, 0.24) - b.rrect(-0.88, 1.62, 0.78, 3.48, 0.2), 0.06, 0.75)
    b.carve(pk * b.band(1.98, 2.06), 0.06, 0.75)
    b.carve(b.line([(0.9, 0.2), (0.4, 1.0)], 0.08) * thigh, 0.05, 0.85)
    b.stitch([(-0.88, 1.65), (-0.88, 3.45), (0.78, 3.45), (0.78, 1.65)])
    b.stitch([(1.3, -0.4), (1.35, 2.0), (1.05, 5.0)])
    t = b.like()
    t.fill(b.erode(thigh, 0.03) * t.band(3.95, 4.3), WEB, z=0.95, height=0.18, bevel=0.07)
    t.fill(t.rrect(-0.35, 3.85, 0.15, 4.4, 0.06), METAL, z=1.15, height=0.08, bevel=0.04, spec=0.8)
    b.shadow_from(t, dy=0.12)
    return {"": b, "_trim": t, "_wound": wound_layer(b, 141, 4)}


def d_noga():
    b = Layer(*BOUNDS["noga"])
    shin = b.poly([(-1.15, -0.45), (1.15, -0.5), (1.08, 1.0), (0.95, 2.8), (0.88, 5.0), (0.85, 5.6), (-0.85, 5.62),
                   (-0.92, 4.8), (-1.0, 3.2), (-1.32, 1.4)], r=0.3)
    fabric(b, shin, 51, bevel=1.0, height=0.8)
    for y in (3.3, 3.65, 4.0):
        b.carve(b.line([(-0.9, y), (0.9, y + 0.12)], 0.1) * shin, 0.05, 0.8)
    b.stitch([(-0.95, 0.4), (-0.92, 3.0)])
    t = b.like()
    pad = t.rrect(0.05, -0.62, 1.48, 1.62, 0.55)
    t.fill(pad, PAD, z=0.8, height=0.8, bevel=0.45, spec=0.55)
    t.edgewear(pad, 0.07, 1.6)
    t.scratches(pad, 12, seed=53)
    t.rivet(0.3, 0.95, 0.07)
    t.rivet(1.25, 0.95, 0.07)
    t.carve(t.rrect(0.32, -0.32, 1.25, 1.3, 0.38) - t.rrect(0.42, -0.22, 1.15, 1.2, 0.32), 0.06, 0.65)
    t.fill(b.erode(shin, 0.02) * t.band(0.85, 1.12) * t.vband(-2, 0.2), WEB, z=0.85, height=0.15, bevel=0.06)
    b.shadow_from(t, dy=0.15)
    return {"": b, "_trim": t, "_wound": wound_layer(b, 151, 3)}


def d_stopa():
    # tall combat boot: the classic skeleton's ankle joint sits ~3.7 px above the
    # ground, so the shaft runs up the lower shin and the trouser tucks into it
    b = Layer(*BOUNDS["stopa"])
    shaft = b.poly([(-0.82, -0.35), (0.9, -0.42), (0.95, 1.4), (-0.86, 1.5)], r=0.12)
    foot = b.poly([(-1.0, 1.0), (0.95, 1.0), (2.05, 1.85), (2.95, 2.55), (3.3, 3.15), (3.2, 3.6), (-1.05, 3.6),
                   (-1.12, 2.2)], r=0.22)
    boot = np.clip(shaft + foot, 0, 1)
    b.fill(boot, COYOTE, height=0.7, bevel=0.42)
    b.fill(b.ell(2.6, 3.0, 0.65, 0.5) * b.erode(boot, 0.05), COYOTE_D, z=0.55, height=0.22, bevel=0.2, spec=0.25)
    b.fill(b.rrect(-0.9, -0.55, 0.98, -0.12, 0.15), COYOTE_D, z=0.6, height=0.18, bevel=0.08)
    for i in range(4):
        y = 0.05 + i * 0.45
        b.fill(b.line([(0.45, y), (1.0, y + 0.13)], 0.12), WEB, z=0.8, height=0.07, bevel=0.04)
    b.carve(b.line([(-0.95, 2.05), (0.95, 1.95), (2.2, 2.25)], 0.07) * boot, 0.05, 0.7)
    b.velcro(boot, 0.08, seed=62)                                   # leather grain
    b.stitch([(-1.05, 3.0), (3.2, 3.0)], light=1.35)                # welt
    b.stitch([(-0.82, 1.9), (0.9, 1.85), (2.1, 2.15)], light=1.3)
    for i in range(4):                                              # eyelets
        b.rivet(0.92, 0.0 + i * 0.45, 0.055, (0.3, 0.3, 0.32))
    b.noise(0.05, 0.05, 0.012, seed=61)
    sole = b.rrect(-1.2, 3.1, 3.42, 3.88, 0.26)
    b.fill(sole, RUBBER, height=0.3, bevel=0.13)
    for i in range(8):
        x = -0.95 + i * 0.55
        b.carve(b.rrect(x, 3.62, x + 0.24, 3.95, 0.05) * sole, 0.09, 0.5)
    return {"": b}


def d_ramie():
    b = Layer(*BOUNDS["ramie"])
    arm = b.poly([(-1.05, -0.6), (-0.8, -1.2), (0.0, -1.38), (0.85, -1.2), (1.08, -0.5), (0.95, 1.8), (0.82, 3.2),
                  (0.0, 3.4), (-0.85, 3.15), (-0.98, 1.6)], r=0.25)
    fabric(b, arm, 71, bevel=0.9, height=0.7)
    t = b.like()
    pad = t.ell(0.05, -0.2, 1.32, 1.3) * t.band(-2, 1.0)
    pad = smooth(pad, 0.12)
    t.fill(pad, PAD, z=0.7, height=0.75, bevel=0.55, spec=0.5)
    t.carve(pad * t.band(0.62, 0.72), 0.05, 0.65)
    t.edgewear(pad, 0.07, 1.55)
    t.scratches(pad, 10, seed=73)
    acc = b.like()
    acc.fill(pad * acc.band(-0.08, 0.36), GREY(1.0), height=0.06, bevel=0.03, emit=0.7)
    b.shadow_from(t, dy=0.15)
    return {"": b, "_trim": t, "_acc": acc, "_wound": wound_layer(b, 171, 2)}


def d_reka():
    b = Layer(*BOUNDS["reka"])
    arm = b.poly([(-0.9, -0.4), (0.0, -0.55), (0.92, -0.35), (0.85, 2.5), (0.76, 5.25), (-0.72, 5.3), (-0.86, 2.4)], r=0.25)
    fabric(b, arm, 81, bevel=0.75, height=0.6)
    b.carve(b.band(2.9, 3.05) * arm, 0.06, 0.78)
    b.bump(b.band(2.45, 2.95) * arm, 0.1, 0.05)
    t = b.like()
    cuff = b.dilate(arm, 0.06) * t.band(4.15, 5.45)
    t.fill(cuff, GLOVE, z=0.65, height=0.4, bevel=0.18)
    t.carve(cuff * t.band(4.5, 4.58), 0.05, 0.65)
    epad = b.dilate(arm, 0.08) * t.band(-0.6, 0.85)
    t.fill(epad, PAD, z=0.65, height=0.4, bevel=0.25, spec=0.4)
    t.edgewear(epad, 0.06, 1.5)
    t.stitch([(-0.75, 4.25), (0.75, 4.25)], light=1.5)
    b.stitch([(0.82, 0.2), (0.8, 2.9)])
    b.shadow_from(t, dy=0.1)
    return {"": b, "_trim": t, "_wound": wound_layer(b, 181, 2)}


def d_dlon():
    b = Layer(*BOUNDS["dlon"])
    fist = np.clip(b.ell(0.05, 0.95, 1.02, 1.18) + b.ell(0.78, 0.28, 0.42, 0.55), 0, 1)
    fist = smooth(fist, 0.1)
    b.fill(fist, GLOVE, height=0.7, bevel=0.6)
    b.fill(b.ell(0.45, 1.25, 0.6, 0.62) * b.erode(fist, 0.1), GLOVE_D, z=0.6, height=0.25, bevel=0.2, spec=0.4)
    for y in (0.8, 1.2, 1.6):
        b.carve(b.line([(-0.6, y), (0.9, y + 0.1)], 0.07) * fist, 0.05, 0.7)
    b.velcro(fist, 0.1, seed=92)
    b.stitch([(-0.85, 0.5), (-0.95, 1.4), (-0.6, 1.95)], light=1.4)
    b.noise(0.05, 0.04, 0.01, seed=91)
    return {"": b}


# ── head pieces (frame "head": x front, y down, origin = neck joint) ──
SKULL = (-0.1, -1.78, 1.86, 1.95)


def head_mask(L):
    skull = L.ell(*SKULL)
    face = L.poly([(-0.6, -0.4), (0.5, -2.6), (1.72, -2.25), (1.86, -1.55), (1.72, -1.26), (1.98, -0.98),
                   (2.24, -0.56), (1.94, -0.4), (2.02, -0.2), (1.86, -0.04), (1.96, 0.34), (1.42, 0.66),
                   (0.25, 0.3)], r=0.08)
    neck = L.rrect(-0.92, -0.4, 0.88, 1.65, 0.3)
    return np.clip(skull + face + neck, 0, 1)


def d_morda():
    b = Layer(*BOUNDS["head"])
    head = head_mask(b)
    b.fill(head, GREY(0.92), height=0.9, bevel=1.0)
    b.bump(b.ell(-0.35, -1.12, 0.36, 0.55), 0.2, 0.06)                     # ear
    b.carve(b.ell(-0.33, -1.08, 0.16, 0.3), 0.08, 0.75)
    b.carve(b.ell(1.45, -1.27, 0.2, 0.13), 0.12, 0.25)                      # eye socket
    b.paint(b.ell(1.5, -1.27, 0.13, 0.08), (0.86, 0.84, 0.8))               # eye white
    b.paint(b.ell(1.58, -1.27, 0.06, 0.07), (0.12, 0.1, 0.09))              # iris
    b.paint(b.line([(1.62, -0.1), (1.94, -0.08)], 0.09), (0.72, 0.55, 0.5), 0.6)   # lips
    rng = np.random.default_rng(105)
    stub = ndimage.gaussian_filter(rng.standard_normal((b.h, b.w)).astype(np.float32), 0.012 * K)
    jaw = b.poly([(0.3, -0.5), (1.9, -0.4), (2.0, 0.35), (1.42, 0.66), (0.25, 0.3)], r=0.15) * head
    b.alb *= (1 - np.clip(stub * 2.0, 0, 1) * 0.22 * jaw)[..., None]       # stubble
    b.velcro(head, 0.05, seed=106)                                           # skin pores
    b.bump(b.line([(1.15, -1.55), (1.82, -1.6)], 0.16), 0.12, 0.05)        # brow
    b.tone(b.line([(1.2, -1.45), (1.78, -1.48)], 0.12), 0.82)
    b.carve(b.line([(1.62, -0.12), (1.95, -0.1)], 0.07), 0.05, 0.55)       # mouth
    b.tone(b.line([(0.3, 0.35), (1.35, 0.62)], 0.25), 0.85)                # jaw shade
    b.tone(b.rrect(-0.92, 0.2, 0.88, 1.65, 0.3) * head, 0.85)               # neck in shade
    b.noise(0.025, 0.05, 0.008, seed=101)
    t = b.like()
    gaiter = smooth(b.poly([(-0.95, 0.05), (0.2, 0.45), (1.15, 0.5), (0.95, 1.7), (-0.98, 1.7)]), 0.15) * b.dilate(head, 0.06)
    t.fill(gaiter, (0.16, 0.165, 0.17), z=0.8, height=0.35, bevel=0.25)
    for y in (0.55, 0.95, 1.35):
        t.carve(gaiter * t.band(y, y + 0.07), 0.05, 0.7)
    t.fill(t.rrect(-0.85, -1.75, 0.22, -0.52, 0.35), HEADSET, z=1.0, height=0.45, bevel=0.25, spec=0.4)
    t.fill(t.line([(-0.05, -0.68), (0.7, -0.22), (1.62, -0.02)], 0.1), HEADSET, z=1.2, height=0.08, bevel=0.04)
    t.fill(t.ell(1.66, -0.02, 0.13, 0.12), HEADSET, z=1.25, height=0.1, bevel=0.06)
    gl = t.poly([(1.05, -1.5), (1.98, -1.42), (2.0, -1.08), (1.12, -1.0)], r=0.04)
    t.fill(gl, LENS, z=1.1, height=0.2, bevel=0.08, spec=1.0)
    t.fill(t.line([(1.05, -1.3), (0.15, -1.25)], 0.08), HEADSET, z=1.1, height=0.06, bevel=0.03)
    acc = b.like()
    acc.fill(acc.line([(1.2, -1.36), (1.86, -1.32)], 0.06) * gl, GREY(1.0), height=0.03, bevel=0.02, emit=0.45)
    b.shadow_from(t, dx=-0.1, dy=0.12, strength=0.35)
    return {"": b, "_trim": t, "_acc": acc, "_wound": wound_layer(b, 191, 2)}


def helm_shell(L):
    dome = L.ell(-0.1, -2.02, 2.12, 2.02)
    cut = L.poly([(-2.4, -0.62), (-1.0, -0.82), (-0.62, -1.62), (0.55, -1.66), (1.92, -1.42), (2.4, -1.85),
                  (2.4, 1.0), (-2.4, 1.0)])
    return smooth(np.clip(dome - cut, 0, 1), 0.08)


def d_helm():
    b = Layer(*BOUNDS["head"])
    shell = helm_shell(b)
    b.fill(shell, GREY(0.8), height=1.0, bevel=0.9, spec=0.3)
    b.carve(b.line([(-1.9, -1.0), (-0.95, -1.05), (-0.6, -1.78), (0.6, -1.82), (1.85, -1.6)], 0.09) * shell, 0.06, 0.78)
    b.carve(b.line([(-0.3, -3.95), (-0.45, -1.9)], 0.07) * shell, 0.04, 0.85)
    b.noise(0.02, 0.06, 0.012, seed=201)
    b.velcro(shell, 0.07, seed=203)                                 # textured coating
    b.edgewear(shell, 0.06, 1.35)
    b.scratches(shell, 18, seed=204)
    t = b.like()
    t.fill(t.line([(-1.95, -1.15), (-0.95, -1.22), (-0.62, -1.9), (0.5, -1.95)], 0.24) * b.dilate(shell, 0.05), HEADSET, z=1.0, height=0.22, bevel=0.08)
    patch = t.rrect(-0.75, -3.2, 0.55, -2.55, 0.12)
    t.fill(patch, POUCH, z=1.15, height=0.1, bevel=0.06)
    t.velcro(patch, 0.25, seed=205)
    for x in (-1.6, -1.05, 0.0):
        t.rivet(x, -1.2 if x < -1 else -1.93, 0.06)
    vis = t.poly([(1.1, -1.72), (2.32, -1.95), (2.48, -1.2), (2.3, -0.72), (1.35, -0.8)], r=0.06)
    t.fill(vis, LENS, z=1.05, height=0.4, bevel=0.22, spec=1.0)
    t.paint(t.line([(1.3, -1.62), (2.25, -1.82)], 0.07) * vis, (0.55, 0.6, 0.7), 0.5)   # reflection streak
    t.fill(t.line([(1.05, -1.75), (2.3, -1.98)], 0.2), HEADSET, z=1.3, height=0.15, bevel=0.07)
    t.fill(t.ell(1.12, -1.55, 0.2, 0.2), METAL, z=1.35, height=0.12, bevel=0.08, spec=0.9)
    t.noise(0.04, 0.04, 0.006, seed=202)
    acc = b.like()
    acc.fill(acc.poly([(1.4, -1.43), (2.42, -1.55), (2.44, -1.27), (1.45, -1.17)], r=0.03), GREY(1.0), height=0.04, bevel=0.03, emit=1.0)
    acc.fill(acc.rrect(-1.65, -3.35, -1.2, -3.02, 0.06), GREY(1.0), height=0.04, bevel=0.03, emit=0.95)
    b.shadow_from(t, dx=-0.1, dy=0.12, strength=0.35)
    return {"": b, "_trim": t, "_acc": acc}


def d_kap():
    b = Layer(*BOUNDS["head"])
    crown = smooth(b.ell(-0.12, -2.05, 1.98, 1.72) * b.band(-4, -1.35), 0.08)
    band = b.rrect(-2.0, -1.62, 1.75, -1.25, 0.1)
    brim = b.poly([(1.1, -1.66), (2.85, -1.48), (2.8, -1.24), (1.2, -1.32)], r=0.05)
    cap = np.clip(crown + band + brim, 0, 1)
    b.fill(cap, GREY(0.82), height=0.75, bevel=0.6)
    b.carve(b.line([(-0.2, -3.75), (-0.1, -1.6)], 0.07) * crown, 0.05, 0.8)
    b.carve(band * b.band(-1.62, -1.55), 0.05, 0.75)
    b.noise(0.02, 0.06, 0.012, seed=211)
    acc = b.like()
    acc.fill(acc.rrect(0.75, -2.55, 1.35, -2.1, 0.06) * crown, GREY(1.0), height=0.04, bevel=0.03, emit=0.6)
    return {"": b, "_acc": acc}


def hair_layer(style):
    b = Layer(*BOUNDS["head"])
    skull = b.ell(SKULL[0] - 0.05, SKULL[1] - 0.05, SKULL[2] + 0.12, SKULL[3] + 0.1)
    if style == 1:      # crew cut
        m = skull * b.band(-5, -1.9) + b.ell(-1.1, -1.5, 0.95, 1.0) * skull
        m = np.clip(m - b.poly([(0.9, -2.25), (2.5, -2.4), (2.5, 0.5), (0.5, 0.5)]), 0, 1)
    elif style == 2:    # slicked back, fuller top
        m = np.clip(b.ell(-0.25, -2.25, 2.1, 1.75) * b.band(-5, -1.75) + b.ell(-1.2, -1.4, 1.0, 1.15), 0, 1)
        m = np.clip(m - b.poly([(1.15, -2.2), (2.6, -2.5), (2.6, 0.5), (0.6, 0.5)]), 0, 1)
    elif style == 3:    # mohawk on a shaved head
        m = np.clip(b.poly([(-1.6, -2.8), (-0.6, -4.05), (0.6, -4.1), (1.55, -3.4), (1.2, -3.0), (0.0, -3.55),
                            (-1.2, -2.5)], r=0.12), 0, 1)
    else:               # long, tied back
        m = np.clip(b.ell(-0.2, -2.2, 2.0, 1.7) * b.band(-5, -1.8) + b.ell(-1.25, -1.3, 0.95, 1.2)
                    + b.poly([(-1.9, -1.6), (-1.05, -1.4), (-1.35, 1.2), (-1.9, 1.35), (-2.25, 0.0)], r=0.18), 0, 1)
        m = np.clip(m - b.poly([(1.1, -2.2), (2.6, -2.5), (2.6, 0.5), (0.0, 0.5), (0.1, -0.6)]), 0, 1)
    m = smooth(m, 0.08)
    b.fill(m, HAIR, height=0.5, bevel=0.35, spec=0.2)
    rng = np.random.default_rng(220 + style)
    ys, xs = np.nonzero(m > 0.5)
    for i in range(40 if len(xs) else 0):    # strands
        j = rng.integers(len(xs))
        x, y = xs[j] / K + b.x0, ys[j] / K + b.y0
        a = rng.uniform(-2.6, -2.0) if style != 3 else rng.uniform(-1.9, -1.2)
        l = rng.uniform(0.3, 0.7)
        b.carve(b.line([(x, y), (x + math.cos(a) * l, y + math.sin(a) * l)], 0.05) * m, 0.04, 0.7, 0.02)
    b.noise(0.06, 0.03, 0.01, seed=230 + style)
    return {"": b}


def d_hair1():
    return hair_layer(1)


def d_hair2():
    return hair_layer(2)


def d_hair3():
    return hair_layer(3)


def d_hair4():
    return hair_layer(4)


def d_dred():
    b = Layer(*BOUNDS["head"])
    m = np.zeros((b.h, b.w), np.float32)
    for k in range(6):
        x0 = -1.5 + k * 0.42
        y0 = -3.3 + abs(k - 2.5) * 0.25
        m = np.maximum(m, b.line([(x0, y0), (x0 - 0.7 - k * 0.08, y0 + 1.6), (x0 - 1.0 - k * 0.12, 0.9 + k * 0.1)], 0.3))
    m = smooth(m, 0.05)
    b.fill(m, HAIR, height=0.4, bevel=0.15, spec=0.15)
    for y in np.arange(-3.4, 1.6, 0.28):
        b.carve(b.band(y, y + 0.06) * m, 0.05, 0.75, 0.03)
    return {"": b}


def d_cygaro():
    b = Layer(*BOUNDS["head"])
    cig = b.line([(1.85, -0.12), (2.62, 0.08)], 0.19)
    b.fill(cig, (0.36, 0.22, 0.12), height=0.18, bevel=0.08)
    b.carve(b.band(-0.1, -0.02) * cig * b.vband(2.05, 2.15), 0.04, 0.7)
    b.fill(b.ell(2.63, 0.08, 0.11, 0.1), (1.0, 0.45, 0.12), z=0.18, height=0.06, bevel=0.04, emit=0.9)
    return {"": b}


def chain_layer(col):
    b = Layer(*BOUNDS["klata"])
    m = np.zeros((b.h, b.w), np.float32)
    pts = [(2.05, -1.05), (2.55, -0.25), (3.35, 0.45), (4.25, 0.75), (4.85, 0.35), (5.2, -0.3)]
    for i in range(len(pts) - 1):
        (xa, ya), (xb, yb) = pts[i], pts[i + 1]
        for s in np.linspace(0, 1, 5, endpoint=False):
            x, y = xa + (xb - xa) * s, ya + (yb - ya) * s
            m = np.maximum(m, b.ell(x, y, 0.13, 0.11) - b.ell(x, y, 0.06, 0.05))
    b.fill(np.clip(m, 0, 1), col, height=0.12, bevel=0.06, spec=1.0)
    return b


def d_lancuch():
    return {"": chain_layer(SILVER)}


def d_zlotylancuch():
    return {"": chain_layer(GOLD)}


def d_metal():
    b = Layer(*BOUNDS["klata"])
    for x, y in [(2.3, -0.9), (2.6, -0.4), (2.95, 0.1), (3.3, 0.55), (3.6, 0.9)]:
        b.fill(b.ell(x, y, 0.06, 0.06), SILVER, height=0.05, bevel=0.03, spec=0.9)
    tag = b.rrect(3.45, 0.95, 4.15, 1.95, 0.18)
    b.fill(tag, SILVER, height=0.1, bevel=0.05, spec=1.0)
    b.carve(b.rrect(3.58, 1.25, 4.02, 1.33, 0.02), 0.03, 0.7)
    b.carve(b.rrect(3.58, 1.45, 3.9, 1.53, 0.02), 0.03, 0.7)
    return {"": b}


def d_jetpack():
    # frame "id" on the back line (joint 10 -> joint 5): x down the back, y away from it
    b = Layer(*BOUNDS["jetpack"])
    b.fill(b.rrect(0.6, 0.25, 8.15, 1.45, 0.3), WEB, height=0.3, bevel=0.15)
    far = b.rrect(1.35, 2.15, 7.25, 4.4, 1.1)
    b.fill(far, (0.18, 0.19, 0.205), z=0.2, height=0.7, bevel=0.75, spec=0.7)
    near = b.rrect(0.3, 0.9, 7.6, 3.8, 1.35)
    b.fill(near, (0.24, 0.25, 0.265), z=0.3, height=0.95, bevel=0.95, spec=0.85)
    b.carve(near * b.band(3.15, 3.25), 0.06, 0.7)
    b.edgewear(near, 0.08, 1.4)
    b.scratches(near, 22, seed=301)
    for x in np.arange(1.0, 7.2, 0.7):
        b.rivet(float(x), 1.2, 0.05)
    lab = b.rrect(2.9, 1.5, 4.9, 2.3, 0.08)
    b.paint(lab, (0.55, 0.47, 0.18), 0.85)                          # warning label
    for x in np.arange(2.95, 4.9, 0.28):
        b.paint(b.poly([(x, 1.5), (x + 0.12, 1.5), (x + 0.02, 2.3), (x - 0.1, 2.3)]) * lab, (0.1, 0.1, 0.1), 0.8)
    for x in (2.15, 5.45):
        b.fill(b.rrect(x, 0.65, x + 0.5, 3.95, 0.12), WEB, z=1.2, height=0.15, bevel=0.07)
    b.fill(b.poly([(7.3, 1.3), (8.0, 1.12), (8.8, 0.82), (8.8, 3.92), (8.0, 3.55), (7.3, 3.35)], r=0.06),
           (0.34, 0.35, 0.37), z=0.3, height=0.6, bevel=0.3, spec=0.9)
    b.carve(b.rrect(8.45, 1.08, 8.9, 3.65, 0.15), 0.3, 0.25, 0.04)
    heat = b.vband(7.9, 8.9) * b.poly([(7.3, 1.3), (8.0, 1.12), (8.8, 0.82), (8.8, 3.92), (8.0, 3.55), (7.3, 3.35)])
    b.paint(heat, (0.36, 0.3, 0.42), 0.45)                          # heat-blued nozzle
    b.fill(b.ell(0.45, 2.3, 0.45, 0.45), METAL, z=1.0, height=0.25, bevel=0.15, spec=0.9)
    acc = b.like()
    acc.fill(acc.rrect(3.2, 2.75, 4.55, 3.28, 0.12), GREY(1.0), height=0.05, bevel=0.03, emit=0.9)
    return {"": b, "_acc": acc}


# Bounds in design coordinates: (x0, x1, y0, y1). Frame per part.
BOUNDS = {
    "klata": (-0.8, 6.3, -2.6, 6.5), "kamizelka": (-1.0, 6.4, -2.6, 6.5), "biodro": (-1.0, 5.0, -1.7, 2.0),
    "stopa": (-1.3, 3.5, -0.7, 3.98), "jetpack": (0.0, 8.9, 0.2, 4.5),
    "udo": (-1.68, 1.68, -1.05, 5.65), "noga": (-1.4, 1.55, -0.7, 5.72), "ramie": (-1.38, 1.38, -1.42, 3.45),
    "reka": (-1.0, 1.0, -0.62, 5.48), "dlon": (-1.1, 1.25, -0.3, 2.2),
    "head": (-2.5, 2.9, -4.2, 1.7),
}
BOUNDS["lancuch"] = BOUNDS["zlotylancuch"] = BOUNDS["metal"] = BOUNDS["klata"]
for _h in ("morda", "helm", "kap", "hair1", "hair2", "hair3", "hair4", "dred", "cygaro"):
    BOUNDS[_h] = BOUNDS["head"]

PARTS = {
    "klata": (d_klata, "id"), "kamizelka": (d_kamizelka, "id"), "biodro": (d_biodro, "id"),
    "stopa": (d_stopa, "id"), "jetpack": (d_jetpack, "jp"),
    "udo": (d_udo, "limb"), "noga": (d_noga, "limb"), "ramie": (d_ramie, "limb"),
    "reka": (d_reka, "limb"), "dlon": (d_dlon, "limb"),
    "morda": (d_morda, "head"), "helm": (d_helm, "head"), "kap": (d_kap, "head"),
    "hair1": (d_hair1, "head"), "hair2": (d_hair2, "head"), "hair3": (d_hair3, "head"), "hair4": (d_hair4, "head"),
    "dred": (d_dred, "head"), "cygaro": (d_cygaro, "head"),
    "lancuch": (d_lancuch, "id"), "zlotylancuch": (d_zlotylancuch, "id"), "metal": (d_metal, "id"),
}
LIGHTS = {"jp": np.array([-0.62, -0.45, 0.64]) / np.linalg.norm([-0.62, -0.45, 0.64])}


def pivot(name):
    """(cx, cy) of the bone's first joint inside the SPRITE rect (unflipped)."""
    x0, x1, y0, y1 = BOUNDS[name]
    frame = PARTS[name][1]
    if frame in ("id", "jp"):
        return -x0 / (x1 - x0), -y0 / (y1 - y0)
    if frame == "limb":     # sprite x = down the limb (design y); sprite y = -front
        return -y0 / (y1 - y0), x1 / (x1 - x0)
    # head: sprite x = up = -design y; sprite y = front = design x
    return y1 / (y1 - y0), -x0 / (x1 - x0)


def to_sprite(img, nrm, frame):
    """Design image (+ normals in design image axes) -> sprite orientation."""
    nx, ny, nz = nrm[..., 0], nrm[..., 1], nrm[..., 2]
    if frame == "limb":       # CCW: u = dy, v = W - dx
        img = img.rotate(90, expand=True)
        nrm = np.dstack([ny, -nx, nz])
        nrm = np.rot90(nrm, 1)
    elif frame == "head":     # CW: u = H - dy, v = dx
        img = img.rotate(-90, expand=True)
        nrm = np.dstack([-ny, nx, nz])
        nrm = np.rot90(nrm, -1)
    return img, nrm


def encode_normals(nrm, alpha):
    """Sprite-space normals (x right, y down) -> OpenGL normal map RGBA (green = up)."""
    r = nrm[..., 0] * 0.5 + 0.5
    g = -nrm[..., 1] * 0.5 + 0.5
    b = nrm[..., 2] * 0.5 + 0.5
    out = np.dstack([r, g, b, alpha])
    return Image.fromarray((np.clip(out, 0, 1) * 255).round().astype(np.uint8), "RGBA")


def build(name):
    fn, frame = PARTS[name]
    layers = fn()
    out = {}
    for suffix, layer in layers.items():
        img, nrm = layer.render(light=LIGHTS.get(frame, LIGHT))
        if img is None:
            continue
        img, nrm = to_sprite(img, nrm, frame)
        alpha = np.asarray(img, np.float32)[..., 3] / 255.0
        nimg = encode_normals(nrm, alpha)
        out[name + suffix] = img
        out[name + suffix + "_n"] = nimg
        out[name + suffix + "2"] = img.transpose(Image.FLIP_TOP_BOTTOM)
        flipped = nrm[::-1].copy()
        flipped[..., 1] *= -1.0
        out[name + suffix + "_n2"] = encode_normals(flipped, alpha[::-1])
    return out


def main():
    sheet = sys.argv[sys.argv.index("--sheet") + 1] if "--sheet" in sys.argv else None
    only = [a for a in sys.argv[1:] if a in PARTS]
    os.makedirs(OUT, exist_ok=True)
    made = {}
    for name in (only or PARTS):
        imgs = build(name)
        for k, im in imgs.items():
            # normal maps are named <layer>_n.png / <layer>_n2.png
            fname = k.replace("_n2", "2_n") if k.endswith("_n2") else k
            path = os.path.join(OUT, fname + ".png")
            im.save(path, optimize=True)
            imp = path + ".import"
            if os.path.exists(imp):
                txt = open(imp).read()
                if "mipmaps/generate=false" in txt:
                    open(imp, "w").write(txt.replace("mipmaps/generate=false", "mipmaps/generate=true"))
        made.update(imgs)
        print("operator gfx: %-12s %d files" % (name, len(imgs)))
    rig = {}
    for name in PARTS:
        cx, cy = pivot(name)
        rig[name] = [round(cx, 5), round(cy, 5)]
    rig_path = os.path.join(OUT, "rig.json")
    with open(rig_path, "w") as f:
        json.dump({"px_per_unit": PX, "pivot": rig}, f, indent=1, sort_keys=True)
    if sheet:
        ims = [made[k] for k in sorted(made) if not (k.endswith("2") or k.endswith("_n"))]
        S = 2
        W = sum(i.width * S + 12 for i in ims) + 12
        H = max(i.height * S for i in ims) + 24
        sh = Image.new("RGBA", (W, H), (70, 80, 90, 255))
        x = 12
        for i in ims:
            sh.alpha_composite(i.resize((i.width * S, i.height * S), Image.LANCZOS), (x, 12))
            x += i.width * S + 12
        sh.save(sheet)


if __name__ == "__main__":
    main()
