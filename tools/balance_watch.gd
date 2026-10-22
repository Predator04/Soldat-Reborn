extends SceneTree
## Dev tool (#310, not shipped logic): weapon / vehicle balance measurements.
## Results go to resumable JSONL files (one line per duel cell / match run; a
## cell or run already in the file is skipped, so a killed process just
## continues where it stopped). `tools/balance_report.py` turns them into tables.
##
## Duel harness (deterministic: seeded spread + strafe pattern):
##   godot --headless --fixed-fps 60 -s tools/balance_watch.gd -- --duel \
##       [--weapons=AK-74,LAW] [--dists=100,300,600,1000] [--trials=8] \
##       [--out=build/balance/duel.jsonl] [--tag=before] [--max-wall=1200]
##   A scripted shooter fires the REAL weapon table (player.gd `weapons` /
##   `secondary`: damage, rate, mag, reload, spread, pellets, wind-up, speed,
##   gravity) through player.net_shoot, so bullets / rockets / splash are the
##   game's own code. Aim is perfect (leads the target by its velocity; lobs
##   for M79 / Bow); only the gun's own spread misses. Target = a bot with its
##   AI off on flat ground, standing or strafing at the player run speed with
##   seeded direction flips every 0.25-0.8 s (within +-160 px). It soaks damage
##   (huge HP) so time-to-kill = time until 100 damage landed. Self-damage of
##   the shooter (splash) is recorded too.
##
## Bot matches with forced loadouts:
##   godot --headless --fixed-fps 60 -s tools/balance_watch.gd -- --match \
##       --runs=0:dm,18:tdm,55:ctf,f.downtown:bomb [--secs=240] [--bots=8] \
##       [--reps=1] [--out=build/balance/match.jsonl] [--tag=before] [--max-wall=1200]
##   One match per process (the run list is walked until one not yet in the
##   file is found; exit code 3 = all done). Every bot holds an assigned
##   loadout (the 12 primaries + LAW, rotated per run so every gun gets equal
##   time on every team); per weapon: alive-seconds held, kills, damage,
##   hit events, projectiles fired, time-to-kill, kill distance, self-kills;
##   per vehicle kind: crewed seconds, lifetime, wrecks + what wrecked it,
##   kills, damage dealt to soldiers.
##   Bots fire at their own cadence (bot.gd WEAPON_STATS), not the player's —
##   weigh the duel numbers for the gun itself.
##
## Gate F `wbal` (BALANCE-TEST):
##   godot --headless --fixed-fps 60 -s tools/balance_watch.gd -- --gate
##   Duel harness, nothing written: every gun must kill a standing target
##   within GATE_LIMITS at its intended range, and no gun may be the fastest
##   killer of a strafing target at every distance (100 / 300 / 600 / 1000).

const MODE_IDX := {"dm": 0, "tdm": 1, "ctf": 2, "inf": 3, "htf": 4, "rm": 5, "pm": 6, "dom": 7, "br": 8, "gg": 9, "bomb": 10}
const LOADOUTS := ["Deagles", "MP5", "AK-74", "Steyr AUG", "Spas-12", "Ruger 77", "M79", "Barrett",
	"Minimi", "Minigun", "Flamethrower", "Rambo Bow", "LAW"]
const VEHICLE_WEAPONS := ["Buggy", "Tank", "Heli", "Plane", "Buggy MG", "Plane MG"]
const STRAFE_SPEED := 205.0     # player.gd RUN_SPEED
const STRAFE_RANGE := 160.0
const DUEL_CAP := 10.0          # s: a trial that hasn't killed by then counts as "no kill"
# Gate: weapon -> [intended range px, max median time-to-kill s vs a standing target].
const GATE_LIMITS := {
	"Deagles": [300, 1.6], "MP5": [100, 1.2], "AK-74": [300, 1.6], "Steyr AUG": [300, 1.6],
	"Spas-12": [100, 1.6], "Ruger 77": [600, 1.6], "M79": [300, 5.0], "Barrett": [1000, 1.2],
	"Minimi": [600, 2.5], "Minigun": [100, 1.6], "Flamethrower": [100, 1.0], "Rambo Bow": [600, 1.5],
	"USSOCOM": [300, 1.6], "LAW": [600, 5.5],
}

var _mode := ""
var _gate := false
var _gate_rows: Array = []
var _out := ""
var _tag := "now"
var _max_wall := 1200.0
var _wall0 := 0
var _st := 0
var _t := 0.0
var _m: Node = null

