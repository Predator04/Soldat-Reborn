extends SceneTree
## Movement course (#262): plays Training phase 2 with injected input.
##   godot --headless --fixed-fps 60 -s tools/movement_course_test.gd
## Training phase 1 -> 2 handoff loads the course; then every gate is driven
## with the intended technique (must pass) and with the wrong one (must
## fail and reset): full jump into the short gap's spikes, a tap on the long
## gap, a non-prone drop past the ring, plain running and roll spam on the
## bunny lane. Then: total time + best time recorded, RELOAD restarts, the
## player's match settings are restored on leaving, the committed map JSON
## matches scripts/movement_course.gd, and the new strings are translated.
## #301: the prone drop is also swept the way a human plays it (press X
## from 0.30 s before the edge to 0.60 s after, hop / jump approaches,
## double presses) — see _drop_sweep for the expected outcome of each, the
## failure message must say what happened, and the in-air cue must show.
## Prints COURSE-TEST ok / FAIL (gate stage F).

var Course = null   # loaded at runtime (player.gd needs the autoloads)

var _t := 0.0
var _phase := 0
var _bad: Array = []
var _log: Array = []
var _orig_mode := 2
var _prev_best := 0
var _sc := 0            # scenario index
var _sf := 0            # frames into the scenario
var _st: Dictionary = {}
var _scen: Array = []


func _build_scenarios() -> void:
	var edge_s: float = Course.C1.y
	var edge_m: float = Course.C2.y
	var edge_l: float = Course.C3.y
	# [label, step, kind, param, expect]
	_scen = [
		["short: full jump into the spikes", Course.S_SHORT, "jump", [30, edge_s - 6.0], "SPIKES!"],
		["short: tap hop under the spikes", Course.S_SHORT, "jump", [4, edge_s - 6.0], "pass"],
		["medium: tap hop", Course.S_MEDIUM, "jump", [4, edge_m - 6.0], "pass"],
		["long: tap falls short", Course.S_LONG, "jump", [6, edge_l - 6.0], "MISSED"],
		["long: held full jump", Course.S_LONG, "jump", [30, edge_l - 6.0], "pass"],
		["drop: no prone overshoots", Course.S_DROP, "drop", {}, "TOO LONG"],
		["drop: prone 0.1 s after the edge", Course.S_DROP, "drop", {"t": 0.1}, "pass"],
	]
	_scen.append_array(_drop_sweep())
	_scen.append_array([
		["lane: plain running", Course.S_BUNNY, "lane", "run", "TOO SLOW"],
		["lane: roll spam", Course.S_BUNNY, "lane", "roll", "TOO SLOW"],
		["lane: chained hops", Course.S_BUNNY, "lane", "hop", "pass"],
	])


## #301: the prone drop as a human plays it, through the real input path.
## Every case holds → (D) the whole time and presses X (prone) for 0.1 s at
## "t" seconds relative to the edge (the first frame the soldier is past
## LEDGE_X in the air; negative = still on the deck, timed from his speed
## there). "t2" = a second press; "appr" = how he got to the ledge: walk
## (run at RUN_SPEED), hop (chained hops, jump released 40 px before the
## edge), hopheld (jump held the whole way), jumpoff (a 6-frame hop from
## the edge), jumpheld (a full jump from the edge, held 0.35 s — what the
## FULL JUMP step just taught). Expected outcome per case; in 1.38.1 a
## press before the edge crawled off "too short", a press after ~0.37 s was
## "too long", and X pressed while jump was held never registered.
func _drop_sweep() -> Array:
	var out: Array = []
	for i in range(-6, 13):
		var t := i * 0.05
		var want := "pass"
		if t < -0.26:
			want = "TOO EARLY"     # beyond the buffer: prone on the deck, crawls off
		elif t > 0.46:
			want = "TOO LONG"      # prone just before touchdown gains nothing
		out.append(["drop: prone at %+.2f s" % t, Course.S_DROP, "drop", {"t": t}, want])
	out.append(["drop: prone at +0.02 s", Course.S_DROP, "drop", {"t": 0.02}, "pass"])
	for appr in ["hop", "hopheld", "jumpoff", "jumpheld"]:
		var jump: bool = str(appr).begins_with("jump")
		out.append(["drop %s: no prone" % appr, Course.S_DROP, "drop", {"appr": appr}, "DON'T JUMP" if jump else "NOT PRONE"])
		for tt in [-0.1, 0.0, 0.1, 0.2, 0.3]:
			out.append(["drop %s: prone at %+.2f s" % [appr, tt], Course.S_DROP, "drop", {"t": tt, "appr": appr}, "DON'T JUMP" if jump else "pass"])
	out.append(["drop: double press +0.10 / +0.30", Course.S_DROP, "drop", {"t": 0.1, "t2": 0.3}, "STOOD UP"])
	out.append(["drop: double press -0.10 / +0.15", Course.S_DROP, "drop", {"t": -0.1, "t2": 0.15}, "STOOD UP"])
	out.append(["drop: double tap +0.05 / +0.15", Course.S_DROP, "drop", {"t": 0.05, "t2": 0.15}, "pass"])
	return out


