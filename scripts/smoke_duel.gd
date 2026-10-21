extends Node
## Release-gate helper (#266, tools/hosthits_test.gd): a scripted one-on-one
## between two joined smoke clients on the same server.
##   --smoke-role=victim   moves around a spot in the open (see --smoke-move)
##   --smoke-role=shooter  aims (with lead) at the other human and attacks it
##   --smoke-weapon=W      the shooter's weapon (default ak): ak mp5 aug spas
##                         ruger m79 barrett minimi minigun flame socom knife
##                         chainsaw law, grenade (throws frag grenades), buggy
##                         (drives the nearest buggy and fires its gun)
##   --smoke-move=M        strafe (victim default: back and forth, hopping),
##                         jet (strafes and flies up and down on its jets),
##                         stand (shooter default), drive (the victim drives the
##                         nearest buggy to and fro). A melee shooter always
##                         closes in; a strafe / jet shooter moves like a victim.
##   --smoke-target=TAG    attack only humans whose name has TAG (their --clan)
##   --smoke-start-ms=N    hold fire until the target has been in view N ms
##                         (default 4200: past a fresh victim's spawn protection)
##   --smoke-burst         fire two rounds, then pause 2.5 s (and repeat)
##   --smoke-vote          vote for the first map offered at the end of a round
##   --smoke-done-file=F   (victim) report and leave 1.5 s after file F appears
##                         (the test writes it once every shooter has left)
##   --smoke-cheat=KIND    plays a modified client (AK only):
##       rate (3x fire rate), dmg (10x damage in its own copy), ammo (never
##       reloads), origin (spawns its rounds next to the target), silentaim
##       (shoots at the target while streaming an aim the other way), fuel
##       (never runs dry), partial / godmode (as the victim: takes half of /
##       none of what the host says hit it).
## Placement: both bodies are moved next to the map's first open bot spawn
## right after spawning (inside the host's spawn grace), on the ground.
## At the end Net prints `report()` (SMOKE-DUEL ...).

const Bullet = preload("res://scripts/bullet.gd")
const AK := 2
# name -> [secondary slot?, index]
const WEAPONS := {"deagles": [false, 0], "mp5": [false, 1], "ak": [false, 2], "aug": [false, 3], "spas": [false, 4],
	"ruger": [false, 5], "m79": [false, 6], "barrett": [false, 7], "minimi": [false, 8], "minigun": [false, 9],
	"flame": [false, 10], "socom": [true, 0], "knife": [true, 1], "chainsaw": [true, 2], "law": [true, 3]}

var role := ""
var cheat := ""
var weapon := "ak"
var move := ""
var target_tag := ""
var start_after_ms := 4200   # the victim's spawn protection is 3 s
var burst := false
var vote := false
var _burst_n := 0
var _burst_wait := 0.0
var _placed_id := 0
var _spawn_ms := 0
var _target_seen: Dictionary = {}   # instance id -> first ms seen alive
var _held: Array = []
var _t := 0.0
var _side := 1.0
var _cheat_t := 0.0
var _cook := -1.0
var _cook_want := 0.5
var _voted := false
var _seat_t := 0.0
var _place_until := 0
var _place_tries := 0
var _ready_frames := 0     # frames the shooter wanted to fire
var _blocked_frames := 0   # ...with level geometry between its gun and the target
var _done_file := ""
var _done_check := 0.0
var _done_at := -1.0
var deaths := 0
var shots := 0
var lives := 0
var throws := 0


var _stop_ms := 0   # hold fire for the last 1.5 s: in-flight shots die with the client


