extends SceneTree
## Bomb Defusal (#304) rules + bots, single player (gate F `bomb`, BOMB-TEST).
##   godot --headless --fixed-fps 60 -s tools/bomb_test.gd [-- --only=rules|bots] [--maps=downtown,...] [--secs=300]
## rules (Downtown, test soldiers = bots with their AI off, placed by hand):
##   carrier handed out, plant takes 3 s (prog ~50 % at 1.5 s), moving
##   interrupts, damage doesn't; a defender's Use can't plant (rejected); fuse
##   -> detonation: blast kills, attackers win the round; next round after the
##   banner; drop on death + only an attacker picks it up; an attacker on the
##   planted bomb can't defuse; a defender defuses in 7 s -> defenders win;
##   clock out with no plant -> defenders win; wave respawn on the next 10 s
##   wave (and the one after when it's under 2 s away); halftime swap (roles +
##   spawns); 7 rounds -> match over (winner screen) -> fresh match.
## bots (each Bomb Defusal featured level, 8 bots, the player parked): a plant
## and then a defuse or detonation, and (#307 balance smoke) both sides win at
## least one round, within `secs` of match time per level (default 900; a
## balanced level takes ~2-4 rounds, ~100-250 s).

const GL = preload("res://tools/gate_load.gd")

var _st: Node = null
var _saved := {}
var _done := false
var _log: Array = []
var _only := ""
var _maps: Array = ["downtown", "dust_yard", "whiteout"]
var _secs := 900.0
var _deadline := 0
var _events: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="): _only = a.substr(7)
		elif a.begins_with("--maps="): _maps = Array(a.substr(7).split(",", false))
		elif a.begins_with("--secs="): _secs = float(a.substr(7))
	_deadline = Time.get_ticks_msec() + GL.wait_ms(1200000.0)
	_run()


func _process(_d: float) -> bool:
	if not _done and Time.get_ticks_msec() > _deadline:
		_finish(false, "timed out after: " + " | ".join(_log))
	return false


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _until(cond: Callable, frames: int = 600) -> bool:
	var n := 0
	while not cond.call():
		if n >= frames or _done:
			return false
		n += 1
		await process_frame
	return true


func _fail(msg: String) -> bool:
	_finish(false, msg)
	return false


func _finish(ok: bool, msg: String) -> void:
	if _done:
		return
	_done = true
	if _st != null:
		for k in _saved:
			_st.set(k, _saved[k])
		_st.save()
	print("BOMB-TEST %s %s | %.1f s" % ["ok" if ok else "FAIL", msg, Time.get_ticks_msec() / 1000.0])
	quit(0 if ok else 1)


func _run() -> void:
	await _frames(2)
	while root.get_node_or_null("Settings") == null:
		await process_frame
	_st = root.get_node("Settings")
	for k in ["game_mode", "custom_map_path", "bot_count", "vehicles", "map_index"]:
		_saved[k] = _st.get(k)
	if _only == "" or _only == "rules":
		if not _i18n():
			return
		if not await _rules():
			return
	if _only == "" or _only == "bots":
		for s in _maps:
			if not await _bots(str(s)):
				return
	_finish(true, " | ".join(_log))


func _start(level: String, bots: int) -> Node:
	_st.game_mode = 10
	_st.bot_count = bots
	_st.vehicles = false
	_st.custom_map_path = load("res://scripts/featured_levels.gd").local_copy(level)
	root.get_node("Net").set_singleplayer()
	change_scene_to_file("res://scenes/main.tscn")
	if not await _until(func() -> bool: return current_scene != null and current_scene.get("_bomb") != null \
			and current_scene._bomb.active() and current_scene.get("player") != null, 900):
		_fail("%s: Bomb Defusal match never started" % level)
		return null
	var m: Node = current_scene
	_events.clear()
	m.objective.connect(func(kind: String, team: int, who: String) -> void: _events.append([kind, team, who]))
	return m


func _bot(m: Node, nm: String) -> Node:
	for s in get_nodes_in_group("soldier"):
		if is_instance_valid(s) and str(s.get("display_name")) == nm and not bool(s.get("dead")) and s.get("bot_id") != null:
			return s
	return null


