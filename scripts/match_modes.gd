extends Node
## Main's game-mode rules (#258 split of main.gd): objectives for every mode
## (CTF / INF / HTF flags, Rambo bow, Pointmatch, Domination, Battle Royale ring,
## Gun Game ladder), kill scoring + streaks, and round end / reset (incl. Survival).
##
## Host-authoritative in MP: these run on the host (or single player) and their
## results reach clients through the match / mode / flag state broadcasts in
## match_net.gd. Objective events go through _objective_event. Scores, flags and
## round state stay on Main (the HUD and tests read them there).

const Main = preload("res://scripts/main.gd")
const WeaponPickup = preload("res://scripts/weapon_pickup.gd")

var main: Main

# (#76) Kill-streak + multi-kill announcer state. Keyed by killer's display_name.
# {"streak": int (kills-per-life), "multi": int (kills within 2s), "multi_t": float,
#  "team": int (last-known team for banner tint)}. Runs on every peer so banners
# render locally; the kill-feed replication path (kill.emit → net_kill_feed) drives it.
var _streaks: Dictionary = {}
const STREAK_TITLES := {2: "Double Kill", 3: "Multi Kill", 4: "Killing Spree", 5: "Rampage", 6: "Godlike"}
const STREAK_ULTRA := "Ultra Godlike"    # 7+ collapses into a single top rung
const MULTI_KILL_WINDOW := 2.0            # seconds since previous kill still counts as multi
const STREAK_ANNOUNCE_END_MIN := 3        # streak length that earns an "ended X's N-kill streak" line
# HTF: while a team's carrier is alive with the flag, ticks accumulate. This
# fractional accumulator flushes to `scores` in whole points.
var _htf_accum: Dictionary = {}
# Rambo bow — cooldown between carrier-death and the bow re-spawning at map center.
var _rambo_respawn_cd: float = 0.0
const RAMBO_RESPAWN_DELAY := 4.0
# Pointmatch — bookkeeping for respawning pickups (spawn_pos -> _next_respawn_t).
var _pm_pickups: Dictionary = {}
const DOM_CAPTURE_TIME := 4.0    # seconds standing on a neutral/enemy point to flip it
var _dom_accum: Dictionary = {}  # team_id -> fractional accumulator (float)
const BR_SHRINK_RATE := 42.0   # px/sec — full ring closes in ~52s
const BR_ZONE_MIN := 180.0
# Gun Game (MODE_GG) — per-soldier rung on the 16-weapon ladder, keyed by
# display_name so the level survives death/respawn (a fresh body reads its
# rung from here in _spawn_*). Host-authoritative in MP; the RPC below fans
# each update out to every peer so client-owned players re-apply the weapon.
const GG_KNIFE_LEVEL := 15
const GG_GOLD_KNIFE_LEVEL := 16
# Ladder weapon names in rung order — mirrors Player.GG_LADDER. Used to
# validate that a kill was made with the killer's current rung weapon (so
# grenade / dropped-weapon / bonus-forced kills don't accidentally advance).
const GG_LADDER_NAMES := [
	"USSOCOM", "Deagles", "MP5", "Steyr AUG", "AK-74", "Spas-12",
	"Ruger 77", "Minimi", "M79", "Minigun", "Flamethrower", "Rambo Bow",
	"LAW", "Barrett", "Chainsaw", "Knife",
]
const WINNER_DISPLAY := 4.0
const WINNER_VOTE_DISPLAY := 10.0    # winner screen with a next-map vote


func _spawn_mode_entities() -> void:
	# Called on both host and client so flags/pickups appear on all peers.
	match Settings.game_mode:
		Settings.MODE_CTF: _spawn_flags()
		Settings.MODE_INF: _spawn_flag_inf()
		Settings.MODE_HTF: _spawn_flag_htf()
		Settings.MODE_RM:  _spawn_rambo_bow()
		Settings.MODE_PM:  _spawn_point_pickups()
		Settings.MODE_DOM: _spawn_dom_points()
		Settings.MODE_BR:  _reset_br_zone()


func _spawn_flags() -> void:
	# CTF bases: BLUE on the far left, RED on the far right of the map's ground row.
	# Custom maps (editor) can override the pair via `ctf_flags: [blue, red]`.
	var ground_y: float = float(main._map.get("ctf_ground_y", main.GROUND_Y))
	var blue_base := Vector2(300, ground_y)
	var red_base := Vector2(main.MAP_W - 300, ground_y)
	var custom: Array = main._map.get("ctf_flags", [])
	if custom.size() >= 2:
		blue_base = custom[0]
		red_base = custom[1]
	# Flags stand on their pole — settle each base onto the ground beneath it
	# so none float in mid-air or sit buried in a floor.
	blue_base = main._settle_on_ground(blue_base)
	red_base = main._settle_on_ground(red_base)
	main.flags = [
		_make_flag(main.TEAM_BLUE, blue_base),
		_make_flag(main.TEAM_RED, red_base),
	]


func _spawn_flag_inf() -> void:
	# INF: single neutral flag near the center. Attackers (RED) deliver to the
	# defenders' base (BLUE) to score. Defenders return the flag by touching it.
	# Custom maps override the flag + defender base via `inf_flag` / `ctf_flags[0]`.
	var ground_y: float = float(main._map.get("ctf_ground_y", main.GROUND_Y))
	var center: Vector2 = main._settle_on_ground(main._map.get("inf_flag", Vector2(main.MAP_W * 0.5, ground_y)))
	var defender_base := Vector2(300, ground_y)
	var custom_flags: Array = main._map.get("ctf_flags", [])
	if custom_flags.size() >= 1:
		defender_base = custom_flags[0]
	defender_base = main._settle_on_ground(defender_base)
	var f := _make_flag(0, center)
	f.set_meta("capture_point", defender_base)
	main.flags = [f]


