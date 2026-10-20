extends RefCounted
## Runtime bot navigation builder (#287): the in-game port of
## tools/build_nav.py, for maps that ship without a baked graph (editor /
## Maker / shared / custom maps). Pure data — it reads only the map dict and
## returns {"nodes", "edges", "air"} in the baked JSON's format, so it can run
## on a WorkerThreadPool thread while the match starts; NavGraph.adopt() then
## loads it on the main thread. Works headless (dedicated servers host bots).
##
## Steps (same as the bake): rasterise the player-solid geometry; where does a
## standing 14x24 soldier fit (summed-area table); ground = fits here but not
## one cell lower; walkable = not steeper than ~45 deg; nodes every ~40 px on
## every surface + every ledge lip; links when a soldier's body clears the
## straight line and the move is a walk / hop / jet / drop the game allows,
## without a long stretch over a bottomless pit; ledge detours (step out past
## a platform's lip, jet up beside it); bridges for objective legs the link
## graph can't do (Dial's shortest path over the free-space raster); keep every
## island of a useful size.

const R := 4.0                 # world px per raster cell (the bake uses 2; 4 is ~4x cheaper)
const DEFAULT_W := 4800.0
const DEFAULT_H := 2000.0
const DEFAULT_GROUND := 1900.0
const STAND_W := 14.0
const STAND_H := 24.0
const PLAYER_SOLID_COLS := [0, 2]
const NODE_STEP := 40.0
const LINK_DX := 230.0
const LINK_UP := 420.0
const LINK_DOWN := 1300.0
const LINK_DX_JET := 440.0
const LINK_DY_JET := 220.0
const LINK_UP_V := 560.0
const DETOUR_MAX := 240.0
const MIN_COMP := 12
const LIFT := 6.0
const VOID_MAX := 56.0
const BRIDGE_MAX_RISE := 790.0   # bake: 740 at 2 px cells; the coarser raster measures climbs a little longer
const BRIDGE_STEP := 6          # coarse cells between bridge waypoints (coarse = 2 cells = 8 px)
const BRIDGE_BUDGET := 600000   # Dijkstra pops per leg
const HAZARD_PAD_X := 20.0     # hazard kill box margin (match_hazards tests feet +-6 px; + path-follow slop)
const HAZARD_PAD_TOP := 20.0   # air waypoints stay this far over a hazard
# Maker jump pads (#286, runtime builder only): a bot walking onto a pad is
# launched (match_hazards: feet within PAD_HALF_W 28 px of its centre) about
# this far from the centre, at full run speed toward it.
const PAD_ENTRY := 24.0
const PAD_SIM_DT := 1.0 / 60.0  # the bots' physics tick
const PAD_SIM_T := 4.0          # longest ride simulated
const PAD_MIN_RISE := 60.0      # landings at least this far above the pad (lower ones are a walk / drop)
const PAD_LAND_DX := 48.0       # the simulated landing must be this close to the node...
const PAD_LAND_DY := 12.0       # ...and on its surface

# Bot physics for the launch arc — bot.gd BASE_GRAVITY / RUN_SPEED / the
# 1300 px/s^2 run (and air) acceleration / MAX_FALL; main sets them scaled by
# the match's gravity / speed modifiers before the build.
var pad_gravity := 1700.0
var pad_run := 235.0
var pad_accel := 1300.0
var pad_max_fall := 1200.0

var nx := 0
var ny := 0
var W := DEFAULT_W
var H := DEFAULT_H
var G := DEFAULT_GROUND
var K := INF                    # kill line (world y), INF = none
var solid := PackedByteArray()
var stand := PackedByteArray()
var ground := PackedByteArray()
var col_ground: Array = []      # per column: PackedInt32Array of ground rows (sorted)
var stats := {}
var _pad_links: Array = []      # Vector3i(pad node, landing node, steer mode)


## Build the graph for map `m`. Returns {} when the map has no walkable space.
static func build(m: Dictionary) -> Dictionary:
	var b = load("res://scripts/nav_builder.gd").new()
	return b._build(m)


func _build(m: Dictionary) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	_world(m)
	_raster(m)
	_fits()
	_ground_cells()
	_apply_hazards(m)
	var walk := _walkable()
	var nodes := _sample_nodes(walk)
	if OS.get_environment("NAV_DEBUG") != "":
		var cs := 0
		var cst := 0
		var cg := 0
		var cw := 0
		for i in nx * ny:
			cs += solid[i]
			cst += stand[i]
			cg += ground[i]
			cw += walk[i]
		print("NAVDBG %dx%d W=%.0f H=%.0f G=%.0f K=%s solid=%d stand=%d ground=%d walk=%d nodes=%d" % [nx, ny, W, H, G, str(K), cs, cst, cg, cw, nodes.size()])
	if nodes.is_empty():
		return {}
	var pts := _dedupe(nodes)
	var res := _link(pts)
	var pts_l: Array = res[0]
	var edges: Array = res[1]
	_add_pad_links(m, pts, pts_l, edges)
	var nb := _bridges(m, pts_l, edges)
	var out := _components(pts_l, edges)
	stats = {"ms": Time.get_ticks_msec() - t0, "nodes": out["nodes"].size() / 2, "edges": out["edges"].size() / 2,
		"bridges": nb, "cells": nx * ny}
	if out.has("pads"):
		stats["pads"] = (out["pads"] as Array).size() / 3
	out["stats"] = stats
	return out


