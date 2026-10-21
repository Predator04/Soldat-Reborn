extends Node
## Bomb Defusal (#304) — Main's helper for the mode (`main._bomb`).
##
## Attackers (RED in the first half, BLUE after halftime) carry one bomb to
## bomb site A or B and plant it (hold Use 3 s, standing); defenders stop
## them, or defuse a planted bomb (hold Use 7 s on it). Round ends: detonation
## (attackers), defuse (defenders), round clock out with no plant (defenders).
## First to ROUNDS_TO_WIN round wins takes the match (main.scores = rounds won;
## the match end goes through main's normal winner screen + next-map vote).
## The dead respawn in waves every WAVE_TIME s (main._respawn_delay_for_team
## asks wave_delay()); a new round respawns everyone at once.
##
## Host-authoritative: this runs on the host (or single player). Clients only
## send "Use held / released" for their own soldier (Main.net_bomb_use) and
## mirror the state from net_payload(): a reliable snapshot on join / round
## start (Main.net_bomb_sync) plus the 10 Hz mode-state stream; sequence
## numbers drop stale stream packets. Banners / sounds go through
## _objective_event (kinds bomb_*). The explosion runs on every peer
## (Main.net_bomb_boom): each peer damages the bodies it owns, the host
## observes client bodies for the trust guard.

const Main = preload("res://scripts/main.gd")

var main: Main

const ROUND_TIME := 150.0      # 2:30 to plant
const FUSE_TIME := 40.0
const PLANT_TIME := 3.0
const DEFUSE_TIME := 7.0
const WAVE_TIME := 10.0
const WAVE_MIN := 2.0          # dying this close to a wave joins the next one
const POST_TIME := 5.0         # round result banner before the next round
const ROUNDS_TO_WIN := 7
const HALF_ROUNDS := 6         # sides swap after this many rounds
const USE_RADIUS := 48.0       # a defuser stands this close to the bomb
const PICKUP_RADIUS := 26.0
const MOVE_TOL := 24.0         # drifting this far from where a plant / defuse began interrupts it
const GROUND_TOL := 10.0       # feet within this of the ground = standing
const BLAST_KILL := 320.0      # inside this the blast is lethal
const BLAST_RADIUS := 560.0
const BLAST_DMG := 250.0
const SITE_W := 240.0          # auto-placed site size (maps without bomb_sites)
const SITE_H := 150.0

# ── State (host-authoritative; clients mirror it) ──
var phase := "live"            # "live" | "planted" | "post"
var round_no := 1
var swapped := false           # halftime passed: BLUE attacks
var round_t := ROUND_TIME
var fuse_t := 0.0
var wave_t := WAVE_TIME
var post_t := 0.0
var bomb_state := "spawn"      # "spawn" (being handed out) | "carried" | "dropped" | "planted" | "gone"
var carrier: Node = null
var bomb_pos := Vector2.ZERO
var planted_site := ""
var planter_name := ""
var plant_prog := 0.0
var planter: Node = null       # soldier planting right now
var defuse_prog := 0.0
var defuser: Node = null
var last_result: Dictionary = {}   # {"team": int, "why": "boom" | "defused" | "time"}
var sites: Array = []          # [{"name": "A", "rect": Rect2}]
var bot_site := "A"            # the site attacking bots go for this round (host)
var stats := {"plants": 0, "defuses": 0, "booms": 0, "timeouts": 0, "drops": 0, "pickups": 0, "rounds": 0, "rejects": 0}

var _use_held: Dictionary = {}     # soldier instance id -> true while Use is held
var _act_anchor := Vector2.INF     # where the current plant / defuse began
var _seq := 0                      # host: payload counter; client: last applied
var _rejected: Dictionary = {}     # instance id -> true once a bad hold was logged
var _use_rate: Dictionary = {}     # peer id -> [window start ms, count]
var _visual: Node2D = null
var _site_nodes: Array = []
var _setup_done := false
var received := false              # client: a host snapshot has arrived (join hydration)


func attack_team() -> int:
	return main.TEAM_BLUE if swapped else main.TEAM_RED


func defend_team() -> int:
	return main.TEAM_RED if swapped else main.TEAM_BLUE


