extends Node
## Zombie (#314) — Main's helper for mode 11 (`main._zombie`).
##
## Round-based humans (BLUE) vs zombies (RED). A round starts with about one
## soldier in four (at least one) as a zombie and everyone respawned fresh on
## their side; any human who dies rises as a zombie (zombies are back in
## RESPAWN s — humans never respawn as humans during a round). Humans win the
## round by lasting the ROUND_TIME clock, zombies by turning every human.
## main.scores = rounds won; first to main.win_score(11) (server.cfg
## score_limit_zombie) takes the match through main's winner screen + vote.
## Per-soldier rules (claws only, no pickups, faster, half damage) live in
## zombie_rules.gd and are keyed on the team, which every peer has.
##
## Host-authoritative: the host (or single player) decides who is a zombie —
## the start pick, every turn (a BLUE death in a live round, from the kill
## signal or the per-tick backstop) and the team of every spawn (team_for(),
## asked by the spawn paths: MatchNet._assign_team_for_peer, MatchBots,
## main._spawn_player). A team only ever changes through a fresh body, which
## the spawn RPCs (net_spawn_player / net_spawn_bot) already replicate with
## its team; a spawn during a live round outside the round-start respawn is
## a zombie, so a late joiner joins as one. Clients mirror the round state
## from net_payload(): a reliable Main.net_zombie_sync (join, round start /
## end) plus the 10 Hz mode-state stream (seq-numbered). Banners / feed
## lines / sounds go through _objective_event (kinds zombie_*).

const Main = preload("res://scripts/main.gd")
const ZR = preload("res://scripts/zombie_rules.gd")
const TeamColors = preload("res://scripts/team_colors.gd")

var main: Main

const ROUND_TIME := 180.0      # 3:00 for the humans to survive
const WAIT_TIME := 3.0         # first round starts this long after the match loads
const POST_TIME := 6.0         # round result banner before the next round
const RESPAWN := 6.0           # zombies (and the freshly turned) come back this fast
const SHARE := 0.15            # starting zombies = round(soldiers x SHARE), >= 1
const GONE_TIME := 6.0         # no zombie anywhere this long = the humans win the round
const TEAM_HUMAN := 1
const TEAM_ZOMBIE := 2

# ── State (host-authoritative; clients mirror it) ──
var phase := "wait"            # "wait" | "live" | "post"
var round_no := 0              # 1-based once a round has started
var round_t := ROUND_TIME
var wait_t := WAIT_TIME
var post_t := 0.0
var humans_left := 0
var zombie_share := 0.0        # host: living zombies / living soldiers (zombie_rules.damage_taken)
var zombies: Dictionary = {}   # host: display name -> true for this round's zombies
var last_result: Dictionary = {}   # {"team": int, "why": "survived" | "overrun" | "gone"}
var stats := {"rounds": 0, "human_wins": 0, "zombie_wins": 0, "turns": 0, "claw_turns": 0, "starts": 0}
var round_log: Array = []      # host: one {round, winner, why, secs, start_humans, start_zombies, turns} per round (watch / tests)
var received := false          # client: a host snapshot has arrived
var exclude_local := false     # tools (zombie_watch / tests): bots only, the SP player stays parked

var _setup_done := false
var _mass := false             # host: inside the round-start respawn (team_for = the pick)
var _seq := 0
var _last_called := false
var _gone_t := 0.0
var _picked_count: Dictionary = {}   # host: name -> rounds started as a zombie (rotation)
var _round_turns := 0
var _start_h := 0
var _start_z := 0
var _rally := Vector2.INF       # host: where human bots regroup this round
var _rally_tried := false
var _smoke_claw := -1          # gate C `zombie`: --smoke-zombie-claw (host) claws the human player in round 1
var _smoke_claw_t := 0.0


func active() -> bool:
	return Settings.game_mode == Settings.MODE_ZOMBIE and _setup_done


