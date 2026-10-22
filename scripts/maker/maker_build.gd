extends Object
## Maker mode compiler (#286): turns the editor's SOURCE map (normal map keys
## for entities + a "maker" block holding the terrain / hazard / pad / prop
## pieces) into the PLAYABLE map JSON every map reader already understands,
## and back.
##
## compile():
##   * solid pieces of one collision class that touch or overlap are unioned
##     (Geometry2D.merge_polygons) into clean outlines; corners get small
##     fillets (<= ~4 px, like tools/smooth_maps.py); each outline becomes
##     convex "collision" pieces (decompose_polygon_in_convex) plus drawn
##     "polys" clipped to a 160 px grid so every cell carries per-vertex colours
##     by depth below the surface (theme: lip -> body -> deep) and tile UVs —
##     the HD terrain (#283) picks materials + painted edges from those.
##   * spikes / lava -> "hazards" (lava adds a rock basin under the pool),
##     pads -> "jump_pads", props -> a "prop" collision box + scenery sprite.
##   * theme -> terrain_texture, sky, weather; maker size / bottom -> world.
##   * anything that was in the map before (Advanced-mode polys, platforms,
##     collision) is kept in front; the maker block records how much, so
##     decompile() can strip exactly what compile() generated.
##   * maps without platforms get one 8 px "anchor" platform outside the world
##     (left of the side wall, above the top): older readers — e.g. the map
##     library's share check — treat a map with no platforms as empty.
## A map without a "maker" block passes through unchanged.

const Pieces = preload("res://scripts/maker/maker_pieces.gd")
const Themes = preload("res://scripts/maker/maker_themes.gd")

const VERSION := 1
const CELL := 160.0
const FILLET := 12.0
const BASIN_H := 60.0      # rock under a lava pool...
const BASIN_RIM := 20.0    # ...and the walls either side of it
const ANCHOR_POS := Vector2(-200, -200)
const ANCHOR_SIZE := Vector2(8, 8)
const DEFAULT_W := 4800.0
const DEFAULT_H := 2000.0
const SIZES := [["S", 3200.0, 1600.0], ["M", 4800.0, 2000.0], ["L", 7200.0, 2600.0], ["XL", 9600.0, 3200.0]]

const TEAM_MODES := [1, 2, 3, 4, 6, 7, 10]   # Settings.is_team_mode()
const MODE_CTF := 2
const MODE_INF := 3
const MODE_HTF := 4
const MODE_RM := 5
const MODE_DOM := 7
const MODE_BOMB := 10


static func is_maker(m: Dictionary) -> bool:
	return m.has("maker") and typeof(m["maker"]) == TYPE_DICTIONARY


## The maker block of a source map, created (from the map's current world /
## hazards / pads) the first time Maker mode edits it.
static func ensure_maker(m: Dictionary, theme: String = "grassland") -> Dictionary:
	if is_maker(m):
		return m["maker"]
	var w: Dictionary = m.get("world", {}) if typeof(m.get("world", {})) == TYPE_DICTIONARY else {}
	var mk := {"v": VERSION, "theme": theme, "grid": 20,
		"w": float(w.get("w", DEFAULT_W)), "h": float(w.get("h", DEFAULT_H)),
		"bottom": "floor" if bool(w.get("floor_visible", true)) else "void", "pieces": []}
	# Hand-written hazards / pads become pieces (compile regenerates the keys).
	for h in m.get("hazards", []):
		if typeof(h) == TYPE_DICTIONARY and h.get("rect") is Rect2:
			var r: Rect2 = h["rect"]
			var kind := str(h.get("kind", "spikes"))
			var c := r.get_center()
			var sz := r.size
			if kind == "lava":
				(mk["pieces"] as Array).append(make_piece("lava", c, sz))
			else:
				var d := int(h.get("dir", 0))
				if d % 2 == 1:
					sz = Vector2(sz.y, sz.x)
				(mk["pieces"] as Array).append(make_piece("spikes", c, sz, d))
	for j in m.get("jump_pads", []):
		if typeof(j) == TYPE_DICTIONARY:
			var big := float(j.get("power", 1150.0)) > 1400.0
			var foot: Vector2 = j.get("pos", Vector2.ZERO)
			(mk["pieces"] as Array).append(make_piece("pad_big" if big else "pad", foot - Vector2(0, 10), Vector2(64, 20)))
	# Bomb sites (#304) written by hand / Advanced become pieces too.
	for b in m.get("bomb_sites", []):
		if typeof(b) == TYPE_DICTIONARY and b.get("rect") is Rect2:
			var br: Rect2 = b["rect"]
			(mk["pieces"] as Array).append(make_piece("site_b" if str(b.get("name", "A")) == "B" else "site_a", br.get_center(), br.size))
	m.erase("hazards")
	m.erase("jump_pads")
	m.erase("bomb_sites")
	m["maker"] = mk
	return mk


