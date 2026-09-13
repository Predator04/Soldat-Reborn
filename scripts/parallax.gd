extends Node2D
## Parallax — layered mountain/hill silhouettes that drift at a fraction of the camera.
## Lives on a CanvasLayer (screen space) so we control the offset by hand; each layer's
## pattern phase follows cam_center.x * factor, giving depth without world transform math.
##
## Four ridge layers plus a horizon haze band give real depth to the arena. Points along
## the ridge are jittered with layered sine noise so peaks feel organic, not sawtooth.

const LAYERS := [
	{"f": 0.06, "h": 0.42, "col": Color(0.10, 0.13, 0.22), "seed": 7,  "peaks": 7},
	{"f": 0.14, "h": 0.34, "col": Color(0.13, 0.17, 0.28), "seed": 19, "peaks": 9},
	{"f": 0.28, "h": 0.26, "col": Color(0.16, 0.22, 0.34), "seed": 31, "peaks": 11},
	{"f": 0.48, "h": 0.18, "col": Color(0.20, 0.28, 0.40), "seed": 47, "peaks": 13},
]
const PERIOD := 1600.0
const SEGMENTS := 72

var _peaks: Array = []


func _ready() -> void:
	for l in LAYERS:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(l["seed"])
		var hs: Array[float] = []
		for _i in int(l["peaks"]):
			hs.append(rng.randf_range(0.0, 1.0))
		_peaks.append(hs)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var view := get_viewport_rect().size
	var cam_x: float = cam.get_screen_center_position().x
	# Warm horizon band — sits behind the mountains, gives the sunset feel.
	_draw_horizon_glow(view)
	for i in LAYERS.size():
		var l: Dictionary = LAYERS[i]
		var f: float = l["f"]
		var max_h: float = view.y * float(l["h"])
		var hs: Array[float] = _peaks[i]
		var pts := PackedVector2Array()
		for s in SEGMENTS + 1:
			var sx: float = view.x * float(s) / float(SEGMENTS)
			var wx: float = sx + cam_x * f
			var ridge: float = _sample_ridge(wx, hs, float(l["peaks"]))
			# Layered noise adds crag detail so ridges don't look interpolated.
			var detail: float = 0.06 * sin(wx * 0.011 + float(i) * 1.7) + 0.035 * sin(wx * 0.033 + float(i) * 3.1)
			pts.append(Vector2(sx, view.y - max_h * (0.30 + 0.65 * ridge + detail)))
		pts.append(Vector2(view.x, view.y))
		pts.append(Vector2(0.0, view.y))
		draw_colored_polygon(pts, l["col"])


func _draw_horizon_glow(view: Vector2) -> void:
	# A thin gradient band across the horizon line — warm at the base of the ridges
	# so mountains stand out against a slightly lit sky (dusk mood).
	var band_top := view.y * 0.35
	var band_bot := view.y * 0.68
	var steps := 16
	var top := Color(0.10, 0.12, 0.20, 0.0)
	var bottom := Color(0.62, 0.42, 0.34, 0.45)
	for i in steps:
		var t := float(i) / float(steps)
		var y := lerpf(band_top, band_bot, t)
		var h := (band_bot - band_top) / float(steps) + 1.0
		draw_rect(Rect2(0.0, y, view.x, h), top.lerp(bottom, t))


func _sample_ridge(wx: float, hs: Array[float], peaks: float) -> float:
	var x := fposmod(wx, PERIOD)
	var seg := PERIOD / peaks
	var idx := int(x / seg)
	var t := fposmod(x / seg, 1.0)
	t = t * t * (3.0 - 2.0 * t)  # smoothstep
	var h0: float = hs[idx]
	var h1: float = hs[(idx + 1) % hs.size()]
	return lerpf(h0, h1, t)
