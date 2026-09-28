extends SceneTree
## Buggy crew check (gate stage F).
##   godot --headless --fixed-fps 60 -s tools/vehicle_crew_test.gd
## Team deathmatch on a flat range: a lone driver who fires is held to half
## speed; a teammate bot walks up and takes the gun seat; the bot gunner
## shoots an enemy; when the driver gets out, the bot gets out too.

const RANGE_Y := 1900.0

var _phase := 0
var _t := 0.0
var _st := 0
var _st_t := 0.0
var _log: Array = []
var _bad: Array = []
var _car: Node = null
var _mate: Node = null
var _foe: Node = null
var _vmax := 0.0


func _fail(msg: String) -> bool:
	print("CREW-TEST FAIL %s | %s" % [msg, " ".join(_log)])
	quit()
	return true


func _freeze(b: Node, on: bool) -> void:
	b.set_physics_process(not on)
	b.set_process(not on)


func _process(d: float) -> bool:
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _phase == 0:
		var MapIO = load("res://scripts/map_io.gd")
		var m := {"name": "qa_crew", "platforms": [], "player_spawn": Vector2(600, RANGE_Y - 20),
			"bot_spawns": [Vector2(900, RANGE_Y - 20), Vector2(3000, RANGE_Y - 20)], "vehicle_spawns": [Vector2(800, RANGE_Y)]}
		st.set("custom_map_path", MapIO.save_to_file("qa_crew", m))
		st.set("game_mode", 1); st.set("bot_count", 2); st.set("vehicles", true)
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
	if _t > 60.0:
		return _fail("timeout st=%d" % _st)
	var p = m.get("player")
	if _t < 1.0 or p == null or not is_instance_valid(p):
		return false
	p.set("ceasefire_t", 0.0)
	p.set("health", 100.0)
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
				return _fail("setup: car=%s mate=%s foe=%s" % [_car, _mate, _foe])
			_freeze(_mate, true)
			_freeze(_foe, true)
			_mate.global_position = Vector2(300, RANGE_Y - 20)
			_foe.global_position = Vector2(3400, RANGE_Y - 20)
			_car.set_seat(0, p)
			Input.action_press("move_right")
			_st = 1
			_st_t = 0.0
		1:
			_vmax = maxf(_vmax, absf(_car.velocity.x))
			if _st_t > 1.4:
				_log.append("top=%d" % _vmax)
				Input.action_press("fire")
				Input.action_press("aim_right", 1.0)
				_vmax = 0.0
				_st = 2
				_st_t = 0.0
		2:
			if _st_t > 0.6:
				_vmax = maxf(_vmax, absf(_car.velocity.x))
			if _st_t > 1.4:
				Input.action_release("fire")
				Input.action_release("move_right")
				Input.action_release("aim_right")
				_log.append("solo_firing=%d" % _vmax)
				if _vmax > 520.0 * 0.5 + 20.0:
					_bad.append("solo driver kept full speed while firing (%d)" % _vmax)
				_st = 3
				_st_t = 0.0
		3:
			# Stop, let the teammate come to us.
			if _st_t > 1.2:
				_mate.global_position = (_car as Node2D).global_position + Vector2(-160, -10)
				_freeze(_mate, false)
				_st = 4
				_st_t = 0.0
		4:
			if _car.gunner() == _mate:
				_log.append("bot boarded %.1fs" % _st_t)
				_foe.set("health", 1000.0)
				_foe.set("ceasefire_t", 0.0)
				_foe.global_position = (_car as Node2D).global_position + Vector2(380, -20)
				_mate.set("target", _foe)
				_st = 5
				_st_t = 0.0
			elif _st_t > 8.0:
				return _fail("teammate bot never took the gun seat")
		5:
			_foe.global_position.y = (_car as Node2D).global_position.y - 20
			_foe.set("ceasefire_t", 0.0)
			_mate.set("target", _foe)
			_mate.set("_target_visible", true)
			if float(_foe.get("health")) < 1000.0:
				_log.append("bot gunner hits")
				_car.request_exit(p)
				_st = 6
				_st_t = 0.0
			elif _st_t > 6.0:
				return _fail("bot gunner never hit")
		6:
			if _car.gunner() == null and _car.driver() == null:
				_log.append("bot left after driver %.1fs" % _st_t)
				print("CREW-TEST %s %s | %s" % ["ok" if _bad.is_empty() else "FAIL", str(_bad), " ".join(_log)])
				quit()
				return true
			elif _st_t > 5.0:
				return _fail("bot gunner stayed after the driver left")
	return false