func _spawn_flag_htf() -> void:
	# HTF: single neutral flag mid-map. The carrying team ticks score per second.
	var ground_y: float = float(main._map.get("ctf_ground_y", main.GROUND_Y))
	var center: Vector2 = main._settle_on_ground(main._map.get("htf_flag", Vector2(main.MAP_W * 0.5, ground_y)))
	main.flags = [_make_flag(0, center)]


func _spawn_rambo_bow() -> void:
	# RM: single Rambo Bow pickup at map center — carrier gets HP regen +
	# is the only one who scores kills.
	# In MP only the host spawns it — the pickup state stream (#34) mirrors
	# it to clients so both peers agree on where the bow is.
	if Net.is_networked() and not Net.is_host():
		return
	var ground_y: float = float(main._map.get("ctf_ground_y", main.GROUND_Y))
	var wp := WeaponPickup.new()
	wp.weapon_name = "Rambo Bow"
	wp.team = -1
	wp.thrower_name = ""
	wp.damage_on_hit = 0.0
	wp.global_position = main._map.get("rambo_pos", Vector2(main.MAP_W * 0.5, ground_y - 40.0))
	wp.set_meta("rambo_spawn", true)
	if Net.is_networked() and Net.is_host():
		wp.pickup_id = main.next_pickup_id()
	main.add_child(wp)


func _spawn_point_pickups() -> void:
	# PM: scatter respawning point pickups. Each grants +1 to the toucher's team.
	# #113: honor an explicit "point_spawns" list from the map editor; fall back
	# to the built-in scan-line pattern so procedural maps still play PM.
	var explicit: Array = main._map.get("point_spawns", [])
	if not explicit.is_empty():
		for pos in explicit:
			if pos is Vector2:
				_spawn_point_pickup(pos)
		return
	# Default pattern scales with the map width and sits 30 px above the
	# actual ground (the old fixed 4800-arena row floated or sank into hills).
	var ground_y: float = float(main._map.get("ctf_ground_y", main.GROUND_Y))
	var fracs: PackedFloat32Array = [0.15, 0.29, 0.44, 0.5, 0.56, 0.71, 0.85]
	for f in fracs:
		_spawn_point_pickup(main._settle_on_ground(Vector2(main.MAP_W * f, ground_y - 2.0)) + Vector2(0, -30.0))


func _make_flag(team: int, base: Vector2) -> Area2D:
	var a := Area2D.new()
	a.add_to_group("ctf_flag")
	a.set_meta("team", team)
	a.set_meta("home", base)
	a.set_meta("carrier", null)
	a.position = base
	var col := CollisionShape2D.new()
	var cs := CircleShape2D.new()
	cs.radius = 18.0
	col.shape = cs
	a.add_child(col)
	# Animated flag (scripts/flag_visual.gd): waving shaded cloth on a pole with
	# a stone base + team glow at home, strapped to the carrier's back while
	# carried, and planted with a blinking beacon when dropped.
	var vis := Node2D.new()
	vis.name = "FlagVisual"
	vis.set_script(preload("res://scripts/flag_visual.gd"))
	a.add_child(vis)
	main.add_child(a)
	return a


func _drop_flag(f: Node2D, at: Vector2) -> void:
	# Carrier died: the flag falls to the ground under them. If there is no
	# ground (carrier fell off the map), the flag goes straight home instead
	# of hanging in the void where nobody can ever reach it.
	f.set_meta("carrier", null)
	var ft: int = int(f.get_meta("team")) if f.has_meta("team") else 0
	var gy := main._geom_ground_y(at.x, at.y - 4.0)
	if gy == INF or gy > main.KILL_Y or at.y > main.KILL_Y:
		f.position = f.get_meta("home")
		_objective_event("return", ft, "")
		return
	var p := Vector2(at.x, gy)
	if not main._spot_is_clear(p + Vector2(0, -1)):
		f.position = f.get_meta("home")
		_objective_event("return", ft, "")
		return
	f.position = p
	_objective_event("drop", ft, "")


func _tick_ctf() -> void:
	# Two-flag CTF: touch enemy flag to carry, deliver to own home to score.
	# Carried flags snap to the carrier; dropped flags stay in place until touched.
	var soldiers := main.get_tree().get_nodes_in_group("soldier")
	for f in main.flags:
		if not is_instance_valid(f):
			continue
		var flag_team: int = int(f.get_meta("team"))
		var home: Vector2 = f.get_meta("home")
		var carrier: Variant = f.get_meta("carrier") if f.has_meta("carrier") else null
		if typeof(carrier) == TYPE_OBJECT and not is_instance_valid(carrier):
			# Carrier body was freed (killed bot / disconnect) before we saw it
			# die — drop the flag where it was instead of leaving it hovering.
			_drop_flag(f, f.position + Vector2(0, 30))
			continue
		if is_instance_valid(carrier):
			if bool(carrier.get("dead")):
				# Carrier died — drop flag where they fell (settled onto the ground).
				_drop_flag(f, carrier.global_position)
				continue
			f.position = carrier.global_position + Vector2(0, -30)
			# Did the carrier reach their own base (their home flag)? Score + reset both.
			for other in main.flags:
				if other == f:
					continue
				var other_team: int = int(other.get_meta("team"))
				var other_home: Vector2 = other.get_meta("home")
				var other_carrier: Variant = other.get_meta("carrier") if other.has_meta("carrier") else null
				if int(carrier.get("team")) == other_team and other_carrier == null:
					if f.global_position.distance_to(other_home) < 40.0:
						_ctf_score(int(carrier.get("team")), str(carrier.get("display_name")))
						# Return both flags to base.
						for ff in main.flags:
							ff.position = ff.get_meta("home")
							ff.set_meta("carrier", null)
			continue
		# Not carried — check for a grab (enemy touches) or return-to-base (own team touches).
		for s in soldiers:
			if not is_instance_valid(s) or bool(s.get("dead")):
				continue
			if s.global_position.distance_to(f.global_position) < 22.0:
				var s_team: int = int(s.get("team"))
				if s_team == flag_team:
					# Own team touches: if the flag is away from home, return it.
					if f.position.distance_to(home) > 12.0:
						f.position = home
						_objective_event("return", flag_team, str(s.get("display_name")))
						break
					# A defender standing on its home flag must not block an
					# enemy grab — keep scanning.
					continue
				else:
					# Enemy pickup.
					f.set_meta("carrier", s)
					_objective_event("grab", flag_team, str(s.get("display_name")))
					main._bots._bot_radio_efc(flag_team, s)
				break


