extends Node2D
## Parallax — layered mountain/hill silhouettes that drift at a fraction of the camera.
## Lives on a CanvasLayer (screen space) so we control the offset by hand; each layer's
## pattern phase follows cam_center.x * factor, giving depth without world transform math.

const LAYERS := [
	{"f": 0.10, "h": 0.34, "col": Color(0.08, 0.12, 0.22), "seed": 11, "peaks": 9},
	{"f": 0.25, "h": 0.26, "col": Color(0.11, 0.16, 0.29), "seed": 23, "peaks": 11},
	{"f": 0.45, "h": 0.18, "col": Color(0.14, 0.21, 0.35), "seed": 37, "peaks": 13},
]
const PERIOD := 1600.0
const SEGMENTS := 48

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
			pts.append(Vector2(sx, view.y - max_h * (0.35 + 0.65 * ridge)))
		pts.append(Vector2(view.x, view.y))
		pts.append(Vector2(0.0, view.y))
		draw_colored_polygon(pts, l["col"])


func _sample_ridge(wx: float, hs: Array[float], peaks: float) -> float:
	var x := fposmod(wx, PERIOD)
	var seg := PERIOD / peaks
	var idx := int(x / seg)
	var t := fposmod(x / seg, 1.0)
	t = t * t * (3.0 - 2.0 * t)  # smoothstep
	var h0: float = hs[idx]
	var h1: float = hs[(idx + 1) % hs.size()]
	return lerpf(h0, h1, t)
