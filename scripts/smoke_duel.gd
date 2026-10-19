extends Node
## Release-gate helper (#266, tools/hosthits_test.gd): a scripted one-on-one
## between two joined smoke clients on the same server.
##   --smoke-role=victim   stays near a spot in the open, strafing and hopping
##   --smoke-role=shooter  aims (with lead) at the other human and fires its AK
##   --smoke-target=TAG    shoot only humans whose name has TAG (their --clan)
##   --smoke-start-ms=N    hold fire until the target has been in view N ms
##                         (default 4200: past a fresh victim's spawn protection)
##   --smoke-burst         fire two rounds, then pause 2.5 s (and repeat)
##   --smoke-cheat=KIND    plays a modified client:
##       rate (3x fire rate), dmg (10x damage in its own copy), ammo (never
##       reloads), origin (spawns its rounds next to the target), silentaim
##       (shoots at the target while streaming an aim the other way), fuel
##       (never runs dry), partial / godmode (as the victim: takes half of /
##       none of what the host says hit it).
## Placement: both bodies are moved next to the map's first bot spawn right
## after spawning (inside the host's spawn grace), on the ground, in the open.
## At the end Net prints `report()` (SMOKE-DUEL ...).

const Bullet = preload("res://scripts/bullet.gd")
const AK := 2

var role := ""
var cheat := ""
var target_tag := ""
var start_after_ms := 4200   # the victim's spawn protection is 3 s
var burst := false
var _burst_n := 0
var _burst_wait := 0.0
var _placed_id := 0
var _spawn_ms := 0
var _target_seen: Dictionary = {}   # instance id -> first ms seen alive
var _held: Array = []
var _t := 0.0
var _side := 1.0
var _cheat_t := 0.0
var deaths := 0
var shots := 0
var lives := 0


var _stop_ms := 0   # hold fire for the last 1.5 s: in-flight shots die with the client


func _ready() -> void:
	_stop_ms = Time.get_ticks_msec() + int((Net._smoke_secs(6.0) - 1.5) * 1000.0)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-role="):
			role = a.substr(13)
		elif a.begins_with("--smoke-cheat="):
			cheat = a.substr(14)
		elif a.begins_with("--smoke-target="):
			target_tag = a.substr(15).to_upper()
		elif a.begins_with("--smoke-start-ms="):
			start_after_ms = int(a.substr(17))
		elif a == "--smoke-burst":
			burst = true
	print("SMOKE-DUEL start role=%s cheat=%s" % [role, cheat])


func report() -> void:
	var hh: Dictionary = HostHits.stats
	print("SMOKE-DUEL role=%s cheat=%s predicted_hits=%d predicted_damage=%.1f hits_taken=%d damage_taken=%.1f shots=%d lives=%d" % [
		role, cheat, Bullet.predicted_hits, Bullet.predicted_damage, int(hh.get("hits_taken", 0.0)),
		float(hh.get("damage_taken", 0.0)), shots, lives])


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
	var m := get_tree().current_scene
	var p = m.get("player") if m != null else null
	if p == null or not is_instance_valid(p) or bool(p.get("dead")):
		_release_all()
		return
	if p.get_instance_id() != _placed_id:
		_placed_id = p.get_instance_id()
		_spawn_ms = Time.get_ticks_msec()
		lives += 1
		_place(m, p)
		if cheat in ["partial", "godmode"]:
			p.test_cheat = cheat
		if p.weapon_index != AK and not p.using_secondary:
			p._switch_weapon(AK)
		match cheat:
			"rate":
				p.weapons[AK]["rate"] = 0.11 / 3.0
			"dmg":
				p.weapons[AK]["damage"] = 220.0
			"ammo":
				p.weapons[AK]["mag"] = 999
				p.ammo[AK] = 999
	_t += delta
	if cheat == "fuel":
		_fuel(p)
	elif role == "victim":
		_victim(p)
	elif role == "shooter":
		_shooter(m, p, delta)


