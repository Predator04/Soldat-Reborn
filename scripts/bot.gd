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
# Secondary slot (#79) — bots carry a USSOCOM as fallback so a dry primary
# doesn't leave them defenseless mid-fight. `using_secondary` is the active-
# weapon flag; both ammo pools are tracked independently so the bot can swap
# back once the primary is reloaded. Host-authoritative; mirrored to clients
# via main.gd::_broadcast_bot_state.
var using_secondary: bool = false
var secondary_ammo: int = 0
const AMMO_STATS := {
	"AK-74":        {"mag": 30,  "reload": 2.0},
	"LAW":          {"mag": 1,   "reload": 3.0},
	"USSOCOM":      {"mag": 14,  "reload": 1.0},
	# Gun Game ladder weapons — bots fall back to AK-74 stats when a name isn't
	# listed here, but explicit entries let the reload cadence read right.
	"Deagles":      {"mag": 14,  "reload": 1.5},
	"MP5":          {"mag": 32,  "reload": 1.8},
	"Steyr AUG":    {"mag": 25,  "reload": 2.1},
	"Spas-12":      {"mag": 8,   "reload": 2.5},
	"Ruger 77":     {"mag": 4,   "reload": 1.4},
	"M79":          {"mag": 1,   "reload": 3.0},
	"Barrett":      {"mag": 10,  "reload": 1.2},
	"Minimi":       {"mag": 50,  "reload": 4.2},
	"Minigun":      {"mag": 100, "reload": 8.0},
	"Flamethrower": {"mag": 200, "reload": 5.0},
	"Rambo Bow":    {"mag": 1,   "reload": 2.5},
	"Knife":        {"mag": 1,   "reload": 0.5},
	"Chainsaw":     {"mag": 200, "reload": 1.8},
}

# Per-weapon combat stats for bots (#80). `damage` + `speed` are mirrored
# straight from player.gd so a Barrett bullet hurts like a Barrett bullet
# and a Minigun tracer travels at Minigun speed. `rate` is a BOT cadence
# — not the player rate — so bots aren't oppressive at every loadout: AK-74
# stays at the pre-#80 flat 0.45, Barrett cools to 2.2 between shots (vs the
# player's 3.75), and slower guns get bot-tuned intervals. Before #80 every
# non-LAW bot fired AK-74 damage at 0.45s regardless of loadout, so a
# Barrett bot hit like an AK. `kind` drives the bullet-vs-rocket branch;
# specialised kinds (flame/arrow/launcher) fall through to a bullet since
# bots don't spawn with those loadouts today. Fallback = AK-74 stats.
const WEAPON_STATS := {
	"Deagles":      {"damage": 34.0,  "rate": 0.44,  "speed": 1200.0, "kind": "bullet"},
	"MP5":          {"damage": 13.0,  "rate": 0.10,  "speed": 950.0,  "kind": "bullet"},
	"AK-74":        {"damage": 22.0,  "rate": 0.45,  "speed": 1050.0, "kind": "bullet"},
	"Steyr AUG":    {"damage": 18.0,  "rate": 0.15,  "speed": 1150.0, "kind": "bullet"},
	"Spas-12":      {"damage": 9.0,   "rate": 0.9,   "speed": 850.0,  "kind": "bullet"},
	"Ruger 77":     {"damage": 82.0,  "rate": 1.0,   "speed": 1450.0, "kind": "bullet"},
	"M79":          {"damage": 90.0,  "rate": 3.0,   "speed": 470.0,  "kind": "bullet"},
	"Barrett":      {"damage": 245.0, "rate": 2.2,   "speed": 2400.0, "kind": "bullet"},
	"Minimi":       {"damage": 23.0,  "rate": 0.20,  "speed": 1180.0, "kind": "bullet"},
	"Minigun":      {"damage": 13.0,  "rate": 0.066, "speed": 1275.0, "kind": "bullet"},
	"Flamethrower": {"damage": 19.0,  "rate": 0.08,  "speed": 420.0,  "kind": "bullet"},
	"Rambo Bow":    {"damage": 12.0,  "rate": 1.5,   "speed": 900.0,  "kind": "bullet"},
	"USSOCOM":      {"damage": 27.0,  "rate": 0.167, "speed": 800.0,  "kind": "bullet"},
	"LAW":          {"damage": 90.0,  "rate": 1.6,   "speed": 720.0,  "kind": "rocket"},
	# Gun Game melee rungs: bots don't do full melee arc scans, so approximate with
	# a very-short-life bullet — travels ~60px then dies harmlessly. Damage still
	# routes through take_damage with the correct weapon_name for GG kill scoring.
	"Knife":        {"damage": 55.0,  "rate": 0.5,   "speed": 600.0,  "kind": "bullet", "life": 0.10},
	"Chainsaw":     {"damage": 20.0,  "rate": 0.10,  "speed": 600.0,  "kind": "bullet", "life": 0.10},
}

