extends Node2D
## Terrain depth pass (gfx.gd Medium+): built once per map from the solid
## outlines. Along every edge a soft dark band fades into the ground (fake
## ambient occlusion, so polygons read as solid rock instead of flat cut-outs);
## upward edges get a sunlit rim tinted by the ground under them, downward
## edges a heavier shadow; on High, green surfaces grow grass blades.
## One ArrayMesh, one draw call.

const Gfx := preload("res://scripts/gfx.gd")

var outlines: Array = []       # Array[PackedVector2Array] — merged solid outlines (ported maps)
var pieces: Array = []         # Array[PackedVector2Array] — solid polygons / triangles with no
                               # merged outline: their shared (internal) edges are dropped
var tris: Array = []           # [{pts, tex, uvs, vc, col}] for colour sampling
var grass := true
var edges_built := 0           # tests
var grass_blades := 0          # tests
var _img_cache: Dictionary = {}
var _grid: Dictionary = {}     # Vector2i cell -> Array[int] tri indices
const CELL := 160.0


func build() -> void:
	_index_tris()
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	var hi := Gfx.on(Gfx.HIGH)
	var depth := 26.0 if hi else 18.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234567
	for e in _edges():
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var nrm: Vector2 = e[2]
		var L := a.distance_to(b)
		var mid := (a + b) * 0.5
		var inw := -nrm
		edges_built += 1
		var up := clampf(-nrm.y, 0.0, 1.0)
		var down := clampf(nrm.y, 0.0, 1.0)
		# Ambient-occlusion band.
		var ao := 0.30 + down * 0.18
		_quad(verts, cols, a, b, b + inw * depth, a + inw * depth,
			Color(0, 0, 0, ao), Color(0, 0, 0, ao), Color(0, 0, 0, 0), Color(0, 0, 0, 0))
		if up > 0.35:
			var ground := _sample(mid + inw * 6.0)
			var rim := ground.lightened(0.5)
			rim.a = 0.55 * up
			var rim0 := rim
			rim0.a = 0.0
			_quad(verts, cols, a, b, b + inw * 6.0, a + inw * 6.0, rim, rim, rim0, rim0)
			var hl := Color(1, 1, 0.92, 0.35 * up)
			_quad(verts, cols, a, b, b + inw * 1.6, a + inw * 1.6, hl, hl, hl, hl)
			if hi and grass and up > 0.55 and _is_green(ground):
				_grass(verts, cols, a, b, nrm, ground, L, up, rng)
	if verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var v3 := PackedVector3Array()
	for v in verts:
		v3.append(Vector3(v.x, v.y, 0.0))
	arrays[Mesh.ARRAY_VERTEX] = v3
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance2D.new()
	mi.mesh = mesh
	add_child(mi)


## Every outer edge once: [a, b, outward normal]. Merged outlines give them
## directly; loose pieces keep only edges no other piece shares (rounded to
## half a pixel so triangle soups line up).
func _edges() -> Array:
	var out: Array = []
	for ol in outlines:
		var pts: PackedVector2Array = ol
		var n := pts.size()
		for i in n:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % n]
			if a.distance_to(b) < 2.0:
				continue
			var nrm := Vector2(b.y - a.y, a.x - b.x).normalized()
			if Geometry2D.is_point_in_polygon((a + b) * 0.5 + nrm * 2.0, pts):
				nrm = -nrm
			out.append([a, b, nrm])
	var count: Dictionary = {}
	for pc in pieces:
		var pts: PackedVector2Array = pc
		var n := pts.size()
		for i in n:
			var k := _ekey(pts[i], pts[(i + 1) % n])
			count[k] = int(count.get(k, 0)) + 1
	for pc in pieces:
		var pts: PackedVector2Array = pc
		var n := pts.size()
		for i in n:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % n]
			if a.distance_to(b) < 2.0 or int(count.get(_ekey(a, b), 0)) > 1:
				continue
			var nrm := Vector2(b.y - a.y, a.x - b.x).normalized()
			if Geometry2D.is_point_in_polygon((a + b) * 0.5 + nrm * 1.0, pts):
				nrm = -nrm
			# Skip edges buried against another piece (outside this one, but
			# still inside solid ground — overlapping polygons).
			if _inside_other((a + b) * 0.5 + nrm * 3.0, pc):
				continue
			out.append([a, b, nrm])
	return out


func _ekey(a: Vector2, b: Vector2) -> String:
	var ra := (a * 2.0).round()
	var rb := (b * 2.0).round()
	if ra.x > rb.x or (ra.x == rb.x and ra.y > rb.y):
		var t := ra
		ra = rb
		rb = t
	return "%d,%d,%d,%d" % [ra.x, ra.y, rb.x, rb.y]


var _piece_grid: Dictionary = {}


