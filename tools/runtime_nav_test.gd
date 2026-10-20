extends SceneTree
## Runtime bot navigation (#287, gate stage F).
##   godot --headless --fixed-fps 60 -s tools/runtime_nav_test.gd
## A map with no baked graph (a classic map saved as a custom map under a new
## name, then a map from the editor's generator) must get a graph built in-game
## on a worker thread: non-empty, adopted within the time limit, every CTF leg
## (each team's spawn -> enemy flag -> home) routable, bots actually travel on
## it, and the build must not stall the main thread (frame gaps stay small).
## Then Maker maps (#286): the starter level with spikes and lava pits (no
## nav node on a hazard, no bot walks into one), with a buggy, a tank and a
## heli pad per team (a bot boards a buggy and drives it; tank / heli use is
## logged), and with the red flag on a floating island ~690 px up that only a
## big jump pad reaches (the graph routes the attack over the pad; a bot is
## launched by it and lands on the island), and with a small pad on the walkway
## out of each base that nothing is worth riding to (#294: bots cross them
## without being launched — unintended launches <= 15 % of crossings).
## Zero script errors (the gate greps the log).

const LIMIT_MS := 20000
var _st := 0
var _n := 0
var _t0 := 0
var _bad: Array = []
var _log: Array = []
var _saved := []
var _start_pos := {}
var _last_pos := {}
var _dist := {}
var _max_gap := 0
var _last_ms := 0
var _case := 0
var _cases := ["classic", "generated", "maker_hazards", "maker_vehicles", "maker_pads", "maker_padcross"]
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
var _pc_side := {}      # maker_padcross: "bot:pad" -> which side of the pad's trigger the feet were on
var _pc_last := {}      # maker_padcross: bot -> msec of its last pad launch seen
var _pc_cross := 0      # maker_padcross: crossings near the pad's level
var _pc_un := 0         # ...launches of bots not riding that pad on purpose
var _pc_int := 0        # ...launches of bots whose path rides it
const PC_MIN_CROSS := 4
const PC_MAX_SHARE := 0.15   # unintended launches per crossing at most


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
		elif kind == "maker_padcross":
			# #294: a jump pad on the only walkway out of each base (nothing
			# worth riding to within its reach): every attack crosses one.
			pcs.append(B.make_piece("pad", Vector2(900, 1500), Vector2(64, 20)))
			pcs.append(B.make_piece("pad", Vector2(3900, 1500), Vector2(64, 20)))
		else:
			src["vehicle_spawns"] = [Vector2(900, 1510), Vector2(3900, 1510)]
			src["tank_spawns"] = [Vector2(600, 1510), Vector2(4200, 1510)]
			src["heli_spawns"] = [Vector2(1150, 1510), Vector2(3650, 1510)]
		m = B.compile(src)
		m["name"] = {"maker_hazards": "RTNav Maker Hazards", "maker_pads": "RTNav Maker Pads",
			"maker_padcross": "RTNav Maker Pad Crossing"}.get(kind, "RTNav Maker Vehicles")
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
	if _last_ms > 0 and _st == 2:
		_max_gap = maxi(_max_gap, now - _last_ms)
	_last_ms = now
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
			if m == null or m.get("nav") == null or _n < 3:
				return false
			if not m.nav.is_empty():
				_bad.append("%s: graph present before the runtime build (stale bake?)" % _cases[_case])
			_t0 = now
			_max_gap = 0
			_st = 2
		2:
			var m = current_scene
			if m.nav.is_empty():
				if now - _t0 > LIMIT_MS:
					return _end("%s: no runtime graph after %d ms" % [_cases[_case], LIMIT_MS])
				return false
			_log.append("%s graph %d ms (frame gap max %d ms)" % [_cases[_case], int(m.nav_runtime_ms), _max_gap])
			if _max_gap > 400:
				_bad.append("%s: main thread stalled %d ms during the build" % [_cases[_case], _max_gap])
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
			_pc_side.clear()
			_pc_last.clear()
			_pc_cross = 0
			_pc_un = 0
			_pc_int = 0
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
			if _cases[_case] == "maker_padcross":
				_padcross_tick()
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
			if _cases[_case] == "maker_padcross":
				_log.append("maker_padcross pads=%d crossings=%d launches unintended=%d intended=%d" % [
					m.get("_hazards").pads.size(), _pc_cross, _pc_un, _pc_int])
				if _pc_cross < PC_MIN_CROSS:
					_bad.append("maker_padcross: bots crossed the pads only %d times" % _pc_cross)
				elif float(_pc_un) > maxf(1.0, float(_pc_cross) * PC_MAX_SHARE):
					_bad.append("maker_padcross: %d of %d pad crossings launched a bot that wasn't riding it" % [_pc_un, _pc_cross])
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


## maker_padcross (#294): count bots crossing a pad near its level (feet go
## from one side of its trigger to the other) and pad launches, sorted by
## whether the bot's path meant to ride that pad.
func _padcross_tick() -> void:
	var m = current_scene
	var hz = m.get("_hazards")
	if hz == null:
		return
	for b in m.get_tree().get_nodes_in_group("soldier"):
		if not is_instance_valid(b) or b == m.player or b.get("bot_id") == null or bool(b.get("dead")):
			continue
		var id: int = b.get_instance_id()
		var f: Vector2 = (b as Node2D).global_position
		var lt: int = int(hz._pad_cd.get(id, -1))
		if lt != int(_pc_last.get(id, -1)):
			_pc_last[id] = lt
			if lt >= 0:
				var near_pad := Vector2.INF
				for pd in hz.pads:
					if near_pad == Vector2.INF or (pd["pos"] as Vector2).distance_to(f) < near_pad.distance_to(f):
						near_pad = pd["pos"]
				if _rides_pad(b, m.nav, near_pad):
					_pc_int += 1
				else:
					_pc_un += 1
		for i in hz.pads.size():
			var pp: Vector2 = hz.pads[i]["pos"]
			var k := "%d:%d" % [id, i]
			if f.y < pp.y - 120.0 or f.y > pp.y + 20.0:
				_pc_side.erase(k)
				continue
			var side := -1 if f.x < pp.x - 28.0 else (1 if f.x > pp.x + 28.0 else 0)
			if side == 0:
				continue
			if _pc_side.has(k) and int(_pc_side[k]) == -side:
				_pc_cross += 1
			_pc_side[k] = side


func _rides_pad(b: Node, nav, pad: Vector2) -> bool:
	if int(b.get("_pad_ride")) >= 0:
		return true
	var p: PackedVector2Array = b.get("_path")
	var i0: int = int(b.get("_path_i"))
	if nav == null or not nav.has_method("pad_ride") or pad == Vector2.INF:
		return false
	for k in range(maxi(0, i0 - 1), mini(i0 + 3, p.size() - 1)):
		if p[k].distance_to(pad) < 40.0 and nav.pad_ride(p[k], p[k + 1]) >= 0:
			return true
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
