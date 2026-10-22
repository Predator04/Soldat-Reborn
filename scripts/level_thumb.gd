extends Control
## Level thumbnail (#288): paints a level's outline — the "thumb" the master
## server builds from the map JSON (levels.go buildThumb: platform rects,
## coloured polygons, flag / dom markers in a <=320x128 box) — scaled to fit,
## over a small sky. No images: everything is one triangle batch per card,
## built once per thumb (Geometry2D triangulation, bad polygons skipped).
## from_map() makes the same thumb from a map JSON dict on the client
## (offline bookmarks, the publish preview, the test's fake server).

const UITheme = preload("res://scripts/ui_theme.gd")

const GROUND := Color(0.50, 0.55, 0.60)          # default ground (maps without colours)
const SKY_TOP := Color(0.10, 0.15, 0.22)
const SKY_BOT := Color(0.20, 0.25, 0.31)
const FLAG_COLS := [Color(0.35, 0.62, 1.0), Color(1.0, 0.36, 0.30), Color(0.95, 0.95, 0.95), Color(1.0, 0.78, 0.30)]
const THEME_SKY := {
	"desert": [Color(0.30, 0.22, 0.16), Color(0.52, 0.40, 0.28)],
	"snow": [Color(0.20, 0.27, 0.36), Color(0.45, 0.53, 0.62)],
	"jungle": [Color(0.09, 0.18, 0.16), Color(0.20, 0.32, 0.26)],
	"urban": [Color(0.12, 0.13, 0.18), Color(0.25, 0.26, 0.31)],
	"ruins": [Color(0.20, 0.16, 0.20), Color(0.36, 0.30, 0.32)],
	"rock": [Color(0.13, 0.16, 0.21), Color(0.28, 0.31, 0.36)],
}

var thumb: Dictionary = {}
var theme_name := ""
var round_corners := true
var _pts := PackedVector2Array()
var _cols := PackedColorArray()
var _idx := PackedInt32Array()
var tris := 0     # for tests: triangles in the batch


func set_thumb(t: Variant, theme := "") -> void:
	thumb = t if t is Dictionary else {}
	theme_name = theme
	_build()
	queue_redraw()


static func _grade(c: Color) -> Color:
	# Calm the raw map colours a little so every card reads on the dark UI.
	var g := c.lerp(Color(0.5, 0.53, 0.56), 0.18)
	var l := g.get_luminance()
	if l < 0.16:
		g = g.lerp(Color(0.42, 0.46, 0.5), (0.16 - l) * 3.0)
	return g


static func _colour(v: Variant, fallback: Color) -> Color:
	var n := int(v) if (v is int or v is float) else -1
	if n < 0:
		return fallback
	return _grade(Color8((n >> 16) & 255, (n >> 8) & 255, n & 255))


func _build() -> void:
	_pts = PackedVector2Array()
	_cols = PackedColorArray()
	_idx = PackedInt32Array()
	tris = 0
	var base := _colour(thumb.get("c", -1), GROUND)
	for r in thumb.get("r", []):
		if not (r is Array) or r.size() < 4:
			continue
		var x := float(r[0])
		var y := float(r[1])
		var w := maxf(1.0, float(r[2]))
		var h := maxf(1.0, float(r[3]))
		var o := _pts.size()
		_pts.append_array(PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)]))
		for _i in 4:
			_cols.append(base)
		_idx.append_array(PackedInt32Array([o, o + 1, o + 2, o, o + 2, o + 3]))
		tris += 2
	for p in thumb.get("p", []):
		if not (p is Array) or p.size() < 7:
			continue
		var poly := PackedVector2Array()
		var k := 1
		while k + 1 < p.size():
			poly.append(Vector2(float(p[k]), float(p[k + 1])))
			k += 2
		var tri := Geometry2D.triangulate_polygon(poly)
		if tri.is_empty():
			continue   # degenerate after quantising: skip it rather than spam errors
		var col := _colour(p[0], base)
		var o := _pts.size()
		_pts.append_array(poly)
		for _i in poly.size():
			_cols.append(col)
		for t in tri:
			_idx.append(o + t)
		tris += tri.size() / 3


func _fit() -> Array:
	var tw := maxf(1.0, float(thumb.get("w", 1)))
	var th := maxf(1.0, float(thumb.get("h", 1)))
	var s := minf((size.x - 8.0) / tw, (size.y - 8.0) / th)
	var off := (size - Vector2(tw, th) * s) * 0.5
	return [off, s]