func _is_authority() -> bool:
	return not Net.is_networked() or Net.is_host()


## Called on every peer from MatchModes._spawn_mode_entities (before anyone
## spawns: everybody starts human until the first round begins).
func setup() -> void:
	_setup_done = true
	phase = "wait"
	wait_t = WAIT_TIME
	round_no = 0
	if _is_authority():
		main.time_left = wait_t


## Rounds to win (server.cfg score_limit_zombie on a dedicated server).
func win_target() -> int:
	return main.win_score(Settings.MODE_ZOMBIE)


# ── Teams ──────────────────────────────────────────────────────────────────

## Host / SP: the team a soldier called `nm` spawns on right now. A spawn in
## a live round outside the round-start respawn is a turned human or a late
## joiner — a zombie either way.
func team_for(nm: String) -> int:
	if not active():
		return TEAM_HUMAN
	if phase == "live" and not _mass and not zombies.has(nm):
		zombies[nm] = true
	return TEAM_ZOMBIE if zombies.has(nm) else TEAM_HUMAN


## Bot loadout for a team (zombies: the claws = the Knife).
func bot_loadout(team: int, human_loadout: String) -> String:
	return ZR.CLAW_WEAPON if team == TEAM_ZOMBIE else human_loadout


func respawn_delay() -> float:
	return RESPAWN


## Everyone who'd be in the next round: humans by their display name (as the
## spawn paths name them), bots by the names MatchBots gives them here.
func _roster() -> Array:
	var out: Array = []
	if not Net.is_networked():
		if not exclude_local:
			out.append(Settings.display_name())
	else:
		if not Net.is_dedicated:
			out.append(Settings.display_name())
		for pid in main._connected_peers.keys():
			out.append(str(main._peer_names.get(int(pid), "Player %d" % int(pid))))
	var spots: Array = main._map.get("bot_spawns", [])
	if not spots.is_empty():
		for i in maxi(0, main._bots._desired_bot_count()):
			out.append(bot_name(i))
	return out


static func bot_name(i: int) -> String:
	return "Bot %d" % (i + 1)


## The round's starting zombies: round(n x SHARE) (>= 1, leaving >= 1 human),
## those who started as zombies least often first, random among equals.
func _pick(roster: Array) -> Dictionary:
	var n := roster.size()
	var k := clampi(int(round(float(n) * SHARE)), 1, maxi(1, n - 1))
	var pool := roster.duplicate()
	pool.shuffle()
	var by_count: Dictionary = {}
	for nm in pool:
		var c := int(_picked_count.get(nm, 0))
		if not by_count.has(c):
			by_count[c] = []
		(by_count[c] as Array).append(nm)
	var counts := by_count.keys()
	counts.sort()
	var out: Dictionary = {}
	for c in counts:
		for nm in by_count[c]:
			if out.size() >= k:
				break
			out[nm] = true
	for nm in out.keys():
		_picked_count[nm] = int(_picked_count.get(nm, 0)) + 1
	return out


# ── Rounds ─────────────────────────────────────────────────────────────────

func _start_round() -> void:
	var roster := _roster()
	round_no += 1
	phase = "live"
	round_t = ROUND_TIME
	post_t = 0.0
	_last_called = false
	_gone_t = 0.0
	_round_turns = 0
	_rally = Vector2.INF
	_rally_tried = false
	zombies = _pick(roster)
	_start_z = zombies.size()
	_start_h = roster.size() - _start_z
	zombie_share = float(_start_z) / float(maxi(1, roster.size()))
	stats["starts"] = int(stats["starts"]) + 1
	main.time_left = round_t
	print("ZOMBIE round %d start: %d humans, %d zombies (%s)" % [round_no, _start_h, _start_z, ", ".join(PackedStringArray(zombies.keys()))])
	_respawn_everyone()
	humans_left = _start_h
	if Net.is_networked():
		_send_sync(true)
	_event("zombie_start", TEAM_HUMAN, str(round_no))


