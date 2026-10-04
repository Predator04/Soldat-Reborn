extends SceneTree
## Gamepad (gate stage F): radio callouts with L3 + D-pad (and the held D-pad
## doesn't switch weapons afterwards), and the limbo loadout picker with the
## D-pad.
##   godot --headless -s tools/pad_test.gd

var _n := 0
var _st := 0
var _t := 0
var _saved := []
var _bad: Array = []
var _log: Array = []
var _w0 := 0
var _pri0 := 0
var _sec0 := 0


func _btn(b: int, down: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = b
	e.pressed = down
	Input.parse_input_event(e)


func _process(_d: float) -> bool:
	_n += 1
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _st == 0:
		_saved = [st.bot_count, st.game_mode, st.map_index, st.custom_map_path, st.spawn_primary, st.spawn_secondary]
		st.bot_count = 0
		st.game_mode = 1   # TDM: radio works
		st.map_index = 19
		st.custom_map_path = ""
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		_st = 1
		return false
	var m = current_scene
	if m == null or m.get("hud") == null or m.hud == null:
		return false
	var p = m.player
	match _st:
		1:
			if _n < 60 or p == null or not is_instance_valid(p):
				return false
			_w0 = int(p.weapon_index)
			_btn(JOY_BUTTON_LEFT_STICK, true)
			_t = _n
			_st = 2
		2:
			if _n - _t < 3:
				return false
			_btn(JOY_BUTTON_LEFT_STICK, false)
			if not m.hud.radio_menu.is_open():
				return _end(false, "L3 didn't open the radio (events=%s team_mode=%s)" % [str(InputMap.action_get_events("radio")), str(st.is_team_mode())])
			_btn(JOY_BUTTON_DPAD_UP, true)     # 1: enemy flag carrier
			_t = _n
			_st = 3
		3:
			if _n - _t < 3:
				return false
			_btn(JOY_BUTTON_DPAD_UP, false)
			_btn(JOY_BUTTON_DPAD_DOWN, true)   # 3: down — D-pad Down is weapon slot 3 too
			_t = _n
			_st = 4
		4:
			if _n - _t < 20:
				return false
			_log.append("radio_count=%d" % int(m.radio_count))
			if int(m.radio_count) < 1:
				_bad.append("radio call not sent")
			if int(p.weapon_index) != _w0:
				_bad.append("held D-pad switched weapon %d -> %d" % [_w0, int(p.weapon_index)])
			_btn(JOY_BUTTON_DPAD_DOWN, false)
			# Limbo loadout picker: die, then D-pad down / right.
			p.ceasefire_t = 0.0
			p.take_damage(999.0, "", "", -1)
			_t = _n
			_st = 5
		5:
			if _n - _t < 20:
				return false
			_pri0 = st.spawn_primary
			_sec0 = st.spawn_secondary
			if not m.hud.weapon_menu.visible if m.hud.get("weapon_menu") != null else false:
				_bad.append("limbo menu not visible")
			_btn(JOY_BUTTON_DPAD_DOWN, true)
			_btn(JOY_BUTTON_DPAD_RIGHT, true)
			_t = _n
			_st = 6
		6:
			if _n - _t < 3:
				return false
			_btn(JOY_BUTTON_DPAD_DOWN, false)
			_btn(JOY_BUTTON_DPAD_RIGHT, false)
			_log.append("primary %d->%d secondary %d->%d" % [_pri0, st.spawn_primary, _sec0, st.spawn_secondary])
			if st.spawn_primary == _pri0:
				_bad.append("D-pad down didn't change the primary")
			if st.spawn_secondary == _sec0:
				_bad.append("D-pad right didn't change the secondary")
			return _end(_bad.is_empty(), " ".join(_log))
	return false


func _end(ok: bool, msg: String) -> bool:
	var st = root.get_node("Settings")
	st.bot_count = _saved[0]; st.game_mode = _saved[1]; st.map_index = _saved[2]; st.custom_map_path = _saved[3]
	st.spawn_primary = _saved[4]; st.spawn_secondary = _saved[5]
	st.save()
	print("PAD-TEST %s %s %s" % ["ok" if ok else "FAIL", str(_bad), msg])
	quit(0 if ok else 1)
	return true