# ── duel state ──
var _weapons_f: Array = []
var _dists: Array = [100, 300, 600, 1000]
var _trials := 8
var _cells: Array = []          # [weapon_name, slot, dist, motion]
var _ci := -1
var _trial := 0
var _shooter: Node = null
var _target: Node = null
var _cell_res: Array = []
var _tr: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _done_keys := {}

# ── match state ──
var _runs: Array = []
var _secs := 240.0
var _bots := 8
var _reps := 1
var _run: Dictionary = {}
var _assign := {}               # bot display name -> loadout
var _w := {}                    # weapon -> stats dict
var _veh := {}                  # instance id -> tracking dict
var _vk := {}                   # vehicle kind -> stats dict
var _prev_hp := {}              # soldier instance id -> last health
var _eng_t0 := {}               # soldier instance id -> time of first damage since full
var _kills_total := 0
var _last_gun := {}             # bot display name -> what it last held ("veh:<kind>" when seated)


func _initialize() -> void:
	_wall0 = Time.get_ticks_msec()
	for a in OS.get_cmdline_user_args():
		if a == "--duel": _mode = "duel"
		elif a == "--gate":
			_mode = "duel"
			_gate = true
			_trials = 4
		elif a == "--match": _mode = "match"
		elif a.begins_with("--weapons="): _weapons_f = Array(a.substr(10).split(",", false))
		elif a.begins_with("--dists="):
			_dists = []
			for s in a.substr(8).split(",", false): _dists.append(int(s))
		elif a.begins_with("--trials="): _trials = int(a.substr(9))
		elif a.begins_with("--out="): _out = a.substr(6)
		elif a.begins_with("--tag="): _tag = a.substr(6)
		elif a.begins_with("--max-wall="): _max_wall = float(a.substr(11))
		elif a.begins_with("--runs="): _runs = Array(a.substr(7).split(",", false))
		elif a.begins_with("--secs="): _secs = float(a.substr(7))
		elif a.begins_with("--bots="): _bots = int(a.substr(7))
		elif a.begins_with("--reps="): _reps = int(a.substr(7))
	if _out == "":
		_out = "res://build/balance/%s.jsonl" % ("duel" if _mode == "duel" else "match")
	if not _out.begins_with("res://") and not _out.begins_with("/"):
		_out = "res://" + _out
	if _gate:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out.get_base_dir()))
	_load_done()


func _load_done() -> void:
	if not FileAccess.file_exists(_out):
		return
	var f := FileAccess.open(_out, FileAccess.READ)
	while f != null and not f.eof_reached():
		var ln := f.get_line().strip_edges()
		if ln == "":
			continue
		var d = JSON.parse_string(ln)
		if typeof(d) == TYPE_DICTIONARY and d.has("key"):
			_done_keys[str(d["key"])] = true


func _append(d: Dictionary) -> void:
	var f: FileAccess
	if FileAccess.file_exists(_out):
		f = FileAccess.open(_out, FileAccess.READ_WRITE)
		f.seek_end()
	else:
		f = FileAccess.open(_out, FileAccess.WRITE)
	f.store_line(JSON.stringify(d))
	f.close()
	_done_keys[str(d["key"])] = true


func _wall_out() -> bool:
	return float(Time.get_ticks_msec() - _wall0) / 1000.0 > _max_wall


func _process(d: float) -> bool:
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _mode == "duel":
		return _duel_tick(d, st)
	if _mode == "match":
		return _match_tick(d, st)
	print("BALANCE usage: --duel | --match (see the header of tools/balance_watch.gd)")
	quit(2)
	return true


# ════════════════════════════ duel harness ════════════════════════════

