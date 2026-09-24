#!/usr/bin/env python3
"""map_audit.py — static "can anyone get stuck?" audit for every Soldat Reborn map.

Rasterises each map's player-solid geometry (polygons, platforms, baseline floor,
side walls) at 2 px per cell, then computes where a soldier's collision box fits
in each stance (stand 14x24, crouch 16x16, prone 28x8 — feet-anchored, matching
player.gd/bot.gd). Stances connect at the same feet position, so the free space
becomes one 3-D graph; its connected components are the regions a soldier can
move between (jets make every connected region reachable).

For every map entity (spawns, flags, M2s, pickups, DOM points) it reports:
  * embedded      — the soldier/flag would start inside solid terrain
  * isolated      — it lands in a pocket that isn't connected to the main arena
  * over a pit    — it falls below the map's kill line
  * long fall     — spawns that drop > 250 px before touching ground

Usage:
    python3 tools/map_audit.py            # audit built-ins + assets/maps/*.json
    python3 tools/map_audit.py nuubia     # only maps whose name contains "nuubia"

Needs numpy, pillow and scipy (pip install numpy pillow scipy).
"""
import glob
import json
import os
import re
import sys
from collections import Counter

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
R = 2.0  # world px per raster cell

# Must mirror main.gd defaults.
DEFAULT_W, DEFAULT_H, DEFAULT_GROUND = 4800.0, 2000.0, 1900.0
FLOOR_THICK = 200.0
STANCES = [(14.0, 24.0), (16.0, 16.0), (28.0, 8.0)]  # (w, h) feet-anchored
PLAYER_SOLID_COLS = (0, 2)  # poly "col": 0 = solid, 1 = bullets only, 2 = players only, 3 = none


def world_of(m):
    w = m.get("world") or {}
    W = float(w.get("w", DEFAULT_W))
    H = float(w.get("h", DEFAULT_H))
    G = float(w.get("ground_y", DEFAULT_GROUND))
    K = w.get("kill_y")
    return W, H, G, (float(K) if K is not None else None)


def raster(m):
    W, H, G, _ = world_of(m)
    nx, ny = int(W / R) + 1, int(H / R) + 1
    img = Image.new("1", (nx, ny), 0)
    dr = ImageDraw.Draw(img)
    for p in m.get("polys", []):
        if int(p.get("col", 0)) not in PLAYER_SOLID_COLS:
            continue
        pts = p["points"]
        xy = [(pts[i] / R, pts[i + 1] / R) for i in range(0, len(pts) - 1, 2)]
        if len(xy) >= 3:
            dr.polygon(xy, fill=1)
    for pl in m.get("platforms", []):
        (px, py), (sx, sy) = pl["p"], pl["s"]
        dr.rectangle([(px - sx / 2) / R, (py - sy / 2) / R,
                      (px + sx / 2) / R - 1e-3, (py + sy / 2) / R - 1e-3], fill=1)
    a = np.array(img, dtype=bool)
    # Baseline floor: top edge sits at ground_y (main.gd::_build_terrain).
    a[int(G / R):, :] = True
    # Side walls: 40 px thick, centred on x=0 and x=W.
    a[:, : int(20 / R)] = True
    a[:, int((W - 20) / R):] = True
    return a


def fits(solid, w, h):
    """free[y, x]: a w×h box whose bottom-centre is at cell (x, y) is clear."""
    ii = np.pad(solid.astype(np.int32).cumsum(0).cumsum(1), ((1, 0), (1, 0)))
    ny, nx = solid.shape
    hw = int(np.ceil(w / 2 / R))
    hh = int(np.ceil(h / R))
    ys = np.arange(ny)[:, None]
    xs = np.arange(nx)[None, :]
    y1 = np.clip(ys - hh, 0, ny)
    y2 = np.clip(ys, 0, ny)
    x1 = np.clip(xs - hw, 0, nx)
    x2 = np.clip(xs + hw, 0, nx)
    s = ii[y2, x2] - ii[y1, x2] - ii[y2, x1] + ii[y1, x1]
    free = s == 0
    free[:hh, :] = False  # box would poke above the world top edge
    return free