func active() -> bool:
	return Settings.game_mode == Settings.MODE_BOMB and _setup_done


# ── Setup ──────────────────────────────────────────────────────────────────

## Called on every peer from MatchModes._spawn_mode_entities.
func setup() -> void:
	sites = _read_sites()
	if sites.size() < 2:
		sites = _auto_sites()
	for s in sites:
		var n := Node2D.new()
		n.name = "BombSite%s" % str(s["name"])
		n.set_script(preload("res://scripts/bomb_site_visual.gd"))
		n.set("main", main)
		n.set("site_name", str(s["name"]))
		n.set("rect", s["rect"])
		main.add_child(n)
		_site_nodes.append(n)
	_visual = Node2D.new()
	_visual.name = "BombVisual"
	_visual.set_script(preload("res://scripts/bomb_visual.gd"))
	_visual.set("main", main)
	main.add_child(_visual)
	_setup_done = true
	_begin_round_state()


func _read_sites() -> Array:
	var out: Array = []
	var raw: Variant = main._map.get("bomb_sites", [])
	if typeof(raw) != TYPE_ARRAY:
		return out
	for b in raw:
		if typeof(b) != TYPE_DICTIONARY or not (b.get("rect") is Rect2):
			continue
		var nm := str(b.get("name", "A"))
		var dup := false
		for o in out:
			if str(o["name"]) == nm:
				dup = true
		if dup:
			continue
		out.append({"name": nm, "rect": b["rect"]})
		if out.size() >= 2:
			break
	out.sort_custom(func(a, b) -> bool: return str(a["name"]) < str(b["name"]))
	return out


## Maps built without bomb sites: two sites on the first-half defenders'
## (BLUE's) side, a little and a lot of the way from its base to the middle,
## each settled on the ground there. Pure geometry: the same on every peer.
func _auto_sites() -> Array:
	var blue: Vector2 = main._centroid(main._team_spawn_list(main.TEAM_BLUE))
	var red: Vector2 = main._centroid(main._team_spawn_list(main.TEAM_RED))
	var spots: Array = []
	var nav = main.nav
	if nav != null and not nav.is_empty():
		# Along the bots' own route from the defenders' spawn to the
		# attackers': A a quarter of the way, B about half way (on another
		# level if there is one nearby), both on walkable nav nodes.
		var route: PackedVector2Array = nav.path(blue, red)
		if route.size() >= 4:
			var total := 0.0
			for i in range(1, route.size()):
				total += route[i].distance_to(route[i - 1])
			for frac in [0.24, 0.5]:
				var want: float = total * frac
				var acc := 0.0
				var at: Vector2 = route[route.size() - 1]
				for i in range(1, route.size()):
					acc += route[i].distance_to(route[i - 1])
					if acc >= want:
						at = route[i]
						break
				var g := _site_node(nav, at, spots)
				if g != Vector2.INF:
					spots.append(g)
	if spots.size() < 2:
		spots.clear()
		for frac in [0.2, 0.42]:
			var x: float = clampf(lerpf(blue.x, red.x, frac), SITE_W, main.MAP_W - SITE_W)
			var g := _ground_spot(Vector2(x, lerpf(blue.y, red.y, frac) - 160.0))
			spots.append(g if g != Vector2.INF else blue + Vector2(float(spots.size()) * 300.0, 0))
	var out: Array = []
	for i in 2:
		var g: Vector2 = spots[i]
		out.append({"name": "AB"[i], "rect": Rect2(g.x - SITE_W * 0.5, g.y - SITE_H + 6.0, SITE_W, SITE_H)})
	return out


## The standable nav node nearest to `at` that is at least 420 px from the
## spots already taken (INF if none within 700 px).
func _site_node(nav, at: Vector2, taken: Array) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	var air: Dictionary = nav.get("_air") if nav.get("_air") != null else {}
	var pts: PackedVector2Array = nav.get("_pts")
	for id in pts.size():
		if air.has(id):
			continue
		var p: Vector2 = pts[id]
		var d := p.distance_to(at)
		if d > 700.0 or d >= best_d:
			continue
		var far := true
		for t in taken:
			if p.distance_to(t) < 420.0:
				far = false
		if not far or p.x < SITE_W * 0.5 or p.x > main.MAP_W - SITE_W * 0.5:
			continue
		var g := _ground_spot(p + Vector2(0, -10))
		if g == Vector2.INF or absf(g.y - p.y) > 24.0:
			continue
		best = g
		best_d = d
	return best