func _inside_other(p: Vector2, self_piece: PackedVector2Array) -> bool:
	if _piece_grid.is_empty():
		for i in pieces.size():
			var pts: PackedVector2Array = pieces[i]
			var r := Rect2(pts[0], Vector2.ZERO)
			for q in pts:
				r = r.expand(q)
			for cx in range(int(floor(r.position.x / CELL)), int(floor(r.end.x / CELL)) + 1):
				for cy in range(int(floor(r.position.y / CELL)), int(floor(r.end.y / CELL)) + 1):
					var key := Vector2i(cx, cy)
					if not _piece_grid.has(key):
						_piece_grid[key] = []
					_piece_grid[key].append(i)
	for i in _piece_grid.get(Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL))), []):
		var pts: PackedVector2Array = pieces[i]
		if pts == self_piece:
			continue
		if Geometry2D.is_point_in_polygon(p, pts):
			return true
	return false


func _quad(v: PackedVector2Array, c: PackedColorArray, p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2,
		c0: Color, c1: Color, c2: Color, c3: Color) -> void:
	v.append_array([p0, p1, p2, p0, p2, p3])
	c.append_array([c0, c1, c2, c0, c2, c3])


func _grass(v: PackedVector2Array, c: PackedColorArray, a: Vector2, b: Vector2, nrm: Vector2, ground: Color,
		L: float, up: float, rng: RandomNumberGenerator) -> void:
	var base := ground.darkened(0.25)
	base.a = 1.0
	var tip := ground.lightened(0.35).lerp(Color(0.75, 0.9, 0.45), 0.35)
	tip.a = 0.95
	var count := int(L / 4.0)
	for k in count:
		var t := (float(k) + rng.randf()) / float(count)
		var p := a.lerp(b, t) - nrm * 1.5
		var h := rng.randf_range(4.0, 11.0) * up
		var w := rng.randf_range(1.2, 2.2)
		var lean := Vector2(nrm.y, -nrm.x) * rng.randf_range(-3.5, 3.5)
		var side := Vector2(-nrm.y, nrm.x) * w
		v.append_array([p - side, p + side, p + nrm * h + lean])
		c.append_array([base, base, tip])
		grass_blades += 1


func _is_green(col: Color) -> bool:
	return col.g > col.r * 1.06 and col.g > col.b * 1.04 and col.g > 0.18


# ── colour of the ground at a point (texture × vertex colour) ─────────────

func _index_tris() -> void:
	_grid.clear()
	for i in tris.size():
		var pts: PackedVector2Array = tris[i].pts
		var r := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			r = r.expand(p)
		for cx in range(int(floor(r.position.x / CELL)), int(floor(r.end.x / CELL)) + 1):
			for cy in range(int(floor(r.position.y / CELL)), int(floor(r.end.y / CELL)) + 1):
				var key := Vector2i(cx, cy)
				if not _grid.has(key):
					_grid[key] = []
				_grid[key].append(i)


func _sample(p: Vector2) -> Color:
	var key := Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL)))
	for i in _grid.get(key, []):
		var t: Dictionary = tris[i]
		var pts: PackedVector2Array = t.pts
		if not Geometry2D.is_point_in_polygon(p, pts):
			continue
		var col: Color = t.col
		var vc: PackedColorArray = t.vc
		if pts.size() == 3:
			var w := _bary(p, pts[0], pts[1], pts[2])
			if vc.size() == 3:
				col = col * (vc[0] * w.x + vc[1] * w.y + vc[2] * w.z)
			var img: Image = _img(str(t.tex))
			var uvs: PackedVector2Array = t.uvs
			if img != null and uvs.size() == 3:
				var uv: Vector2 = uvs[0] * w.x + uvs[1] * w.y + uvs[2] * w.z
				col = col * img.get_pixel(posmod(int(uv.x * img.get_width()), img.get_width()), posmod(int(uv.y * img.get_height()), img.get_height()))
			elif img != null:
				col = col * _world_px(img, str(t.tex), p)
		else:
			var img2: Image = _img(str(t.tex))
			if img2 != null:
				col = col * _world_px(img2, str(t.tex), p)
		return col
	return Color(0.55, 0.52, 0.48)


func _bary(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> Vector3:
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var d := v0.x * v1.y - v1.x * v0.y
	if absf(d) < 0.0001:
		return Vector3(1, 0, 0)
	var v := (v2.x * v1.y - v1.x * v2.y) / d
	var w := (v0.x * v2.y - v2.x * v0.y) / d
	return Vector3(1.0 - v - w, v, w)


# Untextured-UV polygons tile the texture 1 world px = 1 texture px.
func _world_px(img: Image, path: String, p: Vector2) -> Color:
	var sz: Vector2 = _size_cache.get(path, Vector2(256, 256))
	return img.get_pixel(posmod(int(p.x / sz.x * img.get_width()), img.get_width()), posmod(int(p.y / sz.y * img.get_height()), img.get_height()))


var _size_cache: Dictionary = {}


func _img(path: String) -> Image:
	if path == "" or not ResourceLoader.exists(path):
		return null
	if _img_cache.has(path):
		return _img_cache[path]
	var tex := load(path) as Texture2D
	var img: Image = tex.get_image() if tex != null else null
	if img != null:
		_size_cache[path] = Vector2(img.get_width(), img.get_height())
		if img.is_compressed():
			img.decompress()
		img = img.duplicate()
		img.resize(32, 32, Image.INTERPOLATE_BILINEAR)
	_img_cache[path] = img
	return img
