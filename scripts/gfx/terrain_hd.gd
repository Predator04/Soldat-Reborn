extends Node2D
## HD terrain (#283): the cinematic look's map surface. Built once per map at
## load from the same polygons the classic path draws (match_world registers
## them in `_hd_items`), then shown instead of them while the cinematic look
## runs at Medium / High quality:
##   Fill    one ArrayMesh holding every drawn polygon in file order, shaded by
##           terrain_hd.gdshader with up to three high-resolution materials
##           (assets/terrain-hd, tools/gen_terrain_gfx.py) tinted toward the
##           polygon's classic colour, so every map keeps its palette.
##           Non-colliding background polygons are darker, desaturated and
##           flatter so the playable surface reads first.
##   AO      vertex-colour band just inside every solid outline (+ a lit rim
##           on sun-facing sides).
##   Edges   painted strips along the collision outlines: grass lips, snow
##           caps, sand / dirt lips, rock rims, worn metal edges on top-facing
##           edges; hanging roots / icicles under overhangs. One mesh per
##           strip kind.
## A handful of canvas items in all; nothing is rebuilt per frame. Low quality,
## the classic look and headless runs keep the classic nodes exactly as they
## were (this node then draws nothing). Cosmetic only: no physics, no game
## state, no RNG.

const Gfx = preload("res://scripts/gfx.gd")
const TTheme = preload("res://scripts/gfx/terrain_theme.gd")
const SHADER = preload("res://scripts/gfx/terrain_hd.gdshader")
const TerrainFxScript = preload("res://scripts/terrain_fx.gd")

## Surface line (texel row) of each edge strip — tools/gen_terrain_gfx.py EDGE_LINE.
const EDGE_LINE := {"grass": 72, "snow": 44, "sand": 52, "dirt": 56, "rock": 30, "metal": 24, "roots": 10, "icicles": 10}
## Strip texels per world pixel, per kind (snow caps / sand lips drawn bigger).
const EDGE_SCALE := {"grass": 3.2, "snow": 2.3, "sand": 2.6, "dirt": 3.0, "rock": 3.2, "metal": 3.2, "roots": 2.8, "icicles": 2.9}
const EDGE_W := 1024.0
const EDGE_H := 128.0
const TOP_KINDS := ["grass", "snow", "sand", "dirt", "rock", "metal"]
const UNDER_KINDS := ["roots", "icicles"]
const CELL := 128.0

## Release gate: build + show the HD path in a headless test (Medium+ and
## not headless are skipped; the cinematic style is still required).
static var force_hd_for_tests := false
## Capture tools: hide the HD path to render the "before" frame.
static var suppress := false
static var _meta: Dictionary = {}

var main: Node = null
var map: Dictionary = {}
var items: Array = []          # match_world._hd_items: {nodes, pts, vc, col, tex, cc}
var pieces: Array = []         # solid collision pieces (outline edges)

var built := false
var on := false
var primary := ""
var slots: PackedStringArray = PackedStringArray()
var item_mats: PackedStringArray = PackedStringArray()
var edge_counts: Dictionary = {}
var tris_built := 0
var build_ms := 0.0

var _hidden: Array = []
var _snow := false
var _item_tris: Array = []     # per item: PackedVector2Array, 3 points per triangle
var _item_col: Array = []      # per item: average graded colour
var _item_alpha := PackedFloat32Array()
var _item_bg := PackedFloat32Array()
var _grid: Dictionary = {}
var _depth_cache: Dictionary = {}
var _fog := Color(0.2, 0.22, 0.26)


static func wanted() -> bool:
	if suppress or Settings.visual_style != "cinematic":
		return false
	if force_hd_for_tests:
		return true
	return Gfx.on(Gfx.MEDIUM) and DisplayServer.get_name() != "headless"


func setup(m: Node, its: Array, pcs: Array) -> void:
	main = m
	map = m.get("_map")
	items = its
	pieces = pcs


func _ready() -> void:
	z_index = -1
	_sync()


func _process(_delta: float) -> void:
	if wanted() != on:
		_sync()


func _exit_tree() -> void:
	_hidden.clear()


