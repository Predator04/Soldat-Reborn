#!/usr/bin/env python3
"""pms_to_map.py — Convert Soldat .pms binary maps into Soldat Reborn JSON maps.

Emits map dictionaries matching the schema Godot MapIO expects (see
scripts/map_io.gd), with an added "polys" array carrying flat float lists for
polygon terrain. Extra keys the runtime tolerates but ignores if missing:
scenery, m2_mounts, ctf_flags, inf_flag, htf_flag, rambo_pos, dom_points.

Usage:
    python3 tools/pms_to_map.py <input.pms> <output.json> [--name Display]

Coordinate system: .pms coordinates are centered on origin (Y grows down),
while the Reborn runtime uses a positive Godot 2D grid. We translate so bounds
map to a target rect within MAP_W=4800, MAP_H=2000, at a shared scale chosen
so a Soldat soldier (~30 px) matches Reborn's 46-px sprite (~1.5x).
"""

import argparse
import json
import os
import struct
import sys

# Target render window (mirrors main.gd MAP_W / MAP_H).
MAP_W = 4800.0
MAP_H = 2000.0
GROUND_Y = 1900.0  # main.gd's baseline floor (built-in maps)

# Per-map world layout for ported maps (see to_reborn_map).
SIDE_MARGIN = 160.0   # air between the map's outermost vertex and the side walls
TOP_MARGIN = 360.0    # jet headroom above the highest vertex
KILL_BELOW = 60.0     # fall this far below the lowest vertex = fell off the map

# Fixed scale keeps every ported map at the same soldier-to-terrain ratio.
# 1.5x roughly matches original Soldat (soldier ~30 px on-screen) to Reborn
# (soldier 46 px). Wider maps get x-clamped; taller ones y-clamped.
DEFAULT_SCALE = 1.5

# Soldat polygon types (opensoldat PolyMap.pas). Everything is DRAWN; only the
# collision class differs:
#   1 only-bullets, 10/12/14/16 team-bullets  -> bullets only (players pass)
#   2 only-player                              -> players only (bullets pass)
#   3 doesn't-collide, 11/13/15/17 team-player, 21 only-flaggers,
#   23 non-flagger-collides (TeamCollides() returns False for players),
#   24 background, 25 background-transition    -> no collision at all
#   everything else (normal, ice, deadly, hurts, bouncy, ...) -> solid
# Earlier ports dropped types 1/3/16 entirely (lost their artwork) and made
# 11/13/21/23/25 fully solid, which walled players into background art.
BULLETS_ONLY_POLY_TYPES = {1, 10, 12, 14, 16}
NON_SOLID_POLY_TYPES = {3, 11, 13, 15, 17, 21, 23, 24, 25}


def _read_bstr(b, o, fixed):
    ln = b[o]
    s = b[o + 1 : o + 1 + ln].decode("cp1252", "ignore")
    return s, o + 1 + fixed


