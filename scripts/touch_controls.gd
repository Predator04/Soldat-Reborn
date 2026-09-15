extends Control
## TouchControls — Android on-screen input overlay (issues #116, #117).
##
## Splits the viewport into two halves. Default (#117 conventional layout):
##   • Move half (LEFT by default; RIGHT when Settings.touch_swap is on):
##     dynamic virtual joystick. First touch places the stick center; drag
##     deflection maps to move_left / move_right (horizontal), jump (up), and
##     crouch (down). Deadzone matches the gamepad stick (~0.22).
##   • Aim half (the other side): touch-drag rotates aim_dir, holding the
##     finger fires — Soldat's LMB is a hold-to-fire trigger, so the same
##     touch that starts firing keeps firing until released.
##
## Six edge buttons cover the remaining actions without overlapping the zones:
##   move-side edge : JET (hold), GRENADE (tap), RELOAD (tap)
##   aim-side edge  : SWAP (tap), THROW (tap), PRONE (tap)
##
## Each of those buttons can be dragged to a custom position via edit mode
## (Settings → Controls → "Customize touch layout"). Positions persist in
## Settings.touch_btn_pos and can be cleared via "Reset touch layout".
##
## Only instantiated by main.gd on touch devices (see main._maybe_build_touch_controls);
## desktop KB/M + gamepad paths (#115) are untouched. Every action feeds the
## existing player.gd input paths via Input.action_press / release, so we do
## not build a parallel input pipeline. Aim is read by player.gd through the
## static `instance` handle exposed below.

# Static handle so player.gd can query the current touch aim without a scene
# lookup. Cleared on _exit_tree so a scene reload doesn't leave a dangling ref.
static var instance: Control = null

# Static edit-mode flag. Flipped on from settings_panel.gd; toggled off by the
# in-overlay DONE button. Static so the flag survives the panel dismiss and is
# visible to whichever overlay instance is currently mounted.
static var edit_mode: bool = false

# Layout sizes tuned for a 1280×720 viewport (canvas_items stretch keeps these
# roughly consistent on other resolutions).
const JOY_RADIUS := 110.0
const JOY_KNOB_R := 40.0
const JOY_DEADZONE := 0.22
const BTN_R := 44.0
const BTN_SPACING := 22.0
const BTN_MARGIN := 22.0
const AIM_DEADBAND_PX := 14.0
# Edit-mode controls (DONE / RESET pills at the top of the screen).
const EDIT_PILL_W := 160.0
const EDIT_PILL_H := 44.0

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

# ── Edit-mode state ──────────────────────────────────────────────────────────
# Which button (0..5) is currently being dragged; -1 = none.
var _drag_btn: int = -1
# Touch index owning the drag (so lifting the wrong finger doesn't cancel).
var _drag_touch: int = -1
# Offset from touch point to button center at drag start (so the button doesn't
# snap under the fingertip).
var _drag_offset: Vector2 = Vector2.ZERO
# Touch id owning the DONE / RESET pill (so a stray drag from elsewhere doesn't
# eat the tap).
var _edit_pill_touch: int = -1
var _edit_pill_which: String = ""   # "done" | "reset" | ""

# ── Glass button styleboxes (lazy) ───────────────────────────────────────────
static var _sb_normal: StyleBoxFlat = null
static var _sb_pressed: StyleBoxFlat = null
static var _sb_edit: StyleBoxFlat = null
static var _sb_pill: StyleBoxFlat = null
static var _sb_pill_hi: StyleBoxFlat = null


func _ready() -> void:
	instance = self
	# Static edit_mode survives scene reloads, so reset it here — a stale "true"
	# from a previous match would drop the player straight into layout editing
	# on respawn.
	edit_mode = false
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
	# Default (#117): aim is the RIGHT half (conventional dual-stick). Swap on
	# flips to LEFT for players who preferred the pre-#117 layout.
	if _swap_on():
		return Rect2(0.0, 0.0, vp.x * 0.5, vp.y)
	return Rect2(vp.x * 0.5, 0.0, vp.x * 0.5, vp.y)