func _duel_tick(d: float, st) -> bool:
	match _st:
		0:
			var MapIO = load("res://scripts/map_io.gd")
			var m := {"name": "qa_duel", "platforms": [], "player_spawn": Vector2(600, 1880),
				"bot_spawns": [Vector2(3600, 1880)]}
			st.set("custom_map_path", MapIO.save_to_file("qa_duel", m))
			st.set("game_mode", 0)
			st.set("bot_count", 0)
			st.set("vehicles", false)
			st.set("realistic", false)
			root.get_node("Net").set_singleplayer()
			change_scene_to_file("res://scenes/main.tscn")
			_st = 1
		1:
			_m = current_scene
			if _m == null or _m.get("MAPS") == null or _m.get("player") == null:
				return false
			_t += d
			if _t < 0.5:
				return false
			_shooter = _m.player
			_shooter.set_physics_process(false)
			_m._spawn_bot(Vector2(2000, 1880), _m.FFA_BOT_TEAM_BASE + 7, "DuelTarget", "AK-74")
			_st = 2
		2:
			for s in get_nodes_in_group("soldier"):
				if is_instance_valid(s) and str(s.get("display_name")) == "DuelTarget":
					_target = s
			if _target == null:
				return false
			_target.set_physics_process(false)
			_build_cells()
			print("BALANCE duel cells=%d (already done %d)" % [_cells.size(), _done_keys.size()])
			_st = 3
			_next_cell()
		3:
			if _ci >= _cells.size():
				print("BALANCE duel done")
				if _gate:
					_gate_verdict()
				quit(0)
				return true
			_duel_step(d)
	return false


func _build_cells() -> void:
	var pl = _shooter
	var lists := [[pl.weapons, 0], [pl.secondary, 100]]
	for pair in lists:
		var arr: Array = pair[0]
		for i in arr.size():
			var w: Dictionary = arr[i]
			var kind := str(w.get("kind", "bullet"))
			if kind == "melee" or kind == "melee_cont":
				continue
			var wn := str(w["name"])
			if not _weapons_f.is_empty() and not _weapons_f.has(wn):
				continue
			if _gate:
				if GATE_LIMITS.has(wn):
					_cells.append([wn, int(pair[1]) + i, int(GATE_LIMITS[wn][0]), "stand"])
				for dist in [100, 300, 600, 1000]:
					_cells.append([wn, int(pair[1]) + i, dist, "strafe"])
				continue
			for dist in _dists:
				for motion in ["stand", "strafe"]:
					_cells.append([wn, int(pair[1]) + i, int(dist), motion])


func _gate_verdict() -> void:
	var bad: Array = []
	var seen := {}
	for r in _gate_rows:
		var wn := str(r["weapon"])
		if r["motion"] == "stand" and GATE_LIMITS.has(wn):
			seen[wn] = true
			var lim: float = float(GATE_LIMITS[wn][1])
			var t: float = float(r["ttk_med"])
			if int(r["kills"]) * 2 <= int(r["trials"]) or t < 0.0 or t > lim:
				bad.append("%s %dpx standing ttk %.2f > %.2f" % [wn, int(r["dist"]), t, lim])
	for wn in GATE_LIMITS:
		if not seen.has(wn):
			bad.append("%s not measured" % wn)
	var best := {}
	for dist in [100, 300, 600, 1000]:
		var bw := ""
		var bt := INF
		for r in _gate_rows:
			if r["motion"] != "strafe" or int(r["dist"]) != dist or int(r["kills"]) * 2 <= int(r["trials"]):
				continue
			if float(r["ttk_med"]) < bt:
				bt = float(r["ttk_med"])
				bw = str(r["weapon"])
		best[dist] = bw
	var firsts: Array = best.values()
	if firsts.size() == 4 and firsts.count(firsts[0]) == 4 and str(firsts[0]) != "":
		bad.append("%s is the fastest killer at every range" % firsts[0])
	if bad.is_empty():
		print("BALANCE-TEST ok %d guns at their range, fastest by range %s" % [seen.size(), str(best)])
	else:
		print("BALANCE-TEST FAIL " + "; ".join(bad))


func _cell_key(c: Array) -> String:
	return "%s|%s|%d|%s" % [_tag, c[0], c[2], c[3]]


func _next_cell() -> void:
	while true:
		_ci += 1
		if _ci >= _cells.size():
			return
		if not _done_keys.has(_cell_key(_cells[_ci])):
			break
	_trial = 0
	_cell_res = []
	_start_trial()


var _art_s = null
func _art():
	if _art_s == null:
		_art_s = load("res://scripts/soldier_art.gd")
	return _art_s


func _w_of(slot: int) -> Dictionary:
	return _shooter.call("_weapon_for_slot", slot)


