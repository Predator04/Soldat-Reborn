#!/usr/bin/env python3
"""place_vehicles.py — find buggy spawn spots on every map.

A buggy (64x30 clearance box) needs a long drivable stretch: ground it fits on
that continues left and right with slopes up to ~45 degrees, in the main arena
(not an isolated pocket), above the kill line. For each map this writes
"vehicle_spawns": [[x, ground_y], ...] into assets/maps/<map>.json — one per
team base on team maps (bases = ctf_flags / team spawns), else two far apart.
Maps without a stretch of MIN_RUN px get none (tight maps stay on foot).

    python3 tools/place_vehicles.py            # write all classic maps
    python3 tools/place_vehicles.py --dry      # just report
    python3 tools/place_vehicles.py --builtin  # print spots for main.gd's built-ins
    python3 tools/place_vehicles.py --heli     # helicopter pads only (#277), see below
    python3 tools/place_vehicles.py --heli --dry
    python3 tools/place_vehicles.py --plane    # plane runways only (#291), see below

Helicopters (#277) go on the big, open maps only: world at least HELI_MIN_W x
HELI_MIN_H and open sky over most of it (HELI_MIN_SKY of the columns have
HELI_SKY_PX of clear air under the top of the world). A pad is flat ground
(a HELI_W x HELI_H box rests there on a run of HELI_MIN_RUN px) with
HELI_CLEAR_W x HELI_CLEAR_H of clear air above it (rotor + room to climb),
in the main arena, HELI_AVOID px from the buggy / tank spots — one per team
base on team maps, else one where the sky is most open. --heli touches only
"heli_spawns" (the buggy / tank spots of the smoothed maps are left exactly as
they are) and re-checks every pad it writes.

Planes (#291) go on the widest open maps only: world at least PLANE_MIN_W
wide, open sky over most of it (PLANE_MIN_SKY), and a RUNWAY: a stretch of the
topmost surface (open sky above all of it) at least PLANE_MIN_RUN px long,
gently sloped (ground height changes <= PLANE_STEP px per 40 px and stays
within PLANE_RISE of the start), at least
PLANE_TOP_CLEAR px below the top of the world and above the kill line. The
spawn is at the end of the runway from which the plane takes off toward the
middle of the map (the game faces it along the longer clear run), one per team
base on team maps (else one), PLANE_AVOID px from the other vehicles' spots.
--plane touches only "plane_spawns" and re-checks every runway it writes.
"""
import glob, json, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import map_audit as MA

R = MA.R
CAR_W, CAR_H = 64.0, 30.0
MIN_RUN = 700.0          # px of continuous drivable ground
TANK_W, TANK_H = 90.0, 32.0
TANK_MIN_RUN = 1600.0    # tanks only on wide maps with a long ground stretch
HELI_W, HELI_H = 140.0, 70.0
HELI_MIN_RUN = 200.0     # flat-ish ground under the skids
HELI_CLEAR_W, HELI_CLEAR_H = 260.0, 420.0
HELI_MIN_W, HELI_MIN_H = 4500.0, 2300.0
HELI_SKY_PX = 700.0
HELI_MIN_SKY = 0.55
HELI_AVOID = 300.0
HELI_MAX_MAPS = 15
PLANE_MIN_W = 5500.0
PLANE_MIN_SKY = 0.75
PLANE_MIN_RUN = 640.0
PLANE_STEP = 12.0        # px of height change allowed per 40 px of runway
PLANE_RISE = 50.0        # most the runway may rise / fall from its start
PLANE_LIFTOFF = 600.0    # px down the runway by which it is airborne and climbing
PLANE_CLIMB_SLACK = 20.0 # terrain may poke this far over the climb-out line
PLANE_CLIMB_GRAD = 0.45  # climb-out line: px up per px ahead after lift-off
PLANE_CLIMB_OUT = 1100.0 # how far past the runway the climb-out is checked
PLANE_TOP_CLEAR = 420.0  # px of sky above the runway at least
PLANE_AVOID = 220.0
PLANE_MAX_MAPS = 6
PLANE_NEAR_WALK = 2500.0  # #294: an inward runway start this far (walk) from a base is close enough
PLANE_OUT_ROOM = 2400.0   # #294: an outward runway needs this much world ahead to climb out and turn back


