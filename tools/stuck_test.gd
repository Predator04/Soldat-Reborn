extends SceneTree
## Headless soak test: loads every map in turn with bots, simulates N seconds
## each and reports soldiers the anti-stuck watchdog had to free, falls off
## the map, and bots that stopped making progress (possible wedge spots).
##   godot --headless --fixed-fps 60 -s tools/stuck_test.gd -- [--secs=25] [--from=0] [--to=999] [--mode=0]

var _secs := 25.0
var _from := 0
var _to := 999
var _mode := 0
var _idx := 0
var _t := 0.0
var _count := -1
var _loaded := false
var _track: Dictionary = {}   # instance_id -> {pos, t_still}
var _report: Array = []
var _wedged: Dictionary = {}
var _caps := 0
var _kills := 0
var _hooked: Object = null
var _grabs := 0
var _trace := false
var _trace_label := "flag"
var _trace_name := ""
var _trace_t := 0.0
var _last_carrier: Dictionary = {}


func _on_kill(_k: String, victim: String, _w: String, _kt: int, _vt: int) -> void:
	if victim == "FLAG":
		_caps += 1
	elif not victim.begins_with("POINT"):
		_kills += 1


func _on_objective(kind: String, _team: int, _who: String) -> void:
	if kind == "capture" or kind == "dom" or kind == "point":
		_caps += 1


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="): _secs = float(a.substr(7))
		elif a.begins_with("--from="): _from = int(a.substr(7))
		elif a.begins_with("--to="): _to = int(a.substr(5))
		elif a.begins_with("--mode="): _mode = int(a.substr(7))
		elif a == "--trace": _trace = true
		elif a.begins_with("--trace-name="): _trace = true; _trace_name = a.substr(13).replace("_", " ")
		elif a.begins_with("--trace="): _trace = true; _trace_label = a.substr(8)
	_idx = _from


func _physics_process(delta: float) -> bool:
	var settings := root.get_node_or_null("Settings")
	if settings == null:
		return false
	if not _loaded:
		settings.set("custom_map_path", "")
		settings.set("map_index", _idx)
		settings.set("game_mode", _mode)
		change_scene_to_file("res://scenes/main.tscn")
		_loaded = true
		_t = 0.0
		_track.clear()
		_wedged.clear()
		return false
	var m := current_scene
	if m == null or m.get("MAPS") == null:
		return false
	if _count < 0:
		_count = (m.get("MAPS") as Array).size()
	if _hooked != m and m.has_signal("kill"):
		m.connect("kill", _on_kill)
		if m.has_signal("objective"):
			m.connect("objective", _on_objective)
		_hooked = m
		_caps = 0
		_kills = 0
		_grabs = 0
		_last_carrier.clear()
	_t += delta
	var fl = m.get("flags")
	if fl is Array:
		for i in (fl as Array).size():
			var f = fl[i]
			if not is_instance_valid(f):
				continue
			var c = f.get_meta("carrier") if f.has_meta("carrier") else null
			var cid: int = c.get_instance_id() if (c != null and is_instance_valid(c)) else 0
			if cid != 0 and int(_last_carrier.get(i, 0)) != cid:
				_grabs += 1
			_last_carrier[i] = cid
	_trace_t -= delta
	if _trace and _trace_t <= 0.0:
		_trace_t = 0.2
		for b in get_nodes_in_group("soldier"):
			if is_instance_valid(b) and ((_trace_name == "" and str(b.get("_goal_label")) == _trace_label) or str(b.get("display_name")) == _trace_name):
				var pth: PackedVector2Array = b.get("_path")
				var pi: int = b.get("_path_i")
				print("  t=%.0f %s pos=%s goal=%s path=%d/%d wp=%s v=%s fuel=%d fl=%s jet=%s rw=%s esc=%.1f tgt=%s" % [_t, b.get("display_name"), Vector2i(b.global_position), Vector2i(b.get("_goal")), pi, pth.size(), (Vector2i(pth[pi]) if pi < pth.size() else Vector2i.ZERO), Vector2i(b.velocity), int(b.get("fuel")), str(b.is_on_floor()), str(b.get("jet_on")), str(b.get("_refuel_wait")), float(b.get("_escape_t")), str(b.get("_target_visible"))])
				break
	if _t > 2.0:
		for s in get_nodes_in_group("soldier"):
			if not is_instance_valid(s) or bool(s.get("dead")) or s.get("loadout") == null:
				continue
			var id: int = s.get_instance_id()
			var e: Dictionary = _track.get(id, {"pos": s.global_position, "still": 0.0})
			if (s.global_position - (e["pos"] as Vector2)).length() > 40.0:
				e = {"pos": s.global_position, "still": 0.0}
			else:
				e["still"] = float(e["still"]) + delta
				if float(e["still"]) > 10.0:
					var key := "%d,%d" % [int(s.global_position.x / 40.0) * 40, int(s.global_position.y / 40.0) * 40]
					var tg = s.get("target")
					_wedged[key] = "v=%s floor=%s jet=%s tgt=%s fuel=%d hp=%d" % [str(Vector2i(s.velocity)), str(s.is_on_floor()), str(s.get("jet_on")), str(is_instance_valid(tg)), int(s.get("fuel")), int(s.get("health"))]
			_track[id] = e
	if _t >= _secs:
		var st: Dictionary = m.get("safety_stats")
		var name := str((m.get("_map") as Dictionary).get("name", "?"))
		var goals := {}
		for b in get_nodes_in_group("soldier"):
			if is_instance_valid(b) and b.get("_goal_label") != null:
				var g := str(b.get("_goal_label"))
				goals[g] = int(goals.get(g, 0)) + 1
		var line := "map %3d %-14s grabs=%d caps=%d kills=%d unstuck=%d fell=%d score=%s goals=%s idle_spots=%s" % [_idx, name, _grabs, _caps, _kills, int(st["unstuck"]), int(st["fell"]), str(m.get("scores")), str(goals), str(_wedged)]
		print(line)
		_idx += 1
		if _idx >= mini(_count, _to + 1):
			quit()
			return true
		_loaded = false
	return false
