extends SceneTree
## Movement tech (#262): hold-scaling jump height (tap = short hop, hold =
## full jump — the full jump is exactly the pre-change height) and
## prone-in-air fast fall. Drives the real player with real input.
##   godot --headless -s tools/movement_test.gd

var _t := 0.0
var _phase := 0
var _bad: Array = []
var _log: Array = []
var _player = null
var _y0 := 0.0
var _apex := 0.0
var _hold_apex := 0.0
var _tap_apex := 0.0
var _fall_t := 0.0
var _fall_prone_t := 0.0
var _flying := false


func _process(delta: float) -> bool:
	_t += delta
	if _t > 60.0:
		return _end("timeout phase=%d" % _phase)
	match _phase:
		0:
			var MapIO = load("res://scripts/map_io.gd")
			var m := {"name": "qa_move", "platforms": [], "player_spawn": Vector2(400, 1780),
				"bot_spawns": [Vector2(1200, 1780)]}
			var st := get_root().get_node("Settings")
			st.set("custom_map_path", MapIO.save_to_file("qa_move", m))
			st.set("game_mode", 0)
			st.set("bot_count", 0)
			st.set("vehicles", false)
			get_root().get_node("Net").set_singleplayer()
			change_scene_to_file("res://scenes/main.tscn")
			_phase = 1
			return false
		1:
			var main := current_scene
			if main == null or main.get("MAPS") == null:
				return false
			_player = main.get("player")
			if _player == null or not is_instance_valid(_player):
				return false
			# Settle to the floor first.
			_t = 0.0
			_phase = 2
			return false
		2:
			if _t < 0.8:
				return false
			# FULL JUMP: hold jump for 0.5 s.
			_y0 = (_player as Node2D).global_position.y
			_apex = _y0
			Input.action_press("jump")
			_phase = 3
			_t = 0.0
			return false
		3:
			_apex = minf(_apex, (_player as Node2D).global_position.y)
			if _t >= 0.5:
				Input.action_release("jump")
				_hold_apex = _y0 - _apex
				_phase = 4
				_t = 0.0
			return false
		4:
			# Let it land.
			if _t < 1.2:
				return false
			# TAP JUMP: press ~0.06 s.
			_y0 = (_player as Node2D).global_position.y
			_apex = _y0
			Input.action_press("jump")
			_phase = 5
			_t = 0.0
			return false
		5:
			_apex = minf(_apex, (_player as Node2D).global_position.y)
			if _t >= 0.06:
				Input.action_release("jump")
				_phase = 6
				_t = 0.0
			return false
		6:
			_apex = minf(_apex, (_player as Node2D).global_position.y)
			if _t < 1.2:
				return false
			_tap_apex = _y0 - _apex
			if _tap_apex > _hold_apex * 0.85:
				_bad.append("tap jump nearly as high as held (tap=%d hold=%d) — cut not applied" % [int(_tap_apex), int(_hold_apex)])
			if _tap_apex < _hold_apex * 0.25:
				_bad.append("tap jump too weak (tap=%d hold=%d)" % [int(_tap_apex), int(_hold_apex)])
			_log.append("hold=%dpx tap=%dpx" % [int(_hold_apex), int(_tap_apex)])
			# PRONE FAST FALL: jet up (jets need airborne — jump first), then
			# fall prone vs normal.
			_y0 = (_player as Node2D).global_position.y
			Input.action_press("jump")
			Input.action_press("jet")
			_phase = 7
			_t = 0.0
			return false
		7:
			if _t >= 0.7:
				Input.action_release("jet")
				Input.action_release("jump")
				_flying = true
				_fall_t = 0.0
				_phase = 8
				_t = 0.0
			return false
		8:
			# Normal fall timing.
			if _flying:
				_fall_t += delta
				if (_player as Node2D).global_position.y >= _y0 - 4.0:
					_flying = false
					Input.action_press("prone")   # toggle prone ON
					Input.action_release("prone")
					_phase = 9
					_t = 0.0
			return false
		9:
			# Jet up again (prone is toggled at the apex — jump would stand us up).
			if _t < 0.4:
				return false
			_y0 = (_player as Node2D).global_position.y
			Input.action_press("jump")
			Input.action_press("jet")
			_phase = 10
			_t = 0.0
			return false
		10:
			if _t >= 0.7:
				Input.action_release("jet")
				Input.action_release("jump")
				# Toggle prone now, at the apex, while already falling.
				Input.action_press("prone")
				_flying = true
				_fall_prone_t = 0.0
				_phase = 11
				_t = 0.0
			return false
		11:
			if _flying and _t < 0.05:
				Input.action_release("prone")
			if _flying:
				_fall_prone_t += delta
				if (_player as Node2D).global_position.y >= _y0 - 4.0:
					_flying = false
					if _fall_prone_t > _fall_t * 0.9:
						_bad.append("prone fall not faster (prone=%.2fs normal=%.2fs)" % [_fall_prone_t, _fall_t])
					_log.append("fall normal=%.2fs prone=%.2fs" % [_fall_t, _fall_prone_t])
					return _end("")
			return false
	return false


func _end(fail: String) -> bool:
	if fail != "":
		_bad.append(fail)
	print("MOVE-TEST %s %s | %s" % ["ok" if _bad.is_empty() else "FAIL", str(_bad), " ".join(_log)])
	quit()
	return true