## Show / hide: the classic polygon nodes and terrain_fx's edge pass are
## hidden while this draws (and put back exactly as they were otherwise).
func _sync() -> void:
	var w := wanted()
	if w and not built:
		_build()
	on = w
	visible = w
	if w:
		if _hidden.is_empty():
			for it in items:
				for n in it.get("nodes", []):
					var ci := n as CanvasItem
					if ci != null and is_instance_valid(ci) and ci.visible:
						ci.visible = false
						_hidden.append(ci)
	else:
		for ci in _hidden:
			if is_instance_valid(ci):
				(ci as CanvasItem).visible = true
		_hidden.clear()
	var tfx = main.get("terrain_fx") if main != null else null
	if tfx != null and is_instance_valid(tfx):
		(tfx as CanvasItem).visible = not w


static func _load_meta() -> Dictionary:
	if _meta.is_empty():
		var f := FileAccess.open(TTheme.DIR + "materials.json", FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if typeof(d) == TYPE_DICTIONARY:
				_meta = d
	return _meta


static func material_mean(mat: String) -> Color:
	var m: Dictionary = _load_meta().get(mat, {})
	var a: Array = m.get("mean", [0.5, 0.5, 0.5])
	return Color(float(a[0]), float(a[1]), float(a[2]))


## The material each polygon resolves to (tests / diagnostics).
func resolved_materials() -> PackedStringArray:
	return slots


# ── build ────────────────────────────────────────────────────────────────────

func _build() -> void:
	var t0 := Time.get_ticks_usec()
	built = true
	primary = TTheme.primary_for(map)
	_snow = TTheme.snowy(map)
	var sky: Variant = map.get("sky", {})
	if typeof(sky) == TYPE_DICTIONARY and (sky as Dictionary).has("bottom"):
		var b: Array = (sky as Dictionary)["bottom"]
		if b.size() >= 3:
			_fog = Color(float(b[0]), float(b[1]), float(b[2])).darkened(0.55)
	# 1) per polygon: classic colours, background factor, material weights
	#    per vertex (accumulated by area to pick the map's material slots).
	var vcols: Array = []
	var vweights: Array = []
	var area_by_mat: Dictionary = {}
	item_mats.resize(items.size())
	_item_alpha.resize(items.size())
	_item_bg.resize(items.size())
	for i in items.size():
		var it: Dictionary = items[i]
		var pts: PackedVector2Array = it.get("pts", PackedVector2Array())
		var cls := _classic_colors(it, pts)
		var avg := Color(0, 0, 0, 0)
		for c in cls:
			avg += c
		avg = avg / maxf(1.0, float(cls.size()))
		var bg := _bg_factor(int(it.get("cc", 0)), pts)
		if avg.a < 0.7:
			bg = 0.0   # translucent glass / light / shade overlays keep their tone
		item_mats[i] = TTheme.classify(primary, avg, _snow)
		_item_alpha[i] = avg.a
		_item_bg[i] = bg
		var graded := PackedColorArray()
		var ws: Array = []
		var area := _area(pts) * avg.a / maxf(1.0, float(pts.size()))
		for c in cls:
			graded.append(_grade(c, bg))
			var w := TTheme.weights(primary, c, _snow)
			ws.append(w)
			if bg < 0.75:
				for m in w:
					area_by_mat[m] = float(area_by_mat.get(m, 0.0)) + float(w[m]) * area
		vcols.append(graded)
		vweights.append(ws)
		_item_col.append(_grade(avg, 0.0))
	# 2) up to three material slots: primary + the two most-used others.
	var order: Array = area_by_mat.keys()
	order.sort_custom(func(x, y): return float(area_by_mat[x]) > float(area_by_mat[y]))
	slots = PackedStringArray([primary])
	for m in order:
		if slots.size() >= 3:
			break
		if not slots.has(m) and float(area_by_mat[m]) > 0.01 * float(area_by_mat.get(order[0], 1.0)):
			slots.append(m)
	for i in items.size():
		if not slots.has(item_mats[i]):
			item_mats[i] = primary
	var used: Array = []
	for m in slots:
		used.append(TTheme.DIR + m + TTheme.MAT_EXT)
		used.append(TTheme.DIR + m + "_n" + TTheme.MAT_EXT)
	TTheme.keep_half_only(used)
	# 3) fill mesh.
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	for i in items.size():
		var pts: PackedVector2Array = items[i].get("pts", PackedVector2Array())
		var idx := PackedInt32Array([0, 1, 2]) if pts.size() == 3 else Geometry2D.triangulate_polygon(pts)
		var tri := PackedVector2Array()
		var pc: PackedColorArray = vcols[i]
		var ws: Array = vweights[i]
		var lvl := 0.0 if _item_bg[i] <= 0.0 else (1.0 if _item_bg[i] < 0.75 else 2.0)
		if _item_alpha[i] < 0.7 and not _on_solid(items[i].get("pts", PackedVector2Array())):
			lvl = 2.0   # glass / water / light out in the open: flat, no material relief
		var suv := PackedVector2Array()
		for k in pts.size():
			var sw := Vector3.ZERO
			var w: Dictionary = ws[k]
			for m in w:
				var si := slots.find(m)
				sw[maxi(si, 0)] += float(w[m])
			var tot := maxf(sw.x + sw.y + sw.z, 0.0001)
			suv.append(Vector2(sw.y / tot + lvl * 2.0, sw.z / tot))
		for j in idx:
			verts.append(pts[j])
			cols.append(pc[j])
			uvs.append(suv[j])
			tri.append(pts[j])
		_item_tris.append(tri)
		_index_item(i, tri)
	tris_built = verts.size() / 3
	if not verts.is_empty():
		var mi := MeshInstance2D.new()
		mi.name = "Fill"
		mi.mesh = _mesh(verts, cols, uvs)
		mi.material = _fill_material()
		# The primary material as a CanvasTexture (diffuse + normal), so the
		# fill is a regular normal-mapped canvas item for the 2D lights; the
		# shader samples slot 0 through TEXTURE / NORMAL_TEXTURE.
		var ct := CanvasTexture.new()
		ct.diffuse_texture = _mat_tex(slots[0], false)
		ct.normal_texture = _mat_tex(slots[0], true)
		ct.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		ct.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		mi.texture = ct
		mi.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mi.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		add_child(mi)
	# 4) outlines: AO band + painted edges.
	_build_edges()
	build_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	_grid.clear()
	_depth_cache.clear()


func _classic_colors(it: Dictionary, pts: PackedVector2Array) -> PackedColorArray:
	# What the classic path multiplies: texture x node colour x vertex colour
	# (untextured polygons use their colour). The texture term is looked up at
	# each vertex's tile UV (half vertex, half polygon centre: an area
	# estimate) because many classic textures are atlases; polygons without
	# UVs use the texture's typical colour.
	var tex := str(it.get("tex", ""))
	var col: Color = it.get("col", Color(0.3, 0.32, 0.3))
	var vc: PackedColorArray = it.get("vc", PackedColorArray())
	var uvs: PackedVector2Array = it.get("uvs", PackedVector2Array())
	var out := PackedColorArray()
	var textured := tex != "" and ResourceLoader.exists(tex)
	var mod: Color = it.get("mod", Color.WHITE)
	var small: Image = TTheme.tex_small(tex) if textured and uvs.size() == pts.size() else null
	var tm := TTheme.tex_mean(tex) if textured else Color.WHITE
	var uc := Vector2.ZERO
	if small != null:
		for uv in uvs:
			uc += uv
		uc /= float(uvs.size())
	var cc := TTheme.tex_at(small, uc) if small != null else tm
	for k in pts.size():
		var base := col
		if textured:
			var t := tm
			if small != null:
				t = TTheme.tex_at(small, uvs[k]).lerp(cc, 0.5)
			base = Color(t.r * mod.r, t.g * mod.g, t.b * mod.b, mod.a)
		out.append(base * vc[k] if vc.size() == pts.size() else base)
	return out


## Readable palette: a little less saturation, highlights compressed so no
## surface glares behind a soldier; background polygons darker, greyer and
## pulled toward the sky's fog colour.
func _grade(c: Color, bg: float) -> Color:
	var l := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
	# Loud colours (lime jungle, pure blue water) are calmed the most.
	var g := Color(l, l, l).lerp(c, 0.84 - 0.26 * smoothstep(0.45, 0.9, c.s))
	var tl := l if l < 0.58 else 0.58 + (l - 0.58) * 0.5
	tl = maxf(tl, 0.045)
	var k := tl / maxf(l, 0.001)
	g = Color(g.r * k, g.g * k, g.b * k)
	if bg > 0.0:
		var gl := g.r * 0.299 + g.g * 0.587 + g.b * 0.114
		# Mild: background art (skulls, spikes, signs built from polygons) must
		# keep its identity; the painted edges / AO on the solid outlines do
		# most of the solid-vs-backdrop separation.
		var dg := Color(gl, gl, gl).lerp(g, 0.8).darkened(0.12).lerp(_fog, 0.06)
		g = g.lerp(dg, bg)
	return Color(clampf(g.r, 0, 1), clampf(g.g, 0, 1), clampf(g.b, 0, 1), c.a)


func _bg_factor(cc: int, pts: PackedVector2Array) -> float:
	if cc == 0 or cc == 2 or pts.size() < 3:
		return 0.0
	if cc == 1:
		return 0.45
	# Decorative: an overlay painted onto solid ground keeps its tone, a
	# backdrop out in the open recedes.
	return 0.0 if _on_solid(pts) else 1.0


## Mostly inside player-solid ground (centre + vertices pulled inward)?
func _on_solid(pts: PackedVector2Array) -> bool:
	var w = main.get("_world") if main != null else null
	if w == null or not w.has_method("_point_in_solid") or pts.size() < 3:
		return false
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= float(pts.size())
	var inside := 0
	var total := 1
	if w._point_in_solid(c):
		inside += 1
	for k in mini(pts.size(), 6):
		total += 1
		if w._point_in_solid(pts[k].lerp(c, 0.35)):
			inside += 1
	return float(inside) / float(total) >= 0.5


func _area(pts: PackedVector2Array) -> float:
	var a := 0.0
	for k in pts.size():
		var p: Vector2 = pts[k]
		var q: Vector2 = pts[(k + 1) % pts.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5


func _mesh(verts: PackedVector2Array, cols: PackedColorArray, uvs: PackedVector2Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	if not uvs.is_empty():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## High: the 2048 px materials; Medium: 1024 px copies (memory, phones).
func _mat_tex(mat: String, normal: bool) -> Texture2D:
	return TTheme.material_texture(mat, normal, not Gfx.on(Gfx.HIGH))


func _fill_material() -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = SHADER
	var keep := Vector3.ZERO
	var inv := Vector3.ZERO
	for s in 3:
		var mat: String = slots[mini(s, slots.size() - 1)]
		if s > 0:   # slot 0 = the CanvasTexture on the node
			sm.set_shader_parameter("alb%d" % s, _mat_tex(mat, false))
			sm.set_shader_parameter("nrm%d" % s, _mat_tex(mat, true))
		var mc := material_mean(mat)
		sm.set_shader_parameter("mean%d" % s, Vector3(mc.r, mc.g, mc.b))
		keep[s] = float(TTheme.KEEP.get(mat, 0.2))
		inv[s] = 1.0 / float(TTheme.TILE.get(mat, 800.0))
	sm.set_shader_parameter("keep", keep)
	sm.set_shader_parameter("inv_tile", inv)
	return sm


# ── point sampling over the drawn polygons ───────────────────────────────────

func _index_item(i: int, tri: PackedVector2Array) -> void:
	if tri.is_empty():
		return
	var r := Rect2(tri[0], Vector2.ZERO)
	for p in tri:
		r = r.expand(p)
	for cx in range(int(floor(r.position.x / CELL)), int(floor(r.end.x / CELL)) + 1):
		for cy in range(int(floor(r.position.y / CELL)), int(floor(r.end.y / CELL)) + 1):
			var key := Vector2i(cx, cy)
			if not _grid.has(key):
				_grid[key] = PackedInt32Array()
			var l: PackedInt32Array = _grid[key]
			l.append(i)
			_grid[key] = l


## Top-most visible playable polygon at p (-1 if none): the surface whose
## material / colour an edge takes.
func _sample(p: Vector2) -> int:
	var l: PackedInt32Array = _grid.get(Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL))), PackedInt32Array())
	for n in range(l.size() - 1, -1, -1):
		var i := l[n]
		if _item_alpha[i] < 0.35 or _item_bg[i] > 0.5:
			continue
		var tri: PackedVector2Array = _item_tris[i]
		for t in range(0, tri.size() - 2, 3):
			if Geometry2D.point_is_inside_triangle(p, tri[t], tri[t + 1], tri[t + 2]):
				return i
	return -1


