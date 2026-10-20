extends SceneTree
## Vehicle sweep (#299, extended for the all-maps vehicle sweep): bot matches
## with vehicles; watches every buggy / tank / helicopter / plane and logs
##   WEDGE   ground vehicle barely moving for 8 s while NOT on a floor (or
##           tipped past 70 deg) — what the #299 recovery is for
##   STALL   the same driver / pilot sitting still for 10 s (any kind)
##   GROUNDED  plane: pilot aboard but not airborne for 10 s
##   FLIPPED plane resting on the ground canopy-down for 3 s
##   NORUNWAY  plane resting empty for 5 s where neither direction has a
##           runway it can take off from (checked again after every return)
##   HANG    empty heli / plane not resting on anything and not moving, 8 s
##   EMBED   any vehicle whose body overlaps the terrain for 2 s
##   OUT     a vehicle outside the world rect / below the kill line
##   RECOVER a #299 wedge reset fired (where from); IDLE an idle return (#259)
##   PBAN    a bot gave up on a plane (failed flight -> bot_ban_t)
##   ERR     any engine / script error logged during the run (needs Logger)
## Per run it also counts boardings per vehicle (driver / gunner seat) and
## the px driven crewed, so a vehicle nobody ever uses shows up (UNUSED).
##   godot --headless --fixed-fps 60 -s tools/vehicle_wedge_watch.gd -- --maps=0,3-5 [--custom=a.json,b.json]
##       [--secs=180] [--runs=3] [--bots=8] [--mode=2] [--out=build/vehicle_sweep/x.jsonl] [--trace]
## With --out each finished run is appended as one JSON line, and runs already
## in the file (same map / mode / run) are skipped, so a killed sweep resumes.

var _maps: Array = [0]
var _secs := 180.0
var _runs := 1
var _bots := 8
var _mode := 2
var _out := ""
var _trace := false
var _mi := 0
var _run := 0
var _t := 0.0
var _loaded := false
var _sample := 0.0
var _track: Dictionary = {}     # vehicle instance id -> per-vehicle watch state
var _total_wedges := 0
var _total_stalls := 0
var _total_resets := 0
var _total_events := 0
var _lines: Array = []
var _res0: Dictionary = {}
var _events: Array = []
var _done: Dictionary = {}
var _log: Object = null
var _map_name := ""


class ErrLog extends Logger:
	var mutex := Mutex.new()
	var errors: Array = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		mutex.lock()
		if errors.size() < 40:
			errors.append("%s:%d %s %s %s" % [file.get_file(), line, function, code, rationale])
		mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func take() -> Array:
		mutex.lock()
		var e := errors.duplicate()
		errors.clear()
		mutex.unlock()
		return e


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--maps="):
			_maps.clear()
			for part in a.substr(7).split(","):
				if part.contains("-"):
					var ab := part.split("-")
					for i in range(int(ab[0]), int(ab[1]) + 1):
						_maps.append(i)
				elif part != "":
					_maps.append(int(part))
		elif a.begins_with("--custom="):
			for part in a.substr(9).split(","):
				if part != "":
					_maps.append(part)
		elif a.begins_with("--secs="): _secs = float(a.substr(7))
		elif a.begins_with("--runs="): _runs = int(a.substr(7))
		elif a.begins_with("--bots="): _bots = int(a.substr(7))
		elif a.begins_with("--mode="): _mode = int(a.substr(7))
		elif a.begins_with("--out="): _out = a.substr(6)
		elif a == "--trace": _trace = true
	_log = ErrLog.new()
	OS.add_logger(_log)
	if _out != "" and FileAccess.file_exists(_out):
		var f := FileAccess.open(_out, FileAccess.READ)
		while f != null and not f.eof_reached():
			var ln := f.get_line()
			var d = JSON.parse_string(ln) if ln.begins_with("{") else null
			if d is Dictionary:
				_done["%s|%d|%d" % [str(d.get("key")), int(d.get("mode")), int(d.get("run"))]] = true


func _key(m) -> String:
	return ("c:" + str(m).get_file().get_basename()) if m is String else str(int(m))


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


## Something to rest on within `depth` px under the body (heli / plane).
static func _ground_near(v: Node, depth: float) -> bool:
	if v.has_method("_ground_below"):
		return float(v.call("_ground_below", (v as Node2D).global_position + Vector2(0, -6), depth)) != INF
	return supported(v)


