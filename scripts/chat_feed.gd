extends "res://scripts/timed_feed.gd"
## Chat feed (bottom left, above the ammo readout): global / team chat and
## radio calls. Newest at the bottom, seven lines, ten seconds each
## (timed_feed.gd).


func _init() -> void:
	max_lines = 7
	line_ttl = 10.0
	newest_first = false
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 14
	offset_top = -260
	offset_bottom = -140
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func add_chat(author: String, msg: String, is_team: bool) -> void:
	var lbl := Label.new()
	lbl.text = ("(TEAM) %s: %s" % [author, msg]) if is_team else ("%s: %s" % [author, msg])
	var col := Color(0.6, 0.95, 1.0) if is_team else Color(0.95, 0.95, 0.95)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 3)
	push_line(lbl)


## Radio line: amber, tagged, and team-only by construction.
func add_radio(author: String, text: String) -> void:
	add_chat(author, text, true)
	var last := get_child(get_child_count() - 1) as Label
	if last != null:
		last.text = "(RADIO) %s: %s" % [author, text]
		last.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
