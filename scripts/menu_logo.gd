extends Control
## The TRACERFALL wordmark (graphics Phase C, #272): letter-spaced Barlow
## Condensed ExtraBold, "TRACER" in off-white and "FALL" in ember, a faint cool
## neon edge, and a tracer round streaking under it on load (then a glint every
## few seconds) that leaves an ember underline. Reduce motion: static, with the
## underline drawn.

const UITheme = preload("res://scripts/ui_theme.gd")
const GameInfo = preload("res://scripts/game_info.gd")
const SIZE := 78
const INTRO := 0.9

var _t := 0.0
var _glint := 6.0
var _font: Font = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UITheme.font("logo")
	if UITheme.UIFx.reduce_motion():
		_t = 10.0


func _process(delta: float) -> void:
	if UITheme.UIFx.reduce_motion():
		if _t < 10.0:
			_t = 10.0
			queue_redraw()
		return
	_t += delta
	if _t > INTRO:
		_glint -= delta
		if _glint < -0.9:
			_glint = 7.0
	queue_redraw()


func _parts() -> Array:
	var title: String = GameInfo.TITLE_UPPER
	var i := title.find("FALL")
	if i > 0:
		return [title.substr(0, i), title.substr(i)]
	return [title, ""]


func _draw() -> void:
	var parts := _parts()
	var a: String = parts[0]
	var b: String = parts[1]
	var wa := _font.get_string_size(a, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x
	var wb := _font.get_string_size(b, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x
	var total := wa + wb
	var x0 := (size.x - total) * 0.5
	var base := size.y * 0.5 + SIZE * 0.34
	var k := clampf(_t / 0.5, 0.0, 1.0)
	var rise := (1.0 - k) * 10.0
	var pos_a := Vector2(x0, base + rise)
	var pos_b := Vector2(x0 + wa, base + rise)
	var neon := UITheme.COL_NEON
	# Soft neon edge (two wide translucent outlines), then a dark rim, then fill.
	for o in [[16, 0.05], [7, 0.12]]:
		var c := Color(neon, float(o[1]) * k)
		draw_string_outline(_font, pos_a, a, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, int(o[0]), c)
		draw_string_outline(_font, pos_b, b, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, int(o[0]), Color(UITheme.COL_ACCENT, float(o[1]) * k))
	draw_string_outline(_font, pos_a, a, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, 3, Color(0, 0, 0, 0.7 * k))
	draw_string_outline(_font, pos_b, b, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, 3, Color(0, 0, 0, 0.7 * k))
	draw_string(_font, pos_a, a, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, Color(UITheme.COL_TEXT, k))
	draw_string(_font, pos_b, b, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, Color(UITheme.COL_ACCENT, k))
	# Tracer: a round streaks left → right under the word on load, leaving an
	# ember underline; later a faint glint runs along it now and then.
	var ly := base + 14.0
	var lx0 := x0 - 30.0
	var lx1 := x0 + total + 30.0
	var p := clampf((_t - 0.15) / (INTRO - 0.15), 0.0, 1.0)
	p = 1.0 - pow(1.0 - p, 3.0)
	var head := lerpf(lx0, lx1, p)
	if p > 0.0:
		# Underline that fades out at both ends.
		var segs := 24
		for i in segs:
			var u0 := float(i) / segs
			var u1 := float(i + 1) / segs
			var xa := lerpf(lx0, lx1, u0)
			var xb := minf(lerpf(lx0, lx1, u1), head)
			if xa >= head:
				break
			var edge := sin(((u0 + u1) * 0.5) * PI)
			draw_line(Vector2(xa, ly), Vector2(xb, ly), Color(UITheme.COL_ACCENT, 0.55 * edge), 2.0)
	if p > 0.0 and p < 1.0:
		_streak(head, ly, 220.0, 1.0)
	elif _glint < 0.0:
		var g := clampf(-_glint / 0.9, 0.0, 1.0)
		_streak(lerpf(lx0, lx1, g), ly, 120.0, 0.55 * sin(g * PI))


func _streak(head: float, y: float, length: float, a: float) -> void:
	var n := 10
	for i in n:
		var u0 := float(i) / n
		var u1 := float(i + 1) / n
		draw_line(Vector2(head - length * (1.0 - u0), y), Vector2(head - length * (1.0 - u1), y),
				Color(1.0, 0.85, 0.55, a * u1 * u1), 2.0 + 1.5 * u1)
	draw_circle(Vector2(head, y), 6.0, Color(1.0, 0.7, 0.3, 0.25 * a))
	draw_circle(Vector2(head, y), 2.6, Color(1.0, 0.96, 0.85, a))
