extends SceneTree
## Dev-only (#291 / #294, not in the gate): watch bots use the planes on a classic map.
##   godot --headless --fixed-fps 60 -s tools/plane_watch.gd -- --map=51 --mode=2 --bots=8 --secs=90
## Prints per plane: boardings, distance flown by bot pilots, crash reports,
## wrecks, crash wrecks (destroyed by an impact, not shot down), the longest it sat empty away from its
## spawn; and how many soldiers died to plane weapons / wrecks. The last line
## `WATCH SUMMARY ...` sums the planes (one line per match for scripts).

var _map := 51
var _mode := 2
var _bots := 8
var _secs := 90.0
var _n := 0
var _t := 0.0
var _planes: Array = []
var _stat := {}
var _kills := {}
var _custom := ""
var _obj := {}          # objective kind -> count (grab / capture / ...)
var _sorties: Array = []  # seconds each finished bot sortie lasted


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--custom="): _custom = a.substr(9)
		elif a.begins_with("--map="): _map = int(a.substr(6))
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
		st.custom_map_path = _custom
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
				_stat[v.get_instance_id()] = {"board": 0, "wreck": 0, "crashwreck": 0, "drv": false, "alive": true,
					"idle_away": 0.0, "idle_max": 0.0, "first": -1.0, "crashes": 0, "crash_t": -99.0}
		m.kill.connect(func(_k, _v, w, _kt, _vt): if str(w) in ["Plane", "Plane MG", "Crash"]: _kills[str(w)] = int(_kills.get(str(w), 0)) + 1)
		m.objective.connect(func(kind, _tm, _who): _obj[str(kind)] = int(_obj.get(str(kind), 0)) + 1)
		print("WATCH planes=%d" % _planes.size())
	for v in _planes:
		if not is_instance_valid(v):
			continue
		var s: Dictionary = _stat[v.get_instance_id()]
		for b in get_nodes_in_group("soldier"):
			if b.get("bot_id") != null and not bool(b.get("dead")):
				var bd: float = (b as Node2D).global_position.distance_to((v as Node2D).global_position)
				s["near"] = minf(float(s.get("near", INF)), bd)
				if bd < 1700.0 and (b as CharacterBody2D).is_on_floor():
					s["near_t"] = float(s.get("near_t", 0.0)) + d
		var drv = v.driver()
		var has := drv != null and drv.get("bot_id") != null
		var had := bool(s["drv"])
		if has and not had:
			s["board"] = int(s["board"]) + 1
			s["board_t"] = _t
			if float(s["first"]) < 0.0:
				s["first"] = _t
		if had and not has:
			_sorties.append(_t - float(s.get("board_t", _t)))
		if has and _n % 60 == 0 and OS.get_environment("WATCH_LABELS") != "":
			print("WATCH fly t=%.0f %s label=%s goal=%s pos=%s v=%d" % [_t, str(drv.get("display_name")), str(drv.get("_goal_label")),
				str(drv.get("_goal")), str((v as Node2D).global_position.round()), int((v as CharacterBody2D).velocity.length())])
		if had and not has and bool(v.get("alive")):
			s["bail"] = int(s.get("bail", 0)) + 1
		s["drv"] = has
		if int(v.get("crashes")) != int(s["crashes"]):
			s["crashes"] = int(v.get("crashes"))
			s["crash_t"] = _t
		if bool(s["alive"]) and not bool(v.get("alive")):
			s["wreck"] = int(s["wreck"]) + 1
			# Wrecked by an impact (crash report this frame or just before), not shot down.
			if _t - float(s["crash_t"]) < 0.3:
				s["crashwreck"] = int(s["crashwreck"]) + 1
				if had:
					s["pilotcrash"] = int(s.get("pilotcrash", 0)) + 1   # a bot flew it into the ground
		s["alive"] = bool(v.get("alive"))
		# Empty, intact, and away from home: how long does it sit there?
		if bool(v.get("alive")) and drv == null and (v as Node2D).global_position.distance_to(v.get("spawn_pos")) > 24.0:
			s["idle_away"] = float(s["idle_away"]) + d
			s["idle_max"] = maxf(float(s["idle_max"]), float(s["idle_away"]))
		else:
			s["idle_away"] = 0.0
	if _t > _secs:
		var tb := 0
		var tf := 0.0
		var tc := 0
		var tw := 0
		var tcw := 0
		var idle := 0.0
		var first := -1.0
		var tpc := 0
		var tbl := 0
		for v in _planes:
			var s2: Dictionary = _stat[v.get_instance_id()]
			print("WATCH %s spawn=%s boardings=%d bails=%d first=%.0f flown=%d crashes=%d wrecks=%d crash_wrecks=%d pilot_crashes=%d idle_away_max=%.0f nearest_bot=%.0f bot_s_within_1700=%.0f" % [str(v.name), str(v.get("spawn_pos").round()),
				int(s2["board"]), int(s2.get("bail", 0)), float(s2["first"]), int(v.get("bot_flown")), int(v.get("crashes")), int(s2["wreck"]), int(s2["crashwreck"]),
				int(s2.get("pilotcrash", 0)), float(s2["idle_max"]), float(s2.get("near", INF)), float(s2.get("near_t", 0.0))])
			tpc += int(s2.get("pilotcrash", 0))
			tbl += int(s2.get("bail", 0))
			tb += int(s2["board"])
			tf += float(v.get("bot_flown"))
			tc += int(v.get("crashes"))
			tw += int(s2["wreck"])
			tcw += int(s2["crashwreck"])
			idle = maxf(idle, float(s2["idle_max"]))
			if float(s2["first"]) >= 0.0 and (first < 0.0 or float(s2["first"]) < first):
				first = float(s2["first"])
		for v in _planes:   # still flying at the end
			var s3: Dictionary = _stat[v.get_instance_id()]
			if bool(s3["drv"]):
				_sorties.append(_t - float(s3.get("board_t", _t)))
		var smax := 0.0
		var ssum := 0.0
		for x in _sorties:
			smax = maxf(smax, float(x))
			ssum += float(x)
		print("WATCH kills %s objectives %s scores %s sorties=%d avg=%.0fs max=%.0fs" % [str(_kills), str(_obj), str(m.get("scores")),
			_sorties.size(), ssum / maxf(1.0, float(_sorties.size())), smax])
		print("WATCH SUMMARY map=%d boardings=%d bails=%d first=%.0f flown=%d crashes=%d wrecks=%d crash_wrecks=%d pilot_crashes=%d idle_away_max=%.0f kills=%d sortie_max=%.0f grabs=%d caps=%d" % [_map, tb, tbl, first, int(tf), tc, tw, tcw, tpc, idle,
			int(_kills.get("Plane", 0)) + int(_kills.get("Plane MG", 0)), smax, int(_obj.get("grab", 0)), int(_obj.get("capture", 0))])
		quit()
		return true
	return false
