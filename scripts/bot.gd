extends CharacterBody2D
## Bot — AI soldier: leads its aim, circle-strafes, dodge-jumps, lobs grenades, jet-boots up.

signal died

@export var color := Color(0.85, 0.3, 0.25)
# Dedicated non-peer team id: keeps bots hostile to any human peer including host (peer_id 1).
var team := 99
var display_name := "Bot"
var loadout := "AK-74"  # or "LAW" — set by Main._spawn_bot before add_child
# Stable id assigned by the host in MP so per-bot state RPCs can address this body.
# 0 in SP / on non-networked spawns — no broadcast needed there.
var bot_id: int = 0
# Random cosmetic outfit — set in _ready so bots read as distinct characters.
var cosmetics: Dictionary = {}

var last_killer := ""
var last_weapon := ""
var last_killer_team := -1

var health := 100.0
var fuel := 100.0
var facing := 1.0
var jet_on := false
var was_jet := false
var dead := false
var fire_cd := 0.5
var jump_cd := 0.0
var muzzle_t := 0.0
var target: Node2D = null
var _target_refresh_cd := 0.0
var _stuck_t := 0.0

# Ammo state (#36) — bots run dry and reload like players.
# `_mag_size` + `_reload_time` are stat lookups per loadout.
var ammo: int = 30
var reloading: bool = false
var reload_t: float = 0.0
const AMMO_STATS := {
	"AK-74": {"mag": 30, "reload": 2.0},
	"LAW":   {"mag": 1,  "reload": 3.0},
}

# grenades
var grenades := 3
var grenade_cd := 0.0

# Bink (aim penalty when hit — same model as player.gd).
var bink_t := 0.0
# Ceasefire (spawn protection) — invulnerable for the first few seconds after spawn.
var ceasefire_t := 3.0

# strafe / dodge
var strafe_dir := 1.0
var strafe_t := 0.0
var dodge_cd := 0.0
# Idle wander — targetless bots pick a random direction and re-flip periodically
# so they don't pile up against the map edge (issue #43).
var wander_dir := 1.0
var wander_t := 0.0
var _hop_cd := 0.0

const BASE_GRAVITY := 1700.0
# Bots used to run at 230, well under the player's 280 — they could never close.
# 320 slightly beats a player sprint, so a bot can catch a fleeing target.
const RUN_SPEED := 320.0
const JUMP_VEL := -430.0
const JET_THRUST := -2200.0
const MAX_FALL := 1300.0
# Match the actual weapon speeds so bullets read the same coming from bots as
# from players: AK-74 = 1050, LAW rocket = 720.
const BULLET_SPEED := 1050.0
const ENGAGE_RANGE := 720.0
const ROCKET_SPEED := 720.0
const ROCKET_MIN_RANGE := 180.0  # LAW splashes 130px — don't rocket own feet
const HOP_COOLDOWN := 1.2  # min gap between wander bunny-hops so bots don't hop-spam
const WANDER_FLIP_MIN := 3.0
const WANDER_FLIP_MAX := 6.0

var bullet_scene := preload("res://scenes/bullet.tscn")
var grenade_scene := preload("res://scenes/grenade.tscn")
var rocket_scene := preload("res://scenes/rocket.tscn")
const SoldierArt = preload("res://scripts/soldier_art.gd")
const Gostek = preload("res://scripts/gostek.gd")

var jet_particles: CPUParticles2D


