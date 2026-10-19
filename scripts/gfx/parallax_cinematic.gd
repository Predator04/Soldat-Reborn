extends Node2D
## Multi-layer parallax with atmospheric depth (cinematic look). Screen space on
## its own CanvasLayer; each layer's phase follows the camera by a factor.
##
## Five ridge layers from the horizon forward. Far layers melt into the horizon
## fog colour, near ones go dark; every ridge gets a thin moonlit rim and fades
## into a fog band at its base, so depth reads without competing with the arena.
## Two middle layers carry sparse ruin silhouettes (towers, masts, gantries) for
## the gritty war-zone feel. One triangle mesh per layer per frame. Cosmetic only.

const PERIOD := 1800.0
const SEGMENTS := 80
# f = parallax factor, h = max height (fraction of view), d = depth 0 near … 1 far.
const LAYERS := [
	{"f": 0.04, "h": 0.46, "d": 1.00, "seed": 7, "peaks": 6, "ruins": 0},
	{"f": 0.09, "h": 0.40, "d": 0.80, "seed": 19, "peaks": 8, "ruins": 0},
	{"f": 0.17, "h": 0.33, "d": 0.58, "seed": 31, "peaks": 10, "ruins": 5},
	{"f": 0.30, "h": 0.26, "d": 0.36, "seed": 47, "peaks": 12, "ruins": 4},
	{"f": 0.50, "h": 0.17, "d": 0.14, "seed": 59, "peaks": 14, "ruins": 0},
]

var horizon := Color(0.34, 0.24, 0.28)   # fog / far colour (sky bottom)
var near := Color(0.03, 0.035, 0.06)     # nearest ridge colour
var rim := Color(0.75, 0.82, 1.0)        # moonlit edge
var rim_amount := 0.35
var cinematic := 1.0
## Fixed view centre instead of the current camera (the menu backdrop drifts
## this slowly; #272). Vector2.INF = follow the camera.
var center_override := Vector2.INF
## #283: map theme (terrain_theme.gd theme_for, set by atmosphere.gd before
## _ready): picks the silhouettes on the middle layers and the ridge shape.
## "" = the original look (menu backdrop).
var theme := ""

# Silhouette kinds per theme and how many on each of the five layers (far →
# near); jag = sharper peaks, caps = snow on the far ridges, smooth = calmer
# ridge detail (dunes).
const THEMES := {
	"rock": {"kinds": [0, 1, 2], "counts": [0, 0, 5, 4, 0]},
	"urban": {"kinds": [3, 3, 3, 1, 2], "counts": [0, 9, 10, 7, 0]},
	"desert": {"kinds": [4, 4, 5], "counts": [0, 3, 4, 6, 0], "smooth": 0.35},
	"snow": {"kinds": [6], "counts": [0, 0, 14, 18, 0], "jag": 1.0, "caps": true},
	"jungle": {"kinds": [7, 7, 8], "counts": [0, 0, 16, 20, 0]},
	"ruins": {"kinds": [0, 9, 9, 1], "counts": [0, 0, 6, 6, 0]},
}

var _peaks: Array = []
var _ruins: Array = []


func _ready() -> void:
	for l in LAYERS:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(l["seed"])
		var hs: Array[float] = []
		for _i in int(l["peaks"]):
			hs.append(rng.randf_range(0.0, 1.0))
		_peaks.append(hs)
		var rs: Array = []
		var th: Dictionary = THEMES.get(theme, {})
		var count := int(l["ruins"]) if th.is_empty() else int((th["counts"] as Array)[_ruins.size()])
		for _i in count:
			# x in pattern space, width, height (fraction of layer height), kind
			var kind := rng.randi() % 3
			if not th.is_empty():
				var ks: Array = th["kinds"]
				kind = int(ks[rng.randi() % ks.size()])
			rs.append([rng.randf_range(0.0, PERIOD), rng.randf_range(10.0, 34.0), rng.randf_range(0.25, 0.7), kind])
		_ruins.append(rs)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var cc: Vector2 = center_override
	if cc == Vector2.INF:
		var cam := get_viewport().get_camera_2d()
		if cam == null:
			return
		cc = cam.get_screen_center_position()
	var view := get_viewport_rect().size
	for i in LAYERS.size():
		_draw_layer(i, view, cc)


func _layer_color(depth: float) -> Color:
	var c := near.lerp(horizon, pow(depth, 1.35))
	return c


