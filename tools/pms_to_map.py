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

    ctf_flags = []
    if by_team.get(5):
        ctf_flags.append(r2(by_team[5][0]))
    if by_team.get(6):
        ctf_flags.append(r2(by_team[6][0]))

    inf_flag = htf_flag = rambo_pos = None
    if by_team.get(14):
        inf_flag = r2(by_team[14][0])
        htf_flag = inf_flag[:]
    if by_team.get(15):
        rambo_pos = r2(by_team[15][0])
    m2_mounts = [r2(p) for p in by_team.get(16, [])]

    alpha = by_team.get(1, [])
    bravo = by_team.get(2, [])
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
        if "falls" in prob and "pocket" not in prob and not settle:
            return p, None  # a long drop isn't a trap — keep Soldat's airborne spawns
        return [round(good[0], 2), round(good[1], 2)], "%s (%d,%d): %s -> (%d,%d)" % (kind, p[0], p[1], prob, good[0], good[1])

    for key, settle in (("player_spawn", False), ("inf_flag", True), ("htf_flag", True), ("rambo_pos", False)):
        if m.get(key) is not None:
            m[key], n = fix(key, m[key], settle)
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
