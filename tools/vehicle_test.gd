extends SceneTree
## Buggy check (gate stage F).
##   godot --headless --fixed-fps 60 -s tools/vehicle_test.gd
## On a flat test range: F gets you in as the driver, D drives, the buggy runs
## over a bot, the gun fires and hurts, F gets you out; blasts damage it, a
## wreck kills whoever is inside, and it comes back at its spot. Also checks
## the classic maps carry vehicle spawns.

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
var _drv: Object = null
var _drv_dead := false


func _key(action: String, down: bool) -> void:
	if down:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _fail(msg: String) -> bool:
	print("VEHICLE-TEST FAIL %s | %s" % [msg, " ".join(_log)])
	quit()
	return true


func _process(d: float) -> bool:
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _phase == 0:
		var n := 0
		for f in DirAccess.get_files_at("res://assets/maps"):
			if f.ends_with(".json") and FileAccess.get_file_as_string("res://assets/maps/" + f).contains("vehicle_spawns"):
				n += 1
		_log.append("maps_with_vehicles=%d" % n)
		if n < 50:
			_bad.append("only %d classic maps have vehicle spawns" % n)
		var MapIO = load("res://scripts/map_io.gd")
		var m := {"name": "qa_drive", "platforms": [], "player_spawn": Vector2(600, RANGE_Y - 20),
			"bot_spawns": [Vector2(1400, RANGE_Y - 20)], "vehicle_spawns": [Vector2(800, RANGE_Y)]}
		st.set("custom_map_path", MapIO.save_to_file("qa_drive", m))
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
	if _st < 8 and (_t < 1.0 or p == null or not is_instance_valid(p)):
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
			if _car == null:
				return _fail("no buggy spawned")
			_bot.set_physics_process(false)
			_bot.set_process(false)
			p.global_position = (_car as Node2D).global_position + Vector2(-20, -10)
			p.velocity = Vector2.ZERO
			_st = 1
			_st_t = 0.0
		1:
			if _st_t > 0.3:
				_key("weapon_throw", true)
				_st = 2
				_st_t = 0.0
		2:
			if _st_t > 0.1:
				_key("weapon_throw", false)
			if _car.seat_of(p) == 0 and p.get("mounted_m2") == _car:
				_key("weapon_throw", false)
				_log.append("entered")
				_x0 = (_car as Node2D).global_position.x
				_bot.global_position = Vector2(_x0 + 520, (_car as Node2D).global_position.y - 4)
				_bot.set("health", 100.0)
				_bot.set("ceasefire_t", 0.0)
				_key("move_right", true)
				_st = 3
				_st_t = 0.0
			elif _st_t > 1.5:
				return _fail("F did not seat the player as driver")
		3:
			var dx: float = (_car as Node2D).global_position.x - _x0
			var gone: bool = not is_instance_valid(_bot) or _bot.get("dead") == true
			if gone or float(_bot.get("health")) < 100.0:
				_key("move_right", false)
				_log.append("drove=%dpx runover %s" % [dx, "killed" if gone else "hp=%d" % int(_bot.get("health"))])
				if p.global_position.distance_to((_car as Node2D).global_position) > 60.0:
					_bad.append("driver not riding along")
				_st = 4
				_st_t = 0.0
			elif _st_t > 4.0:
				_key("move_right", false)
				return _fail("no run-over (moved %dpx)" % dx)
		4:
			# Brake, then shoot a fresh target with the mounted gun.
			if _st_t > 1.2:
				_bot = null
				for s in get_nodes_in_group("soldier"):
					if s.get("bot_id") != null and s.get("dead") != true:
						_bot = s
				if _bot == null:
					return false   # wait for the bot's respawn
				_bot.set_physics_process(false)
				_bot.set_process(false)
				_bot.set("health", 1000.0)
				_bot.set("ceasefire_t", 0.0)
				_bot.global_position = (_car as Node2D).global_position + Vector2(260, -10)
				Input.action_press("aim_right", 1.0)
				_key("fire", true)
				_st = 5
				_st_t = 0.0
		5:
			_bot.global_position.y = (_car as Node2D).global_position.y - 20
			if float(_bot.get("health")) < 1000.0:
				_key("fire", false)
				Input.action_release("aim_right")
				_log.append("gun hurts")
				_key("weapon_throw", true)
				_st = 6
				_st_t = 0.0
			elif _st_t > 2.0:
				return _fail("mounted gun never hit")
		6:
			if _st_t > 0.1:
				_key("weapon_throw", false)
			if _car.seat_of(p) < 0 and p.get("mounted_m2") == null:
				_key("weapon_throw", false)
				_log.append("exited")
				# Blast damage (explosives count extra).
				var hp0: float = float(_car.get("hp"))
				load("res://scripts/buggy.gd").splash(self, (_car as Node2D).global_position, 130.0, 90.0, "QA", "LAW", 77)
				if float(_car.get("hp")) >= hp0:
					_bad.append("rocket splash did no damage")
				_log.append("splash hp %d->%d" % [hp0, float(_car.get("hp"))])
				# Back in, then wreck it with the player inside.
				p.global_position = (_car as Node2D).global_position + Vector2(-20, -10)
				_st = 7
				_st_t = 0.0
			elif _st_t > 1.5:
				return _fail("F did not get the player out")
		7:
			if _st_t > 0.3 and _st_t < 0.45:
				_key("weapon_throw", true)
			if _st_t >= 0.45:
				_key("weapon_throw", false)
			if _car.seat_of(p) == 0:
				_key("weapon_throw", false)
				_drv = p
				_drv_dead = false
				m.kill.connect(func(_k, v, _w, _kt, _vt): if str(v) == str(p.display_name): _drv_dead = true)
				_car.take_damage(9999.0, "QA", "LAW", 77)
				_st = 8
				_st_t = 0.0
			elif _st_t > 2.0:
				return _fail("could not re-enter")
		8:
			if _car.get("alive") == true:
				return _fail("buggy survived 9999 damage")
			if _st_t > 0.2:
				if not _drv_dead:
					_bad.append("driver survived the wreck")
				_log.append("wreck kills driver=%s" % str(_drv_dead))
				_car.set("_respawn_t", 0.05)
				_st = 9
				_st_t = 0.0
		9:
			if _car.get("alive") == true:
				var at_spawn: bool = (_car as Node2D).global_position.distance_to(_car.get("spawn_pos")) < 5.0
				_log.append("respawned at_spawn=%s" % str(at_spawn))
				if not at_spawn:
					_bad.append("respawned away from its spot")
				print("VEHICLE-TEST %s %s | %s" % ["ok" if _bad.is_empty() else "FAIL", str(_bad), " ".join(_log)])
				quit()
				return true
			elif _st_t > 2.0:
				return _fail("never respawned")
	return false