def runs(m, w=CAR_W, h=CAR_H, edge=None):
    sp = MA.Space(m)
    car = MA.fits(sp.solid, w, h)
    # Real ground: solid terrain right under the box. ("The box doesn't fit one
    # row lower" was also true just above the kill-line cut-off, which put
    # buggies on thin air over the void on half the maps.)
    # fits() boxes occupy the rows *above* cell y, so row y is where the wheels
    # rest. A 64 px box over a slope rests on its low corner, leaving a gap
    # under the centre — accept solid within 20 px below, but only at the
    # lowest free row (car doesn't fit one row lower).
    near = np.zeros_like(sp.solid)
    for k in range(0, int(20 / R) + 1):
        sh = np.zeros_like(sp.solid)
        sh[:sp.solid.shape[0] - k, :] = sp.solid[k:, :]
        near |= sh
    lower = np.zeros_like(car)
    lower[:-1, :] = car[1:, :]
    g = car & ~lower & near
    if sp.K is not None:
        g[int((sp.K - 80.0) / R):, :] = False
    if sp.main is not None:
        g &= (sp.lab[0] == sp.main)
    ny, nx = g.shape
    L = np.zeros((ny, nx), np.int32)
    Rr = np.zeros((ny, nx), np.int32)
    gi = g.astype(np.int32)
    for x in range(nx):
        prev = L[:, x - 1] if x > 0 else np.zeros(ny, np.int32)
        best = np.maximum(prev, np.maximum(np.roll(prev, 1), np.roll(prev, -1)))
        L[:, x] = gi[:, x] * (1 + best)
    for x in range(nx - 1, -1, -1):
        prev = Rr[:, x + 1] if x < nx - 1 else np.zeros(ny, np.int32)
        best = np.maximum(prev, np.maximum(np.roll(prev, 1), np.roll(prev, -1)))
        Rr[:, x] = gi[:, x] * (1 + best)
    tot = (L + Rr - 1) * R
    # Stay a car length away from the ends of the stretch.
    edge_ok = (np.minimum(L, Rr) * R) >= (w * 1.5 if edge is None else edge)
    return sp, tot, edge_ok


def bases(m):
    b = []
    for f in m.get("ctf_flags", []) or []:
        b.append((float(f[0]), float(f[1])))
    if len(b) < 2:
        ts = m.get("team_spawns") or {}
        for k in ("1", "2"):
            if ts.get(k):
                b.append((float(ts[k][0][0]), float(ts[k][0][1])))
    return b[:2]


def pick(m):
    sp, tot, edge_ok = runs(m)
    ys, xs = np.nonzero((tot >= MIN_RUN) & edge_ok)
    if len(xs) == 0:
        return [], 0.0
    pts = np.stack([xs * R, ys * R], 1)
    score = tot[ys, xs]
    out = []
    bs = bases(m)
    if len(bs) == 2:
        for bx, by in bs:
            d = np.hypot(pts[:, 0] - bx, pts[:, 1] - by)
            i = int(np.argmin(d - score * 0.3))   # near the base, prefer long runs
            out.append([round(float(pts[i, 0]), 1), round(float(pts[i, 1]), 1)])
    else:
        i = int(np.argmax(score))
        out.append([round(float(pts[i, 0]), 1), round(float(pts[i, 1]), 1)])
        d = np.hypot(pts[:, 0] - pts[i, 0], pts[:, 1] - pts[i, 1])
        far = d > 1200
        if far.any():
            j = int(np.argmax(np.where(far, score, -1)))
            out.append([round(float(pts[j, 0]), 1), round(float(pts[j, 1]), 1)])
    if len(out) == 2 and abs(out[0][0] - out[1][0]) + abs(out[0][1] - out[1][1]) < 200:
        out = out[:1]
    return out, float(score.max())