## Feet on the ground near `x` (raycast down), or INF.
func _ground(p: Node2D, x: float, y: float) -> Vector2:
	var q := PhysicsRayQueryParameters2D.create(Vector2(x, y - 300.0), Vector2(x, y + 600.0), 1 | 4)
	var hit := p.get_world_2d().direct_space_state.intersect_ray(q)
	return (hit["position"] as Vector2) + Vector2(0, -1) if not hit.is_empty() else Vector2.INF


func _place(m: Node, p: Node2D) -> void:
	var mp: Dictionary = m.get("_map") if m.get("_map") != null else {}
	var spots: Array = mp.get("bot_spawns", [])
	for s in spots:
		var base: Vector2 = s
		var v := _ground(p, base.x + 40.0, base.y)
		var sh := _ground(p, base.x - 150.0, base.y)
		if v == Vector2.INF or sh == Vector2.INF or absf(v.y - sh.y) > 40.0:
			continue
		var q := PhysicsRayQueryParameters2D.create(v + Vector2(0, -14), sh + Vector2(0, -14), 1 | 2)
		if not p.get_world_2d().direct_space_state.intersect_ray(q).is_empty():
			continue
		p.global_position = v if role == "victim" or cheat in ["partial", "godmode"] else sh
		p.velocity = Vector2.ZERO
		set_meta("anchor", p.global_position)
		print("SMOKE-DUEL placed role=%s at=(%.0f,%.0f)" % [role, p.global_position.x, p.global_position.y])
		return
	print("SMOKE-DUEL no open spot found")


func _victim(p: Node2D) -> void:
	# Strafe around the spot, a hop now and then.
	var anchor: Vector2 = get_meta("anchor", p.global_position)
	if fmod(_t, 0.7) < 0.02:
		_side = -_side
	if p.global_position.x > anchor.x + 70.0:
		_side = -1.0
	elif p.global_position.x < anchor.x - 70.0:
		_side = 1.0
	_release("move_left" if _side > 0.0 else "move_right")
	_press("move_right" if _side > 0.0 else "move_left")
	if fmod(_t, 1.6) < 0.25:
		_press("jump")
	else:
		_release("jump")


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


func _shooter(m: Node, p: Node2D, delta: float) -> void:
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
	var chest := tgt.global_position + Vector2(0, -12)
	var from := p.global_position + Vector2(0, -9)
	var spd: float = float(p.weapons[AK]["speed"])
	var lead := chest + (tgt.get("velocity") as Vector2) * (from.distance_to(chest) / spd)
	var dir := (lead - from).normalized()
	var ready := now - int(_target_seen[tid]) >= start_after_ms and now - _spawn_ms >= 1500 and now < _stop_ms \
			and (from.distance_to(chest) < 600.0 or cheat in ["rate", "ammo"])
	if cheat == "silentaim":
		_aim(p, -dir)   # the aim it streams points away
	else:
		_aim(p, dir)
	if not ready:
		_release("fire")
		return
	match cheat:
		"origin":
			_release("fire")
			_cheat_t -= delta
			if _cheat_t <= 0.0:
				_cheat_t = 0.15
				_raw_shot(p, chest - dir * 14.0, dir)
		"silentaim":
			_release("fire")
			_cheat_t -= delta
			if _cheat_t <= 0.0:
				_cheat_t = 0.2
				_raw_shot(p, from + dir * 22.0, dir)
		_:
			if burst:
				_burst_wait -= delta
				if _burst_wait > 0.0:
					_release("fire")
				elif p.fire_cd <= 0.0 and not _held.has("fire"):
					_press("fire")
					_burst_n += 1
				elif _held.has("fire") and p.fire_cd > 0.0:
					_release("fire")
					if _burst_n >= 2:
						_burst_n = 0
						_burst_wait = 2.5
			else:
				_press("fire")


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