# ── world + raster ──────────────────────────────────────────────────────────

## Map dicts hold points as [x, y] (JSON) or Vector2 (built-in / loaded maps).
static func _v2(v: Variant) -> Vector2:
	if v is Vector2:
		return v
	if v is Vector2i:
		return Vector2(v)
	if (v is Array or v is PackedFloat32Array or v is PackedFloat64Array) and v.size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2.INF


## Polygon points as a flat float list, whatever shape they're stored in.
static func _flat(v: Variant) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if v is PackedVector2Array:
		for q in v:
			out.append(q.x)
			out.append(q.y)
	elif v is Array or v is PackedFloat32Array or v is PackedFloat64Array:
		for q in v:
			if q is Vector2:
				out.append(q.x)
				out.append(q.y)
			else:
				out.append(float(q))
	return out


func _world(m: Dictionary) -> void:
	var w: Dictionary = m.get("world", {}) if m.get("world") is Dictionary else {}
	W = float(w.get("w", DEFAULT_W))
	H = float(w.get("h", DEFAULT_H))
	G = float(w.get("ground_y", DEFAULT_GROUND))
	K = float(w["kill_y"]) if w.get("kill_y") != null else INF
	nx = int(W / R) + 1
	ny = int(H / R) + 1


func _raster(m: Dictionary) -> void:
	solid = PackedByteArray()
	solid.resize(nx * ny)
	var list: Array = m.get("collision", m.get("polys", []))
	for p in list:
		if not (p is Dictionary) or not (int(p.get("col", 0)) in PLAYER_SOLID_COLS):
			continue
		var pts := _flat(p.get("points", []))
		if pts.size() < 6:
			continue
		_fill_poly(pts)
	for pl in m.get("platforms", []):
		if not (pl is Dictionary):
			continue
		var pp := _v2(pl.get("p", Vector2.ZERO))
		var ss := _v2(pl.get("s", Vector2.ZERO))
		if not pp.is_finite() or not ss.is_finite():
			continue
		_fill_rect(pp.x - ss.x * 0.5, pp.y - ss.y * 0.5, pp.x + ss.x * 0.5, pp.y + ss.y * 0.5)
	# Maker hazards: solid for clearance (never ground — _apply_hazards).
	for r: Rect2 in _hazard_rects(m):
		_fill_rect(r.position.x - HAZARD_PAD_X, r.position.y - HAZARD_PAD_TOP, r.end.x + HAZARD_PAD_X, r.end.y)
	# Baseline floor (top edge at ground_y) and the side walls (main.gd).
	_fill_rect(0.0, G, W + R, H + R)
	_fill_rect(-R, -R, 20.0, H + R)
	_fill_rect(W - 20.0, -R, W + R, H + R)


func _fill_rect(x0: float, y0: float, x1: float, y1: float) -> void:
	var cx0 := clampi(int(ceil(x0 / R)), 0, nx)
	var cx1 := clampi(int(ceil(x1 / R)), 0, nx)
	var cy0 := clampi(int(ceil(y0 / R)), 0, ny)
	var cy1 := clampi(int(ceil(y1 / R)), 0, ny)
	for y in range(cy0, cy1):
		var o := y * nx
		for x in range(cx0, cx1):
			solid[o + x] = 1


## Scanline fill (even-odd) at cell centres — any simple polygon.
func _fill_poly(pts: PackedFloat32Array) -> void:
	var n := pts.size() / 2
	var xs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	xs.resize(n)
	ys.resize(n)
	var miny := INF
	var maxy := -INF
	for i in n:
		xs[i] = float(pts[i * 2]) / R
		ys[i] = float(pts[i * 2 + 1]) / R
		miny = minf(miny, ys[i])
		maxy = maxf(maxy, ys[i])
	var y0 := clampi(int(floor(miny)), 0, ny - 1)
	var y1 := clampi(int(ceil(maxy)), 0, ny - 1)
	var cross := PackedFloat32Array()
	for y in range(y0, y1 + 1):
		var yc := float(y) + 0.5
		cross.clear()
		var j := n - 1
		for i in n:
			var ya := ys[j]
			var yb := ys[i]
			if (ya <= yc and yb > yc) or (yb <= yc and ya > yc):
				cross.append(xs[j] + (yc - ya) / (yb - ya) * (xs[i] - xs[j]))
			j = i
		if cross.size() < 2:
			continue
		cross.sort()
		var o := y * nx
		var k := 0
		while k + 1 < cross.size():
			var a := clampi(int(ceil(cross[k] - 0.5)), 0, nx)
			var b := clampi(int(floor(cross[k + 1] - 0.5)) + 1, 0, nx)
			for x in range(a, b):
				solid[o + x] = 1
			k += 2