def pick_tank(m, avoid):
    """One tank per team base on team maps (else one), on a run of at least
    TANK_MIN_RUN px, kept 400 px away from the buggy spots."""
    sp, tot, edge_ok = runs(m, TANK_W, TANK_H)
    ok = (tot >= TANK_MIN_RUN) & edge_ok
    ys, xs = np.nonzero(ok)
    if len(xs) == 0:
        return []
    pts = np.stack([xs * R, ys * R], 1)
    score = tot[ys, xs]
    keep = np.ones(len(xs), bool)
    for a in avoid:
        keep &= np.hypot(pts[:, 0] - a[0], pts[:, 1] - a[1]) > 400
    if not keep.any():
        return []
    pts, score = pts[keep], score[keep]
    out = []
    bs = bases(m)
    if len(bs) == 2:
        for bx, by in bs:
            d = np.hypot(pts[:, 0] - bx, pts[:, 1] - by)
            i = int(np.argmin(d - score * 0.3))
            out.append([round(float(pts[i, 0]), 1), round(float(pts[i, 1]), 1)])
        if abs(out[0][0] - out[1][0]) + abs(out[0][1] - out[1][1]) < 600:
            return []   # both bases would share one spot: unfair, skip
    else:
        i = int(np.argmax(score))
        out.append([round(float(pts[i, 0]), 1), round(float(pts[i, 1]), 1)])
    return out


def sky_fraction(m):
    """Share of the world's columns with HELI_SKY_PX of clear air below the top."""
    solid = MA.raster(m)
    first = np.where(solid.any(0), solid.argmax(0), solid.shape[0])
    W = solid.shape[1]
    inner = first[int(60 / R): W - int(60 / R)]
    return float(np.mean(inner * R >= HELI_SKY_PX)), solid


def heli_pads(m, solid=None):
    """Helicopter pads for one map (list of [x, ground_y]), [] if none fit."""
    sp, tot, edge_ok = runs(m, HELI_W, HELI_H, edge=HELI_MIN_RUN * 0.4)
    if solid is None:
        solid = sp.solid
    sky = MA.fits(solid, HELI_CLEAR_W, HELI_CLEAR_H)
    ok = (tot >= HELI_MIN_RUN) & edge_ok & sky
    ys, xs = np.nonzero(ok)
    if len(xs) == 0:
        return []
    pts = np.stack([xs * R, ys * R], 1)
    score = tot[ys, xs].astype(float)
    keep = np.ones(len(xs), bool)
    for k in ("vehicle_spawns", "tank_spawns"):
        for a in m.get(k, []) or []:
            keep &= np.hypot(pts[:, 0] - float(a[0]), pts[:, 1] - float(a[1])) > HELI_AVOID
    if not keep.any():
        return []
    pts, score = pts[keep], score[keep]
    def first_ok(cost):
        # Cheapest candidate that also passes the pad re-check (flat, resting,
        # clear air above), trying the best few thousand.
        for i in np.argsort(cost)[:3000]:
            p = [round(float(pts[i, 0]), 1), round(float(pts[i, 1]), 1)]
            if check_pad(m, p, solid) is None:
                return p
        return None
    out = []
    bs = bases(m)
    if len(bs) == 2:
        for bx, by in bs:
            d = np.hypot(pts[:, 0] - bx, pts[:, 1] - by)
            p = first_ok(d - np.minimum(score, 600.0) * 0.3)
            if p is not None:
                out.append(p)
        if len(out) == 2 and abs(out[0][0] - out[1][0]) + abs(out[0][1] - out[1][1]) < 800:
            out = out[:1]   # both bases would share one pad: keep one
    else:
        # The pad with the longest flat run nearest the middle of the map.
        W = float(MA.world_of(m)[0])
        p = first_ok(np.abs(pts[:, 0] - W * 0.5) - np.minimum(score, 800.0))
        if p is not None:
            out.append(p)
    return out