## A test soldier: a bot with its AI off, put where we want it.
func _puppet(m: Node, team: int, nm: String, at: Vector2) -> Node:
	m._spawn_bot(at, team, nm, "AK-74")
	await _frames(2)
	var b := _bot(m, nm)
	if b == null:
		return null
	b.set_physics_process(false)
	b.global_position = at
	b.velocity = Vector2.ZERO
	b.set("ceasefire_t", 0.0)
	return b


func _hit(s: Node, dmg: float, killer: String, kteam: int) -> void:
	s.set("ceasefire_t", 0.0)   # spawn protection (AI off: it never runs down)
	s.take_damage(dmg, killer, "AK-74", kteam)


func _place(b: Node, at: Vector2) -> void:
	b.global_position = at
	b.set("bomb_use", false)


func _kind_seen(kind: String) -> bool:
	for e in _events:
		if str(e[0]) == kind:
			return true
	return false


# ── strings ────────────────────────────────────────────────────────────────

const KEYS := ["Bomb Defusal", "BOMB DEFUSAL", "Use / Plant / Defuse", "Bomb site A", "Bomb site B", "BOMB PLANTED AT %s",
	"BOMB DETONATED", "HALFTIME — SIDES SWAP", "%s WIN THE ROUND — %s", "HOLD %s TO PLANT", "HOLD %s TO DEFUSE",
	"NEXT WAVE %d", "PLANTING", "DEFUSING", "USE", "Bomb Defusal needs Bomb site %s (Objectives)."]


func _i18n() -> bool:
	var GI = load("res://scripts/game_info.gd")
	var keys: Array = KEYS.duplicate()
	keys.append(str(GI.mode_goal(10)))
	keys.append(str(GI.mode_detail(10)))
	for loc in ["es", "pt_BR", "de", "fr"]:
		TranslationServer.set_locale(loc)
		for k in keys:
			if TranslationServer.translate(k) == k:
				TranslationServer.set_locale("en")
				return _fail("'%s' has no %s translation" % [k, loc])
			if TranslationServer.translate(k) == "":
				TranslationServer.set_locale("en")
				return _fail("'%s' translates to nothing in %s" % [k, loc])
	TranslationServer.set_locale("en")
	_log.append("strings translate (es / pt_BR / de / fr)")
	return true


# ── rules ──────────────────────────────────────────────────────────────────