# grenades
var grenades := 3
var grenade_cd := 0.0

# Bink (aim penalty when hit — same model as player.gd).
var bink_t := 0.0
# Ceasefire (spawn protection) — invulnerable for the first few seconds after spawn.
var ceasefire_t := 3.0

# Gun Game rung (MODE_GG). Bots climb the same 16-weapon ladder as players —
# a kill bumps the level, a knife death demotes by one. GG_LADDER only stores
# the loadout string; the primary/secondary split matters for players.gd, but
# bots swap by re-setting `loadout` so `using_secondary` stays false.
var gg_level := 0
const GG_LADDER := [
	"USSOCOM", "Deagles", "MP5", "Steyr AUG", "AK-74",
	"Spas-12", "Ruger 77", "Minimi", "M79", "Minigun",
	"Flamethrower", "Rambo Bow", "LAW", "Barrett", "Chainsaw", "Knife",
]

# strafe / dodge
var strafe_dir := 1.0
var strafe_t := 0.0
var dodge_cd := 0.0
# Self-preservation: retreat when critically hurt and back off while reloading,
# so bots read as thinking rather than walking into death.
var _retreat_t := 0.0
var _prev_health := 100.0
# Idle wander — targetless bots pick a random direction and re-flip periodically
# so they don't pile up against the map edge (issue #43).
var wander_dir := 1.0
var wander_t := 0.0
var _hop_cd := 0.0

const BASE_GRAVITY := 1700.0
# Bots run slightly faster than the player (205) so they can still close distance,
# but not the old 320 — that read as unfair speed after the player slowdowns.
const RUN_SPEED := 235.0
const JUMP_VEL := -360.0
const JET_THRUST := -1800.0
const MAX_FALL := 1200.0
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

# #67 — difficulty. skill 1 = very easy (wide aim, slow to react, low fire cadence),
# skill 5 = expert (tight aim, snaps to targets, tighter fire cadence). Baked in
# _ready from Settings.bot_skill so a mid-match change doesn't yank existing bots.
var _skill_aim_spread := 0.09      # radians of random aim jitter per shot
var _skill_target_cd := 1.2        # seconds between target refresh
var _skill_fire_delay := 0.0       # additional fire_cd added at spawn
var _skill_engage_range := ENGAGE_RANGE

# #61: shared counter to name bot-fired projectiles consistently across peers.
var _next_proj_id: int = 1
const SoldierArt = preload("res://scripts/soldier_art.gd")
const Gostek = preload("res://scripts/gostek.gd")

var jet_particles: CPUParticles2D


func _ready() -> void:
	add_to_group("soldier")
	tree_exited.connect(func() -> void: Gostek.forget(self))
	_apply_skill()
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
	secondary_ammo = int(AMMO_STATS["USSOCOM"]["mag"])
	# Gun Game: force loadout to the current rung so every bot starts on level 0.
	if Settings.game_mode == Settings.MODE_GG:
		_apply_gg_weapon()
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