def check_pad(m, p, solid):
    """Re-check a written pad: box rests on solid ground, flat, clear air above."""
    x, y = p
    cx, cy = int(round(x / R)), int(round(y / R))
    hw = int(HELI_W / 2 / R)
    under = solid[cy: cy + int(22 / R) + 1, cx - hw: cx + hw + 1]
    if under.size == 0 or under.any(0).mean() < 0.6:
        return "not resting on ground"
    box = solid[max(0, cy - int(HELI_CLEAR_H / R)): cy, cx - int(HELI_CLEAR_W / 2 / R): cx + int(HELI_CLEAR_W / 2 / R) + 1]
    if box.any():
        return "no clear air above"
    # Flat: ground height under the skid ends within 12 px.
    hs = []
    for xx in (cx - hw, cx + hw):
        col = solid[cy - int(30 / R): cy + int(30 / R), xx]
        hs.append(int(np.argmax(col)) if col.any() else 999)
    if abs(hs[0] - hs[1]) * R > 16.0:
        return "ground not flat (%d px)" % int(abs(hs[0] - hs[1]) * R)
    return None


def main_heli(argv):
    dry = "--dry" in argv
    cands = []
    for f in sorted(glob.glob(os.path.join(MA.GAME, "assets", "maps", "*.json"))):
        m = json.load(open(f, encoding="utf-8"))
        W, H, _, _ = MA.world_of(m)
        if W < HELI_MIN_W or H < HELI_MIN_H:
            continue
        sky, solid = sky_fraction(m)
        if sky < HELI_MIN_SKY:
            continue
        cands.append((sky * min(W, 9000.0), f, m, solid, sky))
    cands.sort(key=lambda c: -c[0])
    chosen = {}
    for _, f, m, solid, sky in cands:
        if len(chosen) >= HELI_MAX_MAPS:
            break
        pads = heli_pads(m)
        bad = [check_pad(m, p, solid) for p in pads]
        pads = [p for p, b in zip(pads, bad) if b is None]
        name = os.path.basename(f)[:-5]
        print("%-12s %5dx%-5d sky=%.2f pads=%s %s" % (name, MA.world_of(m)[0], MA.world_of(m)[1], sky, pads,
              [b for b in bad if b] or ""))
        if pads:
            chosen[f] = pads
    for f in sorted(glob.glob(os.path.join(MA.GAME, "assets", "maps", "*.json"))):
        if dry:
            continue
        raw = open(f, encoding="utf-8").read()
        m = json.loads(raw)
        if f in chosen:
            if m.get("heli_spawns") == chosen[f]:
                continue
            m["heli_spawns"] = chosen[f]
        elif "heli_spawns" in m:
            m.pop("heli_spawns")
        else:
            continue
        json.dump(m, open(f, "w", encoding="utf-8"), indent=2)
    print("maps with helicopters: %d" % len(chosen))


def surface(solid, m):
    """Topmost solid row per column in world px (None: no ground / under the kill line)."""
    W, H, G, K = MA.world_of(m)
    first = np.where(solid.any(0), solid.argmax(0), -1)
    out = []
    for x in range(solid.shape[1]):
        y = first[x] * R if first[x] >= 0 else None
        if y is not None and (K is not None and y > K - 60.0):
            y = None
        out.append(y)
    return out


