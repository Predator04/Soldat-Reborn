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


def runs(m, w=CAR_W, h=CAR_H):
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
    edge_ok = (np.minimum(L, Rr) * R) >= w * 1.5
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


def main(argv):
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