## stand[y, x]: a standing soldier's box (feet-anchored at the cell) is clear.
func _fits() -> void:
	var sw := nx + 1
	var ii := PackedInt32Array()
	ii.resize((ny + 1) * sw)
	for y in ny:
		var run := 0
		var o := y * nx
		var r0 := y * sw
		var r1 := (y + 1) * sw
		for x in nx:
			run += solid[o + x]
			ii[r1 + x + 1] = ii[r0 + x + 1] + run
	var hw := int(ceil(STAND_W * 0.5 / R))
	var hh := int(ceil(STAND_H / R))
	var ky := int(K / R) if K != INF else ny
	stand = PackedByteArray()
	stand.resize(nx * ny)
	for y in range(hh, mini(ny, ky)):
		var ya := (y - hh) * sw
		var yb := y * sw
		var o := y * nx
		for x in nx:
			var x1 := maxi(0, x - hw)
			var x2 := mini(nx, x + hw)
			var s := ii[yb + x2] - ii[ya + x2] - ii[yb + x1] + ii[ya + x1]
			if s == 0:
				stand[o + x] = 1


func _ground_cells() -> void:
	ground = PackedByteArray()
	ground.resize(nx * ny)
	var ky := int(K / R) - 1 if K != INF else ny
	col_ground.resize(nx)
	for x in nx:
		var rows := PackedInt32Array()
		for y in range(0, mini(ny, ky)):
			var i := y * nx + x
			if stand[i] == 1 and (y + 1 >= ny or stand[i + nx] == 0):
				ground[i] = 1
				rows.append(y)
		col_ground[x] = rows


## Maker hazards (#286) as world rects ("hazards": [{kind, rect, dir}], the
## rect a Rect2 in-game or [x, y, w, h] in JSON).
func _hazard_rects(m: Dictionary) -> Array:
	var out: Array = []
	var list: Variant = m.get("hazards", [])
	if not (list is Array):
		return out
	for h in list:
		if not (h is Dictionary):
			continue
		var rv: Variant = h.get("rect")
		if rv is Rect2:
			out.append(rv)
		elif (rv is Array or rv is PackedFloat32Array) and rv.size() >= 4:
			out.append(Rect2(float(rv[0]), float(rv[1]), float(rv[2]), float(rv[3])))
	return out


## Spikes / lava are not ground: no nodes on (or just above) them. They are
## rastered as solid too (_raster), so a link or an air bridge can't pass
## through one — bots path over them with a jump / jet and never through.
## The kill test (match_hazards) checks the feet a few px inside the rect and
## +-6 px either side, hence the margins.
func _apply_hazards(m: Dictionary) -> void:
	for r: Rect2 in _hazard_rects(m):
		var x0 := clampi(int(floor((r.position.x - HAZARD_PAD_X) / R)), 0, nx - 1)
		var x1 := clampi(int(ceil((r.end.x + HAZARD_PAD_X) / R)), 0, nx - 1)
		var y0 := int(floor((r.position.y - STAND_H) / R))
		var y1 := int(ceil((r.end.y + 8.0) / R))
		for x in range(x0, x1 + 1):
			var rows: PackedInt32Array = col_ground[x]
			var keep := PackedInt32Array()
			for y in rows:
				if y >= y0 and y <= y1:
					ground[y * nx + x] = 0
				else:
					keep.append(y)
			col_ground[x] = keep


