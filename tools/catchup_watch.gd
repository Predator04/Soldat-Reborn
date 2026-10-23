extends SceneTree
## Dev tool (#315, not in the gate): does new-player protection (catchup.gd)
## leave even fights alone and help a weak player? Bots-only matches (the
## local player parked out of group "soldier") with the catch-up switched on
## for bots too (`Catchup.bots_too`, `force_sp`), each map played with it
## OFF and ON.
##   godot --headless --fixed-fps 60 -s tools/catchup_watch.gd -- --case=even|weak --maps=0,3-7
##       [--secs=180] [--runs=1] [--bots=8] [--weak-spread=1.2] [--weak-rate=2.5] [--out=build/catchup/x.jsonl]
## even: Teammatch (mode 1), all bots skill 3 — blue's share of the kills and
##       the kill rate should not move.
## weak: Deathmatch (mode 0), "Bot 1" plays like skill 1 (slow target
##       pick-up, short range) with --weak-spread rad of aim jitter (skill 3 =
##       0.16, skill 1 = 0.30; 0.6 alone barely hurt a bot at close range, so
##       use ~1.2) and its fire cooldowns x --weak-rate (2.5) — its kill
##       share / K:D with it on vs off.
## One JSON line per (map, run, on/off); lines already in --out are skipped,
## so a killed batch resumes. Summary: python3 tools/catchup_report.py FILE.

var _maps: Array = []
var _secs := 180.0
var _runs := 1
var _bots := 8
var _case := "even"
var _spread := 0.35
var _out := ""
var _jobs: Array = []        # [map, run, on]
var _ji := 0
var _loaded := false
var _ready_run := false
var _t := 0.0
var _k: Dictionary = {}      # name -> kills
var _d: Dictionary = {}      # name -> deaths
var _team_k: Dictionary = {} # team -> kills
var _done: Dictionary = {}
var _wall0 := 0
var _fix_t := 0.0
var _rate := 2.5             # weak bot: fire cooldowns x this
var _last_cd := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--maps="):
			for part in a.substr(7).split(","):
				if part.contains("-"):
					var ab := part.split("-")
					for i in range(int(ab[0]), int(ab[1]) + 1):
						_maps.append(i)
				elif part != "":
					_maps.append(int(part))
		elif a.begins_with("--secs="): _secs = float(a.substr(7))
		elif a.begins_with("--runs="): _runs = int(a.substr(7))
		elif a.begins_with("--bots="): _bots = int(a.substr(7))
		elif a.begins_with("--case="): _case = a.substr(7)
		elif a.begins_with("--weak-spread="): _spread = float(a.substr(14))
		elif a.begins_with("--weak-rate="): _rate = float(a.substr(12))
		elif a.begins_with("--out="): _out = a.substr(6)
	for m in _maps:
		for r in _runs:
			for on in [false, true]:
				_jobs.append([m, r, on])
	if _out != "":
		DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
		if FileAccess.file_exists(_out):
			var f := FileAccess.open(_out, FileAccess.READ)
			while f != null and not f.eof_reached():
				var d = JSON.parse_string(f.get_line())
				if d is Dictionary:
					_done[_id(str(d.get("case")), int(d.get("map")), int(d.get("run")), bool(d.get("on")))] = true


func _id(c: String, m: int, r: int, on: bool) -> String:
	return "%s|%d|%d|%s" % [c, m, r, str(on)]


func _mode() -> int:
	return 1 if _case == "even" else 0