func _start_trial() -> void:
	var c: Array = _cells[_ci]
	var w := _w_of(int(c[1]))
	var gy: float = float(_m.get("GROUND_Y"))
	var sx := 1200.0
	_shooter.global_position = Vector2(sx, gy)
	_shooter.velocity = Vector2.ZERO
	_shooter.set("health", 100000.0)
	_shooter.set("dead", false)
	_shooter.set("facing", 1.0)
	_target.global_position = Vector2(sx + float(c[2]), gy)
	_target.velocity = Vector2.ZERO
	_target.set("health", 100000.0)
	_target.set("bink_t", 0.0)
	seed(hash("%s|%d|%s|%d" % [c[0], c[2], c[3], _trial]))
	_rng.seed = hash("strafe|%d|%d" % [c[2], _trial])
	# Clear stray projectiles of the previous trial.
	for n in _m.get_children():
		var sc = n.get_script()
		if sc != null and (str(sc.resource_path).ends_with("bullet.gd") or str(sc.resource_path).ends_with("rocket.gd")):
			n.queue_free()
	_tr = {"t": 0.0, "fire_cd": 0.0, "mag": int(w["mag"]), "reload_t": 0.0, "spin": 0.0,
		"shots": 0, "proj": 0, "hits": 0, "dmg_t": 0.0, "self": 0.0, "ttk": -1.0,
		"dir": 1.0 if _rng.randf() < 0.5 else -1.0, "flip": _rng.randf_range(0.25, 0.8),
		"home": sx + float(c[2]), "settle": 3, "dist_hit": []}


func _duel_step(d: float) -> void:
	var c: Array = _cells[_ci]
	var w := _w_of(int(c[1]))
	_target.set("ceasefire_t", 0.0)
	_shooter.set("ceasefire_t", 0.0)
	_m.set("time_left", 9999.0)   # no match end / round reset mid-measurement
	_shooter.set_physics_process(false)
	_target.set_physics_process(false)
	# Damage accounting from the previous frame's physics (per-frame deltas,
	# HP topped back up every frame; a reset to 100 HP is not "damage").
	var landed: float = 100000.0 - float(_target.get("health"))
	if landed > 0.001 and landed < 50000.0:
		_tr["hits"] = int(_tr["hits"]) + 1
		_tr["dmg_t"] = float(_tr["dmg_t"]) + landed
	var selfd: float = 100000.0 - float(_shooter.get("health"))
	if selfd > 0.001 and selfd < 50000.0:
		_tr["self"] = float(_tr["self"]) + selfd
	_target.set("health", 100000.0)
	_shooter.set("health", 100000.0)
	_target.set("dead", false)
	_shooter.set("dead", false)
	if float(_tr["dmg_t"]) >= 100.0 and float(_tr["ttk"]) < 0.0:
		_tr["ttk"] = float(_tr["t"])
	if float(_tr["ttk"]) >= 0.0 or float(_tr["t"]) >= DUEL_CAP:
		_finish_trial(w)
		return
	if int(_tr["settle"]) > 0:
		_tr["settle"] = int(_tr["settle"]) - 1
		return
	_tr["t"] = float(_tr["t"]) + d
	# Target motion.
	if str(c[3]) == "strafe":
		_tr["flip"] = float(_tr["flip"]) - d
		var x: float = _target.global_position.x
		var home: float = float(_tr["home"])
		if float(_tr["flip"]) <= 0.0 or (x > home + STRAFE_RANGE and float(_tr["dir"]) > 0.0) or (x < home - STRAFE_RANGE and float(_tr["dir"]) < 0.0):
			_tr["dir"] = -float(_tr["dir"])
			_tr["flip"] = _rng.randf_range(0.25, 0.8)
		var v := Vector2(float(_tr["dir"]) * STRAFE_SPEED, 0.0)
		_target.velocity = v
		_target.global_position += v * d
	# Shooter cadence: exactly the weapon table.
	if float(_tr["reload_t"]) > 0.0:
		_tr["reload_t"] = float(_tr["reload_t"]) - d
		if float(_tr["reload_t"]) <= 0.0:
			_tr["mag"] = int(w["mag"])
		return
	_tr["fire_cd"] = float(_tr["fire_cd"]) - d
	var startup: float = float(w.get("startup", 0.0))
	if startup > 0.0:
		_tr["spin"] = float(_tr["spin"]) + d
	if float(_tr["fire_cd"]) > 0.0 or (startup > 0.0 and float(_tr["spin"]) < startup):
		return
	var aim := _duel_aim(w)
	if aim == Vector2.ZERO:
		return   # out of a launcher's reach: hold fire
	var sp: float = float(w["spread"])
	var dirs := PackedVector2Array()
	for _i in int(w["pellets"]):
		dirs.append(aim.rotated(randf_range(-sp, sp)))
	_shooter.aim_dir = aim
	var muzzle: Vector2 = _shooter.global_position + _art().muzzle_local(_shooter, aim, 1.0, str(w["name"]))
	_shooter.net_shoot(muzzle, dirs, int(c[1]), 0)
	if OS.get_environment("DUEL_DEBUG") != "":
		print("shot muzzle ", muzzle, " dirs ", dirs, " shooter ", _shooter.global_position)
		for n in _m.get_children():
			if n.get("blast_radius") != null and not n.is_connected("tree_exiting", _dbg_gone):
				n.tree_exiting.connect(_dbg_gone.bind(n))
	_tr["shots"] = int(_tr["shots"]) + 1
	_tr["proj"] = int(_tr["proj"]) + int(w["pellets"])
	_tr["fire_cd"] = float(w["rate"])
	if not bool(w.get("auto", false)):
		_tr["spin"] = 0.0   # every semi-auto wind-up shot spins up again
	_tr["mag"] = int(_tr["mag"]) - 1
	if int(_tr["mag"]) <= 0:
		_tr["reload_t"] = float(w["reload"])