## First open, standable ground under `p` (scanning down from it), or INF.
func _ground_spot(p: Vector2) -> Vector2:
	var y := maxf(40.0, p.y)
	var lim := minf(main.KILL_Y, main.GROUND_Y + 1.0)
	var guard := 0
	while y < lim and guard < 12:
		guard += 1
		var gy: float = main._geom_ground_y(p.x, y)
		if gy == INF or gy > lim:
			return Vector2.INF
		var spot := Vector2(p.x, gy)
		if main._world._spot_is_clear(spot + Vector2(0, -2)):
			return spot
		y = gy + 8.0
	return Vector2.INF


func site_at(p: Vector2) -> String:
	for s in sites:
		if (s["rect"] as Rect2).grow(2.0).has_point(p + Vector2(0, -4)):
			return str(s["name"])
	return ""


func site_rect(nm: String) -> Rect2:
	for s in sites:
		if str(s["name"]) == nm:
			return s["rect"]
	return Rect2()


## Ground spot in the middle of a site (bot goals, HUD markers).
func site_spot(nm: String) -> Vector2:
	var r := site_rect(nm)
	if r.size == Vector2.ZERO:
		return Vector2.INF
	var c := Vector2(r.get_center().x, r.position.y + 4.0)
	var g := _ground_spot(c)
	return g if g != Vector2.INF and r.grow(4.0).has_point(g + Vector2(0, -4)) else Vector2(c.x, r.end.y - 6.0)


# ── Rounds ─────────────────────────────────────────────────────────────────

func _begin_round_state() -> void:
	phase = "live"
	round_t = ROUND_TIME
	fuse_t = 0.0
	post_t = 0.0
	wave_t = WAVE_TIME
	bomb_state = "spawn"
	carrier = null
	planted_site = ""
	planter_name = ""
	plant_prog = 0.0
	planter = null
	defuse_prog = 0.0
	defuser = null
	_act_anchor = Vector2.INF
	_rejected.clear()
	if _is_authority():
		main.time_left = round_t
		bot_site = "A" if randi() % 2 == 0 else "B"


func _is_authority() -> bool:
	return not Net.is_networked() or Net.is_host()


## Host: next round (after the result banner), halftime swap included.
func _next_round() -> void:
	round_no += 1
	var half_now := false
	if not swapped and round_no == HALF_ROUNDS + 1:
		swapped = true
		half_now = true
	_start_round()
	if half_now:
		_event("bomb_half", attack_team(), "")


func _start_round() -> void:
	_begin_round_state()
	_flush_respawns()
	if Net.is_networked():
		_send_sync(true)
	main._modes._restore_living_soldiers_local()
	_event("bomb_start", attack_team(), str(round_no))


## A whole new match (main._reset_round after the winner screen).
func match_reset() -> void:
	if not active() or not _is_authority():
		return
	round_no = 1
	swapped = false
	last_result = {}
	_start_round()


## Everyone waiting for a wave comes back now (new round).
func _flush_respawns() -> void:
	for key in main._rs_state.keys():
		main._rs_fire(int(key))
	main._bots.flush_pending_respawns()


## Seconds until the next respawn wave (a death right before a wave joins it
## only if there's WAVE_MIN left; otherwise the one after).
func wave_delay() -> float:
	var d := wave_t
	if d < WAVE_MIN:
		d += WAVE_TIME
	return maxf(0.1, d)