func _solid(p: Vector2) -> bool:
	var w = main.get("_world") if main != null else null
	return w != null and w._point_in_solid(p)


## How far solid ground continues straight below p (capped).
func _depth_below(p: Vector2, cap: float) -> float:
	var key := Vector3i(int(round(p.x * 2.0)), int(round(p.y * 2.0)), int(cap))
	if _depth_cache.has(key):
		return _depth_cache[key]
	var d := 3.0
	var out := cap
	while d <= cap:
		if not _solid(p + Vector2(0, d)):
			out = maxf(0.0, d - 3.0)
			break
		d += 3.0
	_depth_cache[key] = out
	return out


## Free air straight below p (capped) — hanging roots / icicles stop short of
## the ground under them.
func _air_below(p: Vector2, cap: float) -> float:
	var d := 4.0
	while d <= cap:
		if _solid(p + Vector2(0, d)):
			return maxf(0.0, d - 4.0)
		d += 4.0
	return cap


# ── edges ────────────────────────────────────────────────────────────────────

func _build_edges() -> void:
	if pieces.is_empty():
		return
	var fx = TerrainFxScript.new()
	fx.pieces = pieces
	var edges: Array = fx._edges()
	var joined: Array = fx._joined_normals(edges)
	fx.free()
	_edges_cache = edges
	var hi := Gfx.on(Gfx.HIGH)
	var depth := 22.0 if hi else 16.0
	# Pass 1: classify every edge.
	var kinds_top: Array = []
	var kinds_under: Array = []
	var surf: PackedInt32Array = PackedInt32Array()
	var at: Dictionary = {}
	for ei in edges.size():
		var e: Array = edges[ei]
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var nrm: Vector2 = e[2]
		var mid := (a + b) * 0.5
		var si := _sample(mid - nrm * 5.0)
		if si < 0:
			si = _sample(mid - nrm * 12.0)
		surf.append(si)
		var kt := ""
		var ku := ""
		if si >= 0:
			var mat := item_mats[si]
			var col: Color = _item_col[si]
			if -nrm.y > 0.5:
				kt = TTheme.top_edge(mat, col, _snow)
			elif nrm.y > 0.55:
				ku = TTheme.under_edge(mat, col, _snow)
		kinds_top.append(kt)
		kinds_under.append(ku)
		for end in 2:
			var k := Vector2i(((e[end] as Vector2) * 2.0).round())
			if not at.has(k):
				at[k] = []
			at[k].append(ei)
	# Pass 2: geometry.
	var ao_v := PackedVector2Array()
	var ao_c := PackedColorArray()
	var strips: Dictionary = {}
	for k in TOP_KINDS + UNDER_KINDS:
		strips[k] = [PackedVector2Array(), PackedColorArray(), PackedVector2Array()]
	edge_counts = {"ao": 0}
	for ei in edges.size():
		var si: int = surf[ei]
		if si < 0:
			continue
		var e: Array = edges[ei]
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var nrm: Vector2 = e[2]
		var vis := clampf(_item_alpha[si], 0.0, 1.0)
		var col: Color = _item_col[si]
		var ia: Vector2 = -(joined[ei][0] as Vector2)
		var ib: Vector2 = -(joined[ei][1] as Vector2)
		var ra: float = joined[ei][2]
		var rb: float = joined[ei][3]
		var up := clampf(-nrm.y, 0.0, 1.0)
		var down := clampf(nrm.y, 0.0, 1.0)
		# Ambient occlusion just inside the edge; heavier under overhangs.
		var ao := (0.34 + down * 0.22) * vis
		_quad(ao_v, ao_c, a, b, b + ib * minf(depth, rb), a + ia * minf(depth, ra),
			Color(0, 0, 0, ao), Color(0, 0, 0, ao), Color(0, 0, 0, 0), Color(0, 0, 0, 0))
		edge_counts["ao"] = int(edge_counts["ao"]) + 1
		# Sun from the upper left: a lit rim on left-facing walls / slopes.
		var lit := clampf(-nrm.x, 0.0, 1.0) * (1.0 - up)
		if lit > 0.3:
			var rc := col.lightened(0.45)
			rc.a = 0.32 * lit * vis
			var r0 := rc
			r0.a = 0.0
			_quad(ao_v, ao_c, a, b, b + ib * minf(4.0, rb), a + ia * minf(4.0, ra), rc, rc, r0, r0)
		var kt: String = kinds_top[ei]
		if kt != "":
			var fade := smoothstep(0.5, 0.68, up) * vis
			var oa := _open_end(at, ei, 0, kinds_top, kt)
			var ob := _open_end(at, ei, 1, kinds_top, kt)
			_strip_top(strips[kt], kt, a, b, fade, oa, ob, _edge_tint(kt, col))
			edge_counts[kt] = int(edge_counts.get(kt, 0)) + 1
		var ku: String = kinds_under[ei]
		if ku != "":
			var fade2 := smoothstep(0.55, 0.75, down) * vis
			var oa2 := _open_end(at, ei, 0, kinds_under, ku)
			var ob2 := _open_end(at, ei, 1, kinds_under, ku)
			_strip_under(strips[ku], ku, a, b, fade2, oa2, ob2, _edge_tint(ku, col))
			edge_counts[ku] = int(edge_counts.get(ku, 0)) + 1
	if not ao_v.is_empty():
		var mi := MeshInstance2D.new()
		mi.name = "EdgeAO"
		mi.mesh = _mesh(ao_v, ao_c, PackedVector2Array())
		add_child(mi)
	for k in UNDER_KINDS + TOP_KINDS:
		var arr: Array = strips[k]
		if (arr[0] as PackedVector2Array).is_empty():
			continue
		var mi := MeshInstance2D.new()
		mi.name = "Edge_" + k
		mi.mesh = _mesh(arr[0], arr[1], arr[2])
		mi.texture = load(TTheme.DIR + "edge_%s.png" % k)
		mi.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mi.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		add_child(mi)
	_edges_cache = []