## The body's collision shape overlaps terrain (StaticBody2D) right now.
static func embedded(v: Node) -> bool:
	var cs: CollisionShape2D = null
	for c in v.get_children():
		if c is CollisionShape2D:
			cs = c
	if cs == null or cs.shape == null:
		return false
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = cs.shape
	q.transform = cs.global_transform
	q.collision_mask = 1
	q.exclude = [(v as CollisionObject2D).get_rid()]
	q.margin = -2.0
	for h in (v as Node2D).get_world_2d().direct_space_state.intersect_shape(q, 4):
		if h.get("collider") is StaticBody2D:
			return true
	return false


func _event(kind: String, v: Node, extra: String) -> void:
	var pos: Vector2 = (v as Node2D).global_position
	var line := "%s map=%s run=%d t=%.0f %s#%d pos=%s %s" % [kind, _map_name, _run, _t, str(v.get("kind")), int(v.get("vehicle_id")), Vector2i(pos), extra]
	_events.append(line)
	_total_events += 1
	print(line)


func _physics_process(delta: float) -> bool:
	var st := root.get_node_or_null("Settings")
	if st == null:
		return false
	if not _loaded:
		while _mi < _maps.size() and _done.has("%s|%d|%d" % [_key(_maps[_mi]), _mode, _run]):
			print("SKIP %s mode=%d run=%d (already in %s)" % [_key(_maps[_mi]), _mode, _run, _out])
			_run += 1
			if _run >= _runs:
				_run = 0
				_mi += 1
		if _mi >= _maps.size():
			print("WEDGE-WATCH TOTAL wedges=%d stalls=%d wedge_resets=%d events=%d maps=%d runs=%d secs=%d" % [_total_wedges, _total_stalls, _total_resets, _total_events, _maps.size(), _runs, int(_secs)])
			quit()
			return true
		var mm = _maps[_mi]
		if mm is String:
			st.set("custom_map_path", str(mm))
			st.set("map_index", 0)
		else:
			st.set("custom_map_path", "")
			st.set("map_index", int(mm))
		st.set("game_mode", _mode)
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
		_events.clear()
		_log.call("take")
		return false
	var m := current_scene
	if m == null or m.get("MAPS") == null or m.get("_map") == null:
		return false
	_map_name = str(m.get("_map").get("name", _key(_maps[_mi])))
	_t += delta
	var p = m.get("player")
	if p != null and is_instance_valid(p):
		p.set_physics_process(false)
		p.global_position = Vector2(-500, -500)
		# Parked out of the world, it must not be a bot target either (bot
		# helicopters held their stand-off from it in the world's corner).
		if p.is_in_group("soldier"):
			p.remove_from_group("soldier")
	# Seats every frame (a short ride must still count as a boarding).
	for v in get_nodes_in_group("vehicle"):
		if not is_instance_valid(v):
			continue
		var id: int = v.get_instance_id()
		if not _track.has(id):
			_track[id] = {"a": (v as Node2D).global_position, "t": 0.0, "rep": 0, "dt": 0.0, "d": 0,
				"seat": [], "boards": [0, 0], "bot_boards": 0, "crewed_s": 0.0, "dist": 0.0, "air_s": 0.0,
				"takeoffs": 0, "last": (v as Node2D).global_position, "alive": true, "resp": int(v.get("respawns")),
				"wr": int(v.get("wedge_resets")), "wrecks": 0, "idle": 0, "rec": 0, "hang": 0.0, "emb": 0.0,
				"gnd": 0.0, "flip": 0.0, "rest": 0.0, "rw": false, "air": false, "out": false, "ban": false,
				"pban": 0, "maxd": 0.0, "ev": {}}
			_res0[id] = int(v.get("wedge_resets"))
		var tr: Dictionary = _track[id]
		# Launched: something the body stood on handed it its velocity.
		var pv: Vector2 = (v as CharacterBody2D).get_platform_velocity()
		if pv.length() > 300.0 and not tr.has("plat"):
			tr["plat"] = 1
			var cn := "?"
			for ci in (v as CharacterBody2D).get_slide_collision_count():
				var c := (v as CharacterBody2D).get_slide_collision(ci)
				if c.get_collider() != null and not (c.get_collider() is StaticBody2D):
					cn = str(c.get_collider().name) + ":" + c.get_collider().get_class()
			_event("PLATFORM", v, "standing on a moving body (%s) platform_vel=%s" % [cn, Vector2i(pv)])
		var seats: Array = v.get("seats")
		var prev: Array = tr["seat"]
		var now: Array = []
		for i in seats.size():
			var o = seats[i]
			var oid: int = o.get_instance_id() if o != null and is_instance_valid(o) else 0
			now.append(oid)
			if oid != 0 and (i >= prev.size() or int(prev[i]) != oid):
				tr["boards"][mini(i, 1)] += 1
				if o.get("bot_id") != null:
					tr["bot_boards"] += 1
		tr["seat"] = now
	_sample += delta
	if _sample >= 0.25:
		_sample = 0.0
		_sample_all(m)
	if _t >= _secs:
		_finish_run(m)
	return false


