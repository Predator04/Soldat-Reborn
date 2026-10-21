extends Control
## Bomb Defusal HUD (#304): the fuse countdown, the plant / defuse progress
## bar, the "hold Use" hint, the respawn-wave clock and the between-rounds
## countdown. The status line, banners and off-screen site / bomb arrows are
## objective_hud.gd's (fed by match_bomb.gd). Pure _draw(); reads main._bomb.

const ControlsMap = preload("res://scripts/controls_map.gd")

var main: Node = null
var player_ref: Callable = Callable()
var _t := 0.0


var _use_btn: Button = null   # touch devices: hold to plant / defuse
var _use_down := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_use_btn = Button.new()
	_use_btn.name = "UseButton"
	_use_btn.text = tr("USE")
	_use_btn.focus_mode = Control.FOCUS_NONE
	_use_btn.custom_minimum_size = Vector2(118, 64)
	UITheme.style_button(_use_btn, 20, true)
	_use_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_use_btn.offset_left = 150
	_use_btn.offset_right = 268
	_use_btn.offset_top = -200
	_use_btn.offset_bottom = -136
	_use_btn.visible = false
	# The touch overlay leaves taps on this button to it (limbo-menu rule).
	_use_btn.add_to_group("touch_passthrough")
	_use_btn.button_down.connect(func() -> void: _set_use(true))
	_use_btn.button_up.connect(func() -> void: _set_use(false))
	add_child(_use_btn)


func _set_use(on: bool) -> void:
	if on == _use_down:
		return
	_use_down = on
	if on:
		Input.action_press("use")
	else:
		Input.action_release("use")


func _exit_tree() -> void:
	_set_use(false)


func _process(delta: float) -> void:
	_t += delta
	# Touch USE button: only on touch devices, only while it can do something.
	var want := false
	if main != null and is_instance_valid(main) and main.has_node("TouchControls") and main.get("_bomb") != null:
		var p := _player()
		var b = main._bomb
		want = p != null and (b.use_hint(p) != "" or b.planter == p or b.defuser == p)
	if _use_btn.visible != want:
		_use_btn.visible = want
		if not want:
			_set_use(false)
	queue_redraw()


func _player() -> Node2D:
	if player_ref.is_valid():
		var p = player_ref.call()
		if p != null and is_instance_valid(p) and p is Node2D:
			return p
	return null


func _text_c(font: Font, cx: float, y: float, s: String, fs: int, col: Color, outline := 4) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string_outline(font, Vector2(cx - w * 0.5, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, UITheme.COL_SHADOW)
	draw_string(font, Vector2(cx - w * 0.5, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw() -> void:
	if main == null or not is_instance_valid(main) or main.get("_bomb") == null:
		return
	var b = main._bomb
	if not b.active():
		return
	var p := _player()
	var cx := size.x * 0.5
	var head := UITheme.font("title")
	var caps := UITheme.font("caps")
	if head == null or caps == null:
		return
	# Fuse countdown (planted).
	if str(b.phase) == "planted":
		var ft: float = float(b.fuse_t)
		var urgent := ft < 10.0
		var a := 1.0 if not urgent else 0.6 + 0.4 * sin(_t * 12.0)
		var col := Color(UITheme.COL_ALERT, a)
		_text_c(head, cx, 168.0, tr("BOMB %s  %d") % [str(b.planted_site), int(ceil(ft))], 26, col, 6)
	# Between rounds: next round countdown.
	elif str(b.phase) == "post":
		var res: Dictionary = b.last_result
		var nxt := tr("NEXT ROUND IN %d") % maxi(1, int(ceil(float(b.post_t))))
		if not main.round_active:
			nxt = ""
		if nxt != "":
			_text_c(caps, cx, 168.0, nxt, 16, UITheme.COL_TEXT_DIM, 3)
		if res.has("team") and b.round_no == b.HALF_ROUNDS and not b.swapped:
			_text_c(caps, cx, 188.0, tr("Sides swap at halftime"), 14, UITheme.COL_ACCENT_HI, 3)
	# Respawn wave clock (alive; the death band has its own countdown).
	if p != null and str(b.phase) != "post":
		_text_c(caps, cx, 190.0 if str(b.phase) == "planted" else 168.0,
			tr("NEXT WAVE %d") % maxi(1, int(ceil(float(b.wave_t)))), 12, Color(UITheme.COL_TEXT_DIM, 0.8), 3)
	# Plant / defuse progress (yours, or a teammate's you're spectating near).
	var prog := -1.0
	var label := ""
	if p != null and b.planter == p:
		prog = float(b.plant_prog)
		label = tr("PLANTING")
	elif p != null and b.defuser == p:
		prog = float(b.defuse_prog)
		label = tr("DEFUSING")
	var cy := size.y * 0.5 + 64.0
	if prog >= 0.0:
		var w := 260.0
		var r := Rect2(cx - w * 0.5, cy, w, 12.0)
		draw_rect(r.grow(2.0), Color(0, 0, 0, 0.6))
		draw_rect(r, Color(1, 1, 1, 0.12))
		draw_rect(Rect2(r.position, Vector2(w * clampf(prog, 0.0, 1.0), r.size.y)), UITheme.COL_ACCENT)
		_text_c(caps, cx, cy - 8.0, "%s  %d%%" % [label, int(prog * 100.0)], 15, UITheme.COL_TEXT, 3)
	elif p != null:
		var hint: String = b.use_hint(p)
		if hint != "":
			var key := ControlsMap.primary_label("use")
			var txt := (tr("HOLD %s TO PLANT") if hint == "plant" else tr("HOLD %s TO DEFUSE")) % key
			var a2 := 0.7 + 0.3 * sin(_t * 5.0)
			_text_c(caps, cx, cy + 6.0, txt, 16, Color(UITheme.COL_ACCENT_HI, a2), 3)
