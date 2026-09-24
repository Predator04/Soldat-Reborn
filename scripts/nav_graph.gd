extends RefCounted
## NavGraph — baked bot navigation for one map (see tools/build_nav.py).
##
## Nodes sit on walkable surfaces ~40 px apart; directed links mean "a soldier
## can get from A to B" by walking, hopping, jetting up, or dropping down.
## Bots ask for a path (list of feet positions) and follow it waypoint by
## waypoint. Maps without a baked graph (editor maps) get an empty graph and
## bots fall back to their old direct-chase movement.

const NAV_DIR := "res://assets/nav/"
const CELL := 160.0

var astar := AStar2D.new()
var _pts: PackedVector2Array = PackedVector2Array()
var _grid: Dictionary = {}   # Vector2i cell -> Array[int]


static func key_for(map_name: String) -> String:
	var s := map_name.to_lower()
	var out := ""
	var prev_us := false
	for i in s.length():
		var c := s.substr(i, 1)
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
			prev_us = false
		elif not prev_us:
			out += "_"
			prev_us = true
	return out.strip_edges().trim_prefix("_").trim_suffix("_")


static func load_for(m: Dictionary) -> RefCounted:
	var g = load("res://scripts/nav_graph.gd").new()
	var path: String = NAV_DIR + key_for(str(m.get("name", ""))) + ".json"
	if not FileAccess.file_exists(path):
		return g
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return g
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return g
	# Stale bake guard: a map whose geometry changed since the bake would send
	# bots through walls — better to have no graph than a wrong one.
	var polys: Array = m.get("polys", [])
	var coll: Array = m.get("collision", [])
	if int(data.get("poly_count", -1)) != polys.size() or int(data.get("coll_count", 0)) != coll.size():
		push_warning("nav graph for %s is stale — re-run tools/build_nav.py" % m.get("name", "?"))
		return g
	g._build(data.get("nodes", []), data.get("edges", []))
	return g


func _build(nodes: Array, edges: Array) -> void:
	var n := nodes.size() / 2
	astar.reserve_space(n)
	for i in n:
		var p := Vector2(float(nodes[i * 2]), float(nodes[i * 2 + 1]))
		_pts.append(p)
		astar.add_point(i, p)
		var c := Vector2i(int(p.x / CELL), int(p.y / CELL))
		if not _grid.has(c):
			_grid[c] = []
		(_grid[c] as Array).append(i)
	var e := 0
	while e + 1 < edges.size():
		var a := int(edges[e])
		var b := int(edges[e + 1])
		if a >= 0 and a < n and b >= 0 and b < n and not astar.are_points_connected(a, b, false):
			astar.connect_points(a, b, false)
		e += 2


func is_empty() -> bool:
	return _pts.is_empty()


func point(id: int) -> Vector2:
	return _pts[id]


func nearest(pos: Vector2, max_dist: float = 480.0) -> int:
	# Nearest node, biased toward nodes at/below the feet (the surface we're
	# standing on or will fall to) over ones overhead behind a ceiling.
	var best := -1
	var best_d := INF
	var r := int(ceil(max_dist / CELL))
	var c := Vector2i(int(pos.x / CELL), int(pos.y / CELL))
	for gx in range(c.x - r, c.x + r + 1):
		for gy in range(c.y - r, c.y + r + 1):
			var ids: Variant = _grid.get(Vector2i(gx, gy))
			if ids == null:
				continue
			for id in ids:
				var d: Vector2 = _pts[id] - pos
				var cost := d.length() + (maxf(0.0, -d.y) * 0.6)
				if cost < best_d:
					best_d = cost
					best = id
	return best


func path(from: Vector2, to: Vector2) -> PackedVector2Array:
	if _pts.is_empty():
		return PackedVector2Array()
	var a := nearest(from)
	var b := nearest(to, 900.0)
	if a < 0 or b < 0:
		return PackedVector2Array()
	if a == b:
		return PackedVector2Array([to])
	var p := astar.get_point_path(a, b)
	if p.is_empty():
		return p
	p.append(to)
	return p


func random_point_near(pos: Vector2, radius: float) -> Vector2:
	# A walkable spot within `radius` (for defenders patrolling their base).
	var cands: Array = []
	var r := int(ceil(radius / CELL))
	var c := Vector2i(int(pos.x / CELL), int(pos.y / CELL))
	for gx in range(c.x - r, c.x + r + 1):
		for gy in range(c.y - r, c.y + r + 1):
			var ids: Variant = _grid.get(Vector2i(gx, gy))
			if ids == null:
				continue
			for id in ids:
				if _pts[id].distance_to(pos) <= radius:
					cands.append(id)
	if cands.is_empty():
		return pos
	return _pts[cands[randi() % cands.size()]]


func random_point() -> Vector2:
	if _pts.is_empty():
		return Vector2.ZERO
	return _pts[randi() % _pts.size()]
