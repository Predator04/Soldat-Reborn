#!/usr/bin/env python3
"""build_nav.py — bake a bot navigation graph for every map.

Uses map_audit's free-space raster (where a standing 14x24 soldier fits) to
place nav nodes on every walkable surface (~40 px apart), then links node
pairs whose straight path is clear for a soldier's body. Upward links are
reachable with jump + jets (a full tank lifts a soldier > 1000 px), downward
links are drops. The result is written to assets/nav/<map-key>.json and loaded
by scripts/nav_graph.gd at match start; bots run A* over it (bot.gd).

    python3 tools/build_nav.py            # all maps
    python3 tools/build_nav.py arena      # maps whose label contains "arena"

Re-run after changing any map geometry (tools/map_audit.py should pass first).
"""
import json
import os
import re
import sys

import numpy as np
from scipy import ndimage

import map_audit as MA

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(os.path.dirname(HERE), "assets", "nav")
R = MA.R
NODE_STEP = 40.0        # px between nodes along a surface
LINK_DX = 230.0         # max horizontal span of a link
LINK_UP = 420.0         # max rise of a link (jet)
LINK_DOWN = 1300.0      # max drop of a link (no fall damage; long drops are fine)
LINK_DX_JET = 440.0     # longer, roughly level jet hops (gaps between ships)
LINK_DY_JET = 220.0
LINK_UP_V = 560.0       # near-vertical climbs (dx <= 120): a full tank rises ~800 px
DETOUR_MAX = 240.0
MIN_COMP = 12           # smaller disconnected islands are dropped      # how far beside a ledge we look for a clear climb column
LIFT = 6.0              # check paths with feet lifted a few px (slopes)


def map_key(name):
    return re.sub(r"[^a-z0-9]+", "_", str(name).lower()).strip("_") or "map"