func _rel() -> void:
	for a in ["move_left", "move_right", "jump", "jet", "prone", "crouch", "reload"]:
		if InputMap.has_action(a):
			Input.action_release(a)


func _tr_node():
	var m = current_scene
	if m == null or m.get("hud") == null:
		return null
	return m.hud.get_node_or_null("Training")


func _static_checks() -> void:
	var MapIO = load("res://scripts/map_io.gd")
	var built: String = MapIO.map_to_json(Course.build())
	var shipped: String = MapIO.map_to_json(MapIO.load_from_file(Course.PATH))
	if built != shipped:
		_bad.append("assets/maps/movement_course.json is stale: re-run tools/make_movement_course.gd")
	if not FileAccess.file_exists("res://assets/nav/movement_course.json"):
		_bad.append("no nav graph for the course")
	var TR = load("res://scripts/training.gd")
	var keys: Array = ["MOVEMENT COURSE", "NOW THE MOVES THAT MAKE A PRO", "SPIKES!", "TOO SLOW",
		"TOO EARLY", "DON'T JUMP", "STOOD UP", "PRONE  %.2f s", "PRESS {prone}",
		"You went prone %.2f s after the edge. Press {prone} right as you leave the ledge.",
		"You went prone on the ledge, so you crawled off it. Press {prone} as you go over the edge, not before.",
		"{prone} didn't register in the air. Press it once, right as you leave the ledge."]
	for st in TR.COURSE_STEPS:
		keys.append_array(st)
	for loc in ["de", "es", "fr", "pt_BR"]:
		var tobj: Translation = TranslationServer.get_translation_object(loc)
		for k in keys:
			if tobj == null or str(tobj.get_message(k)) == "":
				_bad.append("no %s translation for '%s'" % [loc, str(k).left(30)])
				break


func _process(d: float) -> bool:
	_t += d
	var st = root.get_node_or_null("Settings")
	var stats = root.get_node_or_null("Stats")
	if st == null or stats == null:
		return false
	if _t > 900.0:
		return _end("timeout phase=%d scenario=%d" % [_phase, _sc])
	match _phase:
		0:
			Course = load("res://scripts/movement_course.gd")
			_build_scenarios()
			_static_checks()
			_prev_best = int(stats.counters.get("course_best_ms", 0))
			stats.counters.erase("course_best_ms")
			st.set("game_mode", _orig_mode)
			st.set("custom_map_path", "")
			# Phase 1 first (the shooting steps); we skip to its end below.
			load("res://scripts/training.gd").start_training()
			root.get_node("Net").set_singleplayer()
			change_scene_to_file("res://scenes/main.tscn")
			_phase = 1
		1:
			var tr = _tr_node()
			if tr == null or current_scene.get("player") == null:
				return false
			if bool(tr.get("_course")):
				return _end("phase 1 overlay already on the course")
			tr.set("_step", tr.STEPS.size())
			tr._finish()   # phase 1 done -> "Now the moves..." -> course
			_phase = 2
			_t = 0.0
		2:
			var tr = _tr_node()
			if tr == null or not bool(tr.get("_course")) or current_scene.get("player") == null:
				if _t > 12.0:
					return _end("phase 2 never loaded the course")
				return false
			if str(st.get("custom_map_path")) != Course.PATH or not bool(st.get("training")):
				_bad.append("course loaded without the training session (map=%s)" % str(st.get("custom_map_path")))
			_log.append("handoff %.1fs" % _t)
			_phase = 3
			_sf = -1
		3:
			return _run_scenario()
		4:
			# Finished: total time + best time, then RELOAD replays.
			var tr = _tr_node()
			_sf += 1
			if float(tr.get("_c_end")) < 0.0:
				if _sf > 120:
					return _end("course never finished")
				return false
			var c_end: float = float(tr.get("_c_end"))
			var best: int = int(stats.course_best_ms())
			if best != int(round(c_end * 1000.0)):
				_bad.append("best time %d ms != run %.2f s" % [best, c_end])
			if not str(tr.get("_title").text).contains(tr.fmt_time(c_end)):
				_bad.append("finish title lacks the time: %s" % tr.get("_title").text)
			_log.append("total %s best=%dms" % [tr.fmt_time(c_end), best])
			Input.action_press("reload")
			_phase = 5
			_sf = 0
		5:
			var tr = _tr_node()
			_sf += 1
			if _sf == 3:
				Input.action_release("reload")
			if _sf < 6:
				return false
			if int(tr.get("_step")) != 0 or float(tr.get("_c_end")) >= 0.0:
				_bad.append("RELOAD didn't restart the course (step=%d end=%.1f)" % [int(tr.get("_step")), float(tr.get("_c_end"))])
			var p = current_scene.get("player")
			if (p as Node2D).global_position.distance_to(Course.step_start(Course.S_SHORT)) > 30.0:
				_bad.append("restart didn't put the player at the start")
			_rel()
			change_scene_to_file("res://scenes/menu.tscn")
			_phase = 6
			_t = 0.0
		6:
			var m = current_scene
			if m == null or m.name == "Main" or _t < 0.5:
				return false
			var ok: bool = int(st.get("game_mode")) == _orig_mode and not bool(st.get("training")) \
				and not bool(st.get("training_course")) and str(st.get("custom_map_path")) == ""
			if not ok:
				_bad.append("settings not restored (mode=%d training=%s course=%s map=%s)" % [int(st.get("game_mode")),
					str(st.get("training")), str(st.get("training_course")), str(st.get("custom_map_path"))])
			if m.find_child("MovementCourse", true, false) == null:
				_bad.append("menu has no MOVEMENT COURSE button")
			# The menu entry goes straight to the course.
			load("res://scripts/training.gd").start_training(true)
			if str(st.get("custom_map_path")) != Course.PATH or not bool(st.get("training_course")):
				_bad.append("start_training(true) doesn't pick the course")
			for k in st.training_saved.keys():
				st.set(k, st.training_saved[k])
			st.training_saved = {}
			st.training = false
			st.training_course = false
			return _end("")
	return false


