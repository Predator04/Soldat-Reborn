extends SceneTree
## Zombie (#314) rules + bots, single player (gate F `zombie`, ZOMBIE-TEST).
##   godot --headless --fixed-fps 60 -s tools/zombie_test.gd [-- --only=rules|bots] [--map=19] [--secs=240]
## rules (classic map, 4 bots with their AI off between steps): strings
##   translate; round 1 starts after the wait with the start split (1 zombie
##   of 5, everyone else human, teams = the pick, zombies hold the claws with
##   no grenades); a spawn mid-round is a zombie (late joiner); zombies shrug
##   off part of a hit (horde-scaled); a claw kill turns the human (event +
##   pick) and it rises as a zombie with the claws; a zombie player can't
##   switch / throw / grenade / pick up weapons, a human can pick up; humans
##   survive the clock -> BLUE +1; every human down -> overrun, RED +1; the
##   winning round -> match over (winner screen) -> a fresh match at round 1.
## bots (8 bots, the player parked): a bot zombie claws a human into a zombie
## and a round ends within `secs` of match time.

const GL = preload("res://tools/gate_load.gd")
const ZR = preload("res://scripts/zombie_rules.gd")

var _st: Node = null
var _saved := {}
var _done := false
var _log: Array = []
var _only := ""
var _map := 19
var _secs := 240.0
var _deadline := 0
var _events: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="): _only = a.substr(7)
		elif a.begins_with("--map="): _map = int(a.substr(6))
		elif a.begins_with("--secs="): _secs = float(a.substr(7))
	_deadline = Time.get_ticks_msec() + GL.wait_ms(600000.0)
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
	print("ZOMBIE-TEST %s %s | %.1f s" % ["ok" if ok else "FAIL", msg, Time.get_ticks_msec() / 1000.0])
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
		if not await _bots():
			return
	_finish(true, " | ".join(_log))


func _start(bots: int) -> Node:
	_st.game_mode = 11
	_st.bot_count = bots
	_st.vehicles = false
	_st.custom_map_path = ""
	_st.map_index = _map
	root.get_node("Net").set_singleplayer()
	change_scene_to_file("res://scenes/main.tscn")
	if not await _until(func() -> bool: return current_scene != null and current_scene.get("_zombie") != null \
			and current_scene._zombie.active(), 900):
		_fail("Zombie match never started")
		return null
	var m: Node = current_scene
	_events.clear()
	m.objective.connect(func(kind: String, team: int, who: String) -> void: _events.append([kind, team, who]))
	return m


func _kind_seen(kind: String, who := "") -> bool:
	for e in _events:
		if str(e[0]) == kind and (who == "" or str(e[2]) == who):
			return true
	return false


func _soldiers() -> Array:
	var out: Array = []
	for s in get_nodes_in_group("soldier"):
		if is_instance_valid(s) and not bool(s.get("dead")):
			out.append(s)
	return out


## Bots stand still (AI off) so the rules steps decide every death.
func _freeze() -> void:
	for s in get_nodes_in_group("soldier"):
		if is_instance_valid(s) and s.get("bot_id") != null:
			s.set_physics_process(false)
			s.velocity = Vector2.ZERO


func _by_name(nm: String) -> Node:
	for s in _soldiers():
		if str(s.get("display_name")) == nm:
			return s
	return null


func _hh() -> GDScript:
	return load("res://scripts/host_hits.gd")


func _kill(s: Node, killer: String, kteam: int) -> void:
	s.set("ceasefire_t", 0.0)
	for _i in 30:
		if not is_instance_valid(s) or bool(s.get("dead")):
			return
		_hh().damage(s, 60.0, killer, ZR.CLAW_WEAPON if kteam == 2 else "AK-74", kteam)


# ── strings ────────────────────────────────────────────────────────────────

# ("Zombie" / "ZOMBIES" read the same in German and French: checked for a row only.)
const SAME_KEYS := ["Zombie", "ZOMBIE", "Zombies", "ZOMBIES"]
const KEYS := ["ROUND %s — YOU ARE A ZOMBIE: TURN THEM ALL", "ROUND %s — SURVIVE FOR %s",
	"YOU WERE TURNED — HUNT THE HUMANS", "YOU ARE THE LAST HUMAN", "LAST HUMAN STANDING: %s",
	"THE HUMANS SURVIVED THE ROUND", "THE ZOMBIES ARE GONE — HUMANS WIN THE ROUND", "OVERRUN — THE ZOMBIES WIN THE ROUND",
	"%s was turned by %s", "%s turned into a zombie", "Humans", "ROUND 1 STARTS IN %d", "HUMANS LEFT: %d",
	"HUMANS"]


