extends Control
## TouchControls — Android on-screen input overlay (issue #116).
##
## Splits the viewport into two halves:
##   • Aim half (LEFT by default; RIGHT when Settings.touch_swap is on):
##     touch-drag rotates aim_dir, holding the finger fires — Soldat's LMB is
##     a hold-to-fire trigger, so the same touch that starts firing keeps
##     firing until released.
##   • Move half (the other side): dynamic virtual joystick. First touch
##     places the stick center, drag deflection maps to move_left / move_right
##     (horizontal), jump (up), and crouch (down). Deadzone matches the feel
##     of the gamepad stick (~0.22).
##
## Six edge buttons cover the remaining actions without overlapping the zones:
##   move-side edge : JET (hold), GRENADE (tap), RELOAD (tap)
##   aim-side edge  : SWAP (tap), THROW (tap), PRONE (tap)
##
## Only instantiated by main.gd on touch devices (see main._maybe_build_touch_controls);
## desktop KB/M + gamepad paths (#115) are untouched. Every action feeds the
## existing player.gd input paths via Input.action_press / release, so we do
## not build a parallel input pipeline. Aim is read by player.gd through the
## static `instance` handle exposed below.

# Static handle so player.gd can query the current touch aim without a scene
# lookup. Cleared on _exit_tree so a scene reload doesn't leave a dangling ref.
static var instance: Control = null

# Layout sizes tuned for a 1280×720 viewport (canvas_items stretch keeps these
# roughly consistent on other resolutions).
const JOY_RADIUS := 110.0
const JOY_KNOB_R := 40.0
const JOY_DEADZONE := 0.22
const BTN_R := 44.0
const BTN_SPACING := 22.0
const BTN_MARGIN := 22.0
const AIM_DEADBAND_PX := 14.0

# ── Public state (read by player.gd) ─────────────────────────────────────────
var aim_dir: Vector2 = Vector2.RIGHT
var aim_active: bool = false


# ── Movement joystick (dynamic origin) ────────────────────────────────────────
var _joy_touch: int = -1
var _joy_center: Vector2 = Vector2.ZERO
var _joy_pos: Vector2 = Vector2.ZERO
var _joy_vec: Vector2 = Vector2.ZERO   # -1..1 both axes after deadzone remap

# ── Aim / fire drag (dynamic origin, matches Soldat's mouse-look feel) ───────
var _aim_touch: int = -1
var _aim_origin: Vector2 = Vector2.ZERO
var _aim_pos: Vector2 = Vector2.ZERO

# ── Edge buttons ─────────────────────────────────────────────────────────────
# Each entry mutates in-place — Godot Dictionary keys are stable, so mutating
# through _buttons[i]["touch"] = ... would need a copy-back; we keep touch id in
# a parallel array to keep the code short.
var _buttons: Array = [
	{"action": "jet",             "hold": true,  "label": "JET",     "side": "move"},
	{"action": "grenade",         "hold": false, "label": "GRENADE", "side": "move"},
	{"action": "reload",          "hold": false, "label": "RELOAD",  "side": "move"},
	{"action": "secondary_swap",  "hold": false, "label": "SWAP",    "side": "aim"},
	{"action": "weapon_throw",    "hold": false, "label": "THROW",   "side": "aim"},
	{"action": "prone",           "hold": false, "label": "PRONE",   "side": "aim"},
]
var _btn_touch: Array = [-1, -1, -1, -1, -1, -1]

# Actions we're currently virtually pressing. Guards against double-press /
# leak on exit — cleared on _exit_tree.
var _pressed_actions: Dictionary = {}


func _ready() -> void:
	instance = self
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Overlay doesn't want to intercept mouse hover / GUI focus, only raw touch
	# and screen-drag events routed through _input. Ignore keeps HUD widgets
	# below (chat LineEdit, etc.) still receiving their events.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()


func _exit_tree() -> void:
	# Release every virtual press so the game doesn't wedge an action stuck.
	for k in _pressed_actions.keys():
		if bool(_pressed_actions[k]) and InputMap.has_action(str(k)):
			Input.action_release(str(k))
	_pressed_actions.clear()
	if instance == self:
		instance = null


# ── Layout helpers ───────────────────────────────────────────────────────────

func _swap_on() -> bool:
	return Settings != null and bool(Settings.touch_swap)


func _aim_half_rect() -> Rect2:
	var vp: Vector2 = get_viewport_rect().size
	# Default: aim is the LEFT half. Swap flips to RIGHT.
	if _swap_on():
		return Rect2(vp.x * 0.5, 0.0, vp.x * 0.5, vp.y)
	return Rect2(0.0, 0.0, vp.x * 0.5, vp.y)