func _ready() -> void:
	_stop_ms = Time.get_ticks_msec() + int((Net._smoke_secs(6.0) - 1.5) * 1000.0)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-role="):
			role = a.substr(13)
		elif a.begins_with("--smoke-cheat="):
			cheat = a.substr(14)
		elif a.begins_with("--smoke-weapon="):
			weapon = a.substr(15).to_lower()
		elif a.begins_with("--smoke-move="):
			move = a.substr(13).to_lower()
		elif a.begins_with("--smoke-target="):
			target_tag = a.substr(15).to_upper()
		elif a.begins_with("--smoke-start-ms="):
			start_after_ms = int(a.substr(17))
		elif a == "--smoke-burst":
			burst = true
		elif a == "--smoke-vote":
			vote = true
		elif a.begins_with("--smoke-done-file="):
			_done_file = a.substr(18)
	if move == "":
		move = "strafe" if role == "victim" else "stand"
	if weapon in ["knife", "chainsaw"]:
		move = "chase"
	print("SMOKE-DUEL start role=%s cheat=%s weapon=%s move=%s" % [role, cheat, weapon, move])


func report() -> void:
	var hh: Dictionary = HostHits.stats
	print("SMOKE-DUEL role=%s cheat=%s weapon=%s move=%s predicted_hits=%d predicted_damage=%.1f predicted_other_hits=%d predicted_other_damage=%.1f hits_taken=%d damage_taken=%.1f shots=%d throws=%d lives=%d ready_frames=%d blocked_frames=%d" % [
		role, cheat, weapon, move, Bullet.predicted_hits, Bullet.predicted_damage, Bullet.predicted_other_hits, Bullet.predicted_other_damage,
		int(hh.get("hits_taken", 0.0)), float(hh.get("damage_taken", 0.0)), shots, throws, lives, _ready_frames, _blocked_frames])


func _press(a: String, strength := 1.0) -> void:
	if not InputMap.has_action(a):
		return
	Input.action_press(a, strength)
	if not _held.has(a):
		_held.append(a)


func _release(a: String) -> void:
	if _held.has(a):
		Input.action_release(a)
		_held.erase(a)


func _release_all() -> void:
	for a in _held.duplicate():
		_release(a)


func _physics_process(delta: float) -> void:
	if _done_file != "":
		_done_check -= delta
		if _done_at < 0.0 and _done_check <= 0.0:
			_done_check = 0.25
			if FileAccess.file_exists(_done_file):
				_done_at = 1.5
		if _done_at >= 0.0:
			_done_at -= delta
			if _done_at < 0.0:
				_done_file = ""
				_release_all()
				report()
				Net.leave()
				get_tree().quit()
				return
	var m := get_tree().current_scene
	if vote and not _voted and m != null and m.get("next_map_choices") != null and not (m.next_map_choices as Array).is_empty() \
			and m.has_method("vote_next_map"):
		_voted = true
		m.vote_next_map(0)
		print("SMOKE-DUEL voted next map")
	if m != null and m.get("next_map_choices") != null and (m.next_map_choices as Array).is_empty():
		_voted = false
	var p = m.get("player") if m != null else null
	if p == null or not is_instance_valid(p) or bool(p.get("dead")):
		_release_all()
		_cook = -1.0
		return
	if p.get_instance_id() != _placed_id:
		_placed_id = p.get_instance_id()
		_spawn_ms = Time.get_ticks_msec()
		_target_seen.clear()
		lives += 1
		_cook = -1.0
		_seat_t = 0.0
		_place_until = Time.get_ticks_msec() + 1200
		_place_tries = 0
		if cheat in ["partial", "godmode"]:
			p.test_cheat = cheat
		_equip(p)
		match cheat:
			"rate":
				p.weapons[AK]["rate"] = 0.11 / 3.0
			"dmg":
				p.weapons[AK]["damage"] = 220.0
			"ammo":
				p.weapons[AK]["mag"] = 999
				p.ammo[AK] = 999
	if _place_until > 0:
		# A shooter waits (inside the host's spawn grace) until it sees its
		# target, then takes a spot next to it; a victim takes a map spot.
		if role != "shooter" or cheat in ["partial", "godmode"] or _target(m, p) != null or Time.get_ticks_msec() >= _place_until:
			if _place(m, p):
				_place_until = 0
			else:
				return
		else:
			return
	_t += delta
	if cheat == "fuel":
		_fuel(p)
	elif move == "drive" or weapon == "buggy":
		_drive(m, p, delta)
	elif role == "victim":
		_victim(p)
	elif role == "shooter":
		_shooter(m, p, delta)