func _open_end(at: Dictionary, ei: int, end: int, kinds: Array, kind: String) -> bool:
	var lst: Array = at.get(Vector2i(((_edge_pt(ei, end)) * 2.0).round()), [])
	for j in lst:
		if j != ei and kinds[j] == kind:
			return false
	return true


var _edges_cache: Array = []


func _edge_pt(ei: int, end: int) -> Vector2:
	return _edges_cache[ei][end]


func _edge_tint(kind: String, col: Color) -> Color:
	match kind:
		"grass":
			# The map's green, brightened (the strip is painted light).
			var g := _with_lum(col, 0.62)
			return Color(minf(1.0, g.r * 1.1), minf(1.0, g.g * 1.0), minf(1.0, g.b * 1.35))
		"snow", "icicles":
			return Color(0.93, 0.95, 1.0)
		"sand", "dirt":
			return _with_lum(col, 0.78)
		"roots":
			return _with_lum(col, 0.5)
		"rock", "metal":
			var r := col.lerp(Color(1, 1, 1), 0.5)
			r.a = 0.8
			return r
	return Color.WHITE


func _with_lum(c: Color, l: float) -> Color:
	var cl := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
	var k := l / maxf(cl, 0.02)
	return Color(minf(1.0, c.r * k), minf(1.0, c.g * k), minf(1.0, c.b * k), 1.0)