def parse_pms(path):
    with open(path, "rb") as f:
        b = f.read()
    o = 0
    version = struct.unpack_from("<i", b, o)[0]
    o += 4
    name, o = _read_bstr(b, o, 38)
    texture, o = _read_bstr(b, o, 24)
    bg_top = struct.unpack_from("<I", b, o)[0]
    o += 4
    bg_bot = struct.unpack_from("<I", b, o)[0]
    o += 4
    jet = struct.unpack_from("<i", b, o)[0]
    o += 4
    grenades = b[o]
    medkits = b[o + 1]
    weather = b[o + 2]
    steps = b[o + 3]
    o += 4
    _rid = struct.unpack_from("<I", b, o)[0]
    o += 4

    # Polygons: 3 vertices (28b each) + 3 perpendiculars (12b each) + type byte.
    # Each vertex is TPMSVertex: pos(12) rhw(4) color(4) u,v(8) = 28 bytes.
    # UVs are in normalized texture-tile space so the runtime can multiply by
    # the actual texture size to sample a tiled terrain texture.
    poly_count = struct.unpack_from("<i", b, o)[0]
    o += 4
    polys = []
    for _ in range(poly_count):
        verts = []
        uvs = []
        cols = []
        for v in range(3):
            vb = o + v * 28
            x, y = struct.unpack_from("<ff", b, vb)
            u, vv = struct.unpack_from("<ff", b, vb + 20)
            # Vertex colour is stored B, G, R, A (opensoldat MapFile.pas::ReadColor).
            cb, cg, cr, ca = b[vb + 16], b[vb + 17], b[vb + 18], b[vb + 19]
            verts.append((x, y))
            uvs.append((u, vv))
            cols.append((cr, cg, cb, ca))
        ptype = b[o + 84 + 36]
        polys.append({"verts": verts, "uvs": uvs, "cols": cols, "type": ptype})
        o += 121

    # Sectors: variable-length (count word + count*word poly indices).
    _sdiv = struct.unpack_from("<i", b, o)[0]
    o += 4
    n_sect = struct.unpack_from("<i", b, o)[0]
    o += 4
    for _ in range((2 * n_sect + 1) ** 2):
        cnt = struct.unpack_from("<H", b, o)[0]
        o += 2 + cnt * 2

    # Sceneries: props (44 bytes each) reference types by index.
    prop_count = struct.unpack_from("<i", b, o)[0]
    o += 4
    props = []
    for _ in range(prop_count):
        active = b[o]
        style = struct.unpack_from("<H", b, o + 2)[0]
        pw, ph = struct.unpack_from("<ii", b, o + 4)
        x, y = struct.unpack_from("<ff", b, o + 12)
        rotation = struct.unpack_from("<f", b, o + 20)[0]
        sx, sy = struct.unpack_from("<ff", b, o + 24)
        alpha = b[o + 32]  # u8 + 3 pad bytes
        color = struct.unpack_from("<I", b, o + 36)[0]
        level = b[o + 40]  # u8 + 3 pad bytes
        props.append(
            dict(active=active, style=style, w=pw, h=ph, x=x, y=y,
                 rot=rotation, sx=sx, sy=sy,
                 alpha=alpha, color=color, level=level)
        )
        o += 44

    type_count = struct.unpack_from("<i", b, o)[0]
    o += 4
    types = []
    for _ in range(type_count):
        ln = b[o]
        types.append(b[o + 1 : o + 1 + ln].decode("cp1252", "ignore"))
        o += 55

    coll_count = struct.unpack_from("<i", b, o)[0]
    o += 4
    o += coll_count * 16  # (active i32, x f32, y f32, radius f32)

    spawn_count = struct.unpack_from("<i", b, o)[0]
    o += 4
    spawns = []
    for _ in range(spawn_count):
        active, sx, sy, team = struct.unpack_from("<Iii I", b, o)
        spawns.append(dict(active=active, x=sx, y=sy, team=team))
        o += 16

    return dict(
        version=version, name=name, texture=texture,
        bg_top=bg_top, bg_bot=bg_bot, jet=jet,
        grenades=grenades, medkits=medkits, weather=weather, steps=steps,
        polys=polys, props=props, types=types, spawns=spawns,
    )


def _bounds(polys):
    xs = [v[0] for p in polys for v in p["verts"]]
    ys = [v[1] for p in polys for v in p["verts"]]
    return min(xs), max(xs), min(ys), max(ys)


def _bgr_u32_to_rgb(v):
    # Background colours are read as a little-endian u32 of bytes B, G, R, A.
    return [round(((v >> 16) & 255) / 255.0, 3), round(((v >> 8) & 255) / 255.0, 3), round((v & 255) / 255.0, 3)]


def _col_for_type(t):
    """Poly type → Reborn collision class: 0 solid, 1 bullets only, 2 players only, 3 none."""
    if t in BULLETS_ONLY_POLY_TYPES:
        return 1
    if t == 2:
        return 2
    if t in NON_SOLID_POLY_TYPES:
        return 3
    return 0