## The weapon this run uses, in hand (a pickup / respawn may have changed it).
func _equip(p: Node) -> void:
	if not WEAPONS.has(weapon):
		if p.weapon_index != AK and not p.using_secondary:
			p._switch_weapon(AK)
		return
	var w: Array = WEAPONS[weapon]
	var idx: int = int(w[1])
	if bool(w[0]):
		if p.secondary_index != idx:
			p.secondary_index = idx
			p.secondary_ammo[idx] = int(p.secondary[idx]["mag"])
		if not p.using_secondary:
			p._toggle_secondary()
	elif p.using_secondary or p.weapon_index != idx:
		p._switch_weapon(idx)


func _wdict(p: Node) -> Dictionary:
	return p._active_weapon()


## Feet on the ground near `x` (raycast down), or INF.
func _ground(p: Node2D, x: float, y: float) -> Vector2:
	var hit := _solid(p, Vector2(x, y - 300.0), Vector2(x, y + 600.0), 1 | 4)
	return (hit["position"] as Vector2) + Vector2(0, -1) if not hit.is_empty() else Vector2.INF


## First hit of the level itself (pickups, bonus boxes and dropped weapons
## lie in different places from run to run: they don't count).
func _solid(p: Node2D, a: Vector2, b: Vector2, mask: int) -> Dictionary:
	var space := p.get_world_2d().direct_space_state
	var ex: Array[RID] = []
	for _i in 6:
		var q := PhysicsRayQueryParameters2D.create(a, b, mask, ex)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or hit.get("collider") is StaticBody2D:
			return hit
		ex.append(hit["rid"])
	return {}


## Returns false to try again next frame: right after a map change the
## level's collision may not be in the physics space yet (every probe misses).
func _place(m: Node, p: Node2D) -> bool:
	var mp: Dictionary = m.get("_map") if m.get("_map") != null else {}
	var spots: Array = mp.get("bot_spawns", [])
	# (--smoke-gap: both roles must pass the same one, they pick the spot
	# independently. Wider gaps also want flat ground and open sky between.)
	# --smoke-near-vehicle: around the buggy spawns instead, the victim at
	# +off_v and the shooter at +off_s px (--smoke-offsets=V,S).
	var gap := 190.0
	var offs := Vector2(INF, INF)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-gap="):
			gap = float(a.substr(12))
		elif a.begins_with("--smoke-offsets="):
			var parts := a.substr(16).split(",")
			if parts.size() == 2:
				offs = Vector2(float(parts[0]), float(parts[1]))
		elif a == "--smoke-near-vehicle":
			spots = mp.get("vehicle_spawns", spots)
	if offs.x == INF:
		offs = Vector2(40.0, 40.0 - gap)
	# The map's first open spot (both roles find the same one).
	var spot_v := Vector2.INF
	var spot_s := Vector2.INF
	for s in spots:
		var base: Vector2 = s if s is Vector2 else Vector2(float(s[0]), float(s[1]))
		var v := _ground(p, base.x + offs.x, base.y)
		var sh := _ground(p, base.x + offs.y, base.y)
		if v == Vector2.INF or sh == Vector2.INF or absf(v.y - sh.y) > 40.0:
			continue
		if not _los(p, v, sh):
			continue
		if gap > 190.0 and not _open_between(p, v, sh):
			continue
		spot_v = v
		spot_s = sh
		break
	if spot_v == Vector2.INF and _place_tries < 30 and _ground(p, p.global_position.x, p.global_position.y) == Vector2.INF:
		_place_tries += 1
		return false
	if role == "victim" or cheat in ["partial", "godmode"]:
		if spot_v != Vector2.INF:
			_put(p, spot_v)
		else:
			# No spot on this map: stay at the spawn (the shooter comes over).
			_put(p, p.global_position)
			print("SMOKE-DUEL no open spot found (%d spots, ground here %s, tries %d)" % [spots.size(), str(_ground(p, p.global_position.x, p.global_position.y) != Vector2.INF), _place_tries])
		return true
	# A shooter takes the spot if its target is there, else goes next to the
	# target wherever it is (any map).
	var tgt := _target(m, p)
	if spot_s != Vector2.INF and (tgt == null or tgt.global_position.distance_to(spot_v) < 260.0):
		_put(p, spot_s)
		return true
	if tgt != null:
		var tg := _ground(p, tgt.global_position.x, tgt.global_position.y)
		var side := signf(offs.y - offs.x) if offs.y != offs.x else -1.0
		var want := absf(offs.y - offs.x)
		# The run's distance first, then nearer ones, either side.
		var tries: Array = []
		for f in [1.0, 0.75, 0.55, 0.4]:
			tries.append(side * want * f)
			tries.append(-side * want * f)
		for d in tries:
			if tg == Vector2.INF:
				break
			var sh2 := _ground(p, tg.x + float(d), tg.y)
			if sh2 == Vector2.INF or absf(sh2.y - tg.y) > 40.0:
				continue
			if not _los(p, tg, sh2):
				continue
			if absf(float(d)) > 190.0 and not _open_between(p, tg, sh2):
				continue
			_put(p, sh2)
			return true
		# Nowhere open near it: stand right by it.
		if tg != Vector2.INF:
			_put(p, tg + Vector2(-side * 40.0, 0.0))
			print("SMOKE-DUEL placed by the target (no open spot near it)")
			return true
	_put(p, p.global_position)
	print("SMOKE-DUEL no open spot found")
	return true