func _dbg_gone(n: Node) -> void:
	print("rocket gone at ", (n as Node2D).global_position, " t=", _tr.get("t"))


## Perfect aim at the target's chest, leading it by its velocity over the
## projectile's flight time; ballistic weapons solve the low arc.
func _duel_aim(w: Dictionary) -> Vector2:
	var spd: float = float(w["speed"])
	var kind := str(w.get("kind", "bullet"))
	var grav: float = float(w.get("gravity", 0.0))
	if kind == "launcher":
		grav *= float(root.get_node("MatchConfig").mod_gravity())
	var muzzle0: Vector2 = _shooter.global_position + Vector2(0, -12)
	var tp: Vector2 = _target.global_position + Vector2(0, -12)
	var aim_pt := tp
	for _k in 3:
		var tof: float = muzzle0.distance_to(aim_pt) / spd
		aim_pt = tp + _target.velocity * tof
	var to := aim_pt - muzzle0
	if OS.get_environment("DUEL_DEBUG") != "":
		print("aim from ", muzzle0, " to ", aim_pt)
	if grav > 0.0:
		var x: float = absf(to.x)
		var y: float = -to.y
		var v2 := spd * spd
		var disc: float = v2 * v2 - grav * (grav * x * x + 2.0 * y * v2)
		if disc < 0.0:
			return Vector2.ZERO
		var ang: float = atan((v2 - sqrt(disc)) / (grav * maxf(x, 1.0)))
		return Vector2(cos(ang) * signf(to.x if absf(to.x) > 0.0 else 1.0), -sin(ang))
	return to.normalized()


func _finish_trial(w: Dictionary) -> void:
	_cell_res.append({"ttk": float(_tr["ttk"]), "shots": int(_tr["shots"]), "proj": int(_tr["proj"]),
		"hits": int(_tr["hits"]), "dmg": float(_tr["dmg_t"]), "self": float(_tr["self"]), "t": float(_tr["t"])})
	_trial += 1
	var c: Array = _cells[_ci]
	var n := _trials
	if _trial < n:
		_start_trial()
		return
	var ttks: Array = []
	var kills := 0
	var shots := 0
	var proj := 0
	var hits := 0
	var dmg := 0.0
	var selfd := 0.0
	var tsum := 0.0
	for r in _cell_res:
		shots += int(r["shots"])
		proj += int(r["proj"])
		hits += int(r["hits"])
		dmg += float(r["dmg"])
		selfd = maxf(selfd, float(r["self"]))
		tsum += float(r["t"])
		if float(r["ttk"]) >= 0.0:
			kills += 1
			ttks.append(float(r["ttk"]))
		else:
			ttks.append(INF)
	ttks.sort()
	var med: float = ttks[ttks.size() / 2]
	var line := {"key": _cell_key(c), "tag": _tag, "weapon": c[0], "dist": c[2], "motion": c[3], "trials": _cell_res.size(),
		"kills": kills, "ttk_med": med if med != INF else -1.0, "ttk_all": ttks.map(func(x): return x if x != INF else -1.0),
		"shots": shots, "proj": proj, "hit_events": hits, "dmg": snappedf(dmg, 0.1),
		"dmg_per_shot": snappedf(dmg / maxf(1.0, float(shots)), 0.1),
		"dmg_per_hit": snappedf(dmg / maxf(1.0, float(hits)), 0.1),
		"dps": snappedf(dmg / maxf(0.01, tsum), 0.1), "self_max": snappedf(selfd, 0.1),
		"damage": float(w["damage"]), "rate": float(w["rate"])}
	if _gate:
		_gate_rows.append(line)
	else:
		_append(line)
	print("BALANCE duel %-12s %4dpx %-6s kills %d/%d ttk_med %s dmg/shot %.1f self %.0f" % [c[0], c[2], c[3], kills,
		_cell_res.size(), ("%.2f" % med) if med != INF else "-", float(line["dmg_per_shot"]), selfd])
	if not _gate and _wall_out():
		print("BALANCE duel wall limit; resume later")
		quit(0)
		return
	_next_cell()