func _ready() -> void:
	add_to_group("soldier")
	tree_exited.connect(func() -> void: Gostek.forget(self))
	if cosmetics.is_empty():
		var heads := ["helm", "kap", "hair1", "hair2", "hair3", "hair4"]
		var chains := ["none", "silver", "gold"]
		var head_pick: String = heads[randi() % heads.size()]
		cosmetics = {
			"head": head_pick,
			"vest": randf() < 0.4,
			"chain": chains[randi() % chains.size()],
			"cigar": randf() < 0.2,
			# Dreadlocks only make sense with a hair head; roll separately so bald
			# / helmeted bots don't render orphan dred tufts. (#60)
			"dreadlocks": head_pick.begins_with("hair") and randf() < 0.35,
			"dogtag": randf() < 0.3,
		}
	ammo = int(AMMO_STATS.get(loadout, AMMO_STATS["AK-74"])["mag"])
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20, 42)
	shape.shape = rect
	add_child(shape)
	jet_particles = CPUParticles2D.new()
	jet_particles.amount = 18
	jet_particles.lifetime = 0.45
	jet_particles.one_shot = false
	jet_particles.emitting = false
	jet_particles.direction = Vector2(0, 1)
	jet_particles.spread = 22.0
	jet_particles.gravity = Vector2(0, 340)
	jet_particles.initial_velocity_min = 33.0
	jet_particles.initial_velocity_max = 80.0
	jet_particles.scale_amount_min = 0.8
	jet_particles.scale_amount_max = 2.1
	jet_particles.color = Color(1.0, 0.55, 0.18)
	add_child(jet_particles)


func _physics_process(delta: float) -> void:
	if dead:
		return

	# Non-authority replica: AI + physics run only on the host (bot authority = peer 1).
	# Clients receive pos/vel/facing/health/etc. via main.gd::net_bot_state and just
	# tick the visual bookkeeping so muzzle flashes decay and jet particles animate.
	if multiplayer.multiplayer_peer != null and not is_multiplayer_authority():
		muzzle_t = maxf(0.0, muzzle_t - delta * 10.0)
		if jet_particles != null:
			jet_particles.emitting = jet_on and not Settings.lofi
			jet_particles.position = Vector2(-facing * 3.3, 1.7)
		queue_redraw()
		return

	bink_t = maxf(0.0, bink_t - delta * 100.0)
	ceasefire_t = maxf(0.0, ceasefire_t - delta)
	_refresh_target(delta)

	var on_floor := is_on_floor()
	var dx := 0.0
	var dy := 0.0
	if is_instance_valid(target):
		dx = target.global_position.x - global_position.x
		dy = target.global_position.y - global_position.y

	# circle-strafe: flip lateral direction periodically while engaged
	strafe_t -= delta
	if strafe_t <= 0.0:
		strafe_dir = 1.0 if randf() < 0.5 else -1.0
		strafe_t = randf_range(0.5, 1.2)

	var dir := 0.0
	if is_instance_valid(target):
		if absf(dx) > 120.0:
			dir = signf(dx)
		else:
			dir = strafe_dir  # close in → strafe around
	else:
		# Idle wander: pick a fresh direction periodically, flip early when we
		# reach the map edge. Prior code hard-coded `dir = 1.0` which piled
		# every targetless bot at the right wall.
		wander_t -= delta
		if wander_t <= 0.0 or global_position.x < 200.0 or global_position.x > 4600.0:
			wander_dir = -wander_dir if (global_position.x < 200.0 or global_position.x > 4600.0) \
				else (1.0 if randf() < 0.5 else -1.0)
			wander_t = randf_range(WANDER_FLIP_MIN, WANDER_FLIP_MAX)
		dir = wander_dir

	velocity.x = move_toward(velocity.x, dir * RUN_SPEED, 1300.0 * delta)
	_hop_cd = maxf(0.0, _hop_cd - delta)

	# dodge-jump when an enemy bullet is closing in
	dodge_cd -= delta
	if dodge_cd <= 0.0 and _bullet_incoming():
		if on_floor:
			velocity.y = JUMP_VEL
			Sfx.jump()
		dodge_cd = 0.5

	# jump / jet toward the target when it's above us
	jet_on = false
	jump_cd -= delta
	if is_instance_valid(target):
		# Bunny-hop toward a distant target: on floor, target > 260 away, hop
		# with a small horizontal boost so bots can actually close the gap.
		var dist_h: float = absf(dx)
		if dy < -50.0 and on_floor and jump_cd <= 0.0:
			velocity.y = JUMP_VEL
			jump_cd = 0.9
			Sfx.jump()
		elif on_floor and jump_cd <= 0.0 and dist_h > 260.0 and _hop_cd <= 0.0:
			velocity.y = JUMP_VEL
			velocity.x = signf(dx) * maxf(RUN_SPEED, absf(velocity.x) * 1.08)
			jump_cd = 0.35
			_hop_cd = HOP_COOLDOWN
			Sfx.jump()
		elif dy < -80.0 and not on_floor and fuel > 0.0:
			velocity.y += JET_THRUST * delta
			fuel = maxf(0.0, fuel - 40.0 * delta)
			jet_on = true
	if jet_on and not was_jet:
		Sfx.jet(true)
	elif not jet_on and was_jet:
		Sfx.jet(false)
	was_jet = jet_on
	jet_particles.emitting = jet_on and not Settings.lofi
	jet_particles.position = Vector2(-facing * 3.3, 1.7)
	if on_floor:
		fuel = minf(100.0, fuel + 32.0 * delta)

	if not on_floor:
		velocity.y += BASE_GRAVITY * float(Settings.mod_gravity) * delta
		velocity.y = minf(velocity.y, MAX_FALL)

	if dir != 0.0:
		facing = dir

	move_and_slide()

	# lob a grenade at mid-range
	grenade_cd -= delta
	if is_instance_valid(target) and grenade_cd <= 0.0 and grenades > 0:
		var dist: float = sqrt(dx * dx + dy * dy)
		if dist > 300.0 and dist < 560.0:
			_throw_grenade(dx, dy, dist)
			grenade_cd = 2.5

	# shoot with lead aim (#36: gated on ammo + reload)
	fire_cd -= delta
	muzzle_t = maxf(0.0, muzzle_t - delta * 10.0)
	if reloading:
		reload_t -= delta
		if reload_t <= 0.0:
			reloading = false
			ammo = int(AMMO_STATS.get(loadout, AMMO_STATS["AK-74"])["mag"])
	elif ammo <= 0:
		_start_reload()
	elif is_instance_valid(target) and fire_cd <= 0.0:
		var to_t: Vector2 = target.global_position - global_position
		var t_len: float = to_t.length()
		# LAW bots refuse point-blank shots — rocket blast radius 130 would splash themselves to death.
		if loadout == "LAW" and t_len < ROCKET_MIN_RANGE:
			pass
		elif t_len < ENGAGE_RANGE and _has_line_of_sight(target):
			_shoot(to_t)

	queue_redraw()