## Clear shots between two soldiers standing at feet `a` and `b`: at chest
## and at muzzle height (a low lip between them stops rounds fired at the
## chest even when a ray at mid-body passes over it).
func _los(p: Node2D, a: Vector2, b: Vector2) -> bool:
	for h in [-9.0, -12.0, -24.0]:
		if not _solid(p, a + Vector2(0, h), b + Vector2(0, h), 1 | 2).is_empty():
			return false
	return true


func _put(p: Node2D, at: Vector2) -> void:
	p.global_position = at
	p.velocity = Vector2.ZERO
	set_meta("anchor", at)
	print("SMOKE-DUEL placed role=%s at=(%.0f,%.0f)" % [role, at.x, at.y])


## Flat ground (+-30 px) and 90 px of open air above it all the way between
## (full-power frags / LAW rockets fly low and flat over these distances).
func _open_between(p: Node2D, a: Vector2, b: Vector2) -> bool:
	var x := minf(a.x, b.x) - 60.0
	while x <= maxf(a.x, b.x) + 60.0:
		var gy := _ground(p, x, a.y)
		if gy == Vector2.INF or absf(gy.y - a.y) > 30.0:
			return false
		if not _solid(p, gy + Vector2(0, -4), gy + Vector2(0, -90), 1 | 2).is_empty():
			return false
		x += 30.0
	return true


## Back and forth around the anchor, a hop now and then (jet: long climbs on
## the jets and drops). Shared by victims and moving shooters.
func _wander(p: Node2D, reach := 70.0) -> void:
	var anchor: Vector2 = get_meta("anchor", p.global_position)
	if fmod(_t, 0.7) < 0.02:
		_side = -_side
	if p.global_position.x > anchor.x + reach:
		_side = -1.0
	elif p.global_position.x < anchor.x - reach:
		_side = 1.0
	_release("move_left" if _side > 0.0 else "move_right")
	_press("move_right" if _side > 0.0 else "move_left")
	if move == "jet":
		# Up to ~200 px above the spot and back down, refuelling on the ground.
		var high: float = anchor.y - p.global_position.y
		var phase := fmod(_t, 3.2)
		if phase < 1.4 and high < 200.0 and float(p.get("fuel")) > 8.0:
			_press("jet")
			if p.is_on_floor():
				_press("jump")
			else:
				_release("jump")
		else:
			_release("jet")
			_release("jump")
	elif fmod(_t, 1.6) < 0.25:
		_press("jump")
	else:
		_release("jump")