# ════════════════════════════ bot matches ════════════════════════════

func _run_key(spec: String, rep: int) -> String:
	return "%s|%s|r%d|b%d|s%d" % [_tag, spec, rep, _bots, int(_secs)]


func _match_tick(d: float, st) -> bool:
	match _st:
		0:
			var pick := ""
			var rep := 0
			var ri := 0
			for r in _reps:
				for i in _runs.size():
					if not _done_keys.has(_run_key(str(_runs[i]), r)):
						pick = str(_runs[i])
						rep = r
						ri = i
						break
				if pick != "":
					break
			if pick == "":
				print("BALANCE match all runs done")
				quit(3)
				return true
			var parts := pick.split(":")
			var where := parts[0]
			var mode := parts[1] if parts.size() > 1 else "dm"
			_run = {"spec": pick, "rep": rep, "idx": ri + rep * _runs.size(), "where": where, "mode": mode}
			st.set("bot_count", _bots)
			st.set("game_mode", int(MODE_IDX[mode]))
			st.set("vehicles", true)
			if where.begins_with("f."):
				var FL = load("res://scripts/featured_levels.gd")
				st.set("custom_map_path", FL.local_copy(where.substr(2)))
			else:
				st.set("custom_map_path", "")
				st.set("map_index", int(where))
			seed(hash(_run_key(pick, rep)))
			root.get_node("Net").set_singleplayer()
			change_scene_to_file("res://scenes/main.tscn")
			print("BALANCE match start %s rep %d" % [pick, rep])
			_st = 1
		1:
			_m = current_scene
			if _m == null or _m.get("MAPS") == null or _m.get("player") == null:
				return false
			var p = _m.player
			p.remove_from_group("soldier")
			p.set_physics_process(false)
			p.global_position = Vector2(-4000, -4000)
			p.set("health", 100000.0)
			_m.kill.connect(_on_kill)
			node_added.connect(_on_node_added)
			_t = 0.0
			_st = 2
		2:
			_t += d
			_match_poll(d)
			if _t >= _secs:
				_match_report()
				quit(0)
				return true
	return false


func _ws(wn: String) -> Dictionary:
	if not _w.has(wn):
		_w[wn] = {"alive_s": 0.0, "active_s": 0.0, "kills": 0, "deaths": 0, "dmg": 0.0, "hits": 0, "proj": 0,
			"ttk_sum": 0.0, "ttk_n": 0, "dist_sum": 0.0, "dist_n": 0, "self": 0, "kills_holder": 0}
	return _w[wn]


func _vs(kind: String) -> Dictionary:
	if not _vk.has(kind):
		_vk[kind] = {"crewed_s": 0.0, "alive_s": 0.0, "lives": 0, "life_sum": 0.0, "wrecks": 0, "wrecked_by": {},
			"kills": 0, "dmg": 0.0, "boardings": 0, "crew_deaths": 0}
	return _vk[kind]


func _norm_weapon(w: String) -> String:
	return w.trim_suffix(" (headshot)")


func _soldier_by_name(nm: String) -> Node:
	for s in get_nodes_in_group("soldier"):
		if is_instance_valid(s) and str(s.get("display_name")) == nm:
			return s
	return null


func _vehicle_of(s: Node) -> Node:
	if s == null:
		return null
	for v in get_nodes_in_group("vehicle"):
		if is_instance_valid(v) and v.has_method("seat_of") and int(v.seat_of(s)) >= 0:
			return v
	return null