## A piece dict with fixed key order and number types (JSON round trips must
## compare equal).
static func make_piece(id: String, center: Vector2, size: Vector2, rot: int = 0, flip: int = 0) -> Dictionary:
	return {"t": id, "x": float(center.x), "y": float(center.y), "w": float(size.x), "h": float(size.y),
		"r": posmod(rot, 4), "f": 1 if flip != 0 else 0}


static func norm_piece(p: Dictionary) -> Dictionary:
	return make_piece(str(p.get("t", "block")), Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0))),
		Vector2(float(p.get("w", 100.0)), float(p.get("h", 100.0))), int(p.get("r", 0)), int(p.get("f", 0)))


static func new_piece(id: String, center: Vector2) -> Dictionary:
	var d := Pieces.def(id)
	return make_piece(id, center, Vector2(float(d.get("w", 100.0)), float(d.get("h", 100.0))), 0, int(d.get("f", 0)))


# ── Piece geometry ───────────────────────────────────────────────────────────

## World-space size of a piece's bounding box (odd rotations swap w / h).
static func piece_size(p: Dictionary) -> Vector2:
	var s := Vector2(float(p.get("w", 0.0)), float(p.get("h", 0.0)))
	return Vector2(s.y, s.x) if int(p.get("r", 0)) % 2 == 1 else s


static func piece_rect(p: Dictionary) -> Rect2:
	var s := piece_size(p)
	var c := Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))
	var r := Rect2(c - s * 0.5, s)
	if str(p.get("t", "")) == "lava":
		r = Rect2(r.position.x - BASIN_RIM, r.position.y, r.size.x + BASIN_RIM * 2.0, r.size.y + BASIN_H)
	return r


## The rock tub a lava pool `r` sits in (a U: walls + floor), merged with any
## ground it touches.
static func lava_basin(r: Rect2) -> PackedVector2Array:
	var x0 := r.position.x
	var x1 := r.end.x
	var top := r.position.y
	var bot := r.end.y - 2.0
	return PackedVector2Array([Vector2(x0 - BASIN_RIM, top), Vector2(x0, top), Vector2(x0, bot), Vector2(x1, bot),
		Vector2(x1, top), Vector2(x1 + BASIN_RIM, top), Vector2(x1 + BASIN_RIM, r.end.y + BASIN_H), Vector2(x0 - BASIN_RIM, r.end.y + BASIN_H)])


## The piece's own outline in world space (shapes; hazards / pads / props use
## their rect).
static func piece_polygon(p: Dictionary) -> PackedVector2Array:
	var d := Pieces.def(str(p.get("t", "")))
	var c := Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))
	var shape := str(d.get("shape", "rect")) if str(d.get("kind", "")) == "shape" else "rect"
	var local := Pieces.local_shape(shape, float(p.get("w", 0.0)), float(p.get("h", 0.0)))
	return Pieces.transform_shape(local, c, int(p.get("r", 0)), int(p.get("f", 0)) == 1)


# ── Compile ──────────────────────────────────────────────────────────────────

static func world_of(mk: Dictionary) -> Dictionary:
	var w := clampf(float(mk.get("w", DEFAULT_W)), 1600.0, 12000.0)
	var h := clampf(float(mk.get("h", DEFAULT_H)), 1000.0, 6000.0)
	if str(mk.get("bottom", "void")) == "floor":
		return {"w": w, "h": h, "ground_y": h - 100.0, "floor_visible": true}
	return {"w": w, "h": h, "ground_y": h - 40.0, "kill_y": h - 100.0, "floor_visible": false}