func _move_half_rect() -> Rect2:
	var vp: Vector2 = get_viewport_rect().size
	if _swap_on():
		return Rect2(vp.x * 0.5, 0.0, vp.x * 0.5, vp.y)
	return Rect2(0.0, 0.0, vp.x * 0.5, vp.y)


func _is_in_aim_half(p: Vector2) -> bool:
	return _aim_half_rect().has_point(p)


func _default_btn_center(i: int) -> Vector2:
	var b: Dictionary = _buttons[i]
	var side: String = str(b["side"])
	var swap: bool = _swap_on()
	# Default (#117): aim side sits on the RIGHT edge, move side on the LEFT.
	# Swap flips both. Buttons ride the zone they belong to so their placement
	# stays intuitive after a swap.
	var aim_on_right: bool = not swap
	var on_left: bool
	if side == "aim":
		on_left = not aim_on_right
	else:
		on_left = aim_on_right
	var vp: Vector2 = get_viewport_rect().size
	var cx: float = BTN_MARGIN + BTN_R if on_left else vp.x - BTN_MARGIN - BTN_R
	# Index inside the same side (0..2) so buttons stack top-to-bottom.
	var side_idx: int = 0
	for j in range(i):
		if str(_buttons[j]["side"]) == side:
			side_idx += 1
	var cy: float = BTN_MARGIN + BTN_R + float(side_idx) * (BTN_R * 2.0 + BTN_SPACING)
	return Vector2(cx, cy)


func _btn_center(i: int) -> Vector2:
	# Prefer the user's saved position for this action; fall back to the default
	# anchor otherwise. Clamped to the viewport so a resize or rotation can't
	# strand a button off-screen.
	var action: String = str(_buttons[i]["action"])
	var c: Vector2 = _default_btn_center(i)
	if Settings != null and Settings.touch_btn_pos.has(action):
		var v: Variant = Settings.touch_btn_pos[action]
		if v is Vector2:
			c = v
		elif v is Array and (v as Array).size() >= 2:
			c = Vector2(float(v[0]), float(v[1]))
	var vp: Vector2 = get_viewport_rect().size
	c.x = clampf(c.x, BTN_R, vp.x - BTN_R)
	c.y = clampf(c.y, BTN_R, vp.y - BTN_R)
	return c


func _btn_rect(i: int) -> Rect2:
	var c: Vector2 = _btn_center(i)
	return Rect2(c.x - BTN_R, c.y - BTN_R, BTN_R * 2.0, BTN_R * 2.0)


func _button_at(p: Vector2) -> int:
	for i in range(_buttons.size()):
		if _btn_rect(i).has_point(p):
			return i
	return -1


func _edit_pill_rect(which: String) -> Rect2:
	# DONE (left) / RESET (right) pills, top-centre so they don't collide with
	# the standard button columns on the screen edges.
	var vp: Vector2 = get_viewport_rect().size
	var gap: float = 16.0
	var total: float = EDIT_PILL_W * 2.0 + gap
	var x0: float = (vp.x - total) * 0.5
	var y: float = 14.0
	if which == "done":
		return Rect2(x0, y, EDIT_PILL_W, EDIT_PILL_H)
	return Rect2(x0 + EDIT_PILL_W + gap, y, EDIT_PILL_W, EDIT_PILL_H)


func _edit_pill_at(p: Vector2) -> String:
	if _edit_pill_rect("done").has_point(p):
		return "done"
	if _edit_pill_rect("reset").has_point(p):
		return "reset"
	return ""


# ── Input handling ───────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag)


func _on_touch(ev: InputEventScreenTouch) -> void:
	var idx: int = ev.index
	var pos: Vector2 = ev.position
	if edit_mode:
		_on_touch_edit(idx, pos, ev.pressed)
		return
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


