#!/usr/bin/env python3
"""Paint the high-resolution terrain materials of the cinematic look (#283).

Writes assets/terrain-hd/:

  <material>.webp    2048x2048 tileable albedo (sRGB; 1024 design texels at
                     2x). Kept fairly flat — the map's own palette is applied at run time (terrain_hd.gd
                     multiplies the albedo, normalised by its mean colour, by the
                     classic texture x vertex colour), so these carry FORM:
                     slabs, strata, cracks, plates, planks, bricks, pebbles.
  <material>_n.webp  tangent-space normal map, OpenGL convention (green = up).
  edge_<kind>.png    2048x256 RGBA strips, tileable along x, drawn along the
                     solid outlines: grass lips, snow caps, sand / dirt lips,
                     rock rims, worn metal edges, hanging roots, icicles. The
                     surface line sits at EDGE_LINE[kind] (rows from the top).

Materials: rock dirt soil grass sand snow metal concrete wood brick masonry ice.

Everything is generated from fixed seeds with periodic (FFT / wrapped
Voronoi) noise, so the output is deterministic and tiles seamlessly.

  python3 tools/gen_terrain_gfx.py               # write all
  python3 tools/gen_terrain_gfx.py rock wood     # only these
  python3 tools/gen_terrain_gfx.py --sheet F.png # also save a lit preview sheet

The script writes / patches each image's .import file: mipmaps on (the
materials are minified on screen; gate F `terrain` checks), materials lossy
(WebP), edge strips lossless. Run `godot --headless --import` afterwards.
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage
from scipy.spatial import cKDTree

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "terrain-hd")
# Sizes are in DESIGN texels (every constant below is in these units); the
# PNGs are written at K x that resolution (#283 "ultra HD": 2048 px materials
# over the same world tile = twice the texel density of the 1024 design).
N = 1024
EW, EH = 1024, 128            # edge strip size (design)
K = 2
MAT_EXT = ".webp"
R = N * K                     # material resolution in pixels
ER, EHR = EW * K, EH * K      # edge strip resolution
# Row of the surface line in each edge strip (terrain_hd.gd reads the same).
EDGE_LINE = {"grass": 72, "snow": 44, "sand": 52, "dirt": 56, "rock": 30, "metal": 24,
             "roots": 10, "icicles": 10}

YY, XX = (np.mgrid[0:R, 0:R].astype(np.float32) / K)


# ── noise toolkit (all periodic over the tile) ──────────────────────────────

def rng(seed):
    return np.random.default_rng(seed)


def fbm(seed, p=1.0, lo=2.0, hi=None, ax=1.0, ay=1.0, n=R, m=None):
    """Periodic spectral noise, zero mean / unit std. Amplitude ~ f^-p between
    `lo` and `hi` cycles per tile; ax / ay > 1 squash frequencies along that
    axis (ax > 1 = features stretched along x)."""
    m = m or n
    r = rng(seed)
    F = np.fft.fft2(r.standard_normal((m, n)))
    fx = np.fft.fftfreq(n)[None, :] * n * ax
    fy = np.fft.fftfreq(m)[:, None] * m * ay
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1.0
    amp = np.power(np.maximum(f, 0.5), -p)
    amp *= np.clip(f / lo, 0, 1) ** 2
    if hi is not None:
        amp *= np.exp(-(f / hi) ** 2)
    amp[0, 0] = 0.0
    out = np.real(np.fft.ifft2(F * amp)).astype(np.float32)
    return (out - out.mean()) / (out.std() + 1e-9)


def warp(a, dx, dy):
    return ndimage.map_coordinates(a, [(YY + dy) * K, (XX + dx) * K], order=1, mode="grid-wrap").astype(np.float32)


def blur(a, s):
    return ndimage.gaussian_filter(a, s * K, mode="wrap").astype(np.float32)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def voronoi(seed, count, sx=1.0, sy=1.0, wx=None, wy=None, pts=None):
    """Periodic Voronoi on the tile. sx > 1 = cells wider than tall.
    Returns d1, d2 (scaled px), cell index, and the offset (dx, dy) in px from
    the pixel to its cell's site."""
    r = rng(seed)
    L = np.array([N / sx, N / sy])
    if pts is None:
        pts = r.random((count, 2)) * L
    tree = cKDTree(pts, boxsize=L)
    qx = XX if wx is None else XX + wx
    qy = YY if wy is None else YY + wy
    q = np.stack([np.mod(qx / sx, L[0]).ravel(), np.mod(qy / sy, L[1]).ravel()], 1)
    d, i = tree.query(q, k=2)
    d1 = d[:, 0].reshape(YY.shape).astype(np.float32)
    d2 = d[:, 1].reshape(YY.shape).astype(np.float32)
    idx = i[:, 0].reshape(YY.shape)
    site = pts[idx]
    ox = (site[..., 0] - q[:, 0].reshape(YY.shape))
    oy = (site[..., 1] - q[:, 1].reshape(YY.shape))
    ox = (ox + L[0] / 2) % L[0] - L[0] / 2
    oy = (oy + L[1] / 2) % L[1] - L[1] / 2
    return d1, d2, idx, (ox * sx).astype(np.float32), (oy * sy).astype(np.float32)