## Host / SP: every soldier gets a fresh body on its side for the new round
## (the same wipe-and-spawn a Survival round reset does: the spawn RPCs carry
## the new teams to every peer).
func _respawn_everyone() -> void:
	_mass = true
	main._bots._bot_pending.clear()
	main._bots._bot_respawn_fn.clear()
	if Net.is_networked():
		for pid in main._players_by_id.keys():
			var p = main._players_by_id[pid]
			if is_instance_valid(p):
				p.queue_free()
		main._players_by_id.clear()
		if not Net.is_dedicated:
			main._net._spawn_networked_player(1)
		for pid in main._connected_peers.keys():
			main._net._spawn_networked_player(int(pid))
		for bid in main._bots_by_id.keys():
			var b = main._bots_by_id[bid]
			if is_instance_valid(b):
				main.bcast("net_bot_despawn", [bid], false)
				b.queue_free()
		main._bots_by_id.clear()
		main._spawn_bots()
	else:
		for s in main.get_tree().get_nodes_in_group("soldier"):
			if is_instance_valid(s):
				s.remove_from_group("soldier")
				s.queue_free()
		main._bots_by_id.clear()
		if not exclude_local:
			main.player = null
			main._spawn_player()
		main._spawn_bots()
	_mass = false


## A whole new match (main._reset_round after the winner screen).
func match_reset() -> void:
	if not active() or not _is_authority():
		return
	round_no = 0
	last_result = {}
	_start_round()


func _round_over(team: int, why: String) -> void:
	if phase != "live":
		return
	phase = "post"
	post_t = POST_TIME
	last_result = {"team": team, "why": why}
	stats["rounds"] = int(stats["rounds"]) + 1
	stats["human_wins" if team == TEAM_HUMAN else "zombie_wins"] = int(stats["human_wins" if team == TEAM_HUMAN else "zombie_wins"]) + 1
	round_log.append({"round": round_no, "winner": "human" if team == TEAM_HUMAN else "zombie", "why": why,
		"secs": snappedf(ROUND_TIME - round_t, 0.1), "start_humans": _start_h, "start_zombies": _start_z,
		"turns": _round_turns, "humans_left": humans_left})
	main.scores[team] = int(main.scores.get(team, 0)) + 1
	main.scores[_other(team)] = int(main.scores.get(_other(team), 0))
	print("ZOMBIE round %d over: %s win (%s) after %.0f s, humans left %d, score %d-%d" % [round_no,
		"humans" if team == TEAM_HUMAN else "zombies", why, ROUND_TIME - round_t, humans_left,
		int(main.scores.get(TEAM_HUMAN, 0)), int(main.scores.get(TEAM_ZOMBIE, 0))])
	_event("zombie_round", team, why)
	if Net.is_networked():
		_send_sync(false)
	if int(main.scores[team]) >= win_target():
		var why_txt := {"survived": "the humans held out", "overrun": "every human was turned", "gone": "the zombies were gone"}
		main.winner_note = "%d – %d in rounds (last: %s)" % [int(main.scores[team]), int(main.scores[_other(team)]), str(why_txt.get(why, why))]
		main.time_left = 0.0   # a won match ends the match (vote), not just a round
		main._modes._end_round(team)
	elif Net.is_networked() and Net.is_host():
		main._net._broadcast_match_state()


func _other(t: int) -> int:
	return TEAM_ZOMBIE if t == TEAM_HUMAN else TEAM_HUMAN


# ── Host tick ──────────────────────────────────────────────────────────────

