extends Node2D
## ItemLabel (v1.18) — small name tag floating over a pickup / map item.
## Fades in as the local player gets close so a busy map doesn't turn into
## a wall of text.

const NEAR := 440.0
const FAR := 640.0

var text := ""
var color := Color(1, 1, 1)
var lift := 26.0
var _a := -1.0


var _dup := false        # an identical tag right next to this one already shows the name
var _nudge := 0.0        # lifted a bit so two different tags don't overlap


func _ready() -> void:
	z_index = 60
	top_level = false
	add_to_group("item_label")
	_settle.call_deferred()


# Two kits side by side (Voland) used to print GRENADE KIT twice on top of each
# other: identical tags close together show once; different ones stack.
func _settle() -> void:
	if not is_inside_tree():
		return
	for o in get_tree().get_nodes_in_group("item_label"):
		if o == self or not is_instance_valid(o) or o.get_instance_id() > get_instance_id():
			continue
		var d: Vector2 = (o as Node2D).global_position - global_position
		var font := ThemeDB.fallback_font
		var half: float = (font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x \
				+ font.get_string_size(str(o.get("text")), HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x) * 0.5 + 6.0
		var dy: float = (d.y - float(o.get("lift")) - float(o.get("_nudge"))) - (-lift)
		if absf(d.x) > half or absf(dy) > 16.0:
			continue
		if str(o.get("text")) == text and absf(d.x) < 110.0:
			_dup = true
		else:
			_nudge = maxf(_nudge, 16.0 - dy)


func _process(_d: float) -> void:
	var a := _alpha()
	if absf(a - _a) > 0.02:
		_a = a
		queue_redraw()


func _alpha() -> float:
	var main := get_tree().current_scene
	var p = main.get("player") if main != null else null
	var from: Vector2
	if p != null and is_instance_valid(p) and p.get("dead") != true:
		from = (p as Node2D).global_position
	else:
		from = Sfx.listener_pos()
	var d := global_position.distance_to(from)
	return clampf((FAR - d) / (FAR - NEAR), 0.0, 1.0)


func _draw() -> void:
	if _a <= 0.0 or text == "" or _dup:
		return
	var font := ThemeDB.fallback_font
	var fs := 11
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var at := Vector2(-sz.x * 0.5, -lift - _nudge)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.85 * _a))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(color.r, color.g, color.b, _a))


static func attach(host: Node, label: String, col: Color, lift_px: float = 26.0) -> Node2D:
	var l := (load("res://scripts/item_label.gd") as GDScript).new() as Node2D
	l.set("text", label)
	l.set("color", col)
	l.set("lift", lift_px)
	l.name = "ItemLabel"
	host.add_child(l)
	return l
