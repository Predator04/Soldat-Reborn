extends Node2D
## A Bomb Defusal site (#304) in the world: a faint zone over the ground,
## corner brackets and a big letter over it. Turns red and pulses while the
## bomb is planted here. Cosmetic only (reads main._bomb).

var main: Node = null
var site_name := "A"
var rect := Rect2()
var _t := 0.0

const COL := Color(1.0, 0.62, 0.2)
const HOT := Color(1.0, 0.26, 0.2)


func _ready() -> void:
	z_index = -1


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if rect.size == Vector2.ZERO:
		return
	var hot := false
	if main != null and is_instance_valid(main) and main.get("_bomb") != null:
		var b = main._bomb
		hot = str(b.phase) == "planted" and str(b.planted_site) == site_name
	var col := HOT if hot else COL
	var pulse := 0.5 + 0.5 * sin(_t * (9.0 if hot else 2.0))
	var fill := col
	fill.a = (0.10 + 0.08 * pulse) if hot else 0.07
	draw_rect(rect, fill)
	# Ground strip + corner brackets.
	var edge := col
	edge.a = 0.85
	draw_line(Vector2(rect.position.x, rect.end.y - 1.0), Vector2(rect.end.x, rect.end.y - 1.0), edge, 3.0)
	var L := minf(28.0, rect.size.x * 0.25)
	for c in [rect.position, Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), rect.end]:
		var sx := 1.0 if c.x <= rect.get_center().x else -1.0
		var sy := 1.0 if c.y <= rect.get_center().y else -1.0
		draw_line(c, c + Vector2(L * sx, 0), edge, 2.0)
		draw_line(c, c + Vector2(0, L * sy), edge, 2.0)
	var font := UITheme.font("title")
	if font == null:
		return
	var fs := 56
	var w := font.get_string_size(site_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var at := Vector2(rect.get_center().x - w * 0.5, rect.position.y + fs * 0.85)
	var tc := col
	tc.a = 0.55 + 0.35 * pulse if hot else 0.5
	draw_string_outline(font, at, site_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.45))
	draw_string(font, at, site_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tc)