func _victim(p: Node2D) -> void:
	_wander(p)


func _target(m: Node, p: Node2D) -> Node2D:
	var best: Node2D = null
	var bd := INF
	for s in get_tree().get_nodes_in_group("soldier"):
		if s == p or not is_instance_valid(s) or bool(s.get("dead")) or s.get("loadout") != null:
			continue   # (bots have `loadout`)
		if target_tag != "" and not str(s.get("display_name")).contains("«%s»" % target_tag):
			continue
		var d: float = (s as Node2D).global_position.distance_to(p.global_position)
		if d < bd:
			bd = d
			best = s
	return best


func _aim(p: Node2D, dir: Vector2) -> void:
	for pair in [["aim_right", maxf(0.0, dir.x)], ["aim_left", maxf(0.0, -dir.x)], ["aim_down", maxf(0.0, dir.y)], ["aim_up", maxf(0.0, -dir.y)]]:
		if float(pair[1]) > 0.001:
			_press(pair[0], float(pair[1]))
		else:
			_release(pair[0])


## Launch direction (unit) for a lob at `speed` under `grav` from `from` to
## `to` (the flatter of the two arcs, or the steeper one with `high`), or
## Vector2.ZERO if out of reach.
static func _lob(from: Vector2, to: Vector2, speed: float, grav: float, high := false) -> Vector2:
	var dx := to.x - from.x
	var dy := from.y - to.y   # up is positive
	var v2 := speed * speed
	var disc := v2 * v2 - grav * (grav * dx * dx + 2.0 * dy * v2)
	if disc < 0.0 or absf(dx) < 1.0:
		return Vector2.ZERO
	var th := atan((v2 + sqrt(disc) if high else v2 - sqrt(disc)) / (grav * absf(dx)))
	return Vector2(cos(th) * signf(dx), -sin(th))