func _sample_all(m: Node) -> void:
	var mw: float = float(m.get("MAP_W"))
	var mh: float = float(m.get("MAP_H"))
	var ky: float = float(m.get("KILL_Y"))
	for v in get_nodes_in_group("vehicle"):
		if not is_instance_valid(v):
			continue
		var id: int = v.get_instance_id()
		if not _track.has(id):
			continue
		var tr: Dictionary = _track[id]
		var kind := str(v.get("kind"))
		var pos: Vector2 = (v as Node2D).global_position
		var alive: bool = v.get("alive")
		var d = v.driver()
		var did: int = d.get_instance_id() if d != null else 0
		var crewed := false
		for o in v.get("seats"):
			if o != null and is_instance_valid(o):
				crewed = true
		# Wrecks / returns.
		var resp := int(v.get("respawns"))
		var wr := int(v.get("wedge_resets"))
		if bool(tr["alive"]) and not alive:
			tr["wrecks"] += 1
			if pos.y > ky - 20.0 or pos.y > mh:
				_event("OUT", v, "wrecked below the kill line y=%.0f (kill_y=%.0f)" % [pos.y, ky])
			elif str(v.get("last_hitter")) == "" and kind in ["heli", "plane"]:
				_event("CRASH", v, "destroyed with no attacker (crash) crew=%s" % ("y" if crewed else "-"))
		if wr > int(tr["wr"]):
			tr["rec"] += wr - int(tr["wr"])
			_total_resets += wr - int(tr["wr"])
			_event("RECOVER", v, "wedge reset from %s" % Vector2i(tr["last"]))
		elif resp > int(tr["resp"]) and bool(tr["alive"]) and alive:
			tr["idle"] += 1
			_event("IDLE", v, "idle return from %s" % Vector2i(tr["last"]))
		if resp != int(tr["resp"]):
			tr["ev"] = {}
			tr["rw"] = false
			tr["a"] = pos
			tr["t"] = 0.0
			tr["dt"] = 0.0
		tr["resp"] = resp
		tr["wr"] = wr
		tr["alive"] = alive
		if alive:
			var step: float = pos.distance_to(tr["last"])
			if crewed and step < 400.0:
				tr["dist"] = float(tr["dist"]) + step
				tr["crewed_s"] = float(tr["crewed_s"]) + 0.25
			tr["maxd"] = maxf(float(tr["maxd"]), pos.distance_to(v.get("spawn_pos")))
		tr["prev"] = tr["last"]
		tr["last"] = pos
		if not alive:
			_track[id] = tr
			continue
		# Out of the world.
		var who0: String = str(d.get("display_name")) if d != null else "-"
		var outw := pos.x < -100.0 or pos.x > mw + 100.0 or pos.y > minf(mh + 50.0, ky + 40.0) or pos.y < -300.0
		if outw and not bool(tr["out"]):
			_event("OUT", v, "outside the world (%dx%d kill_y=%.0f) vel=%s crew=%s hitter=%s from=%s" % [int(mw), int(mh), ky, Vector2i(v.velocity), who0, str(v.get("last_hitter")), Vector2i(tr["prev"])])
		tr["out"] = outw
		# Still-tracking (anchor 20 px).
		if pos.distance_to(tr["a"]) > 20.0:
			tr["a"] = pos
			tr["t"] = 0.0
			tr["dt"] = 0.0
			tr["d"] = did
			tr["rep"] = 0
		else:
			tr["t"] = float(tr["t"]) + 0.25
			if did != 0 and did == int(tr["d"]):
				tr["dt"] = float(tr["dt"]) + 0.25
			else:
				tr["dt"] = 0.0
				tr["d"] = did
		var who: String = str(d.get("display_name")) if d != null else "-"
		var tilt: float = float(v.get("_tilt"))
		var ev: Dictionary = tr["ev"]
		if kind in ["buggy", "tank"]:
			# Wheels can't do this (no hop): something threw it.
			if v.velocity.y < -900.0 and not ev.has("launch"):
				ev["launch"] = 1
				_event("LAUNCH", v, "ground vehicle flying up vel=%s crew=%s" % [Vector2i(v.velocity), who])
			# #299 bail: the bot driver gave up here (stuck / a drop / the void).
			var dban: bool = float(v.get("drive_ban_t")) > 0.0
			if dban and not bool(tr.get("dban", false)):
				tr["bails"] = int(tr.get("bails", 0)) + 1
				var why := "stuck"
				if bool(v.get("_bd_drop")):
					why = "drop"
				else:
					var gy: float = m._geom_ground_y(pos.x + signf(v.face) * 70.0, pos.y - 30.0)
					if gy == INF or gy > ky:
						why = "void"
				_event("BAIL", v, "bot driver gave up here (drive ban, %s)" % why)
			tr["dban"] = dban
			var sup := supported(v)
			if float(tr["t"]) >= 8.0 and int(tr["rep"]) == 0 and (not sup or absf(wrapf(tilt, -PI, PI)) > 1.22):
				tr["rep"] = 1
				_total_wedges += 1
				_lines.append("WEDGE map=%s run=%d t=%.0f %s#%d pos=%s tilt=%.2f sup=%s floor=%s wall=%s drv=%s gun=%s" % [_map_name, _run, _t, kind, int(v.get("vehicle_id")), Vector2i(pos), tilt, str(sup), str(v.is_on_floor()), str(v.is_on_wall()), who, "y" if v.gunner() != null else "-"])
				_events.append(_lines[-1])
				_total_events += 1
				print(_lines[-1])
			elif float(tr["dt"]) >= 10.0 and int(tr["rep"]) == 0 and d != null:
				tr["rep"] = 2
				_total_stalls += 1
				_event("STALL", v, "tilt=%.2f sup=%s drv=%s vx=%.0f" % [tilt, str(sup), who, float(v.velocity.x)])
		else:
			var air := not _ground_near(v, 30.0) and not (v as CharacterBody2D).is_on_floor() and not bool(v.get("air_parked") == true)
			if kind == "plane":
				if air and not bool(tr["air"]) and d != null:
					tr["takeoffs"] += 1
				if air:
					tr["air_s"] = float(tr["air_s"]) + 0.25
				# Pilot aboard, wheels on the ground (or parked in the air) for 10 s.
				tr["gnd"] = (float(tr["gnd"]) + 0.25) if (d != null and not air) else 0.0
				if float(tr["gnd"]) >= 10.0 and not ev.has("gnd"):
					ev["gnd"] = 1
					_event("GROUNDED", v, "pilot %s not airborne for 10 s spd=%.0f thr=%.2f tilt=%.2f face=%.0f ban=%.0f" % [who, v.velocity.length(), float(v.get("throttle")), tilt, float(v.get("face")), float(v.get("bot_ban_t"))])
				# Canopy-down on the ground.
				var up := Vector2.from_angle(tilt - PI * 0.5 * float(v.get("face")))
				tr["flip"] = (float(tr["flip"]) + 0.25) if (not air and up.y > 0.3 and v.velocity.length() < 30.0) else 0.0
				if float(tr["flip"]) >= 3.0 and not ev.has("flip"):
					ev["flip"] = 1
					_event("FLIPPED", v, "resting canopy-down tilt=%.2f face=%.0f crew=%s" % [tilt, float(v.get("face")), who])
				# Resting empty: can it ever take off from here?
				tr["rest"] = (float(tr["rest"]) + 0.25) if (not crewed and not air and v.velocity.length() < 8.0 and v.get("air_parked") != true) else 0.0
				if float(tr["rest"]) >= 5.0 and not bool(tr["rw"]):
					tr["rw"] = true
					var rwr: float = float(v.call("_runway", pos, 1.0))
					var rwl: float = float(v.call("_runway", pos, -1.0))
					if maxf(rwr, rwl) < 480.0:
						_event("NORUNWAY", v, "parked with runway R=%.0f L=%.0f (spawn %s)" % [rwr, rwl, Vector2i(v.get("spawn_pos"))])
				var ban: bool = float(v.get("bot_ban_t")) > 0.0
				if ban and not bool(tr["ban"]):
					tr["pban"] += 1
					_event("PBAN", v, "a bot gave up on it (failed flight)")
				tr["ban"] = ban
			else:
				if air:
					tr["air_s"] = float(tr["air_s"]) + 0.25
				if air and not bool(tr["air"]) and d != null:
					tr["takeoffs"] += 1
			tr["air"] = air
			if float(tr["dt"]) >= 10.0 and int(tr["rep"]) == 0 and d != null:
				tr["rep"] = 2
				_total_stalls += 1
				_event("STALL", v, "pilot %s still 10 s air=%s rpm=%s spd=%.0f" % [who, str(air), str(v.get("rpm")), v.velocity.length()])
			# Empty, not parked, nothing under it and not moving: hung up.
			tr["hang"] = (float(tr["hang"]) + 0.25) if (not crewed and air and v.velocity.length() < 10.0) else 0.0
			if float(tr["hang"]) >= 8.0 and not ev.has("hang"):
				ev["hang"] = 1
				_event("HANG", v, "empty, nothing under it, not moving for 8 s")
		tr["emb"] = (float(tr["emb"]) + 0.25) if embedded(v) else 0.0
		if float(tr["emb"]) >= 2.0 and not ev.has("emb"):
			ev["emb"] = 1
			_event("EMBED", v, "body inside terrain for 2 s crew=%s" % who)
		tr["ev"] = ev
		if _trace and d != null and (fmod(_t, 1.0) < 0.26 or OS.get_environment("VTRACE_ALL") != ""):
			print("  t=%.1f #%d pos=%s v=%s tilt=%.2f drv=%s goal=%s ph=%s tgt=%s" % [_t, int(v.get("vehicle_id")), Vector2i(pos), Vector2i(v.velocity), tilt, who, str(d.get("_goal")), str(v.get("_bp_phase")), str(d.get("target").global_position) if d.get("target") != null and is_instance_valid(d.get("target")) else "-"])
		_track[id] = tr