func _rules() -> bool:
	var m := await _start("downtown", 0)
	if m == null:
		return false
	var b = m._bomb
	if b.sites.size() != 2 or str(b.sites[0]["name"]) != "A" or str(b.sites[1]["name"]) != "B":
		return _fail("sites %s" % str(b.sites))
	var spot_a: Vector2 = b.site_spot("A")
	var spot_b: Vector2 = b.site_spot("B")
	if b.site_at(spot_a) != "A" or b.site_at(spot_b) != "B":
		return _fail("site spots %s %s not inside their sites" % [str(spot_a), str(spot_b)])
	# Park the human defender far from everything (it stays in the match).
	m.player.global_position = Vector2(200, 1690)
	var red_spawn: Vector2 = (m._map["team_spawns"][2] as Array)[0]
	var r1 = await _puppet(m, 2, "R1", red_spawn)
	await _frames(3)
	if r1 == null or b.bomb_state != "carried" or b.carrier != r1:
		return _fail("bomb not handed to the only attacker: %s %s" % [b.bomb_state, str(b.carrier)])
	var r2 = await _puppet(m, 2, "R2", red_spawn + Vector2(60, 0))
	var d1 = await _puppet(m, 1, "D1", Vector2(1000, 1898))
	if r2 == null or d1 == null:
		return _fail("test soldiers didn't spawn")
	_log.append("carrier handed out")
	# A defender's Use in a site does nothing (and is logged as rejected).
	var rej0: int = int(b.stats["rejects"])
	_place(d1, spot_a + Vector2(-60, 0))
	b.set_use(m.player, true)
	await _frames(30)
	b.set_use(m.player, false)
	if b.planter != null or b.bomb_state != "carried" or int(b.stats["rejects"]) <= rej0:
		return _fail("defender Use: planter %s state %s rejects %d" % [str(b.planter), b.bomb_state, int(b.stats["rejects"])])
	_log.append("defender Use rejected")
	# Plant: moving interrupts, damage doesn't, 3 s total.
	_place(r1, spot_a)
	r1.set("bomb_use", true)
	await _frames(90)
	var p_half: float = float(b.plant_prog)
	if p_half < 0.4 or p_half > 0.6:
		return _fail("plant progress at 1.5 s = %.2f" % p_half)
	r1.global_position = spot_a + Vector2(36, 0)
	await _frames(2)
	if float(b.plant_prog) > 0.05:
		return _fail("moving didn't interrupt the plant (%.2f)" % float(b.plant_prog))
	var n := 0
	var hp0: float = float(r1.get("health"))
	while b.bomb_state != "planted" and n < 400:
		if n == 60:
			_hit(r1, 25.0, "D1", 1)
		n += 1
		await process_frame
	if b.bomb_state != "planted" or b.phase != "planted":
		return _fail("never planted (prog %.2f)" % float(b.plant_prog))
	if absi(n - 180) > 6:
		return _fail("plant took %d frames, want ~180" % n)
	if float(r1.get("health")) >= hp0:
		return _fail("the hit during the plant did no damage")
	if b.planted_site != "A" or not _kind_seen("bomb_plant") or absf(float(b.fuse_t) - 40.0) > 0.2:
		return _fail("planted site %s fuse %.1f events %s" % [b.planted_site, float(b.fuse_t), str(_events)])
	_log.append("plant 3 s (%d frames, damage kept going, moving reset)" % n)
	# An attacker on the planted bomb can't defuse.
	r1.set("bomb_use", false)
	_place(r2, b.bomb_pos + Vector2(10, 0))
	r2.set("bomb_use", true)
	await _frames(60)
	if float(b.defuse_prog) > 0.0 or b.defuser != null:
		return _fail("attacker defused (%.2f)" % float(b.defuse_prog))
	r2.set("bomb_use", false)
	# Detonation: lethal blast, attackers win.
	_place(d1, b.bomb_pos + Vector2(-80, 0))
	_place(r2, red_spawn + Vector2(60, 0))
	b.fuse_t = 0.5
	await _frames(40)
	if b.phase != "post" or int(m.scores.get(2, 0)) != 1 or str(b.last_result.get("why", "")) != "boom":
		return _fail("detonation: phase %s scores %s result %s" % [b.phase, str(m.scores), str(b.last_result)])
	if _bot(m, "D1") != null:
		return _fail("defender next to the bomb survived the blast")
	if not _kind_seen("bomb_boom") or not _kind_seen("bomb_round"):
		return _fail("detonation events %s" % str(_events))
	_log.append("detonation: blast kills, RED +1")
	# Next round after the banner.
	if not await _until(func() -> bool: return b.round_no == 2 and b.phase == "live", 420):
		return _fail("round 2 never started (round %d phase %s)" % [b.round_no, b.phase])
	if absf(float(b.round_t) - 150.0) > 1.0:
		return _fail("round 2 clock %.1f" % float(b.round_t))
	_log.append("round 2 after the result banner")
	# Respawned / restored soldiers: our puppets are bots again (AI off).
	await _frames(20)
	r1 = _bot(m, "R1")
	r2 = _bot(m, "R2")
	d1 = _bot(m, "D1")
	if r1 == null or r2 == null or d1 == null:
		return _fail("round 2: puppets missing (R1 %s R2 %s D1 %s)" % [str(r1), str(r2), str(d1)])
	for s in [r1, r2, d1]:
		s.set_physics_process(false)
		s.velocity = Vector2.ZERO
	if not await _until(func() -> bool: return b.bomb_state == "carried", 60):
		return _fail("round 2: bomb not handed out (%s)" % b.bomb_state)
	# Drop on death; a defender can't pick it up, an attacker can.
	var carrier: Node = b.carrier
	var other: Node = r2 if carrier == r1 else r1
	_place(carrier, Vector2(1350, 1880))
	await _frames(2)
	_hit(carrier, 999.0, "D1", 1)
	await _frames(3)
	if b.bomb_state != "dropped" or b.bomb_pos.distance_to(Vector2(1350, 1900)) > 30.0:
		return _fail("drop: state %s at %s" % [b.bomb_state, str(b.bomb_pos)])
	_place(d1, b.bomb_pos)
	await _frames(10)
	if b.bomb_state != "dropped":
		return _fail("a defender picked the bomb up")
	_place(d1, Vector2(1000, 1898))
	_place(other, b.bomb_pos)
	await _frames(3)
	if b.bomb_state != "carried" or b.carrier != other:
		return _fail("attacker didn't pick it up: %s %s" % [b.bomb_state, str(b.carrier)])
	_log.append("drop + attacker-only pickup")
	# Plant at B (fast-forward), then defuse in 7 s -> defenders win.
	_place(other, spot_b)
	other.set("bomb_use", true)
	if not await _until(func() -> bool: return b.bomb_state == "planted", 240):
		return _fail("plant at B failed")
	other.set("bomb_use", false)
	_place(other, red_spawn)
	_place(d1, b.bomb_pos + Vector2(-16, 0))
	d1.set("bomb_use", true)
	n = 0
	while b.phase == "planted" and n < 600:
		n += 1
		await process_frame
	if str(b.last_result.get("why", "")) != "defused" or int(m.scores.get(1, 0)) != 1:
		return _fail("defuse: result %s scores %s" % [str(b.last_result), str(m.scores)])
	if absi(n - 420) > 8:
		return _fail("defuse took %d frames, want ~420" % n)
	d1.set("bomb_use", false)
	_log.append("defuse 7 s (%d frames), BLUE +1" % n)
	if not await _until(func() -> bool: return b.round_no == 3 and b.phase == "live", 420):
		return _fail("round 3 never started")
	# Clock out with no plant -> defenders win.
	b.round_t = 0.5
	await _frames(40)
	if str(b.last_result.get("why", "")) != "time" or int(m.scores.get(1, 0)) != 2:
		return _fail("time out: %s %s" % [str(b.last_result), str(m.scores)])
	_log.append("clock out -> BLUE +1")
	if not await _until(func() -> bool: return b.round_no == 4 and b.phase == "live", 420):
		return _fail("round 4 never started")
	await _frames(10)
	# Wave respawn: a death 2+ s before the wave comes back on it; one under
	# 2 s before the wave waits for the next.
	if not await _until(func() -> bool: return float(b.wave_t) > 5.0 and float(b.wave_t) < 8.5, 600):
		return _fail("wave clock never in range")
	d1 = _bot(m, "D1")
	if d1 == null:
		return _fail("D1 missing before the wave test")
	var want: float = float(b.wave_t)
	_hit(d1, 999.0, "R1", 2)
	n = 0
	while _bot(m, "D1") == null and n < 900:
		n += 1
		await process_frame
	if absf(float(n) / 60.0 - want) > 0.25:
		return _fail("wave respawn after %.2f s, the wave was %.2f s away" % [float(n) / 60.0, want])
	if not await _until(func() -> bool: return float(b.wave_t) < 1.5 and float(b.wave_t) > 0.5, 700):
		return _fail("wave clock never under 1.5 s")
	d1 = _bot(m, "D1")
	want = float(b.wave_t) + 10.0
	_hit(d1, 999.0, "R1", 2)
	n = 0
	while _bot(m, "D1") == null and n < 1200:
		n += 1
		await process_frame
	if absf(float(n) / 60.0 - want) > 0.25:
		return _fail("late death respawned after %.2f s, want %.2f" % [float(n) / 60.0, want])
	_log.append("waves: on the next one (%.1f s), the one after when < 2 s left" % want)
	# Halftime: after round 6 the sides swap (roles + spawns).
	var blue0: Array = m._team_spawn_list(1)
	b.round_no = 6
	b._round_over(1, "time")
	if not await _until(func() -> bool: return b.round_no == 7 and b.phase == "live", 420):
		return _fail("round 7 never started")
	if not bool(b.swapped) or b.attack_team() != 1 or b.defend_team() != 2 or not _kind_seen("bomb_half"):
		return _fail("halftime: swapped %s attack %d" % [str(b.swapped), b.attack_team()])
	var blue1: Array = m._team_spawn_list(1)
	if blue1 == blue0 or blue1 != (m._map["team_spawns"][2] as Array):
		return _fail("halftime: BLUE spawns didn't move to the attackers' side")
	await _frames(10)
	if b.bomb_state == "carried" and int(b.carrier.get("team")) != 1:
		return _fail("halftime: the bomb went to team %d" % int(b.carrier.get("team")))
	_log.append("halftime swap: BLUE attacks from RED's spawns")
	# Match win: 7 rounds -> winner screen -> a fresh match.
	m.scores[2] = 6
	b._round_over(2, "boom")
	await _frames(2)
	if bool(m.round_active) or int(m.winner_team) != 2 or not bool(m.match_over):
		return _fail("match win: active %s winner %d over %s scores %s" % [str(m.round_active), int(m.winner_team), str(m.match_over), str(m.scores)])
	_log.append("7 rounds -> RED wins the match")
	m.winner_end_t = 0.05
	if not await _until(func() -> bool: return bool(m.round_active) and b.round_no == 1, 300):
		return _fail("no fresh match after the winner screen (round %d active %s)" % [b.round_no, str(m.round_active)])
	if bool(b.swapped) or not m.scores.is_empty() and int(m.scores.get(1, 0)) + int(m.scores.get(2, 0)) != 0:
		return _fail("fresh match: swapped %s scores %s" % [str(b.swapped), str(m.scores)])
	_log.append("fresh match: round 1, first-half sides, 0-0")
	return true


