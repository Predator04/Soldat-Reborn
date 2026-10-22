extends SceneTree
## Dev tool (#311, not in the gate): mode / map balance from bot matches.
##   godot --headless --fixed-fps 60 -s tools/balance_watch.gd -- --mode=2 --maps=0,3-9 [--levels=twin_forts,frostbite]
##       [--secs=600] [--runs=1] [--bots=8] [--clock=0] [--out=build/balance/x.jsonl]
## Bots only (the local player is parked out of group "soldier"). Each run
## plays `--secs` of match time on one map and records every round: winner,
## active length, ended on score or on the clock, the final scores. It also
## keeps the score running across rounds (`cum`, per team; reset rounds add
## up) with a 10 s timeline (`tl`), so a different score limit can be judged
## from the same run, plus kills per team and objective events per kind /
## team. `--clock=N` sets the match clock to N s at the start (0 = the game's
## own); a long clock measures how fast a mode really scores. With --out each
## run is one JSON line and runs already in the file (same key / mode / run /
## clock) are skipped, so a killed batch resumes. FFA modes (DM RM BR GG):
## `tl` is the leading player's score in the current round.

var _maps: Array = []
var _secs := 600.0
var _runs := 1
var _bots := 8
var _mode := 1
var _clock := 0.0
var _out := ""
var _mi := 0
var _run := 0
var _loaded := false
var _ready_run := false
var _t := 0.0          # match time since the run started
var _act := 0.0        # time with a round in play
var _round_t0 := 0.0
var _was_active := true
var _rounds: Array = []
var _cum: Dictionary = {}
var _last: Dictionary = {}
var _tl: Array = []
var _tl_t := 0.0
var _kills: Dictionary = {}
var _obj: Dictionary = {}
var _done: Dictionary = {}
var _wall0 := 0
var _alive: Dictionary = {}   # team -> live soldier samples (team modes, every 10 s)


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
		elif a.begins_with("--levels="):
			for part in a.substr(9).split(","):
				if part != "":
					_maps.append("featured:" + part)
		elif a.begins_with("--secs="): _secs = float(a.substr(7))
		elif a.begins_with("--runs="): _runs = int(a.substr(7))
		elif a.begins_with("--bots="): _bots = int(a.substr(7))
		elif a.begins_with("--mode="): _mode = int(a.substr(7))
		elif a.begins_with("--clock="): _clock = float(a.substr(8))
		elif a.begins_with("--out="): _out = a.substr(6)
	if _out != "":
		DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
		if FileAccess.file_exists(_out):
			var f := FileAccess.open(_out, FileAccess.READ)
			while f != null and not f.eof_reached():
				var ln := f.get_line()
				var d = JSON.parse_string(ln) if ln.begins_with("{") else null
				if d is Dictionary:
					_done[_id(str(d.get("key")), int(d.get("mode")), int(d.get("run")), float(d.get("clock")))] = true


func _id(key: String, mode: int, run: int, clock: float) -> String:
	return "%s|%d|%d|%d" % [key, mode, run, int(clock)]


func _key(m) -> String:
	return str(m) if m is String else str(int(m))


func _team_mode() -> bool:
	return _mode in [1, 2, 3, 4, 6, 7]


