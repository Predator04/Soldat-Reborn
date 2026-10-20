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
## launched by it and lands on the island).
## #296 maker_basin: Magma Crown with each lava pool's rock basin merged into
## the rock under it (one outline, no designer gap) in Domination — the merged
## outline must give the same nav graph as separate shapes, and bots on a
## contested point must not stand inside each other (they did, shots started
## past the enemy's body and the match froze: all 8 on the hilltop, nobody hit).
## #297 maker_overhang: a floating island 420 px over flat ground with the red
## flag on it and a slab 340 px up — no climb link may start under either
## (bots jetted into the undersides again and again); bots must not keep
## bonking them, and a blue attacker must make it onto the island.
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
var _cases := ["classic", "generated", "maker_hazards", "maker_vehicles", "maker_pads", "maker_basin", "maker_overhang"]
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
const CASE_MODE := {"maker_basin": 7}   # default CTF (2)
const CASE_BOTS := {"maker_basin": 8}   # default 6
const BASIN_SECS := 40          # maker_basin: match length watched
const BASIN_STACK_MAX := 6.0    # maker_basin: longest a blue + a red bot may stand inside each other on a point
const OVERHANG_ISLAND := Rect2(3500, 1090, 400, 80)   # maker_overhang: the island (flag on top)...
const OVERHANG_SLAB := Rect2(2220, 1170, 360, 60)     # ...and a plain slab hanging over the valley
const OVERHANG_MIN_S := 30      # maker_overhang: watched at least this long...
const OVERHANG_LIMIT_S := 75    # ...and until a blue attacker made it up to the island (at most this)
const OVERHANG_BONKS := 3       # maker_overhang: a bot hitting an underside this often = jetting into it
var _kills := 0
var _dom_events := 0
var _stack_run := 0.0
var _stack_max := 0.0
var _bonk := {}         # maker_overhang: bot instance id -> underside hits
var _bonk_on := {}
var _top_t := -1.0      # maker_overhang: seconds until a blue bot made it up to the island


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
		elif kind == "maker_basin":
			src = _basin_source()
		elif kind == "maker_overhang":
			src = _overhang_source()
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
		if kind == "maker_basin":
			_check_basin_geometry(src, m)
		m.erase("_mk_outlines")
		m["name"] = {"maker_hazards": "RTNav Maker Hazards", "maker_pads": "RTNav Maker Pads", "maker_basin": "RTNav Maker Basin",
			"maker_overhang": "RTNav Maker Overhang"}.get(kind, "RTNav Maker Vehicles")
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
			st.game_mode = int(CASE_MODE.get(_cases[_case], 2))
			st.bot_count = int(CASE_BOTS.get(_cases[_case], 6))
			root.get_node("Net").set_singleplayer()
			change_scene_to_file("res://scenes/main.tscn")
			_st = 1
			_n = 0
		1:
			var m = current_scene
			if m == null or m.get("nav") == null or _n < 3:
				return false
			# (A small map's build can already be adopted after a slow first
			# frame or two under load: only a graph main didn't build is stale.)
			if not m.nav.is_empty() and int(m.nav_runtime_ms) < 0:
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
			if _cases[_case] == "maker_overhang":
				_check_overhang_links(m)
			if _cases[_case] == "maker_basin":
				# DOM legs: each team's spawn <-> every point.
				var broken := 0
				for dp in m.dom_points():
					var op: Vector2 = m._settle_on_ground((dp as Node2D).global_position)
					for t in [1, 2]:
						var sp: Array = m._team_spawn_list(t)
						var s: Vector2 = m._settle_on_ground(sp[0])
						if not _ok(m.nav, s, op) or not _ok(m.nav, op, s):
							broken += 1
				_log.append("maker_basin dom legs broken=%d" % broken)
				if broken > 0:
					_bad.append("maker_basin: %d spawn <-> DOM point legs unroutable" % broken)
			_kills = 0
			_dom_events = 0
			_stack_run = 0.0
			_stack_max = 0.0
			_bonk.clear()
			_bonk_on.clear()
			_top_t = -1.0
			if not m.kill.is_connected(_on_kill):
				m.kill.connect(_on_kill)
			if not m.objective.is_connected(_on_objective):
				m.objective.connect(_on_objective)
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
			if _cases[_case] == "maker_basin":
				_track_stack(current_scene)
			if _cases[_case] == "maker_overhang":
				_track_bonks(current_scene)
			# maker_pads runs on (up to PAD_LIMIT_S) until an attacker made the trip.
			if _n < 60 * 25 or (_cases[_case] == "maker_pads" and not _pad_arrive.has(1) and _n < 60 * PAD_LIMIT_S):
				return false
			if _cases[_case] == "maker_basin" and _n < 60 * BASIN_SECS:
				return false
			if _cases[_case] == "maker_overhang" and (_n < 60 * OVERHANG_MIN_S or (_top_t < 0.0 and _n < 60 * OVERHANG_LIMIT_S)):
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
			if _cases[_case] == "maker_basin":
				_log.append("maker_basin kills=%d dom_events=%d longest_stack=%.1f s" % [_kills, _dom_events, _stack_max])
				if _stack_max >= BASIN_STACK_MAX:
					_bad.append("maker_basin: a blue and a red bot stood inside each other on a point for %.1f s (kills %d, captures %d)" % [_stack_max, _kills, _dom_events])
				if _kills == 0:
					_bad.append("maker_basin: no kills in %d s of Domination" % BASIN_SECS)
			if _cases[_case] == "maker_overhang":
				var worst := 0
				var tot := 0
				for k in _bonk:
					worst = maxi(worst, int(_bonk[k]))
					tot += int(_bonk[k])
				_log.append("maker_overhang underside_hits=%d worst_bot=%d blue_on_island_at=%.1f s" % [tot, worst, _top_t])
				if worst >= OVERHANG_BONKS:
					_bad.append("maker_overhang: a bot hit a platform's underside %d times" % worst)
				if _top_t < 0.0:
					_bad.append("maker_overhang: no blue attacker made it up to the island in %d s" % OVERHANG_LIMIT_S)
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