func _apply_skill() -> void:
	# Skill 1..5. Baked here so the whole match uses one difficulty and adjusting
	# mid-match doesn't retro-tune existing bots. Skill 3 preserves prior behavior.
	var s: int = clampi(MatchConfig.bot_skill(), 1, 5)
	# Aim spread: 0.30 rad at skill 1 → 0.02 rad at skill 5. This is applied AFTER
	# the target-lead calculation so a low-skill bot's aim drifts wide, not blind.
	_skill_aim_spread = lerpf(0.30, 0.02, float(s - 1) / 4.0)
	# Target refresh: at skill 1 bots re-pick every 2s (slow to react to a new
	# threat); at skill 5 every 0.4s (snaps onto a fresh target almost instantly).
	_skill_target_cd = lerpf(2.0, 0.4, float(s - 1) / 4.0)
	# Extra delay on first shot after target acquired — low skill = hesitation.
	_skill_fire_delay = lerpf(0.6, 0.0, float(s - 1) / 4.0)
	# Engagement range: low-skill bots don't shoot as far.
	_skill_engage_range = lerpf(ENGAGE_RANGE * 0.55, ENGAGE_RANGE, float(s - 1) / 4.0)
	fire_cd = maxf(fire_cd, _skill_fire_delay)
	_target_refresh_cd = _skill_target_cd


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

	# Self-preservation: entering critical HP starts a brief retreat; keep it
	# refreshing only on the crossing so a low-HP bot still re-engages.
	_retreat_t = maxf(0.0, _retreat_t - delta)
	if health < 35.0 and _prev_health >= 35.0:
		_retreat_t = 1.8
	_prev_health = health

	# circle-strafe: flip lateral direction periodically while engaged
	strafe_t -= delta
	if strafe_t <= 0.0:
		strafe_dir = 1.0 if randf() < 0.5 else -1.0
		strafe_t = randf_range(0.5, 1.2)

	var dir := 0.0
	if is_instance_valid(target):
		if _retreat_t > 0.0 or reloading:
			# Back off — can't fight effectively while hurt/reloading, so put
			# distance between us and the target instead of pressing in.
			dir = -signf(dx) if absf(dx) > 12.0 else -strafe_dir
		elif absf(dx) > 120.0:
			dir = signf(dx)
		else:
			dir = strafe_dir  # close in → strafe around
	else:
		# Idle wander: pick a fresh direction periodically, flip early when we
		# reach the map edge. Prior code hard-coded `dir = 1.0` which piled
		# every targetless bot at the right wall.
		wander_t -= delta
		if global_position.x < 200.0:
			wander_dir = 1.0
		elif global_position.x > 4600.0:
			wander_dir = -1.0
		elif wander_t <= 0.0:
			wander_dir = 1.0 if randf() < 0.5 else -1.0
			wander_t = randf_range(WANDER_FLIP_MIN, WANDER_FLIP_MAX)
		dir = wander_dir

	velocity.x = move_toward(velocity.x, dir * RUN_SPEED * MatchConfig.mod_speed(), 1300.0 * MatchConfig.mod_speed() * delta)
	_hop_cd = maxf(0.0, _hop_cd - delta)

	# dodge-jump when an enemy bullet is closing in
	dodge_cd -= delta
	if dodge_cd <= 0.0 and _bullet_incoming():
		if on_floor:
			velocity.y = JUMP_VEL * MatchConfig.mod_gravity()
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
			velocity.y = JUMP_VEL * MatchConfig.mod_gravity()
			jump_cd = 0.9
			Sfx.jump()
		elif on_floor and jump_cd <= 0.0 and dist_h > 260.0 and _hop_cd <= 0.0:
			velocity.y = JUMP_VEL * MatchConfig.mod_gravity()
			velocity.x = signf(dx) * maxf(RUN_SPEED * MatchConfig.mod_speed(), absf(velocity.x) * 1.08)
			jump_cd = 0.35
			_hop_cd = HOP_COOLDOWN
			Sfx.jump()
		elif dy < -80.0 and not on_floor and fuel > 0.0:
			velocity.y += JET_THRUST * MatchConfig.mod_jet() * MatchConfig.mod_gravity() * delta
			fuel = maxf(0.0, fuel - (40.0 / maxf(0.1, MatchConfig.mod_jet())) * delta)
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
		velocity.y += BASE_GRAVITY * MatchConfig.mod_gravity() * delta
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
	var active_ammo: int = secondary_ammo if using_secondary else ammo
	if reloading:
		reload_t -= delta
		if reload_t <= 0.0:
			reloading = false
			if using_secondary:
				secondary_ammo = int(AMMO_STATS["USSOCOM"]["mag"])
			else:
				ammo = int(AMMO_STATS.get(loadout, AMMO_STATS["AK-74"])["mag"])
	elif active_ammo <= 0:
		# #79: active mag dry. Engaged with a live target + a loaded fallback →
		# swap to the USSOCOM instead of standing in the open reloading. When
		# secondary dries too, drop back to the primary and reload it. Idle
		# bots always reload — no reason to babysit a pistol when nobody's
		# shooting at us. Gun Game locks the slot to the current rung, so the
		# fallback is disabled there — reload the rung weapon instead.
		var engaged: bool = is_instance_valid(target) and _retreat_t <= 0.0
		var gg_lock: bool = Settings.game_mode == Settings.MODE_GG
		if not gg_lock and not using_secondary and engaged and secondary_ammo > 0:
			using_secondary = true
		elif not gg_lock and using_secondary:
			using_secondary = false
			_start_reload()
		else:
			_start_reload()
	elif is_instance_valid(target) and fire_cd <= 0.0 and _retreat_t <= 0.0:
		var to_t: Vector2 = target.global_position - global_position
		var t_len: float = to_t.length()
		# LAW bots refuse point-blank rocket shots — 130px splash would kill themselves.
		# When they've swapped to the USSOCOM secondary (#79) the pistol is safe at any range.
		if loadout == "LAW" and not using_secondary and t_len < ROCKET_MIN_RANGE:
			pass
		elif t_len < _skill_engage_range and _has_line_of_sight(target):
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
	_target_refresh_cd = _skill_target_cd
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
	# MP: broadcast so clients also spawn the grenade + play sfx. Movement is now
	# authority-owned (#61) — the host bot pushes state, clients lerp.
	if Net.is_networked() and multiplayer.has_multiplayer_peer():
		var pid := _next_proj_id
		_next_proj_id += 1
		rpc("net_bot_grenade", g_pos, g_vel, g_ang, pid)
	else:
		net_bot_grenade(g_pos, g_vel, g_ang, 0)


