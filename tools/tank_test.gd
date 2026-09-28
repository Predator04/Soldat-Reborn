extends SceneTree
## Tank check (gate stage F).
##   godot --headless --fixed-fps 60 -s tools/tank_test.gd
## On a flat range: F gets you in, it drives (slower than the buggy), the
## turret lobs a shell onto a bot 650px away without hurting the tank or its
## crew, bullets barely scratch it while rockets bite, a wreck kills the crew
## and it respawns. Also checks the wide classic maps carry tank spawns.

const RANGE_Y := 1900.0

var _phase := 0
var _t := 0.0
var _st := 0
var _st_t := 0.0
var _log: Array = []
var _bad: Array = []
var _car: Node = null
var _bot: Node = null
var _x0 := 0.0
var _vmax := 0.0
var _hp0 := 0.0
var _php0 := 0.0
var _drv_dead := false


func _key(action: String, down: bool) -> void:
	if down:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _fail(msg: String) -> bool:
	print("TANK-TEST FAIL %s | %s" % [msg, " ".join(_log)])
	quit()
	return true


func _process(d: float) -> bool:
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _phase == 0:
		var n := 0
		for f in DirAccess.get_files_at("res://assets/maps"):
			if f.ends_with(".json") and FileAccess.get_file_as_string("res://assets/maps/" + f).contains("tank_spawns"):
				n += 1
		_log.append("maps_with_tanks=%d" % n)
		if n < 10:
			_bad.append("only %d classic maps have tank spawns" % n)
		var MapIO = load("res://scripts/map_io.gd")
		var m := {"name": "qa_tank", "platforms": [], "player_spawn": Vector2(600, RANGE_Y - 20),
			"bot_spawns": [Vector2(2400, RANGE_Y - 20)], "tank_spawns": [Vector2(800, RANGE_Y)]}
		st.set("custom_map_path", MapIO.save_to_file("qa_tank", m))
		st.set("game_mode", 0); st.set("bot_count", 1); st.set("vehicles", true)
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
	if _st < 7 and (_t < 1.0 or p == null or not is_instance_valid(p)):
		return false
	if p != null and is_instance_valid(p):
		p.set("ceasefire_t", 0.0)
	match _st:
		0:
			for v in get_nodes_in_group("vehicle"):
				_car = v
			for s in get_nodes_in_group("soldier"):
				if s.get("bot_id") != null:
					_bot = s
			if _car == null or _car.get("kind") != "tank":
				return _fail("no tank spawned")
			if float(_car.get("hp")) != 900.0:
				_bad.append("tank hp %d" % int(_car.get("hp")))
			_bot.set_physics_process(false)
			_bot.set_process(false)
			p.global_position = (_car as Node2D).global_position + Vector2(-20, -10)
			p.velocity = Vector2.ZERO
			_st = 1
			_st_t = 0.0
		1:
			if _st_t > 0.3 and _st_t < 0.45:
				_key("weapon_throw", true)
			if _st_t >= 0.45:
				_key("weapon_throw", false)
			if _car.seat_of(p) == 0:
				_key("weapon_throw", false)
				_log.append("entered")
				_x0 = (_car as Node2D).global_position.x
				_key("move_right", true)
				_st = 2
				_st_t = 0.0
			elif _st_t > 1.5:
				return _fail("F did not seat the player")
		2:
			_vmax = maxf(_vmax, absf((_car as CharacterBody2D).velocity.x))
			if _st_t > 2.5:
				_key("move_right", false)
				var dx: float = (_car as Node2D).global_position.x - _x0
				_log.append("drove=%dpx vmax=%d" % [dx, _vmax])
				if dx < 200.0:
					_bad.append("tank barely moved")
				if _vmax > 300.0:
					_bad.append("tank as fast as a buggy")
				if p.global_position.distance_to((_car as Node2D).global_position) > 70.0:
					_bad.append("driver not riding along")
				_st = 3
				_st_t = 0.0
		3:
			if _st_t > 1.5:
				_bot.set("health", 1000.0)
				_bot.set("ceasefire_t", 0.0)
				_bot.global_position = Vector2((_car as Node2D).global_position.x + 650, (_car as Node2D).global_position.y - 20)
				var to: Vector2 = _bot.global_position - _car._gun_pivot()
				var sol: Vector2 = _car._aim_solution(to)
				if sol == Vector2.ZERO:
					return _fail("no firing solution at 650px")
				if _car._aim_solution(Vector2(99999, 0)) != Vector2.ZERO:
					_bad.append("solution for an unreachable target")
				_hp0 = float(_car.get("hp"))
				_php0 = float(p.get("health"))
				_car.set("aim_dir", sol)
				_car._fire(p)
				_log.append("fired %.2f,%.2f" % [sol.x, sol.y])
				_st = 4
				_st_t = 0.0
		4:
			if float(_bot.get("health")) < 1000.0:
				_log.append("shell hit bot hp=%d t=%.1fs" % [int(_bot.get("health")), _st_t])
				if float(_car.get("hp")) < _hp0:
					_bad.append("own shell hurt the tank")
				if float(p.get("health")) < _php0:
					_bad.append("own shell hurt the crew")
				# Armor: bullets 20%, rockets bite.
				var h0: float = float(_car.get("hp"))
				_car.take_damage(100.0, "QA", "AK-74", 77)
				var h1: float = float(_car.get("hp"))
				_car.take_damage(100.0, "QA", "LAW", 77)
				var h2: float = float(_car.get("hp"))
				_log.append("armor bullet=%d rocket=%d" % [h0 - h1, h1 - h2])
				if h0 - h1 > 25.0 or h1 - h2 < 60.0:
					_bad.append("armor wrong")
				_drv_dead = false
				m.kill.connect(func(_k, v, _w, _kt, _vt): if str(v) == str(p.display_name): _drv_dead = true)
				_car.take_damage(9999.0, "QA", "LAW", 77)
				_st = 5
				_st_t = 0.0
			elif _st_t > 4.0:
				return _fail("shell never hit (bot hp %d)" % int(_bot.get("health")))
		5:
			if _car.get("alive") == true:
				return _fail("tank survived 9999")
			if _st_t > 0.2:
				if not _drv_dead:
					_bad.append("crew survived the wreck")
				_log.append("wreck kills crew=%s" % str(_drv_dead))
				_car.set("_respawn_t", 0.05)
				_st = 6
				_st_t = 0.0
		6:
			if _car.get("alive") == true:
				_log.append("respawned hp=%d" % int(_car.get("hp")))
				if float(_car.get("hp")) != 900.0:
					_bad.append("respawn hp wrong")
				print("TANK-TEST %s %s | %s" % ["ok" if _bad.is_empty() else "FAIL", str(_bad), " ".join(_log)])
				quit()
				return true
			elif _st_t > 2.0:
				return _fail("never respawned")
	return false