def runways(m, solid):
    """[(x0, x1)] stretches of gently sloped topmost surface (world px)."""
    top = surface(solid, m)
    W = MA.world_of(m)[0]
    step = int(40 / R)
    xs = list(range(int(80 / R), len(top) - int(80 / R), step))
    out = []
    start = None
    prev = None
    for xi in xs:
        y = top[xi]
        ok = y is not None and y >= PLANE_TOP_CLEAR and (prev is None or abs(y - prev) <= PLANE_STEP) \
            and (start is None or abs(y - top[start]) <= PLANE_RISE)
        if ok and start is None:
            start = xi
        if not ok and start is not None:
            out.append((start * R, (xi - step) * R))
            start = None if y is None or y < PLANE_TOP_CLEAR else xi
        prev = y
    if start is not None:
        out.append((start * R, xs[-1] * R))
    return [(a, b) for a, b in out if b - a >= PLANE_MIN_RUN], top


class NavReach:
    """#294: the baked bot nav graph (assets/nav/<map>.json) — which spots a
    soldier can walk / jet to from each team base, and how far that walk is.
    A plane on a plateau no route leads to (Outpost's ridge in 1.38) is a prop."""

    def __init__(self, m, fname):
        self.ok = False
        f = os.path.join(MA.GAME, "assets", "nav", fname or "")
        if not fname or not os.path.isfile(f):
            return
        nav = json.load(open(f, encoding="utf-8"))
        ns = nav["nodes"]
        self.P = [(float(ns[i]), float(ns[i + 1])) for i in range(0, len(ns) - 1, 2)]
        self.adj = [[] for _ in self.P]
        e = nav["edges"]
        for i in range(0, len(e) - 1, 2):
            a, b = int(e[i]), int(e[i + 1])
            self.adj[a].append((b, float(np.hypot(self.P[a][0] - self.P[b][0], self.P[a][1] - self.P[b][1]))))
        self.dist = []
        for bx, by in bases(m):
            s = self.near((bx, by), 400.0)
            self.dist.append(self._dijkstra(s) if s >= 0 else {})
        self.ok = bool(self.dist)

    def near(self, p, maxd=120.0):
        best, bd = -1, maxd
        for i, q in enumerate(self.P):
            d = float(np.hypot(q[0] - p[0], q[1] - p[1]))
            if d < bd:
                best, bd = i, d
        return best

    def _dijkstra(self, s):
        import heapq
        d = {s: 0.0}
        q = [(0.0, s)]
        while q:
            c, u = heapq.heappop(q)
            if c > d[u]:
                continue
            for v, w in self.adj[u]:
                if c + w < d.get(v, 1e18):
                    d[v] = c + w
                    heapq.heappush(q, (c + w, v))
        return d

    def walks(self, p):
        """Walk (px) from each base to the spot, None where unreachable."""
        n = self.near(p)
        return [dd.get(n) if n >= 0 else None for dd in self.dist]


def _run_len(top, x, d, cap=None):
    """Runway (px) from x in direction d with the runway slope rules."""
    xi = int(round(x / R))
    run, prev, y0 = 0.0, top[xi], top[xi]
    if prev is None:
        return 0.0
    while cap is None or run < cap:
        xi += d * int(40 / R)
        if xi < 0 or xi >= len(top) or top[xi] is None or abs(top[xi] - prev) > PLANE_STEP or abs(top[xi] - y0) > PLANE_RISE:
            break
        prev = top[xi]
        run += 40.0
    return run