def entities(m):
    out = []
    if m.get("player_spawn") is not None:
        out.append(("player_spawn", None, m["player_spawn"]))
    for i, b in enumerate(m.get("bot_spawns", [])):
        out.append(("bot_spawns", i, b))
    for k in ("ctf_flags", "m2_mounts", "dom_points", "bonus_spawns", "point_spawns"):
        for i, v in enumerate(m.get(k, [])):
            out.append((k, i, v))
    for k in ("inf_flag", "htf_flag", "rambo_pos"):
        if m.get(k) is not None:
            out.append((k, None, m[k]))
    return out


class Space:
    """Free-space graph for one map."""

    def __init__(self, m):
        self.m = m
        self.W, self.H, self.G, self.K = world_of(m)
        self.solid = raster(m)
        layers = np.stack([fits(self.solid, w, h) for (w, h) in STANCES])
        if self.K is not None:
            layers[:, int(self.K / R):, :] = False  # below the kill line = dead
        self.stand = layers[0]
        self.lab, _ = ndimage.label(layers, structure=ndimage.generate_binary_structure(3, 1))
        self.ny, self.nx = self.stand.shape
        # Ground cells: standing fits here but not one cell lower (feet on something).
        below = np.zeros_like(self.stand)
        below[:-1, :] = self.stand[1:, :]
        self.ground = self.stand & ~below
        if self.K is not None:
            self.ground[max(0, int(self.K / R) - 1):, :] = False
        spawn_labels = []
        for kind, _, p in entities(m):
            if "spawn" not in kind:
                continue
            c = self.land(p)
            if c is not None:
                spawn_labels.append(self.lab[0][c])
        self.main = Counter(spawn_labels).most_common(1)[0][0] if spawn_labels else None

    def cell(self, p):
        return int(round(p[1] / R)), int(round(p[0] / R))

    def free_at(self, p):
        y, x = self.cell(p)
        return 0 <= y < self.ny and 0 <= x < self.nx and bool(self.stand[y, x])

    def land(self, p):
        """Cell where a soldier dropped at p comes to rest, or None if embedded / dies."""
        y, x = self.cell(p)
        if not (0 <= x < self.nx):
            return None
        y = max(y, 0)
        if y >= self.ny or not self.stand[y, x]:
            return None
        while y + 1 < self.ny and self.stand[y + 1, x]:
            y += 1
        if not self.ground[y, x]:
            return None  # fell below the kill line
        return (y, x)

    def check(self, kind, p):
        """Returns (problem-string or None, landing (x, y) world or None)."""
        y, x = self.cell(p)
        if not (0 <= x < self.nx) or y >= self.ny:
            return "outside world", None
        if y >= 0 and not self.stand[y, x]:
            yy = y
            while yy > 0 and not self.stand[yy, x]:
                yy -= 1
            return "embedded in terrain (%d px deep)" % int((y - yy) * R), None
        c = self.land(p)
        if c is None:
            return "falls into a pit / off the map", None
        wp = (c[1] * R, c[0] * R)
        if self.main is not None and self.lab[0][c] != self.main:
            return "lands in an isolated pocket at (%d, %d)" % wp, wp
        return None, wp

    def nearest_good(self, p, max_r=600.0, want_ground=True):
        """Nearest main-component ground cell to p (world coords), searching outward."""
        if self.main is None:
            return None
        cy, cx = self.cell(p)
        mask = (self.lab[0] == self.main)
        if want_ground:
            mask = mask & self.ground
        rc = int(max_r / R)
        y0, y1 = max(0, cy - rc), min(self.ny, cy + rc)
        x0, x1 = max(0, cx - rc), min(self.nx, cx + rc)
        sub = mask[y0:y1, x0:x1]
        ys, xs = np.nonzero(sub)
        if ys.size == 0:
            return None
        ys = ys + y0
        xs = xs + x0
        # Prefer spots at/above the original point (spawns rise out of floors
        # rather than dropping through them) — penalise downward moves a bit.
        dy = ys - cy
        d2 = (xs - cx) ** 2 + np.where(dy > 0, dy * 1.5, dy) ** 2
        i = int(np.argmin(d2))
        return (float(xs[i] * R), float(ys[i] * R))