def build_collision(polys):
    """Merge the map's collision triangles into clean outlines.

    Soldat maps are thousands of loose triangles. Used directly as physics
    shapes, the seams between them (T-junctions, sub-pixel overlaps, 1-2 px
    bumps) snag a sliding rectangle body — soldiers stop dead "on nothing"
    or need to hop. Here each collision class is unioned into polygons,
    micro-bumps are simplified away (<= 1 px), and polygons with holes are
    split along vertical cuts (CollisionPolygon2D can't have holes). The
    triangles stay for rendering only.
    """
    try:
        from shapely.geometry import Polygon, LineString
        from shapely.ops import unary_union, split
    except ImportError:
        print("  (shapely not installed — keeping per-triangle collision)")
        return None
    out = []
    for col in (0, 1, 2):
        tris = []
        for p in polys:
            if int(p.get("col", 0)) != col:
                continue
            pts = p["points"]
            poly = Polygon([(pts[i], pts[i + 1]) for i in range(0, len(pts) - 1, 2)])
            if poly.area > 0.25:
                tris.append(poly.buffer(0))
        if not tris:
            continue
        u = unary_union(tris).buffer(0).simplify(1.0, preserve_topology=True)
        queue = list(getattr(u, "geoms", [u]))
        guard = 0
        while queue and guard < 20000:
            guard += 1
            g = queue.pop()
            if g.geom_type != "Polygon" or g.area < 4.0:
                continue
            # Convex pieces with exactly shared edges: Godot's own concave
            # decomposition fails on some of these outlines ("Convex
            # decomposing failed!" = a missing wall), so do it here.
            for piece in _convex_pieces(g):
                for flat in _strict_convex(piece):
                    entry = {"points": flat}
                    if col:
                        entry["col"] = col
                    out.append(entry)
    return out


def _clean_ring(coords):
    """Round to 0.01 px, drop duplicates and (near-)collinear vertices."""
    pts = []
    for (x, y) in coords:
        q = (round(x, 2), round(y, 2))
        if not pts or q != pts[-1]:
            pts.append(q)
    if len(pts) > 1 and pts[0] == pts[-1]:
        pts.pop()
    changed = True
    while changed and len(pts) > 3:
        changed = False
        for i in range(len(pts)):
            a, b, c = pts[i - 1], pts[i], pts[(i + 1) % len(pts)]
            cr = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
            ln = max(1e-6, ((c[0] - a[0]) ** 2 + (c[1] - a[1]) ** 2) ** 0.5)
            if abs(cr) / ln < 0.05:
                pts.pop(i)
                changed = True
                break
    return pts


def _is_convex(pts):
    sign = 0
    for i in range(len(pts)):
        a, b, c = pts[i - 1], pts[i], pts[(i + 1) % len(pts)]
        cr = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
        if cr == 0:
            continue
        s_ = 1 if cr > 0 else -1
        if sign == 0:
            sign = s_
        elif s_ != sign:
            return False
    return True


def _strict_convex(piece):
    """Flat point lists for pieces Godot can take as-is (convex, non-degenerate).
    Anything else is emitted as its triangles."""
    import shapely
    from shapely.geometry import Polygon
    pts = _clean_ring(piece.exterior.coords)
    if len(pts) >= 3 and _is_convex(pts) and abs(Polygon(pts).area) >= 2.0:
        return [[c for p in pts for c in p]]
    out = []
    for t in shapely.constrained_delaunay_triangles(piece).geoms:
        tp = _clean_ring(t.exterior.coords)
        if len(tp) == 3 and abs(Polygon(tp).area) >= 0.5:
            out.append([c for p in tp for c in p])
    return out


def _convex_pieces(poly):
    """Constrained Delaunay triangulation + Hertel-Mehlhorn style greedy merge
    of neighbouring pieces while the result stays convex."""
    import shapely
    from shapely.geometry import Polygon
    tris = [t for t in shapely.constrained_delaunay_triangles(poly).geoms if t.area > 1e-3]
    pieces = [Polygon(t.exterior.coords) for t in tris]

    def ekey(a, b):
        a = (round(a[0], 3), round(a[1], 3))
        b = (round(b[0], 3), round(b[1], 3))
        return (a, b) if a < b else (b, a)

    changed = True
    while changed:
        changed = False
        edge_owner = {}
        for i, pc in enumerate(pieces):
            cs = list(pc.exterior.coords)
            for k in range(len(cs) - 1):
                edge_owner.setdefault(ekey(cs[k], cs[k + 1]), []).append(i)
        used = set()
        merged = []
        for i, pc in enumerate(pieces):
            if i in used:
                continue
            cs = list(pc.exterior.coords)
            done = False
            for k in range(len(cs) - 1):
                for j in edge_owner.get(ekey(cs[k], cs[k + 1]), []):
                    if j == i or j in used:
                        continue
                    u = pc.union(pieces[j])
                    if u.geom_type == "Polygon" and u.convex_hull.area - u.area < 0.01:
                        merged.append(Polygon(u.exterior.coords).simplify(0.0))
                        used.add(i)
                        used.add(j)
                        done = True
                        changed = True
                        break
                if done:
                    break
            if not done:
                merged.append(pc)
                used.add(i)
        pieces = merged
    return pieces