func _shooter(m: Node, p: Node2D, delta: float) -> void:
	_equip(p)
	var tgt := _target(m, p)
	if tgt == null:
		if cheat in ["rate", "ammo"] and Time.get_ticks_msec() - _spawn_ms >= 1500 and Time.get_ticks_msec() < _stop_ms:
			_aim(p, Vector2.RIGHT)   # (these cheats need no target)
			_press("fire")
		else:
			_release_all()
		return
	var now := Time.get_ticks_msec()
	var tid := tgt.get_instance_id()
	if not _target_seen.has(tid):
		_target_seen[tid] = now
	var w := _wdict(p)
	var kind := str(w.get("kind", "bullet"))
	# (Rockets go for the ground at the feet: the blast gets a hopping target.)
	var chest := tgt.global_position + Vector2(0, -2 if weapon == "law" else -12)
	var from := p.global_position + Vector2(0, -9)
	var tvel: Vector2 = tgt.get("velocity")
	var dir: Vector2
	if weapon == "grenade":
		dir = _grenade_aim(from, tgt.global_position + Vector2(0, -6), tvel)
	elif kind == "launcher":
		var spd_l: float = float(w["speed"])
		var t_l := from.distance_to(chest) / maxf(1.0, spd_l)
		dir = _lob(from, tgt.global_position + Vector2(0, -4) + tvel * t_l, spd_l, float(w.get("gravity", 980.0)))
		if dir == Vector2.ZERO:
			dir = (chest - from).normalized()
	else:
		var spd: float = maxf(1.0, float(w.get("speed", 1000.0)))
		var lead := chest + (tvel * (from.distance_to(chest) / spd) if spd > 1.0 else Vector2.ZERO)
		dir = (lead - from).normalized()
	var reach := 600.0
	if move == "chase":
		reach = float(w.get("range", 32.0)) - 4.0
		_chase(p, tgt)
	elif move in ["strafe", "jet"]:
		_wander(p)
	elif cheat == "":
		# Standing: walk back to the spot if a blast (or the LAW's kick) moved us.
		var home: Vector2 = get_meta("anchor", p.global_position)
		var off_x := home.x - p.global_position.x
		if absf(off_x) > 12.0:
			_release("move_left" if off_x > 0.0 else "move_right")
			_press("move_right" if off_x > 0.0 else "move_left")
		else:
			_release("move_left")
			_release("move_right")
	var ready := now - int(_target_seen[tid]) >= start_after_ms and now - _spawn_ms >= 1500 and now < _stop_ms \
			and (from.distance_to(chest) < reach or cheat in ["rate", "ammo"])
	if move == "chase":
		ready = ready and (tgt.global_position - p.global_position).length() < reach
	# (A player fires once the gun points where it wants: right after a spawn
	# the aim is still swinging round. Cheaters fire regardless.)
	if cheat == "" and weapon != "grenade" and absf((p.aim_dir as Vector2).angle_to(dir)) > 0.6:
		ready = false
	if ready:
		_ready_frames += 1
		if not _solid(p, from, chest, 1).is_empty():
			_blocked_frames += 1
	if cheat == "silentaim":
		_aim(p, -dir)   # the aim it streams points away
	else:
		_aim(p, dir)
	if weapon == "grenade":
		_throw(p, ready, delta)
		return
	if not ready:
		_release("fire")
		return
	match cheat:
		"origin":
			_release("fire")
			_cheat_t -= delta
			# (Only at a target well beyond any muzzle: a round spawned right
			# at a soldier standing next to you is within the host's tolerance.)
			if _cheat_t <= 0.0 and from.distance_to(chest) > 160.0:
				_cheat_t = 0.15
				_raw_shot(p, chest - dir * 14.0, dir)
		"silentaim":
			_release("fire")
			_cheat_t -= delta
			if _cheat_t <= 0.0:
				_cheat_t = 0.2
				_raw_shot(p, from + dir * 22.0, dir)
		_:
			if burst or not bool(w.get("auto", false)):
				# One click per round (semi-automatics need a fresh press): press
				# for one frame, release for at least one.
				_burst_wait -= delta
				if _held.has("fire") or _burst_wait > 0.0:
					_release("fire")
				elif p.fire_cd <= 0.0 and not bool(p.get("reloading")):
					_press("fire")
					_burst_n += 1
					if burst and _burst_n >= 2:
						_burst_n = 0
						_burst_wait = 2.5
			else:
				_press("fire")


## Melee: run at the target (jets when it is above), stop at arm's length.
func _chase(p: Node2D, tgt: Node2D) -> void:
	var dx := tgt.global_position.x - p.global_position.x
	if absf(dx) > 14.0:
		_release("move_left" if dx > 0.0 else "move_right")
		_press("move_right" if dx > 0.0 else "move_left")
	else:
		_release("move_left")
		_release("move_right")
	if tgt.global_position.y < p.global_position.y - 30.0 and float(p.get("fuel")) > 5.0:
		_press("jet")
		if p.is_on_floor():
			_press("jump")
	else:
		_release("jet")
		_release("jump")


## Aim for a frag (player._throw_grenade): toss = normalized(aim + (0, -0.55))
## at 300..650 px/s by wind-up (full at 0.9 s). A full throw on the flat arc,
## cooked so it goes off about when it lands (fuse 2.2 s from the pin).
func _grenade_aim(from: Vector2, to: Vector2, tvel: Vector2) -> Vector2:
	var g: float = float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))
	var spd := 650.0
	var toss := _lob(from, to, spd, g, true)
	if toss == Vector2.ZERO:
		_cook_want = 0.9
		return (to - from).normalized()
	var t_f := absf(to.x - from.x) / maxf(1.0, spd * absf(toss.x))
	toss = _lob(from, to + tvel * minf(t_f, 0.5), spd, g, true)
	if toss == Vector2.ZERO:
		toss = _lob(from, to, spd, g, true)
	_cook_want = clampf(2.2 - t_f - 0.15, 0.9, 1.9)
	# aim + (0, -0.55) = s * toss with |aim| = 1.
	var b := 0.55 * toss.y
	var s := -b + sqrt(maxf(0.0, b * b + 0.6975))
	return (toss * s + Vector2(0, 0.55)).normalized()


