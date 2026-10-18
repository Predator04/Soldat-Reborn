extends Control
## Top-centre HUD strip (graphics Phase C, #272): a glass card behind the mode
## line, the round timer, the objective status line and — in team modes — two
## team-coloured score blocks flanking the timer. Colours come from
## hud._team_display_info, so the colour-blind team option applies. A block
## flashes briefly when its score goes up.

const UITheme = preload("res://scripts/ui_theme.gd")
const W := 540.0
const BLOCK_W := 150.0

var hud: Node = null
var _teams: Array = []      # [[name, colour, points], [..]] or empty
var _flash := [0.0, 0.0]
var _last := [-1, -1]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func has_teams() -> bool:
	return not _teams.is_empty()


func set_teams(t: Array) -> void:
	for i in mini(t.size(), 2):
		var pts := int(t[i][2])
		if _last[i] >= 0 and pts > _last[i]:
			_flash[i] = 1.0
		_last[i] = pts
	if t != _teams:
		_teams = t
		queue_redraw()


func _process(delta: float) -> void:
	# Keep the objective status line tucked under the strip's content.
	var oh: Node = hud.get("objective_hud") if hud != null else null
	var st: Control = oh.get("_status") if oh != null else null
	if st != null:
		var top := 82.0 if has_teams() else 108.0
		if st.offset_top != top:
			st.offset_top = top
			st.offset_bottom = top + 24.0
	if _flash[0] > 0.0 or _flash[1] > 0.0:
		_flash[0] = maxf(0.0, _flash[0] - delta * 1.6)
		_flash[1] = maxf(0.0, _flash[1] - delta * 1.6)
		queue_redraw()
	elif Engine.get_process_frames() % 10 == 0:
		queue_redraw()


func _bottom() -> float:
	var b := 80.0 if has_teams() else 106.0
	var oh: Node = hud.get("objective_hud") if hud != null else null
	var st: RichTextLabel = oh.get("_status") if oh != null else null
	if st != null and st.visible and str(st.text).strip_edges() != "":
		b += 28.0
	return b


func _draw() -> void:
	var cx := size.x * 0.5
	var rect := Rect2(cx - W * 0.5, 4.0, W, _bottom() - 4.0)
	var sb := UITheme.hud_strip_style()
	draw_style_box(sb, rect)
	if not has_teams():
		return
	var font := UITheme.font("caps")
	var num := UITheme.font("hud")
	for i in 2:
		var name: String = str(_teams[i][0])
		var col: Color = _teams[i][1]
		var pts: int = int(_teams[i][2])
		var left := i == 0
		var bx := cx - 60.0 - BLOCK_W if left else cx + 60.0
		var r := Rect2(bx, 36.0, BLOCK_W, 38.0)
		var fill := Color(col, 0.16 + 0.3 * float(_flash[i]))
		var box := UITheme._flat(fill, 5)
		draw_style_box(box, r)
		# Solid team edge on the outer side.
		draw_rect(Rect2(r.position.x if left else r.end.x - 3.0, r.position.y, 3.0, r.size.y), col)
		var ptxt := str(pts)
		var pw: float = num.get_string_size(ptxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		var nw: float = font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var base := r.position.y + 29.0
		if left:
			draw_string(font, Vector2(r.position.x + 12.0, base - 4.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col.lightened(0.25))
			draw_string_outline(num, Vector2(r.end.x - 12.0 - pw, base + 2.0), ptxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, 4, Color(0, 0, 0, 0.6))
			draw_string(num, Vector2(r.end.x - 12.0 - pw, base + 2.0), ptxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UITheme.COL_TEXT)
		else:
			draw_string(font, Vector2(r.end.x - 12.0 - nw, base - 4.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col.lightened(0.25))
			draw_string_outline(num, Vector2(r.position.x + 12.0, base + 2.0), ptxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, 4, Color(0, 0, 0, 0.6))
			draw_string(num, Vector2(r.position.x + 12.0, base + 2.0), ptxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UITheme.COL_TEXT)