func tick(delta: float) -> void:
	if not active():
		return
	match phase:
		"wait":
			wait_t -= delta
			main.time_left = maxf(0.0, wait_t)
			if wait_t <= 0.0:
				if _roster().size() >= 2:
					_start_round()
				else:
					wait_t = 1.0
		"post":
			post_t -= delta
			main.time_left = maxf(0.0, post_t)
			if post_t <= 0.0:
				_start_round()
		"live":
			round_t = maxf(0.0, round_t - delta)
			main.time_left = round_t
			if _smoke_claw < 0:
				_smoke_claw = 1 if OS.get_cmdline_user_args().has("--smoke-zombie-claw") else 0
			if _smoke_claw == 1 and round_no == 1:
				_smoke_claw_tick(delta)
			_turn_backstop()
			humans_left = _humans_alive()
			_update_share()
			if humans_left == 1 and not _last_called and _start_h > 1:
				_last_called = true
				_event("zombie_last", TEAM_HUMAN, _last_human_name())
			if humans_left <= 0:
				_round_over(TEAM_ZOMBIE, "overrun")
			elif round_t <= 0.0:
				_round_over(TEAM_HUMAN, "survived")
			else:
				_gone_t = 0.0 if _zombie_presence() else _gone_t + delta
				if _gone_t >= GONE_TIME:
					_round_over(TEAM_HUMAN, "gone")


## Gate C `zombie` (host, --smoke-zombie-claw): in round 1 the zombie player's
## claws land on the human player every 0.5 s, through HostHits like any hit
## (stands in for scripted melee aim; the turn, respawn and team change that
## follow are the real ones).
func _smoke_claw_tick(delta: float) -> void:
	_smoke_claw_t -= delta
	if _smoke_claw_t > 0.0:
		return
	_smoke_claw_t = 0.5
	var zb: Node = null
	var hb: Node = null
	for pid in main._players_by_id.keys():
		var b = main._players_by_id[pid]
		if not _alive(b):
			continue
		if int(b.get("team")) == TEAM_ZOMBIE and zb == null:
			zb = b
		elif int(b.get("team")) == TEAM_HUMAN and hb == null:
			hb = b
	if zb == null or hb == null:
		return
	print("SMOKE-ZOMBIE claw %s -> %s hp=%.0f" % [str(zb.get("display_name")), str(hb.get("display_name")), float(hb.get("health"))])
	HostHits.damage(hb, ZR.CLAW_DAMAGE, str(zb.get("display_name")), ZR.CLAW_WEAPON, TEAM_ZOMBIE)


func _alive(s: Variant) -> bool:
	return s != null and is_instance_valid(s) and not bool((s as Node).get("dead"))


func _humans_alive() -> int:
	var n := 0
	for s in main.get_tree().get_nodes_in_group("soldier"):
		if _alive(s) and int(s.get("team")) == TEAM_HUMAN and not zombies.has(str(s.get("display_name"))):
			n += 1
	return n


func _update_share() -> void:
	var z := 0
	var n := 0
	for s in main.get_tree().get_nodes_in_group("soldier"):
		if _alive(s):
			n += 1
			if int(s.get("team")) == TEAM_ZOMBIE:
				z += 1
	zombie_share = float(z) / float(n) if n > 0 else 0.0


func _last_human_name() -> String:
	for s in main.get_tree().get_nodes_in_group("soldier"):
		if _alive(s) and int(s.get("team")) == TEAM_HUMAN and not zombies.has(str(s.get("display_name"))):
			return str(s.get("display_name"))
	return ""


## Any zombie in the round: a RED body (alive or a husk about to respawn), a
## zombie bot waiting on its timer, or a zombie player's respawn gate.
func _zombie_presence() -> bool:
	for s in main.get_tree().get_nodes_in_group("soldier"):
		if is_instance_valid(s) and int(s.get("team")) == TEAM_ZOMBIE:
			return true
	for nm in main._bots._bot_pending.keys():
		if zombies.has(str(nm)):
			return true
	for key in main._rs_state.keys():
		var nm2: String = Settings.display_name() if int(key) <= 1 else str(main._peer_names.get(int(key), ""))
		if zombies.has(nm2):
			return true
	return false