func _i18n() -> bool:
	var GI = load("res://scripts/game_info.gd")
	var keys: Array = KEYS.duplicate()
	keys.append(str(GI.mode_goal(11)))
	keys.append(str(GI.mode_detail(11)))
	for loc in ["es", "pt_BR", "de", "fr"]:
		TranslationServer.set_locale(loc)
		for k in keys:
			var t := TranslationServer.translate(k)
			if t == k or t == "":
				TranslationServer.set_locale("en")
				return _fail("'%s' has no %s translation" % [k, loc])
	TranslationServer.set_locale("es")
	for k in SAME_KEYS:
		if TranslationServer.translate(k) == k:
			TranslationServer.set_locale("en")
			return _fail("'%s' has no es translation" % k)
	TranslationServer.set_locale("en")
	var names: Array = load("res://scripts/game_lists.gd").MODE_NAMES
	if names.size() != 12 or str(names[11]) != "Zombie" or str(names[10]) != "Bomb Defusal":
		return _fail("mode list: %s" % str(names))
	_log.append("strings translate, mode 11 appended")
	return true


# ── rules ──────────────────────────────────────────────────────────────────

func _rules() -> bool:
	var m := await _start(4)
	if m == null:
		return false
	var z = m._zombie
	if z.phase != "wait":
		return _fail("match didn't open in the wait phase (%s)" % z.phase)
	if not await _until(func() -> bool: return z.phase == "live" and z.round_no == 1, 400):
		return _fail("round 1 never started (%s %d)" % [z.phase, z.round_no])
	await _frames(3)
	_freeze()
	# Start split: 5 soldiers -> 1 zombie, 4 humans; teams follow the pick.
	var sol := _soldiers()
	var nz := 0
	for s in sol:
		var nm := str(s.get("display_name"))
		var want: int = 2 if z.zombies.has(nm) else 1
		if int(s.get("team")) != want:
			return _fail("%s team %d, pick says %d" % [nm, int(s.get("team")), want])
		if want == 2:
			nz += 1
			if int(s.get("grenades")) != 0:
				return _fail("zombie %s has grenades" % nm)
			if s.get("bot_id") != null and str(s.get("loadout")) != ZR.CLAW_WEAPON:
				return _fail("zombie bot %s holds %s" % [nm, str(s.get("loadout"))])
			if s.get("bot_id") == null and (not bool(s.get("using_secondary")) or int(s.get("secondary_index")) != ZR.CLAW_SLOT):
				return _fail("zombie player not on the claws")
	if sol.size() != 5 or nz != 1 or z.zombies.size() != 1 or z.humans_left != 4:
		return _fail("start split: %d soldiers, %d zombies, pick %s, humans left %d" % [sol.size(), nz, str(z.zombies), z.humans_left])
	if not _kind_seen("zombie_start"):
		return _fail("no zombie_start event")
	_log.append("round 1: 1 zombie / 4 humans, teams = the pick, claws only")
	# A spawn mid-round (a late joiner) is a zombie.
	if z.team_for("Late Joiner") != 2 or not z.zombies.has("Late Joiner"):
		return _fail("a mid-round spawn wasn't a zombie")
	z.zombies.erase("Late Joiner")
	# Zombie toughness: part of a hit, scaled by the horde share.
	var zb: Node = null
	var hum: Node = null
	for s in _soldiers():
		if s.get("bot_id") == null:
			continue
		if int(s.get("team")) == 2 and zb == null:
			zb = s
		elif int(s.get("team")) == 1 and hum == null:
			hum = s
	if hum == null:
		return _fail("no human bot")
	if zb == null:
		# The player was picked: test the claws on a bot from the player.
		zb = m.player
	zb.set("ceasefire_t", 0.0)
	var hp0: float = float(zb.get("health"))
	_hh().damage(zb, 20.0, str(hum.get("display_name")), "AK-74", 1)
	var took: float = hp0 - float(zb.get("health"))
	var want_took: float = 20.0 * ZR.damage_taken(float(z.zombie_share))
	if absf(took - want_took) > 0.05 or took >= 20.0:
		return _fail("zombie took %.2f of a 20 hit (want %.2f, share %.2f)" % [took, want_took, float(z.zombie_share)])
	if ZR.damage_taken(0.1) >= ZR.damage_taken(0.9):
		return _fail("horde scaling not increasing")
	_log.append("zombie takes %.0f %% of a hit at share %.2f" % [took * 5.0, float(z.zombie_share)])
	# A claw kill turns the human; it rises as a zombie with the claws.
	var hname := str(hum.get("display_name"))
	var zname := str(zb.get("display_name"))
	_kill(hum, zname, 2)
	await _frames(2)
	if not z.zombies.has(hname) or not _kind_seen("zombie_turn", hname + "@" + zname):
		return _fail("claw kill didn't turn %s (pick %s, events %s)" % [hname, str(z.zombies), str(_events)])
	if z.humans_left != 3:
		await _frames(2)
	if z.humans_left != 3:
		return _fail("humans left %d after a turn (want 3)" % z.humans_left)
	if not await _until(func() -> bool: return _by_name(hname) != null, int((z.RESPAWN + 2.0) * 60.0)):
		return _fail("%s never rose again" % hname)
	var risen := _by_name(hname)
	if int(risen.get("team")) != 2 or str(risen.get("loadout")) != ZR.CLAW_WEAPON:
		return _fail("%s rose as team %d with %s" % [hname, int(risen.get("team")), str(risen.get("loadout"))])
	_freeze()
	_log.append("claw kill turns %s, rises as a zombie in %.0f s" % [hname, z.RESPAWN])
	# Humans survive the clock -> BLUE +1.
	z.round_t = 0.5
	await _frames(40)
	if str(z.last_result.get("why", "")) != "survived" or int(m.scores.get(1, 0)) != 1 or z.phase != "post":
		return _fail("clock out: %s scores %s phase %s" % [str(z.last_result), str(m.scores), z.phase])
	_log.append("clock out -> humans +1")
	# Round 2: make the player the zombie (everyone else started as one more often).
	for nm in z._roster():
		z._picked_count[nm] = 9
	z._picked_count[str(m.player.get("display_name"))] = 0
	if not await _until(func() -> bool: return z.round_no == 2 and z.phase == "live", 600):
		return _fail("round 2 never started")
	await _frames(3)
	_freeze()
	var p: Node = m.player
	if p == null or int(p.get("team")) != 2:
		return _fail("round 2: the player isn't the zombie (pick %s)" % str(z.zombies))
	# Zombie player: no switching, throwing, grenades or weapon pickups.
	p.call("_switch_weapon", 2)
	p.call("_toggle_secondary")
	p.call("_drop_active_weapon")
	if not bool(p.get("using_secondary")) or int(p.get("secondary_index")) != ZR.CLAW_SLOT or int(p.get("grenades")) != 0:
		return _fail("zombie player left the claws (sec %s idx %d nades %d)" % [str(p.get("using_secondary")), int(p.get("secondary_index")), int(p.get("grenades"))])
	if bool(p.call("try_pickup_weapon", "AK-74")):
		return _fail("zombie player picked up an AK-74")
	var wp = load("res://scripts/weapon_pickup.gd").new()
	wp.weapon_name = "AK-74"
	wp.team = -1
	wp.global_position = p.global_position + Vector2(0, -12)
	m.add_child(wp)
	await _frames(2)
	wp.call("_on_body_entered", p)
	if bool(wp.get("_consumed")) or not is_instance_valid(wp):
		return _fail("a weapon pickup went to the zombie")
	var h2: Node = null
	for s in _soldiers():
		if int(s.get("team")) == 1 and s.get("bot_id") != null:
			h2 = s
			break
	if h2 == null:
		return _fail("round 2: no human bot")
	wp.call("_on_body_entered", h2)
	if not bool(wp.get("_consumed")):
		return _fail("a human couldn't pick the same weapon up")
	_log.append("zombie player: claws locked, no weapon pickup (a human takes it)")
	# Every human down -> overrun, RED +1.
	for s in _soldiers():
		if int(s.get("team")) == 1:
			_kill(s, str(p.get("display_name")), 2)
	await _frames(4)
	if str(z.last_result.get("why", "")) != "overrun" or int(m.scores.get(2, 0)) != 1:
		return _fail("overrun: %s scores %s humans %d" % [str(z.last_result), str(m.scores), z.humans_left])
	_log.append("all humans turned -> zombies +1")
	# Match end: the deciding round -> winner screen -> fresh match.
	if not await _until(func() -> bool: return z.round_no == 3 and z.phase == "live", 600):
		return _fail("round 3 never started")
	await _frames(3)
	_freeze()
	m.scores[1] = z.win_target() - 1
	z.round_t = 0.5
	await _frames(40)
	if bool(m.round_active) or not bool(m.match_over) or int(m.winner_team) != 1:
		return _fail("match end: active %s over %s winner %d scores %s" % [str(m.round_active), str(m.match_over), int(m.winner_team), str(m.scores)])
	_log.append("round %d to win -> match over" % z.win_target())
	if not await _until(func() -> bool: return current_scene != m or (bool(m.round_active) and z.round_no == 1 and z.phase == "live"), 1500):
		return _fail("no fresh match after the winner screen")
	if current_scene == m:
		if int(m.scores.get(1, 0)) != 0 or int(m.scores.get(2, 0)) != 0:
			return _fail("fresh match kept the scores %s" % str(m.scores))
		_log.append("fresh match at round 1")
	else:
		_log.append("next map voted in")
	return true


# ── bots ───────────────────────────────────────────────────────────────────

func _bots() -> bool:
	var m := await _start(8)
	if m == null:
		return false
	var z = m._zombie
	z.exclude_local = true
	if m.player != null and is_instance_valid(m.player):
		m.player.remove_from_group("soldier")
		m.player.global_position = Vector2(-600, -600)
		m.player.set_physics_process(false)
	var frames := int(_secs * 60.0)
	if not await _until(func() -> bool: return int(z.stats["claw_turns"]) > 0 and int(z.stats["rounds"]) > 0, frames):
		return _fail("bots: %d claw turns, %d rounds in %.0f s" % [int(z.stats["claw_turns"]), int(z.stats["rounds"]), _secs])
	_log.append("bots: claw turns %d, round %d over (%s)" % [int(z.stats["claw_turns"]), int(z.stats["rounds"]), str(z.last_result.get("why", ""))])
	return true