func _apply_gg_weapon() -> void:
	# Snap loadout to the current Gun Game rung. Bots don't use their secondary
	# slot for GG — the primary IS the ladder weapon, so `using_secondary` is
	# force-cleared and the primary mag refills to the new weapon's cap.
	if gg_level < 0:
		return
	var wname: String = String(GG_LADDER[mini(gg_level, GG_LADDER.size() - 1)])
	loadout = wname
	using_secondary = false
	ammo = int(AMMO_STATS.get(wname, AMMO_STATS["AK-74"])["mag"])
	reloading = false
	reload_t = 0.0


func _start_reload() -> void:
	if reloading:
		return
	reloading = true
	# Reload the ACTIVE weapon — the secondary has its own mag + reload time (#79).
	var wname: String = "USSOCOM" if using_secondary else loadout
	reload_t = float(AMMO_STATS.get(wname, AMMO_STATS["AK-74"])["reload"])
	Sfx.reload(wname)


func _shoot(to_t: Vector2) -> void:
	# Branch on the active weapon (#79): the secondary tracks its own mag so a
	# dry primary doesn't consume USSOCOM rounds and vice-versa.
	if using_secondary:
		if secondary_ammo <= 0:
			_start_reload()
			return
		secondary_ammo -= 1
	else:
		if ammo <= 0:
			_start_reload()
			return
		ammo -= 1
	var active_weapon: String = "USSOCOM" if using_secondary else loadout
	var stats: Dictionary = WEAPON_STATS.get(active_weapon, WEAPON_STATS["AK-74"])
	var aim := to_t.normalized()
	ceasefire_t = 0.0
	# lead the target by its velocity (predictive aim) — use the actual bullet
	# speed for this loadout so lead is calibrated to what we're about to fire.
	var speed_est: float = float(stats["speed"])
	if is_instance_valid(target) and target is CharacterBody2D:
		var t_est: float = to_t.length() / speed_est
		var lead: Vector2 = target.global_position + target.velocity * t_est
		aim = (lead - global_position).normalized()
	# Bink shakes the bot's aim if they were recently shot.
	if bink_t > 0.0:
		aim = aim.rotated(randf_range(-1.0, 1.0) * (bink_t / 100.0) * 0.18)
	# #67: bake per-shot aim jitter from bot skill on TOP of bink. Low skill
	# widens the cone so shots miss; high skill barely wavers.
	if _skill_aim_spread > 0.0:
		aim = aim.rotated(randf_range(-1.0, 1.0) * _skill_aim_spread)
	var muzzle: Vector2 = global_position + SoldierArt.muzzle_local(self, aim, facing, active_weapon) + aim * 4.0
	# MP: broadcast so clients spawn the tracer/rocket + play sfx (mirrors player.net_shoot).
	# Damage is gated per-victim in bullet.gd/rocket.gd via is_multiplayer_authority();
	# rockets additionally sync transform from the host as authority (#61).
	if Net.is_networked() and multiplayer.has_multiplayer_peer():
		var pid: int = 0
		if String(stats["kind"]) == "rocket":
			pid = _next_proj_id
			_next_proj_id += 1
		rpc("net_bot_shoot", muzzle, aim, pid)
	else:
		net_bot_shoot(muzzle, aim, 0)
	# Fire cadence tracks the active weapon's rate (#80) — a Barrett bot no
	# longer fires at AK cadence, a Minigun no longer at 0.45s.
	fire_cd = float(stats["rate"])