func _tick_inf() -> void:
	# Single-flag INF: RED = attackers, BLUE = defenders. RED delivers to
	# the defenders' base to score; BLUE returns the flag by touching it.
	var f: Area2D = main.flags[0] as Area2D
	if not is_instance_valid(f):
		return
	var home: Vector2 = f.get_meta("home")
	var capture: Vector2 = f.get_meta("capture_point")
	var carrier: Variant = f.get_meta("carrier") if f.has_meta("carrier") else null
	if typeof(carrier) == TYPE_OBJECT and not is_instance_valid(carrier):
		_drop_flag(f, f.position + Vector2(0, 30))
		return
	if is_instance_valid(carrier):
		if bool(carrier.get("dead")):
			_drop_flag(f, carrier.global_position)
			return
		f.position = carrier.global_position + Vector2(0, -30)
		if int(carrier.get("team")) == main.TEAM_RED \
				and f.global_position.distance_to(capture) < 40.0:
			_inf_score(main.TEAM_RED, str(carrier.get("display_name")))
			f.position = home
			f.set_meta("carrier", null)
		return
	# Not carried — pickup / return.
	for s in main.get_tree().get_nodes_in_group("soldier"):
		if not is_instance_valid(s) or bool(s.get("dead")):
			continue
		if s.global_position.distance_to(f.global_position) < 22.0:
			var s_team: int = int(s.get("team"))
			if s_team == main.TEAM_RED:
				f.set_meta("carrier", s)
				_objective_event("grab", 0, str(s.get("display_name")))
				break
			elif s_team == main.TEAM_BLUE:
				if f.position.distance_to(home) > 12.0:
					f.position = home
					_objective_event("return", 0, str(s.get("display_name")))
					break


func _inf_score(team: int, capturer: String) -> void:
	main.scores[team] = int(main.scores.get(team, 0)) + 1
	_objective_event("capture", team, capturer)
	if int(main.scores[team]) >= main.INF_SCORE_TO_WIN:
		_end_round(team)


func _tick_htf(delta: float) -> void:
	# Single-flag HTF: whichever team's soldier is carrying accumulates points
	# per second. Enemy soldier picks it up → carrier switches. If dropped and
	# no one grabs, it just waits.
	var f: Area2D = main.flags[0] as Area2D
	if not is_instance_valid(f):
		return
	var home: Vector2 = f.get_meta("home")
	var carrier: Variant = f.get_meta("carrier") if f.has_meta("carrier") else null
	if typeof(carrier) == TYPE_OBJECT and not is_instance_valid(carrier):
		_drop_flag(f, f.position + Vector2(0, 30))
		return
	if is_instance_valid(carrier):
		if bool(carrier.get("dead")):
			_drop_flag(f, carrier.global_position)
			return
		f.position = carrier.global_position + Vector2(0, -30)
		var ct: int = int(carrier.get("team"))
		_htf_accum[ct] = float(_htf_accum.get(ct, 0.0)) + delta
		# Flush whole seconds into scores so the scoreboard ticks visibly.
		while float(_htf_accum.get(ct, 0.0)) >= 1.0:
			_htf_accum[ct] = float(_htf_accum[ct]) - 1.0
			main.scores[ct] = int(main.scores.get(ct, 0)) + 1
			if int(main.scores[ct]) >= main.HTF_SCORE_TO_WIN:
				_end_round(ct)
				return
		return
	# Not carried — first soldier to touch grabs it.
	for s in main.get_tree().get_nodes_in_group("soldier"):
		if not is_instance_valid(s) or bool(s.get("dead")):
			continue
		if s.global_position.distance_to(f.global_position) < 22.0:
			f.set_meta("carrier", s)
			_objective_event("grab", 0, str(s.get("display_name")))
			break
	# If dropped far from home and untouched for a while, reset (mercy behavior).
	if f.position.distance_to(home) > 1400.0:
		f.position = home


func _tick_rambo() -> void:
	# Rambo Match: single bow pickup. Whoever holds it regenerates HP fast and
	# is the only player whose kills score. Kill feed handled by _on_kill_scored.
	# Determine current carrier by scanning weapon_pickups + soldiers holding "Rambo Bow".
	var carrier_id := 0
	for s in main.get_tree().get_nodes_in_group("soldier"):
		if not is_instance_valid(s) or bool(s.get("dead")):
			continue
		# player.weapons + secondary lookup: if their active weapon is "Rambo Bow".
		var wname := ""
		if s.get("weapons") != null:
			var idx: int = int(s.get("weapon_index"))
			var arr: Array = s.get("weapons")
			if idx >= 0 and idx < arr.size():
				wname = str(arr[idx]["name"])
		elif s.get("loadout") != null:
			wname = str(s.get("loadout"))
		if wname == "Rambo Bow":
			carrier_id = s.get_instance_id()
			# Regenerate carrier's HP fast.
			# Health belongs to the body's authority — a client-owned carrier
			# regenerates itself (see the client branch of _process).
			if main.multiplayer.multiplayer_peer == null or s.is_multiplayer_authority():
				var hp: float = float(s.get("health"))
				s.set("health", minf(100.0, hp + 40.0 * main.get_process_delta_time()))
			break
	# Cooldown gate (#38): if the previous frame had a carrier and we now have none,
	# they died — hold off the bow's map-center respawn for a few seconds so an
	# instant re-pickup doesn't happen the same tick.
	if main._rambo_carrier_id != 0 and carrier_id == 0:
		_rambo_respawn_cd = RAMBO_RESPAWN_DELAY
	main._rambo_carrier_id = carrier_id
	_rambo_respawn_cd = maxf(0.0, _rambo_respawn_cd - main.get_process_delta_time())
	# Respawn the bow at map center if it doesn't exist and nobody is holding it.
	if carrier_id == 0 and _rambo_respawn_cd <= 0.0:
		var exists := false
		for wp in main.get_tree().get_nodes_in_group("weapon_pickup"):
			if is_instance_valid(wp) and str(wp.get("weapon_name")) == "Rambo Bow":
				exists = true
				break
		if not exists:
			_spawn_rambo_bow()