func _draw() -> void:
	var sky: Array = THEME_SKY.get(theme_name, [SKY_TOP, SKY_BOT])
	var r := Rect2(Vector2.ZERO, size)
	# Sky: a vertical gradient as one quad.
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([sky[0], sky[0], sky[1], sky[1]]))
	if thumb.is_empty():
		var f := UITheme.font("caps")
		var txt := tr("NO PREVIEW")
		var tsz := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		draw_string(f, (size - tsz) * 0.5 + Vector2(0, tsz.y * 0.75), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UITheme.COL_TEXT_MUTED)
	else:
		var fit := _fit()
		var off: Vector2 = fit[0]
		var s: float = fit[1]
		if not _idx.is_empty():
			draw_set_transform(off, 0.0, Vector2(s, s))
			RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _idx, _pts, _cols)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var ms := clampf(s * 5.0, 4.0, 9.0)
		for f in thumb.get("f", []):
			if not (f is Array) or f.size() < 3:
				continue
			var c: Vector2 = off + Vector2(float(f[0]), float(f[1])) * s
			var kind := clampi(int(f[2]), 0, 3)
			var col: Color = FLAG_COLS[kind]
			if kind == 3:
				draw_circle(c, ms * 0.45, col)
			else:
				draw_line(c, c + Vector2(0, -ms * 1.6), Color(0.9, 0.9, 0.9), 1.5, true)
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -ms * 1.6), c + Vector2(ms * 1.1, -ms * 1.25), c + Vector2(0, -ms * 0.9)]), col)
	# Hairline frame.
	draw_rect(r.grow(-0.5), UITheme.COL_BORDER, false, 1.0)


# ── Client-side thumb from a map JSON dict (same rules as the server) ──────

const TW := 320.0
const TH := 128.0
const MAX_POLYS := 600


static func _v(v: Variant) -> Variant:
	if v is Array and v.size() >= 2 and (v[0] is float or v[0] is int) and (v[1] is float or v[1] is int):
		return Vector2(float(v[0]), float(v[1]))
	return null


static func _hex(s: String) -> int:
	return s.left(6).hex_to_int() if s.length() >= 6 and s.left(6).is_valid_hex_number() else -1


static func _poly_colour(p: Dictionary, def: int) -> int:
	var c = p.get("color")
	if c is Array and c.size() >= 3:
		return (clampi(roundi(float(c[0]) * 255.0), 0, 255) << 16) | (clampi(roundi(float(c[1]) * 255.0), 0, 255) << 8) | clampi(roundi(float(c[2]) * 255.0), 0, 255)
	var vc = p.get("vc")
	if vc is Array and not vc.is_empty():
		var acc := [0, 0, 0]
		var n := 0
		for h in vc:
			var v := _hex(str(h))
			if v >= 0:
				acc[0] += (v >> 16) & 255
				acc[1] += (v >> 8) & 255
				acc[2] += v & 255
				n += 1
		if n > 0:
			return (int(acc[0] / n) << 16) | (int(acc[1] / n) << 8) | int(acc[2] / n)
	return def


