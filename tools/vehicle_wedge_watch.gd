extends SceneTree
## #299 dev sweep: CTF bot matches with vehicles on built-in / classic maps;
## logs ground vehicles (buggy / tank) that end up wedged — barely moving for
## 8 s while NOT resting on a floor (or tilted past 70 deg) — and stalls (the
## same driver sitting still for 10 s).
##   godot --headless --fixed-fps 60 -s tools/vehicle_wedge_watch.gd -- --maps=0 --secs=180 --runs=3 [--bots=8] [--trace]

var _maps: Array = [0]
var _secs := 180.0
var _runs := 1
var _bots := 8
var _trace := false
var _mi := 0
var _run := 0
var _t := 0.0
var _loaded := false
var _sample := 0.0
var _track: Dictionary = {}     # vehicle instance id -> {a: anchor, t: still secs, rep: reported}
var _total_wedges := 0
var _total_stalls := 0
var _total_resets := 0
var _lines: Array = []
var _res0: Dictionary = {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--maps="):
			_maps.clear()
			for part in a.substr(7).split(","):
				if part.contains("-"):
					var ab := part.split("-")
					for i in range(int(ab[0]), int(ab[1]) + 1):
						_maps.append(i)
				else:
					_maps.append(int(part))
		elif a.begins_with("--secs="): _secs = float(a.substr(7))
		elif a.begins_with("--runs="): _runs = int(a.substr(7))
		elif a.begins_with("--bots="): _bots = int(a.substr(7))
		elif a == "--trace": _trace = true


static func supported(v: Node) -> bool:
	if v.has_method("floor_supported"):
		return bool(v.call("floor_supported"))
	if v.is_on_floor():
		return true
	var col := KinematicCollision2D.new()
	if not (v as CharacterBody2D).test_move((v as Node2D).global_transform, Vector2(0, 6), col):
		return false
	if not (col.get_collider() is StaticBody2D):
		return true
	return absf(col.get_normal().angle_to(Vector2.UP)) <= float(v.get("floor_max_angle")) + 0.02


func _physics_process(delta: float) -> bool:
	var st := root.get_node_or_null("Settings")
	if st == null:
		return false
	if not _loaded:
		if _mi >= _maps.size():
			print("WEDGE-WATCH TOTAL wedges=%d stalls=%d wedge_resets=%d maps=%d runs=%d secs=%d" % [_total_wedges, _total_stalls, _total_resets, _maps.size(), _runs, int(_secs)])
			quit()
			return true
		st.set("custom_map_path", "")
		st.set("map_index", int(_maps[_mi]))
		st.set("game_mode", 2)
		st.set("bot_count", _bots)
		st.set("vehicles", true)
		st.set("bot_skill", 3)
		for k in ["survival", "realistic", "advance"]:
			st.set(k, false)
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		_loaded = true
		_t = 0.0
		_track.clear()
		_res0.clear()
		return false
	var m := current_scene
	if m == null or m.get("MAPS") == null:
		return false
	_t += delta
	var p = m.get("player")
	if p != null and is_instance_valid(p):
		p.set_physics_process(false)
		p.global_position = Vector2(-500, -500)
	_sample += delta
	if _sample >= 0.25:
		_sample = 0.0
		for v in get_nodes_in_group("vehicle"):
			if not is_instance_valid(v) or not (str(v.get("kind")) in ["buggy", "tank"]):
				continue
			var id: int = v.get_instance_id()
			if not _res0.has(id):
				_res0[id] = int(v.get("wedge_resets")) if v.get("wedge_resets") != null else 0
			var pos: Vector2 = (v as Node2D).global_position
			var tr: Dictionary = _track.get(id, {"a": pos, "t": 0.0, "rep": 0, "dt": 0.0, "d": 0})
			var dnow = v.driver()
			var did: int = dnow.get_instance_id() if dnow != null else 0
			if not v.get("alive") or pos.distance_to(tr["a"]) > 20.0:
				tr = {"a": pos, "t": 0.0, "rep": 0, "dt": 0.0, "d": did}
			else:
				tr["t"] = float(tr["t"]) + 0.25
				if did != 0 and did == int(tr["d"]):
					tr["dt"] = float(tr["dt"]) + 0.25
				else:
					tr["dt"] = 0.0
					tr["d"] = did
			var sup := supported(v)
			var tilt: float = float(v.get("_tilt"))
			var d = v.driver()
			var who: String = str(d.get("display_name")) if d != null else "-"
			if float(tr["t"]) >= 8.0 and int(tr["rep"]) == 0 and (not sup or absf(wrapf(tilt, -PI, PI)) > 1.22):
				tr["rep"] = 1
				_total_wedges += 1
				_lines.append("WEDGE map=%s run=%d t=%.0f %s#%d pos=%s tilt=%.2f sup=%s floor=%s wall=%s drv=%s gun=%s" % [str(m.get("_map").get("name")), _run, _t, str(v.get("kind")), int(v.get("vehicle_id")), Vector2i(pos), tilt, str(sup), str(v.is_on_floor()), str(v.is_on_wall()), who, "y" if v.gunner() != null else "-"])
				print(_lines[-1])
			elif float(tr["dt"]) >= 10.0 and int(tr["rep"]) == 0 and d != null:
				tr["rep"] = 2
				_total_stalls += 1
				print("STALL map=%s run=%d t=%.0f %s#%d pos=%s tilt=%.2f sup=%s drv=%s vx=%.0f" % [str(m.get("_map").get("name")), _run, _t, str(v.get("kind")), int(v.get("vehicle_id")), Vector2i(pos), tilt, str(sup), who, float(v.velocity.x)])
			if _trace and d != null and fmod(_t, 1.0) < 0.26:
				print("  t=%.1f #%d pos=%s v=%s tilt=%.2f sup=%s drv=%s goal=%s" % [_t, int(v.get("vehicle_id")), Vector2i(pos), Vector2i(v.velocity), tilt, str(sup), who, str(d.get("_goal"))])
			_track[id] = tr
	if _t >= _secs:
		var rs := 0
		for v in get_nodes_in_group("vehicle"):
			if is_instance_valid(v) and v.get("wedge_resets") != null:
				rs += int(v.get("wedge_resets")) - int(_res0.get(v.get_instance_id(), 0))
		_total_resets += rs
		var at := ""
		for v in get_nodes_in_group("vehicle"):
			if is_instance_valid(v):
				at += " %s#%d@%s/r%d" % [str(v.get("kind")), int(v.get("vehicle_id")), Vector2i((v as Node2D).global_position), int(v.get("respawns"))]
		print("RUN map=%d %s run=%d done (wedge_resets=%d)%s" % [int(_maps[_mi]), str(m.get("_map").get("name")), _run, rs, at])
		_run += 1
		if _run >= _runs:
			_run = 0
			_mi += 1
		_loaded = false
	return false