func _round_over(team: int, why: String) -> void:
	if phase == "post":
		return
	phase = "post"
	post_t = POST_TIME
	plant_prog = 0.0
	defuse_prog = 0.0
	planter = null
	defuser = null
	last_result = {"team": team, "why": why}
	stats["rounds"] = int(stats["rounds"]) + 1
	match why:
		"time": stats["timeouts"] = int(stats["timeouts"]) + 1
	main.scores[team] = int(main.scores.get(team, 0)) + 1
	main.scores[_other(team)] = int(main.scores.get(_other(team), 0))
	print("BOMB round %d over: team %d wins (%s) score %d-%d" % [round_no, team, why,
		int(main.scores.get(main.TEAM_BLUE, 0)), int(main.scores.get(main.TEAM_RED, 0))])
	_event("bomb_round", team, why)
	if Net.is_networked():
		_send_sync(false)
	if int(main.scores[team]) >= ROUNDS_TO_WIN:
		var why_txt := {"boom": "bomb detonated", "defused": "bomb defused", "time": "time ran out"}
		main.winner_note = "%d – %d in rounds (last: %s)" % [int(main.scores[team]), int(main.scores[_other(team)]), str(why_txt.get(why, why))]
		main.time_left = 0.0   # a won match ends the match (vote), not just a round
		main._modes._end_round(team)
	elif Net.is_networked() and Net.is_host():
		main._net._broadcast_match_state()


func _other(t: int) -> int:
	return main.TEAM_RED if t == main.TEAM_BLUE else main.TEAM_BLUE


# ── Host tick ──────────────────────────────────────────────────────────────

func tick(delta: float) -> void:
	if not active():
		return
	wave_t -= delta
	while wave_t <= 0.0:
		wave_t += WAVE_TIME
	if phase == "post":
		post_t -= delta
		main.time_left = maxf(0.0, post_t)
		if post_t <= 0.0:
			_next_round()
		return
	_tick_bomb()
	if phase == "live":
		round_t = maxf(0.0, round_t - delta)
		main.time_left = round_t
		_tick_plant(delta)
		if phase == "live" and round_t <= 0.0:
			_round_over(defend_team(), "time")
	elif phase == "planted":
		fuse_t = maxf(0.0, fuse_t - delta)
		main.time_left = fuse_t
		_tick_defuse(delta)
		if phase == "planted" and fuse_t <= 0.0:
			_detonate()


func _alive(s: Variant) -> bool:
	return s != null and is_instance_valid(s) and not bool((s as Node).get("dead"))


func _tick_bomb() -> void:
	match bomb_state:
		"spawn":
			var cands: Array = []
			for s in main.get_tree().get_nodes_in_group("soldier"):
				if _alive(s) and int(s.get("team")) == attack_team():
					cands.append(s)
			if not cands.is_empty():
				carrier = cands[randi() % cands.size()]
				bomb_state = "carried"
				bomb_pos = (carrier as Node2D).global_position
				_event("bomb_pick", attack_team(), str(carrier.get("display_name")))
		"carried":
			if not _alive(carrier) or int(carrier.get("team")) != attack_team():
				var at: Vector2 = bomb_pos
				if carrier != null and is_instance_valid(carrier):
					at = (carrier as Node2D).global_position
				_drop(at)
			else:
				bomb_pos = (carrier as Node2D).global_position
		"dropped":
			for s in main.get_tree().get_nodes_in_group("soldier"):
				if not _alive(s) or int(s.get("team")) != attack_team():
					continue
				if (s as Node2D).global_position.distance_to(bomb_pos) < PICKUP_RADIUS:
					carrier = s
					bomb_state = "carried"
					stats["pickups"] = int(stats["pickups"]) + 1
					_event("bomb_pick", attack_team(), str(s.get("display_name")))
					break


func _drop(at: Vector2) -> void:
	carrier = null
	plant_prog = 0.0
	planter = null
	stats["drops"] = int(stats["drops"]) + 1
	var gy: float = main._geom_ground_y(at.x, at.y - 4.0)
	if gy == INF or gy > main.KILL_Y or at.y > main.KILL_Y or not main._world._spot_is_clear(Vector2(at.x, gy) + Vector2(0, -1)):
		# Off the map / inside terrain: hand it to another attacker.
		bomb_state = "spawn"
		_event("bomb_drop", attack_team(), "")
		return
	bomb_pos = Vector2(at.x, gy)
	bomb_state = "dropped"
	_event("bomb_drop", attack_team(), "")


## Standing on the ground (feet on a surface), not jetting / falling.
func _standing(s: Node2D) -> bool:
	var p := s.global_position
	var gy: float = main._geom_ground_y(p.x, p.y - 6.0)
	return gy != INF and gy - p.y < GROUND_TOL and gy - p.y > -8.0