func _finish_run(m: Node) -> void:
	var errs: Array = _log.call("take")
	for e in errs:
		var line := "ERR map=%s run=%d %s" % [_map_name, _run, str(e)]
		_events.append(line)
		print(line)
	var rs := 0
	var at := ""
	var vs: Array = []
	for v in get_nodes_in_group("vehicle"):
		if not is_instance_valid(v):
			continue
		var id: int = v.get_instance_id()
		rs += int(v.get("wedge_resets")) - int(_res0.get(id, 0))
		at += " %s#%d@%s/r%d" % [str(v.get("kind")), int(v.get("vehicle_id")), Vector2i((v as Node2D).global_position), int(v.get("respawns"))]
		var tr: Dictionary = _track.get(id, {})
		if tr.is_empty():
			continue
		var b: Array = tr["boards"]
		if int(b[0]) + int(b[1]) == 0:
			_events.append("UNUSED map=%s run=%d %s#%d spawn=%s" % [_map_name, _run, str(v.get("kind")), int(v.get("vehicle_id")), Vector2i(v.get("spawn_pos"))])
		vs.append({"id": int(v.get("vehicle_id")), "kind": str(v.get("kind")), "spawn": [int(v.get("spawn_pos").x), int(v.get("spawn_pos").y)],
			"boards_drv": int(b[0]), "boards_gun": int(b[1]), "bot_boards": int(tr["bot_boards"]),
			"crewed_s": float(tr["crewed_s"]), "dist": int(tr["dist"]), "max_from_spawn": int(tr["maxd"]),
			"air_s": float(tr["air_s"]), "takeoffs": int(tr["takeoffs"]), "wrecks": int(tr["wrecks"]),
			"wedge_resets": int(tr["rec"]), "idle_returns": int(tr["idle"]), "plane_bans": int(tr["pban"]), "bails": int(tr.get("bails", 0))})
	print("RUN map=%s %s mode=%d run=%d done (wedge_resets=%d events=%d errors=%d)%s" % [_key(_maps[_mi]), _map_name, _mode, _run, rs, _events.size(), errs.size(), at])
	if _out != "":
		var f: FileAccess
		if FileAccess.file_exists(_out):
			f = FileAccess.open(_out, FileAccess.READ_WRITE)
			f.seek_end()
		else:
			f = FileAccess.open(_out, FileAccess.WRITE)
		if f != null:
			f.store_line(JSON.stringify({"key": _key(_maps[_mi]), "map": _map_name, "mode": _mode, "run": _run, "secs": int(_secs),
				"bots": _bots, "vehicles": vs, "events": _events, "errors": errs}))
			f.close()
	_run += 1
	if _run >= _runs:
		_run = 0
		_mi += 1
	_loaded = false