static func compile(src: Dictionary) -> Dictionary:
	if not is_maker(src):
		return src.duplicate(true)
	var mk: Dictionary = src["maker"]
	var out := src.duplicate(true)
	var theme := str(mk.get("theme", "grassland"))
	var th := Themes.get_theme(theme)
	var tex := str(th["tex"])
	var tsz := Vector2(512, 512)
	var tx := Pieces.tex(tex)
	if tx != null:
		tsz = tx.get_size()
	out["world"] = world_of(mk)
	out["sky"] = Themes.sky(theme)
	if str(th["weather"]) != "":
		out["weather"] = str(th["weather"])
	else:
		out.erase("weather")
	# Base terrain (Advanced polys / ported collision) stays in front.
	var base_polys: Array = out.get("polys", [])
	var had_coll: bool = src.has("collision") and typeof(src["collision"]) == TYPE_ARRAY and not (src["collision"] as Array).is_empty()
	var coll: Array = (out["collision"] as Array) if had_coll else []
	var base_coll := coll.size()
	var old_tex := str(src.get("terrain_texture", ""))
	for poly in base_polys:
		if not poly.has("texture"):
			poly["texture"] = old_tex
		if not had_coll:
			var cc := int(poly.get("col", 0))
			if cc != 3:
				for piece in _convex(poly.get("points", PackedVector2Array())):
					coll.append({"points": piece, "col": cc})
	out["terrain_texture"] = tex
	# Maker pieces.
	var groups := {"0": [], "2": [], "2w": [], "1": []}
	var hazards: Array = []
	var pads: Array = []
	var props: Array = []
	var bomb_sites: Array = []
	for p in mk.get("pieces", []):
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var id := str(p.get("t", ""))
		var d := Pieces.def(id)
		match str(d.get("kind", "")):
			"shape":
				var col := int(d.get("col", 0))
				var key := str(col) + ("w" if str(d.get("tint", "")) == "wood" else "")
				(groups[key] as Array).append(piece_polygon(p))
			"hazard":
				var r := Rect2(Vector2(float(p["x"]), float(p["y"])) - piece_size(p) * 0.5, piece_size(p))
				hazards.append({"kind": str(d.get("hz", "spikes")), "dir": int(p.get("r", 0)) if str(d.get("hz", "")) == "spikes" else 0, "rect": r})
				if str(d.get("hz", "")) == "lava":
					(groups["0"] as Array).append(lava_basin(r))
			"pad":
				pads.append({"pos": Vector2(float(p["x"]), float(p["y"]) + float(p.get("h", 20.0)) * 0.5), "power": float(d.get("power", 1150.0))})
			"prop":
				props.append({"p": p, "d": d})
			"site":
				var nm := str(d.get("site", "A"))
				var dup := false
				for s in bomb_sites:
					dup = dup or str(s["name"]) == nm
				if not dup:
					bomb_sites.append({"name": nm, "rect": piece_rect(p)})
	var drawn: Array = []
	var outlines: Array = []
	for key in ["0", "2", "2w", "1"]:
		var col := int(key.substr(0, 1))
		var tint := "wood" if key == "2w" else ("glass" if key == "1" else "")
		for o in union_all(groups[key]):
			var rounded := fillet(o, FILLET if col == 0 else 3.0)
			if Geometry2D.triangulate_polygon(rounded).is_empty():
				rounded = _snap_pts(o)   # a fillet folded a tiny edge: keep it sharp
			outlines.append({"pts": rounded, "col": col, "tint": tint})
			for piece in _convex(rounded):
				coll.append({"points": piece, "col": col})
			drawn.append_array(_cells(rounded, theme, col, tint, tex, tsz))
	# Props: solid box (no painted edge) + their sprite in front of the terrain.
	var scn: Array = (out.get("scenery", []) as Array)
	var base_scn := scn.size()
	for pr in props:
		var p: Dictionary = pr["p"]
		var d: Dictionary = pr["d"]
		var r := piece_rect(p)
		var inset := minf(2.0, r.size.y * 0.1)
		var cr := r.grow_individual(-inset, -inset * 0.5, -inset, 0.0)
		coll.append({"points": PackedVector2Array([cr.position, Vector2(cr.end.x, cr.position.y), cr.end, Vector2(cr.position.x, cr.end.y)]),
			"col": 0, "prop": true})
		var t := Pieces.tex(str(d.get("tex", "")))
		var sc := 1.0
		if t != null:
			sc = r.size.x / maxf(1.0, t.get_size().x)
		scn.append({"tex": str(d.get("tex", "")), "pos": r.get_center(), "scale": snappedf(sc, 0.0001), "z": 0})
	if not scn.is_empty():
		out["scenery"] = scn
	out["polys"] = base_polys + drawn
	out["collision"] = coll
	out["hazards"] = hazards
	out["jump_pads"] = pads
	if bomb_sites.is_empty():
		out.erase("bomb_sites")
	else:
		bomb_sites.sort_custom(func(a, b) -> bool: return str(a["name"]) < str(b["name"]))
		out["bomb_sites"] = bomb_sites
	var mk_out := {"v": VERSION, "theme": theme, "grid": int(mk.get("grid", 20)), "w": float(out["world"]["w"]),
		"h": float(out["world"]["h"]), "bottom": str(mk.get("bottom", "void")), "pieces": [],
		"base_polys": base_polys.size(), "base_coll": base_coll if had_coll else -1, "base_scenery": base_scn}
	for p in mk.get("pieces", []):
		if typeof(p) == TYPE_DICTIONARY:
			(mk_out["pieces"] as Array).append(norm_piece(p))
	# Free-for-all spawns: team spawns count when no FFA spawn was placed.
	if (out.get("bot_spawns", []) as Array).is_empty():
		var ffa: Array = []
		var ts: Variant = out.get("team_spawns", {})
		if typeof(ts) == TYPE_DICTIONARY:
			for k in [1, 2]:
				for v in (ts as Dictionary).get(k, []):
					ffa.append(v)
		if not ffa.is_empty():
			out["bot_spawns"] = ffa
			mk_out["ffa_fill"] = true
	if (out.get("platforms", []) as Array).is_empty():
		out["platforms"] = [{"p": ANCHOR_POS, "s": ANCHOR_SIZE}]
		mk_out["anchor"] = true
	# Objectives the map maker didn't place: put them on the terrain here, so
	# every mode works on this map (the game's own defaults sit at ground_y,
	# under the kill line of a bottomless Maker map).
	var auto: Array = _auto_objectives(out)
	if not auto.is_empty():
		mk_out["auto"] = auto
	out["maker"] = mk_out
	out["_mk_outlines"] = outlines   # editor preview only (map_io never writes it)
	return out