func _on_touch_edit(idx: int, pos: Vector2, pressed: bool) -> void:
	# Edit mode never triggers gameplay actions. It only supports:
	#   • drag a button to a new position
	#   • tap DONE (exit edit, save) or RESET (clear custom positions)
	# Aim / joystick zones are inert in this mode so the player can freely place
	# buttons anywhere on screen, including into those zones.
	if pressed:
		var pill: String = _edit_pill_at(pos)
		if pill != "" and _edit_pill_touch < 0:
			_edit_pill_touch = idx
			_edit_pill_which = pill
			get_viewport().set_input_as_handled()
			return
		var bi: int = _button_at(pos)
		if bi >= 0 and _drag_btn < 0:
			_drag_btn = bi
			_drag_touch = idx
			_drag_offset = _btn_center(bi) - pos
			get_viewport().set_input_as_handled()
			return
		return
	# Release
	if idx == _edit_pill_touch:
		var which: String = _edit_pill_which
		_edit_pill_touch = -1
		_edit_pill_which = ""
		# Only trigger if the release is still on top of the same pill (drag-out
		# to cancel, matching every touch UI convention).
		if _edit_pill_at(pos) == which:
			if which == "done":
				edit_mode = false
				if Settings != null:
					Settings.save()
			elif which == "reset":
				if Settings != null:
					Settings.touch_btn_pos = {}
					Settings.save()
		get_viewport().set_input_as_handled()
		return
	if idx == _drag_touch:
		# Persist final position on release. Also handled continuously during
		# the drag (see _on_drag) so an app kill mid-drag still keeps progress.
		if _drag_btn >= 0 and Settings != null:
			var action: String = str(_buttons[_drag_btn]["action"])
			Settings.touch_btn_pos[action] = _btn_center(_drag_btn)
			Settings.save()
		_drag_btn = -1
		_drag_touch = -1
		get_viewport().set_input_as_handled()


func _on_drag(ev: InputEventScreenDrag) -> void:
	var idx: int = ev.index
	if edit_mode:
		if idx == _drag_touch and _drag_btn >= 0 and Settings != null:
			var vp: Vector2 = get_viewport_rect().size
			var c: Vector2 = ev.position + _drag_offset
			c.x = clampf(c.x, BTN_R, vp.x - BTN_R)
			c.y = clampf(c.y, BTN_R, vp.y - BTN_R)
			var action: String = str(_buttons[_drag_btn]["action"])
			Settings.touch_btn_pos[action] = c
			get_viewport().set_input_as_handled()
		return
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

static func _glass_normal() -> StyleBoxFlat:
	if _sb_normal == null:
		var s := StyleBoxFlat.new()
		# Dark semi-transparent glass fill.
		s.bg_color = Color(0.07, 0.09, 0.12, 0.62)
		# Warm amber outline echoes the main menu accent colour without demanding attention.
		s.border_color = Color(0.62, 0.55, 0.32, 0.65)
		s.border_width_left = 1
		s.border_width_right = 1
		s.border_width_top = 1
		s.border_width_bottom = 1
		var rad := 22
		s.corner_radius_top_left = rad
		s.corner_radius_top_right = rad
		s.corner_radius_bottom_left = rad
		s.corner_radius_bottom_right = rad
		# Soft drop shadow gives a sense of depth against a busy battlefield.
		s.shadow_color = Color(0, 0, 0, 0.55)
		s.shadow_size = 4
		s.shadow_offset = Vector2(0, 2)
		_sb_normal = s
	return _sb_normal


static func _glass_pressed() -> StyleBoxFlat:
	if _sb_pressed == null:
		var s := StyleBoxFlat.new()
		# Amber-tinted press state — visibly hot without going neon.
		s.bg_color = Color(0.78, 0.55, 0.18, 0.82)
		s.border_color = Color(1.0, 0.92, 0.62, 0.95)
		s.border_width_left = 2
		s.border_width_right = 2
		s.border_width_top = 2
		s.border_width_bottom = 2
		var rad := 22
		s.corner_radius_top_left = rad
		s.corner_radius_top_right = rad
		s.corner_radius_bottom_left = rad
		s.corner_radius_bottom_right = rad
		s.shadow_color = Color(0, 0, 0, 0.35)
		s.shadow_size = 3
		s.shadow_offset = Vector2(0, 1)
		_sb_pressed = s
	return _sb_pressed