func _refresh_target(delta: float = 0.0) -> void:
	_target_refresh_cd -= delta
	# Detect being wedged against a wall: dir set but velocity stalled.
	var stuck := false
	if is_instance_valid(target):
		var wants_dx: float = target.global_position.x - global_position.x
		if absf(wants_dx) > 120.0 and absf(velocity.x) < 20.0:
			_stuck_t += delta
			if _stuck_t > 0.5:
				stuck = true
				# Jump to try climbing over the wall/ledge that's holding us —
				# a fresh target alone doesn't get us over collision.
				if is_on_floor() and jump_cd <= 0.0:
					velocity.y = JUMP_VEL
					velocity.x = signf(wants_dx) * RUN_SPEED
					jump_cd = 0.5
		else:
			_stuck_t = 0.0
	# Keep the current target only briefly; periodically re-pick the closest live enemy
	# (or force a re-pick if we're stuck on geometry).
	if is_instance_valid(target) and not target.get("dead") and _target_refresh_cd > 0.0 and not stuck:
		return
	_target_refresh_cd = 1.2
	_stuck_t = 0.0
	var best: Node2D = null
	var best_d2: float = INF
	for s in get_tree().get_nodes_in_group("soldier"):
		if s == self or s.get("team") == team or s.get("dead"):
			continue
		var d2: float = (s.global_position - global_position).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best = s
	target = best


