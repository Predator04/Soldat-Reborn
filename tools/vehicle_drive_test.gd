extends SceneTree
## Bot driver check (gate stage F).
##   godot --headless --fixed-fps 60 -s tools/vehicle_drive_test.gd
## Team deathmatch on a long flat range: a bot whose target is far away
## takes the empty buggy next to it, drives it most of the way there, and
## gets out near the destination.

const RANGE_Y := 1900.0

var _phase := 0
var _t := 0.0
var _st := 0
var _st_t := 0.0
var _log: Array = []
var _car: Node = null
var _mate: Node = null
var _foe: Node = null
var _x0 := 0.0
var _xmax := 0.0


func _fail(msg: String) -> bool:
	print("DRIVE-TEST FAIL %s | %s" % [msg, " ".join(_log)])
	quit()
	return true


func _process(d: float) -> bool:
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _phase == 0:
		var MapIO = load("res://scripts/map_io.gd")
		var m := {"name": "qa_botdrive", "platforms": [], "player_spawn": Vector2(200, RANGE_Y - 20),
			"bot_spawns": [Vector2(700, RANGE_Y - 20), Vector2(4300, RANGE_Y - 20)], "vehicle_spawns": [Vector2(820, RANGE_Y)]}
		st.set("custom_map_path", MapIO.save_to_file("qa_botdrive", m))
		st.set("game_mode", 1); st.set("bot_count", 2); st.set("vehicles", true); st.set("bot_skill", 3)
		st.set("survival", false); st.set("realistic", false); st.set("advance", false)
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		_phase = 1
		return false
	var m = current_scene
	if m == null or m.get("MAPS") == null:
		return false
	_t += d
	_st_t += d
	if _t > 70.0:
		return _fail("timeout st=%d" % _st)
	var p = m.get("player")
	if _t < 1.0 or p == null or not is_instance_valid(p):
		return false
	# The human stays out of it.
	p.set_physics_process(false)
	p.global_position = Vector2(150, RANGE_Y - 20)
	match _st:
		0:
			for v in get_nodes_in_group("vehicle"):
				_car = v
			for s in get_nodes_in_group("soldier"):
				if s.get("bot_id") != null:
					if int(s.get("team")) == int(p.get("team")):
						_mate = s
					else:
						_foe = s
			if _car == null or _mate == null or _foe == null:
				return _fail("setup")
			_foe.set_physics_process(false)
			_foe.set_process(false)
			_foe.global_position = Vector2(4400, RANGE_Y - 20)
			_foe.set("health", 5000.0)
			_mate.global_position = Vector2(700, RANGE_Y - 20)
			_st = 1
			_st_t = 0.0
		1:
			_mate.set("target", _foe)
			if _car.driver() == _mate:
				_x0 = (_car as Node2D).global_position.x
				_log.append("boarded %.1fs" % _st_t)
				_st = 2
				_st_t = 0.0
			elif _st_t > 10.0:
				return _fail("bot never took the driver's seat (goal=%s %s)" % [_mate.get("_goal_label"), _mate.get("_goal")])
		2:
			_mate.set("target", _foe)
			_foe.set("health", 5000.0)
			_xmax = maxf(_xmax, (_car as Node2D).global_position.x)
			if _car.driver() != _mate:
				var drove: float = _xmax - _x0
				var left: float = absf(4400.0 - (_car as Node2D).global_position.x)
				_log.append("drove %dpx, got out %dpx from the target after %.1fs" % [drove, left, _st_t])
				var ok: bool = drove > 1800.0 and left < 900.0
				print("DRIVE-TEST %s | %s" % ["ok" if ok else "FAIL", " ".join(_log)])
				quit()
				return true
			elif _st_t > 25.0:
				return _fail("still driving after 25 s (x=%d)" % (_car as Node2D).global_position.x)
	return false