func _draw_layer(i: int, view: Vector2, cc: Vector2) -> void:
	var l: Dictionary = LAYERS[i]
	var f: float = l["f"]
	var depth: float = l["d"]
	var max_h: float = view.y * float(l["h"])
	var hs: Array[float] = _peaks[i]
	var base_y := view.y + 2.0
	# Vertical drift: a little camera-y parallax so jetting upward moves the hills.
	var y_off := clampf(-cc.y * f * 0.04, -40.0, 40.0)
	var body := _layer_color(depth)
	# Valley haze: the base of farther ridges drifts toward the horizon colour.
	var base_col := body.lerp(horizon, 0.18 * depth)
	var top_col := body.lerp(rim, rim_amount * (1.0 - depth * 0.7) * 0.25)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var ridge_y: Array[float] = []
	var th: Dictionary = THEMES.get(theme, {})
	var smooth_k: float = float(th.get("smooth", 1.0))
	var jag: float = float(th.get("jag", 0.0))
	var caps: bool = bool(th.get("caps", false)) and depth >= 0.5
	var snow_col := Color(0.82, 0.86, 0.94).lerp(horizon, 0.35 + 0.4 * depth)
	for s in SEGMENTS + 1:
		var sx: float = view.x * float(s) / float(SEGMENTS)
		var wx: float = sx + cc.x * f
		var r: float = _sample_ridge(wx, hs, float(l["peaks"]))
		var detail: float = (0.06 * sin(wx * 0.011 + float(i) * 1.7) + 0.035 * sin(wx * 0.033 + float(i) * 3.1)) * smooth_k
		if jag > 0.0:
			detail += jag * 0.09 * (1.0 - absf(sin(wx * 0.017 + float(i)))) * r
		var ry: float = view.y - max_h * maxf(0.02, 0.30 + 0.65 * r + detail) + y_off
		if is_nan(ry):
			ry = view.y * 0.7
		ry = minf(ry, view.y - 2.0)
		ridge_y.append(ry)
		# Three vertices per column: rim (ridge), body (a bit below), fog (base).
		pts.append(Vector2(sx, ry))
		if caps:
			# Snow on the high ground of the far ridges.
			var cap := smoothstep(0.45, 0.85, r)
			cols.append(top_col.lerp(snow_col, cap))
			pts.append(Vector2(sx, minf(ry + 1.5 + cap * max_h * 0.14, base_y)))
			cols.append(body.lerp(snow_col, 0.55 * cap))
		else:
			cols.append(top_col)
			pts.append(Vector2(sx, minf(ry + 1.5, base_y)))
			cols.append(body)
		pts.append(Vector2(sx, base_y))
		cols.append(base_col)
	for s in SEGMENTS:
		var a := s * 3
		var b := (s + 1) * 3
		idx.append_array([a, b, a + 1, b, b + 1, a + 1])
		idx.append_array([a + 1, b + 1, a + 2, b + 1, b + 2, a + 2])
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), idx, pts, cols)
	# Ruins on the middle layers.
	var rs: Array = _ruins[i]
	if rs.is_empty():
		return
	for ru in rs:
		var px: float = fposmod(float(ru[0]) - cc.x * f, PERIOD) - 200.0
		for rep in 2:
			var sx := px - float(rep) * PERIOD
			if sx < -60.0 or sx > view.x + 60.0:
				continue
			var col_i := clampi(int(sx / view.x * float(SEGMENTS)), 0, SEGMENTS)
			var gy: float = ridge_y[col_i] + 4.0
			var w: float = ru[1]
			var h: float = max_h * float(ru[2])
			var c := body.darkened(0.08)
			match int(ru[3]):
				0:  # broken tower
					draw_rect(Rect2(sx - w * 0.5, gy - h, w, h), c)
					draw_colored_polygon(PackedVector2Array([Vector2(sx - w * 0.5, gy - h), Vector2(sx + w * 0.5, gy - h * 0.86), Vector2(sx + w * 0.5, gy - h)]), c)
				1:  # radio mast with a blinking light
					draw_rect(Rect2(sx - 1.5, gy - h * 1.3, 3.0, h * 1.3), c)
					draw_line(Vector2(sx, gy - h * 1.3), Vector2(sx - w * 0.6, gy), c, 1.0)
					draw_line(Vector2(sx, gy - h * 1.3), Vector2(sx + w * 0.6, gy), c, 1.0)
					var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.004 + float(ru[0]))
					draw_circle(Vector2(sx, gy - h * 1.3), 1.6, Color(1.0, 0.25, 0.2, (0.35 + 0.65 * blink) * (1.0 - depth * 0.5)))
				2:  # gantry / crane
					draw_rect(Rect2(sx - w * 0.15, gy - h, w * 0.3, h), c)
					draw_rect(Rect2(sx - w, gy - h, w * 2.0, 3.0), c)
					draw_line(Vector2(sx + w * 0.9, gy - h + 3.0), Vector2(sx + w * 0.9, gy - h * 0.55), c, 1.0)
				_:
					_draw_theme_kind(int(ru[3]), sx, gy, w, h, c, depth, float(ru[0]))


