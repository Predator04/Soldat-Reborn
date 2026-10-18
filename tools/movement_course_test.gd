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
		["drop: no prone overshoots", Course.S_DROP, "drop", -1, "TOO LONG"],
		["drop: prone 0.1 s after the edge", Course.S_DROP, "drop", 6, "pass"],
		["lane: plain running", Course.S_BUNNY, "lane", "run", "TOO SLOW"],
		["lane: roll spam", Course.S_BUNNY, "lane", "roll", "TOO SLOW"],
		["lane: chained hops", Course.S_BUNNY, "lane", "hop", "pass"],
	]


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
	var keys: Array = ["MOVEMENT COURSE", "NOW THE MOVES THAT MAKE A SOLDAT", "SPIKES!", "TOO SLOW"]
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
	if _t > 240.0:
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
			Input.action_press("move_right")
			if not _st.has("left") and not body.is_on_floor() and pos.x > Course.LEDGE_X:
				_st["left"] = _sf
			if _st.has("left") and int(sc[3]) >= 0:
				var k: int = _sf - int(_st.left)
				if k == int(sc[3]):
					Input.action_press("prone")
				elif k == int(sc[3]) + 2:
					Input.action_release("prone")
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
		if outcome == "TOO LONG" and dx <= Course.RING.y:
			_bad.append("no-prone drop landed inside the ring (dx %.0f)" % dx)
	elif int(sc[1]) == Course.S_BUNNY:
		note = " t=%.2fs" % float(tr.get("_last_lane_t"))
	_log.append("%s -> %s%s" % [sc[0], outcome, note])
	if outcome != str(sc[4]):
		_bad.append("'%s' expected %s, got %s" % [sc[0], sc[4], outcome])
	_rel()
	_sc += 1
	_sf = -1
	_st = {}
	return false


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