func _run_scenario() -> bool:
	var tr = _tr_node()
	var p = current_scene.get("player")
	if tr == null or p == null or not is_instance_valid(p):
		return false
	if _sc >= _scen.size():
		_rel()
		_phase = 4
		_sf = 0
		return false
	var sc: Array = _scen[_sc]
	var body := p as CharacterBody2D
	if _sf == -1:
		# Wait for the training to be on this step and not showing a ✓.
		if int(tr.get("_step")) != int(sc[1]) and float(tr.get("_done_t")) < 0.0:
			# The #301 sweep passes and fails the drop many times: put the
			# course on this scenario's step.
			tr.set("_step", int(sc[1]))
			tr._show_step()
		if int(tr.get("_step")) != int(sc[1]) or float(tr.get("_done_t")) >= 0.0:
			_st["wait"] = int(_st.get("wait", 0)) + 1
			if int(_st.wait) > 600:
				return _end("'%s': training stuck on step %d (wanted %d)" % [sc[0], int(tr.get("_step")), int(sc[1])])
			return false
		_rel()
		tr._teleport(p, Course.step_start(int(sc[1])))
		_st = {"resets": int(tr.get("_resets"))}
		_sf = 0
		return false
	_sf += 1
	if _sf < 24:
		return false   # settle
	if body.fuel > 1.0:
		_bad.append("jets not disabled on the course (fuel %.1f)" % body.fuel)
	var pos := body.global_position
	match str(sc[2]):
		"jump":
			Input.action_press("move_right")
			var hold: int = int(sc[3][0])
			if not _st.has("jf") and pos.x >= float(sc[3][1]) and body.is_on_floor():
				Input.action_press("jump")
				_st["jf"] = _sf
			elif _st.has("jf") and _sf - int(_st.jf) >= hold:
				Input.action_release("jump")
		"drop":
			_drive_drop(body, sc[3])
		"lane":
			Input.action_press("move_right")
			match str(sc[3]):
				"hop":
					Input.action_press("jump")
				"roll":
					if _sf % 2 == 0:
						Input.action_press("crouch")
					else:
						Input.action_release("crouch")
	# Outcome.
	var outcome := ""
	if int(tr.get("_resets")) > int(_st.resets):
		outcome = str(tr.get("_last_fail"))
	elif float(tr.get("_done_t")) >= 0.0 or int(tr.get("_step")) > int(sc[1]):
		outcome = "pass"
	elif _sf > 60 * 14:
		outcome = "timeout"
	if outcome == "":
		return false
	var note := ""
	if int(sc[1]) == Course.S_DROP:
		var dx: float = float(tr.get("_last_drop_dx"))
		note = " dx=%d" % int(dx)
		if _st.has("edge") and _st.has("pf"):
			note += " pressed=%+.2fs" % ((int(_st.pf) - int(_st.edge)) / 60.0)
		note += " %s" % ("ground-prone" if _st.has("gprone") else "")
		note += " air-prone" if _st.has("aprone") else ""
		if outcome != "pass":
			note += " [%s]" % str(tr.get("_last_fail_desc"))
		if outcome == "TOO LONG" and dx <= Course.RING.y:
			_bad.append("'%s': TOO LONG inside the ring (dx %.0f)" % [sc[0], dx])
		# The message says what happened (#301).
		var desc: String = str(tr.get("_last_fail_desc"))
		var cfg: Dictionary = sc[3] if sc[3] is Dictionary else {}
		var want_txt := ""
		if outcome == "TOO LONG":
			want_txt = "after the edge" if cfg.has("t") else "in mid-air"
		elif outcome == "TOO EARLY":
			want_txt = "on the ledge"
		if want_txt != "" and not desc.contains(want_txt):
			_bad.append("'%s': message '%s' lacks '%s'" % [sc[0], desc, want_txt])
		# The in-air cue: PRESS X while falling, then PRONE once prone.
		if outcome == "pass" and float(cfg.get("t", 0.0)) >= 0.1 and str(cfg.get("appr", "walk")) == "walk" \
				and not (_st.has("cue_press") and _st.has("cue_prone")):
			_bad.append("'%s': in-air cue not shown (press=%s prone=%s)" % [sc[0], _st.has("cue_press"), _st.has("cue_prone")])
	elif int(sc[1]) == Course.S_BUNNY:
		note = " t=%.2fs" % float(tr.get("_last_lane_t"))
	_log.append("%s -> %s%s" % [sc[0], outcome, note])
	if str(sc[4]) != "*" and outcome != str(sc[4]):
		_bad.append("'%s' expected %s, got %s" % [sc[0], sc[4], outcome])
	_rel()
	_sc += 1
	_sf = -1
	_st = {}
	return false