func holding_use(s: Node) -> bool:
	if s == null or not is_instance_valid(s):
		return false
	var b: Variant = s.get("bomb_use")
	if b != null:
		return bool(b)
	return bool(_use_held.get(s.get_instance_id(), false))


func _tick_plant(delta: float) -> void:
	var cand: Node2D = null
	if bomb_state == "carried" and _alive(carrier) and holding_use(carrier):
		var c := carrier as Node2D
		if site_at(c.global_position) != "" and _standing(c):
			cand = c
		elif c.get("bomb_use") == null:
			_reject(c, "plant: not standing in a bomb site")
	_reject_bad_holds()
	if cand == null:
		planter = null
		plant_prog = 0.0
		_act_anchor = Vector2.INF
		return
	if cand != planter:
		planter = cand
		plant_prog = 0.0
		_act_anchor = cand.global_position
	if cand.global_position.distance_to(_act_anchor) > MOVE_TOL:
		plant_prog = 0.0
		_act_anchor = cand.global_position
		return
	plant_prog = minf(1.0, plant_prog + delta / PLANT_TIME)
	if plant_prog >= 1.0:
		_plant(cand)


func _plant(s: Node2D) -> void:
	var p := s.global_position
	var gy: float = main._geom_ground_y(p.x, p.y - 6.0)
	bomb_pos = Vector2(p.x, gy if gy != INF else p.y)
	planted_site = site_at(p)
	planter_name = str(s.get("display_name"))
	bomb_state = "planted"
	phase = "planted"
	fuse_t = FUSE_TIME
	carrier = null
	planter = null
	plant_prog = 0.0
	_act_anchor = Vector2.INF
	stats["plants"] = int(stats["plants"]) + 1
	main.time_left = fuse_t
	print("BOMB planted at %s by %s" % [planted_site, planter_name])
	_event("bomb_plant", attack_team(), "%s@%s" % [planter_name, planted_site])
	if Net.is_networked():
		_send_sync(false)


func _tick_defuse(delta: float) -> void:
	var cand: Node2D = null
	if _alive(defuser) and holding_use(defuser) and int(defuser.get("team")) == defend_team() \
			and (defuser as Node2D).global_position.distance_to(bomb_pos) < USE_RADIUS:
		cand = defuser
	else:
		for s in main.get_tree().get_nodes_in_group("soldier"):
			if not _alive(s) or not holding_use(s):
				continue
			if int(s.get("team")) != defend_team():
				continue
			if (s as Node2D).global_position.distance_to(bomb_pos) < USE_RADIUS:
				cand = s
				break
	_reject_bad_holds()
	if cand == null:
		defuser = null
		defuse_prog = 0.0
		_act_anchor = Vector2.INF
		return
	if cand != defuser:
		defuser = cand
		defuse_prog = 0.0
		_act_anchor = cand.global_position
	if cand.global_position.distance_to(_act_anchor) > MOVE_TOL:
		defuse_prog = 0.0
		_act_anchor = cand.global_position
		return
	defuse_prog = minf(1.0, defuse_prog + delta / DEFUSE_TIME)
	if defuse_prog >= 1.0:
		stats["defuses"] = int(stats["defuses"]) + 1
		var who := str(cand.get("display_name"))
		bomb_state = "gone"
		print("BOMB defused by %s" % who)
		_event("bomb_defuse", defend_team(), who)
		_round_over(defend_team(), "defused")


## Log (once per hold) a Use that can't do anything — the gate's forged-request
## check reads these lines. Attackers on a planted bomb, defenders anywhere
## without one, attackers without the bomb.
func _reject_bad_holds() -> void:
	for s in main.get_tree().get_nodes_in_group("soldier"):
		if not _alive(s) or s.get("bomb_use") != null:
			continue   # bots never ask for anything they can't do
		var id: int = s.get_instance_id()
		if not holding_use(s):
			_rejected.erase(id)
			continue
		var t: int = int(s.get("team"))
		var why := ""
		if phase == "planted":
			if t != defend_team():
				why = "defuse: attackers can't defuse"
			elif (s as Node2D).global_position.distance_to(bomb_pos) >= USE_RADIUS:
				why = "defuse: too far from the bomb"
		elif phase == "live":
			if t != attack_team():
				why = "plant: defenders can't plant"
			elif s != carrier:
				why = "plant: not carrying the bomb"
		if why != "":
			_reject(s, why)