def normal_map(h, strength):
    """h in texels of height x strength -> OpenGL tangent normal (green = up)."""
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength * K
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * strength * K
    n = np.stack([-dx, dy, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n


def cavity(h, s, k):
    """Ambient occlusion-ish term: darker where the surface sits below its
    surroundings."""
    return np.clip(1.0 - k * np.maximum(blur(h, s) - h, 0.0), 0.0, 1.0)


def ramp(t, stops):
    """t (0..1) -> RGB through [(pos, (r, g, b)), ...]."""
    t = np.clip(t, 0, 1)
    out = np.zeros(t.shape + (3,), np.float32)
    pos = [s[0] for s in stops]
    for c in range(3):
        out[..., c] = np.interp(t, pos, [s[1][c] for s in stops])
    return out


def per_cell(idx, values):
    return np.asarray(values, np.float32)[idx]


def wrap_draw(draw_fn, size, ss=1):
    """Draw with PIL on a canvas; every primitive is repeated at +-size on x/y
    so shapes crossing the border tile."""
    pass


def to_img(rgb):
    return Image.fromarray((np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8))


def normal_img(n):
    return to_img(n * 0.5 + 0.5)


class Canvas:
    """Supersampled greyscale canvas with wrap-around drawing (PIL)."""

    def __init__(self, w, h, ss=2, fill=0, wrap_y=True):
        self.w, self.h, self.ss = w, h, ss
        self.wrap_y = wrap_y
        self.ss = ss * K
        self.img = Image.new("L", (w * self.ss, h * self.ss), fill)
        self.d = ImageDraw.Draw(self.img)

    def _offs(self):
        ys = (-self.h, 0, self.h) if self.wrap_y else (0,)
        return [(ox, oy) for ox in (-self.w, 0, self.w) for oy in ys]

    def poly(self, pts, fill):
        s = self.ss
        for ox, oy in self._offs():
            self.d.polygon([((x + ox) * s, (y + oy) * s) for x, y in pts], fill=fill)

    def line(self, pts, fill, width):
        s = self.ss
        for ox, oy in self._offs():
            self.d.line([((x + ox) * s, (y + oy) * s) for x, y in pts], fill=fill, width=max(1, int(round(width * s))), joint="curve")

    def ellipse(self, cx, cy, rx, ry, fill):
        s = self.ss
        for ox, oy in self._offs():
            self.d.ellipse([(cx - rx + ox) * s, (cy - ry + oy) * s, (cx + rx + ox) * s, (cy + ry + oy) * s], fill=fill)

    def array(self):
        im = self.img.resize((self.w * K, self.h * K), Image.LANCZOS) if self.ss > 1 else self.img
        return np.asarray(im, np.float32) / 255.0


# ── materials ────────────────────────────────────────────────────────────────
# Each returns (albedo HxWx3 float, height HxW in texels, normal strength).

def mat_rock():
    w1 = fbm(11, 1.6, lo=1.5, hi=40) * 22
    w2 = fbm(12, 1.6, lo=1.5, hi=40) * 22
    d1, d2, idx, ox, oy = voronoi(13, 26, sx=1.9, sy=1.0, wx=w1, wy=w2)
    r = rng(14)
    n = idx.max() + 1
    tone = r.normal(0, 1, n)
    gx = r.normal(0, 0.10, n)
    gy = r.normal(-0.04, 0.10, n)
    lift = r.uniform(0, 14, n)
    crack = d2 - d1
    slab = smooth(0.0, 12.0, crack)
    # Chunky faceted slabs: each cell is a tilted plane with a rounded rim.
    h = slab * (13.0 + per_cell(idx, lift) * 0.6) + per_cell(idx, gx) * ox + per_cell(idx, gy) * oy
    # Strata inside the slabs (sedimentary banding), only in some cells.
    sw = fbm(15, 1.4, lo=2, hi=30, ax=3.0) * 40
    strata = np.sin((YY + sw) * (2 * math.pi / 23.0) + fbm(22, 1.2, lo=3, hi=60) * 1.5)
    smask = smooth(0.4, 0.9, per_cell(idx, r.random(n))) * slab * smooth(0.0, 1.0, fbm(23, 1.2, lo=2, hi=20))
    h += strata * 1.2 * smask
    # Fine fracture network (second, denser Voronoi), broken up by noise.
    e1, e2, _, _, _ = voronoi(16, 140, sx=1.3, wx=w2 * 0.5, wy=w1 * 0.5)
    fine = 1.0 - smooth(0.0, 2.2, e2 - e1)
    fmask = smooth(0.15, 0.7, fbm(17, 1.2, lo=3, hi=60))
    h -= fine * fmask * 3.5 * slab
    # Surface grain.
    h += fbm(18, 0.9, lo=20, hi=300) * 1.4 + fbm(19, 1.2, lo=6, hi=80) * 2.5
    # Ultra-HD micro relief: grain + pitting only resolvable at 2048 px.
    h += fbm(24, 0.4, lo=250, hi=1100) * 0.45
    pits = smooth(2.2, 2.9, fbm(25, 0.6, lo=120, hi=900))
    h -= pits * 1.2
    alb_t = 0.5 + per_cell(idx, tone) * 0.06 + fbm(20, 1.1, lo=3, hi=120) * 0.05
    alb = ramp(alb_t, [(0.0, (0.30, 0.29, 0.28)), (0.5, (0.47, 0.45, 0.42)), (1.0, (0.60, 0.57, 0.52))])
    # Warm / cool cell variation, mineral speckle, darker cracks, worn bright rims.
    warmth = per_cell(idx, r.normal(0.004, 0.012, n))
    alb[..., 0] += warmth
    alb[..., 2] -= warmth
    speck = (fbm(21, 0.2, lo=200) > 2.3).astype(np.float32)
    alb += speck[..., None] * 0.05
    ao = cavity(h, 6, 0.035) * cavity(h, 24, 0.012)
    alb *= (0.78 + 0.22 * slab)[..., None]
    alb *= (0.72 + 0.28 * ao)[..., None]
    rim = smooth(4.0, 9.0, crack) * (1.0 - smooth(9.0, 18.0, crack))
    alb += rim[..., None] * 0.035
    alb *= (1 - 0.18 * pits)[..., None]
    return alb, h, 0.32


def pebbles(seed, count, frac, size=0.42):
    """Sparse rounded stones: dome (0..1), per-stone tone and the stone's
    radius in texels (height = dome * radius * k)."""
    w1 = fbm(seed + 7, 1.5, lo=4, hi=80) * 3.0
    d1, d2, idx, ox, oy = voronoi(seed, count, sx=1.3, wx=w1, wy=w1 * 0.7)
    r = rng(seed + 1)
    n = idx.max() + 1
    keep = (r.random(n) < frac).astype(np.float32)
    spacing = math.sqrt(N * N / count) / math.sqrt(1.3)
    rad = per_cell(idx, r.uniform(0.35, 1.0, n)) * spacing * size
    t = d1 / rad
    dome = np.sqrt(np.clip(1.0 - t * t, 0, 1)) * per_cell(idx, keep)
    tone = per_cell(idx, r.normal(0, 1, n))
    return dome, tone, rad


def mat_dirt():
    base = fbm(31, 1.3, lo=2, hi=90)
    clump = fbm(32, 1.0, lo=8, hi=160)
    layer = fbm(33, 1.2, lo=2, hi=40, ax=4.0)
    dome, ptone, prad = pebbles(34, 300, 0.30, 0.42)
    dome2, ptone2, prad2 = pebbles(35, 1600, 0.22, 0.40)
    h = base * 5 + clump * 2.2 + layer * 3 + np.maximum(dome * prad * 0.55, dome2 * prad2 * 0.5)
    h += fbm(36, 0.8, lo=40, hi=400) * 0.9 + fbm(38, 0.3, lo=300, hi=1100) * 0.5
    t = 0.5 + base * 0.07 + layer * 0.05 + clump * 0.03
    alb = ramp(t, [(0.0, (0.25, 0.18, 0.12)), (0.5, (0.42, 0.32, 0.23)), (1.0, (0.56, 0.45, 0.33))])
    stone = ramp(0.5 + ptone * 0.15, [(0.0, (0.30, 0.27, 0.24)), (0.5, (0.43, 0.39, 0.34)), (1.0, (0.53, 0.49, 0.43))])
    stone2 = ramp(0.5 + ptone2 * 0.15, [(0.0, (0.28, 0.22, 0.17)), (1.0, (0.50, 0.43, 0.35))])
    stone *= (0.8 + 0.2 * dome)[..., None]
    stone2 *= (0.8 + 0.2 * dome2)[..., None]
    m1 = smooth(0.0, 0.18, dome)[..., None]
    m2 = smooth(0.0, 0.18, dome2)[..., None]
    alb = alb * (1 - m2) + stone2 * m2
    alb = alb * (1 - m1) + stone * m1
    ao = cavity(h, 4, 0.06) * cavity(h, 18, 0.02)
    alb *= (0.62 + 0.38 * ao)[..., None]
    specks = (fbm(37, 0.1, lo=300) > 2.4).astype(np.float32)
    alb *= (1 - specks * 0.25)[..., None]
    grains = smooth(2.5, 3.1, fbm(39, 0.0, lo=500))
    alb += (grains * 0.06)[..., None]
    return alb, h, 0.5


def roots_layer(seed, count, w, h, length=(60, 260), width=(1.2, 3.2), down=0.65, ss=2):
    """Thin wandering root fibres (height / mask)."""
    r = rng(seed)
    c = Canvas(w, h, ss)
    for _ in range(count):
        x, y = r.uniform(0, w), r.uniform(0, h)
        ang = math.pi * 0.5 + r.normal(0, 0.9)
        L = r.uniform(*length)
        wd = r.uniform(*width)
        pts = [(x, y)]
        steps = int(L / 6)
        for s in range(steps):
            ang += r.normal(0, 0.35)
            ang = ang * (1 - 0.08 * down) + (math.pi * 0.5) * 0.08 * down
            x += math.cos(ang) * 6
            y += math.sin(ang) * 6
            pts.append((x, y))
        # taper: draw in segments with decreasing width
        for s in range(len(pts) - 1):
            ww = wd * (1.0 - s / max(1, len(pts) - 1) * 0.7)
            c.line([pts[s], pts[s + 1]], int(150 + 100 * (1 - s / len(pts))), ww)
            if r.random() < 0.08 and s > 2:
                # little side rootlet
                bx, by = pts[s]
                ba = ang + r.choice([-1, 1]) * r.uniform(0.6, 1.2)
                c.line([(bx, by), (bx + math.cos(ba) * 14, by + math.sin(ba) * 14)], 120, ww * 0.5)
    return c.array()


def mat_soil():
    base = fbm(41, 1.25, lo=2, hi=110)
    layer = fbm(42, 1.3, lo=2, hi=36, ax=5.0)
    roots = roots_layer(43, 70, N, N)
    dome, ptone, prad = pebbles(44, 900, 0.16, 0.40)
    h = base * 4.5 + layer * 3.0 + roots * 2.5 + dome * prad * 0.5
    h += fbm(45, 0.8, lo=40, hi=400) * 1.0 + fbm(46, 0.3, lo=300, hi=1100) * 0.5
    t = 0.5 + base * 0.06 + layer * 0.06
    alb = ramp(t, [(0.0, (0.15, 0.11, 0.08)), (0.5, (0.27, 0.20, 0.14)), (1.0, (0.39, 0.30, 0.21))])
    root_col = np.array([0.46, 0.36, 0.25], np.float32)
    rm = smooth(0.1, 0.6, roots)[..., None]
    alb = alb * (1 - rm * 0.8) + root_col * rm * 0.8
    stone = ramp(0.5 + ptone * 0.15, [(0.0, (0.24, 0.22, 0.20)), (1.0, (0.44, 0.40, 0.36))]) * (0.8 + 0.2 * dome)[..., None]
    m1 = smooth(0.0, 0.18, dome)[..., None]
    alb = alb * (1 - m1) + stone * m1
    ao = cavity(h, 4, 0.07) * cavity(h, 16, 0.025)
    alb *= (0.6 + 0.4 * ao)[..., None]
    return alb, h, 0.5


def mat_grass():
    """Moss-grown earth (green maps): soft moss cushions over dark soil, fine
    fuzzy grain, low contrast — an overgrown bank, not a lawn."""
    soil, sh, _ = mat_soil()
    # Round moss cushions: two overlapping layers of domes (max), so the
    # outlines are lumpy instead of Voronoi-straight.
    # Four layers of round domes small enough not to be clipped by their
    # Voronoi cells, max-combined, so cushions overlap with round outlines.
    cushion_h = np.zeros(YY.shape, np.float32)
    tone = np.zeros(YY.shape, np.float32)
    for li, (sd, cnt) in enumerate(((53, 160), (57, 220), (58, 300), (59, 420))):
        d, t, rr = pebbles(sd, cnt, 1.0, 0.5)
        hh = d * rr * 0.32
        tone = np.where(hh > cushion_h, t, tone)
        cushion_h = np.maximum(cushion_h, hh)
    cushion = np.clip(cushion_h / max(1e-3, np.percentile(cushion_h, 99)), 0, 1)
    r = rng(54)
    cover = smooth(-1.3, -0.6, fbm(55, 1.3, lo=2, hi=40))
    moss = smooth(0.0, 0.06, cushion) * cover
    grain = fbm(56, 0.4, lo=120, hi=700)
    c = Canvas(N, N, 2)
    for _ in range(24000):
        x, y = r.uniform(0, N), r.uniform(0, N)
        a = -math.pi / 2 + r.normal(0, 0.7)
        L = r.uniform(2.5, 7)
        c.line([(x, y), (x + math.cos(a) * L, y + math.sin(a) * L)], int(r.uniform(60, 220)), r.uniform(0.45, 0.9))
    fib = c.array()
    h = sh * (1 - moss) * 0.6 + moss * (cushion_h * 0.9 + 2.0 + grain * 0.6 + fib * 1.2)
    g = 0.5 + tone * 0.05 + grain * 0.035 + fib * 0.06 + (cushion - 0.6) * 0.14
    green = ramp(g, [(0.0, (0.15, 0.19, 0.08)), (0.5, (0.28, 0.35, 0.14)), (1.0, (0.42, 0.50, 0.22))])
    green *= (0.72 + 0.28 * np.sqrt(cushion))[..., None]
    alb = soil * (1 - moss[..., None]) + green * moss[..., None]
    ao = cavity(h, 4, 0.06) * cavity(h, 16, 0.025)
    alb *= (0.62 + 0.38 * ao)[..., None]
    return alb, h, 0.42


def mat_sand():
    lowx = fbm(61, 1.8, lo=1, hi=8, ax=2.5) * 16
    t = YY + lowx + fbm(62, 1.4, lo=2, hi=40, ax=4.0) * 3
    # Layers of random thickness (cumulative lookup).
    r = rng(63)
    th = r.uniform(14, 90, 200) ** 1.0
    edges = np.cumsum(th)
    period = N
    # Force periodicity: scale layer thicknesses so they sum to N over the tile.
    k = np.searchsorted(edges, period)
    th = th[: k + 1]
    th *= period / th.sum()
    edges = np.concatenate([[0], np.cumsum(th)])
    tm = np.mod(t, period)
    li = np.clip(np.searchsorted(edges, tm, side="right") - 1, 0, len(th) - 1)
    frac = (tm - edges[li]) / th[li]
    hard = r.uniform(0, 1, len(th))
    tone = r.normal(0, 1, len(th))
    # Harder layers stand out; soft ones are eroded back, with rounded lips.
    prof = np.sin(np.clip(frac, 0, 1) * math.pi) ** 0.6
    h = hard[li] * 6.0 * prof + (1 - hard[li]) * 2.0 * prof
    # Cross bedding in some layers.
    cb = np.sin((XX * 0.55 + YY) * (2 * math.pi / 9.0) + fbm(64, 1.2, lo=2, hi=30) * 2.0)
    cbm = (hard[li] > 0.55).astype(np.float32) * prof
    h += cb * 0.7 * cbm
    # Wind pits / erosion pockets.
    d1, d2, pidx, _, _ = voronoi(65, 160, sx=1.8)
    pr = rng(66).random(pidx.max() + 1) < 0.22
    pit = (1 - smooth(4.0, 22.0, d1)) * pr[pidx]
    h -= pit * 6.0
    h += fbm(67, 0.6, lo=60, hi=500) * 0.8 + fbm(70, 0.2, lo=400, hi=1100) * 0.35
    tt = 0.5 + tone[li] * 0.035 + fbm(68, 1.2, lo=2, hi=60) * 0.04
    alb = ramp(tt, [(0.0, (0.54, 0.42, 0.28)), (0.5, (0.70, 0.58, 0.41)), (1.0, (0.82, 0.71, 0.53))])
    alb *= (0.9 + 0.1 * prof)[..., None]
    grain = fbm(69, 0.0, lo=200)
    alb += (grain * 0.018)[..., None]
    ao = cavity(h, 5, 0.05) * cavity(h, 20, 0.02)
    alb *= (0.65 + 0.35 * ao)[..., None]
    return alb, h, 0.4


def mat_snow():
    lump = fbm(71, 1.7, lo=1.5, hi=30)
    lump2 = fbm(72, 1.3, lo=4, hi=60)
    lw = fbm(73, 1.4, lo=2, hi=24, ax=3.0) * 22
    layers = np.sin((YY + lw) * (2 * math.pi / 37.0))
    lmask = smooth(-0.2, 0.8, fbm(74, 1.0, lo=2, hi=20))
    h = lump * 9 + lump2 * 3.5 + layers * 1.2 * lmask
    # Wind crust: a few sharp horizontal ridges.
    crust = np.maximum(0, np.sin((YY + lw * 1.4) * (2 * math.pi / 131.0))) ** 12
    h += crust * 3.0
    h += fbm(75, 0.7, lo=60, hi=500) * 0.35
    ao = cavity(h, 10, 0.03)
    t = 0.55 + lump * 0.05 + lump2 * 0.03
    alb = ramp(t, [(0.0, (0.66, 0.73, 0.84)), (0.55, (0.86, 0.89, 0.94)), (1.0, (0.95, 0.96, 0.98))])
    blue = np.array([0.62, 0.72, 0.88], np.float32)
    shade = (1 - ao)[..., None]
    alb = alb * (1 - shade * 0.9) + blue * shade * 0.9
    # Ice lenses.
    lens = smooth(1.7, 2.4, fbm(76, 1.3, lo=6, hi=60, ax=4.0))
    alb = alb * (1 - lens[..., None] * 0.35) + np.array([0.70, 0.82, 0.93]) * lens[..., None] * 0.35
    h -= lens * 1.0
    spark = smooth(2.7, 3.3, fbm(77, 0.0, lo=600))
    alb += spark[..., None] * 0.12
    h += fbm(78, 0.3, lo=300, hi=1100) * 0.25
    return alb, h, 0.32


def panel_grid(rows, widths_seed, row_h, min_w, max_w, seam):
    """Staggered rectangles: per pixel distance to the panel border, panel id,
    and local coordinates."""
    r = rng(widths_seed)
    dist = np.zeros(YY.shape, np.float32)
    pid = np.zeros(YY.shape, np.int32)
    lx = np.zeros(YY.shape, np.float32)
    ly = np.zeros(YY.shape, np.float32)
    pw = np.zeros(YY.shape, np.float32)
    nid = 0
    y0 = 0
    for ri in range(rows):
        h = row_h[ri]
        # Widths summing to N.
        ws = []
        while sum(ws) < N:
            ws.append(r.uniform(min_w, max_w))
        ws = np.array(ws)
        ws *= N / ws.sum()
        off = r.uniform(0, N)
        x_edges = np.concatenate([[0], np.cumsum(ws)])
        ys = slice(int(round(y0 * K)), int(round((y0 + h) * K)))
        xx = np.mod(XX[ys] - off, N)
        k = np.clip(np.searchsorted(x_edges, xx, side="right") - 1, 0, len(ws) - 1)
        x0 = x_edges[k]
        w = ws[k]
        lxx = xx - x0
        lyy = YY[ys] - y0
        dx = np.minimum(lxx, w - lxx)
        dy = np.minimum(lyy, h - lyy)
        dist[ys] = np.minimum(dx, dy)
        pid[ys] = k + nid
        lx[ys] = lxx
        ly[ys] = lyy
        pw[ys] = w
        nid += len(ws)
        y0 += h
    return dist, pid, lx, ly, pw, nid


def mat_metal():
    rows = [256, 256, 256, 256]
    dist, pid, lx, ly, pw, nid = panel_grid(4, 81, rows, 240, 560, 3)
    r = rng(82)
    tone = r.normal(0, 1, nid)
    bevel = smooth(2.0, 9.0, dist)
    h = bevel * 10.0
    # Rivets along every panel border.
    inset = 15.0
    sp = 32.0
    rv = np.zeros(YY.shape, np.float32)
    for (u, v_, along) in ((lx, ly, True),):
        pass
    near_h = np.abs(ly - inset)
    near_h2 = np.abs((256 - ly) - inset)
    near_v = np.abs(lx - inset)
    near_v2 = np.abs((pw - lx) - inset)
    def rivet(dperp, along):
        da = np.abs(np.mod(along, sp) - sp / 2)
        rr = np.sqrt(dperp ** 2 + da ** 2)
        return np.sqrt(np.clip(1 - (rr / 5.5) ** 2, 0, 1))
    in_x = (lx > inset - 4) & (lx < pw - inset + 4)
    in_y = (ly > inset - 4) & (ly < 256 - inset + 4)
    rv = np.maximum(rv, rivet(near_h, lx - 0) * in_x)
    rv = np.maximum(rv, rivet(near_h2, lx) * in_x)
    rv = np.maximum(rv, rivet(near_v, ly) * in_y)
    rv = np.maximum(rv, rivet(near_v2, ly) * in_y)
    h += rv * 4.0
    # Brushed grain + dents.
    brush = fbm(83, 0.7, lo=3, hi=500, ax=16.0, ay=1.0)
    dents = fbm(84, 1.6, lo=3, hi=40)
    h += brush * 0.35 + dents * 1.2 * bevel
    # Scratches.
    sc = Canvas(N, N, 2)
    for _ in range(320):
        x, y = r.uniform(0, N), r.uniform(0, N)
        a = r.normal(0, 0.5) + (math.pi if r.random() < 0.5 else 0)
        L = r.uniform(10, 70)
        sc.line([(x, y), (x + math.cos(a) * L, y + math.sin(a) * L)], int(r.uniform(80, 200)), r.uniform(0.6, 1.3))
    scr = sc.array()
    t = 0.5 + per_cell(pid, tone) * 0.035 + brush * 0.02
    alb = ramp(t, [(0.0, (0.33, 0.35, 0.37)), (0.5, (0.47, 0.49, 0.51)), (1.0, (0.60, 0.62, 0.63))])
    # Grime streaks run down from each panel's top seam; worn bright bevels.
    streak = fbm(85, 0.9, lo=4, hi=200, ax=1.0, ay=20.0)
    grime = smooth(0.0, 1.0, (1 - ly / 256.0) ** 2.5 * (0.6 + 0.4 * streak))
    alb *= (1 - 0.22 * grime)[..., None]
    # Rust streaks running down from the rivet rows (gravity), uneven lengths.
    run = fbm(87, 0.9, lo=4, hi=300, ax=1.0, ay=20.0)
    col_r = np.exp(-((np.mod(lx, sp) - sp / 2) / 2.2) ** 2)
    below = ly - inset
    streak_r = col_r * np.exp(-np.maximum(below, 0) / (30 + 50 * smooth(-1, 1.5, run))) * (below > 0) * in_x
    streak_r *= smooth(0.0, 0.8, run + 0.3)
    rust = smooth(1.9, 2.6, fbm(86, 1.3, lo=4, hi=80) + (1 - bevel) * 1.2)
    rust = np.maximum(rust, streak_r * 0.8)
    rust_col = np.array([0.42, 0.27, 0.17], np.float32)
    alb = alb * (1 - rust[..., None] * 0.4) + rust_col * rust[..., None] * 0.4
    wear = smooth(2.0, 4.0, dist) * (1 - smooth(4.0, 9.0, dist))
    alb += (wear * 0.07)[..., None]
    alb += (scr * 0.06)[..., None]
    alb += (rv * 0.06)[..., None]
    seam = 1 - smooth(0.0, 3.0, dist)
    alb *= (1 - 0.55 * seam)[..., None]
    h -= scr * 0.3
    h += fbm(88, 0.3, lo=300, hi=1100) * 0.12 * bevel
    return alb, h, 0.45


def mat_concrete():
    dist, pid, lx, ly, pw, nid = panel_grid(4, 91, [256] * 4, 440, 600, 3)
    r = rng(92)
    tone = r.normal(0, 1, nid)
    bevel = smooth(1.5, 6.0, dist)
    h = bevel * 6.0
    # Form-tie holes: 2 x 2 per slab.
    hole = np.zeros(YY.shape, np.float32)
    has_holes = per_cell(pid, (r.random(nid) < 0.5).astype(np.float32))
    for fx in (0.25, 0.75):
        for fy in (0.25, 0.75):
            dd = np.sqrt((lx - pw * fx) ** 2 + (ly - 256 * fy) ** 2)
            hole = np.maximum(hole, (1 - smooth(3.0, 5.0, dd)) * has_holes)
    h -= hole * 5.0
    # Water stains below the tie holes and the top seams.
    streaks = fbm(93, 1.0, lo=3, hi=180, ax=1.0, ay=20.0)
    stain_top = (1 - ly / 256.0) ** 3 * (0.5 + 0.5 * streaks)
    stain_hole = np.zeros(YY.shape, np.float32)
    for fx in (0.25, 0.75):
        for fy in (0.25, 0.75):
            ddx = np.abs(lx - pw * fx)
            below = ly - 256 * fy
            s = (1 - smooth(4.0, 14.0, ddx + np.maximum(0, -below) * 4)) * np.exp(-np.maximum(below, 0) / 70.0)
            stain_hole = np.maximum(stain_hole, s * (0.6 + 0.4 * streaks) * has_holes)
    mott = fbm(94, 1.4, lo=2, hi=60)
    agg = fbm(95, 0.0, lo=150)
    pores = (fbm(96, 0.0, lo=200) > 2.6).astype(np.float32)
    # A few thin cracks.
    e1, e2, _, _, _ = voronoi(97, 26, sx=1.0, wx=fbm(98, 1.5, lo=2, hi=40) * 30, wy=fbm(99, 1.5, lo=2, hi=40) * 30)
    crack = (1 - smooth(0.0, 1.6, e2 - e1)) * smooth(0.9, 1.5, fbm(100, 1.2, lo=2, hi=40))
    h += mott * 0.8 + agg * 0.25 - pores * 0.8 - crack * 2.0
    grime = smooth(0.2, 1.8, fbm(101, 1.5, lo=2, hi=30) + (1 - ly / 256.0) * 0.6)
    t = 0.5 + per_cell(pid, tone) * 0.04 + mott * 0.05 + agg * 0.02 - grime * 0.08
    alb = ramp(t, [(0.0, (0.38, 0.37, 0.35)), (0.5, (0.56, 0.55, 0.52)), (1.0, (0.68, 0.67, 0.64))])
    alb *= (1 - 0.22 * np.clip(stain_top + stain_hole, 0, 1))[..., None]
    # Chipped slab corners / spalled patches (rougher, darker).
    spall = smooth(1.6, 2.1, fbm(102, 1.2, lo=4, hi=80)) * smooth(2.0, 10.0, dist)
    alb *= (1 - 0.18 * spall)[..., None]
    h -= spall * 2.5
    alb *= (1 - 0.35 * pores - 0.45 * crack - 0.55 * hole)[..., None]
    seam = 1 - smooth(0.0, 2.5, dist)
    alb *= (1 - 0.5 * seam)[..., None]
    alb += (smooth(1.5, 3.5, dist) * (1 - smooth(3.5, 7.0, dist)) * 0.04)[..., None]
    return alb, h, 0.4


def mat_wood():
    row_h = [N / 12.0] * 12
    dist, pid, lx, ly, pw, nid = panel_grid(12, 101, row_h, 300, 720, 2)
    r = rng(102)
    tone = r.normal(0, 1, nid)
    phase = r.uniform(0, 100, nid)
    rh = N / 12.0
    # Grain: stretched rings, warped along x per plank, bent round knots.
    gw = fbm(103, 1.6, lo=1, hi=24, ax=12.0, ay=1.0) * 9.0
    yy = ly + gw + per_cell(pid, phase)
    knot = np.zeros(YY.shape, np.float32)
    kx = per_cell(pid, r.uniform(0.2, 0.8, nid)) * pw
    ky = per_cell(pid, r.uniform(0.3, 0.7, nid)) * rh
    has_k = per_cell(pid, (r.random(nid) < 0.45).astype(np.float32))
    dkx = (lx - kx) / 2.6
    dky = (ly - ky)
    kd = np.sqrt(dkx ** 2 + dky ** 2)
    bend = has_k * 9.0 * np.exp(-(kd / 9.0) ** 2) * np.sign(dky + 1e-3)
    knot = has_k * (1 - smooth(3.0, 7.0, kd))
    rings = np.sin((yy + bend) * (2 * math.pi / 5.3) + fbm(104, 1.0, lo=4, hi=200, ax=10.0) * 1.5)
    rings2 = np.sin((yy + bend) * (2 * math.pi / 17.0))
    bevel = smooth(1.0, 5.0, dist)
    fine = np.sin((yy + bend) * (2 * math.pi / 2.3) + fbm(107, 1.4, lo=2, hi=60, ax=12.0) * 3.0)
    h = bevel * 6.0 + rings * 0.5 + rings2 * 0.4 + fine * 0.18 - knot * 1.5
    # Nails at plank ends.
    nail = np.zeros(YY.shape, np.float32)
    for fy in (0.3, 0.7):
        for end in (0, 1):
            ex = np.where(end == 0, 12.0, pw - 12.0)
            dd = np.sqrt((lx - ex) ** 2 + (ly - rh * fy) ** 2)
            nail = np.maximum(nail, 1 - smooth(2.0, 3.6, dd))
    h += nail * 1.5
    t = 0.5 + per_cell(pid, tone) * 0.06 + rings * 0.035 + rings2 * 0.03 + fbm(105, 1.0, lo=2, hi=60, ax=5.0) * 0.03
    alb = ramp(t, [(0.0, (0.28, 0.19, 0.11)), (0.5, (0.45, 0.32, 0.20)), (1.0, (0.60, 0.45, 0.30))])
    alb *= (1 - 0.35 * knot - 0.03 * fine)[..., None]
    seam = 1 - smooth(0.0, 2.2, dist)
    alb *= (1 - 0.65 * seam)[..., None]
    alb = alb * (1 - nail[..., None]) + np.array([0.30, 0.30, 0.30]) * nail[..., None]
    weather = smooth(0.4, 1.6, fbm(106, 1.2, lo=2, hi=40))
    alb = alb * (1 - 0.25 * weather[..., None]) + np.array([0.42, 0.40, 0.37]) * 0.25 * weather[..., None]
    return alb, h, 0.45


def mat_brick():
    bw, bh, mort = 128, 64, 7
    rowi = (YY // bh).astype(np.int32)
    off = np.where(rowi % 2 == 0, 0, bw / 2)
    xx = np.mod(XX + off, N)
    coli = (xx // bw).astype(np.int32)
    lx = xx - coli * bw
    ly = YY - rowi * bh
    bid = rowi * (N // bw) + coli
    nb = (N // bh) * (N // bw)
    r = rng(111)
    dx = np.minimum(lx, bw - lx)
    dy = np.minimum(ly, bh - ly)
    nz = fbm(112, 1.2, lo=8, hi=160) * 2.2
    d = np.minimum(dx, dy) + nz - mort * 0.5
    # Chipped corners: a per-brick noise erodes the edge in places.
    chip = smooth(1.2, 2.2, fbm(113, 1.0, lo=10, hi=120)) * 4.0
    brick = smooth(0.0, 2.5, d - chip)
    tone = r.normal(0, 1, nb)
    burnt = (r.random(nb) < 0.12).astype(np.float32)
    h = brick * (7.0 + per_cell(bid, r.uniform(-1, 1, nb))) + fbm(114, 1.0, lo=10, hi=300) * 0.9 * brick
    mortar_n = fbm(115, 0.3, lo=60, hi=400)
    pit = smooth(2.3, 3.0, fbm(117, 0.4, lo=200, hi=1000)) * brick
    h -= pit * 1.0
    h += (1 - brick) * mortar_n * 0.5
    t = 0.5 + per_cell(bid, tone) * 0.07 + fbm(116, 1.1, lo=4, hi=90) * 0.04
    bcol = ramp(t, [(0.0, (0.34, 0.17, 0.12)), (0.5, (0.52, 0.29, 0.21)), (1.0, (0.64, 0.40, 0.30))])
    bcol *= (1 - 0.35 * per_cell(bid, burnt))[..., None]
    mcol = ramp(0.5 + mortar_n * 0.08, [(0.0, (0.46, 0.43, 0.39)), (1.0, (0.62, 0.59, 0.54))])
    bcol *= (1 - 0.2 * pit)[..., None]
    alb = bcol * brick[..., None] + mcol * (1 - brick[..., None])
    ao = cavity(h, 4, 0.05)
    alb *= (0.65 + 0.35 * ao)[..., None]
    alb += (smooth(0.0, 1.5, d - chip) * (1 - smooth(1.5, 4.0, d - chip)) * 0.03)[..., None]
    return alb, h, 0.4


def mat_masonry():
    r = rng(121)
    # Courses of varying height, blocks of varying width, slightly irregular.
    hs = []
    while sum(hs) < N:
        hs.append(r.uniform(90, 170))
    hs = np.array(hs) * N / sum(hs)
    w1 = fbm(122, 1.5, lo=2, hi=60) * 3
    w2 = fbm(123, 1.5, lo=2, hi=60) * 3
    dist, pid, lx, ly, pw, nid = panel_grid(len(hs), 124, list(hs), 140, 330, 4)
    dist = warp(dist, w1, w2)
    pid = ndimage.map_coordinates(pid.astype(np.float32), [(YY + w2) * K, (XX + w1) * K], order=0, mode="grid-wrap").astype(np.int32)
    tone = r.normal(0, 1, nid)
    tilt_x = r.normal(0, 0.012, nid)
    tilt_y = r.normal(0, 0.012, nid)
    chip = smooth(1.2, 2.2, fbm(125, 1.2, lo=6, hi=60)) * 2.5
    block = smooth(2.0, 14.0, dist - chip) ** 0.8
    face = fbm(126, 1.3, lo=4, hi=120) * 2.0 + fbm(127, 0.9, lo=30, hi=400) * 0.6
    h = block * (12.0 + per_cell(pid, tilt_x) * lx * 20 + per_cell(pid, tilt_y) * ly * 20) + face * block
    t = 0.5 + per_cell(pid, tone) * 0.06 + face * 0.03
    alb = ramp(t, [(0.0, (0.36, 0.34, 0.30)), (0.5, (0.54, 0.51, 0.45)), (1.0, (0.68, 0.64, 0.57))])
    joint = 1 - smooth(1.0, 6.0, dist - chip)
    alb *= (1 - 0.55 * joint)[..., None]
    moss = smooth(1.2, 2.0, fbm(128, 1.3, lo=3, hi=60) + joint * 0.8)
    alb = alb * (1 - 0.3 * moss[..., None]) + np.array([0.30, 0.34, 0.20]) * 0.3 * moss[..., None]
    ao = cavity(h, 6, 0.04)
    alb *= (0.65 + 0.35 * ao)[..., None]
    return alb, h, 0.32


def mat_ice():
    w1 = fbm(131, 1.5, lo=2, hi=40) * 14
    w2 = fbm(132, 1.5, lo=2, hi=40) * 14
    d1, d2, idx, ox, oy = voronoi(133, 34, sx=1.3, wx=w1, wy=w2)
    r = rng(134)
    n = idx.max() + 1
    gx = r.normal(0, 0.22, n)
    gy = r.normal(-0.05, 0.22, n)
    edge = d2 - d1
    facet = smooth(0.0, 5.0, edge)
    h = per_cell(idx, gx) * ox + per_cell(idx, gy) * oy + facet * 8.0
    # Sub facets.
    e1, e2, sidx, sox, soy = voronoi(135, 160, sx=1.0, wx=w2 * 0.4, wy=w1 * 0.4)
    sg = rng(136).normal(0, 0.08, sidx.max() + 1)
    h += per_cell(sidx, sg) * (sox + soy) * 0.6
    sub_edge = 1 - smooth(0.0, 1.5, e2 - e1)
    depth = fbm(137, 1.4, lo=2, hi=40)
    t = 0.5 + depth * 0.10 + per_cell(idx, r.normal(0, 1, n)) * 0.05
    alb = ramp(t, [(0.0, (0.36, 0.52, 0.66)), (0.5, (0.60, 0.76, 0.86)), (1.0, (0.80, 0.90, 0.96))])
    fr = 1 - smooth(0.0, 3.0, edge)
    alb = alb * (1 - fr[..., None] * 0.6) + np.array([0.92, 0.97, 1.0]) * fr[..., None] * 0.6
    alb += (sub_edge * 0.07)[..., None]
    # Internal fracture lines.
    c = Canvas(N, N, 2)
    for _ in range(90):
        x, y = r.uniform(0, N), r.uniform(0, N)
        a = r.uniform(0, math.pi)
        L = r.uniform(20, 110)
        c.line([(x, y), (x + math.cos(a) * L, y + math.sin(a) * L)], int(r.uniform(100, 220)), r.uniform(0.7, 1.5))
    cr = c.array()
    alb += (cr * 0.10)[..., None]
    h -= cr * 0.4
    frost = smooth(0.0, 1.0, 1 - smooth(0.0, 14.0, edge)) * smooth(-0.3, 0.8, fbm(138, 0.8, lo=40, hi=600))
    alb = alb * (1 - frost[..., None] * 0.35) + np.array([0.90, 0.95, 1.0]) * frost[..., None] * 0.35
    h += frost * fbm(139, 0.2, lo=300, hi=1100) * 0.5
    spark = smooth(2.8, 3.4, fbm(140, 0.0, lo=600))
    alb += spark[..., None] * 0.14
    return alb, h, 0.3


MATERIALS = {
    "rock": mat_rock, "dirt": mat_dirt, "soil": mat_soil, "grass": mat_grass, "sand": mat_sand,
    "snow": mat_snow, "metal": mat_metal, "concrete": mat_concrete, "wood": mat_wood,
    "brick": mat_brick, "masonry": mat_masonry, "ice": mat_ice,
}


# ── edge strips (RGBA, tile along x) ────────────────────────────────────────

def blade(c, x, y, h, w, lean, val):
    """A curved grass blade from (x, y) up h texels."""
    pts_l, pts_r = [], []
    steps = 6
    for s in range(steps + 1):
        t = s / steps
        bx = x + lean * t * t
        by = y - h * t
        ww = w * (1 - t) ** 0.9
        pts_l.append((bx - ww, by))
        pts_r.append((bx + ww, by))
    c.poly(pts_l + pts_r[::-1], val)


def strip_rgba(alpha, rgb):
    a = np.clip(alpha, 0, 1)
    img = np.concatenate([np.clip(rgb, 0, 1), a[..., None]], -1)
    return Image.fromarray((img * 255 + 0.5).astype(np.uint8), "RGBA")


def strip_noise(seed, p, lo, hi, ax=1.0, ay=1.0):
    # Tileable along x only — use the square generator on EW x EW and crop.
    f = fbm(seed, p, lo=lo, hi=hi, ax=ax, ay=ay, n=ER)
    return f[:EHR]


def ys():
    return np.mgrid[0:EHR, 0:ER][0].astype(np.float32) / K


def edge_grass():
    L = EDGE_LINE["grass"]
    r = rng(201)
    # Layer of blades: back (dark), mid, front (bright), so tufts get depth.
    layers = []
    for li, (count, hmin, hmax, val) in enumerate(((900, 10, 40, 1.0), (700, 8, 34, 1.0), (500, 6, 26, 1.0))):
        c = Canvas(EW, EH, 3, wrap_y=False)
        tuft_x = r.uniform(0, EW, 46)
        for _ in range(count):
            if r.random() < 0.7:
                x = tuft_x[r.integers(0, len(tuft_x))] + r.normal(0, 14)
                hh = r.uniform(hmin, hmax) * r.uniform(0.85, 1.25)
            else:
                x = r.uniform(0, EW)
                hh = r.uniform(hmin * 0.6, hmax * 0.55)
            x %= EW
            y = L + r.uniform(1, 7)
            blade(c, x, y, hh, r.uniform(1.4, 2.6), r.normal(0, hh * 0.35), 255)
        layers.append(c.array())
    back, mid, front = layers
    yy = ys()
    # Turf band below the line: dense, dark, fading out with a ragged edge.
    ragged = L + 20 + strip_noise(202, 1.3, 3, 60) * 6
    turf = 1 - smooth(ragged - 10, ragged + 4, yy)
    turf *= smooth(L - 6, L - 1, yy)
    roots = np.zeros((EHR, ER), np.float32)
    c = Canvas(EW, EH, 3, wrap_y=False)
    for _ in range(260):
        x = r.uniform(0, EW)
        y = L + r.uniform(4, 16)
        pts = [(x, y)]
        for s in range(5):
            x += r.normal(0, 2.0)
            y += r.uniform(2, 5)
            pts.append((x, y))
        c.line(pts, int(r.uniform(120, 230)), r.uniform(0.7, 1.4))
    roots = c.array()
    fringe = 1 - smooth(L + 1, L + 5 + np.clip(strip_noise(203, 1.0, 6, 120) * 2, -3, 4), yy)
    fringe *= smooth(L - 5, L - 1, yy)
    alpha = np.maximum.reduce([back * 0.95, mid, front, turf * 0.92, fringe, roots * 0.7 * smooth(L, L + 6, yy) * (1 - smooth(L + 22, L + 30, yy))])
    # Colour: luminance-ish greens (vertex colour adds the map's hue).
    tipv = smooth(L + 4, L - 34, yy)          # brighter toward the tips
    v = np.zeros((EHR, ER), np.float32)
    v = np.where(back > 0.01, 0.45 + 0.30 * tipv, v)
    v = np.where(mid > 0.01, 0.62 + 0.30 * tipv, v)
    v = np.where(front > 0.01, 0.78 + 0.22 * tipv, v)
    turf_v = 0.30 + 0.08 * strip_noise(205, 1.0, 10, 200) - 0.12 * smooth(L, L + 18, yy)
    blades = np.maximum.reduce([back, mid, front])
    v = np.where(blades > 0.01, v, turf_v)
    v = np.where((roots > 0.2) & (blades < 0.01) & (yy > L + 2), 0.55, v)
    hue = np.stack([v * 0.86, v * 1.0, v * 0.62], -1)
    # Soil under the turf is browner.
    soil = np.stack([turf_v * 1.0, turf_v * 0.82, turf_v * 0.6], -1)
    w = (smooth(L + 2, L + 14, yy) * (blades < 0.01))[..., None]
    rgb = hue * (1 - w) + soil * w
    return strip_rgba(alpha, rgb)


def edge_snow():
    L = EDGE_LINE["snow"]
    r = rng(211)
    yy = ys()
    xx = (np.mgrid[0:EHR, 0:ER][1].astype(np.float32) / K)
    # Cap height profile above the line: smooth lumpy pillows.
    prof = fbm(212, 1.7, lo=3, hi=40, n=ER)[0]
    prof2 = fbm(213, 1.2, lo=12, hi=120, n=ER)[0]
    cap_h = 9 + prof * 6 + prof2 * 2.0          # texels above the line
    cap_h = np.clip(cap_h, 3, 24)
    under = 26 + fbm(214, 1.5, lo=3, hi=50, n=ER)[0] * 8   # depth below line
    # Drips / icicle-ish lobes hanging from the cap.
    drip = np.zeros(ER, np.float32)
    for _ in range(16):
        cx = r.uniform(0, EW)
        wd = r.uniform(8, 20)
        ln = r.uniform(3, 12)
        d = np.abs(((np.arange(ER) / K - cx + EW / 2) % EW) - EW / 2)
        drip = np.maximum(drip, ln * np.sqrt(np.clip(1 - (d / wd) ** 2, 0, 1)))
    bottom = L + under + drip
    topy = L - cap_h
    inside = smooth(topy[None, :] - 1.5, topy[None, :] + 1.0, yy) * (1 - smooth(bottom[None, :] - 2.0, bottom[None, :] + 1.0, yy))
    # Shading: bright top, blue-grey lower edge and inner shadow line.
    depth_from_top = yy - topy[None, :]
    up_from_bottom = bottom[None, :] - yy
    lit = 1.0 - 0.10 * smooth(2, 30, depth_from_top) - 0.22 * (1 - smooth(0, 6, up_from_bottom))
    rim = 1 - smooth(0, 2.5, depth_from_top)
    tex = strip_noise(215, 1.0, 8, 200) * 0.02
    v = np.clip(lit + rim * 0.05 + tex, 0, 1)
    rgb = np.stack([v * 0.93, v * 0.96, v * 1.0], -1)
    blue = np.array([0.62, 0.72, 0.88], np.float32)
    bw = (1 - smooth(0, 7, up_from_bottom))[..., None] * 0.45
    rgb = rgb * (1 - bw) + blue * bw
    # Sparkles.
    sp = (strip_noise(216, 0.0, 100, 2000) > 2.8).astype(np.float32) * inside
    rgb += sp[..., None] * 0.1
    return strip_rgba(inside, rgb)


def edge_sand():
    L = EDGE_LINE["sand"]
    r = rng(221)
    yy = ys()
    prof = fbm(222, 1.8, lo=2, hi=30, n=ER)[0]
    mound = np.clip(4 + prof * 3.0, 0.5, 12)
    topy = L - mound
    ragged = L + 26 + fbm(223, 1.3, lo=3, hi=80, n=ER)[0] * 7
    a = smooth(topy[None, :] - 1.2, topy[None, :] + 1.0, yy) * (1 - smooth(ragged[None, :] - 16, ragged[None, :], yy))
    ripple = np.sin(((np.mgrid[0:EHR, 0:ER][1] / K) * 0.21 + yy * 0.5) + strip_noise(224, 1.0, 4, 60) * 2) * 0.03
    v = 0.92 - 0.12 * smooth(L, L + 22, yy) + ripple + strip_noise(225, 0.2, 60, 900) * 0.02
    rgb = np.stack([v, v * 0.93, v * 0.80], -1)
    # A few pebbles sitting on the lip.
    c = Canvas(EW, EH, 3, wrap_y=False)
    for _ in range(60):
        x = r.uniform(0, EW)
        rr = r.uniform(1.5, 4.5)
        c.ellipse(x, L - rr * 0.6, rr * 1.3, rr, int(r.uniform(140, 255)))
    peb = c.array()
    pv = 0.45 + 0.3 * peb
    rgb = rgb * (1 - peb[..., None]) + np.stack([pv, pv * 0.95, pv * 0.88], -1) * peb[..., None]
    a = np.maximum(a, peb)
    return strip_rgba(a * 0.95, rgb)


def edge_dirt():
    L = EDGE_LINE["dirt"]
    r = rng(231)
    yy = ys()
    c = Canvas(EW, EH, 3, wrap_y=False)
    vals = np.zeros((EHR, ER), np.float32)
    # Crumbs and pebbles along the lip.
    for _ in range(420):
        x = r.uniform(0, EW)
        rr = r.uniform(1.0, 4.2)
        y = L - rr * r.uniform(0.2, 0.8)
        c.ellipse(x, y, rr * r.uniform(1.0, 1.6), rr, int(r.uniform(90, 255)))
    peb = c.array()
    # Sparse dry tufts.
    t = Canvas(EW, EH, 3, wrap_y=False)
    for _ in range(22):
        cx = r.uniform(0, EW)
        for _ in range(int(r.uniform(4, 12))):
            hh = r.uniform(6, 20)
            blade(t, (cx + r.normal(0, 4)) % EW, L + 2, hh, r.uniform(1.0, 1.8), r.normal(0, hh * 0.4), 255)
    tuft = t.array()
    ragged = L + 18 + fbm(232, 1.3, lo=3, hi=80, n=ER)[0] * 6
    band = smooth(L - 2, L, yy) * (1 - smooth(ragged[None, :] - 12, ragged[None, :], yy))
    nz = strip_noise(233, 0.6, 20, 600)
    v = 0.70 - 0.2 * smooth(L, L + 16, yy) + nz * 0.04
    rgb = np.stack([v, v * 0.86, v * 0.68], -1)
    pv = 0.45 + 0.4 * peb
    rgb = rgb * (1 - peb[..., None]) + np.stack([pv, pv * 0.92, pv * 0.82], -1) * peb[..., None]
    tv = 0.55 + 0.35 * smooth(L + 2, L - 18, yy)
    rgb = rgb * (1 - tuft[..., None]) + np.stack([tv * 0.95, tv * 0.88, tv * 0.55], -1) * tuft[..., None]
    a = np.maximum.reduce([band * 0.85, peb, tuft])
    return strip_rgba(a, rgb)


def edge_rock():
    L = EDGE_LINE["rock"]
    r = rng(241)
    yy = ys()
    # Chipped bright rim: thickness varies, chips cut into it.
    th = np.clip(5.5 + fbm(242, 1.4, lo=4, hi=90, n=ER)[0] * 2.0, 1.5, 10)
    chips = smooth(1.2, 1.8, fbm(243, 1.0, lo=10, hi=200, n=ER)[0])
    th = th * (1 - 0.7 * chips)
    dy = yy - L
    rim = smooth(-1.6, 0.0, dy) * (1 - smooth(th[None, :] - 1.0, th[None, :] + 0.8, dy))
    glow = smooth(-1.0, 0.5, dy) * np.exp(-np.maximum(dy, 0) / 10.0) * 0.55
    # Little cracks dropping from the rim.
    c = Canvas(EW, EH, 3, wrap_y=False)
    for _ in range(40):
        x = r.uniform(0, EW)
        y = L + r.uniform(1, 4)
        pts = [(x, y)]
        for s in range(2):
            x += r.normal(0, 2.5)
            y += r.uniform(2, 6)
            pts.append((x, y))
        c.line(pts, 255, r.uniform(0.8, 1.6))
    cr = c.array()
    a = np.clip(np.maximum(rim, glow) - cr * 0.0, 0, 1)
    v = 0.90 + strip_noise(244, 0.6, 20, 600) * 0.03
    rgb = np.stack([v, v * 0.98, v * 0.94], -1)
    # Cracks: dark, in their own alpha.
    dark = cr * smooth(L, L + 3, yy)
    rgb = rgb * (1 - dark[..., None]) + 0.08 * dark[..., None]
    a = np.maximum(a, dark * 0.3)
    return strip_rgba(a, rgb)


def edge_metal():
    L = EDGE_LINE["metal"]
    r = rng(251)
    yy = ys()
    dy = yy - L
    bevel = smooth(-1.4, 0.0, dy) * (1 - smooth(2.0, 3.5, dy))
    shadow = smooth(2.5, 4.0, dy) * (1 - smooth(4.0, 7.0, dy))
    # Worn paint: bright scuffs fading into the plate.
    wear = smooth(0.6, 1.6, strip_noise(252, 1.0, 10, 300) - dy / 14.0) * smooth(3.0, 5.0, dy) * (1 - smooth(10, 22, dy))
    c = Canvas(EW, EH, 3, wrap_y=False)
    for _ in range(200):
        x = r.uniform(0, EW)
        y = L + r.uniform(3, 18)
        a = r.normal(0, 0.25)
        ln = r.uniform(4, 22)
        c.line([(x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln)], 255, r.uniform(0.6, 1.1))
    scr = c.array() * (1 - smooth(10, 24, dy))
    a = np.maximum.reduce([bevel, shadow * 0.5, wear * 0.7, scr * 0.6])
    v = np.where(shadow > bevel, 0.12, 0.95)
    v = np.where((wear > 0.05) & (bevel < 0.1) & (shadow < 0.2), 0.78, v)
    v = np.where((scr > 0.1) & (bevel < 0.1), 0.9, v)
    rgb = np.stack([v, v, v * 1.02], -1)
    return strip_rgba(a, rgb)


def edge_roots():
    L = EDGE_LINE["roots"]
    r = rng(261)
    yy = ys()
    c = Canvas(EW, EH, 3, wrap_y=False)
    leaves = Canvas(EW, EH, 3, wrap_y=False)
    for _ in range(150):
        x = r.uniform(0, EW)
        y = L - 2
        ln = r.uniform(8, 110) if r.random() < 0.85 else r.uniform(60, 116)
        w = r.uniform(0.8, 2.4)
        pts = [(x, y)]
        sway = r.normal(0, 0.6)
        steps = int(ln / 5) + 1
        for s in range(steps):
            x += sway + r.normal(0, 0.8)
            y += 5
            pts.append((x, y))
        for s in range(len(pts) - 1):
            c.line([pts[s], pts[s + 1]], 255, w * (1 - 0.6 * s / len(pts)))
        if r.random() < 0.35:
            for s in range(2, len(pts), 3):
                lx, ly = pts[s]
                side = r.choice([-1, 1])
                leaves.poly([(lx, ly), (lx + side * 3.5, ly + 1.0), (lx + side * 6.5, ly + 4.5), (lx + side * 2.5, ly + 3.0)], 255)
    rt = c.array() * (1 - smooth(EH - 14, EH - 2, yy))
    lv = leaves.array() * (1 - smooth(EH - 14, EH - 2, yy))
    band = smooth(L - 4, L - 1, yy) * (1 - smooth(L + 2, L + 10, yy))
    a = np.maximum.reduce([rt, lv, band * 0.7])
    v = 0.42 + 0.1 * strip_noise(262, 1.0, 10, 300)
    rgb = np.stack([v * 0.95, v * 0.78, v * 0.55], -1)
    rgb = rgb * (1 - lv[..., None]) + np.array([0.40, 0.55, 0.25]) * lv[..., None]
    return strip_rgba(a, rgb)


def edge_icicles():
    L = EDGE_LINE["icicles"]
    r = rng(271)
    yy = ys()
    xx = (np.mgrid[0:EHR, 0:ER][1].astype(np.float32) / K)
    a = np.zeros((EHR, ER), np.float32)
    shade = np.zeros((EHR, ER), np.float32)
    # Cluster icicles; sizes vary a lot.
    for _ in range(120):
        cx = r.uniform(0, EW)
        ln = r.uniform(6, 100) * (r.random() ** 0.6)
        wd = max(2.0, ln * r.uniform(0.07, 0.16))
        d = ((xx - cx + EW / 2) % EW) - EW / 2
        t = (yy - L) / max(ln, 1)
        prof = wd * np.clip(1 - t, 0, 1) ** 1.3
        inside = smooth(0.8, -0.6, np.abs(d) - prof) * (t > -0.15) * (t < 1)
        a = np.maximum(a, inside)
        shade = np.maximum(shade, inside * (0.5 + 0.5 * np.clip(-d / np.maximum(prof, 0.5), -1, 1)))
    band = smooth(L - 4, L - 1, yy) * (1 - smooth(L + 1, L + 5, yy))
    a = np.maximum(a * 0.85, band * 0.9)
    v = 0.78 + 0.2 * shade
    rgb = np.stack([v * 0.88, v * 0.95, v * 1.0], -1)
    return strip_rgba(a, rgb)


EDGES = {"grass": edge_grass, "snow": edge_snow, "sand": edge_sand, "dirt": edge_dirt,
         "rock": edge_rock, "metal": edge_metal, "roots": edge_roots, "icicles": edge_icicles}


# ── output ──────────────────────────────────────────────────────────────────

IMPORT_TEMPLATE = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://assets/terrain-hd/{name}"

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
detect_3d/compress_to=0
"""


def import_params(name):
    """Materials: lossy (WebP in the export, ~3 MB per material on disk,
    uncompressed RGBA8 in VRAM; terrain_hd.gd halves them at load on Medium).
    Not VRAM-compressed: Basis / S3TC sampled ~4x slower on software GL and
    the Android export would carry two copies. Edge strips stay lossless."""
    if name.startswith("edge_"):
        return {"compress/mode": "0", "compress/normal_map": "0", "compress/lossy_quality": "0.7"}
    if "_n." in name:
        return {"compress/mode": "1", "compress/normal_map": "2", "compress/lossy_quality": "0.95"}
    return {"compress/mode": "1", "compress/normal_map": "2", "compress/lossy_quality": "0.9"}


def patch_import(path):
    """Make sure the PNG imports lossless with mipmaps (and never switches to
    VRAM compression when it is used in 3D). Writes a template when Godot has
    not created the .import yet."""
    imp = path + ".import"
    name = os.path.basename(path)
    want = {"mipmaps/generate": "true", "detect_3d/compress_to": "0"}
    want.update(import_params(name))
    if not os.path.exists(imp):
        txt = IMPORT_TEMPLATE.format(name=name)
    else:
        txt = open(imp).read()
    out = []
    for line in txt.splitlines():
        key = line.split("=", 1)[0]
        if key in want:
            line = "%s=%s" % (key, want[key])
        out.append(line)
    new = "\n".join(out) + "\n"
    if not os.path.exists(imp) or new != txt:
        with open(imp, "w") as f:
            f.write(new)


def save_png(img, name):
    path = os.path.join(OUT, name)
    if name.endswith(".webp"):
        img.save(path, "WEBP", quality=95, method=6)
    else:
        img.save(path, optimize=True)
    patch_import(path)
    return path


def mean_color(alb):
    return alb.reshape(-1, 3).mean(0)


def write_material(name):
    alb, h, strength = MATERIALS[name]()
    alb = np.clip(alb, 0, 1)
    n = normal_map(h, strength)
    # 2048 px sources as WebP q95 (a lossless PNG pair would be ~13 MB per
    # material in the repo; the export stores them lossy anyway).
    save_png(to_img(alb), name + MAT_EXT)
    save_png(normal_img(n), name + "_n" + MAT_EXT)
    return alb, n


def lit_preview(alb, n, tint=None):
    L = np.array([-0.45, 0.70, 0.55])   # from upper left; tangent space y up
    L /= np.linalg.norm(L)
    d = np.clip((n * L).sum(-1), 0, 1)
    flat = L[2]
    shade = (0.55 + 0.45 * d / flat)
    out = alb * shade[..., None]
    if tint is not None:
        out = out / alb.reshape(-1, 3).mean(0) * np.array(tint)
    return np.clip(out, 0, 1)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    sheet = None
    for a in sys.argv[1:]:
        if a.startswith("--sheet="):
            sheet = a.split("=", 1)[1]
    os.makedirs(OUT, exist_ok=True)
    mats = [a for a in args if a in MATERIALS] or (list(MATERIALS) if not args else [])
    edges = [a[5:] for a in args if a.startswith("edge_") and a[5:] in EDGES] or (list(EDGES) if not args else [])
    previews = []
    meta_path = os.path.join(OUT, "materials.json")
    meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
    for m in mats:
        alb, n = write_material(m)
        mc = mean_color(alb)
        print("material %-9s mean %s" % (m, np.round(mc, 3)))
        # Mean albedo: terrain_hd.gd divides by it so the map tint sets the colour.
        meta[m] = {"mean": [round(float(v), 4) for v in mc]}
    if mats:
        with open(meta_path, "w") as f:
            json.dump(dict(sorted(meta.items())), f, indent=1)
            f.write("\n")
        previews.append((m, lit_preview(alb, n)))
    for e in edges:
        img = EDGES[e]()
        save_png(img, "edge_%s.png" % e)
        print("edge %s" % e)
    if sheet and previews:
        cell = 512
        cols = 4
        rows = (len(previews) + cols - 1) // cols
        S = Image.new("RGB", (cols * cell, rows * cell), (20, 20, 20))
        for i, (m, im) in enumerate(previews):
            # Top-left quarter at 1:1 texels (= 2x zoom-ish), 512 px.
            S.paste(to_img(im[:cell, :cell]), ((i % cols) * cell, (i // cols) * cell))
            ImageDraw.Draw(S).text(((i % cols) * cell + 6, (i // cols) * cell + 6), m, fill=(255, 255, 0))
        S.save(sheet)


if __name__ == "__main__":
    main()