def to_reborn_map(pms, display_name=None, scale=DEFAULT_SCALE):
    minx, maxx, miny, maxy = _bounds(pms["polys"])
    s = scale

    # Every classic map is ported at the SAME scale and gets its own world rect
    # sized to fit it (earlier ports squeezed big maps into a fixed 4800x2000
    # box, shrinking corridors below soldier height on e.g. Messner/Fortress).
    off_x = SIDE_MARGIN - minx * s
    off_y = TOP_MARGIN - miny * s

    def tx(x): return x * s + off_x
    def ty(y): return y * s + off_y

    map_bottom = ty(maxy)
    world_w = (maxx - minx) * s + 2 * SIDE_MARGIN
    kill_y = map_bottom + KILL_BELOW
    ground_y = kill_y + 80.0
    world_h = ground_y + 60.0

    out_polys = []
    for p in pms["polys"]:
        col = _col_for_type(p["type"])
        pts_flat = []
        for (vx, vy) in p["verts"]:
            pts_flat.append(round(tx(vx), 2))
            pts_flat.append(round(ty(vy), 2))
        entry = {"points": pts_flat}
        uvs_flat = []
        for (u, v) in p.get("uvs", []):
            uvs_flat.append(round(u, 5))
            uvs_flat.append(round(v, 5))
        if uvs_flat:
            entry["uvs"] = uvs_flat
        cols = p.get("cols", [])
        if cols and any(c != (255, 255, 255, 255) for c in cols):
            entry["vc"] = ["%02x%02x%02x%02x" % c for c in cols]
        if col:
            entry["col"] = col
        out_polys.append(entry)

    # Bucket spawns by team.
    by_team = {}
    for s_ in pms["spawns"]:
        if not s_["active"]:
            continue
        by_team.setdefault(s_["team"], []).append((tx(s_["x"]), ty(s_["y"])))

    def r2(p): return [round(p[0], 2), round(p[1], 2)]

    # Soldat's Alpha team is RED and Bravo is BLUE (maps paint their bases
    # accordingly), so Bravo -> Reborn BLUE (team 1, ctf_flags[0]) and
    # Alpha -> Reborn RED (team 2). Earlier ports had this backwards, putting
    # the BLUE flag on the red-painted base.
    ctf_flags = []
    if by_team.get(6):
        ctf_flags.append(r2(by_team[6][0]))
    if by_team.get(5):
        ctf_flags.append(r2(by_team[5][0]))

    inf_flag = htf_flag = rambo_pos = None
    if by_team.get(14):
        inf_flag = r2(by_team[14][0])
        htf_flag = inf_flag[:]
    if by_team.get(15):
        rambo_pos = r2(by_team[15][0])
    m2_mounts = [r2(p) for p in by_team.get(16, [])]

    alpha = by_team.get(2, [])   # Soldat Bravo -> Reborn BLUE (player side)
    bravo = by_team.get(1, [])   # Soldat Alpha -> Reborn RED
    general = by_team.get(0, [])
    if alpha:
        player_spawn = list(alpha[0])
    elif general:
        player_spawn = list(general[0])
    elif bravo:
        player_spawn = list(bravo[0])
    else:
        player_spawn = [world_w * 0.3, TOP_MARGIN]

    bot_spawns = []
    seen = set()

    def _push(p):
        key = (round(p[0], 1), round(p[1], 1))
        if key in seen:
            return
        seen.add(key)
        bot_spawns.append(r2(p))

    for p in alpha[1:]:
        _push(p)
        if len(bot_spawns) >= 3:
            break
    for p in bravo:
        _push(p)
        if len(bot_spawns) >= 6:
            break
    for p in general:
        _push(p)
        if len(bot_spawns) >= 6:
            break
    if not bot_spawns:
        bot_spawns = [r2((world_w * 0.7, TOP_MARGIN))]

    scenery = []
    types = pms["types"]
    for prop in pms["props"]:
        if not prop["active"]:
            continue
        if prop["style"] == 0 or prop["style"] > len(types):
            continue
        name = types[prop["style"] - 1]
        if not name:
            continue
        scenery.append({
            "name": name,
            "pos": [round(tx(prop["x"]), 2), round(ty(prop["y"]), 2)],
            "scale": round(prop["sx"], 3),
            "scale_y": round(prop["sy"], 3),
            # Soldat draws a prop as a Width×Height quad (the ORIGINAL sprite
            # size) regardless of the texture's pixel size — our shipped
            # scenery PNGs are often HD (2-4x), so the runtime needs these to
            # size props correctly.
            "w": prop["w"],
            "h": prop["h"],
            "rot": round(prop["rot"], 4),
            "alpha": prop["alpha"],
            # Prop tint, stored B,G,R,A like every Soldat colour. Maps lean on
            # it heavily (e.g. huge black-tinted blank.png backdrops) — dropping
            # it rendered those as glaring white sheets.
            "color": "%02x%02x%02x" % ((prop["color"] >> 16) & 255, (prop["color"] >> 8) & 255, prop["color"] & 255),
            "level": prop["level"],
        })

    tex_ref = (pms.get("texture") or "").strip()
    terrain_texture = ""
    if tex_ref:
        stem = os.path.splitext(tex_ref)[0]
        terrain_texture = "res://assets/textures/%s.png" % stem.lower()

    m = {
        "name": display_name or pms["name"] or "Classic",
        "world": {
            "w": round(world_w, 1), "h": round(world_h, 1),
            "ground_y": round(ground_y, 1), "kill_y": round(kill_y, 1),
            "floor_visible": False,
        },
        "sky": {"top": _bgr_u32_to_rgb(pms["bg_top"]), "bottom": _bgr_u32_to_rgb(pms["bg_bot"])},
        "polys": out_polys,
        "platforms": [],
        "player_spawn": r2(player_spawn),
        "bot_spawns": bot_spawns,
        "ctf_ground_y": round(map_bottom, 2),
    }
    if ctf_flags:
        m["ctf_flags"] = ctf_flags
    if inf_flag:
        m["inf_flag"] = inf_flag
    if htf_flag:
        m["htf_flag"] = htf_flag
    if rambo_pos:
        m["rambo_pos"] = rambo_pos
    if m2_mounts:
        m["m2_mounts"] = m2_mounts
    # Per-team spawn lists so each side respawns at its own base in team
    # modes. (`alpha`/`bravo` here are already swapped to Reborn BLUE/RED —
    # see the ctf_flags comment above.)
    if alpha and bravo:
        m["team_spawns"] = {"1": [r2(p) for p in alpha[:8]], "2": [r2(p) for p in bravo[:8]]}
    if scenery:
        m["_scenery_hints"] = scenery
    if terrain_texture:
        m["terrain_texture"] = terrain_texture
    m["_source"] = {
        "pms_name": pms["name"],
        "pms_texture": pms["texture"],
        "scale": round(s, 4),
        "pms_bounds": [round(minx, 1), round(miny, 1), round(maxx, 1), round(maxy, 1)],
    }
    coll = build_collision(out_polys)
    if coll:
        m["collision"] = coll
    fixes = fix_entities(m)
    if fixes:
        m["_source"]["placement_fixes"] = fixes
    return m