func _spawn_dom_points() -> void:
	# Three capture points along the map — left, center, right — on the ground row.
	# Custom maps override the trio via `dom_points: [Vector2, Vector2, Vector2]`.
	var ground_y: float = float(main._map.get("ctf_ground_y", main.GROUND_Y))
	var default_slots := [
		{"pos": main._settle_on_ground(Vector2(main.MAP_W * 0.20, ground_y - 30.0)) + Vector2(0, -30.0), "name": "A"},
		{"pos": main._settle_on_ground(Vector2(main.MAP_W * 0.50, ground_y - 30.0)) + Vector2(0, -30.0), "name": "B"},
		{"pos": main._settle_on_ground(Vector2(main.MAP_W * 0.80, ground_y - 30.0)) + Vector2(0, -30.0), "name": "C"},
	]
	var slots: Array = default_slots
	var custom: Array = main._map.get("dom_points", [])
	if custom.size() >= 1:
		slots = []
		var labels := ["A", "B", "C", "D", "E"]
		for i in custom.size():
			slots.append({"pos": custom[i], "name": labels[mini(i, labels.size() - 1)]})
	var visual := preload("res://scripts/dom_point_visual.gd")
	for slot in slots:
		var a := Area2D.new()
		a.add_to_group("dom_point")
		a.set_meta("owner_team", 0)   # 0 = neutral, 1 = BLUE, 2 = RED
		a.set_meta("progress", 0.0)   # 0..1 while being captured; polarity is signed by team
		a.set_meta("cap_team", 0)     # which team is actively capturing (0 = none)
		a.set_meta("label", str(slot["name"]))
		a.position = slot["pos"]
		var col := CollisionShape2D.new()
		var cs := CircleShape2D.new()
		cs.radius = 40.0
		col.shape = cs
		a.add_child(col)
		var vis := Node2D.new()
		vis.set_script(visual)
		a.add_child(vis)
		main.add_child(a)
		main._dom_points.append(a)


func _tick_domination(delta: float) -> void:
	var soldiers := main.get_tree().get_nodes_in_group("soldier")
	for a in main._dom_points:
		if not is_instance_valid(a):
			continue
		# Which teams have soldiers standing on this point?
		var blue_on := 0
		var red_on := 0
		var radius: float = 44.0
		for s in soldiers:
			if not is_instance_valid(s) or bool(s.get("dead")):
				continue
			var t: int = int(s.get("team"))
			if s.global_position.distance_to(a.global_position) > radius:
				continue
			if t == main.TEAM_BLUE:
				blue_on += 1
			elif t == main.TEAM_RED:
				red_on += 1
		var contested: bool = blue_on > 0 and red_on > 0
		var owner_team: int = int(a.get_meta("owner_team"))
		var progress: float = float(a.get_meta("progress"))
		var cap_team: int = int(a.get_meta("cap_team"))
		if not contested and (blue_on > 0 or red_on > 0):
			var t_cap: int = main.TEAM_BLUE if blue_on > 0 else main.TEAM_RED
			if owner_team == t_cap:
				progress = 0.0
				cap_team = 0
			else:
				# Same capturing team as last tick → keep ramping. Fresh team resets progress.
				if cap_team != t_cap:
					cap_team = t_cap
					progress = 0.0
				progress = clampf(progress + delta / DOM_CAPTURE_TIME, 0.0, 1.0)
				if progress >= 1.0:
					owner_team = t_cap
					progress = 0.0
					cap_team = 0
					_objective_event("dom", t_cap, str(a.get_meta("label")))
		elif not contested and blue_on == 0 and red_on == 0:
			# Empty point drains progress over time so long-held drops reset naturally.
			progress = maxf(0.0, progress - delta / (DOM_CAPTURE_TIME * 2.0))
			if progress <= 0.0:
				cap_team = 0
		a.set_meta("owner_team", owner_team)
		a.set_meta("progress", progress)
		a.set_meta("cap_team", cap_team)
	# Tick score: each owned point = 1 pt/sec into that team's accumulator.
	for a in main._dom_points:
		if not is_instance_valid(a):
			continue
		var owner_team: int = int(a.get_meta("owner_team"))
		if owner_team == 0:
			continue
		_dom_accum[owner_team] = float(_dom_accum.get(owner_team, 0.0)) + delta
		while float(_dom_accum.get(owner_team, 0.0)) >= 1.0:
			_dom_accum[owner_team] = float(_dom_accum[owner_team]) - 1.0
			main.scores[owner_team] = int(main.scores.get(owner_team, 0)) + 1
			if int(main.scores[owner_team]) >= main.DOM_SCORE_TO_WIN:
				_end_round(owner_team)
				return


func dom_points() -> Array:
	return main._dom_points


func _reset_br_zone() -> void:
	main._br_zone_radius = 2200.0
	main._br_zone_center = Vector2(main.MAP_W * 0.5, main.MAP_H * 0.6)
	# Big ported maps: start the ring wide enough to cover the whole world.
	main._br_zone_radius = maxf(2200.0, Vector2(main.MAP_W, main.MAP_H).length() * 0.5)
	# Attach the zone visual once — it reads center/radius from us on each redraw.
	if not main.has_node("BrZoneVisual"):
		var vis := Node2D.new()
		vis.name = "BrZoneVisual"
		vis.set_script(preload("res://scripts/br_zone_visual.gd"))
		main.add_child(vis)