def build(m):
    sp = MA.Space(m)
    if sp.main is None:
        return None
    main = sp.lab[0] == sp.main
    ground = sp.ground & main
    # Walkable only: slopes steeper than ~45 deg aren't standable (soldiers
    # slide down them), so nodes there led bots to slither off lips into pits.
    # Keep a cell if there's ground within +-8 px height 8 px to BOTH sides,
    # or it's a ledge lip on otherwise-flat ground (one side open air).
    gv = ndimage.binary_dilation(ground, structure=np.ones((9, 1), dtype=bool))
    k = 4
    left = np.zeros_like(ground)
    right = np.zeros_like(ground)
    left[:, k:] = gv[:, :-k]
    right[:, :-k] = gv[:, k:]
    gv2 = ndimage.binary_dilation(ground, structure=np.ones((3, 1), dtype=bool))
    l2 = np.zeros_like(ground)
    r2 = np.zeros_like(ground)
    l2[:, k:] = gv2[:, :-k]
    r2[:, :-k] = gv2[:, k:]
    walk = ground & ((left & right) | (l2 & ~right) | (r2 & ~left))
    ground = walk
    stand = sp.stand
    ny, nx = stand.shape
    step = int(NODE_STEP / R)
    nodes = []
    # Column sampling: every `step` cells, every separate surface in the column.
    for cx in range(0, nx, step):
        ys = np.nonzero(ground[:, cx])[0]
        last = -999
        for cy in ys:
            if cy - last < 6:        # same surface (a few-cell ground band)
                continue
            last = cy
            nodes.append((cx, cy))
    # Also add a node at each surface end (ledge lip / wall foot) so drops and
    # jumps off edges are represented: a ground cell with no ground within
    # +-5 cells vertically in the column to its left or right.
    gv = ndimage.binary_dilation(ground, structure=np.ones((11, 1), dtype=bool))
    left_has = np.zeros_like(ground)
    right_has = np.zeros_like(ground)
    left_has[:, 1:] = gv[:, :-1]
    right_has[:, :-1] = gv[:, 1:]
    lip = ground & ~(left_has & right_has)
    have = set((cx // 8, cy // 8) for (cx, cy) in nodes)
    ly, lx = np.nonzero(lip)
    for cy, cx in zip(ly.tolist(), lx.tolist()):
        key = (cx // 8, cy // 8)
        if key in have:
            continue
        have.add(key)
        nodes.append((cx, cy))
    if not nodes:
        return None
    pts = np.array(nodes, dtype=np.float64) * R  # (x, y) world
    # De-duplicate near-identical nodes (lip + column overlap).
    keep = []
    grid = {}
    for i, (x, y) in enumerate(pts):
        k = (int(x // 16), int(y // 16))
        if k in grid:
            continue
        grid[k] = i
        keep.append(i)
    pts = pts[keep]
    n = len(pts)
    lift = int(LIFT / R)

    def clear(a, b):
        (x0, y0), (x1, y1) = a, b
        length = max(abs(x1 - x0), abs(y1 - y0))
        steps = max(2, int(length / (R * 2)))
        t = np.linspace(0.0, 1.0, steps)
        xs = np.rint((x0 + (x1 - x0) * t) / R).astype(int)
        ys0 = np.rint((y0 + (y1 - y0) * t) / R).astype(int)
        if steps <= 2:
            return True
        # Interior samples must fit a standing body; endpoints are on ground.
        # Along steep slopes the box corner digs in, so allow a larger lift
        # (the soldier is jetting/hopping up those anyway).
        for lf in (lift, lift * 2, lift * 3):
            ys = ys0 - lf
            if xs.min() < 0 or ys.min() < 0 or xs.max() >= nx or ys.max() >= ny:
                return False
            if bool(stand[ys[1:-1], xs[1:-1]].all()):
                return True
        return False

    # Deadly columns: for a point (x, y), is there any ground below it before
    # the kill line? Links whose path crosses a bottomless stretch longer than
    # a short hop are dropped — bots (and their weak jets) kept falling in.
    import bisect
    col_ground = [np.nonzero(sp.ground[:, cx])[0] for cx in range(nx)]
    ky = int(sp.K / R) if sp.K is not None else ny

    def has_floor_below(x, y):
        cx = int(round(x / R))
        if cx < 0 or cx >= nx:
            return False
        rows = col_ground[cx]
        i = bisect.bisect_right(rows, int(y / R))
        return i < len(rows) and rows[i] < ky

    def void_span(a, b):
        (x0, y0), (x1, y1) = a, b
        n = max(2, int(abs(x1 - x0) / 8))
        run = best = 0.0
        for t in np.linspace(0.0, 1.0, n):
            x = x0 + (x1 - x0) * t
            y = y0 + (y1 - y0) * t
            if has_floor_below(x, y - 4):
                run = 0.0
            else:
                run += abs(x1 - x0) / n
                best = max(best, run)
        return best

    # Bucket for neighbour search.
    bucket = {}
    for i, (x, y) in enumerate(pts):
        bucket.setdefault(int(x // LINK_DX_JET), []).append(i)
    edges = []
    climb_cands = []
    for i, (x, y) in enumerate(pts):
        bx = int(x // LINK_DX_JET)
        for b in (bx - 1, bx, bx + 1):
            for j in bucket.get(b, []):
                if j == i:
                    continue
                x2, y2 = pts[j]
                dx = abs(x2 - x)
                dy = y2 - y  # >0 = target lower
                if dy > LINK_DOWN:
                    continue
                if dy < -LINK_UP and (dy < -LINK_UP_V or dx > 120.0):
                    continue
                if dx > LINK_DX and (dx > LINK_DX_JET or abs(dy) > LINK_DY_JET):
                    continue
                if dx < 1 and abs(dy) < 1:
                    continue
                # Long links only when roughly vertical/diagonal moves are needed;
                # flat neighbours beyond 1.6 steps are redundant.
                if abs(dy) < 20 and dx > NODE_STEP * 1.6:
                    continue
                if clear((x, y), (x2, y2)) and void_span((x, y), (x2, y2)) <= 56.0:
                    edges.append((i, j))
                elif dy < -40.0 and dx <= LINK_DX:
                    climb_cands.append((i, j))
    # Ledge detours: a platform right above us can't be reached in a straight
    # line (its own slab is in the way) — the real move is to step out past
    # its edge, jet up beside it and step on. Add an air waypoint beside the
    # lip for those, which is what joined one-way maps like Moonshine,
    # Triumph and Crackedboot (bases you could leave but never return to).
    have_edge = set(edges)
    air = {}
    pts_l = [tuple(p) for p in pts]
    per_src = {}
    for i, j in climb_cands:
        if (i, j) in have_edge or per_src.get(i, 0) >= 2:
            continue
        (x, y), (x2, y2) = pts_l[i], pts_l[j]
        done = False
        for k in range(40, int(DETOUR_MAX) + 1, 20):
            for sgn in (-1.0, 1.0):
                xe = x2 + sgn * k
                if abs(xe - x) > LINK_DX:
                    continue
                a = (xe, y)
                b = (xe, y2 - 24.0)
                if not (clear((x, y), a) and clear(a, b) and clear(b, (x2, y2))):
                    continue
                if void_span((x, y), a) > 56.0 or void_span(b, (x2, y2)) > 56.0:
                    continue
                key = (int(b[0] // 16), int(b[1] // 16))
                bi = air.get(key)
                if bi is None:
                    bi = len(pts_l)
                    pts_l.append(b)
                    air[key] = bi
                edges.append((i, bi))
                edges.append((bi, j))
                per_src[i] = per_src.get(i, 0) + 1
                done = True
                break
            if done:
                break
    pts = np.array(pts_l, dtype=np.float64)
    n = len(pts)
    # Keep the largest strongly-useful component (undirected view).
    if not edges:
        return None
    import collections
    adj = collections.defaultdict(set)
    for a, b in edges:
        adj[a].add(b)
        adj[b].add(a)
    seen = [-1] * n
    best = None
    keep_nodes = []
    for s in range(n):
        if seen[s] != -1 or s not in adj:
            continue
        comp = [s]
        seen[s] = s
        q = [s]
        while q:
            u = q.pop()
            for v in adj[u]:
                if seen[v] == -1:
                    seen[v] = s
                    comp.append(v)
                    q.append(v)
        if best is None or len(comp) > len(best):
            best = comp
        if len(comp) >= MIN_COMP:
            keep_nodes.extend(comp)
    # Keep every sizeable island, not just the largest: a base on a pillar
    # (Outpost) used to vanish from the graph, so defenders patrolled the
    # floor 600 px below and nobody could path around their own flag.
    best = sorted(set(best) | set(keep_nodes))
    idx = {old: new for new, old in enumerate(sorted(best))}
    out_nodes = []
    for old in sorted(best):
        out_nodes += [round(float(pts[old][0]), 1), round(float(pts[old][1]), 1)]
    out_edges = []
    for a, b in edges:
        if a in idx and b in idx:
            out_edges += [idx[a], idx[b]]
    return {"nodes": out_nodes, "edges": out_edges, "poly_count": len(m.get("polys", [])), "coll_count": len(m.get("collision", [])),
            "_dropped": n - len(best)}


def main(argv):
    only = argv[1] if len(argv) > 1 else None
    os.makedirs(OUT_DIR, exist_ok=True)
    for m in MA.builtin_maps() + MA.classic_maps():
        if only and only.lower() not in m["_label"].lower():
            continue
        nav = build(m)
        key = map_key(m["name"])
        if nav is None:
            print("!! %-20s no nav" % key)
            continue
        with open(os.path.join(OUT_DIR, key + ".json"), "w") as f:
            json.dump(nav, f, separators=(",", ":"))
        dropped = nav.pop("_dropped")
        with open(os.path.join(OUT_DIR, key + ".json"), "w") as f:
            json.dump(nav, f, separators=(",", ":"))
        print("%-20s nodes=%5d links=%6d dropped=%d" % (key, len(nav["nodes"]) // 2, len(nav["edges"]) // 2, dropped))


if __name__ == "__main__":
    main(sys.argv)