## Top lip: a vertical skirt hung on the edge (blades stay upright, adjacent
## edges share their end columns so the strip runs on seamlessly; u follows
## world x). Open ends fade out over ~18 px.
func _strip_top(arr: Array, kind: String, a: Vector2, b: Vector2, alpha: float, open_a: bool, open_b: bool, tint: Color) -> void:
	var L: float = EDGE_LINE[kind]
	var T: float = EDGE_SCALE[kind]
	var above := L / T
	var below := (EDGE_H - L) / T
	var pts := [a]
	var al := [0.0 if open_a else alpha]
	var len := a.distance_to(b)
	var f := minf(0.45, 18.0 / maxf(len, 0.001))
	if open_a:
		pts.append(a.lerp(b, f))
		al.append(alpha)
	if open_b:
		pts.append(a.lerp(b, 1.0 - f))
		al.append(alpha)
	pts.append(b)
	al.append(0.0 if open_b else alpha)
	for k in pts.size() - 1:
		var p: Vector2 = pts[k]
		var q: Vector2 = pts[k + 1]
		var dp := _depth_below(p, below)
		var dq := _depth_below(q, below)
		var cp := tint
		cp.a *= al[k]
		var cq := tint
		cq.a *= al[k + 1]
		var w := EDGE_W / T
		_quad_uv(arr, Vector2(p.x, p.y - above), Vector2(q.x, q.y - above), Vector2(q.x, q.y + dq), Vector2(p.x, p.y + dp),
			Vector2(p.x / w, 0.0), Vector2(q.x / w, 0.0), Vector2(q.x / w, (L + dq * T) / EDGE_H), Vector2(p.x / w, (L + dp * T) / EDGE_H),
			cp, cq, cq, cp)