func _tick_battle_royale(delta: float) -> void:
	main._br_zone_radius = maxf(BR_ZONE_MIN, main._br_zone_radius - BR_SHRINK_RATE * delta)
	# Damage anyone outside the safe zone; last soldier alive wins.
	var alive: Array = []
	for s in main.get_tree().get_nodes_in_group("soldier"):
		if not is_instance_valid(s) or bool(s.get("dead")):
			continue
		alive.append(s)
		var d: float = s.global_position.distance_to(main._br_zone_center)
		if d > main._br_zone_radius and s.has_method("take_damage"):
			# Non-authority replicas will refuse — matches CFG for other damage paths.
			if main.multiplayer.multiplayer_peer == null or s.is_multiplayer_authority():
				s.take_damage(main.BR_ZONE_DPS * delta, "", "Zone", -1)
	# Winner: only one soldier alive.
	if alive.size() == 1:
		var lone: Node = alive[0]
		main.scores[int(lone.get("team"))] = int(main.scores.get(int(lone.get("team")), 0)) + 1
		_end_round(int(lone.get("team")))
	elif alive.is_empty():
		_end_round(-1)


func br_zone() -> Dictionary:
	return {"center": main._br_zone_center, "radius": main._br_zone_radius}


func _spawn_point_pickup(pos: Vector2) -> void:
	var a := Area2D.new()
	a.add_to_group("point_pickup")
	a.position = pos
	a.set_meta("spawn_pos", pos)
	var col := CollisionShape2D.new()
	var cs := CircleShape2D.new()
	cs.radius = 12.0
	col.shape = cs
	a.add_child(col)
	# Draw as a small golden diamond so it reads on the terrain.
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([Vector2(0, -10), Vector2(10, 0), Vector2(0, 10), Vector2(-10, 0)])
	poly.color = Color(1.0, 0.85, 0.25)
	a.add_child(poly)
	preload("res://scripts/item_label.gd").attach(a, "+1 POINT", Color(1.0, 0.85, 0.25), 16.0)
	main.add_child(a)


func _tick_pointmatch(delta: float) -> void:
	# PM: pickups grant +1 to the toucher's team, then respawn after 6s.
	var soldiers := main.get_tree().get_nodes_in_group("soldier")
	var live_pickups := main.get_tree().get_nodes_in_group("point_pickup")
	for p in live_pickups:
		if not is_instance_valid(p):
			continue
		for s in soldiers:
			if not is_instance_valid(s) or bool(s.get("dead")):
				continue
			if p.global_position.distance_to(s.global_position) < 22.0:
				var s_team: int = int(s.get("team"))
				main.scores[s_team] = int(main.scores.get(s_team, 0)) + 1
				_objective_event("point", s_team, str(s.get("display_name")))
				var spawn_pos: Vector2 = p.get_meta("spawn_pos")
				_pm_pickups[spawn_pos] = 6.0
				p.queue_free()
				if int(main.scores[s_team]) >= main.PM_SCORE_TO_WIN:
					_end_round(s_team)
					return
				break
	# Respawn pickups after their cooldown.
	for pos in _pm_pickups.keys():
		var t: float = float(_pm_pickups[pos])
		t -= delta
		if t <= 0.0:
			_pm_pickups.erase(pos)
			_spawn_point_pickup(pos)
		else:
			_pm_pickups[pos] = t


func _ctf_score(team: int, capturer: String) -> void:
	main.scores[team] = int(main.scores.get(team, 0)) + 1
	_objective_event("capture", team, capturer)
	if main.scores[team] >= main.CTF_SCORE_TO_WIN:
		_end_round(team)


