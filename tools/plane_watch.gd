extends SceneTree
## Dev-only (#291, not in the gate): watch bots use the planes on a classic map.
##   godot --headless --fixed-fps 60 -s tools/plane_watch.gd -- --map=51 --mode=2 --bots=8 --secs=90
## Prints per plane: boardings, distance flown by bot pilots, crash reports,
## wrecks; and how many soldiers died to plane weapons / wrecks.

var _map := 51
var _mode := 2
var _bots := 8
var _secs := 90.0
var _n := 0
var _t := 0.0
var _planes: Array = []
var _stat := {}
var _kills := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="): _map = int(a.substr(6))
		elif a.begins_with("--mode="): _mode = int(a.substr(7))
		elif a.begins_with("--bots="): _bots = int(a.substr(7))
		elif a.begins_with("--secs="): _secs = float(a.substr(7))


func _process(d: float) -> bool:
	_n += 1
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _n == 2:
		st.bot_count = _bots
		st.game_mode = _mode
		st.map_index = _map
		st.custom_map_path = ""
		st.vehicles = true
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		return false
	var m = current_scene
	if m == null or m.get("MAPS") == null:
		return false
	_t += d
	if _t < 1.0:
		return false
	var p = m.get("player")
	if p != null and is_instance_valid(p):
		p.set("health", 100.0)
		p.set("ceasefire_t", 999.0)
	if _planes.is_empty():
		for v in get_nodes_in_group("vehicle"):
			if str(v.get("kind")) == "plane":
				_planes.append(v)
				_stat[v.get_instance_id()] = {"board": 0, "wreck": 0, "drv": false, "alive": true}
		m.kill.connect(func(_k, _v, w, _kt, _vt): if str(w) in ["Plane", "Plane MG", "Crash"]: _kills[str(w)] = int(_kills.get(str(w), 0)) + 1)
		print("WATCH planes=%d" % _planes.size())
	for v in _planes:
		var s: Dictionary = _stat[v.get_instance_id()]
		var drv = v.driver()
		var has := drv != null and drv.get("bot_id") != null
		if has and not bool(s["drv"]):
			s["board"] = int(s["board"]) + 1
		s["drv"] = has
		if bool(s["alive"]) and not bool(v.get("alive")):
			s["wreck"] = int(s["wreck"]) + 1
		s["alive"] = bool(v.get("alive"))
	if _t > _secs:
		for v in _planes:
			var s2: Dictionary = _stat[v.get_instance_id()]
			print("WATCH %s spawn=%s boardings=%d flown=%d crashes=%d wrecks=%d" % [str(v.name), str(v.get("spawn_pos").round()),
				int(s2["board"]), int(v.get("bot_flown")), int(v.get("crashes")), int(s2["wreck"])])
		print("WATCH kills %s" % str(_kills))
		quit()
		return true
	return false
