extends SceneTree
## Runtime bot navigation (#287, gate stage F).
##   godot --headless --fixed-fps 60 -s tools/runtime_nav_test.gd
## A map with no baked graph (a classic map saved as a custom map under a new
## name, then a map from the editor's generator) must get a graph built in-game
## on a worker thread: non-empty, adopted within the time limit, every CTF leg
## (each team's spawn -> enemy flag -> home) routable, bots actually travel on
## it, and the build must not stall the main thread (#293, load-robust; raw
## wall gaps are only logged, under load they mostly measure other processes):
##  - adopting the graph (main.nav_adopt_ms, capped by the own time — wall
##    minus run-queue wait — of the frame it happened in) takes < STALL_MS;
##  - the main thread keeps ticking while the worker builds: at least
##    MIN_BUILD_FRAMES frames pass (a main thread waiting on the build would
##    see ~1; main and worker are slowed alike by load, so the count isn't);
##  - generous guard: no frame during the build over HANG_MS of own time.
## Then Maker maps (#286): the starter level with spikes and lava pits (no
## nav node on a hazard, no bot walks into one), with a buggy, a tank and a
## heli pad per team (a bot boards a buggy and drives it; tank / heli use is
## logged), and with the red flag on a floating island ~690 px up that only a
## big jump pad reaches (the graph routes the attack over the pad; a bot is
## launched by it and lands on the island).
## Zero script errors (the gate greps the log).

const GL = preload("res://tools/gate_load.gd")
const LIMIT_MS := 20000   # build + adopt deadline on a quiet box; scaled by the load (below)
const STALL_MS := 400.0   # main-thread own time adopting the graph
const HANG_MS := 3000.0   # any single frame's own time while the build runs
const MIN_BUILD_FRAMES := 10
var _st := 0
var _n := 0
var _t0 := 0
var _bad: Array = []
var _log: Array = []
var _saved := []
var _start_pos := {}
var _last_pos := {}
var _dist := {}
var _max_gap := 0.0      # raw wall gap (logged only)
var _max_own := 0.0      # own time of the worst frame during the build
var _build_frames := 0   # main-thread frames while the worker built
var _last_own := 0.0     # own time of the latest frame interval
var _last_st := {}       # GL.stamp() at the previous frame
var _wait_wall := 0.0    # wall / own ms summed while waiting for the graph:
var _wait_own := 0.0     # their ratio = how much other processes slowed us
var _case := 0
var _cases := ["classic", "generated", "maker_hazards", "maker_vehicles", "maker_pads"]
var _hz_kills0 := 0
var _launch0 := 0
var _drive := {}        # vehicle instance id -> px driven by a bot
var _drive_last := {}
var _drive_kind := {}   # vehicle instance id -> "buggy" / "tank" / "heli"
var _boarded := {}      # kind -> times a bot took the driver's / pilot's seat
var _drv_prev := {}     # vehicle instance id -> driver last frame
var _heli_alt := 0.0    # best height over the ground a bot flew a heli
var _pad_t := -1.0      # maker_pads: seconds until a bot first stood on the island
var _pad_arrive := {}   # maker_pads: team -> seconds until its first bot landed there
const PAD_ISLAND := Rect2(4140, 700, 320, 130)   # feet on the island's top (see _write_custom)
const PAD_LIMIT_S := 60   # maker_pads: a blue attacker must make it onto the island within this


func _write_custom(kind: String) -> String:
	var m: Dictionary = {}
	var io = load("res://scripts/map_io.gd")
	if kind == "classic":
		var f := FileAccess.open("res://assets/maps/arena.json", FileAccess.READ)
		m = io.json_to_map(f.get_as_text())
		m["name"] = "RTNav Classic Copy"
	elif kind == "generated":
		m = load("res://scripts/map_gen.gd").generate(4242)
		m["name"] = "RTNav Generated"
	else:
		var B = load("res://scripts/maker/maker_build.gd")
		var src: Dictionary = B.starter_map("grassland")
		var pcs: Array = src["maker"]["pieces"]
		if kind == "maker_hazards":
			# spikes on the first and last ground, lava in both gaps (under the bridges)
			pcs.append(B.make_piece("spikes", Vector2(1100, 1496), Vector2(160, 28)))
			pcs.append(B.make_piece("spikes", Vector2(3700, 1496), Vector2(160, 28)))
			pcs.append(B.make_piece("lava", Vector2(1600, 1600), Vector2(360, 80)))
			pcs.append(B.make_piece("lava", Vector2(3200, 1600), Vector2(360, 80)))
		elif kind == "maker_pads":
			# A floating island 690 px over the east ground (out of jet-link
			# reach) carrying the red flag, a big jump pad beside it.
			pcs.append(B.make_piece("float", Vector2(4300, 860), Vector2(320, 80)))
			pcs.append(B.make_piece("pad_big", Vector2(4000, 1500), Vector2(64, 20)))
			src["ctf_flags"] = [Vector2(300, 1500), Vector2(4300, 810)]
		else:
			src["vehicle_spawns"] = [Vector2(900, 1510), Vector2(3900, 1510)]
			src["tank_spawns"] = [Vector2(600, 1510), Vector2(4200, 1510)]
			src["heli_spawns"] = [Vector2(1150, 1510), Vector2(3650, 1510)]
		m = B.compile(src)
		m["name"] = {"maker_hazards": "RTNav Maker Hazards", "maker_pads": "RTNav Maker Pads"}.get(kind, "RTNav Maker Vehicles")
	return io.save_to_file(str(m["name"]), m)