## Under an overhang: roots / icicles hang straight down from the edge.
func _strip_under(arr: Array, kind: String, a: Vector2, b: Vector2, alpha: float, open_a: bool, open_b: bool, tint: Color) -> void:
	var L: float = EDGE_LINE[kind]
	var T: float = EDGE_SCALE[kind]
	var inside := L / T
	var hang := (EDGE_H - L) / T
	var pts := [a]
	var al := [0.0 if open_a else alpha]
	var len := a.distance_to(b)
	var f := minf(0.45, 14.0 / maxf(len, 0.001))
	if open_a:
		pts.append(a.lerp(b, f))
		al.append(alpha)
	if open_b:
		pts.append(a.lerp(b, 1.0 - f))
		al.append(alpha)
	pts.append(b)
	al.append(0.0 if open_b else alpha)
	for k in pts.size() - 1:
		var p: Vector2 = pts[k]
		var q: Vector2 = pts[k + 1]
		var hp := minf(hang, _air_below(p, hang) * 0.7)
		var hq := minf(hang, _air_below(q, hang) * 0.7)
		var cp := tint
		cp.a *= al[k]
		var cq := tint
		cq.a *= al[k + 1]
		var w := EDGE_W / T
		_quad_uv(arr, Vector2(p.x, p.y - inside), Vector2(q.x, q.y - inside), Vector2(q.x, q.y + hq), Vector2(p.x, p.y + hp),
			Vector2(p.x / w, 0.0), Vector2(q.x / w, 0.0), Vector2(q.x / w, (L + hq * T) / EDGE_H), Vector2(p.x / w, (L + hp * T) / EDGE_H),
			cp, cq, cq, cp)


func _quad(v: PackedVector2Array, c: PackedColorArray, p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2,
		c0: Color, c1: Color, c2: Color, c3: Color) -> void:
	v.append_array([p0, p1, p2, p0, p2, p3])
	c.append_array([c0, c1, c2, c0, c2, c3])


func _quad_uv(arr: Array, p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2,
		u0: Vector2, u1: Vector2, u2: Vector2, u3: Vector2, c0: Color, c1: Color, c2: Color, c3: Color) -> void:
	var v: PackedVector2Array = arr[0]
	var c: PackedColorArray = arr[1]
	var u: PackedVector2Array = arr[2]
	v.append_array([p0, p1, p2, p0, p2, p3])
	c.append_array([c0, c1, c2, c0, c2, c3])
	u.append_array([u0, u1, u2, u0, u2, u3])
	arr[0] = v
	arr[1] = c
	arr[2] = u