func _reject(s: Node, why: String) -> void:
	var id: int = s.get_instance_id()
	if _rejected.has(id):
		return
	_rejected[id] = true
	stats["rejects"] = int(stats["rejects"]) + 1
	print("BOMB reject %s (%s)" % [why, str(s.get("display_name"))])


func _detonate() -> void:
	stats["booms"] = int(stats["booms"]) + 1
	bomb_state = "gone"
	print("BOMB detonated at %s" % planted_site)
	_event("bomb_boom", attack_team(), planted_site)
	if Net.is_networked():
		main.bcast("net_bomb_boom", [bomb_pos], true)
	else:
		boom_local(bomb_pos)
	_round_over(attack_team(), "boom")


## The explosion, on every peer: effects + damage to the bodies this peer
## owns (the host shadows client bodies for the trust guard).
func boom_local(at: Vector2) -> void:
	var Gfx = preload("res://scripts/gfx.gd")
	Gfx.explosion(main, at, 240.0)
	for k in 5:
		var off := Vector2(float(k - 2) * 70.0, -absf(float(k - 2)) * 22.0 - 30.0)
		Gfx.explosion(main, at + off, 120.0)
	Gfx.scorch(main, at, 140.0)
	Sfx.explode(at)
	var host_side: bool = Net.is_networked() and Net.is_host()
	for s in main.get_tree().get_nodes_in_group("soldier"):
		if not _alive(s):
			continue
		var d: float = (s as Node2D).global_position.distance_to(at)
		if d >= BLAST_RADIUS:
			continue
		var dmg := BLAST_DMG if d <= BLAST_KILL else BLAST_DMG * (1.0 - (d - BLAST_KILL) / (BLAST_RADIUS - BLAST_KILL))
		if main.multiplayer.multiplayer_peer == null or s.is_multiplayer_authority():
			s.take_damage(dmg, "", "Bomb", -1)
		elif host_side and s.has_method("observe_damage"):
			s.observe_damage(dmg, "", "Bomb", -1)
	preload("res://scripts/buggy.gd").splash(main.get_tree(), at, BLAST_RADIUS * 0.6, BLAST_DMG, "", "Bomb", -1)


func _event(kind: String, team: int, who: String) -> void:
	main._modes._objective_event(kind, team, who)


# ── Use input ──────────────────────────────────────────────────────────────

## Host / single player: soldier `s` presses or releases Use.
func set_use(s: Node, held: bool) -> void:
	if s == null or not is_instance_valid(s):
		return
	if held:
		_use_held[s.get_instance_id()] = true
	else:
		_use_held.erase(s.get_instance_id())
		_rejected.erase(s.get_instance_id())


## Host: a client's Use for ITS OWN soldier (the sender's body — a client
## can't name anyone else). Rate-limited; what it may do is decided in tick.
func net_use(sender: int, held: bool) -> void:
	if not Net.is_host() or not active():
		return
	var now := Time.get_ticks_msec()
	var r: Array = _use_rate.get(sender, [now, 0])
	if now - int(r[0]) > 1000:
		r = [now, 0]
	r[1] = int(r[1]) + 1
	_use_rate[sender] = r
	if int(r[1]) > 20:
		return
	var body = main._players_by_id.get(sender)
	if body == null or not is_instance_valid(body):
		return
	set_use(body, held)


# ── Net state ──────────────────────────────────────────────────────────────

func _sid(s: Variant) -> int:
	if s == null or not is_instance_valid(s):
		return 0
	var nm := String((s as Node).name)
	if nm.begins_with("Player_"):
		return int(nm.substr(7))
	var bid: Variant = (s as Node).get("bot_id")
	if bid != null and int(bid) > 0:
		return -int(bid)
	if s == main.player:
		return 1
	return 0


func _by_sid(id: int) -> Node:
	if id > 0 and main._players_by_id.has(id) and is_instance_valid(main._players_by_id[id]):
		return main._players_by_id[id]
	if id < 0 and main._bots_by_id.has(-id) and is_instance_valid(main._bots_by_id[-id]):
		return main._bots_by_id[-id]
	return null