## Which bucket a damage / kill goes to: the vehicle kind for vehicle weapons
## (the MG of a buggy / heli shares "Buggy MG"), else the gun.
func _bucket(weapon: String, killer: Node) -> String:
	var w := _norm_weapon(weapon)
	if w in VEHICLE_WEAPONS:
		var v := _vehicle_of(killer)
		if v != null:
			return "veh:" + str(v.get("kind"))
		match w:
			"Buggy MG": return "veh:buggy"
			"Plane MG", "Plane": return "veh:plane"
			"Heli": return "veh:heli"
			"Tank": return "veh:tank"
			"Buggy": return "veh:buggy"
	return w


func _active_of(b: Node) -> String:
	return "USSOCOM" if bool(b.get("using_secondary")) else str(b.get("loadout"))


func _match_poll(d: float) -> void:
	var live: Array = []
	for b in get_nodes_in_group("soldier"):
		if not is_instance_valid(b) or b.get("bot_id") == null:
			continue
		var nm := str(b.get("display_name"))
		if not _assign.has(nm):
			_assign[nm] = LOADOUTS[(_assign.size() + int(_run["idx"]) * 5) % LOADOUTS.size()]
		var want: String = _assign[nm]
		if bool(b.get("dead")):
			continue
		live.append(b)
		if str(b.get("loadout")) != want:
			b.set("loadout", want)
			var am: Dictionary = b.get("AMMO_STATS")
			b.set("ammo", int(am.get(want, am["AK-74"])["mag"]))
			b.set("using_secondary", false)
			b.set("reloading", false)
		var id: int = b.get_instance_id()
		var bveh := _vehicle_of(b)
		var in_veh := bveh != null
		_last_gun[nm] = ("veh:" + str(bveh.get("kind"))) if in_veh else _active_of(b)
		if not in_veh:
			_ws(want)["alive_s"] = float(_ws(want)["alive_s"]) + d
			var act := _active_of(b)
			_ws(act)["active_s"] = float(_ws(act)["active_s"]) + d
		var hp: float = float(b.get("health"))
		var prev: float = float(_prev_hp.get(id, hp))
		if hp < prev - 0.01:
			var killer := _soldier_by_name(str(b.get("last_killer")))
			var bk := _bucket(str(b.get("last_weapon")), killer)
			var dm: float = minf(prev, prev - hp)
			if bk.begins_with("veh:"):
				_vs(bk.substr(4))["dmg"] = float(_vs(bk.substr(4))["dmg"]) + dm
			else:
				_ws(bk)["dmg"] = float(_ws(bk)["dmg"]) + dm
				_ws(bk)["hits"] = int(_ws(bk)["hits"]) + 1
			if not _eng_t0.has(id):
				_eng_t0[id] = _t
		elif hp >= 99.9:
			_eng_t0.erase(id)
		_prev_hp[id] = hp
	# Vehicles.
	for v in get_nodes_in_group("vehicle"):
		if not is_instance_valid(v) or not v.has_method("driver"):
			continue
		var vid: int = v.get_instance_id()
		var kind := str(v.get("kind"))
		var s := _vs(kind)
		if not _veh.has(vid):
			_veh[vid] = {"alive": bool(v.get("alive")), "born": _t, "drv": null, "crewed": false}
			if bool(v.get("alive")):
				s["lives"] = int(s["lives"]) + 1
		var tr: Dictionary = _veh[vid]
		var alive := bool(v.get("alive"))
		var crewed := false
		for o in v.get("seats"):
			if o != null and is_instance_valid(o):
				crewed = true
		if alive:
			s["alive_s"] = float(s["alive_s"]) + d
			if crewed:
				s["crewed_s"] = float(s["crewed_s"]) + d
				if not bool(tr["crewed"]):
					s["boardings"] = int(s["boardings"]) + 1
		if bool(tr["alive"]) and not alive:
			s["wrecks"] = int(s["wrecks"]) + 1
			s["life_sum"] = float(s["life_sum"]) + (_t - float(tr["born"]))
			var hitter := str(v.get("last_hitter"))
			var kn := _soldier_by_name(hitter)
			var why := "none/crash"
			if kn != null:
				var kv := _vehicle_of(kn)
				why = ("veh:" + str(kv.get("kind"))) if kv != null else _active_of(kn) if kn.get("bot_id") != null else "player"
			elif hitter != "":
				why = str(_last_gun.get(hitter, "player" if hitter.find("Bot") < 0 else "?"))
			var wb: Dictionary = s["wrecked_by"]
			wb[why] = int(wb.get(why, 0)) + 1
		elif not bool(tr["alive"]) and alive:
			s["lives"] = int(s["lives"]) + 1
			tr["born"] = _t
		tr["alive"] = alive
		tr["crewed"] = crewed and alive