static func _glass_edit() -> StyleBoxFlat:
	if _sb_edit == null:
		var s := StyleBoxFlat.new()
		# Cool blue outline while editing to signal "draggable, not fireable".
		s.bg_color = Color(0.09, 0.13, 0.20, 0.62)
		s.border_color = Color(0.55, 0.85, 1.0, 0.9)
		s.border_width_left = 2
		s.border_width_right = 2
		s.border_width_top = 2
		s.border_width_bottom = 2
		var rad := 22
		s.corner_radius_top_left = rad
		s.corner_radius_top_right = rad
		s.corner_radius_bottom_left = rad
		s.corner_radius_bottom_right = rad
		s.shadow_color = Color(0, 0, 0, 0.55)
		s.shadow_size = 4
		s.shadow_offset = Vector2(0, 2)
		_sb_edit = s
	return _sb_edit


static func _pill_style() -> StyleBoxFlat:
	if _sb_pill == null:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.08, 0.10, 0.13, 0.85)
		s.border_color = Color(0.62, 0.55, 0.32, 0.85)
		s.border_width_left = 1
		s.border_width_right = 1
		s.border_width_top = 1
		s.border_width_bottom = 1
		var rad := 20
		s.corner_radius_top_left = rad
		s.corner_radius_top_right = rad
		s.corner_radius_bottom_left = rad
		s.corner_radius_bottom_right = rad
		s.shadow_color = Color(0, 0, 0, 0.5)
		s.shadow_size = 3
		s.shadow_offset = Vector2(0, 2)
		_sb_pill = s
	return _sb_pill


static func _pill_style_hi() -> StyleBoxFlat:
	if _sb_pill_hi == null:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.78, 0.55, 0.18, 0.92)
		s.border_color = Color(1.0, 0.92, 0.62, 0.95)
		s.border_width_left = 2
		s.border_width_right = 2
		s.border_width_top = 2
		s.border_width_bottom = 2
		var rad := 20
		s.corner_radius_top_left = rad
		s.corner_radius_top_right = rad
		s.corner_radius_bottom_left = rad
		s.corner_radius_bottom_right = rad
		_sb_pill_hi = s
	return _sb_pill_hi