func _has_line_of_sight(t: Node2D) -> bool:
	# Cast a ray from the bot's chest to the target's chest. If any StaticBody2D
	# terrain sits in the way we skip the shot — otherwise the bot happily plinks
	# through walls, which reads as an aim-bot to human players.
	if not is_instance_valid(t):
		return false
	var space := get_world_2d().direct_space_state
	var from := global_position + Vector2(0, -8)
	var to := t.global_position + Vector2(0, -8)
	var q := PhysicsRayQueryParameters2D.create(from, to)
	q.exclude = [self, t]
	q.collide_with_areas = false
	q.collide_with_bodies = true
	var hit := space.intersect_ray(q)
	return hit.is_empty()


func _bullet_incoming() -> bool:
	for b in get_tree().get_nodes_in_group("bullet"):
		if not is_instance_valid(b) or int(b.get("team")) == team:
			continue
		var to_b: Vector2 = b.global_position - global_position
		var d: float = to_b.length()
		# Widened from 150 → 250: bullets travel ~15px/physics tick, so 150 could skip a dodge frame entirely.
		if d < 250.0 and d > 1.0:
			var bvel: Vector2 = b.get("direction") * float(b.get("speed"))
			if to_b.normalized().dot(bvel.normalized()) < -0.6:
				return true
	return false


func _throw_grenade(dx: float, dy: float, dist: float) -> void:
	grenades -= 1
	# Spawn outside the bot's 11×20 half-extent so physics depenetration doesn't kick the grenade sideways.
	var g_pos: Vector2 = global_position + Vector2(signf(dx) * 20.0, -8.0)
	var toss := (Vector2(dx, dy) / dist + Vector2(0, -0.6)).normalized()
	var g_vel: Vector2 = toss * 460.0
	var g_ang: float = randf_range(-8.0, 8.0)
	# MP: broadcast so clients also spawn the grenade + play sfx. Physics runs
	# locally per peer (matches player.net_grenade's model); damage is authority-gated.
	if Net.is_networked() and multiplayer.has_multiplayer_peer():
		rpc("net_bot_grenade", g_pos, g_vel, g_ang)
	else:
		net_bot_grenade(g_pos, g_vel, g_ang)


func _start_reload() -> void:
	if reloading:
		return
	reloading = true
	reload_t = float(AMMO_STATS.get(loadout, AMMO_STATS["AK-74"])["reload"])
	Sfx.reload(loadout)


func _shoot(to_t: Vector2) -> void:
	if ammo <= 0:
		_start_reload()
		return
	ammo -= 1
	var aim := to_t.normalized()
	ceasefire_t = 0.0
	# lead the target by its velocity (predictive aim) — use the actual bullet
	# speed for this loadout so lead is calibrated to what we're about to fire.
	var speed_est: float = ROCKET_SPEED if loadout == "LAW" else BULLET_SPEED
	if is_instance_valid(target) and target is CharacterBody2D:
		var t_est: float = to_t.length() / speed_est
		var lead: Vector2 = target.global_position + target.velocity * t_est
		aim = (lead - global_position).normalized()
	# Bink shakes the bot's aim if they were recently shot.
	if bink_t > 0.0:
		aim = aim.rotated(randf_range(-1.0, 1.0) * (bink_t / 100.0) * 0.18)
	var muzzle: Vector2 = global_position + SoldierArt.muzzle_local(self, aim, facing, loadout) + aim * 4.0
	# MP: broadcast so clients spawn the tracer/rocket + play sfx (mirrors player.net_shoot).
	# Damage is gated per-victim in bullet.gd/rocket.gd via is_multiplayer_authority(),
	# so a client-authority player takes damage locally when a bot's bullet hits them.
	if Net.is_networked() and multiplayer.has_multiplayer_peer():
		rpc("net_bot_shoot", muzzle, aim)
	else:
		net_bot_shoot(muzzle, aim)
	# Rockets fire slower so LAW bots aren't oppressive.
	fire_cd = 1.6 if loadout == "LAW" else 0.45


# ── RPCs (issue #57) ──────────────────────────────────
# Bot authority is the host (peer 1); the host calls these via rpc() when a bot fires
# so all peers spawn a matching projectile + play sfx. `call_local` covers the host
# too, keeping SP and the host-side branch of MP on the same code path.