# ── RPCs (issue #57) ──────────────────────────────────
# Bot authority is the host (peer 1); the host calls these via rpc() when a bot fires
# so all peers spawn a matching projectile + play sfx. `call_local` covers the host
# too, keeping SP and the host-side branch of MP on the same code path.

@rpc("authority", "call_local", "reliable")
func net_bot_shoot(muzzle: Vector2, aim: Vector2, proj_id: int = 0) -> void:
	# Active weapon = USSOCOM secondary if the bot has swapped, else primary loadout (#79).
	# Damage/speed come from the WEAPON_STATS table (#80) — before that fix, every
	# non-LAW bot fired AK-74 damage at BULLET_SPEED regardless of loadout.
	var active_weapon: String = "USSOCOM" if using_secondary else loadout
	var stats: Dictionary = WEAPON_STATS.get(active_weapon, WEAPON_STATS["AK-74"])
	Sfx.shoot(active_weapon)
	muzzle_t = 0.08
	# Debug counter so --smoke-botfire can confirm the RPC reached the client.
	if Net.is_client():
		Net.bot_shots_seen += 1
	var dmg_mul: float = MatchConfig.mod_damage()
	if String(stats["kind"]) == "rocket":
		var r := rocket_scene.instantiate()
		# #69: name by bot_id so two LAW bots can't collide their proj_id counters
		# and shove a rocket into `@RigidBody2D@nnn`-style auto-name territory.
		if Net.is_networked() and proj_id > 0:
			r.name = "BotRocket_%d_%d" % [bot_id, proj_id]
		r.global_position = muzzle
		r.direction = aim
		r.speed = float(stats["speed"])
		r.damage = float(stats["damage"]) * dmg_mul
		r.team = team
		r.killer_name = display_name
		r.weapon_name = active_weapon
		get_parent().add_child(r)
		if Net.is_networked() and proj_id > 0:
			r.set_multiplayer_authority(get_multiplayer_authority())
	else:
		var b := bullet_scene.instantiate()
		b.global_position = muzzle
		b.direction = aim
		b.speed = float(stats["speed"])
		b.damage = float(stats["damage"]) * dmg_mul
		b.weapon_name = active_weapon
		b.team = team
		b.killer_name = display_name
		# Gun Game melee rungs (Knife/Chainsaw) set a short "life" so bot bullets
		# only reach ~60px — approximates melee range for the bot's shoot path.
		if stats.has("life"):
			b.life = float(stats["life"])
		get_parent().add_child(b)


@rpc("authority", "call_local", "reliable")
func net_bot_grenade(g_pos: Vector2, g_vel: Vector2, g_ang: float, proj_id: int = 0) -> void:
	Sfx.grenade_throw()
	if Net.is_client():
		Net.bot_shots_seen += 1
	var g := grenade_scene.instantiate()
	# #69: name by bot_id so simultaneous throws from different bots don't
	# collide (proj_id is per-bot). Bot_id is host-assigned and mirrored to
	# clients in net_spawn_bot, so the path is identical on every peer.
	if Net.is_networked() and proj_id > 0:
		g.name = "BotGrenade_%d_%d" % [bot_id, proj_id]
	g.global_position = g_pos
	g.team = team
	g.killer_name = display_name
	g.linear_velocity = g_vel
	g.angular_velocity = g_ang
	get_parent().add_child(g)
	if Net.is_networked() and proj_id > 0:
		g.set_multiplayer_authority(get_multiplayer_authority())


