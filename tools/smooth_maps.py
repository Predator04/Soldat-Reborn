#!/usr/bin/env python3
"""smooth_maps.py — round the classic maps' jagged corners (#273).

Post-process for the ported maps (tools/pms_to_map.py output). Per map:

  1. Collision: every collision class (0 solid, 1 bullets only, 2 players only)
     is unioned and each outline corner gets a small circular fillet. The
     fillet is limited by the corner's displacement (D_MAX px), its tangent
     length (T_MAX px, EDGE_FRAC of the shorter neighbouring edge) and skipped
     where it could change the map's topology: corners that touch another
     collision class, fillets that would cross another edge, and fillets with
     less than CLEAR px of free space to a non-neighbouring surface (narrow
     gaps, tunnels, doorways, thin plates). The result is re-split into convex
     pieces (same splitter the porter uses) for CollisionPolygon2D — only the
     pieces a fillet touches; the rest stay byte-identical.
  2. Validation (per map, iterated): polygon / hole counts per class must not
     change, the soldier free-space graph (tools/map_audit.py raster, every
     stance) must keep the same connected regions — no region split (a gap
     closed) or merged (a gap opened) — the bot nav graph (tools/build_nav.py)
     must keep its main region strongly connected, and every spawn / flag /
     pickup / vehicle spot must audit exactly as before. Corners near a failure are
     put back to sharp and the map is redone.
  3. Visuals follow the new outline: triangles of a collision class lose the
     material outside the rounded convex corners, and the new fillet material
     in concave corners is filled with triangles whose UVs / vertex colours
     extrapolate the neighbouring triangle, so the texture continues. Purely
     decorative overlay triangles lying inside solid ground are trimmed too.
  4. Smooth shading: coincident vertices (<= WELD_EPS px) of the same class
     are welded and their vertex colours area-weighted averaged, unless the
     colours differ by more than COLOR_THR on any channel (a deliberate hard
     edge stays hard).

The pre-smoothing geometry ("polys" + "collision") is kept gzipped in
tools/map_src/<map>.json.gz, so re-running is deterministic (always from the
original) and `--restore` brings the unsmoothed map back. pms_to_map.py
--regen calls this automatically on every regenerated map.

    python3 tools/smooth_maps.py                 # all classic maps
    python3 tools/smooth_maps.py jungle arena    # maps whose file stem contains a word
    python3 tools/smooth_maps.py --dry           # report only, write nothing
    python3 tools/smooth_maps.py --restore       # write the original geometry back
    python3 tools/smooth_maps.py --stats out.json

Afterwards run tools/map_audit.py, tools/build_nav.py and tools/make_thumbs.py.
Needs numpy, scipy, pillow, shapely >= 2.1.
"""
import copy
import glob
import gzip
import json
import math
import os
import sys

import numpy as np
from scipy import ndimage
from shapely.geometry import LineString, Point, Polygon
from shapely.geometry.polygon import orient
from shapely.ops import unary_union
import shapely

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
MAPS_DIR = os.path.join(GAME, "assets", "maps")
SRC_DIR = os.path.join(HERE, "map_src")
sys.path.insert(0, HERE)
import map_audit as MA  # noqa: E402
import build_nav as BN  # noqa: E402
import pms_to_map as PM  # noqa: E402

VERSION = 1
# Maps whose geometry is hand-tuned: never touched.
EXCLUDE = {"movement_course"}   # calibrated tap / hold jump gaps (#262)

# Fillet limits.
D_MAX = 4.0          # max distance the outline moves at a corner (px)
T_MAX = 24.0         # max tangent length (px) — how far along each edge the arc starts
EDGE_FRAC = 0.42     # tangent length <= this fraction of the shorter adjacent edge
MIN_TURN = math.radians(8.0)    # flatter corners are already smooth
MIN_T = 0.75         # smaller fillets are invisible — skip
SEG_DEG = 22.5       # arc subdivision: at most this many degrees per segment
MIN_SEG = 2.5        # ... and segments at least this long (terrain_fx skips edges < 2 px)
# Topology guards.
TOUCH = 1.5          # a corner this close to another collision class stays sharp
CLEAR = 34.0         # free space a fillet needs to any non-neighbouring surface
LOCAL_PATH = 48.0    # edges this far along the same outline count as "the same surface"
ENTITY_R = 64.0
NAV_R = 128.0        # ... and corners near a bot link the smoothing broke      # corners near an entity whose audit changed go back to sharp
AREA_LIMIT = 2.0     # % — larger class area change gets a smaller D_MAX
# Free-space comparison (map_audit raster cells, 2 px).
BIG_COMP = 150       # free regions smaller than this (cells, all stances) are ignored
SPLIT_MIN = 60       # a second piece this big = region split
# Visual welding.
WELD_EPS = 0.5
COLOR_THR = 96       # max per-channel (0-255) difference that still gets blended

ENTITY_KEYS_POINT = ("player_spawn", "inf_flag", "htf_flag", "rambo_pos")
UNAUDITED = ("medkits", "grenade_kits", "vehicle_spawns", "tank_spawns", "heli_spawns")
ENTITY_KEYS_LIST = ("bot_spawns", "ctf_flags", "m2_mounts", "dom_points", "point_spawns",
                    "medkits", "grenade_kits", "vehicle_spawns", "tank_spawns", "heli_spawns", "bonus_spawns")


# ── small helpers ──────────────────────────────────────────────────────────

def _pts(flat):
    return [(flat[i], flat[i + 1]) for i in range(0, len(flat) - 1, 2)]


def _hex_to_rgba(h):
    return [int(h[i:i + 2], 16) for i in (0, 2, 4, 6)]