@rpc("authority", "call_local", "reliable")
func net_bot_shoot(muzzle: Vector2, aim: Vector2) -> void:
	Sfx.shoot(loadout)
	muzzle_t = 0.08
	# Debug counter so --smoke-botfire can confirm the RPC reached the client.
	if Net.is_client():
		Net.bot_shots_seen += 1
	var dmg_mul: float = float(Settings.mod_damage)
	if loadout == "LAW":
		var r := rocket_scene.instantiate()
		r.global_position = muzzle
		r.direction = aim
		r.speed = ROCKET_SPEED
		r.damage = 90.0 * dmg_mul
		r.team = team
		r.killer_name = display_name
		r.weapon_name = "LAW"
		get_parent().add_child(r)
	else:
		var b := bullet_scene.instantiate()
		b.global_position = muzzle
		b.direction = aim
		b.speed = BULLET_SPEED
		b.damage = 12.0 * dmg_mul
		b.team = team
		b.killer_name = display_name
		b.weapon_name = "AK-74"
		get_parent().add_child(b)


@rpc("authority", "call_local", "reliable")
func net_bot_grenade(g_pos: Vector2, g_vel: Vector2, g_ang: float) -> void:
	Sfx.grenade_throw()
	if Net.is_client():
		Net.bot_shots_seen += 1
	var g := grenade_scene.instantiate()
	g.global_position = g_pos
	g.team = team
	g.killer_name = display_name
	g.linear_velocity = g_vel
	g.angular_velocity = g_ang
	get_parent().add_child(g)


const BINK_BY_WEAPON := {
	"Deagles": 30.0, "MP5": 20.0, "AK-74": 25.0, "Steyr AUG": 20.0,
	"Spas-12": 45.0, "Ruger 77": 50.0, "Barrett": 65.0,
	"Minimi": 30.0, "Minigun": 15.0, "USSOCOM": 25.0,
}


func try_pickup_weapon(weapon_name: String) -> bool:
	# Bots only understand two loadouts today (AK-74 / LAW) — swap if matched.
	if weapon_name == "LAW" or weapon_name == "AK-74":
		loadout = weapon_name
		# Fresh magazine on pickup — mirrors player.try_pickup_weapon.
		ammo = int(AMMO_STATS.get(loadout, AMMO_STATS["AK-74"])["mag"])
		reloading = false
		reload_t = 0.0
		return true
	return false


func take_damage(amount: float, killer := "", weapon := "", killer_team := -1) -> void:
	if dead:
		return
	# Bots are singleplayer-only today, but if MP ever spawns them, only their authority peer should tally damage.
	if multiplayer.multiplayer_peer != null and not is_multiplayer_authority():
		return
	if ceasefire_t > 0.0 and killer != display_name:
		return
	health -= amount
	var bv: float = float(BINK_BY_WEAPON.get(weapon, 0.0))
	if bv > 0.0:
		bink_t = minf(100.0, bink_t + bv)
	if killer != "":
		last_killer = killer
		last_weapon = weapon
		last_killer_team = killer_team
	if health <= 0.0:
		_die()


func _die() -> void:
	if dead:
		return
	dead = true
	Sfx.gib()
	_emit_kill()
	# MP host: tell every client to play the death visual + free their replica so
	# the body vanishes in lockstep with the host (issue #55).
	if Net.is_networked() and Net.is_host() and bot_id > 0:
		var m := get_parent()
		if m != null:
			m.rpc("net_bot_die", bot_id)
	# defer FX spawn out of the physics flush (bullet body_entered → take_damage path)
	if not Settings.lofi:
		_spawn_gibs.call_deferred()
		_spawn_ragdoll.call_deferred()
	died.emit()
	queue_free()


# Called on non-authority peers from main.gd::net_bot_die — plays the visual death
# (sfx + gibs) and frees the replica. Skips _emit_kill because the host already
# fired the kill-feed via net_kill_feed.
func die_replica() -> void:
	if dead:
		queue_free()
		return
	dead = true
	Sfx.gib()
	if not Settings.lofi:
		_spawn_gibs.call_deferred()
		_spawn_ragdoll.call_deferred()
	died.emit()
	queue_free()