func _on_kill_scored(killer_name: String, victim_name: String, _weapon_name: String, killer_team: int, victim_team: int) -> void:
	# Objective feed lines (victim_team < 0: FLAG/POINT) were double-scoring
	# (+1 here on top of the mode's own point) and counting as kills in Stats.
	if victim_team < 0:
		return
	if main.round_active:
		_stat_add(victim_name, "d", 1)
		if killer_name != "" and killer_name != victim_name:
			_stat_add(killer_name, "k", 1)
		elif killer_name == victim_name:
			_stat_add(victim_name, "k", -1)   # Soldat: a suicide costs a point
	# Local stats — track the local player's kills / deaths / suicides.
	# Skips scoreboard synthetic entries (FLAG/POINT etc.) which have killer_team but no soldier.
	if is_instance_valid(main.player):
		var me: String = str(main.player.display_name)
		if killer_name == me and victim_name != me:
			Stats.record_kill(_weapon_name)
		if victim_name == me and killer_name == me:
			Stats.record_suicide()
		elif victim_name == me:
			Stats.record_death()
	# (#76) Streak + multi-kill announcer — runs on every peer (banner is local
	# per-viewer) so it must live above the host-only early-return below.
	_track_kill_streaks(killer_name, victim_name, killer_team)
	if Net.is_networked() and not Net.is_host():
		return
	if not main.round_active or killer_team < 0:
		return
	main._bots._maybe_bot_chatter(killer_name, victim_name)
	# Gun Game runs its own ladder BEFORE the generic team/suicide gate.
	# Suicides are still filtered here so a self-kill can't earn a rung-up.
	if Settings.game_mode == Settings.MODE_GG:
		if killer_name == victim_name:
			if Settings.survival:
				_check_survival_end()
			return
		# #91: track per-killer kill count so the GG scoreboard reads live.
		# Advances on every non-suicide kill (rung/grenade/off-rung alike) so
		# players see kill throughput even when the ladder hasn't moved yet.
		main._gg_kills[killer_name] = int(main._gg_kills.get(killer_name, 0)) + 1
		var k_lvl: int = _gg_get(killer_name)
		var weapon_key: String = str(_weapon_name).replace(" (headshot)", "")
		# Ladder advances only on kills with the killer's CURRENT rung weapon.
		# Grenade / off-rung / dropped-weapon kills stay on-kill-feed but grant
		# no progress — otherwise every rung could be skipped with a nade.
		var rung_weapon: String = ""
		if k_lvl >= 0:
			# Golden-knife rung (16) is still a knife kill.
			rung_weapon = str(GG_LADDER_NAMES[mini(k_lvl, GG_LADDER_NAMES.size() - 1)])
		var on_rung: bool = weapon_key == rung_weapon
		# Demote only when the killer is actually on the knife rung.
		var is_knife_kill: bool = weapon_key == "Knife" and k_lvl >= GG_KNIFE_LEVEL
		if on_rung and k_lvl >= GG_GOLD_KNIFE_LEVEL:
			main.winner_note = "%s reached the golden knife" % killer_name
			_end_round(killer_team)
			if Net.is_networked() and Net.is_host():
				main._net._broadcast_match_state()
			return
		# Broadcast the new killer level; every peer applies it to the body
		# they own (host owns bots + host player; each client owns their player).
		if on_rung:
			if Net.is_networked():
				main.bcast("net_gg_set_level", [killer_name, k_lvl + 1], true)
			else:
				_gg_set(killer_name, k_lvl + 1)
		if is_knife_kill:
			if Net.is_networked():
				main.bcast("net_gg_set_level", [victim_name, _gg_get(victim_name) - 1], true)
			else:
				_gg_set(victim_name, _gg_get(victim_name) - 1)
		if Settings.survival:
			_check_survival_end()
		if Net.is_networked() and Net.is_host():
			main._net._broadcast_match_state()
		return
	# Suicide or team-kill: no score change, but still check survival end so
	# the round can end on the last soldier down even from friendly fire.
	if killer_name == victim_name or killer_team == victim_team:
		if Settings.survival:
			_check_survival_end()
		return
	# Rambo mode: only the current bow carrier's kills count.
	if Settings.game_mode == Settings.MODE_RM:
		var carrier_is_killer := false
		for s in main.get_tree().get_nodes_in_group("soldier"):
			if is_instance_valid(s) and str(s.get("display_name")) == killer_name:
				if s.get_instance_id() == main._rambo_carrier_id:
					carrier_is_killer = true
				break
		if not carrier_is_killer:
			return
	# Objective modes score only objectives (Soldat rules). Kills used to add
	# to the same team score, so a CTF team with two kills won on its first
	# capture (the limit is 3).
	var kill_scores: bool = not (Settings.game_mode in [Settings.MODE_CTF, Settings.MODE_INF,
			Settings.MODE_HTF, Settings.MODE_DOM, Settings.MODE_PM])
	if kill_scores:
		main.scores[killer_team] = int(main.scores.get(killer_team, 0)) + 1
	# Advance: bump the local player's kill counter and auto-equip any new tier.
	if Settings.advance and is_instance_valid(main.player) and str(main.player.display_name) == killer_name:
		var unlocked: PackedStringArray = main.player.advance_receive_kill()
		for name in unlocked:
			if main.hud != null and main.hud.has_method("post_chat"):
				main.hud.post_chat("ADVANCE", "Unlocked: %s" % name, false)
	if kill_scores and main.scores[killer_team] >= main.SCORE_TO_WIN:
		_end_round(killer_team)
	elif Settings.survival:
		# Survival: last team standing ends the round early.
		_check_survival_end()
	if Net.is_networked() and Net.is_host():
		main._net._broadcast_match_state()


func _check_survival_end() -> void:
	# Round ends when only one team has any live soldier remaining.
	var alive_teams: Dictionary = {}
	for s in main.get_tree().get_nodes_in_group("soldier"):
		if not is_instance_valid(s) or bool(s.get("dead")):
			continue
		alive_teams[int(s.get("team"))] = true
	if alive_teams.size() <= 1:
		var winner_t := -1
		for k in alive_teams.keys():
			winner_t = int(k)
			break
		_end_round(winner_t)


func _gg_get(display_name: String) -> int:
	return int(main._gg_levels.get(display_name, 0))


func _gg_set(display_name: String, level: int) -> void:
	# Store the clamped level, then push it into whichever live body carries the
	# name. Only the peer that owns the body mutates it — non-authority replicas
	# will pick up the swap through the usual net_state / net_bot_state stream.
	var clamped: int = clampi(level, 0, GG_GOLD_KNIFE_LEVEL)
	main._gg_levels[display_name] = clamped
	for s in main.get_tree().get_nodes_in_group("soldier"):
		if not is_instance_valid(s):
			continue
		if str(s.get("display_name")) != display_name:
			continue
		if not s.has_method("_apply_gg_weapon"):
			continue
		if main.multiplayer.multiplayer_peer != null and not s.is_multiplayer_authority():
			continue
		s.gg_level = clamped
		s._apply_gg_weapon()
		break


func net_gg_set_level(display_name: String, level: int) -> void:
	_gg_set(display_name, level)


func net_gg_state_sync(levels: Dictionary) -> void:
	# Replace the entire cache — used both for a joining peer's initial snapshot
	# (so mid-match spawns read the correct rung locally) and for a round reset
	# so stale entries don't leak into the next round's first spawn wave.
	main._gg_levels = levels.duplicate(true)


func _end_round(team: int) -> void:
	if not main.round_active:
		return  # already over — don't restart the winner countdown / re-save stats
	main.winner_team = team
	main.round_active = false
	main.winner_end_t = WINNER_DISPLAY
	if not Net.is_networked() or Net.is_host():
		main._votes._pick_next_map_choices()
		if not main.next_map_choices.is_empty():
			main.winner_end_t = WINNER_VOTE_DISPLAY
	# Record local W/L for the human player. In FFA modes the winner is the local
	# player's own team id; in team modes it's TEAM_BLUE / TEAM_RED.
	if is_instance_valid(main.player):
		var won: bool = team >= 0 and int(main.player.team) == team
		Stats.record_match_end(won)
	if main.recorder != null:
		main.recorder.save()
		main.recorder.queue_free()   # next round records into a new file
		main.recorder = preload("res://scripts/replay_recorder.gd").new()
		main.recorder.main = main
		main.add_child(main.recorder)
	if main.ranked != null:
		main.ranked.round_end(team)
	if Net.is_networked() and Net.is_host():
		main._net._broadcast_match_state()


