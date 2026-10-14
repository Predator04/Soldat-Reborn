extends SceneTree
## #259 verification: untouched, displaced vehicles return to their spawn
## point (occupied / damaged / entered reset the clock), and the idle timer
## only runs while empty. Runs the real buggy through the real tick.
##   godot --headless -s tools/vehicle_reset_test.gd

var _t := 0.0
var _phase := 0
var _bad: Array = []
var _log: Array = []
var _car: Node = null
var _player = null
var _touched_once := false


func _process(delta: float) -> bool:
	_t += delta
	if _t > 60.0:
		return _end("timeout phase=%d" % _phase)
	match _phase:
		0:
			var MapIO = load("res://scripts/map_io.gd")
			var m := {"name": "qa_vreset", "platforms": [], "player_spawn": Vector2(400, 1780),
				"bot_spawns": [Vector2(700, 1780)],
				"vehicle_spawns": [Vector2(600, 1780)]}
			var st := get_root().get_node("Settings")
			st.set("custom_map_path", MapIO.save_to_file("qa_vreset", m))
			st.set("game_mode", 0)
			st.set("bot_count", 0)
			st.set("vehicles", true)
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
			var vs: Array = get_nodes_in_group("vehicle")
			if vs.is_empty():
				return false
			_car = vs[0]
			# Short clock so the test runs quickly.
			_car.set("idle_respawn_time", 2.0)
			_log.append("spawn=%s" % str((_car as Node2D).global_position))
			_phase = 2
			_t = 0.0
			return false
		2:
			# Abandon it far from spawn (teleport is enough — it settles where
			# it lands), then wait PAST the idle clock with a mid-way damage
			# touch that must reset it.
			if _t < 0.5:
				return false
			var sp: Vector2 = _car.get("spawn_pos")
			(_car as Node2D).global_position = sp + Vector2(-320, -30)
			_car.set("velocity", Vector2.ZERO)
			_log.append("moved=%s" % str((_car as Node2D).global_position))
			_phase = 3
			_t = 0.0
			return false
		3:
			# 1.2 s in (before the 2 s clock): damage it — this must RESET the
			# idle timer, so at 1.8 s it must still be away from spawn.
			if _t >= 1.2 and not _touched_once:
				_touched_once = true
				_car.call("take_damage", 10.0, "tester", "AK-74", -1)
				_log.append("touched@1.2 hp=%d" % int(_car.get("hp")))
			if _t >= 1.9:
				var d1: float = (_car as Node2D).global_position.distance_to(_car.get("spawn_pos"))
				if d1 < 24.0:
					_bad.append("damage did not reset the idle clock (returned early, d=%d)" % int(d1))
				_log.append("after-touch d=%d" % int(d1))
				_phase = 4
				_t = 0.0
			return false
		4:
			# Now untouched: by ~2.5 s past the reset it must be back at spawn
			# (fresh, too — a respawn, not a teleport that keeps the damage).
			if _t < 3.2:
				return false
			var home: Vector2 = _car.get("spawn_pos")
			var now: Vector2 = (_car as Node2D).global_position
			if absf(now.x - home.x) > 40.0:
				_bad.append("idle vehicle did not go home (x=%d want %d)" % [int(now.x), int(home.x)])
			if int(_car.get("hp")) < int(_car.get("MAX_HP")):
				_bad.append("idle respawn did not restore hp (%d)" % int(_car.get("hp")))
			_log.append("respawned x=%d hp=%d/%d" % [int(now.x), int(_car.get("hp")), int(_car.get("MAX_HP"))])
			# Occupied vehicles must NEVER idle-respawn: sit in it and wait out
			# the clock while displaced.
			(_car as Node2D).global_position = (_car.get("spawn_pos") as Vector2) + Vector2(-200, -30)
			_car.set("velocity", Vector2.ZERO)
			var main := current_scene
			(main.get("player") as Node2D).global_position = (_car as Node2D).global_position + Vector2(0, -12)
			_car.call("set_seat", 0, main.get("player"))
			_phase = 5
			_t = 0.0
			return false
		5:
			if _t < 3.0:
				return false
			var d3: float = (_car as Node2D).global_position.distance_to(_car.get("spawn_pos"))
			if d3 < 24.0:
				_bad.append("OCCUPIED vehicle was teleported home (d=%d)" % int(d3))
			_log.append("occupied stays d=%d" % int(d3))
			return _end("")
	return false


func _end(fail: String) -> bool:
	if fail != "":
		_bad.append(fail)
	print("VRESET-TEST %s %s | %s" % ["ok" if _bad.is_empty() else "FAIL", str(_bad), " ".join(_log)])
	quit()
	return true