func _emit_kill() -> void:
	if last_killer == "":
		return
	var parent := get_parent()
	if parent != null and parent.has_signal("kill"):
		parent.emit_signal("kill", last_killer, display_name, last_weapon, last_killer_team, team)


# Between-round clean-slate reset (issue #58). Called by main.gd::_reset_round for
# every LIVING bot in non-survival modes. Position is set by the caller.
func restore_for_round() -> void:
	if dead:
		return
	health = 100.0
	fuel = 100.0
	velocity = Vector2.ZERO
	ammo = int(AMMO_STATS.get(loadout, AMMO_STATS["AK-74"])["mag"])
	reloading = false
	reload_t = 0.0
	fire_cd = 0.5
	grenades = 3
	grenade_cd = 0.0
	muzzle_t = 0.0
	bink_t = 0.0
	ceasefire_t = 3.0


func _spawn_gibs() -> void:
	var p := CPUParticles2D.new()
	p.amount = 46
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.one_shot = true
	p.emitting = true
	p.global_position = global_position
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = Vector2(0, 620)
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 440.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 5.0
	p.color = Color(0.9, 0.15, 0.15)
	get_parent().add_child(p)
	get_tree().create_timer(1.3).timeout.connect(p.queue_free)


func _spawn_ragdoll() -> void:
	# physics gib chunks: rigid bodies that fly out and settle on terrain
	var count := 7
	for _i in count:
		var body := RigidBody2D.new()
		body.position = global_position + Vector2(randf_range(-8.0, 8.0), randf_range(-20.0, 0.0))
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(randf_range(5.0, 12.0), randf_range(5.0, 12.0))
		shape.shape = rect
		body.add_child(shape)
		var vis := Polygon2D.new()
		var s := rect.size
		vis.polygon = PackedVector2Array([
			Vector2(-s.x / 2.0, -s.y / 2.0),
			Vector2(s.x / 2.0, -s.y / 2.0),
			Vector2(s.x / 2.0, s.y / 2.0),
			Vector2(-s.x / 2.0, s.y / 2.0),
		])
		vis.color = color.darkened(randf_range(0.0, 0.35))
		body.add_child(vis)
		body.linear_damp = 0.4
		body.angular_damp = 1.5
		get_parent().add_child(body)
		body.linear_velocity = Vector2(randf_range(-260.0, 260.0), randf_range(-520.0, -120.0))
		body.angular_velocity = randf_range(-14.0, 14.0)
		get_tree().create_timer(2.5).timeout.connect(body.queue_free)


func _draw() -> void:
	# Aim direction: bots don't track aim_dir as a var — reconstruct it from facing + target.
	var aim: Vector2 = Vector2(facing, 0.0)
	if is_instance_valid(target):
		aim = (target.global_position - global_position).normalized()
	var weapon_col := Color(0.85, 0.55, 0.35) if loadout == "LAW" else Color(0.72, 0.72, 0.78)
	var weapon_kind := "rocket" if loadout == "LAW" else "bullet"
	# Non-authority replicas never run move_and_slide, so is_on_floor() is stale.
	# Approximate from vertical velocity — matches the guard in player.gd::_draw.
	var on_floor := is_on_floor()
	if multiplayer.multiplayer_peer != null and not is_multiplayer_authority():
		on_floor = absf(velocity.y) < 5.0
	# #60: bots carry a fixed loadout with no secondary slot, so nothing rides
	# their back for now. Belt grenade shows when their grenade pool is > 0.
	SoldierArt.draw_soldier(
		self,
		color,
		facing,
		aim,
		velocity,
		jet_on,
		dead,
		weapon_col,
		weapon_kind,
		muzzle_t,
		health,
		fuel,
		false,
		loadout,
		on_floor,
		reloading,
		false,
		false,
		false,
		"",
		false,
		ceasefire_t > 0.0,
		cosmetics,
		"",
		grenades,
		false,
	)