def fix_entities(m):
    """Move any spawn / flag / mount that would start embedded in terrain, over a
    pit, or in a sealed pocket onto the nearest reachable ground. Flags are also
    settled onto the ground they'd rest on (they're drawn standing on their pole).
    Returns a list of human-readable notes (kept in _source for traceability)."""
    try:
        import map_audit as MA
    except ImportError:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import map_audit as MA
    sp = MA.Space(m)
    notes = []
    # Every objective the runtime needs gets an explicit, reachable spot —
    # otherwise main.gd falls back to 4800x2000-arena defaults (x=300 /
    # MAP_W-300 / fixed thirds on ctf_ground_y), which on ported maps land in
    # pits or inside rock. Soldat maps only ship flags for their own mode.
    xs = [v for p in m["polys"] if int(p.get("col", 0)) in MA.PLAYER_SOLID_COLS for v in p["points"][0::2]]
    ys = [v for p in m["polys"] if int(p.get("col", 0)) in MA.PLAYER_SOLID_COLS for v in p["points"][1::2]]
    cx, cy = (min(xs) + max(xs)) / 2.0, (min(ys) + max(ys)) / 2.0
    span = max(xs) - min(xs)

    def ground_near(x, y, r=4000.0):
        g = sp.nearest_good((x, y), max_r=r, flat=True) or sp.nearest_good((x, y), max_r=r)
        return None if g is None else [round(g[0], 2), round(g[1], 2)]

    if not m.get("ctf_flags"):
        ts = m.get("team_spawns") or {}
        a_sp, b_sp = ts.get("1"), ts.get("2")
        if a_sp and b_sp:
            ax = sum(p[0] for p in a_sp) / len(a_sp); ay = sum(p[1] for p in a_sp) / len(a_sp)
            bx = sum(p[0] for p in b_sp) / len(b_sp); by = sum(p[1] for p in b_sp) / len(b_sp)
            fa, fb = ground_near(ax, ay), ground_near(bx, by)
        else:
            fa, fb = ground_near(min(xs) + span * 0.12, cy), ground_near(max(xs) - span * 0.12, cy)
        if not (fa and fb) or abs(fa[0] - fb[0]) < span * 0.35:
            # Team spawns overlap (DM-style layout) — put the bases at the two
            # most widely separated reachable spawn landings instead.
            lands = []
            for p in [m["player_spawn"]] + m.get("bot_spawns", []):
                _, l = sp.check("spawn", p)
                if l is not None:
                    lands.append([round(l[0], 2), round(l[1], 2)])
            if len(lands) >= 2:
                lands.sort(key=lambda q: q[0])
                fa, fb = lands[0], lands[-1]
            if not (fa and fb) or abs(fa[0] - fb[0]) < span * 0.35:
                # Leftmost / rightmost flat, reachable ground.
                import numpy as _np
                fy, fx = _np.nonzero(sp.flat_ground())
                if fx.size:
                    lo, hi = _np.percentile(fx, 3), _np.percentile(fx, 97)
                    il = int(_np.argmin(_np.abs(fx - lo)))
                    ih = int(_np.argmin(_np.abs(fx - hi)))
                    fa = [float(fx[il] * MA.R), float(fy[il] * MA.R)]
                    fb = [float(fx[ih] * MA.R), float(fy[ih] * MA.R)]
        if fa and fb:
            m["ctf_flags"] = [fa, fb]
            notes.append("ctf_flags generated -> %s %s" % (fa, fb))
    if m.get("inf_flag") is None:
        c = ground_near(cx, cy)
        if c:
            m["inf_flag"] = c
            m["htf_flag"] = list(c)
    if m.get("rambo_pos") is None:
        c = m.get("inf_flag")
        if c:
            m["rambo_pos"] = [c[0], c[1] - 40.0]
    if not m.get("dom_points"):
        pts = []
        for f in (0.2, 0.5, 0.8):
            g = ground_near(min(xs) + span * f, cy)
            if g:
                pts.append([g[0], round(g[1] - 30.0, 2)])  # DOM points hover 30 px up
        if len(pts) == 3:
            m["dom_points"] = pts
    if not m.get("point_spawns"):
        pts = []
        for f in (0.1, 0.25, 0.4, 0.5, 0.6, 0.75, 0.9):
            g = ground_near(min(xs) + span * f, cy)
            if g and all(abs(g[0] - q[0]) + abs(g[1] - q[1]) > 80 for q in pts):
                pts.append([g[0], round(g[1] - 30.0, 2)])
        if pts:
            m["point_spawns"] = pts

    def fix(kind, p, settle):
        prob, landing = sp.check(kind, p)
        if prob is None:
            if settle and landing is not None:
                return [round(landing[0], 2), round(landing[1], 2)], None
            return p, None
        good = sp.nearest_good(landing if landing is not None else p)
        if good is None:
            good = sp.nearest_good(p, max_r=4000.0)
        if good is None:
            return p, "%s: %s (no safe spot found)" % (kind, prob)
        return [round(good[0], 2), round(good[1], 2)], "%s (%d,%d): %s -> (%d,%d)" % (kind, p[0], p[1], prob, good[0], good[1])

    for key, settle in (("player_spawn", False), ("inf_flag", True), ("htf_flag", True), ("rambo_pos", False)):
        if m.get(key) is not None:
            m[key], n = fix(key, m[key], settle)
            if n:
                notes.append(n)
    for t, arr in (m.get("team_spawns") or {}).items():
        for i, p in enumerate(arr):
            arr[i], n = fix("team_spawns[%s]" % t, p, False)
            if n:
                notes.append(n)
    for key, settle in (("bot_spawns", False), ("ctf_flags", True), ("m2_mounts", False)):
        arr = m.get(key, [])
        for i, p in enumerate(arr):
            arr[i], n = fix(key, p, settle)
            if n:
                notes.append(n)
    return notes