func _draw_button(i: int) -> void:
	var b: Dictionary = _buttons[i]
	var r: Rect2 = _btn_rect(i)
	var held: bool = _btn_touch[i] >= 0
	var style: StyleBoxFlat
	if edit_mode:
		style = _glass_edit()
	elif held:
		style = _glass_pressed()
	else:
		style = _glass_normal()
	style.draw(get_canvas_item(), r)
	# Inner top highlight — 2px band across the top gives a soft "glass" cap.
	# Cheap: single semi-transparent rect, no per-pixel work.
	var hi_alpha: float = 0.18 if not held else 0.32
	var hi_rect := Rect2(r.position + Vector2(6, 4), Vector2(r.size.x - 12, 6))
	draw_rect(hi_rect, Color(1, 1, 1, hi_alpha), true)
	# Label.
	var f: Font = get_theme_default_font()
	var fs: int = 13
	var lbl: String = str(b["label"])
	var sz: Vector2 = f.get_string_size(lbl, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	var c: Vector2 = r.position + r.size * 0.5
	draw_string(f, c + Vector2(-sz.x * 0.5, sz.y * 0.30), lbl,
		HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(1, 1, 1, 0.96))
	# Drag handle "grip" bars in edit mode so the affordance is obvious.
	if edit_mode:
		var gx: float = c.x - 8.0
		var gy: float = c.y + sz.y * 0.55
		for k in range(3):
			draw_rect(Rect2(gx + float(k) * 6.0, gy, 3.0, 3.0),
				Color(0.85, 0.9, 1.0, 0.8), true)


func _draw_edit_pills() -> void:
	# DONE = accent pill; RESET = neutral pill. Both use the shared glass style.
	var f: Font = get_theme_default_font()
	var fs: int = 15
	for which in ["done", "reset"]:
		var r: Rect2 = _edit_pill_rect(String(which))
		var held: bool = _edit_pill_touch >= 0 and _edit_pill_which == String(which)
		var style: StyleBoxFlat = _pill_style_hi() if (held or String(which) == "done") else _pill_style()
		style.draw(get_canvas_item(), r)
		var text: String = "DONE" if String(which) == "done" else "RESET LAYOUT"
		var sz: Vector2 = f.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		var c: Vector2 = r.position + r.size * 0.5
		var col: Color = Color(1, 1, 1, 0.98)
		if String(which) == "done":
			col = Color(0.06, 0.06, 0.08, 0.95)
		draw_string(f, c + Vector2(-sz.x * 0.5, sz.y * 0.30), text,
			HORIZONTAL_ALIGNMENT_CENTER, -1, fs, col)


func _draw_edit_banner() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var f: Font = get_theme_default_font()
	var fs: int = 13
	var s: String = "EDIT MODE — drag buttons; tap DONE to save"
	var sz: Vector2 = f.get_string_size(s, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	var y: float = 14.0 + EDIT_PILL_H + 10.0
	draw_string(f, Vector2((vp.x - sz.x) * 0.5, y + sz.y), s,
		HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(0.85, 0.92, 1.0, 0.9))


func _draw() -> void:
	var vp: Vector2 = get_viewport_rect().size
	# Faint zone tint so the layout reads at a glance without dominating the
	# game view. Aim = cool blue, move = warm amber (matches Soldat's HUD
	# accent). Alpha is tiny — visible on flat backgrounds, invisible on busy
	# terrain. Edit mode dims the game a touch more so buttons pop.
	var aim_r: Rect2 = _aim_half_rect()
	var mv_r: Rect2 = _move_half_rect()
	if edit_mode:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.35), true)
	else:
		draw_rect(aim_r, Color(0.35, 0.6, 1.0, 0.035), true)
		draw_rect(mv_r, Color(1.0, 0.75, 0.25, 0.035), true)
		draw_line(Vector2(vp.x * 0.5, 0.0), Vector2(vp.x * 0.5, vp.y), Color(1, 1, 1, 0.06), 1.0)
	# Buttons
	for i in range(_buttons.size()):
		_draw_button(i)
	# Joystick (only when active, and only in gameplay mode)
	if not edit_mode and _joy_touch >= 0:
		draw_arc(_joy_center, JOY_RADIUS, 0.0, TAU, 40, Color(1, 1, 1, 0.28), 2.0, true)
		var knob: Vector2 = _joy_center + _joy_vec * JOY_RADIUS
		draw_circle(knob, JOY_KNOB_R, Color(1.0, 0.82, 0.32, 0.6))
		draw_arc(knob, JOY_KNOB_R, 0.0, TAU, 24, Color(1, 0.95, 0.7, 0.9), 2.0, true)
	# Fire touch marker — subtle so it doesn't fight the crosshair.
	if not edit_mode and _aim_touch >= 0:
		draw_arc(_aim_origin, 22.0, 0.0, TAU, 24, Color(1, 0.5, 0.4, 0.6), 2.0, true)
		if _aim_origin.distance_to(_aim_pos) > AIM_DEADBAND_PX:
			draw_line(_aim_origin, _aim_pos, Color(1, 0.55, 0.4, 0.55), 2.0)
			draw_circle(_aim_pos, 8.0, Color(1, 0.6, 0.4, 0.7))
	if edit_mode:
		_draw_edit_pills()
		_draw_edit_banner()