## Host: soldier `victim` (team victim_team) died; killer_team says by whom.
## A human dying in a live round turns (the kill signal, MatchModes).
func on_kill(killer: String, victim: String, killer_team: int, victim_team: int) -> void:
	if not active() or phase != "live" or victim_team != TEAM_HUMAN or zombies.has(victim):
		return
	var by := killer if killer_team == TEAM_ZOMBIE and killer != victim else ""
	_turn(victim, by)


## Deaths without a kill line (no killer recorded) still turn the human.
func _turn_backstop() -> void:
	for s in main.get_tree().get_nodes_in_group("soldier"):
		if not is_instance_valid(s) or not bool(s.get("dead")) or int(s.get("team")) != TEAM_HUMAN:
			continue
		var nm := str(s.get("display_name"))
		if nm != "" and not zombies.has(nm):
			_turn(nm, "")


func _turn(victim: String, by: String) -> void:
	zombies[victim] = true
	_round_turns += 1
	stats["turns"] = int(stats["turns"]) + 1
	if by != "":
		stats["claw_turns"] = int(stats["claw_turns"]) + 1
	print("ZOMBIE turned %s%s" % [victim, (" by " + by) if by != "" else ""])
	_event("zombie_turn", TEAM_ZOMBIE, victim + "@" + by)


func _event(kind: String, team: int, who: String) -> void:
	main._modes._objective_event(kind, team, who)


# ── Bots (host) ────────────────────────────────────────────────────────────

## Where human bots regroup this round: high, reachable ground not far from
## the human spawns (by nav walk), picked once per round when the graph is in.
func rally() -> Vector2:
	if _rally != Vector2.INF or _rally_tried:
		return _rally
	var nav = main.nav
	if nav == null or nav.is_empty():
		return Vector2.INF
	_rally_tried = true
	var spawns: Array = main._team_spawn_list(TEAM_HUMAN)
	if spawns.is_empty():
		return Vector2.INF
	var src: int = nav.nearest(spawns[0], 480.0)
	if src < 0:
		return Vector2.INF
	var walk: PackedFloat32Array = main._bomb._walk_from(nav, src)[0]
	var pts: PackedVector2Array = nav.get("_pts")
	var air: Dictionary = nav.get("_air")
	var base: Vector2 = pts[src]
	var best := -INF
	for i in pts.size():
		if air.has(i) or walk[i] == INF or walk[i] > 900.0:
			continue
		var p: Vector2 = pts[i]
		if main.has_method("hazard_at") and main.hazard_at(p, 40.0):
			continue
		var sc: float = (base.y - p.y) - 0.5 * walk[i]
		if sc > best:
			best = sc
			_rally = p
	if _rally != Vector2.INF:
		print("ZOMBIE rally (%.0f, %.0f)" % [_rally.x, _rally.y])
	return _rally


# ── Net state ──────────────────────────────────────────────────────────────

func net_payload(_full: bool) -> Dictionary:
	_seq += 1
	return {"q": _seq, "ph": phase, "rn": round_no, "rt": round_t, "wt": wait_t, "pt": post_t,
		"hl": humans_left, "res": last_result}


func _send_sync(reset: bool) -> void:
	var d := net_payload(true)
	d["reset"] = reset
	main.bcast("net_zombie_sync", [d], false)


## Client: apply a host snapshot (stream or reliable sync).
func apply_payload(d: Dictionary) -> void:
	if _is_authority():
		return
	var q := int(d.get("q", 0))
	if q <= _seq and not bool(d.get("reset", false)):
		return
	_seq = maxi(_seq, q)
	received = true
	phase = str(d.get("ph", phase))
	round_no = int(d.get("rn", round_no))
	round_t = float(d.get("rt", round_t))
	wait_t = float(d.get("wt", wait_t))
	post_t = float(d.get("pt", post_t))
	humans_left = int(d.get("hl", humans_left))
	last_result = d.get("res", {}) if typeof(d.get("res", {})) == TYPE_DICTIONARY else {}