func _physics_process(delta: float) -> bool:
	var st := root.get_node_or_null("Settings")
	if st == null:
		return false
	if not _loaded:
		while _ji < _jobs.size() and _done.has(_id(_case, int(_jobs[_ji][0]), int(_jobs[_ji][1]), bool(_jobs[_ji][2]))):
			_ji += 1
		if _ji >= _jobs.size():
			print("CATCHUP-WATCH DONE")
			quit()
			return true
		var job: Array = _jobs[_ji]
		var C = load("res://scripts/catchup.gd")
		C.force_sp = true
		C.bots_too = true
		st.set("catchup", bool(job[2]))
		st.set("custom_map_path", "")
		st.set("map_index", int(job[0]))
		st.set("game_mode", _mode())
		st.set("bot_count", _bots)
		st.set("bot_skill", 3)
		for k in ["survival", "realistic", "advance"]:
			st.set(k, false)
		# Same random stream for the OFF and ON run of a map.
		seed(1000 + int(job[0]) * 10 + int(job[1]))
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		_loaded = true
		_ready_run = false
		return false
	var m := current_scene
	if m == null or m.get("_catchup") == null or m.get("_map") == null or not m.is_node_ready():
		return false
	if not _ready_run:
		_ready_run = true
		_t = 0.0
		_k = {}; _d = {}; _team_k = {}
		_wall0 = Time.get_ticks_msec()
		m.round_time = _secs + 600.0
		m.time_left = _secs + 600.0
		m.kill.connect(func(k: String, v: String, _w, kt: int, vt: int) -> void:
			if vt < 0:
				return
			_d[v] = int(_d.get(v, 0)) + 1
			if k != "" and k != v:
				_k[k] = int(_k.get(k, 0)) + 1
				if kt >= 0 and kt != vt:
					_team_k[str(kt)] = int(_team_k.get(str(kt), 0)) + 1)
	var p = m.get("player")
	if p != null and is_instance_valid(p):
		p.set_physics_process(false)
		p.global_position = Vector2(-500, -500)
		if p.is_in_group("soldier"):
			p.remove_from_group("soldier")
	if _case == "weak":
		# Fire cadence: every new cooldown (= a shot) is stretched x --weak-rate.
		for b in get_nodes_in_group("soldier"):
			if is_instance_valid(b) and str(b.display_name) == "Bot 1":
				var cd := float(b.get("fire_cd"))
				if cd > _last_cd + 0.01:
					cd *= _rate
					b.set("fire_cd", cd)
				_last_cd = cd
		_fix_t -= delta
		if _fix_t <= 0.0:
			_fix_t = 0.5
			for b in get_nodes_in_group("soldier"):
				if is_instance_valid(b) and str(b.display_name) == "Bot 1":
					# Skill-1 reactions + range, and a much wider aim cone.
					b.set("_skill_aim_spread", _spread)
					b.set("_skill_target_cd", 2.0)
					b.set("_skill_engage_range", 720.0 * 0.55)   # bot.gd ENGAGE_RANGE x skill 1
	_t += delta
	if _t < _secs and not bool(m.match_over):
		return false
	_finish(m)
	return false


func _finish(m: Node) -> void:
	var job: Array = _jobs[_ji]
	var total := 0
	for k in _k.values():
		total += int(k)
	var rec := {"case": _case, "map": int(job[0]), "map_name": str(m.get("_map").get("name", "?")), "run": int(job[1]),
		"on": bool(job[2]), "secs": snappedf(_t, 0.1), "kills": _k, "deaths": _d, "team_kills": _team_k, "total": total,
		"cut_hits": int(m._catchup.reduced_hits), "cut_dmg": snappedf(float(m._catchup.reduced_dmg), 0.1),
		"spread": _spread if _case == "weak" else 0.0, "rate": _rate if _case == "weak" else 1.0, "wall_s": snappedf((Time.get_ticks_msec() - _wall0) / 1000.0, 0.1)}
	var line := JSON.stringify(rec)
	print("RUN " + line)
	if _out != "":
		var f := FileAccess.open(_out, FileAccess.READ_WRITE if FileAccess.file_exists(_out) else FileAccess.WRITE)
		if f != null:
			f.seek_end()
			f.store_line(line)
			f.close()
	_ji += 1
	_loaded = false