func net_payload(full: bool) -> Dictionary:
	_seq += 1
	var d := {"q": _seq, "ph": phase, "rn": round_no, "sw": swapped, "rt": round_t, "ft": fuse_t, "wt": wave_t,
		"pt": post_t, "bs": bomb_state, "c": _sid(carrier), "bp": bomb_pos, "site": planted_site, "pn": planter_name,
		"pp": plant_prog, "pl": _sid(planter), "dp": defuse_prog, "df": _sid(defuser), "res": last_result}
	if full:
		var ss: Array = []
		for s in sites:
			var r: Rect2 = s["rect"]
			ss.append([str(s["name"]), r.position.x, r.position.y, r.size.x, r.size.y])
		d["sites"] = ss
	return d


func _send_sync(reset: bool) -> void:
	var d := net_payload(false)
	d["reset"] = reset
	main.bcast("net_bomb_sync", [d], false)


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
	swapped = bool(d.get("sw", swapped))
	round_t = float(d.get("rt", round_t))
	fuse_t = float(d.get("ft", fuse_t))
	wave_t = float(d.get("wt", wave_t))
	post_t = float(d.get("pt", post_t))
	bomb_state = str(d.get("bs", bomb_state))
	carrier = _by_sid(int(d.get("c", 0)))
	bomb_pos = d.get("bp", bomb_pos)
	planted_site = str(d.get("site", planted_site))
	planter_name = str(d.get("pn", planter_name))
	plant_prog = float(d.get("pp", 0.0))
	planter = _by_sid(int(d.get("pl", 0)))
	defuse_prog = float(d.get("dp", 0.0))
	defuser = _by_sid(int(d.get("df", 0)))
	last_result = d.get("res", {}) if typeof(d.get("res", {})) == TYPE_DICTIONARY else {}
	if d.has("sites") and typeof(d["sites"]) == TYPE_ARRAY:
		var ss: Array = []
		for e in d["sites"]:
			if typeof(e) == TYPE_ARRAY and (e as Array).size() >= 5:
				ss.append({"name": str(e[0]), "rect": Rect2(float(e[1]), float(e[2]), float(e[3]), float(e[4]))})
		if ss.size() >= 2:
			sites = ss
			for i in mini(ss.size(), _site_nodes.size()):
				_site_nodes[i].set("site_name", str(ss[i]["name"]))
				_site_nodes[i].set("rect", ss[i]["rect"])
				(_site_nodes[i] as CanvasItem).queue_redraw()


## Client: reliable snapshot (join / round start / plant / round end).
func net_sync(d: Dictionary) -> void:
	if _is_authority():
		return
	apply_payload(d)
	if bool(d.get("reset", false)):
		main._modes._restore_living_soldiers_local()


## Clients tick the clocks between snapshots so the HUD counts smoothly.
func client_tick(delta: float) -> void:
	if not active() or _is_authority():
		return
	wave_t -= delta
	while wave_t <= 0.0:
		wave_t += WAVE_TIME
	match phase:
		"live": round_t = maxf(0.0, round_t - delta)
		"planted": fuse_t = maxf(0.0, fuse_t - delta)
		"post": post_t = maxf(0.0, post_t - delta)
	if bomb_state == "carried" and _alive(carrier):
		bomb_pos = (carrier as Node2D).global_position


# ── HUD helpers (read on every peer) ───────────────────────────────────────

func role_of(team: int) -> String:
	return "attack" if team == attack_team() else "defend"


## What the local soldier could do with Use right now: "plant" | "defuse" | "".
func use_hint(p: Node) -> String:
	if not active() or not _alive(p):
		return ""
	var t := int(p.get("team"))
	if phase == "live" and bomb_state == "carried" and carrier == p and site_at((p as Node2D).global_position) != "":
		return "plant"
	if phase == "planted" and t == defend_team() and (p as Node2D).global_position.distance_to(bomb_pos) < USE_RADIUS + 40.0:
		return "defuse"
	return ""