## Client: reliable snapshot (join / round start / round end).
func net_sync(d: Dictionary) -> void:
	if _is_authority():
		return
	apply_payload(d)


## Clients tick the clocks between snapshots so the HUD counts smoothly.
func client_tick(delta: float) -> void:
	if not active() or _is_authority():
		return
	match phase:
		"wait": wait_t = maxf(0.0, wait_t - delta)
		"live": round_t = maxf(0.0, round_t - delta)
		"post": post_t = maxf(0.0, post_t - delta)


# ── HUD helpers (read on every peer) ───────────────────────────────────────

func role_of(team: int) -> String:
	return "zombie" if team == TEAM_ZOMBIE else "human"


func _local_name() -> String:
	var p = main.player
	if p != null and is_instance_valid(p):
		return str(p.get("display_name"))
	return Settings.display_name()


func _local_zombie() -> bool:
	var p = main.player
	return p != null and is_instance_valid(p) and int(p.get("team")) == TEAM_ZOMBIE


static func clock_text(secs: float) -> String:
	var s := maxi(0, int(ceil(secs)))
	return "%d:%02d" % [s / 60, s % 60]


## Banner text + colour for a zombie_* objective event ("" = none).
func banner(kind: String, team: int, who: String) -> Array:
	var hc := TeamColors.blue(true)
	var zc := TeamColors.red(true)
	match kind:
		"zombie_start":
			if _local_zombie():
				return [tr("ROUND %s — YOU ARE A ZOMBIE: TURN THEM ALL") % who, zc]
			return [tr("ROUND %s — SURVIVE FOR %s") % [who, clock_text(ROUND_TIME)], hc]
		"zombie_turn":
			var victim := who.get_slice("@", 0)
			if victim != "" and victim == _local_name():
				return [tr("YOU WERE TURNED — HUNT THE HUMANS"), zc]
		"zombie_last":
			if who != "" and who == _local_name():
				return [tr("YOU ARE THE LAST HUMAN"), hc]
			if who != "":
				return [tr("LAST HUMAN STANDING: %s") % who, hc]
		"zombie_round":
			match who:
				"survived": return [tr("THE HUMANS SURVIVED THE ROUND"), hc]
				"gone": return [tr("THE ZOMBIES ARE GONE — HUMANS WIN THE ROUND"), hc]
				_: return [tr("OVERRUN — THE ZOMBIES WIN THE ROUND"), zc]
	return ["", Color.WHITE]


## Kill-feed line for a zombie_* event ("" = none).
func feed_text(kind: String, team: int, who: String) -> String:
	match kind:
		"zombie_turn":
			var victim := who.get_slice("@", 0)
			var by := who.get_slice("@", 1) if who.contains("@") else ""
			return (tr("%s was turned by %s") % [victim, by]) if by != "" else (tr("%s turned into a zombie") % victim)
		"zombie_round":
			return tr("%s won round %d") % [tr("Humans") if team == TEAM_HUMAN else tr("Zombies"), round_no]
	return ""


## Status line under the score strip (objective_hud.gd).
func status_bbcode(_p: Node) -> String:
	if not active():
		return ""
	var out: PackedStringArray = PackedStringArray()
	match phase:
		"wait":
			out.append("[b]%s[/b]" % (tr("ROUND 1 STARTS IN %d") % maxi(1, int(ceil(wait_t)))))
		_:
			out.append("[b]%s[/b]" % (tr("ROUND %d") % maxi(1, round_no)))
			var hc := TeamColors.blue(true)
			var a := 1.0
			if phase == "live" and humans_left <= 1:
				a = 0.6 + 0.4 * sin(float(Time.get_ticks_msec()) / 160.0)
			hc.a = a
			out.append("[color=#%s][b]%s[/b][/color]" % [hc.to_html(true), tr("HUMANS LEFT: %d") % humans_left])
	return "   ·   ".join(out)
