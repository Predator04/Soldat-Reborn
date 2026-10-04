extends SceneTree
## End-of-round map vote (gate stage F): the winner screen offers three other
## maps, pressing 2 votes for the second, and the next round loads it. With no
## votes the same map continues.
##   godot --headless -s tools/mapvote_test.gd

var _n := 0
var _st := 0
var _t := 0
var _saved := []
var _want := -1
var _first_map := -1
var _log: Array = []


func _key(kc: int) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = kc
		e.keycode = kc
		e.pressed = down
		Input.parse_input_event(e)


func _process(_d: float) -> bool:
	_n += 1
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _st == 0:
		_saved = [st.bot_count, st.game_mode, st.map_index, st.custom_map_path]
		st.bot_count = 0
		st.game_mode = 0
		st.map_index = 19
		st.custom_map_path = ""
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		_st = 1
		return false
	var m = current_scene
	if m == null or m.get("next_map_choices") == null:
		return false
	match _st:
		1:
			if _n < 40:
				return false
			_first_map = m.cur_map_index
			# Round 1 ends with no votes: same map again.
			m._end_round(-1)
			if m.next_map_choices.size() != 3 or m.next_map_choices.has(_first_map):
				return _end(false, "choices %s (current %d)" % [str(m.next_map_choices), _first_map])
			if m.hud.next_map_panel == null:
				m.hud._process(0.016)
			m.winner_end_t = 0.05
			_t = _n
			_st = 2
		2:
			if _n - _t < 20:
				return false
			if not m.round_active or m.cur_map_index != _first_map:
				return _end(false, "no-vote round didn't restart on the same map")
			_log.append("no votes -> same map")
			m._end_round(-1)
			_want = int(m.next_map_choices[1])
			_t = _n
			_st = 3
		3:
			if _n - _t < 3:
				return false
			var panel_ok: bool = m.hud.next_map_panel != null and m.hud.next_map_panel.visible
			_log.append("panel=%s" % str(panel_ok))
			if not panel_ok:
				return _end(false, "vote panel not shown")
			_key(KEY_2)
			_t = _n
			_st = 4
		4:
			if _n - _t < 5:
				return false
			if int(m.my_next_map_vote) != 1 or int(m.next_map_tally[1]) != 1:
				return _end(false, "vote not counted: mine=%d tally=%s" % [int(m.my_next_map_vote), str(m.next_map_tally)])
			_log.append("voted %s" % m.next_map_name(1))
			m.winner_end_t = 0.05
			_t = _n
			_st = 5
		5:
			if m.cur_map_index == _want and m.round_active and _n - _t > 30:
				return _end(true, " | ".join(_log) + " | loaded map %d" % _want)
			if _n - _t > 600:
				return _end(false, "map %d never loaded (now %d)" % [_want, m.cur_map_index])
	return false


func _end(ok: bool, msg: String) -> bool:
	var st = root.get_node("Settings")
	st.bot_count = _saved[0]; st.game_mode = _saved[1]; st.map_index = _saved[2]; st.custom_map_path = _saved[3]
	st.save()
	print("MAPVOTE-TEST %s %s" % ["ok" if ok else "FAIL", msg])
	quit(0 if ok else 1)
	return true