func _on_kill(_a, _b, _c, _d, _e) -> void:
	_kills += 1


func _on_objective(kind: String, _t: int, _w: String) -> void:
	if kind == "dom":
		_dom_events += 1


## #296: Magma Crown's source with every rock piece just under a lava basin
## pulled up against it, so basin + rock + neighbours union into one outline
## (the layout the designer first had to keep 3 px apart).
func _basin_source() -> Dictionary:
	var src: Dictionary = load("res://scripts/featured_levels.gd").source("magma_crown")
	_set_basin_gap(src, 0.0)
	return src


## Put the top of every ground piece that sits within 8 px under a lava
## basin's floor `gap` px under it. Returns how many pieces it moved.
func _set_basin_gap(src: Dictionary, gap: float) -> int:
	var B = load("res://scripts/maker/maker_build.gd")
	var pcs: Array = src["maker"]["pieces"]
	var moved := 0
	for lv in pcs.duplicate():
		if str(lv["t"]) != "lava":
			continue
		var lr: Rect2 = B.piece_rect(lv)   # the pool + its basin
		for i in pcs.size():
			var q: Dictionary = pcs[i]
			if not (str(q["t"]) in ["block", "wide"]):
				continue
			var r: Rect2 = B.piece_rect(q)
			if r.end.x <= lr.position.x or r.position.x >= lr.end.x or absf(r.position.y - lr.end.y) > 8.0:
				continue
			var top := lr.end.y + gap
			pcs[i] = B.make_piece(str(q["t"]), Vector2(r.get_center().x, (top + r.end.y) * 0.5), Vector2(r.size.x, r.end.y - top))
			moved += 1
	return moved


## #296: the merged outline must not change what bots can do: the nav graph
## must match the same map with the basins kept 3 px apart.
func _check_basin_geometry(src: Dictionary, merged: Dictionary) -> void:
	var B = load("res://scripts/maker/maker_build.gd")
	var NB = load("res://scripts/nav_builder.gd")
	var apart: Dictionary = src.duplicate(true)
	var n := _set_basin_gap(apart, 3.0)
	var sep: Dictionary = B.compile(apart)
	var om := _solid_outlines(merged)
	var os := _solid_outlines(sep)
	if n < 2 or om >= os:
		_bad.append("maker_basin: the basins didn't merge (%d rocks moved, outlines merged %d vs apart %d)" % [n, om, os])
	var pm := _node_set(NB.build(merged))
	var ps := _node_set(NB.build(sep))
	var only := 0
	for k in pm:
		if not ps.has(k):
			only += 1
	for k in ps:
		if not pm.has(k):
			only += 1
	_log.append("maker_basin outlines merged=%d apart=%d nodes %d / %d (differ %d)" % [om, os, pm.size(), ps.size(), only])
	if only > maxi(2, (pm.size() + ps.size()) / 100):
		_bad.append("maker_basin: merged basins change the nav graph (%d of %d / %d nodes differ)" % [only, pm.size(), ps.size()])


func _solid_outlines(m: Dictionary) -> int:
	var k := 0
	for o in m.get("_mk_outlines", []):
		if int(o["col"]) == 0:
			k += 1
	return k


func _node_set(g: Dictionary) -> Dictionary:
	var out := {}
	var nodes: Array = g.get("nodes", [])
	var i := 0
	while i + 1 < nodes.size():
		out[Vector2i(int(round(float(nodes[i]) / 8.0)), int(round(float(nodes[i + 1]) / 8.0)))] = true
		i += 2
	return out