## Thumb dict (server format) from a map JSON dict, or {} with no geometry.
static func from_map(m: Dictionary) -> Dictionary:
	var def := -1
	var tc = m.get("terrain_color")
	if tc is Array and tc.size() >= 3:
		def = _poly_colour({"color": tc}, -1)
	var rects: Array = []   # [x, y, w, h]
	var polys: Array = []   # [colour, PackedVector2Array, area]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for pl in (m.get("platforms", []) if m.get("platforms") is Array else []):
		if not (pl is Dictionary):
			continue
		var p = _v(pl.get("p"))
		var s = _v(pl.get("s"))
		if p == null or s == null or s.x <= 0 or s.y <= 0:
			continue
		rects.append([p.x, p.y, s.x, s.y])
		lo = lo.min(p)
		hi = hi.max(p + s)
	for po in (m.get("polys", []) if m.get("polys") is Array else []):
		if not (po is Dictionary) or not (po.get("points") is Array):
			continue
		var flat: Array = po["points"]
		var pts := PackedVector2Array()
		var i := 0
		while i + 1 < flat.size():
			pts.append(Vector2(float(flat[i]), float(flat[i + 1])))
			i += 2
		if pts.size() < 3:
			continue
		for q in pts:
			lo = lo.min(q)
			hi = hi.max(q)
		polys.append([_poly_colour(po, def), pts, absf(_area(pts))])
	var world = m.get("world")
	var floor_y := 0.0
	var floor_w := 0.0
	if world is Dictionary:
		if bool(world.get("floor_visible", false)):
			floor_y = float(world.get("ground_y", 0.0))
			floor_w = float(world.get("w", 0.0))
	else:
		floor_y = 1900.0
		floor_w = 4800.0
	if floor_w > 0.0 and floor_y > 0.0:
		rects.append([0.0, floor_y, floor_w, 100.0])
		lo = lo.min(Vector2(0, floor_y))
		hi = hi.max(Vector2(floor_w, floor_y + 100.0))
	if rects.is_empty() and polys.is_empty():
		return {}
	var ext := hi - lo
	if ext.x < 1.0 or ext.y < 1.0:
		return {}
	# Objective markers widen the box (a flag stands above its ground) unless
	# they're far outside the geometry.
	var marks: Array = []   # [Vector2, kind]
	var flags = m.get("ctf_flags", [])
	if flags is Array:
		for i in mini(2, flags.size()):
			marks.append([_v(flags[i]), i])
	for key in ["inf_flag", "htf_flag"]:
		var fv = _v(m.get(key))
		if fv != null:
			marks.append([fv, 2])
			break
	var doms = m.get("dom_points", [])
	if doms is Array:
		for d in doms:
			marks.append([_v(d), 3])
	var kept: Array = []
	var slack := ext * 0.25
	for mk in marks:
		var v = mk[0]
		if v is Vector2 and v.x >= lo.x - slack.x and v.x <= hi.x + slack.x and v.y >= lo.y - slack.y and v.y <= hi.y + slack.y:
			lo = lo.min(v - Vector2(0, 60))
			hi = hi.max(v)
			kept.append(mk)
	ext = hi - lo
	lo -= ext * 0.02
	hi += ext * 0.02
	ext = hi - lo
	var sc := minf(TW / ext.x, TH / ext.y)
	var t := {"w": int(ceil(ext.x * sc)), "h": int(ceil(ext.y * sc)), "c": def, "r": [], "p": [], "f": []}
	for r in rects:
		t["r"].append([roundi((r[0] - lo.x) * sc), roundi((r[1] - lo.y) * sc), maxi(1, roundi(r[2] * sc)), maxi(1, roundi(r[3] * sc))])
	# Biggest first when over budget, then back in file order.
	var order := range(polys.size())
	order.sort_custom(func(a: int, b: int) -> bool: return polys[a][2] > polys[b][2])
	var keep := {}
	for k in order:
		if keep.size() >= MAX_POLYS:
			break
		if polys[k][2] * sc * sc >= 0.5:
			keep[k] = true
	for k in polys.size():
		if not keep.has(k):
			continue
		var row := [polys[k][0]]
		var last := Vector2i(-99999, -99999)
		for q in (polys[k][1] as PackedVector2Array):
			var qi := Vector2i(roundi((q.x - lo.x) * sc), roundi((q.y - lo.y) * sc))
			if qi != last:
				row.append(qi.x)
				row.append(qi.y)
				last = qi
		if row.size() >= 7:
			t["p"].append(row)
	for mk in kept:
		var v: Vector2 = mk[0]
		t["f"].append([roundi((v.x - lo.x) * sc), roundi((v.y - lo.y) * sc), int(mk[1])])
	return t


static func _area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		var j := (i + 1) % p.size()
		a += p[i].x * p[j].y - p[j].x * p[i].y
	return a * 0.5


## Mode hints for a map JSON dict (same rules as the server's modeHints).
static func mode_hints(m: Dictionary) -> String:
	var out := ["dm"]
	var spawns := (m.get("bot_spawns", []) as Array).size() if m.get("bot_spawns") is Array else 0
	if _v(m.get("player_spawn")) != null:
		spawns += 1
	var flags := (m.get("ctf_flags", []) as Array).size() if m.get("ctf_flags") is Array else 0
	if spawns >= 2 or m.get("team_spawns") is Dictionary or flags >= 2:
		out.append("tdm")
	if flags >= 2:
		out.append("ctf")
	for pair in [["inf_flag", "inf"], ["htf_flag", "htf"], ["rambo_pos", "rm"]]:
		if _v(m.get(pair[0])) != null:
			out.append(pair[1])
	if m.get("dom_points") is Array and not (m["dom_points"] as Array).is_empty():
		out.append("dom")
	# #304: two bomb sites = built for Bomb Defusal (same rule as the server).
	if m.get("bomb_sites") is Array and (m["bomb_sites"] as Array).size() >= 2:
		out.append("bomb")
	return " ".join(out)