def _rgba_to_hex(c):
    return "%02x%02x%02x%02x" % tuple(max(0, min(255, int(round(v)))) for v in c)


def _tri_area(a, b, c):
    return abs((b[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (b[1] - a[1])) * 0.5


def _bary(p, a, b, c):
    v0x, v0y = b[0] - a[0], b[1] - a[1]
    v1x, v1y = c[0] - a[0], c[1] - a[1]
    v2x, v2y = p[0] - a[0], p[1] - a[1]
    d = v0x * v1y - v1x * v0y
    if abs(d) < 1e-9:
        return None
    l1 = (v2x * v1y - v1x * v2y) / d
    l2 = (v0x * v2y - v2x * v0y) / d
    return (1.0 - l1 - l2, l1, l2)


def _min_angle(a, b, c):
    def ang(p, q, r):
        ux, uy = q[0] - p[0], q[1] - p[1]
        vx, vy = r[0] - p[0], r[1] - p[1]
        nu, nv = math.hypot(ux, uy), math.hypot(vx, vy)
        if nu < 1e-9 or nv < 1e-9:
            return 0.0
        return math.acos(max(-1.0, min(1.0, (ux * vx + uy * vy) / (nu * nv))))
    return min(ang(a, b, c), ang(b, c, a), ang(c, a, b))


def _polys_of(g):
    if g is None or g.is_empty:
        return []
    if g.geom_type == "Polygon":
        return [g]
    out = []
    for h in getattr(g, "geoms", []):
        out.extend(_polys_of(h))
    return out


def _clean_coords(coords):
    """Ring coords (closed) -> open list without duplicates / collinear points."""
    pts = []
    for (x, y) in coords:
        if not pts or abs(x - pts[-1][0]) > 1e-6 or abs(y - pts[-1][1]) > 1e-6:
            pts.append((float(x), float(y)))
    if len(pts) > 1 and abs(pts[0][0] - pts[-1][0]) < 1e-6 and abs(pts[0][1] - pts[-1][1]) < 1e-6:
        pts.pop()
    changed = True
    while changed and len(pts) > 3:
        changed = False
        for i in range(len(pts)):
            a, b, c = pts[i - 1], pts[i], pts[(i + 1) % len(pts)]
            cr = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
            ln = math.hypot(c[0] - a[0], c[1] - a[1])
            if ln < 1e-9 or abs(cr) / ln < 0.03:
                pts.pop(i)
                changed = True
                break
    return pts


def class_unions(coll):
    out = {}
    for c in (0, 1, 2):
        shapes = [Polygon(_pts(e["points"])).buffer(0) for e in coll
                  if int(e.get("col", 0)) == c and len(e["points"]) >= 6]
        shapes = [s for s in shapes if not s.is_empty]
        if shapes:
            out[c] = unary_union(shapes).buffer(0)
    return out


# ── fillets ────────────────────────────────────────────────────────────────

class Ring:
    def __init__(self, cls, pid, rid, pts):
        self.cls, self.pid, self.rid, self.pts = cls, pid, rid, pts
        n = len(pts)
        self.lens = [math.hypot(pts[(i + 1) % n][0] - pts[i][0], pts[(i + 1) % n][1] - pts[i][1]) for i in range(n)]
        self.cum = [0.0]
        for L in self.lens:
            self.cum.append(self.cum[-1] + L)
        self.per = self.cum[-1]

    def path_dist(self, i, j):
        """Distance along the ring from vertex i to edge j (0 if adjacent)."""
        s = self.cum[i]
        a, b = self.cum[j], self.cum[j + 1]
        if a <= s <= b:
            return 0.0
        d = min(abs(s - a), abs(s - b))
        return min(d, self.per - d)


def corner_fillet(a, b, c, d_max):
    """Fillet geometry at b (solid on the left of a->b->c): None or dict."""
    e1 = (b[0] - a[0], b[1] - a[1])
    e2 = (c[0] - b[0], c[1] - b[1])
    L1, L2 = math.hypot(*e1), math.hypot(*e2)
    if L1 < 1e-6 or L2 < 1e-6:
        return None
    u1 = (e1[0] / L1, e1[1] / L1)
    u2 = (e2[0] / L2, e2[1] / L2)
    cr = u1[0] * u2[1] - u1[1] * u2[0]
    dt = u1[0] * u2[0] + u1[1] * u2[1]
    th = math.atan2(cr, dt)
    ath = abs(th)
    if ath < MIN_TURN or ath > math.radians(170.0):
        return None
    t = min(EDGE_FRAC * L1, EDGE_FRAC * L2, T_MAX, d_max / math.tan(ath / 4.0))
    if t < MIN_T:
        return None
    r = t / math.tan(ath / 2.0)
    p1 = (b[0] - u1[0] * t, b[1] - u1[1] * t)
    p2 = (b[0] + u2[0] * t, b[1] + u2[1] * t)
    sgn = 1.0 if th > 0 else -1.0
    nrm = (-u1[1] * sgn, u1[0] * sgn)
    ctr = (p1[0] + nrm[0] * r, p1[1] + nrm[1] * r)
    arc_len = r * ath
    n = max(1, min(int(math.ceil(math.degrees(ath) / SEG_DEG)), int(arc_len // MIN_SEG)))
    arc = []
    vx, vy = p1[0] - ctr[0], p1[1] - ctr[1]
    for k in range(n + 1):
        ang = th * k / n
        ca, sa = math.cos(ang), math.sin(ang)
        arc.append((ctr[0] + vx * ca - vy * sa, ctr[1] + vx * sa + vy * ca))
    arc[0], arc[-1] = p1, p2
    sliver = Polygon([b] + arc[::-1]) if n >= 1 else None
    if sliver is None or not sliver.is_valid or sliver.area < 1e-4:
        sliver = Polygon([p1, b, p2]).buffer(0)
    disp = r / math.cos(ath / 2.0) - r
    return {"arc": arc, "convex": th > 0, "sliver": sliver, "t": t, "disp": disp}


def smooth_classes(unions, blocked, d_max_by_cls):
    """Fillet every class union. Returns (smoothed unions, corner list, skip counts)."""
    rings = []
    shapes = {}
    for c, u in unions.items():
        polys = []
        for pid, p in enumerate(_polys_of(u)):
            p = orient(p, 1.0)
            ext = _clean_coords(p.exterior.coords)
            ints = [_clean_coords(r.coords) for r in p.interiors if Polygon(r).area >= 1.0]
            ints = [r for r in ints if len(r) >= 3]
            polys.append((ext, ints))
            rings.append(Ring(c, pid, 0, ext))
            for k, r in enumerate(ints):
                rings.append(Ring(c, pid, k + 1, r))
        shapes[c] = polys
    segs, owners = [], []
    for ri, R in enumerate(rings):
        n = len(R.pts)
        for j in range(n):
            segs.append(LineString([R.pts[j], R.pts[(j + 1) % n]]))
            owners.append((ri, j))
    tree = shapely.STRtree(segs)
    other_cls_geom = {c: unary_union([u2 for c2, u2 in unions.items() if c2 != c]) if len(unions) > 1 else None
                      for c in unions}
    corners = []
    skips = {"touch": 0, "cross": 0, "clear": 0, "blocked": 0}
    new_rings = {}
    for ri, R in enumerate(rings):
        pts = R.pts
        n = len(pts)
        out = []
        if n < 3:
            new_rings[ri] = pts
            continue
        for i in range(n):
            a, b, c = pts[i - 1], pts[i], pts[(i + 1) % n]
            f = corner_fillet(a, b, c, d_max_by_cls.get(R.cls, D_MAX))
            if f is None:
                out.append(b)
                continue
            key = (R.cls, round(b[0], 2), round(b[1], 2))
            if key in blocked:
                skips["blocked"] += 1
                out.append(b)
                continue
            og = other_cls_geom.get(R.cls)
            if og is not None and not og.is_empty and og.distance(Point(b)) < TOUCH:
                skips["touch"] += 1
                out.append(b)
                continue
            sl = f["sliver"]
            ok = True
            adj = {(ri, (i - 1) % n), (ri, i)}
            for k in tree.query(sl.buffer(0.01), predicate="intersects"):
                if owners[k] not in adj:
                    ok = False
                    break
            if not ok:
                skips["cross"] += 1
                out.append(b)
                continue
            zone = sl.buffer(CLEAR)
            for k in tree.query(zone, predicate="intersects"):
                rj, j = owners[k]
                if rj == ri and R.path_dist(i, j) <= LOCAL_PATH:
                    continue
                if segs[k].distance(sl) < CLEAR:
                    ok = False
                    break
            if not ok:
                skips["clear"] += 1
                out.append(b)
                continue
            out.extend(f["arc"])
            corners.append({"key": key, "cls": R.cls, "b": b, "convex": f["convex"],
                            "sliver": sl, "disp": f["disp"]})
        new_rings[ri] = out
    smoothed = {}
    ri = 0
    for c, polys in shapes.items():
        res = []
        for (ext, ints) in polys:
            e = new_rings[ri]
            ri += 1
            holes = []
            for _ in ints:
                holes.append(new_rings[ri])
                ri += 1
            g = Polygon(e, holes)
            if not g.is_valid:
                g = g.buffer(0)
            res.append(g)
        smoothed[c] = unary_union(res) if res else None
    return smoothed, corners, skips


def to_collision(coll0, corners):
    """New collision list. Original convex pieces no fillet touches are kept
    byte-for-byte (re-splitting everything shifted whole walls by a raster
    cell and broke tight bot links); only the touched pieces are merged with
    their fillets and re-split into convex pieces (same splitter as the porter)."""
    out = []
    for c in (0, 1, 2):
        cs = [k for k in corners if k["cls"] == c]
        entries = [e for e in coll0 if int(e.get("col", 0)) == c]
        if not cs:
            out.extend(entries)
            continue
        polys = [Polygon(_pts(e["points"])).buffer(0) for e in entries]
        tree = shapely.STRtree(polys)
        touched = set()
        for k in cs:
            for i in tree.query(k["sliver"].buffer(0.05), predicate="intersects"):
                touched.add(int(i))
        region = unary_union([polys[i] for i in touched] + [k["sliver"] for k in cs if not k["convex"]])
        cut = unary_union([k["sliver"] for k in cs if k["convex"]])
        region = shapely.set_precision(region.difference(cut).buffer(0), 0.01)
        for i, e in enumerate(entries):
            if i not in touched:
                out.append(e)
        for p in _polys_of(region):
            if p.area < 1.0:
                continue
            for piece in PM._convex_pieces(p):
                for flat in PM._strict_convex(piece):
                    ent = {"points": flat}
                    if c:
                        ent["col"] = c
                    out.append(ent)
    return out


# ── validation ─────────────────────────────────────────────────────────────

def topo_sig(unions):
    sig = {}
    for c, u in unions.items():
        ps = _polys_of(u)
        sig[c] = sorted((sum(1 for r in p.interiors if Polygon(r).area >= 1.0) for p in ps if p.area >= 4.0))
    return sig


def entity_list(m):
    out = []
    for k in ENTITY_KEYS_POINT:
        if m.get(k) is not None:
            out.append((k, m[k]))
    for k in ENTITY_KEYS_LIST:
        for i, v in enumerate(m.get(k) or []):
            vv = list(v)
            if k in ("dom_points", "point_spawns"):
                vv = [vv[0], vv[1] + 28.0]
            elif k in ("vehicle_spawns", "tank_spawns", "heli_spawns"):
                vv = [vv[0], vv[1] - 4.0]   # [x, ground y]: test the body just above
            out.append(("%s[%d]" % (k, i), vv))
    for t, arr in (m.get("team_spawns") or {}).items():
        for i, v in enumerate(arr):
            out.append(("team_spawns_%s[%d]" % (t, i), v))
    return out


def _changed_clusters(changed, side_a, side_b):
    """Clusters of changed cells (3-D) touching both side_a and side_b."""
    st = ndimage.generate_binary_structure(3, 1)
    lab, n = ndimage.label(changed, structure=st)
    if n == 0:
        return np.zeros_like(changed)
    da = ndimage.binary_dilation(side_a, structure=st)
    db = ndimage.binary_dilation(side_b, structure=st)
    ta = np.unique(lab[da & changed])
    tb = np.unique(lab[db & changed])
    both = np.intersect1d(ta[ta > 0], tb[tb > 0])
    return np.isin(lab, both)


def free_space_diff(sp0, sp1):
    """Returns (problems, list of world points to protect)."""
    l0, l1 = sp0.lab, sp1.lab
    n1 = int(l1.max()) + 1
    s0 = np.bincount(l0.ravel())
    big = [a for a in range(1, len(s0)) if s0[a] >= BIG_COMP]
    both = (l0 > 0) & (l1 > 0)
    joint = l0[both].astype(np.int64) * n1 + l1[both]
    jl, jc = np.unique(joint, return_counts=True)
    table = {}
    for v, cnt in zip(jl, jc):
        table.setdefault(int(v // n1), []).append((int(cnt), int(v % n1)))
    problems, spots = [], []
    partner = {}
    for a in big:
        ov = sorted(table.get(a, []), reverse=True)
        if not ov or ov[0][0] < s0[a] * 0.5:
            problems.append("free region %d (%d cells) vanished" % (a, s0[a]))
            cells = np.argwhere((l0 == a).any(axis=0))
            spots.append(tuple(cells.mean(axis=0)[::-1] * MA.R))
            continue
        partner.setdefault(ov[0][1], []).append(a)
        for cnt, b2 in ov[1:]:
            if cnt >= SPLIT_MIN:
                problems.append("free region %d split (%d / %d cells)" % (a, ov[0][0], cnt))
                newly_blocked = (l0 == a) & (l1 == 0)
                cut = _changed_clusters(newly_blocked, l1 == ov[0][1], l1 == b2)
                pts = np.argwhere(cut.any(axis=0))
                if pts.size == 0:
                    pts = np.argwhere((l1 == b2).any(axis=0))
                spots.extend(tuple(p[::-1] * MA.R) for p in pts[:: max(1, len(pts) // 40)])
    for b, alist in partner.items():
        if len(alist) > 1:
            problems.append("free regions %s merged" % alist)
            newly_free = (l1 == b) & (l0 == 0)
            for k in range(1, len(alist)):
                br = _changed_clusters(newly_free, l0 == alist[0], l0 == alist[k])
                pts = np.argwhere(br.any(axis=0))
                spots.extend(tuple(p[::-1] * MA.R) for p in pts[:: max(1, len(pts) // 40)])
    return problems, spots


# ── visuals ────────────────────────────────────────────────────────────────

def _poly_tri(p):
    pts = _pts(p["points"])
    return pts if len(pts) == 3 else None


def _attrs(p):
    pts = _pts(p["points"])
    uvs = _pts(p["uvs"]) if len(p.get("uvs", [])) == 6 else None
    vc = [_hex_to_rgba(h) for h in p["vc"]] if len(p.get("vc", [])) == 3 else None
    return pts, uvs, vc


def _make_tri(src, tri_pts, base_pts, uvs, vc, clamp_colour):
    e = {k: v for k, v in src.items() if k not in ("points", "uvs", "vc")}
    flat, fuv, fvc = [], [], []
    for q in tri_pts:
        flat += [round(q[0], 2), round(q[1], 2)]
        l = _bary(q, *base_pts)
        if l is None:
            l = (1.0, 0.0, 0.0)
        if uvs is not None:
            fuv += [round(sum(l[k] * uvs[k][0] for k in range(3)), 5), round(sum(l[k] * uvs[k][1] for k in range(3)), 5)]
        if vc is not None:
            lc = l
            if clamp_colour:
                lc = [max(0.0, x) for x in l]
                s = sum(lc) or 1.0
                lc = [x / s for x in lc]
            fvc.append(_rgba_to_hex([sum(lc[k] * vc[k][ch] for k in range(3)) for ch in range(4)]))
    out = {"points": flat}
    if uvs is not None:
        out["uvs"] = fuv
    if vc is not None:
        out["vc"] = fvc
    # keep the original key order: points, uvs, vc, then the rest (col, ...)
    out.update(e)
    return out


def _triangulate(g):
    tris = []
    for p in _polys_of(g):
        if p.area < 0.05:
            continue
        for t in shapely.constrained_delaunay_triangles(p).geoms:
            cs = list(t.exterior.coords)[:3]
            if _tri_area(*cs) >= 0.02:
                tris.append(cs)
    return tris


def _pieces(g):
    """Drawable point lists for region g. A hole-free piece stays ONE polygon
    (Polygon2D triangulates it itself) — splitting every clipped triangle
    into a fan tripled the node count; anything else is triangulated."""
    out = []
    for p in _polys_of(g):
        if p.area < 0.05:
            continue
        ring = None
        if not p.interiors:
            ring = _clean_coords([(round(x, 2), round(y, 2)) for (x, y) in p.exterior.coords])
            if len(ring) < 3 or not Polygon(ring).is_valid or Polygon(ring).area < 0.05:
                ring = None
        if ring is not None:
            out.append(ring)
        else:
            out.extend(_triangulate(p))
    return out


def _shoelace(pts):
    a = 0.0
    for i in range(len(pts)):
        x0, y0 = pts[i - 1]
        x1, y1 = pts[i]
        a += x0 * y1 - x1 * y0
    return abs(a) * 0.5


STATS = {"clipped": 0, "filled": 0}


def rebuild_visuals(polys, unions, smoothed, corners):
    STATS["clipped"] = STATS["filled"] = 0
    rem, add = {}, {}
    for c in unions:
        cv = [k["sliver"] for k in corners if k["cls"] == c and k["convex"]]
        cc = [k["sliver"] for k in corners if k["cls"] == c and not k["convex"]]
        if cv:
            sm = smoothed.get(c)
            r = unary_union([s.buffer(1.5, join_style="mitre") for s in cv])
            rem[c] = r.difference(sm) if sm is not None else r
        if cc:
            add[c] = cc
    solid_any = unary_union(list(unions.values())) if unions else None
    rem_all = unary_union(list(rem.values())) if rem else None
    # 1) clip
    out = []
    origin = []   # index into the original list for each output triangle
    for idx, p in enumerate(polys):
        cls = int(p.get("col", 0))
        tri = _poly_tri(p)
        cut = None
        if tri is not None and _tri_area(*tri) > 0.01:
            tp = Polygon(tri)
            if cls in rem and tp.intersects(rem[cls]):
                cut = rem[cls]
            elif cls == 3 and rem_all is not None and tp.intersects(rem_all) and solid_any is not None:
                if tp.intersection(solid_any).area >= 0.98 * tp.area:
                    cut = rem_all
        if cut is None:
            out.append(p)
            origin.append(idx)
            continue
        rest = Polygon(tri).difference(cut)
        if rest.area >= Polygon(tri).area - 0.5:   # sub-pixel overhang: not worth a split
            out.append(p)
            origin.append(idx)
            continue
        base, uvs, vc = _attrs(p)
        STATS["clipped"] += 1
        for t in _pieces(rest):
            out.append(_make_tri(p, t, base, uvs, vc, False))
            origin.append(idx)
    # 2) fill concave fillets, right after the triangle they continue
    inserts = {}
    if add:
        trees = {}
        for c in add:
            cand = [(i, Polygon(_poly_tri(p))) for i, p in enumerate(polys)
                    if int(p.get("col", 0)) == c and _poly_tri(p) is not None and _tri_area(*_poly_tri(p)) > 0.5]
            vis_union = unary_union([g for _, g in cand]) if cand else None
            trees[c] = (cand, shapely.STRtree([g for _, g in cand]) if cand else None, vis_union)
        for c, slivers in add.items():
            cand, tree, vis_union = trees[c]
            if tree is None:
                continue
            for sl in slivers:
                need = sl.difference(vis_union) if vis_union is not None else sl
                if need.area < 0.05:
                    continue
                probe = need.buffer(2.0)
                best, best_s = None, 0.0
                for k in tree.query(probe, predicate="intersects"):
                    i, g = cand[k]
                    s = g.intersection(probe).area * (0.2 + _min_angle(*_poly_tri(polys[i])))
                    if s > best_s:
                        best, best_s = i, s
                if best is None:
                    continue
                p = polys[best]
                base, uvs, vc = _attrs(p)
                STATS["filled"] += 1
                for t in _pieces(need):
                    inserts.setdefault(best, []).append(_make_tri(p, t, base, uvs, vc, True))
    if inserts:
        final = []
        last_of = {}
        for j, o in enumerate(origin):
            last_of[o] = j
        for j, p in enumerate(out):
            final.append(p)
            o = origin[j]
            if last_of.get(o) == j and o in inserts:
                final.extend(inserts[o])
        out = final
    return out


def weld(polys):
    """Average vertex colours of coincident vertices (same class), area-weighted."""
    from scipy.spatial import cKDTree
    refs = []   # (poly idx, vertex idx)
    pos, cls, cols, wts = [], [], [], []
    for i, p in enumerate(polys):
        pts = _pts(p["points"])
        if len(pts) < 3:
            continue
        area = max(_shoelace(pts), 0.01)
        vc = p.get("vc")
        has_vc = bool(vc) and len(vc) == len(pts)
        for k in range(len(pts)):
            refs.append((i, k))
            pos.append(pts[k])
            cls.append((int(p.get("col", 0)), str(p.get("texture", ""))))
            cols.append(_hex_to_rgba(vc[k]) if has_vc else [255, 255, 255, 255])
            wts.append(area)
    if not refs:
        return 0
    pos = np.array(pos)
    cols = np.array(cols, dtype=float)
    parent = list(range(len(refs)))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    for a, b in cKDTree(pos).query_pairs(WELD_EPS):
        if cls[a] == cls[b]:
            ra, rb = find(a), find(b)
            if ra != rb:
                parent[max(ra, rb)] = min(ra, rb)
    groups = {}
    for i in range(len(refs)):
        groups.setdefault(find(i), []).append(i)
    changed = 0
    newcol = {}
    newpos = {}
    for g in groups.values():
        if len(g) < 2:
            continue
        # snap positions (sub-pixel) so neighbouring triangles share exact corners
        cx, cy = pos[g, 0].mean(), pos[g, 1].mean()
        if np.ptp(pos[g, 0]) > 1e-6 or np.ptp(pos[g, 1]) > 1e-6:
            for i in g:
                newpos[i] = (round(float(cx), 2), round(float(cy), 2))
        # single-link colour clusters: hard colour edges stay hard
        sub = list(range(len(g)))
        par = list(range(len(g)))

        def f2(x):
            while par[x] != x:
                par[x] = par[par[x]]
                x = par[x]
            return x
        for x in sub:
            for y in sub[x + 1:]:
                if np.max(np.abs(cols[g[x]] - cols[g[y]])) <= COLOR_THR:
                    rx, ry = f2(x), f2(y)
                    if rx != ry:
                        par[max(rx, ry)] = min(rx, ry)
        cl = {}
        for x in sub:
            cl.setdefault(f2(x), []).append(g[x])
        for members in cl.values():
            if len(members) < 2:
                continue
            w = np.array([wts[i] for i in members])
            avg = (cols[members] * w[:, None]).sum(axis=0) / w.sum()
            for i in members:
                if np.max(np.abs(cols[i] - avg)) >= 0.5:
                    newcol[i] = avg
    for i, c in newcol.items():
        pi, k = refs[i]
        p = polys[pi]
        nv = len(p["points"]) // 2
        if not (p.get("vc") and len(p["vc"]) == nv):
            p["vc"] = ["ffffffff"] * nv
            # keep the porter's key order: points, uvs, vc, then the rest
            polys[pi] = p = {k: p[k] for k in ("points", "uvs", "vc") if k in p} | \
                {k: v for k, v in p.items() if k not in ("points", "uvs", "vc")}
        h = _rgba_to_hex(c)
        if p["vc"][k] != h:
            p["vc"][k] = h
            changed += 1
    for i, q in newpos.items():
        pi, k = refs[i]
        polys[pi]["points"][2 * k] = q[0]
        polys[pi]["points"][2 * k + 1] = q[1]
    return changed


# ── per-map driver ─────────────────────────────────────────────────────────

def _boundary_disp(u0, u1):
    if u0 is None or u1 is None:
        return 0.0
    return float(u0.boundary.hausdorff_distance(u1.boundary))


def _entity_ok(sp1, name, p, prob0):
    """Same audit verdict as before. Pickups / vehicles (not audited by
    map_audit; they settle onto the ground at runtime) may sit up to 4 px
    higher — the 2 px raster flips on a re-split slope otherwise."""
    prob1 = _verdict(sp1.check(name, p)[0])
    if prob1 == prob0:
        return True
    base = name.split("[")[0]
    if base in UNAUDITED:
        return _verdict(sp1.check(name, [p[0], p[1] - 4.0])[0]) == prob0
    return False


def _verdict(prob):
    return prob.split(" (")[0].split(" at ")[0] if prob else None


def _nudge(m, name, dy):
    """Move entity `name` (entity_list label) up by dy px."""
    if "[" in name:
        key, i = name[:-1].split("[")
        i = int(i)
        if key.startswith("team_spawns_"):
            arr = m["team_spawns"][key[len("team_spawns_"):]]
        else:
            arr = m[key]
        arr[i] = [arr[i][0], round(arr[i][1] - dy, 2)]
    else:
        m[name] = [m[name][0], round(m[name][1] - dy, 2)]


def _nav_scc(m):
    """Bot nav graph (tools/build_nav.py) as (node xy array, edges, SCC labels)."""
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    g = BN.build(m)
    if g is None:
        return None
    nodes = np.array(g["nodes"], dtype=float).reshape(-1, 2)
    e = np.array(g["edges"], dtype=int).reshape(-1, 2)
    n = len(nodes)
    if n == 0 or len(e) == 0:
        return nodes, e, np.zeros(n, dtype=int)
    A = coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(n, n))
    _, lab = connected_components(A, directed=True, connection="strong")
    return nodes, e, lab


def nav_diff(nav0, nav1):
    """Does every node of the original graph's main strongly connected region
    still reach every other one? If not, returns the original links to blame
    (links whose move can no longer be made, plus links through nodes that
    vanished — ledge-detour / bridge waypoints) for localisation."""
    from scipy.spatial import cKDTree
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import breadth_first_order
    if nav0 is None or nav1 is None:
        return ([] if nav0 is None else ["nav graph lost"]), []
    n0, e0, l0 = nav0
    n1, e1, l1 = nav1
    if len(n1) == 0:
        return ["nav graph empty"], []
    main0 = int(np.argmax(np.bincount(l0)))
    d, idx = cKDTree(n1).query(n0)
    mapped = [int(idx[i]) for i in range(len(n0)) if l0[i] == main0 and d[i] <= 60]
    cnt = {}
    for j in mapped:
        cnt[int(l1[j])] = cnt.get(int(l1[j]), 0) + 1
    parts = [c for c, k in cnt.items() if k >= 3]
    if len(parts) <= 1:
        return [], []
    A1 = coo_matrix((np.ones(len(e1)), (e1[:, 0], e1[:, 1])), shape=(len(n1), len(n1))).tocsr()
    reach = {}
    lost = []
    for a, b in e0:
        if l0[a] != main0 or l0[b] != main0:
            continue
        if d[a] > 60 or d[b] > 60:
            lost.append((n0[a], n0[b]))
            continue
        ia, ib = int(idx[a]), int(idx[b])
        if l1[ia] == l1[ib]:
            continue
        if ia not in reach:
            reach[ia] = set(breadth_first_order(A1, ia, directed=True, return_predecessors=False).tolist())
        if ib not in reach[ia]:
            lost.append((n0[a], n0[b]))
    sizes = sorted(cnt.values(), reverse=True)
    msg = "nav: main region split %s" % sizes[:4]
    if lost:
        msg += ", e.g. (%d,%d)->(%d,%d)" % (lost[0][0][0], lost[0][0][1], lost[0][1][0], lost[0][1][1])
    return [msg], lost


def smooth_map(m, log=print):
    """Smooth map dict m (unsmoothed geometry) in place. Returns stats dict."""
    coll0 = m.get("collision") or []
    if not coll0:
        return None
    unions = class_unions(coll0)
    sp0 = MA.Space(m)
    nav0 = _nav_scc(m)
    ent0 = {name: (_verdict(sp0.check(name, p)[0]), p) for name, p in entity_list(m)}
    # Topology reference: the same outlines run through the cleaner with no
    # fillets (vertex clean-up alone may legitimately merge touching specks).
    ref, _, _ = smooth_classes(unions, set(), {c: 0.0 for c in unions})
    sig0 = topo_sig({c: g for c, g in ref.items() if g is not None})
    blocked = set()
    d_max = {c: D_MAX for c in unions}
    notes = []
    nudged = []
    nav_r = NAV_R
    for it in range(10):
        smoothed, corners, skips = smooth_classes(unions, blocked, d_max)
        problems, spots, ent_fail = [], [], []
        sig1 = topo_sig({c: g for c, g in smoothed.items() if g is not None})
        for c in unions:
            if sig0.get(c) != sig1.get(c):
                problems.append("class %d components/holes changed %s -> %s" % (c, sig0.get(c), sig1.get(c)))
                holes = lambda g: sum(1 for r in g.interiors if Polygon(r).area >= 1.0)
                for p in _polys_of(ref[c]):
                    if p.area < 4.0:
                        continue
                    q = [g for g in _polys_of(smoothed[c]) if g.intersects(p) and g.area >= 4.0]
                    if len(q) != 1 or holes(q[0]) != holes(p):
                        zone = p.buffer(2.0)
                        for k in corners:
                            if k["cls"] == c and zone.contains(Point(k["b"])):
                                blocked.add(k["key"])
        area = {}
        for c in unions:
            a0 = unions[c].area
            a1 = smoothed[c].area if smoothed.get(c) is not None else 0.0
            area[c] = (a1 - a0) / a0 * 100.0 if a0 else 0.0
            if abs(area[c]) > AREA_LIMIT:
                problems.append("class %d area %+.2f%%" % (c, area[c]))
                d_max[c] *= 0.6
        coll1 = to_collision(coll0, corners)
        m1 = dict(m)
        m1["collision"] = coll1
        sp1 = MA.Space(m1)
        fp, fs = free_space_diff(sp0, sp1)
        problems += fp
        spots += fs
        nav_spots = []
        if not fp:
            npb, nav_spots = nav_diff(nav0, _nav_scc(m1))
            problems += npb
        for name, (prob0, p) in ent0.items():
            if not _entity_ok(sp1, name, p, prob0):
                ent_fail.append(name)
                problems.append("%s: %s -> %s" % (name, prob0, _verdict(sp1.check(name, p)[0])))
        n_before = len(blocked)
        for (x, y) in spots + [tuple(ent0[n][1]) for n in ent_fail]:
            for k in corners:
                if abs(k["b"][0] - x) <= ENTITY_R and abs(k["b"][1] - y) <= ENTITY_R:
                    blocked.add(k["key"])
        # Bot links hinge on single raster cells (a re-split piece nearby is
        # enough): wider net there.
        # A link also needs floor somewhere below its path (build_nav
        # void_span), so the whole band under it down to the kill line counts.
        for _grow in range(4):
            for (p, q) in nav_spots:
                x0, x1 = min(p[0], q[0]) - nav_r, max(p[0], q[0]) + nav_r
                y0 = min(p[1], q[1]) - nav_r
                for k in corners:
                    if x0 <= k["b"][0] <= x1 and k["b"][1] >= y0:
                        blocked.add(k["key"])
            if not nav_spots or len(blocked) > n_before:
                break
            nav_r *= 2.0   # nothing new nearby (ledge detours reach 240 px): widen
        if not problems:
            break
        notes.append("pass %d: %s" % (it + 1, "; ".join(problems[:6])))
        log("   pass %d: %d problem(s): %s" % (it + 1, len(problems), "; ".join(problems[:4])))
        if len(blocked) == n_before and not any("area" in pr for pr in problems):
            only_ent = len(problems) == len(ent_fail)
            if only_ent:
                # No fillet near: 2 px raster noise from the re-split outline.
                # Lift the entity just clear (<= 6 px) — same verdict as before.
                for name in ent_fail:
                    prob0, p = ent0[name]
                    for dy in (2.0, 4.0, 6.0):
                        if _verdict(sp1.check(name, [p[0], p[1] - dy])[0]) == prob0:
                            _nudge(m, name, dy)
                            nudged.append("%s up %g px" % (name, dy))
                            ent0[name] = (prob0, [p[0], p[1] - dy])
                            break
                    else:
                        log("   !! %s: no clear spot within 6 px; leaving map unsmoothed" % name)
                        return {"failed": problems}
                continue
            log("   !! could not localise; leaving map unsmoothed")
            return {"failed": problems}
    else:
        log("   !! still failing after 10 passes; leaving map unsmoothed")
        return {"failed": problems}
    polys0 = m["polys"]
    polys1 = rebuild_visuals(polys0, unions, smoothed, corners)
    welded = weld(polys1)
    m["collision"] = coll1
    m["polys"] = polys1
    disp = max([_boundary_disp(ref.get(c), smoothed.get(c)) for c in unions] + [0.0])
    stats = {
        "v": VERSION,
        "corners": len(corners),
        "convex": sum(1 for k in corners if k["convex"]),
        "concave": sum(1 for k in corners if not k["convex"]),
        "kept_sharp": dict(skips),
        "max_disp": round(disp, 2),
        "area_pct": {str(c): round(v, 3) for c, v in area.items()},
        "coll_pieces": [len(coll0), len(coll1)],
        "coll_verts": [sum(len(e["points"]) // 2 for e in coll0), sum(len(e["points"]) // 2 for e in coll1)],
        "polys": [len(polys0), len(polys1)],
        "welded_vc": welded,
        "tris_clipped": STATS["clipped"],
        "fills": STATS["filled"],
        "passes": len(notes) + 1,
    }
    if nudged:
        stats["nudged"] = nudged
    if notes:
        stats["notes"] = notes
    return stats


_src_dir = SRC_DIR


def _src_path(stem):
    return os.path.join(_src_dir, stem + ".json.gz")


ENTITY_ALL = ENTITY_KEYS_POINT + ENTITY_KEYS_LIST + ("team_spawns",)


def load_original(stem, m):
    """Original (unsmoothed) geometry + entity spots for map m."""
    path = _src_path(stem)
    smoothed = bool((m.get("_source") or {}).get("smooth"))
    if smoothed:
        if not os.path.exists(path):
            return None
        with gzip.open(path, "rt", encoding="utf-8") as f:
            return json.load(f)
    return copy.deepcopy({"polys": m["polys"], "collision": m.get("collision", []),
                          "entities": {k: m[k] for k in ENTITY_ALL if k in m}})


def save_original(stem, orig):
    os.makedirs(_src_dir, exist_ok=True)
    data = json.dumps(orig, separators=(",", ":")).encode("utf-8")
    path = _src_path(stem)
    # mtime=0 keeps the .gz byte-identical across runs (clean git diffs)
    with open(path, "wb") as f:
        with gzip.GzipFile(filename="", mode="wb", fileobj=f, mtime=0, compresslevel=9) as g:
            g.write(data)


def process_file(path, dry=False, restore=False, log=print):
    global _src_dir
    stem = os.path.splitext(os.path.basename(path))[0]
    # Bundled maps keep their originals in tools/map_src; maps elsewhere (a
    # scratch regen) next to themselves, so they never clobber the bundled ones.
    here = os.path.dirname(os.path.abspath(path))
    _src_dir = SRC_DIR if here == os.path.abspath(MAPS_DIR) else os.path.join(here, "_map_src")
    if stem in EXCLUDE:
        log("%-14s excluded (hand-tuned geometry)" % stem)
        return None
    with open(path, encoding="utf-8") as f:
        m = json.load(f)
    if not m.get("collision"):
        log("%-14s no merged collision — skipped" % stem)
        return None
    orig = load_original(stem, m)
    if orig is None:
        log("%-14s already smoothed but %s is missing — skipped" % (stem, os.path.relpath(_src_path(stem), GAME)))
        return None
    m["polys"] = copy.deepcopy(orig["polys"])
    m["collision"] = copy.deepcopy(orig["collision"])
    for k, v in (orig.get("entities") or {}).items():
        m[k] = copy.deepcopy(v)
    src = m.setdefault("_source", {})
    src.pop("smooth", None)
    if restore:
        stats = {"restored": True}
    else:
        stats = smooth_map(m, log=log)
        if stats is None or "failed" in stats:
            m["polys"], m["collision"] = orig["polys"], orig["collision"]
            for k, v in (orig.get("entities") or {}).items():
                m[k] = copy.deepcopy(v)
        else:
            src["smooth"] = stats
    if not dry:
        save_original(stem, orig)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(m, f, indent=2)
    if stats and "corners" in stats:
        log("%-14s corners=%4d (cvx %d / ccv %d) sharp=%s disp=%.2f area=%s coll %d->%d pcs %d->%d verts  polys %d->%d  welded=%d clip=%d fill=%d%s" % (
            stem, stats["corners"], stats["convex"], stats["concave"],
            ",".join("%s:%d" % kv for kv in stats["kept_sharp"].items()), stats["max_disp"],
            ",".join("%s:%+.2f%%" % kv for kv in stats["area_pct"].items()),
            stats["coll_pieces"][0], stats["coll_pieces"][1], stats["coll_verts"][0], stats["coll_verts"][1],
            stats["polys"][0], stats["polys"][1], stats["welded_vc"], stats["tris_clipped"], stats["fills"],
            "" if stats["passes"] == 1 else "  passes=%d" % stats["passes"]))
    elif stats and "failed" in stats:
        log("%-14s LEFT UNSMOOTHED: %s" % (stem, "; ".join(stats["failed"][:4])))
    elif stats:
        log("%-14s restored" % stem)
    return stats


def main(argv):
    dry = "--dry" in argv
    restore = "--restore" in argv
    stats_out = None
    words = []
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == "--stats":
            stats_out = argv[i + 1]
            i += 1
        elif not a.startswith("--"):
            words.append(a.lower())
        i += 1
    all_stats = {}
    for path in sorted(glob.glob(os.path.join(MAPS_DIR, "*.json"))):
        stem = os.path.splitext(os.path.basename(path))[0]
        if words and not any(w in stem for w in words):
            continue
        st = process_file(path, dry=dry, restore=restore)
        if st is not None:
            all_stats[stem] = st
    if stats_out:
        with open(stats_out, "w") as f:
            json.dump(all_stats, f, indent=1)
    failed = [k for k, v in all_stats.items() if "failed" in v]
    if failed:
        print("left unsmoothed: %s" % ", ".join(failed))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