func _end_round_by_time() -> void:
	# Fixes #37: on time-out with an empty or tied scoreboard, describe *why*
	# the round ended as a draw instead of just showing "DRAW".
	# Gun Game (#91): use the ladder itself — highest rung wins, kills break ties.
	if Settings.game_mode == Settings.MODE_GG:
		var top_name: String = ""
		var top_lvl: int = -1
		var top_kills: int = -1
		var top_team: int = -1
		for s in main.get_tree().get_nodes_in_group("soldier"):
			if not is_instance_valid(s):
				continue
			var nm: String = str(s.get("display_name"))
			var lvl: int = _gg_get(nm)
			var kills: int = int(main._gg_kills.get(nm, 0))
			if lvl > top_lvl or (lvl == top_lvl and kills > top_kills):
				top_lvl = lvl
				top_kills = kills
				top_name = nm
				top_team = int(s.get("team"))
		if top_name == "":
			main.winner_note = "Time up — no rung climbed"
			_end_round(-1)
		else:
			main.winner_note = "Time up — top rung: %s on rung %d/%d" % [top_name, top_lvl + 1, GG_GOLD_KNIFE_LEVEL]
			_end_round(top_team)
		return
	if main.scores.is_empty():
		main.winner_note = "Time up — no team scored"
		_end_round(-1)
		return
	var top_team := -1
	var top_score := -1
	var tied := false
	for t in main.scores.keys():
		var s := int(main.scores[t])
		if s > top_score:
			top_score = s
			top_team = int(t)
			tied = false
		elif s == top_score:
			tied = true
	if tied:
		var pieces: PackedStringArray = PackedStringArray()
		for t in main.scores.keys():
			pieces.append("%d" % int(main.scores[t]))
		main.winner_note = "Tied at %s — time up" % " – ".join(pieces)
		_end_round(-1)
	else:
		main.winner_note = "Time up — top score %d" % top_score
		_end_round(top_team)


func _reset_round() -> void:
	main.scores.clear()
	main._stuck_time.clear()
	# #263: even the teams between rounds (bots only — never touch a human's
	# chosen side). Snowballed lobbies were the classic complaint.
	if Settings.is_team_mode() and Settings.game_mode != Settings.MODE_INF:
		main._bots._balance_teams()
	# Flags home, nobody carrying — a carrier teleported to spawn used to start
	# the next round holding the enemy flag next to their own base.
	for f in main.flags:
		if is_instance_valid(f):
			f.position = f.get_meta("home")
			f.set_meta("carrier", null)
	_htf_accum.clear()
	_dom_accum.clear()
	main._gg_levels.clear()
	main._gg_kills.clear()
	# Reset control points to neutral so the next round has fresh objectives.
	for a in main._dom_points:
		if not is_instance_valid(a):
			continue
		a.set_meta("owner_team", 0)
		a.set_meta("progress", 0.0)
		a.set_meta("cap_team", 0)
	_reset_br_zone()
	# Wipe stale weapon pickups so a knife lying on the ground from last round
	# doesn't linger into the fresh round. `restore_for_round` already clears
	# per-player `_thrown` sets on host; the physics bodies need parity.
	if not Net.is_networked() or Net.is_host():
		for wp in main.get_tree().get_nodes_in_group("weapon_pickup"):
			if is_instance_valid(wp):
				wp.queue_free()
	main.time_left = main.ROUND_TIME
	main.winner_team = -1
	main.winner_note = ""
	main.winner_end_t = 0.0
	main.round_active = true
	main.next_map_choices = []
	main.my_next_map_vote = -1
	# Survival: nobody respawns during the round, so at reset we wipe surviving
	# bodies and start everyone fresh.
	if Settings.survival:
		if Net.is_networked():
			# Only the host owns spawn authority; clients receive net_spawn_player.
			# Wipe living peer bodies + re-spawn every connected peer.
			if Net.is_host():
				for pid in main._players_by_id.keys():
					var p = main._players_by_id[pid]
					if is_instance_valid(p):
						p.queue_free()
				main._players_by_id.clear()
				# Peer 1 (host, unless dedicated) + every fully-connected peer.
				if not Net.is_dedicated:
					main._net._spawn_networked_player(1)
				for pid in main._connected_peers.keys():
					main._net._spawn_networked_player(int(pid))
				# #92: surviving bots kept last round's HP/ammo/pos while players
				# started fresh — wipe them too and re-spawn via net_spawn_bot so
				# clients mirror the reset.
				for bid in main._bots_by_id.keys():
					var b = main._bots_by_id[bid]
					if is_instance_valid(b):
						main.bcast("net_bot_despawn", [bid], false)
						b.queue_free()
				main._bots_by_id.clear()
				main.call_deferred("_spawn_bots")
		else:
			for s in main.get_tree().get_nodes_in_group("soldier"):
				if is_instance_valid(s):
					s.queue_free()
			main._bots_by_id.clear()
			main.call_deferred("_spawn_player")
			main.call_deferred("_spawn_bots")
	else:
		# Non-survival (#58): the round ended but soldiers keep running around
		# with mid-fight HP/ammo/pos. Give every LIVING soldier a clean slate —
		# full HP, refilled ammo, teleport to a spawn slot. Dead-and-respawning
		# soldiers keep their own scheduled timer (no double-spawn) and come back
		# fresh the normal way.
		if Net.is_networked():
			if Net.is_host():
				main.bcast("net_round_reset", [], false)
				_restore_living_soldiers_local()
		else:
			_restore_living_soldiers_local()
	if Net.is_networked() and Net.is_host():
		main._net._broadcast_match_state()


func _restore_living_soldiers_local() -> void:
	# Each peer restores only bodies it has authority over (host owns its own
	# player + bots; clients own their own player). Non-authority replicas will
	# receive the fresh state via the usual net_state / net_bot_state broadcasts.
	for s in main.get_tree().get_nodes_in_group("soldier"):
		if not is_instance_valid(s) or bool(s.get("dead")):
			continue
		if main.multiplayer.multiplayer_peer != null and not s.is_multiplayer_authority():
			# A client's own body jumps to its spawn at full health next: let it.
			if s.has_method("trust_amnesty"):
				s.trust_amnesty()
			continue
		if not s.has_method("restore_for_round"):
			continue
		s.position = main._safe_spawn_near(_round_spawn_pos_for_team(int(s.get("team"))), int(s.get("team")))
		s.restore_for_round()