def plane_spots(m, solid, fname=None):
    """Plane spawns for one map: [x, ground_y] at a runway end.

    Inward = the end away from the middle, taking off toward it (preferred).
    Outward (#294) = the end nearer the middle, taking off away from it and
    turning back once airborne; used for a base only when no inward spot is
    within PLANE_NEAR_WALK of walking from it, and only where the game will
    face it that way (the run back toward the middle is much shorter). Every
    spot must be reachable on foot from every base (NavReach)."""
    rws, top = runways(m, solid)
    if not rws:
        return []
    W = MA.world_of(m)[0]
    nav = NavReach(m, fname)
    avoid = [(float(a[0]), float(a[1])) for k in ("vehicle_spawns", "tank_spawns", "heli_spawns") for a in (m.get(k) or [])]
    cands = []
    for a, b in rws:
        inward_x = a + 70.0 if (a + b) * 0.5 <= W * 0.5 else b - 70.0
        for x, outward in ((inward_x, False), (a + b - inward_x, True)):
            y = top[int(round(x / R))]
            if y is None:
                continue
            p = [round(x, 1), round(float(y), 1)]
            if any(np.hypot(x - ax, y - ay) < PLANE_AVOID for ax, ay in avoid):
                continue
            mid = 1 if x < W * 0.5 else -1
            d = -mid if outward else mid
            if outward and _run_len(top, x, mid, 880.0) > min(_run_len(top, x, d, 880.0), 880.0) - 120.0:
                continue   # the game would face it toward the middle (the longer run)
            if outward and (x if d < 0 else W - x) < PLANE_OUT_ROOM:
                continue   # no room to climb out and turn back before the side of the world
            if check_runway(m, p, solid, d) is not None:
                continue
            walks = nav.walks(p) if nav.ok else []
            if nav.ok and any(w is None for w in walks):
                continue   # no route to it from some base
            cands.append((p, b - a, outward, walks))
    if not cands:
        return []
    bs = bases(m)
    out = []
    if len(bs) == 2:
        for i, (bx, by) in enumerate(bs):
            def cost(c):
                w = c[3][i] if c[3] else float(np.hypot(c[0][0] - bx, c[0][1] - by))
                return w - min(c[1], 1500.0) * 0.4
            inward = [c for c in cands if not c[2]]
            near_in = [c for c in inward if c[3] and c[3][i] <= PLANE_NEAR_WALK]
            pool = inward if near_in or not nav.ok else cands
            if not pool:
                pool = cands
            best = min(pool, key=cost)
            if best[0] not in out:
                out.append(best[0])
        if len(out) == 2 and abs(out[0][0] - out[1][0]) < 900.0:
            out = out[:1]
    else:
        inward = [c for c in cands if not c[2]] or cands
        out.append(max(inward, key=lambda c: c[1])[0])
    return out


def check_runway(m, p, solid, d=None):
    """Re-check a plane spawn: on the top surface, with a runway ahead (toward
    the middle unless `d` says otherwise) and room to climb out."""
    top = surface(solid, m)
    W = MA.world_of(m)[0]
    x, y = p
    xi = int(round(x / R))
    if top[xi] is None or abs(top[xi] - y) > 4.0:
        return "not on the topmost ground"
    if d is None:
        d = 1 if x < W * 0.5 else -1
        if _run_len(top, x, d) < PLANE_MIN_RUN and _run_len(top, x, -d, 880.0) >= _run_len(top, x, d, 880.0) + 120.0:
            d = -d   # an outward spawn (#294): the game faces it along the longer run
    y0 = top[xi]
    run = _run_len(top, x, d, PLANE_MIN_RUN)
    if run < PLANE_MIN_RUN:
        return "runway only %d px" % int(run)
    # Climb-out: past the take-off point (~PLANE_LIFTOFF px down the runway)
    # the terrain ahead must stay under a gentle climb line.
    xi = int(round(x / R))
    s = 0.0
    while s < PLANE_MIN_RUN + PLANE_CLIMB_OUT:
        s += 40.0
        xj = xi + d * int(s / R)
        if xj < int(40 / R) or xj >= len(top) - int(40 / R):
            break
        if top[xj] is not None and top[xj] < y0 - max(0.0, s - PLANE_LIFTOFF) * PLANE_CLIMB_GRAD - PLANE_CLIMB_SLACK:
            return "terrain in the climb-out %d px ahead" % int(s)
    return None


