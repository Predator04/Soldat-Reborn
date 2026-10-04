extends PanelContainer
## RadioMenu (v1.18) — Soldat's team radio. V opens it, then two number picks:
## what (enemy flag carrier / friendly flag carrier / enemy spotted) and where
## (up / mid / down). The call goes to your team as a voice line + chat line.
## Team modes only.

const WHAT := [["efc", "Enemy flag carrier"], ["ffc", "Friendly flag carrier"], ["es", "Enemy spotted"]]
const WHERE := [["up", "Up"], ["mid", "Mid"], ["down", "Down"]]
const TIMEOUT := 4.0

var player: Node = null
var _stage := 0
var _what := ""
var _t := 0.0
var _lbl: Label
var _release_pending := false


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UITheme.hud_strip_style())
	# Just under the HP/ammo strip, clear of the edge objective arrows.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = 14
	offset_top = 148
	_lbl = Label.new()
	UITheme.style_hud_label(_lbl, Color(0.75, 0.95, 1.0))
	add_child(_lbl)


static func label_for(code: String) -> String:
	var parts := code.split("_")
	if parts.size() != 2:
		return ""
	var what := ""
	for w in WHAT:
		if w[0] == parts[0]:
			what = w[1]
	var where := ""
	for w in WHERE:
		if w[0] == parts[1]:
			where = str(w[1]).to_lower()
	if what == "" or where == "":
		return ""
	return "%s — %s!" % [what, where]


func is_open() -> bool:
	return visible


func toggle() -> void:
	if visible:
		close()
		return
	if not Settings.is_team_mode():
		return
	if player == null or not is_instance_valid(player) or player.get("dead") == true:
		return
	_stage = 0
	_t = 0.0
	_refresh()
	visible = true
	player.set("radio_open", true)


func close(hold_key := false) -> void:
	visible = false
	# Picked with a number key: keep weapon hotkeys blocked until that key is
	# released, or the held "3" would switch to weapon slot 3 a frame later.
	_release_pending = hold_key
	if not hold_key and player != null and is_instance_valid(player):
		player.set("radio_open", false)


func _refresh() -> void:
	var rows: Array = WHAT if _stage == 0 else WHERE
	var head := tr("RADIO") if _stage == 0 else tr("RADIO") + " · " + tr(_label_of(_what))
	var s := head
	var pad := not Input.get_connected_joypads().is_empty()
	var pad_keys := ["↑", "→", "↓"]
	for i in rows.size():
		s += "\n %s  %s" % [("%d/%s" % [i + 1, pad_keys[i]]) if pad else str(i + 1), tr(rows[i][1])]
	s += "\n " + ("Esc/B" if pad else "Esc") + "  " + tr("cancel")
	_lbl.text = s


func _label_of(code: String) -> String:
	for w in WHAT:
		if w[0] == code:
			return str(w[1])
	return code


func _process(delta: float) -> void:
	if _release_pending and not (Input.is_physical_key_pressed(KEY_1) or Input.is_physical_key_pressed(KEY_2) \
			or Input.is_physical_key_pressed(KEY_3) or Input.is_physical_key_pressed(KEY_KP_1) \
			or Input.is_physical_key_pressed(KEY_KP_2) or Input.is_physical_key_pressed(KEY_KP_3) or _dpad_held()):
		_release_pending = false
		if player != null and is_instance_valid(player):
			player.set("radio_open", false)
	if not visible:
		return
	_t += delta
	if _t > TIMEOUT or player == null or not is_instance_valid(player) or player.get("dead") == true:
		close()


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		var b: int = (event as InputEventJoypadButton).button_index
		if b >= JOY_BUTTON_DPAD_UP and b <= JOY_BUTTON_DPAD_RIGHT:
			if event.pressed:
				_dpad_down[b] = true
			else:
				_dpad_down.erase(b)
	if _release_pending and event is InputEventKey and not event.pressed:
		_release_pending = false
		if player != null and is_instance_valid(player):
			player.set("radio_open", false)
	if not visible:
		return
	# Gamepad: D-pad up / right / down pick 1 / 2 / 3, B cancels.
	if event is InputEventJoypadButton and event.pressed:
		var jb: int = (event as InputEventJoypadButton).button_index
		var jp: int = {JOY_BUTTON_DPAD_UP: 0, JOY_BUTTON_DPAD_RIGHT: 1, JOY_BUTTON_DPAD_DOWN: 2}.get(jb, -1)
		if jb == JOY_BUTTON_B:
			close()
			get_viewport().set_input_as_handled()
		elif jp >= 0:
			get_viewport().set_input_as_handled()
			_choose(jp)
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var kc: int = (event as InputEventKey).physical_keycode
	if kc == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
		return
	var pick := -1
	if kc >= KEY_1 and kc <= KEY_3:
		pick = kc - KEY_1
	elif kc >= KEY_KP_1 and kc <= KEY_KP_3:
		pick = kc - KEY_KP_1
	if pick < 0:
		return
	get_viewport().set_input_as_handled()
	_choose(pick)


var _dpad_down: Dictionary = {}   # D-pad buttons currently held (from events)


func _dpad_held() -> bool:
	return not _dpad_down.is_empty()


func _choose(pick: int) -> void:
	_t = 0.0
	if _stage == 0:
		_what = str(WHAT[pick][0])
		_stage = 1
		_refresh()
		return
	var code := "%s_%s" % [_what, WHERE[pick][0]]
	close(true)
	if player != null and is_instance_valid(player) and player.has_method("send_radio"):
		player.send_radio(code)
