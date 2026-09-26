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
	var t := Time.get_ticks_msec() / 1000.0
	var col: Color = _team_color(owner_team)
	var ground := Vector2(0, 30)   # the Area2D hovers 30 px above its floor
	# Floor ring (squashed for a little perspective) with a soft owner glow.
	var pulse := 0.5 + 0.5 * sin(t * 2.2)
	for i in 3:
		_ellipse(ground, Vector2(RADIUS + 6.0 * i + pulse * 3.0, (RADIUS + 6.0 * i) * 0.26), Color(col, 0.16 - 0.04 * i), true)
	_ellipse(ground, Vector2(RADIUS, RADIUS * 0.26), Color(0, 0, 0, 0.7), false)
	# Light column: faint beam up from the ring, stronger when owned.
	var beam_a := 0.10 if owner_team == 0 else 0.18
	draw_colored_polygon(PackedVector2Array([
		ground + Vector2(-RADIUS * 0.55, 0), ground + Vector2(RADIUS * 0.55, 0),
		ground + Vector2(RADIUS * 0.25, -120), ground + Vector2(-RADIUS * 0.25, -120)]),
		Color(col.lightened(0.2), beam_a * (0.7 + 0.3 * pulse)))
	# Pole + pennant in the owner's colour.
	var base := ground + Vector2(0, -2)
	var top := ground + Vector2(0, -74)
	draw_line(base, top, Color(0.2, 0.18, 0.16), 3.0)
	draw_line(base + Vector2(0.8, 0), top + Vector2(0.8, 0), Color(0.7, 0.66, 0.6), 1.0)
	draw_circle(top, 3.0, Color(0.85, 0.68, 0.22))
	var wave := sin(t * 5.0) * 3.0
	draw_colored_polygon(PackedVector2Array([top + Vector2(1, 2), top + Vector2(30, 9 + wave), top + Vector2(1, 18)]), col)
	draw_polyline(PackedVector2Array([top + Vector2(1, 2), top + Vector2(30, 9 + wave), top + Vector2(1, 18)]), Color(0, 0, 0, 0.6), 1.0, true)
	# Capture progress: ring around the letter badge in the capturer's colour.
	var badge := top + Vector2(0, -22)
	draw_circle(badge, 15.0, Color(0.06, 0.07, 0.1, 0.85))
	draw_arc(badge, 15.0, 0.0, TAU, 32, Color(col, 0.9), 2.0)
	if cap_team != 0 and progress > 0.01:
		var ccol: Color = _team_color(cap_team)
		draw_arc(badge, 19.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(progress, 0.0, 1.0), 40, ccol, 4.0, true)
	var font := ThemeDB.fallback_font
	var fs := 18
	var sz := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(font, badge + Vector2(-sz.x * 0.5, sz.y * 0.32), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.92, 0.55))


func _ellipse(c: Vector2, r: Vector2, color: Color, filled: bool) -> void:
	var pts := PackedVector2Array()
	for i in 28:
		var a := TAU * float(i) / 28.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	if filled:
		draw_colored_polygon(pts, color)
	else:
		pts.append(pts[0])
		draw_polyline(pts, color, 1.5, true)


func _team_color(team: int) -> Color:
	match team:
		1: return Color(0.35, 0.55, 1.0)
		2: return Color(0.85, 0.3, 0.25)
		_: return Color(0.6, 0.6, 0.6)