func _physics_process(delta: float) -> bool:
	var st := root.get_node_or_null("Settings")
	if st == null:
		return false
	if not _loaded:
		while _mi < _maps.size() and _done.has(_id(_key(_maps[_mi]), _mode, _run, _clock)):
			print("SKIP %s mode=%d run=%d" % [_key(_maps[_mi]), _mode, _run])
			_next()
		if _mi >= _maps.size():
			print("BALANCE-WATCH DONE")
			quit()
			return true
		var mm = _maps[_mi]
		if mm is String:
			var slug: String = str(mm).substr(9)
			st.set("custom_map_path", load("res://scripts/featured_levels.gd").local_copy(slug))
			st.set("map_index", 0)
		else:
			st.set("custom_map_path", "")
			st.set("map_index", int(mm))
		st.set("game_mode", _mode)
		st.set("bot_count", _bots)
		st.set("bot_skill", 3)
		for k in ["survival", "realistic", "advance"]:
			st.set(k, false)
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		_loaded = true
		_ready_run = false
		return false
	var m := current_scene
	if m == null or m.get("MAPS") == null or m.get("_map") == null or not m.is_node_ready():
		return false
	if not _ready_run:
		_ready_run = true
		_t = 0.0; _act = 0.0; _round_t0 = 0.0; _was_active = true
		_rounds = []; _cum = {}; _last = {}; _tl = []; _tl_t = 0.0; _kills = {}; _obj = {}; _alive = {}
		_wall0 = Time.get_ticks_msec()
		if _clock > 0.0:
			m.round_time = _clock
			m.time_left = _clock
		m.kill.connect(func(_k, _v, _w, kt: int, vt: int) -> void:
			if vt >= 0 and kt != vt and kt >= 0:
				var k: String = str(kt) if _team_mode() else "ffa"
				_kills[k] = int(_kills.get(k, 0)) + 1)
		m.objective.connect(func(kind: String, team: int, _who: String) -> void:
			var o: Dictionary = _obj.get(kind, {})
			o[str(team)] = int(o.get(str(team), 0)) + 1
			_obj[kind] = o)
	var p = m.get("player")
	if p != null and is_instance_valid(p):
		p.set_physics_process(false)
		p.global_position = Vector2(-500, -500)
		if p.is_in_group("soldier"):
			p.remove_from_group("soldier")
	_t += delta
	var active: bool = bool(m.round_active)
	if active:
		_act += delta
	# Scores: carry the running total across round resets.
	var sc: Dictionary = m.scores
	for k in sc.keys():
		var v := int(sc[k])
		var prev := int(_last.get(k, 0))
		if v > prev:
			_cum[k] = int(_cum.get(k, 0)) + v - prev
		_last[k] = v
	if sc.is_empty() and not _last.is_empty():
		_last = {}
	if _was_active and not active:
		var s := {}
		for k in sc.keys():
			s[str(k)] = int(sc[k])
		_rounds.append({"w": int(m.winner_team), "t": snappedf(_act - _round_t0, 0.1),
			"by": "time" if float(m.time_left) <= 0.0 else "score", "s": s, "note": str(m.winner_note)})
	elif not _was_active and active:
		_round_t0 = _act
		_last = {}
	_was_active = active
	_tl_t += delta
	if _tl_t >= 10.0:
		_tl_t = 0.0
		if _team_mode():
			_tl.append([int(_cum.get(1, 0)), int(_cum.get(2, 0))])
			for s2 in get_nodes_in_group("soldier"):
				if is_instance_valid(s2) and not bool(s2.get("dead")):
					var tk := str(int(s2.get("team")))
					_alive[tk] = int(_alive.get(tk, 0)) + 1
		else:
			var top := 0
			for k in sc.keys():
				top = maxi(top, int(sc[k]))
			_tl.append(top)
	if _t < _secs:
		return false
	_finish(m)
	return false


func _finish(m: Node) -> void:
	var cum := {}
	for k in _cum.keys():
		cum[str(k)] = int(_cum[k])
	var rec := {"key": _key(_maps[_mi]), "map": str(m.get("_map").get("name", "?")), "mode": _mode, "run": _run,
		"clock": _clock, "secs": snappedf(_t, 0.1), "active": snappedf(_act, 0.1), "rounds": _rounds,
		"cum": cum if _team_mode() else {}, "tl": _tl, "kills": _kills, "obj": _obj, "alive": _alive,
		"wall_s": snappedf((Time.get_ticks_msec() - _wall0) / 1000.0, 0.1)}
	var line := JSON.stringify(rec)
	print("RUN " + line)
	if _out != "":
		var f := FileAccess.open(_out, FileAccess.READ_WRITE if FileAccess.file_exists(_out) else FileAccess.WRITE)
		if f != null:
			f.seek_end()
			f.store_line(line)
			f.close()
	_next()
	_loaded = false


func _next() -> void:
	_run += 1
	if _run >= _runs:
		_run = 0
		_mi += 1