func _round_spawn_pos_for_team(t: int) -> Vector2:
	# Mirrors _spawn_networked_player's slot picker: team modes use the shared
	# player_spawn; FFA picks a random bot_spawns entry so respawning peers land
	# in the action instead of a corner. Small jitter avoids stacking on top.
	var base: Vector2 = main._map["player_spawn"]
	if Settings.is_team_mode():
		base = main._team_spawn_pick(t)
	if not Settings.is_team_mode():
		var bs: Array = main._map.get("bot_spawns", [])
		if not bs.is_empty():
			base = main._pick_spawn_away(bs, t)
	return _jitter_spawn(base)


func _jitter_spawn(base: Vector2) -> Vector2:
	# Small random sideways offset so respawns don't stack — but only onto open
	# air with real ground below (a blind ±140 px shift used to drop players
	# inside walls or over pits on the tighter ported maps).
	var safe_base := main._find_free_spot_near(base)
	for _i in 6:
		var c := safe_base + Vector2(randf_range(-140.0, 140.0), 0.0)
		if c.x < 60.0 or c.x > main.MAP_W - 60.0 or not main._spot_is_clear(c):
			continue
		var gy := main._geom_ground_y(c.x, c.y - 2.0)
		if gy == INF or gy > minf(main.KILL_Y, main.GROUND_Y + 1.0) or gy - c.y > 600.0:
			continue
		return c
	return safe_base


func net_round_reset() -> void:
	# Host-triggered non-survival round reset (#58). Runs on every client so
	# each peer restores the state of the soldier it owns.
	# Gun Game: also drop the client's cached rungs so a stale entry from the
	# previous round can't seed a fresh net_spawn_player / net_spawn_bot with
	# the wrong weapon before the next net_gg_set_level fires.
	main._gg_levels.clear()
	_restore_living_soldiers_local()


# ── Kill streaks + multi-kills (#76) ──────────────────
# Reads killer/victim from the shared kill signal. Runs on every peer so the
# banner lookup is identical everywhere without an extra RPC. Synthetic entries
# (FLAG capture, POINT capture, etc.) carry a killer_team but the "victim" is
# a scoreboard label, not a soldier — those still increment the killer's streak
# so a flag-capture-during-spree escalates the announcement naturally.
func _track_kill_streaks(killer_name: String, victim_name: String, killer_team: int) -> void:
	if killer_name == "":
		return
	# Suicide or team-kill: reset the killer's own streak. No banner.
	var is_self: bool = killer_name == victim_name
	if is_self:
		_reset_streak(killer_name)
		return
	# Before incrementing, capture the victim's pre-death streak for the
	# "ended <name>'s N-kill streak" announcement.
	var ended: int = 0
	if _streaks.has(victim_name):
		ended = int((_streaks[victim_name] as Dictionary).get("streak", 0))
	# Increment killer's own counters.
	var now := Time.get_ticks_msec() / 1000.0
	var s: Dictionary = _streaks.get(killer_name, {"streak": 0, "multi": 0, "multi_t": 0.0, "team": killer_team})
	s["team"] = killer_team
	s["streak"] = int(s.get("streak", 0)) + 1
	if float(s.get("multi_t", 0.0)) > now:
		s["multi"] = int(s.get("multi", 0)) + 1
	else:
		s["multi"] = 1
	s["multi_t"] = now + MULTI_KILL_WINDOW
	_streaks[killer_name] = s
	# Announce banner: whichever count is louder (streak or multi).
	var count: int = maxi(int(s["streak"]), int(s["multi"]))
	# Banner only for the local player's streaks (or big ones) — bot-vs-bot
	# FFA would otherwise spam it constantly.
	var is_me: bool = is_instance_valid(main.player) and str(main.player.display_name) == killer_name
	if count >= (2 if is_me else 5) and main.hud != null and main.hud.has_method("show_streak_banner"):
		main.hud.show_streak_banner(killer_name, _streak_title(count), int(s["team"]), count)
	# Streak-ended feed line — reuse the existing kill-feed styling for consistency.
	if ended >= STREAK_ANNOUNCE_END_MIN and main.hud != null and main.hud.has_method("post_streak_ended"):
		main.hud.post_streak_ended(killer_name, victim_name, ended, killer_team)
	# Victim loses their life-scoped streak. Multi window also clears — they're dead.
	_reset_streak(victim_name)


func _reset_streak(name: String) -> void:
	if name == "":
		return
	if not _streaks.has(name):
		return
	var s: Dictionary = _streaks[name]
	s["streak"] = 0
	s["multi"] = 0
	s["multi_t"] = 0.0
	_streaks[name] = s


func _streak_title(count: int) -> String:
	if STREAK_TITLES.has(count):
		return String(STREAK_TITLES[count])
	if count >= 7:
		return STREAK_ULTRA
	return "Multi Kill"


# ── Objective events (grab / drop / return / capture / dom / point) ───────
# Host-side game logic calls _objective_event; every peer gets the banner,
# feed line and sound via net_objective_event (they used to be host-only
# kill-feed hacks that also double-scored).
func _objective_event(kind: String, team: int, who: String) -> void:
	if Net.is_networked():
		if Net.is_host() and main.multiplayer.has_multiplayer_peer():
			main.bcast("net_objective_event", [kind, team, who], true)
	else:
		main.net_objective_event(kind, team, who)


func _stat_add(who: String, key: String, n: int) -> void:
	if who == "":
		return
	if not main.player_stats.has(who):
		main.player_stats[who] = {"k": 0, "d": 0, "c": 0}
	main.player_stats[who][key] = int(main.player_stats[who][key]) + n
