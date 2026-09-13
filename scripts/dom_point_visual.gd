extends Node2D
## Draws the capture-progress ring + owner tint for a Domination control point.
## Attached as a child of the Area2D flagged with add_to_group("dom_point").

const RADIUS := 40.0


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var owner_team: int = int(parent.get_meta("owner_team"))
	var progress: float = float(parent.get_meta("progress"))
	var cap_team: int = int(parent.get_meta("cap_team"))
	var label: String = str(parent.get_meta("label", "?"))
	# Base pad — floor puck showing current ownership.
	var base_col: Color = _team_color(owner_team)
	base_col.a = 0.55
	draw_circle(Vector2.ZERO, RADIUS, base_col)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 40, Color(0, 0, 0, 0.85), 2.0)
	# In-progress capture arc — a partial circle in the capturing team's color.
	if cap_team != 0 and progress > 0.01:
		var col: Color = _team_color(cap_team)
		var end_angle: float = -PI * 0.5 + TAU * progress
		draw_arc(Vector2(0, -6), RADIUS - 6.0, -PI * 0.5, end_angle, 30, col, 4.0)
	# Big letter label so points read from a distance.
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-6, -46), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.95, 0.9, 0.5))


func _team_color(team: int) -> Color:
	match team:
		1: return Color(0.35, 0.55, 1.0)
		2: return Color(0.85, 0.3, 0.25)
		_: return Color(0.6, 0.6, 0.6)