func _throw(p: Node, ready: bool, delta: float) -> void:
	if _cook >= 0.0:
		_cook += delta
		if _cook >= _cook_want:
			_release("grenade")
			_cook = -1.0
			throws += 1
		return
	if ready and int(p.get("grenades")) > 0 and float(p.get("grenade_cd")) <= 0.0:
		_press("grenade")
		_cook = 0.0
	else:
		_release("grenade")


## Buggy: get to the nearest one (inside the spawn grace), take the seat the
## host hands out, then drive back and forth; a shooter fires the gun at its
## target (a lone driver has the gun).
func _drive(m: Node, p: Node2D, delta: float) -> void:
	var v: Node2D = null
	for c in get_tree().get_nodes_in_group("vehicle"):
		if str(c.get("kind")) == "buggy" and bool(c.get("alive")) and (v == null or (c as Node2D).global_position.distance_to(p.global_position) < v.global_position.distance_to(p.global_position)):
			v = c
	if v == null:
		_release_all()
		return
	var seat: int = int(v.seat_of(p))
	if seat < 0:
		_seat_t -= delta
		if _seat_t <= 0.0:
			_seat_t = 1.0
			if Time.get_ticks_msec() - _spawn_ms < 1500 or p.global_position.distance_to(v.global_position) > 60.0:
				p.global_position = v.global_position + Vector2(-16, -12)
				p.velocity = Vector2.ZERO
			v.request_enter(p)
			print("SMOKE-DUEL seat request %s at=(%.0f,%.0f) dist=%.0f" % [str(v.name), v.global_position.x, v.global_position.y, p.global_position.distance_to(v.global_position)])
		return
	if not has_meta("drive_anchor") or int(get_meta("drive_life", -1)) != lives:
		set_meta("drive_anchor", v.global_position)
		set_meta("drive_life", lives)
	var anchor: Vector2 = get_meta("drive_anchor")
	if fmod(_t, 1.8) < 0.02:
		_side = -_side
	if v.global_position.x > anchor.x + 160.0:
		_side = -1.0
	elif v.global_position.x < anchor.x - 160.0:
		_side = 1.0
	_release("move_left" if _side > 0.0 else "move_right")
	_press("move_right" if _side > 0.0 else "move_left")
	if role != "shooter":
		return
	var tgt := _target(m, p)
	if tgt == null:
		_release("fire")
		return
	var now := Time.get_ticks_msec()
	var tid := tgt.get_instance_id()
	if not _target_seen.has(tid):
		_target_seen[tid] = now
	var pivot: Vector2 = v._gun_pivot()
	var chest := tgt.global_position + Vector2(0, -12)
	var lead := chest + (tgt.get("velocity") as Vector2) * (pivot.distance_to(chest) / float(v.get("GUN_SPEED")))
	_aim(p, (lead - pivot).normalized())
	if now - int(_target_seen[tid]) >= start_after_ms and now < _stop_ms and pivot.distance_to(chest) < 600.0:
		_press("fire")
	else:
		_release("fire")


## A net_shoot the game would never send (origin / silent aim cheats).
func _raw_shot(p: Node, at: Vector2, dir: Vector2) -> void:
	shots += 1
	var pid: int = int(p._next_proj_id)
	p._next_proj_id = pid + 1
	p.rpc_id(1, "net_shoot", at, PackedVector2Array([dir]), AK, pid, HostHits.view_now(), HostHits.game_ms())


func _fuel(p: Node2D) -> void:
	# Hover on a full tank forever: jump, then hold the jets.
	p.fuel = 100.0
	if p.is_on_floor():
		_press("jump")
	else:
		_release("jump")
	_press("jet")