## Strip what compile() generated: back to the editor's source form.
static func decompile(m: Dictionary) -> Dictionary:
	if not is_maker(m):
		return m
	var out := m.duplicate(true)
	var mk: Dictionary = out["maker"]
	var polys: Array = out.get("polys", [])
	out["polys"] = polys.slice(0, clampi(int(mk.get("base_polys", polys.size())), 0, polys.size()))
	var bc := int(mk.get("base_coll", -1))
	if bc < 0:
		out.erase("collision")
	else:
		var coll: Array = out.get("collision", [])
		out["collision"] = coll.slice(0, clampi(bc, 0, coll.size()))
	if out.has("scenery"):
		var scn: Array = out["scenery"]
		out["scenery"] = scn.slice(0, clampi(int(mk.get("base_scenery", scn.size())), 0, scn.size()))
		if (out["scenery"] as Array).is_empty():
			out.erase("scenery")
	out.erase("hazards")
	out.erase("jump_pads")
	out.erase("bomb_sites")
	out.erase("_mk_outlines")
	if bool(mk.get("ffa_fill", false)):
		out["bot_spawns"] = []
	for k in mk.get("auto", []):
		out.erase(str(k))
	if bool(mk.get("anchor", false)):
		var keep: Array = []
		for pl in out.get("platforms", []):
			if not (pl.get("p") == ANCHOR_POS and pl.get("s") == ANCHOR_SIZE):
				keep.append(pl)
		out["platforms"] = keep
	var clean := {"v": VERSION, "theme": str(mk.get("theme", "grassland")), "grid": int(mk.get("grid", 20)),
		"w": float(mk.get("w", DEFAULT_W)), "h": float(mk.get("h", DEFAULT_H)), "bottom": str(mk.get("bottom", "void")), "pieces": []}
	for p in mk.get("pieces", []):
		if typeof(p) == TYPE_DICTIONARY and Pieces.def(str(p.get("t", ""))).size() > 0:
			(clean["pieces"] as Array).append(norm_piece(p))
	out["maker"] = clean
	return out


# ── Geometry ─────────────────────────────────────────────────────────────────

static func _area(p: PackedVector2Array) -> float:
	var a := 0.0
	var n := p.size()
	for i in n:
		var q: Vector2 = p[i]
		var r: Vector2 = p[(i + 1) % n]
		a += q.x * r.y - r.x * q.y
	return a * 0.5


## Union of overlapping / touching outlines. A merge that would leave a hole
## (a fully enclosed room) is skipped: those pieces stay separate outlines.
static func union_all(polys: Array) -> Array:
	var outs: Array = []
	for p0 in polys:
		var cur: PackedVector2Array = p0
		if cur.size() < 3 or absf(_area(cur)) < 1.0:
			continue
		if _area(cur) < 0.0:
			cur.reverse()
		var i := 0
		while i < outs.size():
			var r := Geometry2D.merge_polygons(outs[i], cur)
			# One clean outline only: pieces touching at a single corner can
			# come back pinched (not triangulable) — keep those separate.
			if r.size() == 1 and not Geometry2D.triangulate_polygon(r[0]).is_empty():
				cur = r[0]
				if _area(cur) < 0.0:
					cur.reverse()
				outs.remove_at(i)
				i = 0
				continue
			i += 1
		outs.append(cur)
	return outs


## Small rounded corners: each corner sharper than ~12 deg becomes a quadratic
## curve that starts / ends at most `r` (and 45 % of the edge) away from it.
static func fillet(poly: PackedVector2Array, r: float) -> PackedVector2Array:
	var n := poly.size()
	if n < 3 or r <= 0.5:
		return poly
	var out := PackedVector2Array()
	for i in n:
		var prev: Vector2 = poly[(i - 1 + n) % n]
		var cur: Vector2 = poly[i]
		var nxt: Vector2 = poly[(i + 1) % n]
		var d1 := cur - prev
		var d2 := nxt - cur
		var l1 := d1.length()
		var l2 := d2.length()
		if l1 < 0.01 or l2 < 0.01:
			out.append(cur)
			continue
		d1 /= l1
		d2 /= l2
		var turn := absf(d1.angle_to(d2))
		var rr := minf(r, minf(l1, l2) * 0.45)
		if turn < deg_to_rad(12.0) or rr < 1.5:
			out.append(cur)
			continue
		var a := cur - d1 * rr
		var b := cur + d2 * rr
		var segs := 4 if turn > 1.0 else 3
		for k in segs + 1:
			var t := float(k) / float(segs)
			out.append(a.lerp(cur, t).lerp(cur.lerp(b, t), t))
	return _snap_pts(out)


