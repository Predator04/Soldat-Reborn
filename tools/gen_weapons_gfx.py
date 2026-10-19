#!/usr/bin/env python3
"""Paint the HD weapon sprites (#284) into assets/weapons-hd/.

Every weapon (and the frag / cluster belt grenades) gets a new sprite at
exactly 6x the pixel size of its classic assets/weapons-gfx/ sprite, laid out
on the classic silhouette, so the game draws it into the classic rect
(classic size * Gostek.SPRITE_SCALE) with the classic grip pivot: barrel
length, muzzle position and bullet spawn do not move by a pixel.

Same approach as the first Operator soldier generator (#280): parts are
vector shapes on an 18x supersampled canvas (one design unit = one classic
sprite pixel), each with a material (gunmetal, polymer, wood, brass ...) and
its surface finish (cerakote mottle, machined edge wear with bright chips,
fine scratches, wood grain + pores, moulded stippling, woven nylon, brass
tarnish), extruded into a height field (bevels, cylinders, grooves, rails,
vents, knurling, stamped markings, pins, rivets), lit with one key light +
specular + ambient occlusion + a two-tone studio bounce, inked (a thin dark
line inside every part and a dark silhouette outline), then downsampled to
6x. Next to each sprite goes <name>_n.png, the height field's normal map
(OpenGL convention: +x right = red, +y UP = green, alpha = coverage), which
the dynamic lights (#282) use through weapon_gfx.gd's CanvasTexture.

Albedo is mid-grey metal rather than near-black so the weapon skins
(Custom.WEAPON_SKINS, multiplied in, some channels > 1) read; the grenades
ride the belt untinted and use their real colours.

Deterministic: same files on every run. Edit the w_<name> design functions,
never the PNGs.

  python3 tools/gen_weapons_gfx.py               # write assets/weapons-hd/
  python3 tools/gen_weapons_gfx.py ak74 mp5      # only these
  python3 tools/gen_weapons_gfx.py --sheet F.png # also a classic | HD sheet
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "weapons-gfx")
OUT = os.path.join(ROOT, "assets", "weapons-hd")
HD = 6          # output pixels per classic sprite pixel ("ultra HD", #284 follow-up)
SS = 3          # supersampling on top of that
K = HD * SS     # canvas pixels per design unit
LIGHT = np.array([0.5, -0.68, 0.55])
LIGHT = LIGHT / np.linalg.norm(LIGHT)
FONT = os.path.join(ROOT, "assets", "fonts", "BarlowCondensed-Bold.ttf")

# Materials: albedo (0..1), specular strength, gloss exponent, surface finish.
#   brush:   anisotropic streaks along the long axis (machined metal)
#   grit:    fine isotropic stipple in albedo + height (polymer, parkerizing)
#   cera:    cerakote-like orange-peel mottle on painted / coated metal
#   grain:   wood grain (rings, fibres, pores) along the long axis
#   wear:    bright chipped edges + scattered chips showing bare steel
#   scuff:   lighter rubbed edges on polymer / rubber
#   scratch: fine bright scratches
#   stip:    moulded stippling (grips, pads)
#   tarnish: dull mottled patches (brass, copper)
#   metal:   how much the specular takes the albedo colour (brass, gold)
MAT = {
    "gun":    dict(col=(0.335, 0.345, 0.375), spec=0.85, gloss=22, brush=0.03, cera=0.03, wear=0.9, scratch=0.32),
    "dark":   dict(col=(0.23, 0.235, 0.25), spec=0.7, gloss=20, brush=0.02, cera=0.04, wear=0.75, scratch=0.28),
    "steel":  dict(col=(0.52, 0.53, 0.56), spec=1.0, gloss=26, brush=0.06, wear=0.35, scratch=0.25),
    "chrome": dict(col=(0.66, 0.67, 0.70), spec=1.1, gloss=30, brush=0.05, scratch=0.22, wear=0.25),
    "blade":  dict(col=(0.74, 0.76, 0.79), spec=1.2, gloss=40, brush=0.08, scratch=0.25),
    "poly":   dict(col=(0.22, 0.22, 0.235), spec=0.35, gloss=10, grit=0.035, scuff=0.5, scratch=0.12),
    "grip":   dict(col=(0.21, 0.21, 0.225), spec=0.3, gloss=9, grit=0.03, scuff=0.45, stip=1.0),
    "rubber": dict(col=(0.17, 0.17, 0.18), spec=0.14, gloss=6, grit=0.05, stip=0.7, scuff=0.3),
    "od":     dict(col=(0.37, 0.40, 0.27), spec=0.3, gloss=10, grit=0.02, cera=0.06, wear=0.7, scratch=0.2),
    "od_d":   dict(col=(0.28, 0.31, 0.21), spec=0.28, gloss=10, grit=0.02, cera=0.06, wear=0.6, scratch=0.2),
    "od_g":   dict(col=(0.30, 0.33, 0.22), spec=0.26, gloss=9, grit=0.02, stip=1.0, scuff=0.4),
    "tan":    dict(col=(0.54, 0.46, 0.34), spec=0.2, gloss=8, grit=0.05, weave=1.0),
    "wood":   dict(col=(0.62, 0.34, 0.15), spec=0.45, gloss=14, grain=0.26, scratch=0.12),
    "walnut": dict(col=(0.47, 0.26, 0.13), spec=0.5, gloss=16, grain=0.3, scratch=0.12),
    "plum":   dict(col=(0.42, 0.21, 0.16), spec=0.4, gloss=14, grit=0.02, scuff=0.45, scratch=0.15),
    "plum_g": dict(col=(0.40, 0.20, 0.15), spec=0.35, gloss=12, grit=0.02, stip=1.0, scuff=0.4),
    "brass":  dict(col=(0.82, 0.62, 0.28), spec=1.1, gloss=26, metal=0.7, tarnish=0.55, brush=0.03),
    "copper": dict(col=(0.74, 0.43, 0.25), spec=1.0, gloss=24, metal=0.6, tarnish=0.5),
    "red":    dict(col=(0.76, 0.17, 0.10), spec=0.65, gloss=18, cera=0.035, wear=0.55, scratch=0.18),
    "orange": dict(col=(0.88, 0.43, 0.10), spec=0.6, gloss=18, cera=0.03),
    "lens":   dict(col=(0.10, 0.17, 0.24), spec=1.4, gloss=50),
    "string": dict(col=(0.80, 0.78, 0.72), spec=0.3, gloss=12, grit=0.04),
    "frag":   dict(col=(0.38, 0.54, 0.18), spec=0.55, gloss=16, cera=0.06, wear=0.6, scratch=0.2),
    "yellow": dict(col=(0.88, 0.68, 0.14), spec=0.6, gloss=18, cera=0.05, wear=0.55, scratch=0.2),
}
BARE = np.array((0.60, 0.61, 0.635), np.float32)    # steel showing through worn edges (mid-tone: skins still tint)


class Base:
    """Mask helpers in design space (W x H units, y down) on a K x canvas
    (the approach of the first Operator generator, #280)."""

    def __init__(self, W, H):
        self.W, self.H = W, H
        self.w, self.h = int(round(W * K)), int(round(H * K))
        self.alb = np.zeros((self.h, self.w, 3), np.float32)
        self.a = np.zeros((self.h, self.w), np.float32)
        self.z = np.zeros((self.h, self.w), np.float32)
        self.spec = np.zeros((self.h, self.w), np.float32)

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

    def folds(self, lum, amount=0.9):
        """Soft fold relief from the classic sprite's shading."""
        l = lum - ndimage.gaussian_filter(lum, 2.5 * K)
        self.z += l * amount * 6.0 * (self.a > 0.01)



class W(Base):
    """A weapon sprite in design space (one unit = one classic sprite pixel,
    y down, muzzle toward +x). Adds per-material gloss and surface finish
    (wear, scratches, cerakote, grain, stippling, tarnish), explicit height
    maps (cylinders), part inking and engraved markings to the Operator Layer."""

    def __init__(self, Wd, Hd, seed=1, axis="x"):
        super().__init__(Wd, Hd)
        self.axis = axis
        self.gloss = np.full((self.h, self.w), 20.0, np.float32)
        self.metal = np.zeros((self.h, self.w), np.float32)
        self.X = ((np.arange(self.w) + 0.5) / K)[None, :].repeat(self.h, 0).astype(np.float32)
        self.Y = ((np.arange(self.h) + 0.5) / K)[:, None].repeat(self.w, 1).astype(np.float32)
        rng = np.random.default_rng(seed)
        self.rng = rng

        def al(a, b):   # (sigma along the short axis, sigma along the long axis)
            return (a * K, b * K) if axis == "x" else (b * K, a * K)

        def field(sig):
            n = ndimage.gaussian_filter(rng.standard_normal((self.h, self.w)).astype(np.float32), sig)
            return n / max(1e-6, float(n.std()))
        self.f_brush = field(al(0.05, 2.0))
        self.f_grit = field(0.06 * K)
        self.f_fine = field(0.09 * K)
        self.f_mottle = field(0.6 * K)
        self.f_chip = field(0.1 * K)
        self.f_tarnish = field(0.8 * K)
        rings = np.sin(field(al(0.4, 7.0)) * 3.0 + (self.Y if axis == "x" else self.X) * 2.3)
        fibres = field(al(0.035, 1.8))
        self.f_pore = np.clip(field(al(0.05, 0.45)) - 1.7, 0, 1.5)
        self.f_grain = rings * 0.5 + fibres * 0.32 + self.f_mottle * 0.12 - self.f_pore * 0.9
        # fine scratches, mostly along the weapon's long axis
        im = Image.new("L", (self.w, self.h), 0)
        dr = ImageDraw.Draw(im)
        for _ in range(int(Wd * Hd / 9)):
            x, y = rng.uniform(0, self.w), rng.uniform(0, self.h)
            a = rng.normal(0, 0.3) + (0 if axis == "x" else math.pi / 2) + (math.pi / 2 if rng.uniform() < 0.12 else 0)
            ln = rng.uniform(0.3, 2.6) * K
            dr.line([(x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln)], fill=int(rng.uniform(70, 255)),
                    width=1 if rng.uniform() < 0.6 else 2)
        self.f_scratch = ndimage.gaussian_filter(np.asarray(im, np.float32) / 255.0, 0.35)
        # moulded stipple: a hex field of little bumps, slightly jittered
        p = 0.42
        u = self.X / p
        v = self.Y / (p * 0.866)
        self.f_stip = np.clip(np.cos(u * 2 * np.pi + (np.floor(v) % 2) * np.pi) * np.cos(v * 2 * np.pi) * 0.5 + 0.5
                              + self.f_grit * 0.12, 0, 1)
        # woven nylon (pouches): two crossing fine ridges
        self.f_weave = (np.sin((self.X + self.Y) * 2 * np.pi / 0.28) * np.sin((self.X - self.Y) * 2 * np.pi / 0.28)) * 0.5 + 0.5
        self._font = {}

    # ── painting ──
    def put(self, m, mat, z=0.0, h=1.0, bevel=0.6, zmap=None, ink=0.55, ink_w=0.2, col=None, tex=1.0, dome=0.7, rnd=0.0):
        """Paint mask `m` in material `mat`: a slab `h` high over `z` with
        rounded edges `bevel` wide (or the explicit height map `zmap`). The
        slab's top is gently domed across its height (`dome`) so every part
        catches the key light on its upper half and falls off below. `rnd`
        rounds the outline's corners (units) for organic shapes (stocks).
        The material's finish (wear, scratches, grain ...) is applied here."""
        m = np.clip(m, 0, 1).astype(np.float32)
        if rnd > 0:
            sig = rnd * K * 0.5
            m = np.clip((ndimage.gaussian_filter(m, sig) - 0.5) * sig * 1.7 + 0.5, 0, 1)
        if m.max() <= 0:
            return m
        M = MAT[mat]
        d = ndimage.distance_transform_edt(m > 0.5) / K
        if zmap is None:
            prof = np.clip(d / max(bevel, 0.01), 0, 1)
            zz = z + prof * prof * (3 - 2 * prof) * h
            rows = np.nonzero((m > 0.5).any(axis=1))[0]
            if dome > 0 and len(rows) > 1:
                cy = (rows[0] + rows[-1] + 1) * 0.5 / K
                hy = max(0.3, (rows[-1] - rows[0] + 1) * 0.5 / K)
                zz = zz + dome * min(1.0, hy / 2.0) * np.clip(1 - ((self.Y - cy) / hy) ** 2, 0, 1) * prof
        else:
            zz = zmap.copy()
        c = np.array(col if col is not None else M["col"], np.float32).reshape(1, 1, 3)
        g = lambda k: M.get(k, 0.0) * tex
        mul = np.ones((self.h, self.w), np.float32)
        mul += self.f_brush * g("brush") + self.f_grit * g("grit") + self.f_grain * g("grain")
        mul += self.f_fine * g("cera") + self.f_mottle * g("cera") * 0.5
        zz += self.f_grit * g("grit") * 0.1 + self.f_fine * g("cera") * 0.035 + self.f_brush * g("brush") * 0.01
        zz -= self.f_pore * g("grain") * 0.12
        inner = np.clip((d - 0.3) / 0.15, 0, 1)
        if g("stip"):
            zz += (self.f_stip - 0.5) * 0.09 * g("stip") * inner
            mul *= 1 - (1 - self.f_stip) * 0.22 * g("stip") * inner
        if g("weave"):
            zz += (self.f_weave - 0.5) * 0.05 * inner
            mul *= 1 - (1 - self.f_weave) * 0.16 * inner
        alb = c * mul[..., None]
        spec = np.full((self.h, self.w), M["spec"], np.float32)
        if g("tarnish"):
            t = np.clip(self.f_tarnish * 0.35 + 0.3 + self.f_fine * 0.08, 0, 1) * g("tarnish")
            alb = alb * (1 - t[..., None]) + alb * np.array([0.6, 0.62, 0.48], np.float32) * t[..., None]
            spec *= 1 - t * 0.6
        if g("grain"):
            alb *= (1 - 0.22 * np.clip(1 - d / 0.9, 0, 1) * (0.6 + 0.4 * self.f_mottle.clip(-1, 1)))[..., None]   # handled edges
        if g("wear"):
            band = np.clip(1 - np.abs(d - 0.3) / 0.22, 0, 1)
            chip = np.clip((self.f_chip + 0.8 * self.f_mottle - 0.55) * 2.2, 0, 1)
            spot = np.clip((self.f_chip - 2.2) * 3.0, 0, 1) * np.clip(self.f_mottle + 0.5, 0, 1)
            wm = np.clip(band * chip * 1.2 + spot * 0.7, 0, 1) * g("wear")
            alb = alb * (1 - wm[..., None]) + BARE * wm[..., None]
            spec += wm * 0.5
            zz -= wm * 0.05
        if g("scuff"):
            band = np.clip(1 - np.abs(d - 0.25) / 0.2, 0, 1)
            sc = band * np.clip(self.f_chip * 0.5 + self.f_mottle * 0.6, 0, 1) * g("scuff")
            alb *= (1 + sc * 0.5)[..., None]
        if g("scratch"):
            s = self.f_scratch * g("scratch") * inner
            alb = alb + (s * 0.55)[..., None] * (BARE - alb * 0.5)
            spec += s * 0.6
        if ink > 0:
            alb *= (1 - ink * np.clip(1 - d / ink_w, 0, 1))[..., None]
        mm = m[..., None]
        self.alb = self.alb * (1 - mm) + alb * mm
        self.z = self.z * (1 - m) + zz * m
        self.spec = self.spec * (1 - m) + spec * m
        self.gloss = self.gloss * (1 - m) + M["gloss"] * m
        self.metal = self.metal * (1 - m) + M.get("metal", 0.0) * m
        self.a = np.maximum(self.a, m)
        return m

    def cylx(self, x0, x1, yc, r, mat, z=0.0, h=None, cap=0.35, **kw):
        """Horizontal cylinder (barrels, tubes) with a round cross-section."""
        m = self.rrect(x0, yc - r, x1, yc + r, min(r, cap))
        t = np.clip((self.Y - yc) / r, -1, 1)
        hh = r * 1.6 if h is None else h
        zmap = z + hh * np.sqrt(np.clip(1 - t * t, 0, 1)) ** 0.8
        return self.put(m, mat, zmap=zmap, **kw)

    def cyly(self, y0, y1, xc, r, mat, z=0.0, h=None, cap=0.35, **kw):
        m = self.rrect(xc - r, y0, xc + r, y1, min(r, cap))
        t = np.clip((self.X - xc) / r, -1, 1)
        hh = r * 1.6 if h is None else h
        zmap = z + hh * np.sqrt(np.clip(1 - t * t, 0, 1)) ** 0.8
        return self.put(m, mat, zmap=zmap, **kw)

    def ball(self, cx, cy, rx, ry, mat, z=0.0, h=None, **kw):
        m = self.ell(cx, cy, rx, ry)
        t = ((self.X - cx) / rx) ** 2 + ((self.Y - cy) / ry) ** 2
        hh = min(rx, ry) * 1.4 if h is None else h
        zmap = z + hh * np.sqrt(np.clip(1 - t, 0, 1))
        return self.put(m, mat, zmap=zmap, **kw)

    def groove(self, pts, w=0.35, depth=0.5, dark=0.55):
        self.carve(self.line(pts, w), depth, dark, 0.05)

    def slot(self, x0, y0, x1, y1, r=None, depth=0.7, dark=0.4):
        rr = min(x1 - x0, y1 - y0) * 0.5 if r is None else r
        self.carve(self.rrect(x0, y0, x1, y1, rr), depth, dark, 0.05)

    def hole(self, cx, cy, r, depth=0.8, dark=0.25):
        self.carve(self.ell(cx, cy, r, r), depth, dark, 0.04)

    def _zat(self, x, y):
        return float(self.z[min(self.h - 1, max(0, int(y * K))), min(self.w - 1, max(0, int(x * K)))])

    def screw(self, cx, cy, r=0.45, mat="steel", z=None):
        zz = self._zat(cx, cy) if z is None else z
        self.carve(self.ell(cx, cy, r * 1.25, r * 1.25), 0.08, 0.6, 0.03)           # counterbore shadow
        self.ball(cx, cy, r, r, mat, z=zz, h=r * 0.6, ink=0.5, ink_w=0.1, tex=0.5)
        self.carve(self.rrect(cx - r * 0.75, cy - 0.06, cx + r * 0.75, cy + 0.06, 0.04), 0.15, 0.45, 0.02)

    def pin(self, cx, cy, r=0.36, mat="steel"):
        """Flush cross pin (trigger / hammer pins)."""
        zz = self._zat(cx, cy)
        self.put(self.ell(cx, cy, r, r), mat, z=zz, h=0.05, bevel=0.08, ink=0.6, ink_w=0.08, dome=0.0, tex=0.4)

    def rivets(self, pts, r=0.34):
        for x, y in pts:
            zz = self._zat(x, y)
            self.ball(x, y, r, r, "steel", z=zz, h=0.12, ink=0.45, ink_w=0.08, tex=0.4)

    def stamp(self, text, x, y, size=1.0, depth=0.14, dark=0.32):
        """Engraved / stamped marking (model, calibre, serial). (x, y) = top-left."""
        px = max(6, int(size * 1.2 * K))
        if px not in self._font:
            self._font[px] = ImageFont.truetype(FONT, px)
        im = Image.new("L", (self.w, self.h), 0)
        ImageDraw.Draw(im).text((x * K, y * K), text, font=self._font[px], fill=255)
        m = np.asarray(im, np.float32) / 255.0
        self.carve(m, depth, dark, 0.02)
        # the stamp's lower lip catches a little light
        self.alb += (np.clip(ndimage.shift(m, (0.07 * K, 0.05 * K), order=1) - m, 0, 1) * 0.08)[..., None] * (self.a > 0.01)[..., None]

    def stencil(self, text, x, y, size, col, amount=0.85):
        """Painted stencil marking, a little worn."""
        px = max(6, int(size * 1.2 * K))
        if px not in self._font:
            self._font[px] = ImageFont.truetype(FONT, px)
        im = Image.new("L", (self.w, self.h), 0)
        ImageDraw.Draw(im).text((x * K, y * K), text, font=self._font[px], fill=255)
        m = np.asarray(im, np.float32) / 255.0 * (self.a > 0.01)
        m *= np.clip(1.4 - np.clip(self.f_chip - 0.8, 0, 9) * 0.8, 0, 1) * amount
        lum = self.alb.mean(axis=2, keepdims=True) / 0.3
        self.alb = self.alb * (1 - m[..., None]) + np.array(col, np.float32) * np.clip(lum, 0.6, 1.3) * m[..., None]

    def plate(self, x0, y0, x1, y1, text="", size=0.8, mat="steel"):
        """Small riveted serial / data plate."""
        zz = self._zat((x0 + x1) * 0.5, (y0 + y1) * 0.5)
        self.put(self.rrect(x0, y0, x1, y1, 0.25), mat, z=zz, h=0.12, bevel=0.1, ink_w=0.1, dome=0.0, tex=0.6)
        if text:
            self.stamp(text, x0 + 0.45, y0 + (y1 - y0 - size) * 0.42, size, 0.06, 0.55)

    def knurl(self, m, pitch=0.42, amp=0.08):
        """Diamond knurling (metal grips, knobs, rings)."""
        u = (self.X + self.Y) * 2 * np.pi / pitch
        v = (self.X - self.Y) * 2 * np.pi / pitch
        k = (np.abs(np.sin(u * 0.5)) * np.abs(np.sin(v * 0.5)))
        m = np.clip(m, 0, 1) * (self.a > 0.01)
        self.z += (k - 0.5) * amp * m
        self.alb *= (1 - (1 - k) * 0.25 * m)[..., None]

    def rail(self, x0, x1, y, mat="dark", z=1.0, h=1.0, pitch=1.05, tooth=0.55, height=1.0):
        """Picatinny rail along y (top at y - height)."""
        base = self.rrect(x0, y - height * 0.45, x1, y, 0.12)
        self.put(base, mat, z=z, h=h * 0.7, bevel=0.2, ink_w=0.14)
        x = x0 + 0.35
        while x + tooth < x1 - 0.2:
            self.put(self.rrect(x, y - height, x + tooth, y - height * 0.3, 0.1), mat, z=z, h=h, bevel=0.15, ink=0.5, ink_w=0.12)
            x += pitch

    def ribs(self, x0, x1, y0, y1, pitch=1.0, w=0.35, depth=0.4, dark=0.6):
        x = x0
        while x < x1:
            self.carve(self.rrect(x, y0, x + w, y1, w * 0.5), depth, dark, 0.04)
            x += pitch

    def hribs(self, y0, y1, x0, x1, pitch=1.0, w=0.35, depth=0.4, dark=0.6):
        y = y0
        while y < y1:
            self.carve(self.rrect(x0, y, x1, y + w, w * 0.5), depth, dark, 0.04)
            y += pitch

    # ── output ──
    def render2(self, light=LIGHT, ambient=0.46, diffuse=0.66, outline=0.86, ao=0.6):
        """-> (sprite RGBA, normal map RGBA) at HD x the design size."""
        zs = ndimage.gaussian_filter(self.z, 0.07 * K)
        gy, gx = np.gradient(zs)
        n = np.dstack([-gx * K * 0.85, -gy * K * 0.85, np.ones_like(zs)])
        n /= np.linalg.norm(n, axis=2, keepdims=True)
        lam = np.clip((n * light).sum(axis=2), 0, 1)
        # soft wrap fill from below-behind so shadow sides keep some form
        fill = np.clip((n * np.array([-0.3, 0.6, 0.74])).sum(axis=2), 0, 1) * 0.12
        hv = light + np.array([0, 0, 1.0])
        hv /= np.linalg.norm(hv)
        nh = np.clip((n * hv).sum(axis=2), 0, 1)
        sp = nh ** self.gloss * self.spec
        # broad sheen (cheap env reflection) so metal reads as metal at 1x
        sheen = nh ** (self.gloss * 0.18) * self.spec * 0.12
        occ = np.clip((ndimage.gaussian_filter(self.z, 1.1 * K) - self.z) * 0.55, 0, 1) * ao
        # tight contact occlusion in creases (seams, under parts)
        occ = np.clip(occ + np.clip((ndimage.gaussian_filter(self.z, 0.25 * K) - self.z) * 0.9, 0, 1) * 0.5, 0, 1)
        shade = (ambient + diffuse * lam + fill) * (1 - occ)
        scol = 1 - self.metal[..., None] + self.metal[..., None] * self.alb / np.maximum(self.alb.max(axis=2, keepdims=True), 1e-3)
        rgb = self.alb * shade[..., None] + (sp + sheen)[..., None] * scol * (1 - occ[..., None] * 0.7)
        # two-tone studio bounce: cool from above, warm from the ground
        up = np.clip(-n[..., 1], 0, 1)[..., None]
        dn = np.clip(n[..., 1], 0, 1)[..., None]
        rgb += self.alb * (up * np.array([0.05, 0.07, 0.11]) + dn * np.array([0.08, 0.055, 0.03])) * (1 - occ[..., None])
        # studio rim: a bright line just inside the silhouette's lit (top)
        # edges, then the thin dark outline all round
        a1 = ndimage.shift(self.a, (0.36 * K, 0), order=1)
        a2 = ndimage.shift(self.a, (0.85 * K, 0), order=1)
        rim = np.clip(self.a * ((1 - a2) - (1 - a1)), 0, 1)
        rim = ndimage.gaussian_filter(rim, 0.06 * K)
        rgb += (rim * (0.1 + 0.22 * np.clip(self.spec, 0, 1)))[..., None] * scol
        inner = ndimage.grey_erosion(self.a, size=max(1, int(0.36 * K)))
        edge = np.clip(self.a - inner, 0, 1)
        rgb *= (1 - outline * edge)[..., None]
        a = self.a
        size = (self.w // SS, self.h // SS)
        prem = np.dstack([np.clip(rgb, 0, 1) * a[..., None], a[..., None]])
        im = Image.fromarray((prem * 255).astype(np.uint8), "RGBA").resize(size, Image.LANCZOS)
        arr = np.asarray(im, np.float32) / 255.0
        al = arr[..., 3:4]
        rgb = np.where(al > 1e-4, arr[..., :3] / np.maximum(al, 1e-4), 0)
        sprite = Image.fromarray((np.dstack([np.clip(rgb, 0, 1), np.clip(al, 0, 1)]) * 255).round().astype(np.uint8), "RGBA")
        # normal map: average the coverage-weighted normals per output pixel
        nw = n * a[..., None]
        nd = np.dstack([nw, a[..., None]]).reshape(size[1], SS, size[0], SS, 4).mean(axis=(1, 3))
        cov = nd[..., 3:4]
        nv = np.where(cov > 1e-4, nd[..., :3] / np.maximum(cov, 1e-4), np.array([0, 0, 1.0]))
        nv /= np.maximum(np.linalg.norm(nv, axis=2, keepdims=True), 1e-6)
        enc = np.dstack([nv[..., 0] * 0.5 + 0.5, -nv[..., 1] * 0.5 + 0.5, nv[..., 2] * 0.5 + 0.5, np.clip(cov[..., 0], 0, 1)])
        normal = Image.fromarray((np.clip(enc, 0, 1) * 255).round().astype(np.uint8), "RGBA")
        return sprite, normal


def bend(p0, d0, length, turn, w0, w1, steps=24):
    """Polygon of a curved strip (magazines): centre line from p0 heading d0
    (radians, 0 = +x, pi/2 = down), turning `turn` radians over `length`,
    width w0 -> w1. Returns (left edge + reversed right edge) points."""
    pts_l, pts_r = [], []
    x, y = p0
    for i in range(steps + 1):
        t = i / steps
        a = d0 + turn * t
        w = (w0 + (w1 - w0) * t) * 0.5
        nx, ny = -math.sin(a), math.cos(a)
        pts_l.append((x - nx * w, y - ny * w))
        pts_r.append((x + nx * w, y + ny * w))
        x += math.cos(a) * length / steps
        y += math.sin(a) * length / steps
    return pts_l + pts_r[::-1]


# ─────────────────────────────── weapon designs ──────────────────────────────
# Each w_<name>(L) paints onto L (design units = classic pixels). Coordinates
# follow the classic sprite's silhouette so the HD art sits where the old art
# did in the soldier's hands.


def w_ak74(L):
    # wooden stock
    L.put(L.poly([(1.2, 3.1), (13.0, 3.1), (15.4, 4.2), (23.6, 3.9), (23.8, 10.4), (17.0, 11.3),
                  (12.6, 13.0), (8.0, 14.2), (1.2, 15.0)]), "wood", h=2.2, bevel=1.6, rnd=0.8)
    L.groove([(2.5, 9.6), (12.5, 8.9), (21.5, 7.9)], 0.22, 0.25, 0.8)
    L.put(L.rrect(0.2, 2.8, 1.7, 15.3, 0.5), "dark", z=0.3, h=1.9, bevel=0.5)          # butt plate
    L.ribs(0.45, 1.5, 4.0, 14.5, 0.6, 0.18, 0.2, 0.7)
    # receiver
    L.put(L.poly([(22.6, 3.4), (46.5, 3.4), (46.5, 9.6), (40.5, 10.8), (24.0, 11.0), (22.6, 10.2)]), "gun", z=0.4, h=2.2, bevel=0.8)
    L.put(L.rrect(23.2, 1.9, 47.6, 4.4, 1.1), "gun", z=1.3, h=1.6, bevel=0.9)              # dust cover
    L.groove([(23.6, 4.5), (46.2, 4.5)], 0.22, 0.4, 0.5)
    for x in (27.5, 41.0):
        L.groove([(x, 2.2), (x, 4.1)], 0.18, 0.3, 0.6)
    L.slot(33.8, 5.0, 42.6, 6.6, 0.25, 0.9, 0.18)                                           # ejection port
    L.cylx(35.2, 41.6, 5.8, 0.55, "brass", z=0.6, h=0.6, ink=0.4)                           # case in the port
    L.put(L.line([(25.0, 6.0), (31.0, 5.5), (37.5, 7.6)], 0.55), "steel", z=2.6, h=0.6, bevel=0.25, ink_w=0.12)  # selector
    for x, y in ((24.6, 9.0), (28.0, 9.4), (44.6, 8.4), (44.6, 5.2)):
        L.screw(x, y, 0.38)
    # rear sight
    L.put(L.poly([(37.0, 2.6), (38.8, 0.4), (44.2, 0.3), (48.4, 1.6), (48.4, 2.7)]), "dark", z=1.8, h=1.2, bevel=0.4)
    L.slot(40.0, 0.9, 44.0, 1.5, 0.2, 0.3, 0.6)
    # gas tube + handguards
    L.cylx(46.8, 61.6, 2.7, 0.8, "dark", z=1.2)
    L.put(L.rrect(49.6, 2.8, 60.4, 5.0, 1.0), "wood", z=1.6, h=1.6, bevel=0.9)
    L.put(L.rrect(48.4, 4.8, 60.6, 9.4, 1.2), "wood", z=1.0, h=2.2, bevel=1.1)
    L.ribs(50.4, 59.4, 5.6, 8.6, 1.5, 0.5, 0.35, 0.6)
    L.put(L.rrect(47.2, 2.0, 49.4, 9.8, 0.4), "gun", z=1.6, h=1.6, bevel=0.4)
    L.put(L.rrect(60.0, 2.0, 62.2, 9.4, 0.4), "gun", z=1.6, h=1.6, bevel=0.4)
    # barrel, gas block, front sight, cleaning rod
    L.cylx(61.0, 77.5, 7.1, 0.95, "gun", z=0.8)
    L.cylx(62.0, 76.0, 8.85, 0.38, "steel", z=0.6)
    L.put(L.poly([(61.6, 2.4), (66.2, 2.4), (67.4, 4.0), (67.4, 8.2), (61.6, 8.2)]), "gun", z=1.2, h=1.6, bevel=0.6)
    L.put(L.poly([(70.4, 6.8), (71.4, 0.2), (76.6, 0.2), (77.2, 6.8)]), "gun", z=1.2, h=1.4, bevel=0.5)
    L.carve(L.rrect(72.4, 1.4, 75.4, 5.4, 0.8), 1.2, 0.2, 0.06)                            # hood window
    L.put(L.rrect(73.5, 1.6, 74.3, 5.6, 0.3), "steel", z=1.4, h=0.6, bevel=0.2, ink_w=0.12)  # post
    # AK-74 muzzle brake
    L.cylx(76.4, 83.8, 7.0, 1.55, "gun", z=0.8, cap=0.6)
    L.slot(78.4, 6.2, 80.4, 7.8, 0.4, 0.8, 0.2)
    L.slot(81.2, 6.0, 82.4, 8.0, 0.3, 0.8, 0.2)
    L.groove([(77.4, 5.5), (77.4, 8.5)], 0.2, 0.3, 0.6)
    # pistol grip, trigger guard, trigger
    L.put(L.poly([(24.6, 10.6), (31.2, 10.6), (29.6, 16.6), (28.6, 22.4), (27.6, 24.4), (24.6, 24.6),
                  (21.4, 23.0), (20.8, 20.6), (22.4, 16.4)]), "plum_g", z=0.6, h=2.0, bevel=1.1)
    for y in (16.5, 18.8, 21.1):
        L.groove([(22.3, y), (28.8, y + 0.4)], 0.22, 0.25, 0.75)
    L.put(L.line([(31.6, 10.6), (32.0, 14.0), (38.6, 14.0), (39.6, 10.6)], 0.75), "gun", z=0.8, h=0.9, bevel=0.3, ink_w=0.14)
    L.put(L.line([(34.4, 10.8), (34.9, 12.2), (34.6, 13.0)], 0.6), "steel", z=0.6, h=0.6, bevel=0.2, ink_w=0.12)
    # curved AK-74 magazine
    mag = L.poly(bend((42.2, 10.0), math.radians(78), 15.0, -0.62, 7.2, 6.4))
    L.put(mag, "plum", z=0.4, h=2.3, bevel=1.0)
    L.carve(L.poly(bend((42.2, 11.6), math.radians(78), 12.5, -0.55, 0.45, 0.45)), 0.25, 0.75, 0.08)
    for i, t in enumerate((0.25, 0.55)):
        p = bend((42.2, 10.0), math.radians(78), 15.0 * t, -0.62 * t, 7.2, 6.4, steps=4)
        L.groove([p[4], p[5]], 0.25, 0.3, 0.7)


def off(ox, oy, pts):
    return [(x + ox, y + oy) for x, y in pts]


def taper(pts, w0, w1, steps=6):
    """Polygon around a polyline whose width goes w0 -> w1 (bow limbs)."""
    P = []
    for i in range(len(pts) - 1):
        for k in range(steps):
            t = k / steps
            P.append((pts[i][0] + (pts[i + 1][0] - pts[i][0]) * t, pts[i][1] + (pts[i + 1][1] - pts[i][1]) * t))
    P.append(pts[-1])
    left, right = [], []
    for i, (x, y) in enumerate(P):
        a = P[max(0, i - 1)]
        b = P[min(len(P) - 1, i + 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / ln, dx / ln
        w = (w0 + (w1 - w0) * i / (len(P) - 1)) * 0.5
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
    return left + right[::-1]


def deagle(L, ox, oy, shade=1.0):
    """One Desert Eagle; (ox, oy) = rear of the hammer / top of the slide."""
    sh = lambda m: tuple(c * shade for c in MAT[m]["col"])
    o = lambda pts: off(ox, oy, pts)
    L.put(L.poly(o([(0.2, 5.4), (1.4, 4.6), (3.6, 4.8), (3.6, 7.4), (1.6, 7.6)])), "dark", col=sh("dark"), z=0.6, h=1.2, bevel=0.4)
    # grip frame + panel
    L.put(L.poly(o([(1.8, 6.2), (27.4, 6.2), (27.4, 7.6), (17.0, 8.2), (16.0, 8.2), (11.2, 8.0), (10.6, 10.6),
                    (9.8, 13.6), (9.2, 16.4), (8.4, 17.3), (4.2, 17.3), (2.8, 16.8), (1.4, 14.8), (2.6, 11.4),
                    (1.2, 8.6)])), "chrome", col=sh("chrome"), z=0.3, h=1.8, bevel=0.7)
    L.put(L.poly(o([(3.4, 8.6), (9.8, 8.6), (9.0, 12.4), (8.2, 15.4), (4.6, 15.6), (3.2, 14.6), (3.9, 11.4)])),
          "rubber", col=sh("rubber"), z=1.4, h=1.0, bevel=0.6)
    for i in range(5):
        y = oy + 9.6 + i * 1.15
        L.groove([(ox + 4.0 - (i % 2) * 0.2, y), (ox + 9.0 - i * 0.2, y)], 0.2, 0.25, 0.7)
    L.put(L.rrect(ox + 3.6, oy + 16.4, ox + 8.8, oy + 17.6, 0.4), "dark", col=sh("dark"), z=0.8, h=0.9, bevel=0.3, ink_w=0.12)
    L.put(L.line(o([(11.1, 7.8), (11.5, 10.6), (16.4, 10.6), (16.8, 9.6), (16.4, 7.8)]), 0.75), "chrome", col=sh("chrome"), z=0.4, h=0.8,
          bevel=0.3, ink_w=0.14)
    L.put(L.line(o([(12.8, 8.0), (13.3, 9.2), (13.0, 9.9)]), 0.55), "dark", col=sh("dark"), z=0.4, h=0.5, bevel=0.2, ink_w=0.1)
    # slide
    L.put(L.poly(o([(3.0, 1.3), (3.8, 0.5), (26.6, 0.5), (27.6, 1.4), (27.6, 6.5), (3.0, 6.5)])), "chrome",
          col=sh("chrome"), z=0.8, h=2.0, bevel=0.8)
    L.groove(o([(8.6, 4.1), (27.3, 4.1)]), 0.2, 0.35, 0.65)
    L.groove(o([(19.4, 0.7), (19.4, 4.1)]), 0.2, 0.35, 0.6)                      # slide / barrel block
    L.raise_(L.rrect(ox + 19.6, oy + 0.6, ox + 27.5, oy + 4.0, 0.3), 0.3, 0.3)
    L.ribs(ox + 3.8, ox + 8.0, oy + 1.4, oy + 5.8, 0.75, 0.28, 0.35, 0.55)
    L.slot(ox + 11.4, oy + 1.2, ox + 17.0, oy + 3.0, 0.25, 0.8, 0.2)
    L.cylx(ox + 12.4, ox + 16.2, oy + 2.1, 0.45, "brass", z=0.8, h=0.5, ink=0.35)
    L.put(L.rrect(ox + 5.0, oy - 0.3, ox + 7.2, oy + 0.8, 0.3), "dark", col=sh("dark"), z=2.4, h=0.6, bevel=0.2, ink_w=0.12)
    L.put(L.rrect(ox + 25.0, oy - 0.3, ox + 26.4, oy + 0.8, 0.3), "dark", col=sh("dark"), z=2.4, h=0.6, bevel=0.2, ink_w=0.12)
    L.hole(ox + 27.0, oy + 2.6, 0.5)
    L.screw(ox + 23.4, oy + 7.0, 0.32)
    L.screw(ox + 5.6, oy + 7.2, 0.32)


def w_deserteagle(L):
    deagle(L, 38.0, 0.0, shade=0.8)     # the far gun (dual Deagles)
    deagle(L, 6.0, 4.0)


def w_mp5(L):
    # A3 collapsible stock: butt pad + two struts
    L.cylx(7.0, 15.0, 5.0, 0.75, "dark", z=0.4)
    L.cylx(8.0, 15.0, 8.8, 0.6, "dark", z=0.4)
    L.put(L.rrect(6.2, 3.8, 9.8, 16.6, 1.2), "rubber", z=0.6, h=2.0, bevel=0.9)
    L.hribs(10.4, 15.6, 6.6, 9.4, 1.0, 0.3, 0.25, 0.7)
    # receiver tube + trigger housing
    L.put(L.poly([(12.6, 7.0), (37.6, 7.0), (37.6, 10.0), (35.0, 11.2), (16.0, 11.4), (13.0, 10.2)]), "poly", z=0.3, h=1.8, bevel=0.7)
    L.cylx(12.4, 53.0, 5.3, 2.35, "gun", z=0.6, cap=0.8)
    L.groove([(13.0, 7.2), (52.4, 7.2)], 0.2, 0.25, 0.7)
    L.cylx(13.0, 55.0, 3.0, 0.9, "dark", z=1.6)                                   # cocking tube
    L.slot(36.0, 2.6, 44.0, 3.4, 0.3, 0.4, 0.4)                                    # cocking slot
    L.put(L.rrect(42.0, 0.6, 43.2, 3.0, 0.35), "steel", z=2.4, h=0.7, bevel=0.2, ink_w=0.12)   # handle
    L.slot(25.0, 4.6, 33.0, 6.4, 0.3, 0.9, 0.18)                                   # ejection port
    L.cylx(26.2, 31.6, 5.5, 0.5, "brass", z=0.6, h=0.5, ink=0.35)
    L.put(L.rrect(17.8, -0.0, 25.4, 3.2, 0.9), "dark", z=2.0, h=1.4, bevel=0.6)      # drum sight
    L.hole(21.6, 1.5, 0.5)
    for x, y in ((15.0, 9.6), (35.6, 9.4)):
        L.screw(x, y, 0.38)
    L.put(L.line([(24.0, 8.6), (27.6, 8.0)], 0.55), "steel", z=2.4, h=0.5, bevel=0.2, ink_w=0.1)  # selector
    L.put(L.ell(24.2, 8.8, 0.55, 0.55), "red", z=2.8, h=0.3, bevel=0.2, ink=0.3)
    # handguard (slim tropical)
    L.put(L.poly([(37.0, 5.6), (55.0, 5.6), (55.4, 7.2), (54.0, 9.8), (38.6, 10.2), (36.4, 9.0)]), "poly", z=1.4, h=2.0, bevel=0.9)
    L.ribs(39.2, 53.4, 6.6, 9.2, 1.6, 0.55, 0.45, 0.55)
    # front sight hood + barrel with 3-lug
    L.put(L.poly([(50.6, 3.2), (51.4, 0.0), (55.2, 0.0), (55.8, 3.2)]), "dark", z=2.0, h=1.2, bevel=0.4)
    L.carve(L.rrect(52.0, 0.8, 54.6, 2.4, 0.6), 0.8, 0.25, 0.06)
    L.cylx(53.0, 58.8, 4.9, 1.25, "gun", z=0.8)
    for x in (55.6, 57.0):
        L.groove([(x, 3.8), (x, 6.0)], 0.22, 0.3, 0.6)
    L.hole(58.6, 4.9, 0.45)
    # grip, trigger guard, trigger
    L.put(L.poly([(18.6, 10.6), (24.6, 10.6), (23.6, 15.0), (22.8, 19.2), (22.0, 20.8), (19.6, 20.8), (18.4, 19.6),
                  (18.0, 15.0)]), "grip", z=0.6, h=1.9, bevel=0.9)
    for y in (14.2, 16.2, 18.2):
        L.groove([(18.4, y), (23.4, y)], 0.2, 0.25, 0.75)
    L.put(L.line([(24.4, 11.0), (24.6, 13.6), (29.6, 13.6), (30.2, 11.0)], 0.7), "poly", z=0.6, h=0.8, bevel=0.3, ink_w=0.14)
    L.put(L.line([(26.4, 11.2), (26.9, 12.4), (26.6, 13.0)], 0.55), "steel", z=0.5, h=0.5, bevel=0.2, ink_w=0.1)
    # curved 30-round magazine
    L.put(L.poly(bend((33.0, 10.0), math.radians(84), 13.0, -0.55, 4.2, 3.9)), "dark", z=0.4, h=1.9, bevel=0.8)
    L.carve(L.poly(bend((33.0, 11.4), math.radians(84), 10.6, -0.5, 0.4, 0.4)), 0.25, 0.7, 0.06)


def w_steyraug(L):
    # one-piece OD body: tall stock sloping up to the mag well, receiver
    L.put(L.poly([(1.6, 6.8), (21.0, 6.2), (28.0, 6.0), (58.6, 6.0), (59.4, 7.0), (59.4, 11.4), (57.4, 13.2),
                  (55.2, 15.4), (37.0, 15.6), (29.0, 15.6), (22.6, 16.0), (16.0, 18.4), (13.0, 21.6), (12.2, 26.6),
                  (1.6, 26.6)]), "od", h=2.4, bevel=1.6, rnd=1.4)
    L.put(L.rrect(0.0, 6.4, 2.6, 26.9, 0.9), "rubber", z=0.4, h=2.2, bevel=0.8)        # butt pad
    L.hribs(8.0, 26.0, 0.3, 2.3, 1.1, 0.28, 0.25, 0.7)
    L.groove([(3.0, 21.0), (11.6, 21.0)], 0.22, 0.3, 0.7)
    L.put(L.ell(6.8, 23.6, 1.3, 1.3), "dark", z=2.2, h=0.6, bevel=0.3, ink_w=0.12)      # sling point
    L.hole(6.8, 23.6, 0.55, 0.4, 0.4)
    L.groove([(1.2, 9.2), (40.0, 9.0)], 0.22, 0.35, 0.7)
    L.groove([(30.0, 15.0), (36.0, 12.6), (56.0, 12.6)], 0.22, 0.3, 0.7)
    L.slot(13.0, 9.8, 22.0, 11.6, 0.3, 0.9, 0.2)                                        # port (bullpup: rear)
    L.cylx(14.2, 20.8, 10.7, 0.5, "brass", z=0.8, h=0.5, ink=0.35)
    L.put(L.rrect(37.0, 9.8, 42.0, 11.4, 0.4), "dark", z=2.4, h=0.6, bevel=0.2, ink_w=0.12)  # cross-bolt safety
    for x, y in ((6.0, 12.8), (26.0, 12.8), (50.0, 10.0)):
        L.screw(x, y, 0.4, mat="dark")
    # translucent-smoke magazine behind the grip
    L.put(L.poly(bend((17.8, 15.0), math.radians(96), 10.4, -0.25, 6.6, 6.0)), "poly", z=0.2, h=1.8, bevel=0.7,
          col=(0.2, 0.21, 0.22))
    L.carve(L.rrect(16.0, 17.6, 18.4, 23.0, 0.6), 0.5, 0.7, 0.08)
    L.put(L.rrect(16.4, 18.2, 18.0, 22.6, 0.5), "brass", z=1.0, h=0.4, bevel=0.3, ink=0.25)   # rounds in the window
    # full-hand trigger guard + grip
    L.put(L.poly([(27.6, 14.6), (33.4, 14.6), (33.2, 19.0), (33.0, 26.4), (28.0, 26.4), (27.4, 20.0)]), "od_g", z=0.5, h=2.0, bevel=1.0,
          rnd=0.9)
    L.hribs(18.0, 25.0, 28.0, 32.8, 1.2, 0.3, 0.25, 0.7)
    L.put(L.line([(32.8, 25.4), (38.8, 24.8), (42.8, 20.4), (45.6, 15.2)], 2.0), "od", z=0.5, h=1.6, bevel=0.7)
    L.put(L.line([(35.6, 15.6), (36.2, 17.6), (35.8, 18.6)], 0.6), "dark", z=0.5, h=0.5, bevel=0.2, ink_w=0.1)
    # folding fore-grip
    L.put(L.poly([(51.6, 13.6), (57.6, 13.6), (57.0, 24.4), (55.8, 25.0), (53.0, 25.0), (52.2, 24.0)]), "od_g", z=0.4, h=1.8,
          bevel=0.9)
    L.hribs(16.6, 23.6, 52.4, 56.6, 1.4, 0.3, 0.25, 0.7)
    # integrated optic / carry handle
    L.put(L.poly([(28.0, 6.4), (29.0, 3.6), (36.4, 3.6), (37.4, 6.4)]), "dark", z=1.0, h=1.4, bevel=0.5)
    L.put(L.poly([(44.6, 6.4), (45.6, 3.6), (51.6, 3.6), (53.0, 6.4)]), "dark", z=1.0, h=1.4, bevel=0.5)
    L.cylx(24.2, 50.6, 1.75, 1.75, "dark", z=1.4, cap=0.6)
    L.put(L.rrect(24.0, -0.0, 26.4, 3.6, 0.6), "rubber", z=2.0, h=2.0, bevel=0.5)          # eye cup
    L.put(L.rrect(47.8, 0.0, 50.8, 3.6, 0.5), "dark", z=2.0, h=2.2, bevel=0.5)
    L.put(L.rrect(50.0, 0.6, 50.8, 3.0, 0.3), "lens", z=2.8, h=0.6, bevel=0.2, ink=0.3)
    L.groove([(30.0, 0.4), (30.0, 3.1)], 0.2, 0.3, 0.6)
    # barrel + flash hider
    L.cylx(57.0, 72.0, 8.4, 1.25, "gun", z=0.8)
    L.cylx(58.4, 61.8, 8.4, 1.7, "dark", z=0.9, cap=0.5)
    L.cylx(70.0, 74.8, 8.4, 1.6, "dark", z=1.0, cap=0.4)
    for x in (71.4, 73.0):
        L.slot(x, 7.6, x + 0.8, 9.2, 0.3, 0.7, 0.25)


def w_spas12(L):
    # stock (folded-stock look of the classic) + pistol grip
    L.put(L.poly([(0.4, 2.6), (2.0, 1.8), (23.4, 1.8), (23.4, 11.2), (12.4, 11.2), (9.0, 9.4), (1.4, 9.4), (0.4, 8.4)]),
          "poly", h=2.2, bevel=1.0)
    L.carve(L.rrect(2.6, 4.2, 10.4, 7.6, 1.4), 0.9, 0.45, 0.1)
    L.put(L.poly([(5.6, 10.4), (13.6, 10.4), (12.4, 14.6), (11.6, 18.6), (11.4, 23.4), (2.6, 23.4), (2.4, 19.0),
                  (3.6, 15.0)]), "grip", z=0.4, h=2.0, bevel=1.0)
    for y in (15.6, 17.6, 19.6, 21.6):
        L.groove([(3.4, y), (11.2, y - 0.2)], 0.22, 0.25, 0.75)
    L.put(L.rrect(2.2, 22.0, 11.8, 23.8, 0.5), "rubber", z=0.8, h=1.2, bevel=0.4, ink_w=0.12)
    L.put(L.line([(13.4, 11.0), (14.0, 14.4), (20.4, 14.4), (21.4, 11.0)], 0.8), "poly", z=0.5, h=0.9, bevel=0.3, ink_w=0.14)
    L.put(L.line([(16.6, 11.2), (17.2, 12.6), (16.9, 13.4)], 0.6), "steel", z=0.5, h=0.5, bevel=0.2, ink_w=0.1)
    # receiver
    L.put(L.poly([(22.4, 1.2), (25.2, 0.0), (38.0, 0.0), (38.0, 3.0), (33.8, 3.2), (33.8, 12.0), (22.4, 12.0)]), "gun",
          z=0.6, h=2.2, bevel=0.8)
    L.slot(26.0, 4.2, 32.6, 6.4, 0.3, 0.9, 0.2)
    L.cylx(27.0, 31.6, 5.3, 0.75, "copper", z=0.6, h=0.7, ink=0.35)                        # shell
    L.put(L.rrect(26.4, 7.6, 30.8, 8.6, 0.3), "steel", z=2.6, h=0.5, bevel=0.2, ink_w=0.1)
    L.screw(24.4, 10.4, 0.4)
    L.screw(32.2, 10.4, 0.4)
    # barrel with perforated heat shield, mag tube, front sight
    L.cylx(33.0, 75.6, 3.4, 1.4, "gun", z=0.8)
    L.put(L.rrect(33.4, 1.0, 62.2, 5.4, 0.8), "dark", z=1.2, h=1.8, bevel=0.7)
    for i in range(8):
        L.slot(35.0 + i * 3.4, 2.2, 37.0 + i * 3.4, 4.2, 0.9, 0.9, 0.25)
    L.cylx(56.0, 70.6, 8.6, 1.9, "gun", z=0.6)
    L.put(L.rrect(68.4, 6.4, 71.0, 10.8, 0.5), "dark", z=1.4, h=1.4, bevel=0.4)               # mag cap
    L.put(L.rrect(71.8, 0.6, 74.4, 2.4, 0.4), "dark", z=2.2, h=0.7, bevel=0.2, ink_w=0.12)
    L.hole(75.0, 3.4, 0.55)
    # ribbed pump forend
    L.put(L.rrect(32.6, 5.6, 58.6, 12.2, 1.4), "poly", z=1.4, h=2.4, bevel=1.1)
    L.ribs(34.2, 57.2, 6.6, 11.4, 1.6, 0.6, 0.5, 0.55)


def w_ruger77(L):
    # walnut stock
    L.put(L.poly([(0.6, 5.6), (8.6, 5.6), (10.4, 6.8), (17.6, 6.6), (20.6, 5.0), (44.0, 5.0), (56.6, 5.0), (57.2, 6.6),
                  (55.6, 8.4), (50.0, 9.8), (45.0, 11.0), (30.0, 11.0), (25.6, 11.8), (22.2, 14.4), (19.2, 15.2),
                  (14.0, 17.0), (10.0, 18.4), (0.6, 18.0)]), "walnut", h=2.4, bevel=1.8, rnd=1.2)
    L.groove([(1.6, 12.2), (14.0, 10.6), (19.6, 9.6)], 0.22, 0.25, 0.75)
    L.put(L.rrect(0.0, 5.2, 1.6, 18.4, 0.5), "rubber", z=0.3, h=2.0, bevel=0.5)            # recoil pad
    L.put(L.rrect(1.5, 5.4, 1.9, 18.2, 0.1), "string", z=0.3, h=1.8, bevel=0.2, ink=0.2)     # white spacer
    L.put(L.ell(12.6, 17.2, 0.6, 0.6), "steel", z=2.0, h=0.4, bevel=0.2, ink_w=0.1)            # sling studs
    L.put(L.ell(50.6, 9.4, 0.55, 0.55), "steel", z=2.0, h=0.4, bevel=0.2, ink_w=0.1)
    # barrel (tapered, blued) + action
    L.put(L.poly([(44.0, 2.0), (82.8, 2.4), (82.8, 4.4), (44.0, 4.9)]), "dark", z=0.8, h=1.6, bevel=1.0)
    L.put(L.rrect(22.6, 1.8, 45.4, 5.4, 0.9), "dark", z=1.0, h=2.0, bevel=0.8)
    L.slot(31.6, 2.4, 38.6, 3.8, 0.3, 0.6, 0.35)
    L.cylx(31.4, 38.8, 3.1, 0.75, "steel", z=1.6, h=0.8, ink=0.3)                          # bolt body
    L.put(L.line([(28.6, 3.6), (27.6, 1.2)], 0.6), "steel", z=2.6, h=0.6, bevel=0.2, ink_w=0.1)   # bolt handle
    L.ball(27.2, 0.9, 0.95, 0.9, "steel", z=2.8, h=0.8)
    L.put(L.rrect(38.6, 0.4, 42.4, 2.2, 0.4), "dark", z=2.4, h=0.8, bevel=0.3, ink_w=0.12)    # rear sight
    L.put(L.rrect(80.6, 1.2, 81.8, 2.6, 0.3), "dark", z=2.0, h=0.6, bevel=0.2, ink_w=0.1)
    L.hole(82.6, 3.4, 0.45)
    # trigger guard + trigger
    L.put(L.line([(23.0, 10.8), (24.0, 13.2), (29.4, 13.2), (31.0, 10.8)], 0.75), "dark", z=0.8, h=0.8, bevel=0.3, ink_w=0.14)
    L.put(L.line([(26.2, 11.0), (26.7, 12.2), (26.4, 12.8)], 0.55), "steel", z=0.6, h=0.5, bevel=0.2, ink_w=0.1)


def w_m79(L):
    L.put(L.poly([(1.0, 2.4), (10.2, 2.4), (15.0, 4.6), (22.6, 7.6), (24.6, 4.6), (31.2, 4.6), (31.2, 13.4), (27.4, 14.0),
                  (26.4, 16.8), (24.8, 18.8), (20.8, 18.8), (19.4, 17.0), (17.4, 15.6), (8.0, 15.8), (1.0, 15.8)]), "wood",
          h=2.4, bevel=1.8, rnd=1.2)
    L.put(L.rrect(0.0, 2.0, 2.8, 16.2, 0.7), "rubber", z=0.4, h=2.2, bevel=0.6)
    L.hribs(3.4, 15.0, 0.4, 2.4, 0.8, 0.22, 0.2, 0.7)
    L.groove([(4.0, 11.0), (14.0, 11.6), (20.6, 13.4)], 0.22, 0.25, 0.75)
    L.put(L.line([(26.8, 13.4), (27.4, 16.8), (31.4, 16.8), (32.4, 12.8)], 0.75), "gun", z=0.6, h=0.8, bevel=0.3, ink_w=0.14)
    L.put(L.line([(28.8, 13.4), (29.3, 14.8), (29.0, 15.6)], 0.6), "steel", z=0.5, h=0.5, bevel=0.2, ink_w=0.1)
    # break-open receiver
    L.put(L.poly([(24.0, 1.4), (34.6, 1.4), (34.6, 12.2), (29.0, 13.6), (24.0, 13.2)]), "gun", z=0.6, h=2.2, bevel=0.8)
    L.put(L.rrect(27.0, -0.0, 29.4, 2.6, 0.5), "steel", z=2.2, h=1.0, bevel=0.3, ink_w=0.12)    # latch
    L.screw(31.6, 9.6, 0.5)
    L.groove([(30.0, 1.8), (30.0, 12.6)], 0.22, 0.35, 0.6)
    # fat barrel + forend + leaf sight
    L.cylx(33.6, 66.8, 6.4, 4.1, "gun", z=0.6, cap=0.6)
    L.groove([(36.0, 2.6), (36.0, 10.2)], 0.22, 0.3, 0.65)
    L.put(L.rrect(46.4, 8.4, 56.4, 11.8, 1.2), "wood", z=2.4, h=1.6, bevel=1.0)
    L.screw(51.4, 10.1, 0.38)
    L.put(L.poly([(31.0, 2.6), (31.8, 0.0), (40.0, 0.0), (41.2, 2.6)]), "dark", z=4.4, h=0.8, bevel=0.3)
    L.carve(L.rrect(33.4, 0.6, 38.6, 1.8, 0.4), 0.6, 0.3, 0.06)
    L.put(L.rrect(62.8, 1.4, 64.4, 2.8, 0.3), "dark", z=4.6, h=0.5, bevel=0.2, ink_w=0.1)
    L.carve(L.rrect(66.0, 3.0, 66.8, 9.8, 0.3), 0.6, 0.45, 0.06)


def w_barretm82(L):
    # stock with skeleton window + butt pad
    st = np.clip(L.poly([(0.6, 8.0), (18.4, 8.0), (18.4, 14.6), (13.4, 15.0), (13.6, 23.0), (1.2, 23.0), (1.0, 15.0),
                         (0.6, 14.0)]) - L.rrect(5.8, 15.6, 10.8, 19.6, 1.0), 0, 1)
    L.put(st, "gun", h=2.2, bevel=1.0)
    L.put(L.rrect(0.0, 7.6, 1.8, 15.0, 0.6), "rubber", z=0.4, h=2.0, bevel=0.5)
    L.put(L.rrect(0.6, 20.6, 13.8, 23.6, 0.8), "rubber", z=0.4, h=1.8, bevel=0.6)               # monopod foot
    L.groove([(2.0, 11.2), (17.6, 11.2)], 0.22, 0.3, 0.65)
    # receiver (upper + lower) and rail
    L.put(L.poly([(17.2, 7.6), (67.0, 7.6), (67.0, 14.4), (48.0, 14.6), (34.0, 14.6), (17.2, 14.6)]), "gun", z=0.4, h=2.2, bevel=0.8)
    L.groove([(18.0, 11.4), (66.0, 11.4)], 0.22, 0.35, 0.6)
    L.rail(17.6, 50.0, 7.8, "dark", z=1.8, h=0.9, height=1.2)
    L.slot(36.0, 9.0, 45.0, 10.8, 0.3, 0.9, 0.18)
    L.cylx(37.0, 44.0, 9.9, 0.6, "brass", z=0.8, h=0.6, ink=0.35)
    for x, y in ((20.0, 13.0), (31.0, 13.0), (47.0, 13.0), (64.0, 13.0)):
        L.screw(x, y, 0.42)
    # perforated handguard
    L.put(L.rrect(48.6, 7.6, 67.6, 14.8, 0.8), "dark", z=1.0, h=2.2, bevel=0.8)
    for i in range(6):
        L.hole(51.4 + i * 3.0, 11.2, 0.95, 1.0, 0.2)
    # barrel + big arrowhead muzzle brake
    L.cylx(66.0, 88.0, 11.2, 1.8, "gun", z=0.8)
    L.put(L.poly([(86.0, 8.6), (91.6, 8.4), (94.8, 9.6), (94.8, 12.8), (91.6, 14.0), (86.0, 13.8)]), "gun", z=1.0, h=2.6, bevel=1.0)
    L.slot(88.0, 9.4, 90.0, 13.0, 0.6, 1.0, 0.18)
    L.slot(91.4, 9.8, 93.0, 12.6, 0.5, 1.0, 0.2)
    # scope
    L.put(L.rrect(23.0, 3.4, 28.4, 8.0, 0.6), "dark", z=1.6, h=1.6, bevel=0.5)
    L.put(L.rrect(39.6, 3.4, 45.0, 8.0, 0.6), "dark", z=1.6, h=1.6, bevel=0.5)
    L.cylx(21.0, 42.0, 2.4, 1.5, "dark", z=2.2)
    L.put(L.poly([(17.8, 0.8), (19.0, 0.2), (21.8, 0.6), (22.6, 1.4), (22.6, 3.4), (21.8, 4.2), (19.0, 4.6), (17.8, 4.0)]),
          "rubber", z=2.4, h=2.4, bevel=0.8)
    L.put(L.poly([(40.0, 1.0), (42.6, -0.0), (48.0, -0.0), (48.4, 0.6), (48.4, 4.4), (48.0, 5.0), (42.6, 5.0), (40.0, 3.8)]),
          "dark", z=2.4, h=2.6, bevel=0.9)
    L.put(L.rrect(47.6, 0.6, 48.4, 4.4, 0.3), "lens", z=4.0, h=0.6, bevel=0.2, ink=0.3)
    L.put(L.rrect(29.4, -0.0, 33.4, 1.6, 0.4), "dark", z=3.4, h=1.0, bevel=0.3, ink_w=0.12)    # turret
    L.ribs(29.8, 33.0, 0.2, 1.4, 0.7, 0.25, 0.2, 0.6)
    # grip, guard, magazine, bipod
    L.put(L.poly([(19.6, 14.0), (27.4, 14.0), (26.4, 19.6), (25.4, 25.4), (24.4, 27.4), (21.4, 27.4), (19.4, 25.6),
                  (19.0, 22.0), (20.4, 18.0)]), "grip", z=0.6, h=2.0, bevel=1.0)
    for y in (19.0, 21.2, 23.4, 25.6):
        L.groove([(19.6, y), (26.0, y - 0.3)], 0.22, 0.25, 0.75)
    L.put(L.line([(27.2, 14.6), (28.0, 18.8), (34.6, 18.8), (35.4, 14.6)], 0.8), "gun", z=0.6, h=0.9, bevel=0.3, ink_w=0.14)
    L.put(L.line([(30.0, 14.8), (30.6, 16.4), (30.2, 17.4)], 0.6), "steel", z=0.5, h=0.5, bevel=0.2, ink_w=0.1)
    L.put(L.rrect(35.0, 13.6, 47.6, 20.8, 0.8), "dark", z=0.6, h=2.0, bevel=0.8)
    L.hribs(15.4, 19.6, 36.0, 46.6, 2.0, 0.35, 0.25, 0.7)
    L.put(L.rrect(56.8, 13.8, 63.2, 17.0, 0.6), "dark", z=1.6, h=1.4, bevel=0.5)
    L.cyly(15.0, 27.8, 60.0, 1.35, "gun", z=0.8)
    for y in (19.0, 23.0):
        L.put(L.rrect(58.4, y, 61.6, y + 1.0, 0.3), "dark", z=1.8, h=0.6, bevel=0.2, ink_w=0.1)
    L.put(L.rrect(58.0, 26.6, 62.0, 27.9, 0.4), "rubber", z=1.6, h=0.6, bevel=0.2, ink_w=0.1)


def w_m249(L):
    # skeleton stock
    L.put(np.clip(L.poly([(0.4, 3.0), (4.6, 3.0), (7.0, 4.2), (19.6, 4.6), (19.6, 13.0), (5.4, 13.0), (5.4, 16.6),
                          (1.0, 16.6), (0.4, 15.4)]) - L.rrect(5.2, 7.6, 15.6, 10.4, 1.2), 0, 1), "poly", h=2.2, bevel=1.0)
    L.put(L.rrect(0.0, 2.6, 2.0, 16.8, 0.6), "rubber", z=0.4, h=2.0, bevel=0.5)
    L.cylx(15.0, 21.0, 9.0, 1.0, "dark", z=0.6)                                               # buffer tube
    # receiver + feed cover
    L.put(L.poly([(17.4, 4.6), (66.4, 4.6), (66.4, 10.4), (46.0, 10.6), (44.0, 13.0), (17.4, 13.0)]), "gun", z=0.4,
          h=2.2, bevel=0.8)
    L.put(L.poly([(20.8, 5.0), (22.4, 1.0), (32.8, 1.0), (34.6, 3.8), (45.0, 4.2), (45.0, 5.6), (20.8, 5.6)]), "dark",
          z=1.6, h=1.6, bevel=0.7)
    L.rail(24.0, 32.6, 1.2, "dark", z=2.6, h=0.7, height=1.0)
    L.groove([(18.0, 8.4), (45.0, 8.4)], 0.22, 0.3, 0.65)
    L.slot(34.0, 9.0, 42.0, 10.8, 0.3, 0.9, 0.2)
    L.cylx(35.0, 41.0, 9.9, 0.55, "brass", z=0.6, h=0.5, ink=0.35)
    for x, y in ((19.6, 11.6), (42.6, 11.6), (36.0, 6.6)):
        L.screw(x, y, 0.4)
    # heat shield + handguard + barrel + front sight + flash hider
    L.put(L.rrect(45.4, 3.4, 63.8, 6.2, 0.6), "dark", z=1.6, h=1.4, bevel=0.5)
    for i in range(5):
        L.slot(47.0 + i * 3.4, 4.2, 48.8 + i * 3.4, 5.4, 0.5, 0.8, 0.25)
    L.put(L.poly([(44.0, 9.6), (66.0, 9.6), (66.6, 12.6), (64.0, 15.4), (47.0, 15.4), (44.6, 13.6)]), "poly", z=0.8, h=2.0, bevel=0.9)
    L.ribs(48.0, 63.0, 11.0, 14.4, 2.0, 0.5, 0.4, 0.6)
    L.cylx(63.0, 78.6, 7.6, 1.35, "gun", z=0.8)
    L.cylx(77.0, 81.8, 7.6, 1.6, "dark", z=1.0, cap=0.4)
    L.slot(78.4, 6.8, 80.4, 8.4, 0.3, 0.7, 0.25)
    L.put(L.poly([(65.4, 6.4), (66.0, 0.0), (68.8, 0.0), (69.6, 6.4)]), "dark", z=1.8, h=1.2, bevel=0.4)
    L.carve(L.rrect(66.6, 0.8, 68.2, 3.4, 0.4), 0.8, 0.25, 0.06)
    # folded bipod under the barrel
    L.put(L.line([(64.0, 10.6), (75.2, 10.8)], 1.1), "dark", z=1.0, h=1.0, bevel=0.4)
    L.put(L.line([(64.6, 12.0), (74.6, 12.2)], 0.9), "dark", z=0.8, h=0.8, bevel=0.3)
    # 100-round soft pouch (coyote canvas)
    L.put(L.rrect(31.6, 11.0, 45.2, 21.2, 1.6), "tan", z=0.6, h=2.6, bevel=1.6)
    L.groove([(32.6, 13.0), (44.2, 13.0)], 0.2, 0.25, 0.7)
    L.carve(L.rrect(32.4, 12.0, 44.4, 20.4, 1.2) - L.rrect(32.9, 12.5, 43.9, 19.9, 1.0), 0.15, 0.75, 0.04)   # stitching
    L.put(L.rrect(36.0, 11.6, 40.6, 13.6, 0.5), "rubber", z=3.2, h=0.6, bevel=0.3, ink_w=0.12)               # buckle tab
    # grip, guard, trigger
    L.put(L.poly([(22.4, 12.4), (30.4, 12.4), (29.4, 17.0), (28.4, 21.2), (27.2, 22.6), (23.8, 22.6), (22.4, 21.2),
                  (22.0, 17.4)]), "grip", z=0.6, h=2.0, bevel=1.0)
    for y in (16.6, 18.6, 20.6):
        L.groove([(22.4, y), (28.8, y - 0.2)], 0.22, 0.25, 0.75)
    L.put(L.line([(30.0, 12.8), (30.4, 15.0), (31.6, 15.0)], 0.75), "gun", z=0.6, h=0.8, bevel=0.3, ink_w=0.14)


def w_minigun(L):
    # spade handle + top grip
    L.put(L.line([(9.0, 1.9), (5.0, 3.0), (2.4, 6.4), (2.2, 12.6)], 3.8), "rubber", z=0.6, h=2.4, bevel=1.2)
    L.hribs(7.0, 12.4, 0.2, 3.2, 1.2, 0.3, 0.25, 0.7)
    L.put(L.rrect(27.0, 1.2, 33.2, 10.4, 1.6), "rubber", z=0.6, h=2.4, bevel=1.2)
    L.hribs(2.6, 8.6, 27.4, 32.8, 1.3, 0.3, 0.25, 0.7)
    L.put(L.rrect(29.0, 1.0, 31.2, 2.4, 0.4), "red", z=2.8, h=0.5, bevel=0.2, ink=0.3)         # trigger button
    # housing
    L.put(L.poly([(1.0, 12.2), (8.6, 11.0), (12.0, 8.4), (37.0, 8.2), (46.6, 11.6), (46.6, 27.0), (1.0, 27.0)]), "gun",
          z=0.2, h=2.4, bevel=1.0, col=(0.31, 0.32, 0.345), rnd=0.6)
    L.put(L.rrect(2.0, 21.4, 45.4, 26.4, 0.8), "dark", z=1.6, h=1.0, bevel=0.5)               # battery / feeder box
    L.hribs(22.4, 25.6, 4.0, 44.0, 1.0, 0.3, 0.25, 0.7)
    L.cylx(13.4, 36.0, 17.4, 2.6, "steel", z=1.6)                                            # drive motor
    L.ribs(16.0, 33.6, 15.2, 19.6, 1.3, 0.35, 0.4, 0.5)
    L.put(L.rrect(3.0, 13.4, 11.6, 20.2, 0.8), "dark", z=2.0, h=1.0, bevel=0.5)                # control box
    L.put(L.ell(6.0, 16.6, 1.0, 1.0), "orange", z=3.0, h=0.4, bevel=0.3, ink=0.3)
    for x, y in ((40.0, 13.0), (40.0, 19.6), (14.6, 10.2), (34.6, 10.2), (8.6, 22.6), (42.4, 22.6)):
        L.screw(x, y, 0.45)
    # ammo chute with linked brass
    L.put(L.rrect(12.0, 25.8, 46.4, 31.8, 0.8), "dark", z=0.4, h=1.8, bevel=0.6)
    for x0 in (14.2, 27.2):
        L.carve(L.rrect(x0, 26.6, x0 + 5.4, 31.6, 0.4), 1.0, 0.3, 0.06)
        for k in range(4):
            L.cyly(26.8, 31.4, x0 + 0.8 + k * 1.3, 0.55, "brass", z=0.4, h=0.7, ink=0.35)
    # rotor drum + barrels + clamps
    L.cylx(44.6, 56.0, 19.8, 7.2, "gun", z=0.6, cap=1.2)
    L.ribs(46.6, 54.6, 13.6, 26.0, 2.0, 0.4, 0.4, 0.55)
    for yc in (17.9, 24.5):
        L.cylx(55.0, 110.0, yc, 1.55, "dark", z=0.6)
    for yc in (14.6, 21.2):
        L.cylx(55.0, 110.6, yc, 1.6, "gun", z=1.6)
    for x0 in (84.0, 97.0):
        L.put(L.rrect(x0, 12.0, x0 + 6.8, 27.6, 1.2), "steel", z=1.8, h=2.0, bevel=0.7)
        L.groove([(x0 + 3.4, 12.4), (x0 + 3.4, 27.2)], 0.22, 0.3, 0.65)
        L.screw(x0 + 1.6, 19.8, 0.45)
        L.screw(x0 + 5.2, 19.8, 0.45)
    L.put(L.rrect(107.6, 12.6, 110.8, 26.6, 0.8), "dark", z=2.0, h=1.6, bevel=0.5)            # muzzle clamp
    for yc in (14.6, 21.2):
        L.hole(110.2, yc, 0.6)


def w_colt1911(L):
    # Mk23 SOCOM: polymer frame, long slide
    L.put(L.poly([(37.6, 0.6), (39.6, 0.4), (40.2, 2.2), (38.0, 2.6)]), "dark", z=0.6, h=1.0, bevel=0.3)        # hammer
    L.put(L.poly([(38.4, 4.4), (61.4, 4.4), (61.4, 5.8), (53.0, 6.8), (51.0, 6.8), (46.2, 6.6), (45.6, 9.6),
                  (45.0, 13.2), (44.2, 16.2), (43.4, 16.8), (40.0, 16.8), (38.8, 16.0), (37.2, 13.4), (38.6, 10.0),
                  (38.0, 7.6)]), "poly", z=0.3, h=1.8, bevel=0.8)
    L.put(L.poly([(39.6, 7.4), (45.0, 7.4), (44.2, 11.6), (43.4, 15.2), (40.4, 15.4), (39.0, 14.4), (39.8, 11.0)]),
          "rubber", z=1.4, h=0.8, bevel=0.5)
    for y in (9.0, 10.4, 11.8, 13.2, 14.6):
        L.groove([(39.6, y), (44.4, y - 0.2)], 0.16, 0.2, 0.7)
    L.put(L.line([(46.0, 6.4), (46.4, 9.4), (51.0, 9.4), (51.6, 6.2)], 0.75), "poly", z=0.4, h=0.8, bevel=0.3, ink_w=0.14)
    L.put(L.line([(47.6, 6.6), (48.1, 7.8), (47.8, 8.6)], 0.55), "steel", z=0.4, h=0.5, bevel=0.2, ink_w=0.1)
    L.put(L.rrect(53.6, 5.4, 60.4, 6.2, 0.2), "dark", z=1.2, h=0.6, bevel=0.2, ink_w=0.1)        # accessory rail
    L.put(L.poly([(38.6, 1.4), (39.6, 0.8), (62.2, 0.8), (62.8, 1.6), (62.8, 4.8), (38.6, 4.8)]), "dark", z=0.8,
          h=2.0, bevel=0.8)
    L.ribs(39.6, 43.6, 1.6, 4.2, 0.75, 0.28, 0.35, 0.55)
    L.slot(47.0, 1.4, 52.6, 2.8, 0.25, 0.8, 0.2)
    L.cylx(47.8, 51.8, 2.1, 0.45, "brass", z=0.8, h=0.4, ink=0.35)
    L.put(L.rrect(40.6, 0.0, 42.6, 1.0, 0.3), "dark", z=2.4, h=0.6, bevel=0.2, ink_w=0.12)
    L.put(L.rrect(60.2, 0.0, 61.6, 1.0, 0.3), "dark", z=2.4, h=0.6, bevel=0.2, ink_w=0.12)
    L.put(L.ell(41.6, 0.5, 0.18, 0.18), "string", z=3.0, h=0.2, bevel=0.1, ink=0)
    L.put(L.ell(60.9, 0.5, 0.18, 0.18), "string", z=3.0, h=0.2, bevel=0.1, ink=0)
    L.hole(62.4, 2.8, 0.5)
    L.screw(44.0, 5.6, 0.32)


def w_knife(L):
    L.put(L.poly([(0.6, 1.2), (13.6, 1.2), (13.6, 6.2), (8.0, 6.2), (6.0, 6.8), (3.0, 6.8), (0.6, 6.2)]), "rubber", h=2.0, bevel=1.0)
    for x in (4.0, 6.6, 9.2, 11.6):
        L.groove([(x, 1.4), (x, 6.2)], 0.3, 0.3, 0.7)
    L.put(L.rrect(0.0, 1.0, 2.0, 6.8, 0.8), "steel", z=0.3, h=2.0, bevel=0.7)                     # pommel
    L.put(L.rrect(13.0, 0.0, 15.4, 8.8, 0.6), "gun", z=0.4, h=2.2, bevel=0.6)                    # guard
    blade = L.poly([(15.0, 1.2), (28.6, 1.2), (31.2, 2.0), (36.8, 3.4), (33.6, 5.4), (29.6, 6.6), (15.0, 6.6)])
    L.put(blade, "blade", z=0.2, h=1.8, bevel=2.6, ink_w=0.16)
    L.raise_(L.poly([(15.0, 3.6), (30.0, 3.6), (36.6, 3.4), (33.4, 5.4), (29.6, 6.6), (15.0, 6.6)]) * blade, -0.6, 0.4)
    L.groove([(17.0, 2.6), (27.0, 2.6)], 0.4, 0.35, 0.6)                                          # fuller
    for x in np.arange(16.0, 23.0, 0.9):                                                          # spine teeth
        L.carve(L.poly([(x, 1.0), (x + 0.45, 1.8), (x + 0.9, 1.0)]), 0.5, 0.45, 0.04)
    L.screw(7.2, 3.8, 0.4)


def w_chainsaw(L):
    # bar + chain
    chain = np.clip(L.rrect(52.0, 8.6, 107.8, 21.0, 6.0) - L.rrect(53.0, 10.6, 106.0, 19.0, 4.2), 0, 1)
    L.put(L.rrect(52.0, 10.4, 106.2, 19.2, 4.4), "steel", z=0.4, h=1.4, bevel=0.8)
    L.groove([(56.0, 14.8), (102.0, 14.8)], 0.5, 0.25, 0.7)
    for x in (60.0, 64.0):
        L.hole(x, 14.8, 0.6, 0.6, 0.35)
    L.put(L.rrect(66.0, 12.0, 82.0, 13.4, 0.5), "orange", z=1.9, h=0.2, bevel=0.2, ink=0.3)   # decal stripe
    L.put(chain, "dark", z=1.0, h=1.2, bevel=0.4, ink_w=0.14)
    x = 54.0
    while x < 104.0:
        L.carve(L.rrect(x, 9.0, x + 0.25, 10.6, 0.1), 0.4, 0.4, 0.03)
        L.carve(L.rrect(x, 19.0, x + 0.25, 20.6, 0.1), 0.4, 0.4, 0.03)
        x += 1.2
    for k in range(7):
        x0 = 55.0 + k * 7.0
        L.put(L.poly([(x0, 9.2), (x0 + 1.0, 7.8), (x0 + 3.4, 7.8), (x0 + 3.8, 9.2)]), "blade", z=1.4, h=0.8, bevel=0.3, ink_w=0.12)
        L.put(L.poly([(x0 + 3.2, 20.4), (x0 + 3.6, 21.8), (x0 + 6.0, 21.8), (x0 + 7.0, 20.4)]), "blade", z=1.4, h=0.8, bevel=0.3,
              ink_w=0.12)
    # engine body with rear handle loop
    body = L.poly([(7.4, 13.6), (8.6, 10.4), (12.4, 8.0), (20.0, 6.2), (28.0, 5.0), (40.0, 4.8), (46.0, 6.4), (48.8, 9.0),
                   (49.2, 22.4), (46.0, 24.8), (26.0, 25.2), (22.0, 22.0), (9.6, 21.0), (7.4, 19.0)])
    body = np.clip(body - L.rrect(13.2, 12.0, 25.4, 16.6, 2.2), 0, 1)
    L.put(body, "red", h=2.4, bevel=1.4)
    L.put(L.rrect(24.4, 10.6, 44.4, 22.4, 2.0), "red", z=1.2, h=1.8, bevel=1.2)              # engine cover
    for x in np.arange(27.0, 42.0, 1.8):
        L.slot(x, 16.0, x + 0.8, 21.0, 0.35, 0.9, 0.2)
    L.put(L.rrect(26.6, 11.8, 36.0, 14.6, 0.6), "dark", z=3.0, h=0.6, bevel=0.3, ink_w=0.12)  # label plate
    L.put(L.rrect(27.4, 12.6, 35.2, 13.8, 0.3), "orange", z=3.6, h=0.2, bevel=0.1, ink=0.2)
    L.put(L.rrect(40.4, 8.0, 53.8, 23.6, 1.6), "dark", z=0.8, h=2.2, bevel=0.9)               # clutch cover
    L.screw(46.0, 12.0, 0.6)
    L.screw(46.0, 19.6, 0.6)
    L.put(L.rrect(9.4, 9.4, 13.0, 13.4, 0.8), "rubber", z=2.0, h=0.8, bevel=0.4)             # throttle
    L.put(L.ell(30.0, 7.0, 1.4, 1.0), "rubber", z=2.4, h=0.6, bevel=0.3)                      # fuel cap
    # wrap handle (front)
    L.cyly(0.4, 23.0, 50.8, 2.3, "rubber", z=1.6, cap=1.6)
    L.hribs(2.0, 21.0, 48.6, 53.0, 1.6, 0.3, 0.25, 0.7)


def w_law(L):
    L.cylx(2.0, 30.4, 12.9, 4.4, "od", z=0.2, cap=0.9)                                      # outer tube
    L.cylx(29.0, 80.8, 13.2, 3.9, "od", z=0.0, cap=0.5)                                     # inner tube
    for x in (6.0, 26.6):
        L.groove([(x, 8.8), (x, 17.0)], 0.3, 0.35, 0.6)
    L.put(L.rrect(56.0, 9.4, 57.8, 17.0, 0.2), "yellow", z=2.2, h=1.0, bevel=0.3, ink=0.35)  # HE band
    L.put(L.rrect(1.2, 8.2, 3.2, 17.6, 0.6), "rubber", z=0.6, h=2.8, bevel=0.6)               # rear cover
    L.put(L.rrect(79.6, 9.0, 81.0, 17.4, 0.4), "rubber", z=0.6, h=2.4, bevel=0.4)
    L.put(L.rrect(6.0, 7.0, 14.8, 9.6, 0.6), "od_d", z=2.6, h=1.0, bevel=0.4)                # sling bracket
    # trigger housing with rubber boot + rear sight
    L.put(L.poly([(31.0, 9.4), (32.0, 5.4), (46.0, 4.6), (49.4, 6.4), (49.4, 9.4)]), "od_d", z=2.0, h=1.8, bevel=0.8)
    L.put(L.rrect(39.0, 3.6, 45.4, 6.0, 1.0), "rubber", z=3.2, h=1.0, bevel=0.6)
    L.put(L.rrect(33.6, 0.0, 37.6, 5.6, 0.5), "dark", z=3.2, h=0.8, bevel=0.3)
    L.carve(L.rrect(34.4, 0.8, 36.8, 3.0, 0.6), 0.8, 0.25, 0.06)
    # front sight
    L.put(L.rrect(64.4, 4.6, 78.2, 9.8, 0.8), "od_d", z=2.0, h=1.6, bevel=0.6)
    L.put(L.rrect(70.0, 0.0, 74.6, 5.0, 0.5), "dark", z=3.2, h=0.8, bevel=0.3)
    L.carve(L.rrect(70.8, 0.8, 73.8, 3.6, 0.4), 0.8, 0.25, 0.06)
    L.put(L.rrect(72.0, 1.0, 72.6, 3.4, 0.1), "dark", z=3.4, h=0.4, bevel=0.1, ink=0.2)
    # sling swivel
    ring = np.clip(L.rrect(28.4, 16.2, 33.4, 20.8, 1.6) - L.rrect(29.6, 17.2, 32.2, 19.8, 1.0), 0, 1)
    L.put(ring, "gun", z=0.4, h=0.8, bevel=0.3, ink_w=0.12)
    L.hole(80.4, 13.2, 1.8, 0.6, 0.35)


def w_flamer(L):
    # fuel tank with straps + valve
    L.cyly(0.2, 28.8, 11.8, 6.6, "od", z=0.2, cap=4.2)
    for y in (5.0, 23.4):
        L.put(L.rrect(5.0, y, 18.8, y + 1.4, 0.4), "dark", z=2.0, h=1.0, bevel=0.3, ink_w=0.12)
    L.groove([(5.4, 14.0), (18.2, 14.0)], 0.24, 0.3, 0.65)
    L.put(L.rrect(16.6, 2.0, 18.8, 27.0, 0.8), "rubber", z=4.0, h=1.0, bevel=0.5)               # shoulder strap
    L.ball(9.2, 7.6, 1.8, 1.8, "steel", z=5.0, h=1.0)                                         # valve wheel
    L.hole(9.2, 7.6, 0.5, 0.3, 0.4)
    # hose
    L.put(L.line([(18.0, 14.6), (22.0, 14.2), (26.4, 13.0)], 2.4), "rubber", z=1.0, h=1.8, bevel=0.9)
    for x in (19.4, 21.0, 22.6, 24.2):
        L.groove([(x, 12.6), (x + 0.6, 16.0)], 0.22, 0.25, 0.7)
    # wand body, lower fuel line, igniter hump
    L.cylx(50.0, 80.6, 14.0, 1.4, "gun", z=0.4)
    L.put(L.poly([(24.0, 8.2), (60.4, 7.4), (60.4, 12.4), (24.0, 12.8)]), "gun", z=0.8, h=2.2, bevel=0.9)
    L.groove([(25.0, 10.4), (60.0, 10.0)], 0.22, 0.3, 0.65)
    L.put(L.rrect(30.2, 6.0, 36.6, 9.0, 0.8), "dark", z=2.2, h=1.0, bevel=0.4)
    L.put(L.rrect(38.0, 7.0, 50.0, 8.4, 0.4), "copper", z=2.6, h=0.6, bevel=0.3, ink_w=0.12)  # igniter line
    for x, y in ((27.0, 11.2), (57.6, 11.0)):
        L.screw(x, y, 0.4)
    # rear grip (slanted back) + trigger
    L.put(L.poly([(28.6, 12.0), (37.0, 12.0), (35.6, 17.0), (34.2, 22.0), (32.8, 25.6), (27.2, 25.6), (26.6, 23.0),
                  (28.0, 17.0)]), "grip", z=0.6, h=2.0, bevel=1.0)
    for y in (17.4, 19.6, 21.8, 24.0):
        L.groove([(27.8, y), (34.6, y - 0.2)], 0.22, 0.25, 0.75)
    L.put(L.line([(37.0, 12.4), (37.6, 15.4), (42.6, 15.4), (43.4, 12.4)], 0.75), "gun", z=0.6, h=0.8, bevel=0.3, ink_w=0.14)
    L.put(L.line([(38.8, 12.6), (39.3, 14.0), (39.0, 14.8)], 0.6), "red", z=0.5, h=0.5, bevel=0.2, ink_w=0.1)
    # vented shroud + nozzle
    L.put(L.rrect(59.2, 4.0, 74.6, 12.4, 1.0), "dark", z=1.0, h=2.4, bevel=0.9)
    for x in np.arange(61.0, 73.0, 1.9):
        L.slot(x, 5.4, x + 0.9, 11.0, 0.4, 1.0, 0.18)
    L.cylx(73.4, 85.4, 9.2, 2.4, "gun", z=0.8)
    L.put(L.poly([(84.0, 6.0), (87.8, 7.0), (87.8, 11.6), (84.0, 12.4)]), "steel", z=1.2, h=2.0, bevel=0.6)
    L.hole(87.2, 9.3, 1.2, 0.8, 0.25)
    L.put(L.rrect(76.0, 11.2, 82.0, 12.6, 0.4), "copper", z=2.0, h=0.6, bevel=0.3, ink_w=0.12)  # pilot line


def w_bow(L):
    up = [(5.4, 6.2), (9.0, 7.6), (13.0, 10.4), (17.0, 14.4), (20.6, 19.0), (23.0, 24.0), (23.8, 29.0), (23.4, 33.0)]
    dn = [(x, 95.0 - y) for x, y in up]
    L.put(L.line([(11.2, 8.6), (11.2, 86.4)], 0.9), "string", z=0.4, h=0.6, bevel=0.3, ink_w=0.14)   # string
    for y0 in (19.6, 44.0, 72.4):
        L.put(L.rrect(10.4, y0, 12.0, y0 + 2.6, 0.5), "dark", z=0.8, h=0.8, bevel=0.3, ink_w=0.12)  # servings
    for pts in (up, dn):
        L.put(L.poly(taper(pts, 1.8, 6.6)), "dark", z=0.4, h=2.2, bevel=1.4)
        L.put(L.poly(taper(pts[1:], 0.5, 2.2)), "gun", z=1.8, h=0.6, bevel=0.4, ink=0.35)
    for y in (6.4, 88.6):
        L.ball(5.6, y, 1.0, 1.0, "gun", z=1.0, h=0.8)                                             # tip nocks
    riser = L.poly([(19.0, 31.0), (24.6, 30.6), (26.4, 36.0), (28.8, 41.5), (29.2, 47.5), (28.8, 53.5), (26.4, 59.0),
                    (24.6, 64.4), (19.0, 64.0), (18.2, 58.0), (21.4, 53.0), (22.2, 47.5), (21.4, 42.0), (18.2, 37.0)])
    L.put(riser, "walnut", z=0.6, h=2.6, bevel=1.6)
    L.put(L.poly([(22.4, 42.6), (28.2, 42.0), (28.8, 47.5), (28.2, 53.0), (22.4, 52.4), (22.8, 47.5)]), "tan", z=2.0,
          h=1.0, bevel=0.6)
    L.hribs(43.4, 52.2, 22.6, 28.6, 1.1, 0.25, 0.2, 0.7)
    L.put(L.rrect(20.2, 45.2, 22.8, 46.4, 0.3), "steel", z=2.6, h=0.5, bevel=0.2, ink_w=0.1)          # arrow rest
    for y in (34.0, 61.0):
        L.screw(21.6, y, 0.55)


def w_frag_grenade(L):
    L.ball(7.0, 11.2, 6.4, 6.3, "frag", h=4.2, bevel=1.0)
    L.groove([(1.2, 11.0), (12.8, 11.0)], 0.3, 0.35, 0.65)
    L.put(L.rrect(4.0, 2.2, 10.0, 5.6, 0.8), "gun", z=2.6, h=1.6, bevel=0.6)               # fuze
    L.cyly(0.4, 2.8, 7.0, 1.4, "gun", z=3.0)
    L.put(L.poly([(9.4, 2.2), (11.0, 2.6), (12.4, 6.2), (12.6, 9.6), (11.6, 9.6), (11.2, 6.4), (9.4, 4.6)]),
          "steel", z=4.0, h=0.9, bevel=0.35, ink_w=0.14)                                    # spoon
    ring = np.clip(L.ell(2.7, 3.6, 1.6, 1.6) - L.ell(2.7, 3.6, 0.95, 0.95), 0, 1)
    L.put(ring, "steel", z=3.6, h=0.6, bevel=0.3, ink_w=0.12)
    L.put(L.line([(3.9, 3.8), (5.4, 3.9)], 0.45), "steel", z=3.6, h=0.5, bevel=0.2, ink_w=0.1)


def w_cluster_grenade(L):
    L.ball(9.0, 17.2, 8.6, 9.2, "yellow", h=5.0)
    for x in (4.4, 9.0, 13.6):
        L.groove([(x, 8.6), (x, 25.8)], 0.32, 0.45, 0.6)
    for y in (12.4, 15.6, 18.8, 22.0):
        L.groove([(0.4, y), (17.6, y)], 0.32, 0.45, 0.6)
    L.put(L.rrect(3.6, 7.6, 14.4, 9.8, 0.8), "gun", z=3.8, h=1.2, bevel=0.5)                 # collar
    L.cyly(0.4, 8.0, 9.0, 2.6, "gun", z=4.0)                                                 # fuze tube
    L.groove([(6.6, 2.6), (11.4, 2.6)], 0.22, 0.3, 0.6)
    L.put(L.poly([(11.4, 0.6), (12.6, 0.8), (12.4, 7.4), (11.4, 7.6)]), "steel", z=5.6, h=0.6, bevel=0.25, ink_w=0.12)
    L.put(L.rrect(7.6, 9.0, 10.4, 10.0, 0.3), "orange", z=5.0, h=0.4, bevel=0.2, ink=0.3)     # cluster band


# ─────────────────────────── close-up details (6x) ───────────────────────────
# Painted after each design: markings, pins, rivets, plates, knurling. Text is
# generic (model / calibre / lot numbers), never a maker's logo.

YEL = (0.86, 0.72, 0.22)


def x_ak74(L):
    L.stamp("AK-74", 24.6, 6.7, 1.45)
    L.stamp("No 04417", 24.6, 8.8, 0.92)
    L.rivets([(23.7, 4.9), (23.7, 8.4), (33.0, 10.0), (35.2, 10.0), (37.4, 10.0)])
    L.pin(42.0, 9.4)
    L.stamp("A", 33.2, 3.0, 0.7)      # selector marks on the dust cover edge
    L.stamp("O", 35.6, 3.0, 0.7)
    L.knurl(L.rrect(76.6, 5.6, 77.6, 8.4, 0.2), 0.36, 0.06)


def x_mp5(L):
    L.stamp("MP5", 30.4, 7.7, 1.05)
    L.stamp("9mm x19", 30.4, 9.05, 0.7)
    L.stamp("S", 23.0, 6.95, 0.6)
    L.stamp("F", 27.8, 6.95, 0.6)
    L.pin(20.6, 10.0)
    L.pin(28.6, 10.3)
    L.knurl(L.rrect(17.9, 0.2, 25.3, 3.0, 0.8), 0.4, 0.07)        # drum sight wheel
    L.rivets([(46.0, 3.9), (50.0, 3.9)])


def x_steyraug(L):
    L.stamp("AUG A1", 43.2, 9.5, 1.05)
    L.stamp("5.56 NATO", 3.6, 10.6, 0.85)
    L.stamp("Nr 22871", 3.6, 11.8, 0.65)
    L.pin(24.0, 13.2)
    L.pin(31.0, 13.4)
    L.knurl(L.rrect(30.0, 0.5, 33.0, 3.0, 0.3), 0.38, 0.05)      # optic adjuster


def x_spas12(L):
    L.stamp("SPAS-12", 25.6, 0.55, 1.0)
    L.stamp("12 GA", 23.4, 8.75, 0.8)
    L.pin(28.4, 10.6)
    L.pin(30.2, 10.6)
    L.rivets([(63.4, 3.2), (66.4, 3.2), (4.0, 2.9), (21.6, 2.9), (21.6, 9.6)])
    ring = np.clip(L.ell(1.6, 10.6, 1.1, 1.1) - L.ell(1.6, 10.6, 0.6, 0.6), 0, 1)         # sling loop
    L.put(ring, "steel", z=2.4, h=0.4, bevel=0.2, ink_w=0.1)


def x_ruger77(L):
    L.knurl(L.poly([(21.6, 6.8), (27.6, 6.6), (28.4, 10.0), (24.0, 11.0), (21.0, 12.4)]), 0.42, 0.07)   # wrist checkering
    L.knurl(L.poly([(35.6, 6.0), (50.4, 6.0), (49.0, 8.6), (36.0, 9.2)]), 0.42, 0.07)                 # forend checkering
    L.stamp("M77  .308 WIN", 47.6, 2.75, 0.85)
    L.pin(24.4, 4.4)
    L.pin(43.2, 4.4)


def x_m79(L):
    L.stamp("M79  40MM", 38.6, 5.35, 1.0)
    L.stamp("LOT 7743", 38.6, 6.75, 0.72)
    L.rivets([(25.6, 3.0), (25.6, 11.6), (33.2, 3.0)])
    L.pin(28.4, 11.4)
    L.knurl(L.rrect(27.0, 0.0, 29.4, 2.6, 0.4), 0.36, 0.06)        # latch


def x_barretm82(L):
    L.stamp("M82A1", 19.2, 8.85, 1.0)
    L.stamp(".50 BMG", 25.4, 9.1, 0.78)
    L.plate(3.0, 8.8, 11.2, 10.7, "SN 00447", 0.75)
    L.knurl(L.rrect(29.4, 0.0, 33.4, 1.6, 0.4), 0.34, 0.06)        # turret
    L.knurl(L.rrect(18.0, 0.8, 22.4, 4.2, 0.6), 0.4, 0.05)          # eye piece ring
    L.pin(29.0, 13.4)
    L.pin(34.4, 13.2)
    L.pin(43.0, 13.2)
    L.groove([(33.4, 11.6), (33.4, 14.4)], 0.18, 0.25, 0.6)
    L.stamp("SAFE", 27.0, 12.1, 0.8)
    L.rivets([(50.0, 8.4), (66.0, 8.4)])


def x_m249(L):
    L.stamp("M249  5.56MM", 19.8, 8.75, 1.05)
    L.pin(26.4, 12.0)
    L.pin(33.0, 12.2)
    L.rivets([(46.0, 9.8), (64.6, 9.8)])


def x_minigun(L):
    L.plate(36.8, 14.2, 45.2, 18.6, "M134", 1.15)
    L.stamp("7.62MM  4000 RPM", 3.4, 24.7, 0.78)
    L.knurl(L.rrect(13.6, 15.0, 15.6, 19.8, 0.4), 0.36, 0.05)     # motor end cap
    L.rivets([(46.0, 13.4), (46.0, 26.0), (54.6, 13.4), (54.6, 26.0)], 0.3)


def x_colt1911(L):
    L.stamp("MK23  .45", 53.2, 1.55, 0.85)
    L.pin(46.4, 5.4)
    L.pin(49.6, 5.4)


def x_deserteagle(L):
    for ox, oy in ((38.0, 0.0), (6.0, 4.0)):
        L.stamp(".50 AE", ox + 20.2, oy + 1.05, 0.8)
        L.pin(ox + 13.6, oy + 7.1)
        L.pin(ox + 17.4, oy + 7.1)


def x_knife(L):
    L.stamp("TF-7", 19.2, 3.9, 0.85)
    L.knurl(L.rrect(0.1, 1.2, 1.9, 6.6, 0.6), 0.34, 0.05)          # pommel


def x_chainsaw(L):
    L.stamp("PRO-SERIES 20\"", 84.0, 15.3, 1.25)
    L.stamp("TF 460", 28.2, 12.55, 1.0, 0.1, 0.35)
    L.rivets([(56.0, 12.2), (56.0, 17.6)], 0.32)


def x_law(L):
    L.stencil("ROCKET 66MM HEAT M72A2", 8.4, 12.3, 1.0, YEL)
    L.stencil("LOT 4471-A", 60.0, 12.5, 0.85, YEL)
    L.rivets([(30.0, 10.0), (30.0, 16.2), (79.0, 10.4)])


def x_flamer(L):
    L.stencil("FUEL", 6.6, 15.6, 1.45, YEL)
    L.tone(L.band(19.8, 20.6) * L.vband(5.6, 16.4), np.array([2.2, 1.8, 0.7], np.float32))   # warning stripe
    L.plate(44.6, 8.4, 52.0, 10.0, "M2A1", 0.75)
    L.knurl(L.rrect(84.0, 6.4, 85.6, 12.0, 0.3), 0.34, 0.05)


def x_frag_grenade(L):
    L.stencil("M67", 4.6, 12.0, 1.3, YEL)


def x_cluster_grenade(L):
    L.stencil("CL-4", 5.6, 19.2, 1.3, (0.18, 0.16, 0.12))
    L.knurl(L.rrect(6.6, 0.6, 11.4, 2.4, 0.4), 0.34, 0.05)


def x_bow(L):
    L.rivets([(21.6, 38.6), (21.6, 56.4)], 0.32)


DETAILS = {
    "ak74": x_ak74, "mp5": x_mp5, "steyraug": x_steyraug, "spas12": x_spas12, "ruger77": x_ruger77, "m79": x_m79,
    "barretm82": x_barretm82, "m249": x_m249, "minigun": x_minigun, "colt1911": x_colt1911, "deserteagle": x_deserteagle,
    "knife": x_knife, "chainsaw": x_chainsaw, "law": x_law, "flamer": x_flamer, "bow": x_bow,
    "frag-grenade": x_frag_grenade, "cluster-grenade": x_cluster_grenade,
}


# name -> (design fn, seed, axis)
WEAPONS = {
    "deserteagle": (w_deserteagle, 5, "x"),
    "mp5": (w_mp5, 7, "x"),
    "ak74": (w_ak74, 3, "x"),
    "steyraug": (w_steyraug, 11, "x"),
    "spas12": (w_spas12, 13, "x"),
    "ruger77": (w_ruger77, 17, "x"),
    "m79": (w_m79, 19, "x"),
    "barretm82": (w_barretm82, 23, "x"),
    "m249": (w_m249, 29, "x"),
    "minigun": (w_minigun, 31, "x"),
    "colt1911": (w_colt1911, 37, "x"),
    "knife": (w_knife, 2, "x"),
    "chainsaw": (w_chainsaw, 47, "x"),
    "law": (w_law, 53, "x"),
    "flamer": (w_flamer, 59, "x"),
    "bow": (w_bow, 61, "y"),
    "frag-grenade": (w_frag_grenade, 41, "x"),
    "cluster-grenade": (w_cluster_grenade, 43, "x"),
}


def classic(name):
    return Image.open(os.path.join(SRC, name + ".png")).convert("RGBA")


def build(name):
    fn, seed, axis = WEAPONS[name]
    cl = classic(name)
    L = W(cl.width, cl.height, seed=seed, axis=axis)
    fn(L)
    if name in DETAILS:
        DETAILS[name](L)
    spr, nrm = L.render2()
    exp = (cl.width * HD, cl.height * HD)
    assert spr.size == exp, (name, spr.size, exp)
    return spr, nrm


IMPORT_TMPL = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""


def ensure_import(path):
    """The sprites are minified on screen: import them with mipmaps. A new
    file gets a stub .import (Godot fills in the rest on the next import);
    an existing one is patched."""
    imp = path + ".import"
    if not os.path.exists(imp):
        with open(imp, "w") as f:
            f.write(IMPORT_TMPL)
        return
    txt = open(imp).read()
    if "mipmaps/generate=false" in txt:
        with open(imp, "w") as f:
            f.write(txt.replace("mipmaps/generate=false", "mipmaps/generate=true"))


def sheet(made, path):
    """Classic (nearest, scaled to the HD size) | HD per row, on a mid backdrop."""
    rows = []
    for name in made:
        cl = classic(name)
        hd = made[name]
        rows.append((cl.resize((cl.width * HD, cl.height * HD), Image.NEAREST), hd))
    pad = 16
    Wt = max(a.width + b.width for a, b in rows) + pad * 3
    Ht = sum(max(a.height, b.height) + pad for a, b in rows) + pad
    sh = Image.new("RGBA", (Wt, Ht), (92, 104, 116, 255))
    y = pad
    for a, b in rows:
        sh.alpha_composite(a, (pad, y))
        sh.alpha_composite(b, (pad * 2 + a.width, y))
        y += max(a.height, b.height) + pad
    sh.save(path)


def main():
    args = sys.argv[1:]
    sheet_path = None
    if "--sheet" in args:
        sheet_path = args[args.index("--sheet") + 1]
    only = [a for a in args if a in WEAPONS]
    os.makedirs(OUT, exist_ok=True)
    made = {}
    for name in (only or WEAPONS):
        spr, nrm = build(name)
        for im, suffix in ((spr, ""), (nrm, "_n")):
            path = os.path.join(OUT, name + suffix + ".png")
            im.save(path, optimize=True)
            ensure_import(path)
        made[name] = spr
        print("weapons gfx: %-16s %dx%d" % (name, spr.width, spr.height))
    if sheet_path:
        sheet(made, sheet_path)


if __name__ == "__main__":
    main()
