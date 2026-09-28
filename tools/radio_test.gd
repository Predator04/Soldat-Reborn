extends SceneTree
## Team radio check (gate stage F).
##   godot --headless --fixed-fps 60 -s tools/radio_test.gd
## Presses V, 2, 3 (friendly flag carrier — down) as the player and checks the
## call lands in the chat feed with its voice line and without switching
## weapons; then waits for a bot to call out an enemy flag carrier.

var _t := 0.0
var _phase := 0
var _step := 0
var _w0 := -1
var _log: Array = []


func _key(kc: int) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = kc
		e.keycode = kc
		e.pressed = down
		Input.parse_input_event(e)


func _process(d: float) -> bool:
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _phase == 0:
		st.set("custom_map_path", ""); st.set("map_index", 0); st.set("game_mode", 2)
		st.set("bot_count", 6); st.set("bot_skill", 3); st.set("sfx_volume", 0.8)
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		_phase = 1
		return false
	var m = current_scene
	if m == null or m.get("MAPS") == null or m.get("hud") == null:
		return false
	_t += d
	var p = m.get("player")
	if _t > 150.0:
		print("RADIO-TEST FAIL timeout step=%d %s" % [_step, " ".join(_log)])
		quit()
		return true
	if _t < 2.0 or p == null or not is_instance_valid(p):
		return false
	match _step:
		0:
			_w0 = int(p.get("weapon_index"))
			_key(KEY_V)
			_step = 1
		1:
			if p.get("radio_open") == true:
				_log.append("menu")
				_key(KEY_2)
				_step = 2
		2:
			_key(KEY_3)
			_step = 3
		3:
			var feed = m.hud.get("chat_feed")
			var said := false
			for c in feed.get_children():
				if c is Label and str(c.text).contains("(RADIO)") and str(c.text).contains("Friendly flag carrier — down"):
					said = true
			var voiced: int = int(root.get_node("Sfx").play_counts.get("radio/ffcdown", 0))
			if said and voiced > 0:
				_log.append("player-call")
				if int(p.get("weapon_index")) != _w0 or p.get("radio_open") == true:
					print("RADIO-TEST FAIL weapon switched or menu stuck")
					quit()
					return true
				_step = 4
				m.set("radio_count", 0)
			elif _t > 10.0:
				print("RADIO-TEST FAIL no player call said=%s voiced=%d" % [said, voiced])
				quit()
				return true
		4:
			if int(m.get("radio_count")) > 0:
				_log.append("bot-call@%.0fs" % _t)
				print("RADIO-TEST ok %s" % " ".join(_log))
				quit()
				return true
	return false
