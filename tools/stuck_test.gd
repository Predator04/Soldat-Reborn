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


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="): _secs = float(a.substr(7))
		elif a.begins_with("--from="): _from = int(a.substr(7))
		elif a.begins_with("--to="): _to = int(a.substr(5))
		elif a.begins_with("--mode="): _mode = int(a.substr(7))
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
	_t += delta
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
		var line := "map %3d %-14s unstuck=%d fell=%d idle_spots=%s" % [_idx, name, int(st["unstuck"]), int(st["fell"]), str(_wedged)]
		print(line)
		_idx += 1
		if _idx >= mini(_count, _to + 1):
			quit()
			return true
		_loaded = false
	return false