## Bots on a DOM point: a blue and a red one (alive, standing) within 12 px of
## each other = inside each other, where no shot can hit.
func _track_stack(m: Node) -> void:
	var on: Array = []
	for b in m.get_tree().get_nodes_in_group("soldier"):
		if is_instance_valid(b) and b != m.player and not bool(b.get("dead")) and (b as CharacterBody2D).is_on_floor():
			for dp in m.dom_points():
				if (b.global_position as Vector2).distance_to((dp as Node2D).global_position) < 60.0:
					on.append(b)
					break
	var stacked := false
	for i in on.size():
		for j in range(i + 1, on.size()):
			var a: Node2D = on[i]
			var c: Node2D = on[j]
			if int(a.get("team")) != int(c.get("team")) and absf(a.global_position.x - c.global_position.x) < 12.0 \
					and absf(a.global_position.y - c.global_position.y) < 16.0:
				stacked = true
	_stack_run = _stack_run + 1.0 / 60.0 if stacked else 0.0
	_stack_max = maxf(_stack_max, _stack_run)


## #297: flat ground, the red flag on a floating island 420 px up, a slab
## 340 px over the valley.
func _overhang_source() -> Dictionary:
	var B = load("res://scripts/maker/maker_build.gd")
	var src := {"name": "", "platforms": [], "ladders": [], "bot_spawns": [], "player_spawn": Vector2(400, 1500)}
	var pcs: Array = []
	for x in [600.0, 1800.0, 3000.0, 4200.0]:
		pcs.append(B.make_piece("wide", Vector2(x, 1660), Vector2(1200, 300)))
	pcs.append(B.make_piece("float", OVERHANG_ISLAND.get_center(), OVERHANG_ISLAND.size))
	pcs.append(B.make_piece("block", OVERHANG_SLAB.get_center(), OVERHANG_SLAB.size))
	src["maker"] = {"v": 1, "theme": "grassland", "grid": 20, "w": 4800.0, "h": 2000.0, "bottom": "void", "pieces": pcs}
	src["team_spawns"] = {1: [Vector2(300, 1506), Vector2(600, 1506)], 2: [Vector2(4300, 1506), Vector2(4550, 1506)]}
	src["ctf_flags"] = [Vector2(400, 1506), Vector2(OVERHANG_ISLAND.get_center().x, OVERHANG_ISLAND.position.y - 4.0)]
	return src


## No climb link may start under a platform: straight up from its start a
## soldier would hit terrain before the link's top.
func _check_overhang_links(m: Node) -> void:
	var nav = m.nav
	var space: PhysicsDirectSpaceState2D = (m as Node2D).get_world_2d().direct_space_state
	var under := 0
	var climbs := 0
	var ex: Array = []
	for u in nav.astar.get_point_ids():
		var a: Vector2 = nav.astar.get_point_position(u)
		for v in nav.astar.get_point_connections(u):
			var b: Vector2 = nav.astar.get_point_position(v)
			if b.y > a.y - 90.0:
				continue
			climbs += 1
			for sx in [-6.0, 6.0]:
				var from := Vector2(a.x + sx, a.y - 20.0)
				var q := PhysicsRayQueryParameters2D.create(from, Vector2(from.x, b.y - 4.0), 1 | 4)
				var hit := space.intersect_ray(q)
				if not hit.is_empty() and hit.get("collider") is StaticBody2D:
					under += 1
					if ex.size() < 4:
						ex.append("%s->%s" % [str(Vector2i(a)), str(Vector2i(b))])
					break
	_log.append("maker_overhang climb_links=%d from_under=%d" % [climbs, under])
	if climbs == 0:
		_bad.append("maker_overhang: no climb links onto the platforms")
	if under > 0:
		_bad.append("maker_overhang: %d climb links start under a platform (%s)" % [under, ", ".join(ex)])


## Underside hits: a bot pressed against the bottom of the island / slab.
func _track_bonks(m: Node) -> void:
	for b in m.get_tree().get_nodes_in_group("soldier"):
		if not is_instance_valid(b) or b == m.player or bool(b.get("dead")):
			continue
		var id: int = b.get_instance_id()
		var gp: Vector2 = b.global_position
		var hit := false
		if (b as CharacterBody2D).is_on_ceiling():
			for r: Rect2 in [OVERHANG_ISLAND, OVERHANG_SLAB]:
				if gp.x > r.position.x - 8.0 and gp.x < r.end.x + 8.0 and gp.y > r.position.y + 20.0 and gp.y < r.end.y + 40.0:
					hit = true
		if hit and not bool(_bonk_on.get(id, false)):
			_bonk[id] = int(_bonk.get(id, 0)) + 1
		_bonk_on[id] = hit
		# A blue attacker made the climb: on the island's top, or up beside its
		# lip at the height of the top (red defends up there and often shoots
		# it before the feet touch down).
		if _top_t < 0.0 and int(b.get("team")) == 1 and gp.x > OVERHANG_ISLAND.position.x - 40.0 and gp.x < OVERHANG_ISLAND.end.x + 40.0 \
				and gp.y < OVERHANG_ISLAND.position.y + 4.0 and gp.y > OVERHANG_ISLAND.position.y - 60.0:
			_top_t = float(_n) / 60.0


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