func _move_half_rect() -> Rect2:
	var vp: Vector2 = get_viewport_rect().size
	if _swap_on():
		return Rect2(0.0, 0.0, vp.x * 0.5, vp.y)
	return Rect2(vp.x * 0.5, 0.0, vp.x * 0.5, vp.y)


func _is_in_aim_half(p: Vector2) -> bool:
	return _aim_half_rect().has_point(p)


func _btn_rect(i: int) -> Rect2:
	var b: Dictionary = _buttons[i]
	var side: String = str(b["side"])
	var swap: bool = _swap_on()
	# aim side sits on LEFT edge unless swapped; move side on RIGHT edge unless
	# swapped. Buttons ride the zone they belong to so their placement stays
	# intuitive (aim-related buttons near the aim thumb, jet/reload near the
	# move thumb) after a swap.
	var aim_on_left: bool = not swap
	var on_left: bool
	if side == "aim":
		on_left = aim_on_left
	else:
		on_left = not aim_on_left
	var vp: Vector2 = get_viewport_rect().size
	var cx: float = BTN_MARGIN + BTN_R if on_left else vp.x - BTN_MARGIN - BTN_R
	# Index inside the same side (0..2) so buttons stack top-to-bottom.
	var side_idx: int = 0
	for j in range(i):
		if str(_buttons[j]["side"]) == side:
			side_idx += 1
	var cy: float = BTN_MARGIN + BTN_R + float(side_idx) * (BTN_R * 2.0 + BTN_SPACING)
	return Rect2(cx - BTN_R, cy - BTN_R, BTN_R * 2.0, BTN_R * 2.0)


func _button_at(p: Vector2) -> int:
	for i in range(_buttons.size()):
		if _btn_rect(i).has_point(p):
			return i
	return -1


# ── Input handling ───────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag)


func _on_touch(ev: InputEventScreenTouch) -> void:
	var idx: int = ev.index
	var pos: Vector2 = ev.position
	if ev.pressed:
		# Priority: buttons > zones. Buttons are small so this rarely conflicts.
		var bi: int = _button_at(pos)
		if bi >= 0 and _btn_touch[bi] < 0:
			_btn_touch[bi] = idx
			_press_action(str(_buttons[bi]["action"]))
			get_viewport().set_input_as_handled()
			return
		if _is_in_aim_half(pos):
			if _aim_touch < 0:
				_aim_touch = idx
				_aim_origin = pos
				_aim_pos = pos
				aim_active = true
				# Hold-to-fire: pressing the aim zone starts firing right away
				# and keeps firing until the finger lifts. Aim direction only
				# changes once the finger drags past AIM_DEADBAND_PX so a
				# stationary tap doesn't jerk the crosshair.
				_press_action("fire")
				get_viewport().set_input_as_handled()
		else:
			if _joy_touch < 0:
				_joy_touch = idx
				_joy_center = pos
				_joy_pos = pos
				_joy_vec = Vector2.ZERO
				get_viewport().set_input_as_handled()
		return
	# Release
	if idx == _aim_touch:
		_aim_touch = -1
		aim_active = false
		_release_action("fire")
		get_viewport().set_input_as_handled()
		return
	if idx == _joy_touch:
		_joy_touch = -1
		_joy_vec = Vector2.ZERO
		_release_action("move_left")
		_release_action("move_right")
		_release_action("jump")
		_release_action("crouch")
		get_viewport().set_input_as_handled()
		return
	for i in range(_buttons.size()):
		if _btn_touch[i] == idx:
			_btn_touch[i] = -1
			_release_action(str(_buttons[i]["action"]))
			get_viewport().set_input_as_handled()
			return


func _on_drag(ev: InputEventScreenDrag) -> void:
	var idx: int = ev.index
	if idx == _aim_touch:
		_aim_pos = ev.position
		var d: Vector2 = _aim_pos - _aim_origin
		if d.length() > AIM_DEADBAND_PX:
			aim_dir = d.normalized()
		get_viewport().set_input_as_handled()
		return
	if idx == _joy_touch:
		_joy_pos = ev.position
		var raw: Vector2 = _joy_pos - _joy_center
		var r: float = raw.length()
		if r <= 0.001:
			_joy_vec = Vector2.ZERO
		else:
			var clamped_r: float = minf(r, JOY_RADIUS)
			var t: float = clamped_r / JOY_RADIUS
			if t < JOY_DEADZONE:
				_joy_vec = Vector2.ZERO
			else:
				# Remap [deadzone .. 1] → [0 .. 1] so past-deadzone response
				# still spans the full range instead of feeling truncated.
				var s: float = (t - JOY_DEADZONE) / (1.0 - JOY_DEADZONE)
				_joy_vec = raw.normalized() * s
		_apply_joy_actions()
		get_viewport().set_input_as_handled()