## Vertical dilation of `g` by `r` cells each way (any ground within +-r rows).
func _vdilate(g: PackedByteArray, r: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(nx * ny)
	for x in nx:
		var rows: PackedInt32Array = col_ground[x]
		for yy in rows:
			if g[yy * nx + x] == 0:
				continue
			for y in range(maxi(0, yy - r), mini(ny, yy + r + 1)):
				out[y * nx + x] = 1
	return out


func _walkable() -> PackedByteArray:
	# Walkable only: slopes steeper than ~45 deg aren't standable; keep a cell
	# with ground within +-4 rows 4 cells to both sides, or a ledge lip on flat
	# ground (one side open air) — build_nav.py's rule at this resolution.
	var k := maxi(1, int(round(8.0 / R)))
	var gv := _vdilate(ground, int(round(8.0 / R)))
	var gv2 := _vdilate(ground, int(round(2.0 / R)) if R < 4.0 else 1)
	var walk := PackedByteArray()
	walk.resize(nx * ny)
	for x in nx:
		var rows: PackedInt32Array = col_ground[x]
		for y in rows:
			var o := y * nx
			var l := x - k >= 0 and gv[o + x - k] == 1
			var r := x + k < nx and gv[o + x + k] == 1
			var l2 := x - k >= 0 and gv2[o + x - k] == 1
			var r2 := x + k < nx and gv2[o + x + k] == 1
			if (l and r) or (l2 and not r) or (r2 and not l):
				walk[o + x] = 1
	return walk


# ── nodes ───────────────────────────────────────────────────────────────────

func _sample_nodes(walk: PackedByteArray) -> Array:
	var nodes: Array = []
	var step := int(NODE_STEP / R)
	var same := maxi(2, int(12.0 / R))
	for cx in range(0, nx, step):
		var last := -999
		for cy in (col_ground[cx] as PackedInt32Array):
			if walk[cy * nx + cx] == 0:
				continue
			if cy - last < same:
				continue
			last = cy
			nodes.append(Vector2i(cx, cy))
	# Surface ends (ledge lips / wall feet): a walkable cell with no walkable
	# ground within +-5 rows in the column to its left or right.
	var r5 := maxi(1, int(round(10.0 / R)))
	var wv := _vdilate(walk, r5)
	var have := {}
	var cell := maxi(1, int(16.0 / R))
	for v in nodes:
		have[Vector2i(v.x / cell, v.y / cell)] = true
	for x in nx:
		for y in (col_ground[x] as PackedInt32Array):
			var o := y * nx
			if walk[o + x] == 0:
				continue
			var lh := x - 1 >= 0 and wv[o + x - 1] == 1
			var rh := x + 1 < nx and wv[o + x + 1] == 1
			if lh and rh:
				continue
			var key := Vector2i(x / cell, y / cell)
			if have.has(key):
				continue
			have[key] = true
			nodes.append(Vector2i(x, y))
	return nodes


func _dedupe(nodes: Array) -> Array:
	var seen := {}
	var pts: Array = []
	for v in nodes:
		var p := Vector2(v.x * R, v.y * R)
		var k := Vector2i(int(p.x / 16.0), int(p.y / 16.0))
		if seen.has(k):
			continue
		seen[k] = true
		pts.append(p)
	return pts


# ── links ───────────────────────────────────────────────────────────────────

func _stand_at(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < nx and y < ny and stand[y * nx + x] == 1


func _clear(a: Vector2, b: Vector2) -> bool:
	var length := maxf(absf(b.x - a.x), absf(b.y - a.y))
	var steps := maxi(2, int(length / (R * 2.0)))
	if steps <= 2:
		return true
	var lift := int(LIFT / R)
	if lift < 1:
		lift = 1
	for lf: int in [lift, lift * 2, lift * 3]:
		var ok := true
		for s in range(1, steps - 1):
			var t := float(s) / float(steps - 1)
			var x := int(round((a.x + (b.x - a.x) * t) / R))
			var y := int(round((a.y + (b.y - a.y) * t) / R)) - lf
			if not _stand_at(x, y):
				ok = false
				break
		if ok:
			return true
	return false


## #297: a standing soldier fits all the way straight up from `p` to height
## `top_y` (nothing overhead to start a climb under).
func _rise_clear(p: Vector2, top_y: float) -> bool:
	var cx := int(round(p.x / R))
	for y in range(int(round(p.y / R)), int(round(top_y / R)) - 1, -1):
		if not _stand_at(cx, y):
			return false
	return true


func _has_floor_below(x: float, y: float) -> bool:
	var cx := int(round(x / R))
	if cx < 0 or cx >= nx:
		return false
	var rows: PackedInt32Array = col_ground[cx]
	var ky := int(K / R) if K != INF else ny
	var i := rows.bsearch(int(y / R), false)
	return i < rows.size() and rows[i] < ky


func _void_span(a: Vector2, b: Vector2) -> float:
	var n := maxi(2, int(absf(b.x - a.x) / 8.0))
	var run := 0.0
	var best := 0.0
	var seg := absf(b.x - a.x) / float(n)
	for s in n:
		var t := float(s) / float(n - 1)
		if _has_floor_below(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t - 4.0):
			run = 0.0
		else:
			run += seg
			best = maxf(best, run)
	return best


func _link(pts: Array) -> Array:
	var bucket := {}
	for i in pts.size():
		var bx := int((pts[i] as Vector2).x / LINK_DX_JET)
		if not bucket.has(bx):
			bucket[bx] = []
		(bucket[bx] as Array).append(i)
	var edges: Array = []
	var climb: Array = []
	for i in pts.size():
		var p: Vector2 = pts[i]
		var bx := int(p.x / LINK_DX_JET)
		for b: int in [bx - 1, bx, bx + 1]:
			if not bucket.has(b):
				continue
			for j: int in bucket[b]:
				if j == i:
					continue
				var q: Vector2 = pts[j]
				var dx := absf(q.x - p.x)
				var dy := q.y - p.y
				if dy > LINK_DOWN:
					continue
				if dy < -LINK_UP and (dy < -LINK_UP_V or dx > 120.0):
					continue
				if dx > LINK_DX and (dx > LINK_DX_JET or absf(dy) > LINK_DY_JET):
					continue
				if dx < 1.0 and absf(dy) < 1.0:
					continue
				if absf(dy) < 20.0 and dx > NODE_STEP * 1.6:
					continue
				if _clear(p, q) and _void_span(p, q) <= VOID_MAX:
					edges.append(Vector2i(i, j))
				elif dy < -40.0 and dx <= LINK_DX:
					climb.append(Vector2i(i, j))
	# Ledge detours: step out past the platform's lip, jet up beside it.
	var have := {}
	for e in edges:
		have[e] = true
	var pts_l: Array = pts.duplicate()
	var air := {}
	var steps := {}
	var per_src := {}
	for e in climb:
		var i: int = e.x
		var j: int = e.y
		if have.has(e) or int(per_src.get(i, 0)) >= 2:
			continue
		var p: Vector2 = pts_l[i]
		var q: Vector2 = pts_l[j]
		var done := false
		for k in range(40, int(DETOUR_MAX) + 1, 20):
			for sgn: float in [-1.0, 1.0]:
				var xe: float = q.x + sgn * k
				if absf(xe - p.x) > LINK_DX:
					continue
				var a := Vector2(xe, p.y)
				var bb := Vector2(xe, q.y - 24.0)
				if not (_clear(p, a) and _clear(a, bb) and _clear(bb, q)):
					continue
				if _void_span(p, a) > VOID_MAX or _void_span(bb, q) > VOID_MAX:
					continue
				var key := Vector2i(int(bb.x / 16.0), int(bb.y / 16.0))
				var bi: int = int(air.get(key, -1))
				if bi < 0:
					bi = pts_l.size()
					pts_l.append(bb)
					air[key] = bi
				if _clear(p, bb) and _rise_clear(p, bb.y):
					edges.append(Vector2i(i, bi))
				else:
					# #297: p stands UNDER the platform (a slab hanging 300-560 px
					# over walkable ground): the straight line p -> bb runs through
					# its body or along its underside, and a bot follows a link's
					# line (it can't build up the sideways speed under it either)
					# — it jetted into the underside again and again. Route over
					# the step-out point the detour was checked with: walk out
					# to `a`, then jet straight up beside the lip.
					var ak := Vector2i(int(a.x / 16.0), int(a.y / 16.0))
					var ai: int = int(steps.get(ak, -1))
					if ai < 0:
						ai = pts_l.size()
						pts_l.append(a)
						steps[ak] = ai
					edges.append(Vector2i(i, ai))
					edges.append(Vector2i(ai, bi))
				edges.append(Vector2i(bi, j))
				per_src[i] = int(per_src.get(i, 0)) + 1
				done = true
				break
			if done:
				break
	return [pts_l, edges]


# ── jump pads (#286) ────────────────────────────────────────────────────────

## Maker jump pads as {pos: Vector2 (the pad's base, on the ground), power}
## ("jump_pads": pos a Vector2 in-game or [x, y] in JSON).
func _jump_pads(m: Dictionary) -> Array:
	var out: Array = []
	var list: Variant = m.get("jump_pads", [])
	if not (list is Array):
		return out
	for j in list:
		if not (j is Dictionary):
			continue
		var p := _v2(j.get("pos"))
		var pw := float(j.get("power", 1150.0))
		if p.is_finite() and pw > 0.0:
			out.append({"pos": p, "power": pw})
	return out


func _fits_at(x: float, y: float) -> bool:
	return _stand_at(int(round(x / R)), int(round(y / R)))


## Pad links: a node on each pad (reached by walking from the nodes beside
## it) and one-way links pad -> every node the launch can land a bot on. The
## ride is SIMULATED with the bots' own physics on the stand raster: launched
## at PAD_ENTRY px from the centre at full run speed toward it (either side
## it can be walked onto), velocity.y = -power, gravity, the run / air
## acceleration steering at the landing node; walls stop the sideways
## motion, ceilings the rise. Steer mode 0 = steer at once, 1 = rise straight
## until the feet are over the landing's height, then steer (under an
## overhang). Both approach sides must land on the node's surface. No pads
## in the map = nothing changes.
func _add_pad_links(m: Dictionary, pts: Array, pts_l: Array, edges: Array) -> void:
	_pad_links.clear()
	var pads := _jump_pads(m)
	if pads.is_empty():
		return
	var n_ground := pts.size()   # sampled surface nodes (detour waypoints come after)
	for pad: Dictionary in pads:
		var pp: Vector2 = pad["pos"]
		var power: float = pad["power"]
		var cx := int(round(pp.x / R))
		if cx < 0 or cx >= nx:
			continue
		# The trigger wants the feet within [pos.y - 24, pos.y + 6].
		var gy := -1
		for y in (col_ground[cx] as PackedInt32Array):
			var wy := float(y) * R
			if wy >= pp.y - 24.0 and wy <= pp.y + 6.0 and (gy < 0 or absf(wy - pp.y) < absf(float(gy) * R - pp.y)):
				gy = y
		if gy < 0:
			continue
		var pn := Vector2(pp.x, float(gy) * R)
		# Approach sides: standing room on the pad's level PAD_ENTRY px out.
		var starts: Array = []
		for sgn: float in [-1.0, 1.0]:
			var sx := pn.x + sgn * PAD_ENTRY
			for dy: float in [0.0, -R, R]:
				if _fits_at(sx, pn.y + dy) and _clear(Vector2(sx, pn.y + dy), pn):
					starts.append(Vector3(sx, pn.y + dy, -sgn * pad_run))
					break
		if starts.is_empty():
			continue
		var pi := pts_l.size()
		var ins: Array = []
		for j in n_ground:
			var q: Vector2 = pts_l[j]
			if absf(q.x - pn.x) <= NODE_STEP * 2.0 and absf(q.y - pn.y) <= 16.0 and _clear(q, pn):
				ins.append(j)
		if ins.is_empty():
			continue
		pts_l.append(pn)
		for j: int in ins:
			edges.append(Vector2i(j, pi))
		var apex := pn.y - power * power / (2.0 * pad_gravity)
		var reach := pad_run * (2.0 * power / pad_gravity + 0.5)
		for j in n_ground:
			var q: Vector2 = pts_l[j]
			if q.y > pn.y - PAD_MIN_RISE or q.y < apex - 4.0 or absf(q.x - pn.x) > reach:
				continue
			for mode in 2:
				var ok := true
				for st: Vector3 in starts:
					var land := _pad_ride(Vector2(st.x, st.y), st.z, -power, q, mode)
					if not land.is_finite() or absf(land.y - q.y) > PAD_LAND_DY or absf(land.x - q.x) > PAD_LAND_DX \
							or not _clear(land, q):
						ok = false
						break
				if ok:
					edges.append(Vector2i(pi, j))
					_pad_links.append(Vector3i(pi, j, mode))
					break


## One simulated pad ride (feet position, bot physics at 60 Hz) steering at
## `to`. Returns where it lands, or INF (fell past the kill line / too long).
func _pad_ride(p: Vector2, vx: float, vy: float, to: Vector2, mode: int) -> Vector2:
	var dt := PAD_SIM_DT
	var x := p.x
	var y := p.y
	var t := 0.0
	var ky := minf(K, H)
	while t < PAD_SIM_T:
		t += dt
		var dir := 0.0
		if absf(to.x - x) >= 6.0 and not (mode == 1 and vy < 0.0 and y > to.y - 24.0):
			dir = signf(to.x - x)
		vx = move_toward(vx, dir * pad_run, pad_accel * dt)
		vy = minf(vy + pad_gravity * dt, pad_max_fall)
		var mx := vx * dt
		if mx != 0.0:
			if _fits_at(x + mx, y):
				x += mx
			else:
				vx = 0.0
		var my := vy * dt
		var n := maxi(1, int(ceil(absf(my) / 8.0)))
		var stepy := my / float(n)
		for _k in n:
			if _fits_at(x, y + stepy):
				y += stepy
			elif vy > 0.0:
				# Landed: settle onto the ground row below.
				var cxl := int(round(x / R))
				var cyl := int(round(y / R))
				while cyl + 1 < ny and _stand_at(cxl, cyl + 1):
					cyl += 1
				return Vector2(x, float(cyl) * R)
			else:
				vy = 0.0
				break
		if y > ky:
			return Vector2.INF
	return Vector2.INF


# ── bridges ─────────────────────────────────────────────────────────────────

func _landed(v: Variant) -> Vector2:
	var p := _v2(v)
	if not p.is_finite():
		return Vector2.INF
	var x := int(round(p.x / R))
	var y := maxi(0, int(round(p.y / R)))
	if x < 0 or x >= nx or y >= ny or stand[y * nx + x] == 0:
		return p
	while y + 1 < ny and stand[(y + 1) * nx + x] == 1:
		y += 1
	if ground[y * nx + x] == 0:
		return p
	return Vector2(x * R, y * R)


func _nearest(pts_l: Array, p: Vector2) -> int:
	var best := -1
	var bd := 400.0 * 400.0
	for i in pts_l.size():
		var d := (pts_l[i] as Vector2).distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


func _reach(s: int, adj: Dictionary) -> Dictionary:
	var seen := {s: true}
	var st: Array = [s]
	while not st.is_empty():
		var u: int = st.pop_back()
		for v in adj.get(u, []):
			if not seen.has(v):
				seen[v] = true
				st.append(v)
	return seen


func _max_climb(chain: Array) -> float:
	var best := 0.0
	var run := 0.0
	for k in chain.size() - 1:
		var dy: float = (chain[k] as Vector2).y - (chain[k + 1] as Vector2).y
		if dy > 0.0:
			run += dy
			best = maxf(best, run)
		elif dy < -24.0:
			run = 0.0
	return best


func _bridges(m: Dictionary, pts_l: Array, edges: Array) -> int:
	var legs: Array = []
	var ts: Dictionary = m.get("team_spawns", {}) if m.get("team_spawns") is Dictionary else {}
	var fl: Array = m.get("ctf_flags", []) if m.get("ctf_flags") is Array else []
	if fl.size() >= 2:
		var f := {1: _landed(fl[0]), 2: _landed(fl[1])}
		for pair in [[1, 2], [2, 1]]:
			var t: int = pair[0]
			var e: int = pair[1]
			var spl: Array = ts.get(str(t), ts.get(t, []))
			for k in mini(2, spl.size()):
				legs.append([_landed(spl[k]), f[e]])
			legs.append([f[e], f[t]])
	var base: Array = (ts.get("1", ts.get(1, [])) as Array).slice(0, 1) if (ts.get("1", ts.get(1, [])) is Array) else []
	if base.is_empty() and m.get("player_spawn") != null:
		base = [m["player_spawn"]]
	if not base.is_empty():
		var home := _landed(base[0])
		var objs: Array = []
		for k in ["inf_flag", "htf_flag", "rambo_pos"]:
			if m.get(k) != null:
				objs.append(m[k])
		if m.get("dom_points") is Array:
			objs.append_array(m["dom_points"])
		for o in objs:
			var op := _landed(o)
			legs.append([home, op])
			legs.append([op, home])
	if legs.is_empty():
		return 0
	# Coarse free-space grid (2x2 cells) + "has ground somewhere below" mask.
	var F := 2
	var W2 := nx / F
	var H2 := ny / F
	var coarse := PackedByteArray()
	coarse.resize(W2 * H2)
	var safe := PackedByteArray()
	safe.resize(W2 * H2)
	var ky := int(K / R) if K != INF else ny
	for cx in W2:
		# below[y] = some ground at or below y (before the kill line), per column
		var any_below := false
		for cy in range(H2 - 1, -1, -1):
			var all_free := true
			var gb := false
			for dy in F:
				for dx in F:
					var x := cx * F + dx
					var y := cy * F + dy
					if stand[y * nx + x] == 0:
						all_free = false
					if ground[y * nx + x] == 1 and y < ky:
						gb = true
			if gb:
				any_below = true
			coarse[cy * W2 + cx] = 1 if all_free else 0
			safe[cy * W2 + cx] = 1 if any_below else 0
	var CR := R * F
	var added := 0
	for leg in legs:
		var a_pt: Vector2 = leg[0]
		var b_pt: Vector2 = leg[1]
		if not a_pt.is_finite() or not b_pt.is_finite():
			continue
		for _attempt in 3:
			var a := _nearest(pts_l, a_pt)
			var b := _nearest(pts_l, b_pt)
			if a < 0 or b < 0:
				break
			var out := {}
			var inn := {}
			for e in edges:
				if not out.has(e.x):
					out[e.x] = []
				(out[e.x] as Array).append(e.y)
				if not inn.has(e.y):
					inn[e.y] = []
				(inn[e.y] as Array).append(e.x)
			var ra := _reach(a, out)
			if ra.has(b):
				break
			var rb := _reach(b, inn)
			var src := {}
			for i in ra:
				var c := _coarse_cell(pts_l[i], coarse, W2, H2, CR)
				if c >= 0:
					src[c] = i
			var dst := {}
			for i in rb:
				var c := _coarse_cell(pts_l[i], coarse, W2, H2, CR)
				if c >= 0:
					dst[c] = i
			if src.is_empty() or dst.is_empty():
				break
			var path := _dial(src, dst, coarse, safe, W2, H2)
			if path.is_empty():
				break
			# Void stretches must be short and roughly level (jet-able).
			var bad := false
			var run: Array = []
			for idx in path.size() + 1:
				var c: int = path[idx] if idx < path.size() else -1
				if c >= 0 and safe[c] == 0:
					run.append(c)
					continue
				if not run.is_empty():
					var minx := 1 << 30
					var maxx := -1
					for r in run:
						minx = mini(minx, r % W2)
						maxx = maxi(maxx, r % W2)
					var y0: int = run[0] / W2
					var y1: int = run[run.size() - 1] / W2
					if float(maxx - minx) * CR > 240.0 or float(y1 - y0) * CR > 40.0:
						bad = true
						break
					run = []
			if bad:
				break
			var wp: Array = []
			var k := BRIDGE_STEP
			while k < path.size() - BRIDGE_STEP:
				var c: int = path[k]
				wp.append(_snap_floor(float(c % W2) * CR, float(c / W2) * CR + 8.0))
				k += BRIDGE_STEP
			var si: int = src[path[0]]
			var di: int = dst[path[path.size() - 1]]
			var chain: Array = [pts_l[si]] + wp + [pts_l[di]]
			if _max_climb(chain) > BRIDGE_MAX_RISE:
				break
			var back := chain.duplicate()
			back.reverse()
			var two_way := _max_climb(back) <= BRIDGE_MAX_RISE
			var ids: Array = [si]
			for w in wp:
				ids.append(pts_l.size())
				pts_l.append(w)
			ids.append(di)
			for q in ids.size() - 1:
				edges.append(Vector2i(ids[q], ids[q + 1]))
				if two_way:
					edges.append(Vector2i(ids[q + 1], ids[q]))
			added += 1
	return added


func _coarse_cell(p: Vector2, coarse: PackedByteArray, W2: int, H2: int, CR: float) -> int:
	var cx := int(p.x / CR)
	var cy := int((p.y - 8.0) / CR)
	for d in 8:
		var yy := cy - d
		if yy >= 0 and yy < H2 and cx >= 0 and cx < W2 and coarse[yy * W2 + cx] == 1:
			return yy * W2 + cx
	return -1


func _snap_floor(x: float, y: float) -> Vector2:
	var col := int(round(x / R))
	var row := int(round(y / R))
	if col < 0 or col >= nx:
		return Vector2(x, y)
	for dr in int(160.0 / R):
		var rr := row + dr
		if rr < 0:
			continue
		if rr >= ny or stand[rr * nx + col] == 0:
			break
		if ground[rr * nx + col] == 1:
			return Vector2(x, rr * R)
	return Vector2(x, y)


## Dial's algorithm (small integer weights): step 1, climbing +1, air over a
## bottomless pit +40. Returns the cell path src -> dst, or [].
func _dial(src: Dictionary, dst: Dictionary, coarse: PackedByteArray, safe: PackedByteArray, W2: int, H2: int) -> Array:
	const NB := 64
	var dist := PackedInt32Array()
	dist.resize(W2 * H2)
	dist.fill(1 << 30)
	var parent := PackedInt32Array()
	parent.resize(W2 * H2)
	parent.fill(-1)
	var buckets: Array = []
	for i in NB:
		buckets.append(PackedInt32Array())
	var b0 := PackedInt32Array()
	for c in src:
		dist[c] = 0
		parent[c] = c
		b0.append(c)
	buckets[0] = b0
	var cur := 0
	var pending := src.size()
	var budget := BRIDGE_BUDGET
	var hit := -1
	while pending > 0 and budget > 0:
		var bk: PackedInt32Array = buckets[cur % NB]
		if bk.is_empty():
			cur += 1
			continue
		var c: int = bk[bk.size() - 1]
		bk.remove_at(bk.size() - 1)
		buckets[cur % NB] = bk
		pending -= 1
		budget -= 1
		if dist[c] != cur:
			continue
		if dst.has(c):
			hit = c
			break
		var x := c % W2
		var y := c / W2
		for d in 4:
			var xx := x + (1 if d == 0 else (-1 if d == 1 else 0))
			var yy := y + (1 if d == 2 else (-1 if d == 3 else 0))
			if xx < 0 or yy < 0 or xx >= W2 or yy >= H2:
				continue
			var n := yy * W2 + xx
			if coarse[n] == 0:
				continue
			var w := 1 + (1 if yy < y else 0) + (0 if safe[n] == 1 else 40)
			var nd := cur + w
			if nd < dist[n]:
				dist[n] = nd
				parent[n] = c
				var nb: PackedInt32Array = buckets[nd % NB]
				nb.append(n)
				buckets[nd % NB] = nb
				pending += 1
	if hit < 0:
		return []
	var path: Array = []
	var c2 := hit
	var guard := W2 * H2
	while guard > 0:
		path.append(c2)
		if parent[c2] == c2:
			break
		c2 = parent[c2]
		guard -= 1
	path.reverse()
	return path


# ── components + output ─────────────────────────────────────────────────────

func _components(pts_l: Array, edges: Array) -> Dictionary:
	var n := pts_l.size()
	var adj := {}
	for e in edges:
		if not adj.has(e.x):
			adj[e.x] = []
		if not adj.has(e.y):
			adj[e.y] = []
		(adj[e.x] as Array).append(e.y)
		(adj[e.y] as Array).append(e.x)
	var seen := PackedInt32Array()
	seen.resize(n)
	seen.fill(-1)
	var best: Array = []
	var keep := {}
	for s in n:
		if seen[s] != -1 or not adj.has(s):
			continue
		var comp: Array = [s]
		seen[s] = s
		var q: Array = [s]
		while not q.is_empty():
			var u: int = q.pop_back()
			for v in adj[u]:
				if seen[v] == -1:
					seen[v] = s
					comp.append(v)
					q.append(v)
		if comp.size() > best.size():
			best = comp
		if comp.size() >= MIN_COMP:
			for c in comp:
				keep[c] = true
	for c in best:
		keep[c] = true
	var order: Array = keep.keys()
	order.sort()
	var idx := {}
	for i in order.size():
		idx[order[i]] = i
	var nodes: Array = []
	var air: Array = []
	for i in order.size():
		var p: Vector2 = pts_l[order[i]]
		nodes.append(snappedf(p.x, 0.1))
		nodes.append(snappedf(p.y, 0.1))
		# Air waypoints (detours / bridge points not on a floor): fly through, never roam to.
		var cx := int(round(p.x / R))
		var cy := int(round(p.y / R))
		var on := false
		for dy in range(-2, 4):
			var yy := cy + dy
			if yy >= 0 and yy < ny and cx >= 0 and cx < nx and ground[yy * nx + cx] == 1:
				on = true
				break
		if not on:
			air.append(i)
	var out_edges: Array = []
	for e in edges:
		if idx.has(e.x) and idx.has(e.y):
			out_edges.append(idx[e.x])
			out_edges.append(idx[e.y])
	var out := {"nodes": nodes, "edges": out_edges, "air": air}
	if not _pad_links.is_empty():
		# Jump-pad rides (#286): [pad node, landing node, steer mode] triples.
		var pads: Array = []
		for pl: Vector3i in _pad_links:
			if idx.has(pl.x) and idx.has(pl.y):
				pads.append_array([idx[pl.x], idx[pl.y], pl.z])
		out["pads"] = pads
	return out