def main_plane(argv):
    dry = "--dry" in argv
    cands = []
    for f in sorted(glob.glob(os.path.join(MA.GAME, "assets", "maps", "*.json"))):
        m = json.load(open(f, encoding="utf-8"))
        W, H, _, _ = MA.world_of(m)
        if W < PLANE_MIN_W:
            continue
        sky, solid = sky_fraction(m)
        if sky < PLANE_MIN_SKY:
            continue
        cands.append((sky * min(W, 10000.0), f, m, solid, sky))
    cands.sort(key=lambda c: -c[0])
    chosen = {}
    for _, f, m, solid, sky in cands:
        if len(chosen) >= PLANE_MAX_MAPS:
            break
        spots = plane_spots(m, solid, os.path.basename(f))
        bad = [check_runway(m, p, solid) for p in spots]
        spots = [p for p, b in zip(spots, bad) if b is None]
        name = os.path.basename(f)[:-5]
        print("%-12s %5dx%-5d sky=%.2f planes=%s %s" % (name, MA.world_of(m)[0], MA.world_of(m)[1], sky, spots,
              [b for b in bad if b] or ""))
        if spots:
            chosen[f] = spots
    for f in sorted(glob.glob(os.path.join(MA.GAME, "assets", "maps", "*.json"))):
        if dry:
            continue
        raw = open(f, encoding="utf-8").read()
        m = json.loads(raw)
        if f in chosen:
            if m.get("plane_spawns") == chosen[f]:
                continue
            m["plane_spawns"] = chosen[f]
        elif "plane_spawns" in m:
            m.pop("plane_spawns")
        else:
            continue
        json.dump(m, open(f, "w", encoding="utf-8"), indent=2)
    print("maps with planes: %d" % len(chosen))


REACH_DX = 160.0          # a reachable nav node this close sideways ...
REACH_DY = 60.0           # ... and this close in height = bots walk right past the spot
REACH_SLACK = 700.0       # walk base -> spot -> other base at most this much longer than base -> base
REACH_SAME = 600.0        # keep two spots of one kind this far apart


def reach_mask(m, fname, shape):
    """Raster cells (R px) with a nav node bots can walk to from every base
    within REACH_DX / REACH_DY (not an air waypoint). Also returns the
    NavReach and, per cell, the walk (px) from each base to that node."""
    nav = NavReach(m, fname)
    ny, nx = shape
    ok = np.zeros(shape, bool)
    walk = np.full((len(nav.dist) if nav.ok else 0,) + shape, np.inf, np.float32)
    if not nav.ok:
        return ok, nav, walk
    air = set(json.load(open(os.path.join(MA.GAME, "assets", "nav", fname), encoding="utf-8")).get("air", []))
    dx, dy = int(REACH_DX / R), int(REACH_DY / R)
    for j, (px, py) in enumerate(nav.P):
        if j in air:
            continue
        w = [dd.get(j) for dd in nav.dist]
        if any(v is None for v in w):
            continue
        cx, cy = int(px / R), int(py / R)
        y0, y1, x0, x1 = max(0, cy - dy), min(ny, cy + dy + 1), max(0, cx - dx), min(nx, cx + dx + 1)
        ok[y0:y1, x0:x1] = True
        for b, v in enumerate(w):
            walk[b, y0:y1, x0:x1] = np.minimum(walk[b, y0:y1, x0:x1], v)
    return ok, nav, walk


