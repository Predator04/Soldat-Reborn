extends SceneTree
## Script/physics cost per frame in a busy match (no rendering).
##   godot --headless --fixed-fps 60 -s tools/perf_test.gd -- --map=13 --mode=2 --bots=16 --secs=25
## Prints avg / p95 / max of (process + physics) ms per frame after warmup, and
## the busiest node types by count. Phones have ~4x less CPU than a desktop, so
## keep avg well under 4 ms here.

var _map := 13
var _mode := 2
var _bots := 16
var _secs := 25.0
var _loaded := false
var _t := 0.0
var _samples: Array = []
var _wall0 := 0
var _frames := 0
var _last_us := 0
var _wall: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="): _map = int(a.substr(6))
		elif a.begins_with("--mode="): _mode = int(a.substr(7))
		elif a.begins_with("--bots="): _bots = int(a.substr(7))
		elif a.begins_with("--secs="): _secs = float(a.substr(7))


func _process(d: float) -> bool:
	var st := root.get_node_or_null("Settings")
	if st == null:
		return false
	if not _loaded:
		st.set("custom_map_path", ""); st.set("map_index", _map); st.set("game_mode", _mode)
		st.set("bot_count", _bots); st.set("vehicles", true); st.set("survival", false); st.set("advance", false)
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		_loaded = true
		return false
	if current_scene == null or current_scene.get("MAPS") == null:
		return false
	_t += d
	var now := Time.get_ticks_usec()
	if _t > 3.0:
		if _wall0 == 0:
			_wall0 = now
		else:
			var fm := (now - _last_us) / 1000.0
			_wall.append(fm)
			if fm > 15.0:
				print("SPIKE t=%.2f %.1fms bullets=%d nodes=%d" % [_t, fm, get_nodes_in_group("bullet").size(), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
		_frames += 1
		var ms: float = (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
		_samples.append(ms)
	_last_us = now
	if _t > _secs:
		_samples.sort()
		var n := _samples.size()
		var avg := 0.0
		for v in _samples: avg += v
		avg /= maxf(1.0, n)
		var counts := {}
		for node in current_scene.get_children():
			var k := node.get_class() + ("/" + (node.get_script() as Script).resource_path.get_file() if node.get_script() != null else "")
			counts[k] = int(counts.get(k, 0)) + 1
		var top: Array = counts.keys()
		top.sort_custom(func(a, b) -> bool: return counts[a] > counts[b])
		var tops := []
		for k in top.slice(0, 6): tops.append("%s=%d" % [k, counts[k]])
		_wall.sort()
		var wavg := float(now - _wall0) / 1000.0 / maxf(1.0, _frames)
		var mx: float = _wall[_wall.size() - 1]
		print("WALL frames=%d avg=%.2fms median=%.2fms p95=%.2fms max=%.2fms (real frame time incl. physics, no rendering)" % [_frames, wavg, _wall[_wall.size() / 2], _wall[int(_wall.size() * 0.95)], mx])
		# Gate verdict: smooth on this machine (phones are ~4x slower).
		print("PERF-TEST %s avg=%.2fms max=%.1fms" % ["ok" if wavg < 6.0 and mx < 80.0 else "FAIL", wavg, mx])
		print("PERF map=%d mode=%d bots=%d nodes=%d objects=%d | %s" % [_map, _mode, _bots, Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT), ", ".join(tops)])
		quit()
		return true
	return false