func _sample_ridge(wx: float, hs: Array[float], peaks: float) -> float:
	var x := fposmod(wx, PERIOD)
	var seg := PERIOD / peaks
	var i := int(x / seg)
	var t := fposmod(x / seg, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	return lerpf(hs[i % hs.size()], hs[(i + 1) % hs.size()], t)


## #283 theme silhouettes: skyline blocks with a few lit windows, mesas and
## cacti, pines, canopy trees and palms, broken arches.
func _draw_theme_kind(kind: int, sx: float, gy: float, w: float, h: float, c: Color, depth: float, seed_x: float) -> void:
	match kind:
		3:  # building block, some windows lit
			var bw := w * 1.6
			var bh := h * 1.15
			draw_rect(Rect2(sx - bw * 0.5, gy - bh, bw, bh), c)
			if int(seed_x) % 3 == 0:
				draw_rect(Rect2(sx - bw * 0.15, gy - bh - h * 0.25, bw * 0.12, h * 0.25), c)
			var lit := Color(1.0, 0.78, 0.45, 0.45 * (1.0 - depth * 0.6))
			var hs := int(seed_x * 7.0)
			for k in 6:
				hs = (hs * 1103515245 + 12345) & 0x7fffffff
				if hs % 3 != 0:
					continue
				var wx := sx - bw * 0.4 + float(hs % 5) * bw * 0.18
				var wy := gy - bh + 4.0 + float((hs >> 4) % 6) * bh * 0.14
				draw_rect(Rect2(wx, wy, 2.0, 2.0), lit)
		4:  # mesa
			draw_colored_polygon(PackedVector2Array([Vector2(sx - w * 2.4, gy + 2.0), Vector2(sx - w * 1.5, gy - h * 0.8),
				Vector2(sx + w * 1.3, gy - h * 0.8), Vector2(sx + w * 2.2, gy + 2.0)]), c)
		5:  # cactus
			var tw := maxf(2.0, w * 0.12)
			draw_rect(Rect2(sx - tw * 0.5, gy - h * 0.6, tw, h * 0.6), c)
			draw_rect(Rect2(sx - tw * 2.2, gy - h * 0.42, tw, h * 0.2), c)
			draw_rect(Rect2(sx - tw * 2.2, gy - h * 0.26, tw * 2.0, tw), c)
			draw_rect(Rect2(sx + tw * 1.2, gy - h * 0.5, tw, h * 0.22), c)
			draw_rect(Rect2(sx + tw * 0.4, gy - h * 0.32, tw * 1.6, tw), c)
		6:  # pine
			var pw := w * 0.55
			var ph := h * 0.9
			draw_colored_polygon(PackedVector2Array([Vector2(sx - pw, gy), Vector2(sx, gy - ph * 0.6), Vector2(sx + pw, gy)]), c)
			draw_colored_polygon(PackedVector2Array([Vector2(sx - pw * 0.75, gy - ph * 0.35), Vector2(sx, gy - ph), Vector2(sx + pw * 0.75, gy - ph * 0.35)]), c)
		7:  # canopy tree
			draw_rect(Rect2(sx - 1.5, gy - h * 0.5, 3.0, h * 0.5), c)
			draw_circle(Vector2(sx, gy - h * 0.62), w * 0.55, c)
			draw_circle(Vector2(sx - w * 0.45, gy - h * 0.5), w * 0.4, c)
			draw_circle(Vector2(sx + w * 0.5, gy - h * 0.52), w * 0.42, c)
		8:  # palm
			var top := Vector2(sx + w * 0.35, gy - h * 0.95)
			draw_polyline(PackedVector2Array([Vector2(sx, gy), Vector2(sx + w * 0.12, gy - h * 0.5), top]), c, 2.0)
			for k in 5:
				var a := -2.6 + float(k) * 0.55
				var tip := top + Vector2(cos(a), sin(a) * 0.55 + 0.25) * w * 0.9
				draw_polyline(PackedVector2Array([top, top.lerp(tip, 0.5) + Vector2(0, -3.0), tip]), c, 1.5)
		9:  # broken arch / colonnade
			var cw := maxf(3.0, w * 0.22)
			draw_rect(Rect2(sx - w, gy - h, cw, h), c)
			draw_rect(Rect2(sx + w - cw, gy - h * 0.7, cw, h * 0.7), c)
			draw_rect(Rect2(sx - w - cw * 0.3, gy - h - cw * 0.6, w * 1.3, cw * 0.6), c)