## Off-screen arrow targets for objective_hud: [[pos, color, label]].
func hud_targets(p: Node) -> Array:
	var out: Array = []
	if not active():
		return out
	var att: bool = p != null and is_instance_valid(p) and int(p.get("team")) == attack_team()
	var site_col := Color(1.0, 0.62, 0.2)
	for s in sites:
		var r: Rect2 = s["rect"]
		var hot: bool = phase == "planted" and str(s["name"]) == planted_site
		out.append([r.get_center(), Color(1.0, 0.3, 0.25) if hot else site_col, str(s["name"])])
	if bomb_state == "dropped" or (bomb_state == "carried" and att and carrier != p):
		out.append([bomb_pos + Vector2(0, -20), Color(1.0, 0.85, 0.3), "BOMB"])
	return out


func carrier_name() -> String:
	return str(carrier.get("display_name")) if _alive(carrier) else ""


func _team_info(team: int) -> Dictionary:
	if main.hud != null and main.hud.has_method("_team_display_info"):
		return main.hud._team_display_info(team)
	return {"name": "BLUE" if team == main.TEAM_BLUE else "RED", "color": Color.WHITE}


## Banner text + colour for a bomb_* objective event ("" = none).
func banner(kind: String, team: int, who: String) -> Array:
	var info := _team_info(team)
	var col: Color = info.get("color", Color.WHITE)
	match kind:
		"bomb_plant":
			var parts := who.split("@")
			var site: String = parts[1] if parts.size() > 1 else planted_site
			return [tr("BOMB PLANTED AT %s") % site, Color(1.0, 0.35, 0.25)]
		"bomb_defuse":
			return [tr("BOMB DEFUSED  (%s)") % who, col]
		"bomb_boom":
			return [tr("BOMB DETONATED"), Color(1.0, 0.45, 0.2)]
		"bomb_drop":
			return [tr("THE BOMB WAS DROPPED"), Color(1.0, 0.85, 0.3)]
		"bomb_half":
			return [tr("HALFTIME — SIDES SWAP"), Color(1.0, 0.85, 0.35)]
		"bomb_start":
			return [tr("ROUND %s — %s ATTACK") % [who, str(info.get("name", ""))], col]
		"bomb_round":
			var why := {"boom": tr("bomb detonated"), "defused": tr("bomb defused"), "time": tr("time ran out")}
			return [tr("%s WIN THE ROUND — %s") % [str(info.get("name", "")), str(why.get(who, who))], col]
	return ["", col]


## Kill-feed line for a bomb_* event ("" = none).
func feed_text(kind: String, team: int, who: String) -> String:
	match kind:
		"bomb_plant":
			var parts := who.split("@")
			return tr("%s planted the bomb at %s") % [parts[0], parts[1] if parts.size() > 1 else "?"]
		"bomb_defuse":
			return tr("%s defused the bomb") % who
		"bomb_pick":
			return (tr("%s has the bomb") % who) if who != "" else ""
		"bomb_round":
			return tr("%s won round %d") % [str(_team_info(team).get("name", "")), round_no]
	return ""


## Status line under the score strip (objective_hud.gd).
func status_bbcode(p: Node) -> String:
	if not active():
		return ""
	var out: PackedStringArray = PackedStringArray()
	var half := tr("2nd half") if swapped else tr("1st half")
	out.append("[b]%s[/b] %s" % [tr("ROUND %d") % round_no, half])
	if p != null and is_instance_valid(p):
		var mine: bool = int(p.get("team")) == attack_team()
		var c := Color(1.0, 0.55, 0.3) if mine else Color(0.5, 0.8, 1.0)
		out.append("[color=#%s][b]%s[/b][/color]" % [c.to_html(false), tr("ATTACK") if mine else tr("DEFEND")])
	var st := ""
	match bomb_state:
		"carried":
			st = tr("YOU HAVE THE BOMB") if (carrier == p and p != null) else tr("BOMB: CARRIED")
		"dropped":
			st = tr("BOMB: DROPPED")
		"planted":
			st = tr("BOMB PLANTED AT %s") % planted_site
	if st != "":
		var bc := Color(1, 0.35, 0.25) if bomb_state == "planted" else Color(1.0, 0.85, 0.3)
		if bomb_state == "carried" and carrier == p:
			bc = Color(1, 1, 0.5)
		out.append("[color=#%s][b]%s[/b][/color]" % [bc.to_html(false), st])
	return "   ·   ".join(out)