func _ok(nav, a: Vector2, b: Vector2) -> bool:
	var p: PackedVector2Array = nav.path(a, b)
	return p.size() > 0 and p[p.size() - 1].distance_to(b) < 260.0


func _initialize() -> void:
	# RTNAV_CASES=maker_pads,maker_vehicles runs just those (debugging).
	var only := OS.get_environment("RTNAV_CASES")
	if only != "":
		_cases = Array(only.split(",", false))


func _process(_d: float) -> bool:
	_n += 1
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	var now := Time.get_ticks_msec()
	var stp := GL.stamp()
	if not _last_st.is_empty():
		_last_own = GL.own_ms(_last_st, stp)
		if _st == 2:
			var w := GL.wall_ms(_last_st, stp)
			_max_gap = maxf(_max_gap, w)
			_max_own = maxf(_max_own, _last_own)
			_build_frames += 1
			_wait_wall += w
			_wait_own += _last_own
	_last_st = stp
	match _st:
		0:
			if _saved.is_empty():
				_saved = [st.custom_map_path, st.game_mode, st.bot_count, st.map_index, st.vehicles]
			st.vehicles = true
			var path := _write_custom(_cases[_case])
			if path == "":
				return _end("could not save the %s test map" % _cases[_case])
			st.custom_map_path = path
			st.game_mode = 2
			st.bot_count = 6
			root.get_node("Net").set_singleplayer()
			change_scene_to_file("res://scenes/main.tscn")
			_st = 1
			_n = 0
		1:
			var m = current_scene
			if m == null or m.get("nav") == null:
				return false
			# Checked on the match's FIRST frame, before main._process ever ran,
			# so a worker-built graph can't have been adopted yet (#293: this
			# used to wait 3 frames, and under load the worker finished and was
			# adopted in between — reported as a stale bake).
			if not m.nav.is_empty():
				if int(m.nav_runtime_ms) >= 0 or float(m.nav_adopt_ms) >= 0.0:
					_bad.append("%s: runtime graph adopted before the match's first frame (built on the main thread?)" % _cases[_case])
				else:
					_bad.append("%s: graph present before the runtime build (stale bake?)" % _cases[_case])
			elif int(m.get("_nav_task")) < 0:
				_bad.append("%s: no baked graph and no runtime build started" % _cases[_case])
			_t0 = now
			_max_gap = 0.0
			_max_own = 0.0
			_build_frames = 0
			_wait_wall = 0.0
			_wait_own = 0.0
			_st = 2
		2:
			var m = current_scene
			if m.nav.is_empty():
				# Deadline for a wait, scaled by the load: the gate's measured
				# factor, or how much other processes slowed this very wait.
				var slow := clampf(_wait_wall / maxf(1.0, _wait_own), 1.0, GL.MAX_FACTOR)
				var limit := LIMIT_MS * maxf(GL.factor(), slow)
				if now - _t0 > limit:
					return _end("%s: no runtime graph after %d ms (limit scaled x%.1f by load)" % [_cases[_case], now - _t0, limit / LIMIT_MS])
				return false
			# Adopted during main._process of the previous frame, i.e. inside
			# the interval that just ended.
			var adopt := float(m.nav_adopt_ms)
			var stall := minf(adopt, _last_own) if adopt >= 0.0 else _last_own
			_log.append("%s graph %d ms (adopt %.0f ms, %d frames meanwhile, frame own max %.0f ms, raw gap max %.0f ms)" % [_cases[_case], int(m.nav_runtime_ms), stall, _build_frames, _max_own, _max_gap])
			if _build_frames < MIN_BUILD_FRAMES:
				_bad.append("%s: only %d main-thread frames during the %d ms build (main thread blocked on it?)" % [_cases[_case], _build_frames, int(m.nav_runtime_ms)])
			if stall > STALL_MS:
				_bad.append("%s: main thread stalled %.0f ms adopting the graph" % [_cases[_case], stall])
			if _max_own > HANG_MS:
				_bad.append("%s: a frame took %.0f ms of main-thread time during the build" % [_cases[_case], _max_own])
			# CTF legs
			var home := {}
			for f in m.flags:
				home[int(f.get_meta("team"))] = f.get_meta("home")
			if home.size() >= 2:
				for t in [1, 2]:
					var e: int = 2 if t == 1 else 1
					var sp: Array = m._team_spawn_list(t)
					var s: Vector2 = m._settle_on_ground(sp[0] if not sp.is_empty() else home[t])
					if not _ok(m.nav, s, home[e]):
						_bad.append("%s: T%d spawn -> enemy flag unroutable" % [_cases[_case], t])
					if not _ok(m.nav, home[e], home[t]):
						_bad.append("%s: T%d enemy flag -> home unroutable" % [_cases[_case], t])
			# Maker hazards: the graph must keep off spikes / lava.
			var zones: Array = m.get("_hazards").zones if m.get("_hazards") != null else []
			if _cases[_case] == "maker_hazards":
				if zones.size() != 4:
					_bad.append("maker_hazards: %d hazard zones loaded (want 4)" % zones.size())
				var on := 0
				for p in m.nav._pts:
					for z in zones:
						if (z["rect"] as Rect2).grow(2.0).has_point(p):
							on += 1
				_log.append("maker_hazards nodes=%d on_hazard=%d" % [m.nav._pts.size(), on])
				if on > 0:
					_bad.append("maker_hazards: %d nav nodes sit on a hazard" % on)
			if _cases[_case] == "maker_pads":
				# The only route to the red flag must be a pad ride.
				var pads: int = int(m.nav.get("_pad_ride").size()) if m.nav.has_method("has_pads") else 0
				var sp: Array = m._team_spawn_list(1)
				var s: Vector2 = m._settle_on_ground(sp[0] if not sp.is_empty() else Vector2(420, 1500))
				var pth: PackedVector2Array = m.nav.path(s, home.get(2, Vector2(4300, 810)))
				var rides := 0
				for i in range(1, pth.size()):
					if m.nav.pad_ride(pth[i - 1], pth[i]) >= 0:
						rides += 1
				_log.append("maker_pads pad_links=%d rides_on_attack_path=%d" % [pads, rides])
				if pads == 0:
					_bad.append("maker_pads: the runtime graph has no jump-pad links")
				elif rides == 0:
					_bad.append("maker_pads: the attack path to the island flag doesn't use the pad")
			_hz_kills0 = int(m.get("_hazards").kills) if m.get("_hazards") != null else 0
			_launch0 = int(m.get("_hazards").bot_launches) if m.get("_hazards") != null else 0
			_pad_t = -1.0
			_pad_arrive.clear()
			_boarded.clear()
			_drv_prev.clear()
			_drive_kind.clear()
			_heli_alt = 0.0
			_drive.clear()
			_drive_last.clear()
			_start_pos.clear()
			_last_pos.clear()
			_dist.clear()
			for b in m.get_tree().get_nodes_in_group("soldier"):
				if is_instance_valid(b) and b != m.player:
					_start_pos[b.get_instance_id()] = b.global_position
			_t0 = now
			_n = 0
			_st = 3
		3:
			# accumulate how far each bot walks / flies (defenders patrol, so
			# distance travelled says more than displacement)
			for b in current_scene.get_tree().get_nodes_in_group("soldier"):
				if not is_instance_valid(b) or b == current_scene.player:
					continue
				var id: int = b.get_instance_id()
				if not _start_pos.has(id):
					_start_pos[id] = b.global_position
				var last: Vector2 = _last_pos.get(id, b.global_position)
				var step: float = b.global_position.distance_to(last)
				if step < 60.0:          # ignore respawn teleports
					_dist[id] = float(_dist.get(id, 0.0)) + step
				_last_pos[id] = b.global_position
			for v in current_scene.get_tree().get_nodes_in_group("vehicle"):
				if not is_instance_valid(v) or not v.has_method("driver"):
					continue
				var vid: int = v.get_instance_id()
				var d = v.driver()
				var vp: Vector2 = (v as Node2D).global_position
				var kind: String = "heli" if v.has_method("bot_board_ok") else ("tank" if str(v.name).begins_with("Tank") else "buggy")
				_drive_kind[vid] = kind
				if d != null and d != current_scene.player:
					var step: float = vp.distance_to(_drive_last.get(vid, vp))
					if step < 60.0:
						_drive[vid] = float(_drive.get(vid, 0.0)) + step
					if _drv_prev.get(vid) != d:
						_boarded[kind] = int(_boarded.get(kind, 0)) + 1
					if kind == "heli":
						var gy: float = current_scene._geom_ground_y(vp.x, vp.y)
						if gy != INF:
							_heli_alt = maxf(_heli_alt, gy - vp.y)
				_drv_prev[vid] = d
				_drive_last[vid] = vp
			if _cases[_case] == "maker_pads" and _pad_arrive.size() < 2:
				# Over the island's top, coming down (or standing) after a pad
				# launch within the last 4 s (first arrival per team: red defends
				# there, blue attacks from 3600 px away; red on the high ground
				# sometimes shoots the attacker just before its feet touch down).
				var hz = current_scene.get("_hazards")
				for b in current_scene.get_tree().get_nodes_in_group("soldier"):
					if is_instance_valid(b) and b != current_scene.player and not bool(b.get("dead")) \
							and not _pad_arrive.has(int(b.get("team"))) \
							and PAD_ISLAND.has_point(b.global_position) and (b as CharacterBody2D).velocity.y >= 0.0 \
							and now - int(hz._pad_cd.get(b.get_instance_id(), -100000)) < 4000:
						_pad_arrive[int(b.get("team"))] = float(_n) / 60.0
						if _pad_t < 0.0:
							_pad_t = float(_n) / 60.0
			# maker_pads runs on (up to PAD_LIMIT_S) until an attacker made the trip.
			if _n < 60 * 25 or (_cases[_case] == "maker_pads" and not _pad_arrive.has(1) and _n < 60 * PAD_LIMIT_S):
				return false
			var m = current_scene
			if _cases[_case] == "maker_hazards":
				var hk: int = int(m.get("_hazards").kills) - _hz_kills0
				_log.append("maker_hazards hazard_deaths=%d" % hk)
				if hk > 0:
					_bad.append("maker_hazards: bots died in spikes / lava %d times (%s)" % [hk, ", ".join(m.get("_hazards").kill_log)])
			if _cases[_case] == "maker_vehicles":
				var best := {"buggy": 0.0, "tank": 0.0, "heli": 0.0}
				for k in _drive:
					var kk: String = _drive_kind.get(k, "buggy")
					best[kk] = maxf(float(best[kk]), float(_drive[k]))
				_log.append("maker_vehicles vehicles=%d buggy=%d px tank=%d px heli=%d px (alt %d) boarded=%s" % [
					m.get_tree().get_nodes_in_group("vehicle").size(), int(best["buggy"]), int(best["tank"]),
					int(best["heli"]), int(_heli_alt), str(_boarded)])
				if float(best["buggy"]) < 400.0:
					_bad.append("maker_vehicles: no bot drove a buggy (best %d px)" % int(best["buggy"]))
			if _cases[_case] == "maker_pads":
				var hz = m.get("_hazards")
				var nl: int = int(hz.bot_launches) - _launch0
				_log.append("maker_pads bot_launches=%d on_island_at=%.1f s (red %.1f s, blue %.1f s)" % [nl, _pad_t,
					float(_pad_arrive.get(2, -1.0)), float(_pad_arrive.get(1, -1.0))])
				if nl == 0:
					_bad.append("maker_pads: no bot used the jump pad")
				if not _pad_arrive.has(1):
					_bad.append("maker_pads: no blue attacker reached the island off the pad in %d s (pad launches %d)" % [PAD_LIMIT_S, nl])
			var moved := 0
			var total := 0
			for b in m.get_tree().get_nodes_in_group("soldier"):
				if not is_instance_valid(b) or not _start_pos.has(b.get_instance_id()):
					continue
				total += 1
				if float(_dist.get(b.get_instance_id(), 0.0)) > 900.0:
					moved += 1
			_log.append("%s bots travelled %d/%d" % [_cases[_case], moved, total])
			if total == 0 or moved * 2 < total:
				_bad.append("%s: bots didn't travel (%d/%d covered > 900 px)" % [_cases[_case], moved, total])
			_case += 1
			if _case >= _cases.size():
				return _end("")
			_st = 0
	return false


func _end(fail: String) -> bool:
	if fail != "":
		_bad.append(fail)
	var st = root.get_node_or_null("Settings")
	if st != null and not _saved.is_empty():
		st.custom_map_path = _saved[0]
		st.game_mode = _saved[1]
		st.bot_count = _saved[2]
		st.map_index = _saved[3]
		st.vehicles = _saved[4]
		st.save()
	var ok := _bad.is_empty()
	print("RTNAV-TEST %s %s%s" % ["ok" if ok else "FAIL", " | ".join(_log), "" if ok else " | " + "; ".join(_bad)])
	quit(0 if ok else 1)
	return true