# ── bots ───────────────────────────────────────────────────────────────────

func _bots(level: String) -> bool:
	var m := await _start(level, 8)
	if m == null:
		return false
	var p = m.player
	if p != null and is_instance_valid(p):
		p.remove_from_group("soldier")
		p.global_position = Vector2(-600, -600)
		p.set_physics_process(false)
	var b = m._bomb
	var t := 0.0
	var plant_t := -1.0
	var end_t := -1.0
	var why := ""
	var wins := {"att": 0, "def": 0}
	m.objective.connect(func(kind: String, team: int, _who: String) -> void:
		if kind == "bomb_round":
			var side := "att" if team == int(b.attack_team()) else "def"
			wins[side] = int(wins[side]) + 1)
	var limit := _secs * 60.0
	var f := 0
	while f < int(limit):
		f += 1
		await process_frame
		if _done:
			return false
		t = float(f) / 60.0
		if plant_t < 0.0 and int(b.stats["plants"]) > 0:
			plant_t = t
		if end_t < 0.0 and plant_t >= 0.0 and int(b.stats["defuses"]) + int(b.stats["booms"]) > 0:
			end_t = t
			why = "defuse" if int(b.stats["defuses"]) > 0 else "detonation"
		if end_t >= 0.0 and int(wins["att"]) > 0 and int(wins["def"]) > 0:
			break
	var line := "%s: plant %.0f s, %s %.0f s, rounds %d won attack %d / defense %d in %.0f s (plants %d defuses %d booms %d timeouts %d)" % [level, plant_t,
		why if why != "" else "no resolution", end_t, int(b.stats["rounds"]), int(wins["att"]), int(wins["def"]), t, int(b.stats["plants"]),
		int(b.stats["defuses"]), int(b.stats["booms"]), int(b.stats["timeouts"])]
	print("BOMB-BOTS " + line)
	if plant_t < 0.0 or end_t < 0.0:
		return _fail("bots on %s" % line)
	if int(wins["att"]) == 0 or int(wins["def"]) == 0:
		return _fail("balance smoke: one side never won on %s" % line)
	_log.append(line)
	return true
