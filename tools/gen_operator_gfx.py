#!/usr/bin/env python3
"""Paint the "Operator" soldier sprite set (#280) into assets/gostek-hd/.

Every body part of the classic gostek skeleton gets a new, 3x higher-resolution
sprite that fills exactly the same footprint (same pivot, same rect), so the
.poa animations, hit boxes and the whole drawing path stay as they are.
Each part is up to three layers drawn in order with the same transform:

  <part>.png       base, greyscale — tinted like the classic sprite (team
                   colour, trousers, skin, helmet paint); boots / gloves use
                   real colours (drawn untinted)
  <part>_trim.png  gear in real colours drawn untinted on top (plate carrier,
                   webbing, knee pads, headset, NVG mount ...)
  <part>_acc.png   small accents tinted with the bright team colour (shoulder
                   stripes, NVG lens, IR strobe) so friend / foe pops

plus <name>2.png mirrors (vertical flips — the classic left-facing sprites are
vertical flips too). Shapes are drawn as vectors on a 12x canvas, extruded into
a height field (bevels, seams, folds), lit, given ambient occlusion and a thin
dark outline, then downsampled. Deterministic: re-running gives the same files.

  python3 tools/gen_operator_gfx.py            # write assets/gostek-hd/
  python3 tools/gen_operator_gfx.py --sheet F  # also save a contact sheet
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "gostek-gfx")
OUT = os.path.join(ROOT, "assets", "gostek-hd")
HD = 3          # output pixels per classic sprite pixel
SS = 4          # supersampling on top of that
K = HD * SS     # canvas pixels per design unit (one classic sprite pixel)
LIGHT = np.array([0.5, -0.68, 0.55])
LIGHT = LIGHT / np.linalg.norm(LIGHT)

# Real-colour materials (linear-ish sRGB, 0..1).
CARRIER = (0.205, 0.215, 0.205)
POUCH = (0.255, 0.262, 0.245)
WEB = (0.13, 0.135, 0.13)
METAL = (0.5, 0.52, 0.55)
COYOTE = (0.3, 0.255, 0.2)
COYOTE_D = (0.21, 0.18, 0.145)
GLOVE = (0.29, 0.25, 0.2)
GLOVE_D = (0.17, 0.155, 0.14)
RUBBER = (0.08, 0.08, 0.085)
PAD = (0.15, 0.155, 0.16)
HEADSET = (0.12, 0.125, 0.13)
LENS = (0.05, 0.06, 0.07)


def orig(name):
    p = os.path.join(SRC, name + ".png")
    return Image.open(p).convert("RGBA") if os.path.exists(p) else None


class Layer:
    """One sprite layer in design space (W x H units, y down, front = +x)."""

    def __init__(self, W, H):
        self.W, self.H = W, H
        self.w, self.h = int(round(W * K)), int(round(H * K))
        self.alb = np.zeros((self.h, self.w, 3), np.float32)
        self.a = np.zeros((self.h, self.w), np.float32)
        self.z = np.zeros((self.h, self.w), np.float32)
        self.spec = np.zeros((self.h, self.w), np.float32)
        self.emit = np.zeros((self.h, self.w), np.float32)

    # ── mask helpers (design units) ──
    def _img(self):
        return Image.new("L", (self.w, self.h), 0)

    def _m(self, im):
        return np.asarray(im, np.float32) / 255.0

    def poly(self, pts):
        im = self._img()
        ImageDraw.Draw(im).polygon([(x * K, y * K) for x, y in pts], fill=255)
        return self._m(im)

    def ell(self, cx, cy, rx, ry):
        im = self._img()
        ImageDraw.Draw(im).ellipse([(cx - rx) * K, (cy - ry) * K, (cx + rx) * K, (cy + ry) * K], fill=255)
        return self._m(im)

    def rrect(self, x0, y0, x1, y1, r):
        im = self._img()
        ImageDraw.Draw(im).rounded_rectangle([x0 * K, y0 * K, x1 * K, y1 * K], radius=r * K, fill=255)
        return self._m(im)

    def line(self, pts, width):
        im = self._img()
        d = ImageDraw.Draw(im)
        d.line([(x * K, y * K) for x, y in pts], fill=255, width=max(1, int(width * K)), joint="curve")
        r = width * K * 0.5
        for x, y in (pts[0], pts[-1]):
            d.ellipse([x * K - r, y * K - r, x * K + r, y * K + r], fill=255)
        return self._m(im)

    def band(self, y0, y1):
        m = np.zeros((self.h, self.w), np.float32)
        m[int(max(0, y0 * K)):int(max(0, min(self.h, y1 * K))), :] = 1.0
        return m

    def vband(self, x0, x1):
        m = np.zeros((self.h, self.w), np.float32)
        m[:, int(max(0, x0 * K)):int(max(0, min(self.w, x1 * K)))] = 1.0
        return m

    def from_sprite(self, spr, smooth=0.9):
        """Classic sprite (already in design orientation) -> (mask, luminance)."""
        a = np.asarray(spr.resize((self.w, self.h), Image.BILINEAR), np.float32) / 255.0
        mask = ndimage.gaussian_filter(a[..., 3], smooth * K)
        mask = np.clip((mask - 0.5) * 6.0 + 0.5, 0, 1)
        lum = a[..., :3].mean(axis=2)
        lum = ndimage.gaussian_filter(lum, 0.8 * K)
        return mask, lum

    def erode(self, m, units):
        return np.clip(ndimage.grey_erosion((m > 0.5).astype(np.float32), size=max(1, int(units * K * 2))), 0, 1) * m

    def dilate(self, m, units):
        return ndimage.grey_dilation(m, size=max(1, int(units * K * 2)))

    # ── painting ──
    def fill(self, m, col, z=0.0, height=1.0, bevel=1.0, spec=0.0, emit=0.0, stack=False):
        """Paint mask `m` with colour `col`; extrude it `height` over `z` with
        rounded edges `bevel` units wide (stack: sit on whatever is below)."""
        m = np.clip(m, 0, 1)
        if m.max() <= 0:
            return
        d = ndimage.distance_transform_edt(m > 0.5) / K
        prof = np.clip(d / max(bevel, 0.01), 0, 1)
        prof = prof * prof * (3 - 2 * prof)
        base = self.z if stack else z
        zz = base + prof * height
        col = np.array(col, np.float32).reshape(1, 1, 3) if not isinstance(col, np.ndarray) else col
        mm = m[..., None]
        self.alb = self.alb * (1 - mm) + col * mm
        self.z = self.z * (1 - m) + zz * m
        self.spec = self.spec * (1 - m) + spec * m
        self.emit = self.emit * (1 - m) + emit * m
        self.a = np.maximum(self.a, m)

    def carve(self, m, depth=0.5, dark=0.75, soft=0.25):
        m = ndimage.gaussian_filter(np.clip(m, 0, 1), soft * K) * (self.a > 0.01)
        self.z -= m * depth
        self.alb *= (1 - m * (1 - dark))[..., None]

    def raise_(self, m, amount=0.5, soft=0.6):
        m = ndimage.gaussian_filter(np.clip(m, 0, 1), soft * K) * (self.a > 0.01)
        self.z += m * amount

    def tone(self, m, mul):
        m = np.clip(m, 0, 1)[..., None]
        self.alb *= (1 - m) + m * mul

    def noise(self, amount=0.06, scale=0.7, zamount=0.15, seed=1):
        rng = np.random.default_rng(seed)
        n = rng.standard_normal((self.h, self.w)).astype(np.float32)
        n = ndimage.gaussian_filter(n, scale * K)
        n /= max(1e-6, n.std())
        self.alb *= (1 + n * amount)[..., None]
        self.z += n * zamount

    def camo(self, amount=0.09, seed=7, scale=2.2):
        """Subtle three-tone camo blotches in the (tinted) fabric albedo."""
        rng = np.random.default_rng(seed)
        out = np.zeros((self.h, self.w), np.float32)
        for i, (lvl, s) in enumerate(((1.0, scale), (-1.0, scale * 0.7))):
            n = ndimage.gaussian_filter(rng.standard_normal((self.h, self.w)).astype(np.float32), s * K)
            n /= max(1e-6, n.std())
            out += lvl * np.clip((n - 0.55) * 3.0, 0, 1)
        out = ndimage.gaussian_filter(out, 0.15 * K)
        self.alb *= (1 + out * amount)[..., None] * (self.a > 0.01)[..., None] + (self.a <= 0.01)[..., None]

    def folds(self, lum, amount=0.9):
        """Soft fold relief from the classic sprite's shading."""
        l = lum - ndimage.gaussian_filter(lum, 2.5 * K)
        self.z += l * amount * 6.0 * (self.a > 0.01)

    def shadow_from(self, other, dx=-0.5, dy=0.7, strength=0.45, blur=0.6):
        sh = ndimage.shift(other.a, (dy * K, dx * K), order=1)
        sh = ndimage.gaussian_filter(sh, blur * K)
        self.alb *= (1 - strength * sh * (1 - other.a))[..., None]

    # ── output ──
    def render(self, light=LIGHT, ambient=0.5, diffuse=0.62, outline=0.55, ao=0.55):
        if self.a.max() <= 0:
            return None
        zs = ndimage.gaussian_filter(self.z, 0.35 * K)
        gy, gx = np.gradient(zs)
        n = np.dstack([-gx * K * 0.9, -gy * K * 0.9, np.ones_like(zs)])
        n /= np.linalg.norm(n, axis=2, keepdims=True)
        lam = np.clip((n * light).sum(axis=2), 0, 1)
        hv = light + np.array([0, 0, 1.0])
        hv /= np.linalg.norm(hv)
        sp = np.clip((n * hv).sum(axis=2), 0, 1) ** 28 * self.spec * 0.9
        occ = np.clip((ndimage.gaussian_filter(self.z, 1.6 * K) - self.z) * 0.6, 0, 1) * ao
        shade = (ambient + diffuse * lam) * (1 - occ)
        rgb = self.alb * shade[..., None] + sp[..., None]
        rgb = rgb * (1 - self.emit[..., None]) + self.alb * self.emit[..., None]
        # thin dark outline on the silhouette (readability at 1x)
        inner = ndimage.grey_erosion(self.a, size=max(1, int(0.7 * K)))
        edge = np.clip(self.a - inner, 0, 1)
        rgb *= (1 - outline * edge)[..., None]
        a = self.a
        prem = np.dstack([np.clip(rgb, 0, 1) * a[..., None], a[..., None]])
        im = Image.fromarray((prem * 255).astype(np.uint8), "RGBA")
        im = im.resize((self.w // SS, self.h // SS), Image.LANCZOS)
        arr = np.asarray(im, np.float32) / 255.0
        al = arr[..., 3:4]
        rgb = np.where(al > 1e-4, arr[..., :3] / np.maximum(al, 1e-4), 0)
        out = np.dstack([np.clip(rgb, 0, 1), np.clip(al, 0, 1)])
        return Image.fromarray((out * 255).round().astype(np.uint8), "RGBA")


GREY = lambda v: (v, v, v)

# ─────────────────────────────── part designs ───────────────────────────────
# Each design gets (W, H) in design units and returns {"": base, "_trim": ..,
# "_acc": ..} Layers. Design frames are upright and face right (+x = front).


def d_klata(W, H, spr):
    b = Layer(W, H)
    mask, lum = b.from_sprite(spr)
    b.fill(mask, GREY(0.84), height=2.4, bevel=3.0)
    b.folds(lum, 0.7)
    b.noise(0.022, 0.6, 0.06, seed=11)
    b.camo(seed=511)
    t = Layer(W, H)
    body = b.erode(mask, 0.7)
    xs = np.nonzero(body.max(axis=0) > 0.5)[0]
    x0, x1 = (xs.min() / K, xs.max() / K) if len(xs) else (2, W - 2)
    carrier = body * np.clip(t.band(H * 0.3, H * 0.84) * t.vband(x1 - W * 0.36, x1 + 1)
                             + t.band(H * 0.46, H * 0.74)
                             + t.band(H * 0.32, H * 0.8) * t.vband(x0 - 1, x0 + W * 0.12), 0, 1)
    t.fill(carrier, CARRIER, z=1.2, height=1.4, bevel=1.1)
    front = carrier * t.vband(x1 - W * 0.30, x1 + 1)
    t.raise_(front, 0.9, 0.8)
    t.carve(carrier * t.vband(x1 - W * 0.31, x1 - W * 0.29), 0.5, 0.6, 0.15)
    back = carrier * t.vband(x0 - 1, x0 + W * 0.2)
    t.raise_(back, 0.6, 0.8)
    # MOLLE rows on the cummerbund
    for i in range(2):
        y = H * (0.52 + i * 0.1)
        t.carve(carrier * t.band(y, y + 0.55) * t.vband(x0 + W * 0.2, x1 - W * 0.31), 0.35, 0.55, 0.1)
    # shoulder strap over the top of the shoulder
    strap = body * t.band(1.0, H * 0.32) * t.vband(W * 0.46, W * 0.6)
    t.fill(strap, WEB, z=1.1, height=0.9, bevel=0.6)
    # mag pouches on the front, low
    for i in range(2):
        px = x1 - W * 0.29 + i * W * 0.125
        pm = t.rrect(px, H * 0.58, px + W * 0.12, H * 0.87, 0.7) * b.dilate(mask, 0.6)
        t.fill(pm, POUCH, z=2.4, height=1.1, bevel=0.7)
        t.carve(t.rrect(px + 0.2, H * 0.58, px + W * 0.12 - 0.2, H * 0.65, 0.3), 0.3, 0.7, 0.1)
    # radio pouch on the back + antenna
    rp = t.rrect(x0 - 0.6, H * 0.35, x0 + W * 0.17, H * 0.68, 0.9) * b.dilate(mask, 1.0)
    t.fill(rp, POUCH, z=2.0, height=1.2, bevel=0.8)
    ant = t.line([(x0 + W * 0.06, H * 0.36), (x0 + W * 0.02, H * 0.12), (x0 - 0.2, 0.6)], 0.5)
    t.fill(ant * (1 - rp), WEB, z=2.0, height=0.4, bevel=0.25)
    # drag handle buckle
    t.fill(t.rrect(W * 0.46, H * 0.26, W * 0.58, H * 0.31, 0.3) * body, METAL, z=2.6, height=0.4, bevel=0.2, spec=0.8)
    t.noise(0.07, 0.35, 0.05, seed=12)
    acc = Layer(W, H)
    acc.fill(t.rrect(x1 - W * 0.3, H * 0.33, x1 - W * 0.08, H * 0.45, 0.4) * body, GREY(1.0), height=0.3, bevel=0.2, emit=0.7)
    b.shadow_from(t)
    return {"": b, "_trim": t, "_acc": acc}


def d_kamizelka(W, H, spr):
    # Heavy armour (the Vest cosmetic): thick plates, shoulder guard, collar.
    b = Layer(W, H)
    mask, lum = b.from_sprite(spr)
    b.fill(mask, GREY(0.85), height=2.6, bevel=1.4)
    xs = np.nonzero(mask.max(axis=0) > 0.5)[0]
    x0, x1 = xs.min() / K, xs.max() / K
    b.raise_(mask * b.vband(x1 - W * 0.32, x1 + 1), 1.0, 0.7)
    b.raise_(mask * b.vband(x0 - 1, x0 + W * 0.22), 0.8, 0.7)
    for y in (0.33, 0.55, 0.77):
        b.carve(mask * b.band(H * y, H * y + 0.6), 0.6, 0.6, 0.12)
    b.carve(mask * b.vband(x1 - W * 0.33, x1 - W * 0.31), 0.5, 0.6, 0.12)
    b.noise(0.06, 0.4, 0.05, seed=21)
    t = Layer(W, H)
    t.fill(t.rrect(W * 0.36, 0.5, W * 0.7, H * 0.2, 1.0) * b.dilate(mask, 0.4), PAD, z=2.8, height=1.0, bevel=0.6)
    for i in range(4):
        t.fill(t.ell(x1 - W * 0.06, H * (0.3 + i * 0.16), 0.55, 0.55) * mask, METAL, z=3.4, height=0.4, bevel=0.3, spec=0.9)
    b.shadow_from(t)
    return {"": b, "_trim": t}


def d_biodro(W, H, spr):
    b = Layer(W, H)
    mask, lum = b.from_sprite(spr)
    b.fill(mask, GREY(0.84), height=2.0, bevel=2.5)
    b.folds(lum, 0.6)
    b.noise(0.022, 0.6, 0.05, seed=31)
    b.camo(seed=531)
    t = Layer(W, H)
    belt = b.erode(mask, 0.5) * t.band(H * 0.1, H * 0.46)
    t.fill(belt, WEB, z=1.6, height=1.0, bevel=0.6)
    t.carve(belt * t.band(H * 0.27, H * 0.3), 0.3, 0.6, 0.1)
    xs = np.nonzero(mask.max(axis=0) > 0.5)[0]
    x0, x1 = xs.min() / K, xs.max() / K
    t.fill(t.rrect(x1 - W * 0.17, H * 0.12, x1 - W * 0.05, H * 0.44, 0.35) * mask, METAL, z=2.4, height=0.5, bevel=0.25, spec=0.85)
    t.fill(t.rrect(x1 - W * 0.145, H * 0.2, x1 - W * 0.075, H * 0.36, 0.2), WEB, z=2.6, height=0.2, bevel=0.1)
    # dump pouch at the back + small utility pouch at the side
    t.fill(t.rrect(x0 - 0.4, H * 0.22, x0 + W * 0.2, H * 0.78, 1.2) * b.dilate(mask, 1.0), POUCH, z=2.0, height=1.4, bevel=1.0)
    t.carve(t.rrect(x0, H * 0.22, x0 + W * 0.18, H * 0.34, 0.5), 0.35, 0.7, 0.12)
    t.fill(t.rrect(W * 0.42, H * 0.3, W * 0.6, H * 0.7, 0.6) * mask, POUCH, z=2.0, height=1.1, bevel=0.6)
    t.noise(0.07, 0.35, 0.04, seed=32)
    b.shadow_from(t)
    return {"": b, "_trim": t}


def d_udo(W, H, spr):
    # upright: hip at the top, knee at the bottom, front to the right
    b = Layer(W, H)
    mask, lum = b.from_sprite(spr)
    b.fill(mask, GREY(0.84), height=2.6, bevel=W * 0.38)
    b.folds(lum, 0.8)
    # cargo pocket with a flap
    pk = b.rrect(W * 0.2, H * 0.36, W * 0.72, H * 0.7, 1.0) * mask
    b.raise_(pk, 0.55, 0.35)
    b.carve(b.band(H * 0.36, H * 0.44) * pk, 0.25, 0.85, 0.12)
    b.carve(b.rrect(W * 0.19, H * 0.355, W * 0.73, H * 0.705, 1.0) - b.rrect(W * 0.22, H * 0.38, W * 0.7, H * 0.68, 0.9), 0.2, 0.8, 0.1)
    b.noise(0.022, 0.6, 0.06, seed=41)
    b.camo(seed=541)
    t = Layer(W, H)
    strap = b.erode(mask, 0.3) * t.band(H * 0.76, H * 0.82)
    t.fill(strap, WEB, z=2.4, height=0.6, bevel=0.3)
    b.shadow_from(t, dy=0.4)
    return {"": b, "_trim": t}


def d_noga(W, H, spr):
    # upright: knee at the top, ankle at the bottom, front to the right
    b = Layer(W, H)
    mask, lum = b.from_sprite(spr)
    b.fill(mask, GREY(0.84), height=2.4, bevel=W * 0.35)
    b.folds(lum, 0.7)
    for i in range(3):   # bloused trousers above the boot
        y = H * (0.72 + i * 0.07)
        b.carve(mask * b.band(y, y + 0.5), 0.3, 0.8, 0.25)
    b.noise(0.022, 0.6, 0.06, seed=51)
    b.camo(seed=551)
    t = Layer(W, H)
    pad = t.rrect(W * 0.48, -0.3, W * 1.0, H * 0.36, 2.4) * b.dilate(mask, 0.9)
    t.fill(pad, PAD, z=2.2, height=1.8, bevel=1.4, spec=0.5)
    t.carve(t.rrect(W * 0.58, H * 0.07, W * 0.92, H * 0.28, 1.4) - t.rrect(W * 0.61, H * 0.1, W * 0.89, H * 0.25, 1.2), 0.3, 0.7, 0.1)
    t.fill(t.band(H * 0.18, H * 0.25) * b.erode(mask, 0.2) * (1 - t.vband(W * 0.45, W)), WEB, z=2.3, height=0.5, bevel=0.25)
    t.noise(0.06, 0.3, 0.04, seed=52)
    b.shadow_from(t, dy=0.5)
    return {"": b, "_trim": t}


def d_stopa(W, H, spr):
    # boot (real colours) on the classic boot's silhouette: shaft at the back,
    # toe to the right, sole at the bottom
    b = Layer(W, H)
    mask, lum = b.from_sprite(spr, smooth=0.7)
    ys, xs = np.nonzero(mask > 0.5)
    x0, x1, y0, y1 = xs.min() / K, xs.max() / K, ys.min() / K, ys.max() / K
    bw, bh = x1 - x0, y1 - y0
    b.fill(mask, COYOTE, height=2.6, bevel=1.4)
    b.folds(lum, 0.4)
    b.fill(b.ell(x1 - bw * 0.16, y1 - bh * 0.24, bw * 0.2, bh * 0.17) * b.erode(mask, 0.4), COYOTE_D, z=2.0, height=0.8, bevel=0.9, spec=0.3)
    b.fill(b.rrect(x0 - 1, y0 - 1, x0 + bw * 0.6, y0 + bh * 0.1, 0.6) * mask, COYOTE_D, z=2.4, height=0.5, bevel=0.4)
    lx = x0 + bw * 0.43
    for i in range(4):
        y = y0 + bh * (0.2 + i * 0.12)
        b.fill(b.line([(lx - bw * 0.1, y), (lx + bw * 0.05, y + 0.4)], 0.5) * mask, WEB, z=2.6, height=0.3, bevel=0.2)
    sole = mask * b.band(y1 - bh * 0.17, y1 + 1)
    b.fill(sole, RUBBER, height=1.4, bevel=0.5)
    for i in range(7):
        x = x0 + 1.0 + i * bw / 7.0
        b.carve(b.rrect(x, y1 - bh * 0.07, x + bw * 0.06, y1 + 1, 0.2) * sole, 0.4, 0.5, 0.1)
    b.noise(0.05, 0.3, 0.05, seed=61)
    return {"": b}


def d_ramie(W, H, spr):
    # upright: shoulder at the top, elbow at the bottom
    b = Layer(W, H)
    mask, lum = b.from_sprite(spr)
    b.fill(mask, GREY(0.84), height=2.0, bevel=W * 0.3)
    b.folds(lum, 0.5)
    b.noise(0.022, 0.6, 0.05, seed=71)
    b.camo(seed=571)
    t = Layer(W, H)
    pad = t.ell(W * 0.5, H * 0.18, W * 0.62, H * 0.42) * b.dilate(mask, 0.8) * t.band(-1, H * 0.56)
    t.fill(pad, PAD, z=1.6, height=1.4, bevel=1.2, spec=0.45)
    t.carve(pad * t.band(H * 0.44, H * 0.5), 0.3, 0.7, 0.1)
    t.noise(0.05, 0.3, 0.03, seed=72)
    acc = Layer(W, H)
    acc.fill(pad * acc.band(H * 0.24, H * 0.42), GREY(1.0), height=0.2, bevel=0.1, emit=0.6)
    b.shadow_from(t, dy=0.6)
    return {"": b, "_trim": t, "_acc": acc}


def d_reka(W, H, spr):
    # upright: elbow at the top, wrist at the bottom (W is the forearm's width)
    b = Layer(W, H)
    mask, lum = b.from_sprite(spr)
    b.fill(mask, GREY(0.84), height=2.0, bevel=W * 0.32)
    b.folds(lum, 0.5)
    b.carve(mask * b.band(H * 0.55, H * 0.6), 0.3, 0.8, 0.2)    # pushed-up sleeve
    b.noise(0.022, 0.6, 0.05, seed=81)
    b.camo(seed=581)
    t = Layer(W, H)
    cuff = b.dilate(mask, 0.3) * t.band(H * 0.74, H + 1)
    t.fill(cuff, GLOVE, z=1.8, height=1.0, bevel=0.6)
    t.carve(cuff * t.band(H * 0.82, H * 0.85), 0.25, 0.7, 0.1)
    t.fill(b.dilate(mask, 0.4) * t.band(-1, H * 0.2), PAD, z=1.7, height=1.0, bevel=0.8, spec=0.35)  # elbow pad
    b.shadow_from(t, dy=0.4)
    return {"": b, "_trim": t}


def d_dlon(W, H, spr):
    # gloved fist (real colours)
    b = Layer(W, H)
    mask, _ = b.from_sprite(spr)
    cy_, cx_ = ndimage.center_of_mass(mask)
    zoom = 0.86
    mask = ndimage.affine_transform(mask, [1 / zoom, 1 / zoom], offset=[cy_ - cy_ / zoom * 1.0 + (1 / zoom - 1) * 0, cx_ - cx_ / zoom], order=1)
    b.fill(mask, GLOVE, height=2.2, bevel=W * 0.25)
    knuckle = b.ell(W * 0.62, H * 0.62, W * 0.34, H * 0.26) * b.erode(mask, 0.6)
    b.fill(knuckle, GLOVE_D, z=2.0, height=0.8, bevel=0.6, spec=0.35)
    b.carve(b.line([(W * 0.2, H * 0.36), (W * 0.8, H * 0.4)], 0.5) * mask, 0.3, 0.7, 0.12)
    b.noise(0.06, 0.3, 0.05, seed=91)
    return {"": b}


def d_morda(W, H, spr):
    # head upright facing right; keeps the classic face, adds headset + glasses
    b = Layer(W, H)
    mask, lum = b.from_sprite(spr, smooth=0.6)
    detail = np.clip(0.62 + (lum - ndimage.gaussian_filter(lum, 2.2 * K)) * 2.8, 0.2, 1.05)
    b.fill(mask, GREY(0.92), height=3.0, bevel=W * 0.3)
    b.alb *= detail[..., None]
    b.folds(lum, 0.5)
    t = Layer(W, H)
    # tactical glasses over the eye
    gl = t.poly([(W * 0.64, H * 0.39), (W * 0.93, H * 0.37), (W * 0.95, H * 0.47), (W * 0.68, H * 0.5)]) * b.dilate(mask, 0.6)
    t.fill(gl, LENS, z=3.0, height=0.6, bevel=0.3, spec=1.0)
    t.fill(t.line([(W * 0.66, H * 0.42), (W * 0.42, H * 0.44)], 0.6) * mask, HEADSET, z=3.0, height=0.3, bevel=0.2)
    # headset ear cup + mic boom
    t.fill(t.rrect(W * 0.39, H * 0.47, W * 0.54, H * 0.65, 1.2), HEADSET, z=3.2, height=1.3, bevel=0.8, spec=0.4)
    t.fill(t.line([(W * 0.5, H * 0.63), (W * 0.64, H * 0.74), (W * 0.78, H * 0.76)], 0.4), HEADSET, z=3.5, height=0.3, bevel=0.15)
    t.fill(t.ell(W * 0.79, H * 0.76, 0.6, 0.55), HEADSET, z=3.6, height=0.3, bevel=0.25)
    acc = Layer(W, H)
    acc.fill(acc.line([(W * 0.7, H * 0.405), (W * 0.9, H * 0.39)], 0.35) * gl, GREY(1.0), height=0.1, bevel=0.1, emit=0.35)
    b.shadow_from(t, dx=-0.4, dy=0.5, strength=0.35)
    return {"": b, "_trim": t, "_acc": acc}


def d_helm(W, H, spr):
    # ballistic helmet on the classic helmet's footprint (chin strap dropped):
    # wrap-around visor with a team-coloured glow slit, side rails, velcro
    # patch, IR strobe on the back
    b = Layer(W, H)
    mask, lum = b.from_sprite(spr, smooth=0.8)
    shell = mask * b.band(-1, H * 0.7)
    shell = np.clip(shell + b.ell(W * 0.46, H * 0.47, W * 0.4, H * 0.42) * b.band(-1, H * 0.66) * b.dilate(mask, 0.5), 0, 1)
    b.fill(shell, GREY(0.8), height=3.6, bevel=W * 0.22, spec=0.3)
    b.carve(b.line([(W * 0.12, H * 0.6), (W * 0.32, H * 0.56), (W * 0.66, H * 0.56)], 0.35) * shell, 0.35, 0.78, 0.12)
    b.carve(b.line([(W * 0.4, H * 0.08), (W * 0.36, H * 0.55)], 0.3) * shell, 0.25, 0.85, 0.12)
    b.noise(0.022, 0.6, 0.06, seed=101)
    t = Layer(W, H)
    # rail along the lower edge
    t.fill(t.line([(W * 0.1, H * 0.62), (W * 0.3, H * 0.6), (W * 0.62, H * 0.6)], 1.0) * b.dilate(shell, 0.3), HEADSET, z=3.4, height=0.8, bevel=0.35)
    # velcro patch on the side
    t.fill(t.rrect(W * 0.42, H * 0.24, W * 0.62, H * 0.38, 0.6), POUCH, z=3.8, height=0.35, bevel=0.3)
    # visor: dark glass wrapping the front, from the brow down past the eye
    vis = t.poly([(W * 0.6, H * 0.5), (W * 0.9, H * 0.46), (W * 1.0, H * 0.56), (W * 0.99, H * 0.78),
                  (W * 0.86, H * 0.86), (W * 0.62, H * 0.8)])
    t.fill(vis, LENS, z=3.6, height=1.4, bevel=0.9, spec=1.0)
    t.fill(t.line([(W * 0.6, H * 0.5), (W * 0.92, H * 0.46)], 1.0), HEADSET, z=4.2, height=0.6, bevel=0.3)   # visor hinge bar
    t.fill(t.ell(W * 0.62, H * 0.58, 1.1, 1.1), METAL, z=4.4, height=0.5, bevel=0.4, spec=0.9)               # pivot screw
    t.noise(0.04, 0.3, 0.03, seed=102)
    acc = Layer(W, H)
    acc.fill(acc.poly([(W * 0.66, H * 0.58), (W * 0.985, H * 0.565), (W * 0.985, H * 0.67), (W * 0.68, H * 0.7)]), GREY(1.0), height=0.2, bevel=0.15, emit=1.0)
    acc.fill(acc.rrect(W * 0.08, H * 0.3, W * 0.17, H * 0.38, 0.3) * b.dilate(shell, 0.4), GREY(1.0), height=0.2, bevel=0.1, emit=0.9)
    b.shadow_from(t, dx=-0.4, dy=0.5, strength=0.35)
    return {"": b, "_trim": t, "_acc": acc}


def d_kap(W, H, spr):
    # field cap, brim forward, headset over it
    b = Layer(W, H)
    crown = b.ell(W * 0.45, H * 0.52, W * 0.36, H * 0.34) * b.band(-1, H * 0.62)
    brim = b.poly([(W * 0.62, H * 0.5), (W * 0.98, H * 0.56), (W * 0.96, H * 0.64), (W * 0.6, H * 0.64)])
    band = b.rrect(W * 0.09, H * 0.52, W * 0.8, H * 0.64, 0.8)
    cap = np.clip(crown + brim + band, 0, 1)
    b.fill(cap, GREY(0.82), height=2.4, bevel=W * 0.16)
    b.carve(b.line([(W * 0.45, H * 0.2), (W * 0.47, H * 0.55)], 0.3) * crown, 0.25, 0.8, 0.1)
    b.carve(b.band(H * 0.55, H * 0.58) * cap, 0.25, 0.8, 0.1)
    b.noise(0.022, 0.6, 0.06, seed=111)
    t = Layer(W, H)
    t.fill(t.line([(W * 0.42, H * 0.15), (W * 0.46, H * 0.6)], 0.8), HEADSET, z=2.8, height=0.6, bevel=0.3)
    acc = Layer(W, H)
    acc.fill(acc.rrect(W * 0.6, H * 0.4, W * 0.72, H * 0.5, 0.3) * crown, GREY(1.0), height=0.2, bevel=0.1, emit=0.5)
    b.shadow_from(t, dx=-0.4, dy=0.5, strength=0.35)
    return {"": b, "_trim": t, "_acc": acc}


def d_jetpack(W, H, spr):
    # Drawn straight in sprite space: x runs down the back from the shoulder
    # (joint 10) toward the hip, y away from the back (0 = against it).
    b = Layer(W, H)
    b.fill(b.rrect(2.0, 0.5, 24.5, 5.5, 1.5), WEB, height=1.0, bevel=0.6)                       # back plate
    tb = b.rrect(4.0, 6.5, 22.0, 14.5, 3.8)
    b.fill(tb, (0.2, 0.21, 0.225), z=0.6, height=2.6, bevel=2.2, spec=0.7)                          # far tank
    ta = b.rrect(1.0, 3.0, 23.0, 11.6, 4.2)
    b.fill(ta, (0.25, 0.26, 0.275), z=1.0, height=3.2, bevel=2.6, spec=0.8)                         # near tank
    for x in (6.5, 16.5):
        b.fill(b.rrect(x, 2.2, x + 1.6, 12.2, 0.4), WEB, z=3.4, height=0.6, bevel=0.3)               # straps
    b.fill(b.poly([(22.0, 4.6), (24.2, 4.0), (27.0, 3.0), (27.0, 11.8), (24.2, 10.6), (22.0, 10.0)]), (0.36, 0.37, 0.39),
           z=1.0, height=2.0, bevel=1.0, spec=0.9)                                                  # nozzle
    b.carve(b.rrect(25.6, 4.0, 27.4, 10.8, 0.6), 1.0, 0.25, 0.15)                                   # nozzle mouth
    b.fill(b.ell(1.4, 7.0, 1.4, 1.3), METAL, z=3.0, height=0.8, bevel=0.5, spec=0.9)                # valve
    b.carve(b.band(10.6, 11.0) * ta, 0.3, 0.7, 0.15)
    acc = Layer(W, H)
    acc.fill(acc.rrect(9.5, 8.6, 13.5, 10.2, 0.5), GREY(1.0), height=0.2, bevel=0.1, emit=0.9)     # status strip
    return {"": b, "_acc": acc}


# name -> (design fn, frame) ; frame: "id" | "head" | "limb"
PARTS = {
    "klata": (d_klata, "id"),
    "kamizelka": (d_kamizelka, "id"),
    "biodro": (d_biodro, "id"),
    "udo": (d_udo, "limb"),
    "noga": (d_noga, "limb"),
    "stopa": (d_stopa, "id"),
    "ramie": (d_ramie, "limb"),
    "reka": (d_reka, "limb"),
    "dlon": (d_dlon, "limb"),
    "morda": (d_morda, "head"),
    "helm": (d_helm, "head"),
    "kap": (d_kap, "head"),
    "jetpack": (d_jetpack, "jp"),
}
SIZES = {"jetpack": (27, 15)}   # parts with no classic sprite (classic px)
LIGHTS = {"jp": np.array([-0.62, -0.45, 0.64]) / np.linalg.norm([-0.62, -0.45, 0.64])}


def to_design(spr, frame):
    if frame == "head":
        return spr.rotate(90, expand=True)
    if frame == "limb":
        return spr.rotate(-90, expand=True)
    return spr


def to_sprite(im, frame):
    if frame == "head":
        return im.rotate(-90, expand=True)
    if frame == "limb":
        return im.rotate(90, expand=True)
    return im


def build(name):
    fn, frame = PARTS[name]
    out = {}
    for mirror in (False, True):
        if name in SIZES:
            spr = Image.new("RGBA", SIZES[name], (0, 0, 0, 0))
        else:
            spr = orig(name + ("2" if mirror else "")) or orig(name)
        flipped_src = mirror and name not in SIZES and orig(name + "2") is not None
        if flipped_src:
            spr = spr.transpose(Image.FLIP_TOP_BOTTOM)   # undo the classic mirror -> right-facing art
        d = to_design(spr, frame)
        W, H = d.size
        layers = fn(W, H, d)
        for suffix, layer in layers.items():
            im = layer.render(light=LIGHTS.get(frame, LIGHT))
            if im is None:
                continue
            im = to_sprite(im, frame)
            exp = (spr.width * HD, spr.height * HD)
            if im.size != exp:
                im = im.resize(exp, Image.LANCZOS)
            if mirror:
                im = im.transpose(Image.FLIP_TOP_BOTTOM)
            out[name + suffix + ("2" if mirror else "")] = im
    return out


def main():
    sheet = None
    if "--sheet" in sys.argv:
        sheet = sys.argv[sys.argv.index("--sheet") + 1]
    only = [a for a in sys.argv[1:] if a in PARTS]
    os.makedirs(OUT, exist_ok=True)
    made = {}
    for name in (only or PARTS):
        imgs = build(name)
        for k, im in imgs.items():
            path = os.path.join(OUT, k + ".png")
            im.save(path, optimize=True)
            # The sprites are minified 3-9x on screen: they must import with
            # mipmaps (gate F sart checks). New files get an .import on the
            # next editor / --import run; re-run this script to patch it.
            imp = path + ".import"
            if os.path.exists(imp):
                txt = open(imp).read()
                if "mipmaps/generate=false" in txt:
                    open(imp, "w").write(txt.replace("mipmaps/generate=false", "mipmaps/generate=true"))
        made.update(imgs)
        print("operator gfx: %-10s %s" % (name, " ".join(sorted(imgs))))
    if sheet:
        ims = [made[k] for k in sorted(made) if not k.endswith("2")]
        S = 3
        W = sum(i.width * S + 12 for i in ims) + 12
        H = max(i.height * S for i in ims) + 24
        sh = Image.new("RGBA", (W, H), (70, 80, 90, 255))
        x = 12
        for i in ims:
            sh.alpha_composite(i.resize((i.width * S, i.height * S), Image.NEAREST), (x, 12))
            x += i.width * S + 12
        sh.save(sheet)


if __name__ == "__main__":
    main()