## One drop case (see _drop_sweep); records the edge frame, the press
## frame(s) and whether the soldier was prone on the deck / in the air.
func _drive_drop(body: CharacterBody2D, cfg: Dictionary) -> void:
	var pos := body.global_position
	var on_floor := body.is_on_floor()
	var appr: String = str(cfg.get("appr", "walk"))
	Input.action_press("move_right")
	match appr:
		"hop":
			if pos.x < Course.LEDGE_X - 40.0:
				Input.action_press("jump")
			else:
				Input.action_release("jump")
		"hopheld":
			Input.action_press("jump")
		"jumpoff", "jumpheld":
			if not _st.has("jf") and on_floor and pos.x >= Course.LEDGE_X - 4.0:
				Input.action_press("jump")
				_st["jf"] = _sf
			elif _st.has("jf") and _sf - int(_st.jf) >= (6 if appr == "jumpoff" else 21):
				Input.action_release("jump")
	if not _st.has("edge") and not on_floor and pos.x > Course.LEDGE_X:
		_st["edge"] = _sf
	var cue = _tr_node().get("_flash")
	if cue is Label and (cue as Label).visible:
		_st["cue_prone" if bool(body.get("prone")) else "cue_press"] = true
	if bool(body.get("prone")) and not _st.has("edge"):
		_st["gprone"] = true
	elif bool(body.get("prone")) and not on_floor:
		_st["aprone"] = true
	for key in ["t", "t2"]:
		if not cfg.has(key):
			continue
		var t: float = float(cfg[key])
		var pk: String = "pf" if key == "t" else "pf2"
		if not _st.has(pk):
			var go := false
			if t < -0.001:
				# Before the edge: when the soldier, at his current speed, is
				# |t| s from leaving it (feet past LEDGE_X + half the body).
				var vx := maxf(absf(body.velocity.x), 1.0)
				go = not _st.has("edge") and pos.x >= Course.LEDGE_X + 7.0 - vx * (-t)
			else:
				go = _st.has("edge") and _sf - int(_st.edge) >= roundi(t * 60.0)
			if go:
				Input.action_press("prone")
				_st[pk] = _sf
		elif _sf - int(_st[pk]) == 6:
			Input.action_release("prone")


func _end(fail: String) -> bool:
	if fail != "":
		_bad.append(fail)
	_rel()
	var stats = root.get_node_or_null("Stats")
	if stats != null:
		# Leave the machine's own best time as it was.
		if _prev_best > 0:
			stats.counters["course_best_ms"] = _prev_best
		else:
			stats.counters.erase("course_best_ms")
		stats.save()
	print("COURSE-TEST %s %s | %s" % ["ok" if _bad.is_empty() else "FAIL", str(_bad), " · ".join(_log)])
	quit()
	return true