static func _snap_pts(p: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in p:
		var s := v.snapped(Vector2(0.01, 0.01))
		if out.is_empty() or out[out.size() - 1].distance_to(s) > 0.05:
			out.append(s)
	if out.size() > 1 and out[0].distance_to(out[out.size() - 1]) <= 0.05:
		out.remove_at(out.size() - 1)
	return out


static func _convex(pts: PackedVector2Array) -> Array:
	if pts.size() < 3:
		return []
	var out: Array = []
	for c in Geometry2D.decompose_polygon_in_convex(pts):
		var s := _snap_pts(c)
		if s.size() >= 3 and absf(_area(s)) > 0.5:
			out.append(s)
	if out.is_empty():
		var idx := Geometry2D.triangulate_polygon(pts)
		var i := 0
		while i + 2 < idx.size():
			out.append(PackedVector2Array([pts[idx[i]], pts[idx[i + 1]], pts[idx[i + 2]]]))
			i += 3
	return out


## Depth of `p` below the top of the solid run of `poly` it sits in.
static func _depth(poly: PackedVector2Array, p: Vector2) -> float:
	var n := poly.size()
	for dx in [0.0, 0.6, -0.6]:
		var x: float = p.x + dx
		var ys: Array = []
		for i in n:
			var a: Vector2 = poly[i]
			var b: Vector2 = poly[(i + 1) % n]
			if (a.x <= x and b.x > x) or (b.x <= x and a.x > x):
				ys.append(lerpf(a.y, b.y, (x - a.x) / (b.x - a.x)))
		ys.sort()
		var k := 0
		while k + 1 < ys.size():
			if p.y >= float(ys[k]) - 0.6 and p.y <= float(ys[k + 1]) + 0.6:
				return maxf(0.0, p.y - float(ys[k]))
			k += 2
	return 0.0


static func _jitter(p: Vector2) -> float:
	var h := hash(Vector2i(int(floor(p.x / 48.0)), int(floor(p.y / 48.0))))
	return float(posmod(h, 2001)) / 1000.0 - 1.0


## Drawn polys of one outline: clipped to the CELL grid, coloured per vertex.
static func _cells(outline: PackedVector2Array, theme: String, col: int, tint: String, tex: String, tsz: Vector2) -> Array:
	var out: Array = []
	if outline.size() < 3:
		return out
	var bb := Rect2(outline[0], Vector2.ZERO)
	for v in outline:
		bb = bb.expand(v)
	var depth_cache := {}
	var cx0 := int(floor(bb.position.x / CELL))
	var cx1 := int(floor((bb.end.x - 0.001) / CELL))
	var cy0 := int(floor(bb.position.y / CELL))
	var cy1 := int(floor((bb.end.y - 0.001) / CELL))
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			var x0 := float(cx) * CELL
			var y0 := float(cy) * CELL
			var cell := PackedVector2Array([Vector2(x0, y0), Vector2(x0 + CELL, y0), Vector2(x0 + CELL, y0 + CELL), Vector2(x0, y0 + CELL)])
			for part in Geometry2D.intersect_polygons(outline, cell):
				if _area(part) <= 0.5:
					continue   # hole / sliver
				var pts := _snap_pts(part)
				if pts.size() < 3:
					continue
				var vc := PackedColorArray()
				var uv := PackedVector2Array()
				for p in pts:
					var key := Vector2i(roundi(p.x * 10.0), roundi(p.y * 10.0))
					var d: float
					if depth_cache.has(key):
						d = depth_cache[key]
					else:
						d = _depth(outline, p)
						depth_cache[key] = d
					var c: Color
					if tint == "":
						c = Themes.depth_color(theme, d, _jitter(p))
					else:
						c = Pieces.tint_color(theme, tint, d)
					vc.append(c)
					uv.append(Vector2(snappedf(p.x / tsz.x, 0.0001), snappedf(p.y / tsz.y, 0.0001)))
				out.append({"points": pts, "uvs": uv, "vc": vc, "col": col, "texture": tex})
	return out


## Top of the terrain at column x (INF = none above the kill line).
static func _surface_at(solids: Array, x: float, limit: float) -> float:
	var y := 8.0
	while y < limit:
		if _in_solid(solids, Vector2(x, y)):
			var top := y - 6.0
			while top < y - 0.5:   # refine to ~1 px
				var mid := (top + y) * 0.5
				if _in_solid(solids, Vector2(x, mid)):
					y = mid
				else:
					top = mid
			return y
		y += 6.0
	return INF


## A point standing on the terrain near column x (searching outward).
static func _surface_near(solids: Array, x: float, w: float, limit: float) -> Vector2:
	var step := 40.0
	var d := 0.0
	while d < w:
		for sx in [x + d, x - d]:
			if sx > 40.0 and sx < w - 40.0:
				var y := _surface_at(solids, sx, limit)
				if y != INF and not _in_solid(solids, Vector2(sx, y - 30.0)):
					return Vector2(sx, y - 4.0)
		d += step
	return Vector2.INF


static func _auto_objectives(out: Dictionary) -> Array:
	var w: Dictionary = out["world"]
	var W := float(w["w"])
	var limit := minf(float(w.get("kill_y", w.get("ground_y", 1900.0))), float(w.get("ground_y", 1900.0)))
	var solids := _solids(out)
	var auto: Array = []
	for pair in [["inf_flag", 0.5], ["htf_flag", 0.5], ["rambo_pos", 0.5]]:
		if not out.has(pair[0]):
			var p := _surface_near(solids, W * float(pair[1]), W, limit)
			if p != Vector2.INF:
				out[pair[0]] = p
				auto.append(pair[0])
	if (out.get("ctf_flags", []) as Array).size() < 2:
		var a := _surface_near(solids, W * 0.08, W, limit)
		var b := _surface_near(solids, W * 0.92, W, limit)
		if a != Vector2.INF and b != Vector2.INF and absf(a.x - b.x) > W * 0.3:
			out["ctf_flags"] = [a, b]
			auto.append("ctf_flags")
	if (out.get("dom_points", []) as Array).is_empty():
		var pts: Array = []
		for f in [0.2, 0.5, 0.8]:
			var q := _surface_near(solids, W * f, W, limit)
			if q != Vector2.INF:
				pts.append(q + Vector2(0, -28.0))   # capture area centre ~30 px up
		if pts.size() == 3:
			out["dom_points"] = pts
			auto.append("dom_points")
	return auto


# ── New maps ─────────────────────────────────────────────────────────────────

## A small, playable starting map (Mario-Maker style: some ground to start on).
static func starter_map(theme: String = "grassland") -> Dictionary:
	var m := {"name": "My map", "platforms": [], "ladders": [], "bot_spawns": [],
		"player_spawn": Vector2(560, 1500)}
	var mk := {"v": VERSION, "theme": theme, "grid": 20, "w": DEFAULT_W, "h": DEFAULT_H, "bottom": "void", "pieces": []}
	var pcs: Array = mk["pieces"]
	pcs.append(make_piece("wide", Vector2(800, 1660), Vector2(1200, 300)))
	pcs.append(make_piece("wide", Vector2(2400, 1700), Vector2(1200, 300)))
	pcs.append(make_piece("wide", Vector2(4000, 1660), Vector2(1200, 300)))
	pcs.append(make_piece("hill", Vector2(2400, 1450), Vector2(640, 200)))
	pcs.append(make_piece("float", Vector2(1640, 1260), Vector2(320, 80)))
	pcs.append(make_piece("float", Vector2(3160, 1260), Vector2(320, 80)))
	pcs.append(make_piece("bridge", Vector2(1600, 1528), Vector2(400, 16)))
	pcs.append(make_piece("bridge", Vector2(3200, 1528), Vector2(400, 16)))
	m["maker"] = mk
	m["team_spawns"] = {1: [Vector2(420, 1500), Vector2(700, 1500)], 2: [Vector2(4100, 1500), Vector2(4380, 1500)]}
	m["ctf_flags"] = [Vector2(300, 1500), Vector2(4500, 1500)]
	m["weapon_pickups"] = [{"pos": Vector2(2400, 1300), "weapon": "Barrett"}]
	return m


# ── Validation ───────────────────────────────────────────────────────────────

static func _tr(s: String) -> String:
	return TranslationServer.translate(s)


static func _solids(m: Dictionary) -> Array:
	var out: Array = []
	var coll: Array = m.get("collision", []) if typeof(m.get("collision", [])) == TYPE_ARRAY else []
	if not coll.is_empty():
		for c in coll:
			if int(c.get("col", 0)) == 0 or int(c.get("col", 0)) == 2:
				out.append(c["points"])
	else:
		for p in m.get("polys", []):
			if int(p.get("col", 0)) == 0 or int(p.get("col", 0)) == 2:
				out.append(p.get("points", PackedVector2Array()))
	for pl in m.get("platforms", []):
		var c: Vector2 = pl.get("p", Vector2.ZERO)
		var h: Vector2 = (pl.get("s", Vector2.ZERO) as Vector2) * 0.5
		out.append(PackedVector2Array([c - h, Vector2(c.x + h.x, c.y - h.y), c + h, Vector2(c.x - h.x, c.y + h.y)]))
	return out


static func _in_solid(solids: Array, p: Vector2) -> bool:
	for s in solids:
		var pts: PackedVector2Array = s
		if pts.size() >= 3 and Geometry2D.is_point_in_polygon(p, pts):
			return true
	return false


static func _ground_below(solids: Array, p: Vector2, limit: float) -> bool:
	var y := p.y
	while y < limit:
		if _in_solid(solids, Vector2(p.x, y)):
			return true
		y += 8.0
	return false


## Every placed entity: [label, position, "feet" | "center"].
static func entities(m: Dictionary) -> Array:
	var out: Array = []
	out.append([_tr("Player start"), m.get("player_spawn", Vector2.ZERO)])
	var mk: Dictionary = m.get("maker", {}) if typeof(m.get("maker", {})) == TYPE_DICTIONARY else {}
	if not bool(mk.get("ffa_fill", false)):
		for v in m.get("bot_spawns", []):
			out.append([_tr("FFA spawn"), v])
	var ts: Variant = m.get("team_spawns", {})
	if typeof(ts) == TYPE_DICTIONARY:
		for v in (ts as Dictionary).get(1, []):
			out.append([_tr("Blue spawn"), v])
		for v in (ts as Dictionary).get(2, []):
			out.append([_tr("Red spawn"), v])
	var auto: Array = mk.get("auto", [])
	var fl: Array = m.get("ctf_flags", []) if not auto.has("ctf_flags") else []
	for i in fl.size():
		out.append([_tr("Blue flag") if i == 0 else _tr("Red flag"), fl[i]])
	for pair in [["inf_flag", "INF flag"], ["htf_flag", "HTF flag"], ["rambo_pos", "Rambo bow"]]:
		if m.has(pair[0]) and not auto.has(pair[0]):
			out.append([_tr(pair[1]), m[pair[0]]])
	for pair in [["dom_points", "DOM point"], ["point_spawns", "Point"], ["bonus_spawns", "Bonus box"], ["medkits", "Medikit"],
			["grenade_kits", "Grenade kit"], ["vehicle_spawns", "Buggy"], ["tank_spawns", "Tank"], ["heli_spawns", "Heli pad"], ["plane_spawns", "Plane"], ["m2_mounts", "M2 gun"]]:
		if auto.has(pair[0]):
			continue
		for v in m.get(pair[0], []):
			out.append([_tr(pair[1]), v])
	for wp in m.get("weapon_pickups", []):
		out.append([_tr("%s pickup") % str(wp.get("weapon", "?")), wp.get("pos", Vector2.ZERO)])
	return out


## Friendly checks before PLAY / SAVE on the COMPILED map. Returns
## [{lvl: "error" | "warn", msg, at: Vector2}] — errors block.
static func validate(m: Dictionary, mode: int) -> Array:
	var probs: Array = []
	var w: Dictionary = m.get("world", {}) if typeof(m.get("world", {})) == TYPE_DICTIONARY else {}
	var W := float(w.get("w", DEFAULT_W))
	var H := float(w.get("h", DEFAULT_H))
	var floor_on := bool(w.get("floor_visible", true))
	var ground_y := float(w.get("ground_y", H - 100.0))
	var kill_y := float(w.get("kill_y", INF))
	var solids := _solids(m)
	var maker := is_maker(m)
	var mk: Dictionary = m["maker"] if maker else {}
	var real_solid := 0
	for c in m.get("collision", []):
		if int(c.get("col", 0)) != 1:
			real_solid += 1
	for pl in m.get("platforms", []):
		if not (pl.get("p") == ANCHOR_POS and pl.get("s") == ANCHOR_SIZE):
			real_solid += 1
	if real_solid == 0 and (m.get("polys", []) as Array).is_empty() and not floor_on:
		probs.append({"lvl": "error", "msg": _tr("There's nothing to stand on yet — drag some Ground in from the Terrain tab."), "at": Vector2(W * 0.5, H * 0.6)})
	var zones: Array = m.get("hazards", [])
	for e in entities(m):
		var label: String = e[0]
		var p: Vector2 = e[1]
		if p.x < 20.0 or p.x > W - 20.0 or p.y < 0.0 or p.y > H:
			probs.append({"lvl": "error", "msg": _tr("%s is outside the map — drag it back in.") % label, "at": p})
			continue
		if _in_solid(solids, p + Vector2(0, -6)) or _in_solid(solids, p + Vector2(0, -18)) or (floor_on and p.y > ground_y + 2.0):
			probs.append({"lvl": "error", "msg": _tr("%s is buried in the terrain — drag it up into open air.") % label, "at": p})
			continue
		var bad_zone := false
		for z in zones:
			if (z["rect"] as Rect2).grow(6.0).has_point(p + Vector2(0, -4)):
				bad_zone = true
		if bad_zone:
			probs.append({"lvl": "error", "msg": _tr("%s sits in spikes or lava.") % label, "at": p})
			continue
		if kill_y != INF and not _ground_below(solids, p, kill_y):
			probs.append({"lvl": "warn", "msg": _tr("%s is over a bottomless pit.") % label, "at": p})
	if maker:
		for p in mk.get("pieces", []):
			var r := piece_rect(p)
			if not Rect2(0, 0, W, H).intersects(r):
				probs.append({"lvl": "error", "msg": _tr("A %s is completely outside the map.") % _tr(str(Pieces.def(str(p.get("t", ""))).get("label", "piece"))), "at": r.get_center()})
			elif not Rect2(-1, -1, W + 2, H + 2).encloses(r):
				probs.append({"lvl": "warn", "msg": _tr("Part of a %s sticks out of the map.") % _tr(str(Pieces.def(str(p.get("t", ""))).get("label", "piece"))), "at": r.get_center()})
	var ts: Variant = m.get("team_spawns", {})
	var blue: Array = (ts as Dictionary).get(1, []) if typeof(ts) == TYPE_DICTIONARY else []
	var red: Array = (ts as Dictionary).get(2, []) if typeof(ts) == TYPE_DICTIONARY else []
	var flags: Array = m.get("ctf_flags", [])
	if mode in TEAM_MODES:
		var lvl := "error" if maker else "warn"
		if blue.is_empty():
			probs.append({"lvl": lvl, "msg": _tr("The Blue team needs a spawn — drag a Blue spawn in from Objectives."), "at": flags[0] if flags.size() > 0 else Vector2(W * 0.2, H * 0.5)})
		if red.is_empty():
			probs.append({"lvl": lvl, "msg": _tr("The Red team needs a spawn — drag a Red spawn in from Objectives."), "at": flags[1] if flags.size() > 1 else Vector2(W * 0.8, H * 0.5)})
	var auto: Array = mk.get("auto", [])
	if mode == MODE_CTF and (flags.size() < 2 or auto.has("ctf_flags")):
		probs.append({"lvl": "error", "msg": _tr("Capture the Flag needs a Blue flag and a Red flag (Objectives)."), "at": Vector2(W * 0.5, H * 0.5)})
	elif mode == MODE_INF and (not m.has("inf_flag") or auto.has("inf_flag")):
		probs.append({"lvl": "warn", "msg": _tr("No Infiltration flag placed — one goes on the terrain in the middle."), "at": Vector2(W * 0.5, H * 0.5)})
	elif mode == MODE_HTF and (not m.has("htf_flag") or auto.has("htf_flag")):
		probs.append({"lvl": "warn", "msg": _tr("No Hold the Flag flag placed — one goes on the terrain in the middle."), "at": Vector2(W * 0.5, H * 0.5)})
	elif mode == MODE_RM and (not m.has("rambo_pos") or auto.has("rambo_pos")):
		probs.append({"lvl": "warn", "msg": _tr("No Rambo bow placed — one goes on the terrain in the middle."), "at": Vector2(W * 0.5, H * 0.5)})
	elif mode == MODE_DOM and ((m.get("dom_points", []) as Array).is_empty() or auto.has("dom_points")):
		probs.append({"lvl": "warn", "msg": _tr("No DOM points placed — three go on the terrain, left, middle and right."), "at": Vector2(W * 0.5, H * 0.5)})
	if mode == MODE_BOMB:
		probs.append_array(_validate_sites(m, solids, zones, W, H, floor_on, ground_y))
	var ffa := (m.get("bot_spawns", []) as Array).size() + 1
	if not (mode in TEAM_MODES) and ffa < 2:
		probs.append({"lvl": "warn", "msg": _tr("Only one spawn point — add a few so players don't all appear in one spot."), "at": m.get("player_spawn", Vector2.ZERO)})
	return probs


## Bomb Defusal (#304): both sites placed, inside the map, with ground to stand
## on inside them, out of spikes / lava, apart from each other.
static func _validate_sites(m: Dictionary, solids: Array, zones: Array, W: float, H: float, floor_on: bool, ground_y: float) -> Array:
	var probs: Array = []
	var by_name := {}
	for b in m.get("bomb_sites", []):
		if typeof(b) == TYPE_DICTIONARY and b.get("rect") is Rect2:
			by_name[str(b.get("name", "A"))] = b["rect"]
	for nm in ["A", "B"]:
		if not by_name.has(nm):
			probs.append({"lvl": "error", "msg": _tr("Bomb Defusal needs Bomb site %s (Objectives).") % nm, "at": Vector2(W * (0.35 if nm == "A" else 0.65), H * 0.5)})
			continue
		var r: Rect2 = by_name[nm]
		if not Rect2(0, 0, W, H).encloses(r):
			probs.append({"lvl": "error", "msg": _tr("Bomb site %s sticks out of the map.") % nm, "at": r.get_center()})
			continue
		var stand := 0
		var x := r.position.x + 10.0
		while x < r.end.x - 9.0:
			var y := r.position.y + 2.0
			while y < r.end.y + 10.0:
				var solid_here: bool = _in_solid(solids, Vector2(x, y)) or (floor_on and y >= ground_y)
				if solid_here:
					var clear := true
					for up in [6.0, 18.0, 30.0]:
						if _in_solid(solids, Vector2(x, y - up)):
							clear = false
					if clear and y > r.position.y + 30.0:
						var in_zone := false
						for z in zones:
							if (z["rect"] as Rect2).grow(6.0).has_point(Vector2(x, y - 4.0)):
								in_zone = true
						if not in_zone:
							stand += 1
					break
				y += 4.0
			x += 20.0
		if stand < 2:
			probs.append({"lvl": "error", "msg": _tr("Bomb site %s has no ground to stand on inside it — stretch it down over a floor.") % nm, "at": r.get_center()})
	if by_name.has("A") and by_name.has("B") and (by_name["A"] as Rect2).intersects(by_name["B"]):
		probs.append({"lvl": "warn", "msg": _tr("Bomb sites A and B overlap — put them in different places."), "at": (by_name["B"] as Rect2).get_center()})
	return probs


static func has_errors(probs: Array) -> bool:
	for p in probs:
		if str(p.get("lvl", "")) == "error":
			return true
	return false