func _on_node_added(n: Node) -> void:
	if _st != 2:
		return
	var sc = n.get_script()
	if sc == null:
		return
	var p := str(sc.resource_path)
	if not (p.ends_with("bullet.gd") or p.ends_with("rocket.gd")):
		return
	var wn := _norm_weapon(str(n.get("weapon_name")))
	if wn == "" or wn in VEHICLE_WEAPONS or wn == "M2":
		return
	_ws(wn)["proj"] = int(_ws(wn)["proj"]) + 1


func _on_kill(killer: String, victim: String, weapon: String, _kt: int, _vt: int) -> void:
	if _st != 2:
		return
	_kills_total += 1
	var kn := _soldier_by_name(killer)
	var vn := _soldier_by_name(victim)
	var bk := _bucket(weapon, kn)
	# The killing blow: the HP it took (the body leaves the group at once,
	# so the poll never sees that drop).
	if vn != null and _prev_hp.has(vn.get_instance_id()):
		var left: float = maxf(0.0, float(_prev_hp[vn.get_instance_id()]))
		_prev_hp.erase(vn.get_instance_id())
		if bk.begins_with("veh:"):
			_vs(bk.substr(4))["dmg"] = float(_vs(bk.substr(4))["dmg"]) + left
		elif killer != victim:
			_ws(bk)["dmg"] = float(_ws(bk)["dmg"]) + left
			_ws(bk)["hits"] = int(_ws(bk)["hits"]) + 1
	if vn != null and vn.get("bot_id") != null:
		var vv := _vehicle_of(vn)
		if vv != null:
			_vs(str(vv.get("kind")))["crew_deaths"] = int(_vs(str(vv.get("kind")))["crew_deaths"]) + 1
		else:
			_ws(str(_assign.get(victim, "?")))["deaths"] = int(_ws(str(_assign.get(victim, "?")))["deaths"]) + 1
	if bk.begins_with("veh:"):
		_vs(bk.substr(4))["kills"] = int(_vs(bk.substr(4))["kills"]) + 1
		return
	var s := _ws(bk)
	if killer == victim:
		s["self"] = int(s["self"]) + 1
		return
	s["kills"] = int(s["kills"]) + 1
	if kn != null and kn.get("bot_id") != null:
		_ws(str(_assign.get(killer, "?")))["kills_holder"] = int(_ws(str(_assign.get(killer, "?")))["kills_holder"]) + 1
	if kn != null and vn != null:
		s["dist_sum"] = float(s["dist_sum"]) + (kn as Node2D).global_position.distance_to((vn as Node2D).global_position)
		s["dist_n"] = int(s["dist_n"]) + 1
	if vn != null and _eng_t0.has(vn.get_instance_id()):
		s["ttk_sum"] = float(s["ttk_sum"]) + (_t - float(_eng_t0[vn.get_instance_id()]))
		s["ttk_n"] = int(s["ttk_n"]) + 1
		_eng_t0.erase(vn.get_instance_id())


func _match_report() -> void:
	for vid in _veh:
		var tr: Dictionary = _veh[vid]
		if bool(tr["alive"]):
			pass   # still alive at the end: lifetime censored, not counted in life_sum
	var line := {"key": _run_key(str(_run["spec"]), int(_run["rep"])), "tag": _tag, "spec": _run["spec"], "rep": _run["rep"],
		"secs": _secs, "bots": _bots, "kills_total": _kills_total, "weapons": _w, "vehicles": _vk}
	_append(line)
	var ks: Array = []
	for wn in _w:
		if int(_w[wn]["kills"]) > 0:
			ks.append("%s=%d" % [wn, int(_w[wn]["kills"])])
	var vs: Array = []
	for k in _vk:
		vs.append("%s k%d w%d" % [k, int(_vk[k]["kills"]), int(_vk[k]["wrecks"])])
	print("BALANCE match done %s kills=%d | %s | %s" % [_run["spec"], _kills_total, " ".join(ks), ", ".join(vs)])