def regen_bundled(pms_dir, maps_dir, scale=DEFAULT_SCALE):
    """Re-port every bundled map in maps_dir from the matching .pms in pms_dir
    (e.g. a checkout of github.com/opensoldat/base), keeping each JSON's display
    name and any hand-added keys such as "weather"."""
    import glob
    pms_by_stem = {}
    for f in glob.glob(os.path.join(pms_dir, "**", "*.pms"), recursive=True):
        st = os.path.splitext(os.path.basename(f))[0].lower()
        pms_by_stem[st] = f
        for prefix in ("ctf_", "inf_", "htf_"):
            if st.startswith(prefix):
                pms_by_stem.setdefault(st[len(prefix):], f)
    for jf in sorted(glob.glob(os.path.join(maps_dir, "*.json"))):
        stem = os.path.splitext(os.path.basename(jf))[0]
        if stem not in pms_by_stem:
            print("skip %s (no .pms found)" % stem)
            continue
        with open(jf, encoding="utf-8") as f:
            old = json.load(f)
        m = to_reborn_map(parse_pms(pms_by_stem[stem]), display_name=old.get("name"), scale=scale)
        for keep in ("weather",):
            if keep in old:
                m[keep] = old[keep]
        with open(jf, "w", encoding="utf-8") as f:
            json.dump(m, f, indent=2)
        fixes = m["_source"].get("placement_fixes", [])
        print("%-12s %5d x %-5d  fixes=%d" % (stem, m["world"]["w"], m["world"]["h"], len(fixes)))
        for n in fixes:
            print("      ", n)


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "--regen":
        # python3 tools/pms_to_map.py --regen <opensoldat-base-dir> [maps-dir]
        here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        maps_dir = sys.argv[3] if len(sys.argv) > 3 else os.path.join(here, "assets", "maps")
        regen_bundled(sys.argv[2], maps_dir)
        return
    ap = argparse.ArgumentParser()
    ap.add_argument("input", help="Path to input .pms")
    ap.add_argument("output", help="Path to output .json")
    ap.add_argument("--name", help="Display name (default: strip prefix from filename)")
    ap.add_argument("--scale", type=float, default=DEFAULT_SCALE)
    args = ap.parse_args()

    pms = parse_pms(args.input)
    display = args.name
    if not display:
        stem = os.path.splitext(os.path.basename(args.input))[0]
        for prefix in ("ctf_", "inf_", "htf_"):
            if stem.startswith(prefix):
                stem = stem[len(prefix):]
                break
        display = stem
    m = to_reborn_map(pms, display_name=display, scale=args.scale)
    with open(args.output, "w") as f:
        json.dump(m, f, indent=2)
    print(f"Wrote {args.output}  polys={len(m['polys'])}  spawns={len(m['bot_spawns'])+1}  scale={m['_source']['scale']}")


if __name__ == "__main__":
    main()