const BINK_BY_WEAPON := {
	"Deagles": 30.0, "MP5": 20.0, "AK-74": 25.0, "Steyr AUG": 20.0,
	"Spas-12": 45.0, "Ruger 77": 50.0, "Barrett": 65.0,
	"Minimi": 30.0, "Minigun": 15.0, "USSOCOM": 25.0,
}


func try_pickup_weapon(weapon_name: String, mag: int = -1) -> bool:
	# Bots only understand two loadouts today (AK-74 / LAW) — swap if matched.
	if weapon_name == "LAW" or weapon_name == "AK-74":
		loadout = weapon_name
		# Mirrors player.try_pickup_weapon: preserve the thrown mag if the pickup
		# was dropped mid-fight; -1 (world pickup / legacy) means full mag.
		var full: int = int(AMMO_STATS.get(loadout, AMMO_STATS["AK-74"])["mag"])
		ammo = full if mag < 0 else clampi(mag, 0, full)
		using_secondary = false
		reloading = false
		reload_t = 0.0
		return true
	return false


@rpc("any_peer", "call_local", "reliable")
func net_remote_pickup(weapon_name: String, mag: int = -1) -> void:
	# Parity with player.net_remote_pickup (#83). Bots are host-authoritative so
	# this normally runs locally on the host anyway; keeps the pickup call site uniform.
	if multiplayer.multiplayer_peer != null:
		var sender := multiplayer.get_remote_sender_id()
		if sender == 0:
			if not Net.is_host():
				return
		elif sender != 1:
			return
	try_pickup_weapon(weapon_name, mag)


@rpc("any_peer", "call_local", "reliable")
func net_remote_damage(amount: float, killer: String, weapon: String, killer_team: int) -> void:
	if multiplayer.multiplayer_peer != null:
		var sender := multiplayer.get_remote_sender_id()
		if sender == 0:
			if not Net.is_host():
				return
		elif sender != 1:
			return
	take_damage(amount, killer, weapon, killer_team)


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
	secondary_ammo = int(AMMO_STATS["USSOCOM"]["mag"])
	using_secondary = false
	reloading = false
	reload_t = 0.0
	fire_cd = 0.5
	grenades = 3
	grenade_cd = 0.0
	muzzle_t = 0.0
	bink_t = 0.0
	ceasefire_t = 3.0
	# Gun Game: fresh round → back to level 0.
	if Settings.game_mode == Settings.MODE_GG:
		gg_level = 0
		_apply_gg_weapon()


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
		# Gibs are cosmetic — zero collision so they can't snag the player/bots.
		body.collision_layer = 0
		body.collision_mask = 0
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
	# When the bot has swapped to its USSOCOM secondary (#79), draw the pistol
	# in its hand and slot the primary on its back so it reads as a real swap.
	var active_weapon: String = "USSOCOM" if using_secondary else loadout
	var back_weapon: String = loadout if using_secondary else ""
	var weapon_col: Color
	var weapon_kind: String
	if active_weapon == "LAW":
		weapon_col = Color(0.85, 0.55, 0.35)
		weapon_kind = "rocket"
	elif active_weapon == "USSOCOM":
		weapon_col = Color(0.85, 0.8, 0.6)
		weapon_kind = "bullet"
	else:
		weapon_col = Color(0.72, 0.72, 0.78)
		weapon_kind = "bullet"
	# Non-authority replicas never run move_and_slide, so is_on_floor() is stale.
	# Approximate from vertical velocity — matches the guard in player.gd::_draw.
	var on_floor := is_on_floor()
	if multiplayer.multiplayer_peer != null and not is_multiplayer_authority():
		on_floor = absf(velocity.y) < 5.0
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
		active_weapon,
		on_floor,
		reloading,
		false,
		false,
		false,
		"",
		false,
		ceasefire_t > 0.0,
		cosmetics,
		back_weapon,
		grenades,
		false,
	)
