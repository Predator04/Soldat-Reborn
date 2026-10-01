extends SceneTree
## Buggy curb check (gate stage F).
##   godot --headless --fixed-fps 60 -s tools/vehicle_step_test.gd
## Vehicles don't hop (reported: "you can jump the whole buggy"). A bot drives
## a buggy over a 12 px curb (the wheels roll up it) and is stopped by a 60 px
## wall; the buggy never leaves the ground with upward speed from a hop.

const G := 1900.0

var _phase := 0
var _t := 0.0
var _car: Node = null
var _mate: Node = null
var _foe: Node = null
var _on_curb := false
var _max_up := 0.0
var _xmax := 0.0


func _process(d: float) -> bool:
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _phase == 0:
		var MapIO = load("res://scripts/map_io.gd")
		var m := {"name": "qa_step", "platforms": [
				{"p": Vector2(3000, G + 50), "s": Vector2(8000, 100)},
				{"p": Vector2(1700, G - 6), "s": Vector2(400, 12)},
				{"p": Vector2(2800, G - 30), "s": Vector2(200, 60)}],
			"player_spawn": Vector2(200, G - 20),
			"bot_spawns": [Vector2(700, G - 20), Vector2(4300, G - 20)], "vehicle_spawns": [Vector2(820, G)]}
		st.set("custom_map_path", MapIO.save_to_file("qa_step", m))
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
	var p = m.get("player")
	if _t < 1.0 or p == null or not is_instance_valid(p):
		return false
	p.set_physics_process(false)
	p.global_position = Vector2(150, G - 20)
	if _car == null:
		for v in get_nodes_in_group("vehicle"):
			_car = v
		for s in get_nodes_in_group("soldier"):
			if s.get("bot_id") != null:
				if int(s.get("team")) == int(p.get("team")):
					_mate = s
				else:
					_foe = s
		if _car == null or _mate == null or _foe == null:
			print("STEP-TEST FAIL setup"); quit(); return true
		_foe.set_physics_process(false); _foe.set_process(false)
		_foe.global_position = Vector2(4400, G - 20)
		_mate.global_position = Vector2(700, G - 20)
		return false
	_mate.set("target", _foe)
	_foe.set("health", 5000.0)
	var c := _car as Node2D
	if _car.driver() == _mate:
		_xmax = maxf(_xmax, c.global_position.x)
		_max_up = maxf(_max_up, -float(_car.get("velocity").y))
		if c.global_position.x > 1560.0 and c.global_position.x < 1880.0 and c.global_position.y < G - 8.0:
			_on_curb = true
	if _t > 22.0:
		var stopped: bool = _xmax < 2720.0
		var ok: bool = _on_curb and stopped and _max_up < 250.0
		print("STEP-TEST %s | on_curb=%s xmax=%d stopped_by_wall=%s max_up_speed=%d" % ["ok" if ok else "FAIL", _on_curb, _xmax, stopped, _max_up])
		quit()
		return true
	return false