def main_reach(argv):
    """#302: move only the named buggy / tank spawns that bots can't walk to
    (BAKED nav graph) to the nearest drivable spot they can — near the same
    base, on the way between the bases. Every other spot stays as it is (a
    full re-run moves the spots of the smoothed maps).

        python3 tools/place_vehicles.py --reach [--dry] [--force] dusk:vehicle:0 outpost:tank:0:1400 ...

    An optional 4th field lowers the minimum drivable run for that spot;
    --force also moves spots bots can reach but never walk past (Rescue's
    roof buggy).
    """
    dry = "--dry" in argv
    jobs = {}
    for a in argv:
        if a.startswith("--"):
            continue
        f = a.split(":")
        jobs.setdefault(f[0], []).append((f[1] + "_spawns", int(f[2]), float(f[3]) if len(f) > 3 else None))
    for name, items in jobs.items():
        f = os.path.join(MA.GAME, "assets", "maps", name + ".json")
        m = json.load(open(f, encoding="utf-8"))
        bs = bases(m)
        changed = False
        for key, idx, min_run in items:
            w, h, mr = (TANK_W, TANK_H, TANK_MIN_RUN) if key == "tank_spawns" else (CAR_W, CAR_H, MIN_RUN)
            mr = min_run or mr
            sp, tot, edge_ok = runs(m, w, h)
            ok, nav, walk = reach_mask(m, name + ".json", tot.shape)
            old = m[key][idx]
            if ok[int(old[1] / R) - 1, int(old[0] / R)] and "--force" not in argv:
                print("%-10s %s[%d] %s already reachable" % (name, key, idx, old))
                continue
            cand = (tot >= mr) & edge_ok & ok
            ys, xs = np.nonzero(cand)
            pts = np.stack([xs * R, ys * R], 1)
            keep = np.ones(len(xs), bool)
            for k2 in ("vehicle_spawns", "tank_spawns", "heli_spawns", "plane_spawns"):
                for j, a in enumerate(m.get(k2) or []):
                    if k2 == key and j == idx:
                        continue
                    lim = REACH_SAME if k2 == key else 400.0
                    keep &= np.hypot(pts[:, 0] - a[0], pts[:, 1] - a[1]) > lim
            b = idx if idx < len(bs) else 0
            wb = walk[b, ys, xs]
            if len(bs) == 2:
                wo = walk[1 - b, ys, xs]
                d12 = nav.walks(bs[1 - b])[b] if nav.walks(bs[1 - b])[b] is not None else np.inf
                keep &= (wb + wo) <= d12 + REACH_SLACK
                keep &= wb <= wo   # on this base's half of the route
            if not keep.any():
                print("%-10s %s[%d] %s: NO reachable drivable spot" % (name, key, idx, old))
                continue
            cost = wb - np.minimum(tot[ys, xs], 2.0 * mr) * 0.3
            cost[~keep] = np.inf
            i = int(np.argmin(cost))
            new = [round(float(pts[i, 0]), 1), round(float(pts[i, 1]), 1)]
            print("%-10s %s[%d] %s -> %s (walk %d px from base %d, run %d px)" % (
                name, key, idx, old, new, wb[i], b, tot[ys[i], xs[i]]))
            m[key][idx] = new
            changed = True
        if changed and not dry:
            json.dump(m, open(f, "w", encoding="utf-8"), indent=2)


def main(argv):
    if "--heli" in argv:
        return main_heli(argv)
    if "--plane" in argv:
        return main_plane(argv)
    if "--reach" in argv:
        return main_reach(argv)
    dry = "--dry" in argv
    if "--builtin" in argv:
        for m in MA.builtin_maps():
            sp_, _ = pick(m)
            print(m["name"], sp_, "tank", pick_tank(m, sp_))
        return
    n = nt = 0
    for f in sorted(glob.glob(os.path.join(MA.GAME, "assets", "maps", "*.json"))):
        m = json.load(open(f, encoding="utf-8"))
        spots, best = pick(m)
        tanks = pick_tank(m, spots) if spots else []
        n += 1 if spots else 0
        nt += 1 if tanks else 0
        print("%-12s best_run=%5dpx spots=%s tanks=%s" % (os.path.basename(f)[:-5], best, spots, tanks))
        if not dry:
            if spots:
                m["vehicle_spawns"] = spots
            else:
                m.pop("vehicle_spawns", None)
            if tanks:
                m["tank_spawns"] = tanks
            else:
                m.pop("tank_spawns", None)
            json.dump(m, open(f, "w", encoding="utf-8"), indent=2)
    print("maps with vehicles: %d, with tanks: %d" % (n, nt))


if __name__ == "__main__":
    main(sys.argv[1:])