func _apply_joy_actions() -> void:
	var v: Vector2 = _joy_vec
	# Horizontal → walk. 0.35 threshold matches feel of a keyboard tap (short
	# lateral flick shouldn't start moving) without being harder than the
	# gamepad's ~0.2 aim deadzone.
	if v.x < -0.35:
		_press_action("move_left"); _release_action("move_right")
	elif v.x > 0.35:
		_press_action("move_right"); _release_action("move_left")
	else:
		_release_action("move_left"); _release_action("move_right")
	# Vertical → jump (up) / crouch (down). Y is screen-down positive so up on
	# screen = negative y = jump. Player.gd's own jump_buffer + coyote logic
	# ensures a held-up joystick only jumps once per takeoff.
	if v.y < -0.4:
		_press_action("jump"); _release_action("crouch")
	elif v.y > 0.4:
		_press_action("crouch"); _release_action("jump")
	else:
		_release_action("jump"); _release_action("crouch")


func _press_action(action: String) -> void:
	if not InputMap.has_action(action):
		return
	if bool(_pressed_actions.get(action, false)):
		return
	Input.action_press(action)
	_pressed_actions[action] = true


func _release_action(action: String) -> void:
	if not InputMap.has_action(action):
		return
	if not bool(_pressed_actions.get(action, false)):
		return
	Input.action_release(action)
	_pressed_actions[action] = false


# ── Draw ─────────────────────────────────────────────────────────────────────

func _draw() -> void:
	var vp: Vector2 = get_viewport_rect().size
	# Faint zone tint so the layout reads at a glance without dominating the
	# game view. Aim = cool blue, move = warm amber (matches Soldat's HUD
	# accent). Alpha is tiny — visible on flat backgrounds, invisible on busy
	# terrain.
	var aim_r: Rect2 = _aim_half_rect()
	var mv_r: Rect2 = _move_half_rect()
	draw_rect(aim_r, Color(0.35, 0.6, 1.0, 0.035), true)
	draw_rect(mv_r, Color(1.0, 0.75, 0.25, 0.035), true)
	draw_line(Vector2(vp.x * 0.5, 0.0), Vector2(vp.x * 0.5, vp.y), Color(1, 1, 1, 0.06), 1.0)
	# Buttons
	var f: Font = get_theme_default_font()
	var fs: int = 13
	for i in range(_buttons.size()):
		var b: Dictionary = _buttons[i]
		var r: Rect2 = _btn_rect(i)
		var c: Vector2 = r.position + r.size * 0.5
		var held: bool = _btn_touch[i] >= 0
		var bg: Color = Color(0.85, 0.65, 0.25, 0.72) if held else Color(0.12, 0.13, 0.16, 0.55)
		var edge: Color = Color(1, 0.95, 0.7, 0.9) if held else Color(0.8, 0.75, 0.45, 0.7)
		draw_circle(c, BTN_R, bg)
		draw_arc(c, BTN_R, 0.0, TAU, 28, edge, 2.0, true)
		var lbl: String = str(b["label"])
		var sz: Vector2 = f.get_string_size(lbl, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(f, c + Vector2(-sz.x * 0.5, sz.y * 0.25), lbl,
			HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(1, 1, 1, 0.95))
	# Joystick (only when active)
	if _joy_touch >= 0:
		draw_arc(_joy_center, JOY_RADIUS, 0.0, TAU, 40, Color(1, 1, 1, 0.28), 2.0, true)
		var knob: Vector2 = _joy_center + _joy_vec * JOY_RADIUS
		draw_circle(knob, JOY_KNOB_R, Color(1.0, 0.82, 0.32, 0.6))
		draw_arc(knob, JOY_KNOB_R, 0.0, TAU, 24, Color(1, 0.95, 0.7, 0.9), 2.0, true)
	# Fire touch marker — subtle so it doesn't fight the crosshair.
	if _aim_touch >= 0:
		draw_arc(_aim_origin, 22.0, 0.0, TAU, 24, Color(1, 0.5, 0.4, 0.6), 2.0, true)
		if _aim_origin.distance_to(_aim_pos) > AIM_DEADBAND_PX:
			draw_line(_aim_origin, _aim_pos, Color(1, 0.55, 0.4, 0.55), 2.0)
			draw_circle(_aim_pos, 8.0, Color(1, 0.6, 0.4, 0.7))