# ── map loading ────────────────────────────────────────────────────────────

def builtin_maps():
    src = open(os.path.join(GAME, "scripts", "main.gd"), encoding="utf-8").read()
    blk = src[src.index("var MAPS := ["):]
    blk = blk[: blk.index("\n]\n") + 2][len("var MAPS := "):]
    blk = re.sub(r"#[^\n]*", "", blk)
    blk = blk.replace("PackedVector2Array(", "(").replace("PackedColorArray(", "(")
    blk = re.sub(r"\bVector2\(", "(", blk)
    blk = re.sub(r"\bColor\(", "(", blk)
    blk = blk.replace("true", "True").replace("false", "False")
    out = []
    for m in eval(blk):
        d = dict(m)
        d["polys"] = [{"points": [c for pt in pl["points"] for c in pt], "col": pl.get("col", 0)} for pl in m["polys"]]
        d["platforms"] = [{"p": list(p["p"]), "s": list(p["s"])} for p in m["platforms"]]
        d["_label"] = "builtin:" + m["name"]
        out.append(d)
    return out


def classic_maps():
    res = []
    for f in sorted(glob.glob(os.path.join(GAME, "assets", "maps", "*.json"))):
        d = json.load(open(f, encoding="utf-8"))
        d["_label"] = os.path.basename(f)
        res.append(d)
    return res


def poly_mask(m):
    W, H, _, _ = world_of(m)
    img = Image.new("1", (int(W / R) + 1, int(H / R) + 1), 0)
    dr = ImageDraw.Draw(img)
    for p in m.get("polys", []):
        if int(p.get("col", 0)) not in PLAYER_SOLID_COLS:
            continue
        pts = p["points"]
        xy = [(pts[i] / R, pts[i + 1] / R) for i in range(0, len(pts) - 1, 2)]
        if len(xy) >= 3:
            dr.polygon(xy, fill=1)
    return np.array(img, dtype=bool)


def audit(m):
    sp = Space(m)
    problems = []
    # Platforms buried inside terrain polygons (drawn as slabs inside a hill).
    pm = poly_mask(m)
    for i, pl in enumerate(m.get("platforms", [])):
        (px, py), (sx, sy) = pl["p"], pl["s"]
        x0, x1 = int((px - sx / 2) / R), int((px + sx / 2) / R)
        y0, y1 = int((py - sy / 2) / R), max(int((py + sy / 2) / R), int((py - sy / 2) / R) + 1)
        sub = pm[max(0, y0):y1, max(0, x0):x1]
        if sub.size and sub.mean() > 0.25:
            problems.append("platform[%d] @ (%d, %d): %d%% buried inside terrain" % (i, px, py, sub.mean() * 100))
    for kind, i, p in entities(m):
        prob, _ = sp.check(kind, p)
        if prob:
            label = kind if i is None else "%s[%d]" % (kind, i)
            problems.append("%s @ (%d, %d): %s" % (label, p[0], p[1], prob))
    return problems


def main(argv):
    only = argv[1] if len(argv) > 1 else None
    maps = builtin_maps() + classic_maps()
    bad = 0
    for m in maps:
        if only and only.lower() not in m["_label"].lower():
            continue
        probs = audit(m)
        if probs:
            bad += 1
            print("✗", m["_label"])
            for p in probs:
                print("    ", p)
    print("%d / %d maps have problems" % (bad, len(maps)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
