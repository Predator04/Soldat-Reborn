extends Node2D
## Floating hit feedback for the local shooter: a small X at the impact and
## the damage number drifting up and fading. Spawned by bullet.gd.

var amount := 0.0
var big := false          # headshot / kill-sized hit
var _t := 0.0
const LIFE := 0.75
var _drift := Vector2.ZERO


func _ready() -> void:
	z_index = 50
	_drift = Vector2(randf_range(-18.0, 18.0), -70.0)


func _process(delta: float) -> void:
	_t += delta
	position += _drift * delta
	_drift.y *= 0.96
	if _t >= LIFE:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var a := clampf(1.0 - _t / LIFE, 0.0, 1.0)
	# Impact X (only the first ~0.15 s).
	if _t < 0.15:
		var s := 5.0 + _t * 20.0
		var xc := Color(1, 1, 1, a)
		draw_line(Vector2(-s, -s) - _drift * _t, Vector2(s, s) - _drift * _t, xc, 2.0)
		draw_line(Vector2(-s, s) - _drift * _t, Vector2(s, -s) - _drift * _t, xc, 2.0)
	var font := ThemeDB.fallback_font
	var fs := 18 if big else 14
	var txt := str(int(round(amount)))
	var col := Color(1.0, 0.35, 0.25, a) if big else Color(1.0, 0.92, 0.6, a)
	var sz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var at := Vector2(-sz.x * 0.5, -14.0)
	draw_string_outline(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.8 * a))
	draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
