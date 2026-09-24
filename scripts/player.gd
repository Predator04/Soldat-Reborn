extends CharacterBody2D
## Soldier — Soldat-style movement + weapon system. Net-aware (multiplayer authority).

signal died

@export var color := Color(0.25, 0.75, 0.45)
var team := 0
var display_name := "You"
# Cosmetic outfit for this soldier — defaults to the player's Settings picks,
# but bots override to a random look so the field reads as different characters.
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
var aim_dir := Vector2.RIGHT

# ── Weapons ────────────────────────────────────────────
# `kind`: "bullet" (default) | "rocket" (slow, straight, explodes) | "launcher" (rocket + gravity arc, e.g. M79) | "melee" (single-swing arc) | "melee_cont" (chainsaw).
# `startup` (optional, seconds): Barrett/Minigun wind-up before the first shot fires while LMB held.
var weapons := [
	{"name": "Deagles",   "damage": 34.0,  "rate": 0.30,  "mag": 14,  "reload": 1.5,  "auto": false, "spread": 0.02,  "speed": 1200.0, "pellets": 1, "color": Color(0.92, 0.78, 0.35), "kind": "bullet", "bink": 30.0},
	{"name": "MP5",       "damage": 13.0,  "rate": 0.075, "mag": 32,  "reload": 1.8,  "auto": true,  "spread": 0.085, "speed": 950.0,  "pellets": 1, "color": Color(0.5, 0.62, 0.8),   "kind": "bullet", "bink": 20.0},
	{"name": "AK-74",     "damage": 22.0,  "rate": 0.11,  "mag": 30,  "reload": 2.0,  "auto": true,  "spread": 0.055, "speed": 1050.0, "pellets": 1, "color": Color(0.72, 0.72, 0.78), "kind": "bullet", "bink": 25.0},
	{"name": "Steyr AUG", "damage": 18.0,  "rate": 0.117, "mag": 25,  "reload": 2.08, "auto": true,  "spread": 0.075, "speed": 1150.0, "pellets": 1, "color": Color(0.72, 0.68, 0.55), "kind": "bullet", "bink": 20.0},
	{"name": "Spas-12",   "damage": 9.0,   "rate": 0.6,   "mag": 8,   "reload": 2.5,  "auto": false, "spread": 0.26,  "speed": 850.0,  "pellets": 8, "color": Color(0.88, 0.58, 0.3),  "kind": "bullet", "bink": 45.0},
	{"name": "Ruger 77",  "damage": 82.0,  "rate": 0.65,  "mag": 4,   "reload": 1.4,  "auto": false, "spread": 0.0,   "speed": 1450.0, "pellets": 1, "color": Color(0.78, 0.68, 0.5),  "kind": "bullet", "bink": 50.0},
	{"name": "M79",       "damage": 90.0,  "rate": 0.10,  "mag": 1,   "reload": 2.97, "auto": false, "spread": 0.0,   "speed": 470.0,  "pellets": 1, "color": Color(0.55, 0.5, 0.32),  "kind": "launcher", "gravity": 980.0, "bink": 0.0},
	{"name": "Barrett",   "damage": 245.0, "rate": 3.75,  "mag": 10,  "reload": 1.17, "auto": false, "spread": 0.0,   "speed": 2400.0, "pellets": 1, "color": Color(0.55, 0.55, 0.6),  "kind": "bullet", "startup": 0.32, "bink": 65.0},
	{"name": "Minimi",    "damage": 23.0,  "rate": 0.15,  "mag": 50,  "reload": 4.17, "auto": true,  "spread": 0.064, "speed": 1180.0, "pellets": 1, "color": Color(0.5, 0.55, 0.4),   "kind": "bullet", "bink": 30.0},
	{"name": "Minigun",   "damage": 13.0,  "rate": 0.05,  "mag": 100, "reload": 8.0,  "auto": true,  "spread": 0.3,   "speed": 1275.0, "pellets": 1, "color": Color(0.75, 0.72, 0.78), "kind": "bullet", "startup": 0.42, "bink": 15.0},
	# Flamethrower — kind "flame" spawns short-lived orange puffs, so the cone dies at ~120px.
	{"name": "Flamethrower", "damage": 19.0, "rate": 0.06,  "mag": 200, "reload": 5.0,  "auto": true,  "spread": 0.12, "speed": 420.0, "pellets": 1, "color": Color(1.0, 0.5, 0.15), "kind": "flame", "bink": 0.0, "life": 0.35},
	# Rambo Bow — kind "arrow" is a slow, sagging projectile.
	{"name": "Rambo Bow",    "damage": 12.0, "rate": 1.0,   "mag": 1,   "reload": 2.5,  "auto": false, "spread": 0.0,  "speed": 900.0, "pellets": 1, "color": Color(0.6, 0.4, 0.2),  "kind": "arrow", "bink": 0.0, "gravity": 240.0},
]
# Secondary slot — the second weapon the soldier carries (Q to swap primary↔secondary).
var secondary := [
	{"name": "USSOCOM",  "damage": 27.0, "rate": 0.167, "mag": 14,  "reload": 1.0,  "auto": false, "spread": 0.0, "speed": 800.0, "pellets": 1, "color": Color(0.85, 0.8, 0.6),   "kind": "bullet", "bink": 25.0},
	{"name": "Knife",    "damage": 55.0, "rate": 0.5,   "mag": 1,   "reload": 0.05, "auto": false, "spread": 0.0, "speed": 0.0,   "pellets": 0, "color": Color(0.9, 0.9, 0.95),   "kind": "melee",      "range": 34.0, "bink": 0.0},
	{"name": "Chainsaw", "damage": 3.0,  "rate": 0.10,  "mag": 200, "reload": 1.83, "auto": true,  "spread": 0.0, "speed": 0.0,   "pellets": 0, "color": Color(1.0, 0.7, 0.15),   "kind": "melee_cont", "range": 32.0, "bink": 0.0},
	{"name": "LAW",      "damage": 90.0, "rate": 1.1,   "mag": 1,   "reload": 3.0,  "auto": false, "spread": 0.0, "speed": 720.0, "pellets": 1, "color": Color(0.85, 0.55, 0.35), "kind": "rocket", "bink": 0.0},
]
var ammo: Array[int] = []
var secondary_ammo: Array[int] = []
var weapon_index := 2   # default primary = AK-74 (Soldat's #3)
var secondary_index := 0  # default secondary = USSOCOM
var using_secondary := false
var fire_cd := 0.0
var spin_up_t := 0.0    # ramps up while LMB held for weapons with a startup wind-up (Barrett, Minigun)
var lmb_prev := false   # prev-frame LMB state — resets spin_up_t when the trigger releases
var reloading := false
var reload_t := 0.0
var grenades := 3
var grenade_cd := 0.0
# Grenade type toggle — press G to swap Frag ↔ Cluster.
var use_cluster := false
var g_prev := false
var muzzle_t := 0.0
var q_prev := false     # prev-frame Q — swap on rising edge only, not every physics tick
var x_prev := false     # prev-frame X — prone toggle on rising edge
var s_prev := false     # prev-frame S — roll on rising edge with lateral momentum
var f_prev := false     # prev-frame F — throw current weapon on rising edge
# #87: weapons the player has thrown (name -> true). Thrown weapons are removed
# from the active roster until re-picked up (or respawn).
var _thrown: Dictionary = {}
# Host-side rate-limit on drop RPCs so a modded client can't spam pickup spawns.
var _last_drop_ms: int = 0
var crouching := false
var prone := false
# Roll — S pressed while running triggers a short forward burst (Soldat's roll).
var roll_t := 0.0
var roll_cd := 0.0
const ROLL_DURATION := 0.32
const ROLL_COOLDOWN := 0.85
# Roll must beat bunny-hop (BUNNY_SPEED 415) — otherwise it's a slower alternative
# and no one uses it. Locked at 650 for the whole roll window, ignoring friction.
const ROLL_SPEED := 650.0
var roll_dir := 1.0
var melee_swing_t := 0.0  # short window (~0.25s) after a Knife/Chainsaw strike — drives the "bije" pose
# Bink — extra aim spread applied when the *victim* takes damage from a bink weapon.
# Barrett's 65 is intentionally punishing; most rifles land 20-30. Decays over ~0.6s.
var bink_t := 0.0
# Gesture (/commands) — overrides the anim state machine while active.
var gesture_anim := ""
var gesture_t := 0.0
# Ceasefire — brief invulnerability window after (re)spawn. Prevents spawn-kills.
# Ends early the moment the soldier fires/throws (Soldat behavior).
var ceasefire_t := 0.0
const CEASEFIRE_SECS := 3.0
# M2 mount — set to the M2 node while mounted. Skips all normal movement /
# firing paths; m2.gd drives position + fires directly.
var mounted_m2: Node2D = null

# MP projectile identity (#61). Each grenade/rocket the local peer spawns is
# named "Grenade_<peer>_<n>" / "Rocket_<peer>_<n>" so per-projectile RPCs (state
# broadcasts) can address the same node path on every peer. Counter increments
# locally on this peer; peer_id disambiguates across peers.
var _next_proj_id: int = 1

# Advance mode — kill count and per-slot unlock kill thresholds. Only enforced
# when Settings.advance is on; otherwise every weapon is available from spawn.
var advance_kills := 0
# Indexed by weapon_index — 12 primaries (matches `weapons` array size).
const ADV_PRIMARY_UNLOCK := [10, 4, 6, 8, 12, 14, 20, 22, 18, 24, 28, 30]
# Indexed by secondary_index — 4 slots (USSOCOM, Knife, Chainsaw, LAW).
const ADV_SECONDARY_UNLOCK := [2, 0, 26, 16]

# Gun Game (MODE_GG) — 16-rung weapon ladder, weak → strong, knife last.
# `sec` picks the slot (secondary vs primary); `idx` is the index inside that
# slot's array (see `weapons` / `secondary` above). A kill bumps gg_level by 1;
# a knife kill at the final rung wins the round.
var gg_level := 0
const GG_LADDER := [
	{"name": "USSOCOM",      "sec": true,  "idx": 0},
	{"name": "Deagles",      "sec": false, "idx": 0},
	{"name": "MP5",          "sec": false, "idx": 1},
	{"name": "Steyr AUG",    "sec": false, "idx": 3},
	{"name": "AK-74",        "sec": false, "idx": 2},
	{"name": "Spas-12",      "sec": false, "idx": 4},
	{"name": "Ruger 77",     "sec": false, "idx": 5},
	{"name": "Minimi",       "sec": false, "idx": 8},
	{"name": "M79",          "sec": false, "idx": 6},
	{"name": "Minigun",      "sec": false, "idx": 9},
	{"name": "Flamethrower", "sec": false, "idx": 10},
	{"name": "Rambo Bow",    "sec": false, "idx": 11},
	{"name": "LAW",          "sec": true,  "idx": 3},
	{"name": "Barrett",      "sec": false, "idx": 7},
	{"name": "Chainsaw",     "sec": true,  "idx": 2},
	{"name": "Knife",        "sec": true,  "idx": 1},
]
# Input lock — HUD sets this while the chat/command LineEdit is focused so held
# WASD keys don't leak into movement while the player is typing.
var input_locked := false

# Bonus pickup (#78). Applied/cleared via net_bonus_apply / net_bonus_clear
# (call_local, so every peer applies its own copy). Duration ticks locally on
# each replica so the visual (predator alpha, red tint) decays in step. The
# "breaks on fire" clear for predator broadcasts an explicit clear RPC.
var bonus_kind: String = ""       # "" | "predator" | "berserker" | "vest" | "cluster"
var bonus_t: float = 0.0
# Saved state so clear_bonus can restore the pre-effect loadout. Berserker
# forces the knife slot; cluster forces use_cluster on; both need to snap back.
var _bonus_saved_use_cluster: bool = false
var _bonus_saved_using_secondary: bool = false
var _bonus_saved_secondary_index: int = 0
var _bonus_saved_color: Color = Color(1, 1, 1)

# ── Feel ───────────────────────────────────────────────
var coyote_t := 0.0
var jump_buffer_t := 0.0
var shake := 0.0
var cam: Camera2D
var jet_particles: CPUParticles2D

# Three preallocated collision shapes so crouch/prone can hot-swap without
# leaking or freeing while physics is still using the current shape.
var col_shape: CollisionShape2D
var shape_stand: RectangleShape2D
var _wedge_t := 0.0  # seconds resting wedged without floor contact
var shape_crouch: RectangleShape2D
var shape_prone: RectangleShape2D

# ── Physics ────────────────────────────────────────────
const GRAVITY := 1700.0
const RUN_SPEED := 205.0
const BUNNY_SPEED := 415.0
const GROUND_ACCEL := 2250.0
const AIR_ACCEL := 950.0
const AIR_FRICTION := 45.0
const GROUND_FRICTION := 1700.0
const JUMP_VEL := -345.0
const JET_THRUST := -1720.0
const JET_DRAIN := 40.0
const JET_REGEN := 32.0
const MAX_FALL := 1200.0
const COYOTE_TIME := 0.09
const JUMP_BUFFER := 0.10
# Ladder climb — Soldat-style. W/S drives vertical velocity, gravity off, x
# snapped toward the ladder center. Slower than run (205) so climbing feels
# deliberate.
const CLIMB_SPEED := 150.0
# Time after engaging a ladder before a fresh jump-press can dismount, so the
# initial W press that engages doesn't also hop-off in the same frame.
const CLIMB_ENGAGE_GRACE := 0.20
# Ladder overlap padding — the player's feet-anchored body sits above the
# world origin, so this bounds the vertical range we treat as "on the ladder".
const CLIMB_BODY_PAD_TOP := 24.0
const CLIMB_BODY_PAD_BOTTOM := 6.0

# Ladder climb state. `on_ladder` is set each physics tick from ladder overlap;
# `climbing` becomes true when W/S engages a climb and clears on dismount.
var on_ladder := false
var climbing := false
var _active_ladder: Node2D = null
var _climb_engage_t: float = 0.0

var bullet_scene := preload("res://scenes/bullet.tscn")
var grenade_scene := preload("res://scenes/grenade.tscn")
var rocket_scene := preload("res://scenes/rocket.tscn")
const SoldierArt = preload("res://scripts/soldier_art.gd")
const Gostek = preload("res://scripts/gostek.gd")
const WeaponPickup = preload("res://scripts/weapon_pickup.gd")
const TouchControls = preload("res://scripts/touch_controls.gd")


func _ready() -> void:
	# Terrain layer 3 (bit 4) = ported "only players collide" polys.
	# Soldiers live on their own layer 4 (bit 8) and don't collide with each
	# other (as in Soldat) — bodies shoving one another used to push soldiers
	# into walls and block narrow tunnels. Bullets/rockets/grenades/pickups
	# mask bit 8 to keep hitting them.
	collision_layer = 8
	collision_mask = 1 | 4
	add_to_group("soldier")
	ceasefire_t = CEASEFIRE_SECS
	if cosmetics.is_empty():
		cosmetics = {
			"head": Settings.cos_head,
			"vest": Settings.cos_vest,
			"chain": Settings.cos_chain,
			"cigar": Settings.cos_cigar,
			"dreadlocks": Settings.cos_dreadlocks,
			"dogtag": Settings.cos_dogtag,
		}
	# Release the per-instance skeleton state dict when this node is freed so long
	# sessions don't leak dict entries in Gostek._states.
	tree_exited.connect(func() -> void: Gostek.forget(self))
	for w in weapons:
		ammo.append(int(w["mag"]))
	for w in secondary:
		secondary_ammo.append(int(w["mag"]))
	# Gun Game: spawn on the current rung's weapon so every soldier starts on the
	# same weak weapon (level 0 = USSOCOM). Level persists across deaths.
	if Settings.game_mode == Settings.MODE_GG:
		_apply_gg_weapon()
	col_shape = CollisionShape2D.new()
	shape_stand = RectangleShape2D.new()
	shape_stand.size = Vector2(14, 24)
	shape_crouch = RectangleShape2D.new()
	shape_crouch.size = Vector2(16, 16)
	shape_prone = RectangleShape2D.new()
	shape_prone.size = Vector2(28, 8)
	col_shape.shape = shape_stand
	# Feet-anchored: box bottom sits at the body origin (sprite feet, Y≈0) so the
	# soldier stands ON the ground instead of floating. (#72)
	col_shape.position = Vector2(0, -shape_stand.size.y * 0.5)
	add_child(col_shape)
	cam = Camera2D.new()
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	cam.zoom = Vector2(1.0, 1.0)
	# Clamp the camera to the map bounds (Soldat renders 1:1 with no outside-map view).
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = 4800
	cam.limit_bottom = 2000
	add_child(cam)
	if multiplayer.multiplayer_peer == null or is_multiplayer_authority():
		cam.make_current()
	else:
		cam.enabled = false
	jet_particles = CPUParticles2D.new()
	jet_particles.amount = 24
	jet_particles.lifetime = 0.5
	jet_particles.one_shot = false
	jet_particles.explosiveness = 0.0
	jet_particles.emitting = false
	jet_particles.direction = Vector2(0, 1)
	jet_particles.spread = 22.0
	jet_particles.gravity = Vector2(0, 360)
	jet_particles.initial_velocity_min = 38.0
	jet_particles.initial_velocity_max = 88.0
	jet_particles.scale_amount_min = 0.8
	jet_particles.scale_amount_max = 2.3
	jet_particles.color = Color(1.0, 0.55, 0.18)
	add_child(jet_particles)


func _physics_process(delta: float) -> void:
	if dead:
		velocity = Vector2.ZERO
		return

	# During teardown (server disconnect / quit), the peer may be gone for a frame.
	# Skip everything cleanly rather than throwing "No multiplayer peer" errors.
	var has_peer := multiplayer.has_multiplayer_peer()
	if Net.is_networked() and not has_peer:
		return

	# Non-authority replica: state is set by net_state RPCs; just visual bookkeeping.
	if has_peer and not is_multiplayer_authority():
		muzzle_t = maxf(0.0, muzzle_t - delta * 10.0)
		if gesture_t > 0.0:
			gesture_t = maxf(0.0, gesture_t - delta)
			if gesture_t <= 0.0:
				gesture_anim = ""
		# Bonus tick on the replica so predator alpha / berserker red decay in
		# step with the authority peer (both received the same duration via
		# call_local). Explicit predator break-on-fire is still broadcast.
		if bonus_kind != "":
			bonus_t = maxf(0.0, bonus_t - delta)
			if bonus_t <= 0.0:
				_clear_bonus_local()
		# Predator: other peers see the ghost, self stays visible. This branch
		# only runs on peers where this body is not the local player, so we
		# always dim when active. (#78)
		modulate.a = 0.35 if bonus_kind == "predator" else 1.0
		jet_particles.emitting = jet_on and not dead
		jet_particles.position = Vector2(-facing * 3.3, 1.7)
		queue_redraw()
		return

	# Mounted on an M2 — the turret drives position, aim, and firing.
	if mounted_m2 != null:
		velocity = Vector2.ZERO
		if was_jet:
			Sfx.jet(false)
			was_jet = false
		jet_on = false
		jet_particles.emitting = false
		muzzle_t = maxf(0.0, muzzle_t - delta * 10.0)
		# Fuel keeps regenerating while mounted — the operator is stationary on
		# the sandbag, not draining tanks. Uses the same mod_jet scaling as
		# grounded regen so mods stay consistent.
		fuel = minf(100.0, fuel + JET_REGEN * MatchConfig.mod_jet() * delta)
		# Allow exiting prone/crouch while mounted so the soldier isn't locked
		# into a stance they can't leave. Toggle on rising edge like normal.
		var x_now_m := Input.is_action_pressed("prone")
		if x_now_m and not x_prev and prone:
			prone = false
		x_prev = x_now_m
		if crouching and not Input.is_action_pressed("crouch"):
			crouching = false
		_apply_stance_shape()
		# Recover from bink/ceasefire while mounted too — otherwise a soldier who
		# mounts mid-fight still shakes forever.
		bink_t = maxf(0.0, bink_t - delta * 100.0)
		ceasefire_t = maxf(0.0, ceasefire_t - delta)
		# Refresh rising-edge prev states so a key held while mounted doesn't
		# fire a spurious roll/swap/throw on the frame after dismount.
		s_prev = Input.is_action_pressed("crouch")
		q_prev = Input.is_action_pressed("secondary_swap")
		g_prev = Input.is_action_pressed("grenade_toggle")
		f_prev = Input.is_action_pressed("weapon_throw")
		lmb_prev = Input.is_action_pressed("fire")
		queue_redraw()
		return

	# If the HUD command/chat line is open, freeze inputs: drop x-velocity, apply
	# gravity so we still fall to ground, and skip all movement/shooting handling.
	if input_locked:
		velocity.x = move_toward(velocity.x, 0.0, (GROUND_FRICTION if is_on_floor() else AIR_FRICTION) * delta)
		if not is_on_floor():
			velocity.y += GRAVITY * MatchConfig.mod_gravity() * delta
			velocity.y = minf(velocity.y, MAX_FALL)
		jet_on = false
		if was_jet:
			Sfx.jet(false)
			was_jet = false
		jet_particles.emitting = false
		move_and_slide()
		if gesture_t > 0.0:
			gesture_t = maxf(0.0, gesture_t - delta)
			if gesture_t <= 0.0:
				gesture_anim = ""
		# Refresh rising-edge prev states so closing chat with a key still held
		# doesn't trigger a spurious prone/roll/swap/grenade/throw/fire.
		x_prev = Input.is_action_pressed("prone")
		s_prev = Input.is_action_pressed("crouch")
		q_prev = Input.is_action_pressed("secondary_swap")
		g_prev = Input.is_action_pressed("grenade_toggle")
		f_prev = Input.is_action_pressed("weapon_throw")
		lmb_prev = Input.is_action_pressed("fire")
		queue_redraw()
		return

	var left := Input.is_action_pressed("move_left")
	var right := Input.is_action_pressed("move_right")
	var jump_pressed := Input.is_action_pressed("jump")

	# Crouch (S hold) + prone (X toggle). Prone locks out crouching.
	# W/Space or another X press stands us up from prone.
	var x_now := Input.is_action_pressed("prone")
	if x_now and not x_prev:
		prone = not prone
		if prone:
			crouching = false
	x_prev = x_now
	if prone and jump_pressed:
		prone = false
	var s_now := Input.is_action_pressed("crouch") and not prone
	# Roll: press S with lateral momentum → brief burst, skokdolobrot anim, no crouch shape.
	# Suppressed while climbing so S = climb-down doesn't fire a roll on step-off.
	if s_now and not s_prev and is_on_floor() and roll_cd <= 0.0 and absf(velocity.x) > 60.0 and not climbing:
		roll_t = ROLL_DURATION
		roll_cd = ROLL_COOLDOWN
		roll_dir = signf(velocity.x)
		velocity.x = roll_dir * ROLL_SPEED
		Sfx.jump()
	s_prev = s_now
	crouching = s_now and roll_t <= 0.0 and not climbing
	_apply_stance_shape()

	# ── Ladder / climbing ──────────────────────────────
	# Detect overlap, engage on W/S press, disengage on overlap loss or a
	# fresh jump-tap after the engage grace. Climbing suppresses gravity/jet/
	# jump/roll/crouch/prone for this tick; other movement/weapon paths run
	# normally so aim + shoot still work while climbing.
	var new_ladder: Node2D = _find_ladder_overlap()
	on_ladder = new_ladder != null
	var climb_down_pressed := Input.is_action_pressed("crouch")
	# Engage on the RISING edge of jump/climb-down, not the level. Held-W while
	# jetpacking through a ladder rect used to auto-snap you onto it, killing
	# vertical velocity mid-flight. Grace-time hop-off already uses just_pressed.
	var engage_pressed: bool = Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("crouch")
	if not climbing and on_ladder and engage_pressed:
		climbing = true
		_active_ladder = new_ladder
		_climb_engage_t = 0.0
		prone = false
		crouching = false
		roll_t = 0.0
		if was_jet:
			Sfx.jet(false)
			was_jet = false
		jet_on = false
		velocity.y = 0.0
		_apply_stance_shape()
	if climbing:
		if not on_ladder:
			climbing = false
			_active_ladder = null
		else:
			_active_ladder = new_ladder
			_climb_engage_t += delta
			# Fresh jump-tap after grace → hop off with a small upward pop.
			if Input.is_action_just_pressed("jump") and _climb_engage_t > CLIMB_ENGAGE_GRACE:
				climbing = false
				_active_ladder = null
				var mg_off: float = MatchConfig.mod_gravity()
				velocity.y = JUMP_VEL * 0.55 * mg_off
				coyote_t = 0.0
				jump_buffer_t = 0.0
				Sfx.jump()

	var dir := 0.0
	if left:
		dir -= 1.0
	if right:
		dir += 1.0

	var on_floor := is_on_floor() or _wedge_t > 0.2  # see _update_wedge

	# coyote time + jump buffering
	coyote_t = COYOTE_TIME if on_floor else maxf(0.0, coyote_t - delta)
	jump_buffer_t = JUMP_BUFFER if jump_pressed else maxf(0.0, jump_buffer_t - delta)

	if climbing and _active_ladder != null:
		# Climbing owns velocity this frame. Vertical from W/S; horizontal is a
		# gentle snap toward the ladder center that A/D input can overpower to
		# step off (which disengages via overlap loss next frame).
		var vy_climb := 0.0
		if jump_pressed:
			vy_climb -= CLIMB_SPEED
		if climb_down_pressed:
			vy_climb += CLIMB_SPEED
		velocity.y = vy_climb
		var target_x: float = float(_active_ladder.get_meta("center_x", global_position.x))
		var to_center: float = target_x - global_position.x
		# #96: only auto-center when the player isn't giving lateral input, and
		# only if we're actually off-center by more than a few pixels. Otherwise
		# the snap term drags A/D input on wide ladders and step-off fights the
		# lateral exit.
		if dir == 0.0 and absf(to_center) > 8.0:
			velocity.x = clampf(to_center * 9.0, -220.0, 220.0)
		else:
			velocity.x = clampf(dir * 160.0, -220.0, 220.0)
		# Suppress bunny-hop this tick — climbing steers vertical velocity.
		jump_buffer_t = 0.0
		coyote_t = 0.0
	else:
		# horizontal
		var speed_mul: float = MatchConfig.mod_speed()
		# Predator bonus (#78) — +35% speed while active. Berserker also gets a
		# small nudge so the melee rush feels dangerous. Cluster/Vest are neutral.
		if bonus_kind == "predator":
			speed_mul *= 1.35
		elif bonus_kind == "berserker":
			speed_mul *= 1.15
		var accel := (GROUND_ACCEL if on_floor else AIR_ACCEL) * speed_mul
		var cap := (RUN_SPEED if on_floor else BUNNY_SPEED) * speed_mul
		# Preserve bunny-hop momentum: if a buffered jump will fire this tick,
		# skip the RUN_SPEED clamp so airborne speed isn't clipped on the landing frame.
		if on_floor and jump_buffer_t > 0.0 and coyote_t > 0.0:
			cap = BUNNY_SPEED * speed_mul
		# Crouch/prone slow the ground cap; airborne cap is untouched so bunny-hops are preserved.
		# Roll trumps both — a short window at ROLL_SPEED before ground friction reasserts.
		if on_floor:
			if roll_t > 0.0:
				cap = ROLL_SPEED
			elif prone:
				cap *= 0.28
			elif crouching:
				cap *= 0.6
		if roll_t > 0.0:
			# Roll ignores A/D input + friction — locked speed for the whole window
			# so it always beats a bunny-hop's lateral cap.
			velocity.x = roll_dir * ROLL_SPEED
		elif dir != 0.0:
			velocity.x += dir * accel * delta
			velocity.x = clampf(velocity.x, -cap, cap)
		else:
			var fr := GROUND_FRICTION if on_floor else AIR_FRICTION
			velocity.x = move_toward(velocity.x, 0.0, fr * delta)
			velocity.x = clampf(velocity.x, -cap, cap)

		# jet boots (RMB, matching Soldat's default controls). Realistic mode locks
		# the boots — Soldat's Realistic ruleset removes fuel entirely.
		# mod_jet scales thrust/drain/regen consistently; mod_gravity scales thrust
		# so the boots still lift you in higher-gravity worlds.
		var jet_pressed := Input.is_action_pressed("jet") and not Settings.realistic
		var mj: float = MatchConfig.mod_jet()
		var mg: float = MatchConfig.mod_gravity()
		jet_on = false
		if jet_pressed and not on_floor and fuel > 0.0:
			velocity.y += JET_THRUST * mj * mg * delta
			fuel = maxf(0.0, fuel - (JET_DRAIN / maxf(0.1, mj)) * delta)
			jet_on = true
		# Grounded regen — always fires when on the floor, even if RMB is held.
		# Prior version used elif, which technically worked (RMB+ground failed
		# the first branch), but the split makes the intent unambiguous.
		if on_floor:
			fuel = minf(100.0, fuel + JET_REGEN * mj * delta)

		# jump / bunny hop (coyote + buffer aware). Jump velocity scales with
		# mod_gravity so peak height feels the same under heavier gravity.
		if jump_buffer_t > 0.0 and coyote_t > 0.0:
			velocity.y = JUMP_VEL * mg
			# Scale the hop's lateral clamp by speed_mul so the Predator/Berserker
			# bonuses (and any host speed mod) can boost a hop above the base
			# BUNNY_SPEED cap — otherwise the powerup felt inert while airborne (#86.5).
			var hop_cap: float = BUNNY_SPEED * speed_mul
			velocity.x = clampf(velocity.x * 1.06, -hop_cap, hop_cap)
			coyote_t = 0.0
			jump_buffer_t = 0.0
			Sfx.jump()

		if not on_floor:
			velocity.y += GRAVITY * mg * delta
			velocity.y = minf(velocity.y, MAX_FALL)

	# aim — gamepad right stick when deflected past its deadzone, then the
	# Android touch overlay (#116) when present, mouse otherwise. Stick has to
	# come first: on a system with both a controller and a mouse a stationary
	# mouse must not overwrite active stick input, and a resting stick must not
	# overwrite mouse aim. The 0.2 threshold matches the aim_* action deadzone
	# set in controls_map.gd and keeps drift/idle jitter from twitching aim.
	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down", 0.2)
	if stick.length() > 0.0:
		aim_dir = stick.normalized()
		if absf(aim_dir.x) > 0.05:
			facing = signf(aim_dir.x)
	elif TouchControls.instance != null:
		# On Android the touch overlay writes to its own aim_dir on drag; we
		# copy it every tick so a released finger keeps the last aim (there's
		# no mouse to fall back on). Facing follows aim.x with the same 0.05
		# deadband used by the mouse path.
		var tc_aim: Vector2 = TouchControls.instance.aim_dir
		if tc_aim.length() > 0.001:
			aim_dir = tc_aim.normalized()
			if absf(aim_dir.x) > 0.05:
				facing = signf(aim_dir.x)
	else:
		var mouse := get_global_mouse_position()
		var to_mouse := mouse - global_position
		if to_mouse.length() > 1.0:
			aim_dir = to_mouse.normalized()
			# Small deadband around vertical so facing doesn't pop as the mouse crosses through x=0.
			if absf(aim_dir.x) > 0.05:
				facing = signf(aim_dir.x)

	move_and_slide()
	_update_wedge(delta)

	# primary weapon switching (keys 1..9,0). Numbers map to Soldat's classic slot order.
	if Input.is_action_pressed("weapon_1"):
		_switch_weapon(0)
	elif Input.is_action_pressed("weapon_2"):
		_switch_weapon(1)
	elif Input.is_action_pressed("weapon_3"):
		_switch_weapon(2)
	elif Input.is_action_pressed("weapon_4"):
		_switch_weapon(3)
	elif Input.is_action_pressed("weapon_5"):
		_switch_weapon(4)
	elif Input.is_action_pressed("weapon_6"):
		_switch_weapon(5)
	elif Input.is_action_pressed("weapon_7"):
		_switch_weapon(6)
	elif Input.is_action_pressed("weapon_8"):
		_switch_weapon(7)
	elif Input.is_action_pressed("weapon_9"):
		_switch_weapon(8)
	elif Input.is_action_pressed("weapon_10"):
		_switch_weapon(9)

	# Q toggles primary ↔ secondary — swap on the rising edge so a held key doesn't ping-pong.
	var q_now := Input.is_action_pressed("secondary_swap")
	if q_now and not q_prev:
		_toggle_secondary()
	q_prev = q_now

	# reload
	if Input.is_action_pressed("reload") and not reloading:
		_start_reload()

	# Grenade type toggle (G — rising edge only, matches Q swap pattern).
	# Cluster bonus (#78) locks use_cluster on for the whole duration so a stray
	# G tap can't flip us back to plain frag mid-effect.
	var g_now := Input.is_action_pressed("grenade_toggle")
	if g_now and not g_prev and bonus_kind != "cluster":
		use_cluster = not use_cluster
	g_prev = g_now

	# F — mount an M2 if we're standing on one, otherwise throw the current
	# weapon (issue #11). Mount only when we're not already mounted.
	# Gun Game: the rung IS the weapon — throwing it would strand you off
	# the ladder and hand the rung to whoever picks it up. Mount still works.
	var f_now := Input.is_action_pressed("weapon_throw")
	if f_now and not f_prev:
		var m2 := _find_nearby_m2()
		if m2 != null and mounted_m2 == null:
			m2.mount(self)
		elif Settings.game_mode != Settings.MODE_GG:
			_drop_active_weapon()
	f_prev = f_now

	# grenade — locked out in Gun Game so grenade kills can't skip the ladder.
	grenade_cd -= delta
	if Settings.game_mode != Settings.MODE_GG \
			and Input.is_action_pressed("grenade") and grenade_cd <= 0.0 and grenades > 0:
		_throw_grenade()
		grenade_cd = 0.6

	# shooting
	fire_cd -= delta
	var w_active: Dictionary = _active_weapon()
	if reloading:
		reload_t -= delta
		if reload_t <= 0.0:
			reloading = false
			_set_active_mag(int(w_active["mag"]))
	else:
		var lmb := Input.is_action_pressed("fire")
		# Wind-up trackers: Barrett/Minigun need to spin up before their first shot,
		# then fire at their normal rate as long as LMB stays down.
		var startup: float = float(w_active.get("startup", 0.0))
		if lmb:
			if startup > 0.0:
				# Play the spin-up tell on the rising edge of the trigger (before ramping)
				# and add a small wobble so the shake reads visually while ramping.
				if spin_up_t <= 0.0:
					Sfx.spinup(str(w_active["name"]))
				spin_up_t = minf(spin_up_t + delta, startup + 0.5)
				if spin_up_t < startup:
					_shake(1.2)
		else:
			spin_up_t = 0.0
		if lmb and fire_cd <= 0.0:
			var can_fire := true
			if startup > 0.0 and spin_up_t < startup:
				can_fire = false
			# Semi-auto: don't refire until LMB is released and re-pressed.
			if not bool(w_active.get("auto", false)) and lmb_prev:
				can_fire = false
			if can_fire:
				var kind_a := str(w_active.get("kind", "bullet"))
				if kind_a == "melee":
					_perform_melee()
				elif kind_a == "melee_cont":
					# Chainsaw taps its 200-round fuel tank per swing; when empty it
					# reloads like a firearm rather than draining into negative ammo.
					if _active_mag() > 0:
						_perform_melee()
					else:
						_start_reload()
				elif _active_mag() > 0:
					_shoot()
				else:
					Sfx.empty()
					fire_cd = 0.25
		lmb_prev = lmb

	muzzle_t = maxf(0.0, muzzle_t - delta * 10.0)
	melee_swing_t = maxf(0.0, melee_swing_t - delta)
	# Bink recovery: at 100 units/sec, a 65-Bink Barrett hit (0.65s) clears in ~2/3 second.
	bink_t = maxf(0.0, bink_t - delta * 100.0)
	# Bonus tick (#78). Every peer decrements its own copy; the clear callback
	# restores saved loadout state (see _clear_bonus_local). Self stays fully
	# visible under predator — modulate only dims for other viewers.
	if bonus_kind != "":
		bonus_t = maxf(0.0, bonus_t - delta)
		if bonus_t <= 0.0:
			_clear_bonus_local()
	modulate.a = 1.0
	if gesture_t > 0.0:
		gesture_t = maxf(0.0, gesture_t - delta)
		if gesture_t <= 0.0:
			gesture_anim = ""
	roll_t = maxf(0.0, roll_t - delta)
	roll_cd = maxf(0.0, roll_cd - delta)
	ceasefire_t = maxf(0.0, ceasefire_t - delta)

	# jet particles + sfx transitions
	if jet_on and not was_jet:
		Sfx.jet(true)
	elif not jet_on and was_jet:
		Sfx.jet(false)
	was_jet = jet_on
	jet_particles.emitting = jet_on and not Settings.lofi
	jet_particles.position = Vector2(-facing * 3.3, 1.7)

	# camera shake decay
	if shake > 0.0:
		cam.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake
		shake = maxf(0.0, shake - delta * 26.0)
	else:
		cam.offset = Vector2.ZERO

	queue_redraw()

	# Broadcast authoritative state to peers who have finished handshake (spawned us).
	# On host: parent Main tracks ready peers. On client: peer 1 (host) is always ready
	# because we only spawn locally after receiving spawn RPCs from host.
	if Net.is_networked() and multiplayer.has_multiplayer_peer():
		if Net.is_host():
			var m := get_parent()
			if m != null and m.has_method("ready_peer_ids"):
				for pid in m.ready_peer_ids():
					rpc_id(pid, "net_state", position, velocity, aim_dir, facing, jet_on, health, fuel, weapon_index, ammo[weapon_index], reloading, grenades, secondary_index, secondary_ammo[secondary_index], using_secondary, crouching, prone, climbing)
		else:
			# Broadcast so the host relays to other clients (Godot's server_relay).
			# Using rpc_id(1, ...) would freeze non-host peers' views of this body.
			rpc("net_state", position, velocity, aim_dir, facing, jet_on, health, fuel, weapon_index, ammo[weapon_index], reloading, grenades, secondary_index, secondary_ammo[secondary_index], using_secondary, crouching, prone, climbing)


# ── /command console (gestures) ────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if dead:
		return
	# Only the local (authority) player opens the console.
	if multiplayer.multiplayer_peer != null and not is_multiplayer_authority():
		return
	if input_locked:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var parent := get_parent()
	var hud = null
	if parent != null and parent.get("hud") != null:
		hud = parent.hud
	# Taunt-modifier + a..z / 0..9 → send a canned taunt over global chat.
	# `taunt` is rebindable (defaults to ALT); we poll live rather than reading
	# event.alt_pressed so custom binds like F1+letter still work.
	if Input.is_action_pressed("taunt") and hud != null:
		var ch := ""
		var kc: int = event.keycode
		if kc >= KEY_A and kc <= KEY_Z:
			ch = String.chr(kc + 32)
		elif kc >= KEY_0 and kc <= KEY_9:
			ch = String.chr(kc)
		if ch != "":
			var msg: String = hud.get_taunt(ch)
			if msg != "":
				send_chat("global", msg)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("chat"):
		if hud != null:
			hud.open_chat("global")
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("team_chat"):
		if hud != null:
			hud.open_chat("team")
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("command"):
		if hud != null:
			hud.open_command()
			get_viewport().set_input_as_handled()


func send_chat(scope: String, msg: String) -> void:
	var m := msg.strip_edges()
	if m == "":
		return
	var parent := get_parent()
	if parent == null:
		return
	if Net.is_networked():
		if parent.has_method("net_chat"):
			parent.rpc("net_chat", display_name, m, scope, team)
	else:
		if parent.get("hud") != null and parent.hud.has_method("post_chat"):
			parent.hud.post_chat(display_name, m, scope == "team")


func apply_gesture(cmd_raw: String) -> void:
	# Local + broadcast in MP. `cmd_raw` is stripped, lower-cased, no leading slash.
	var cmd := cmd_raw.strip_edges().to_lower()
	if cmd.begins_with("/"):
		cmd = cmd.substr(1)
	if cmd == "":
		return
	if Net.is_networked():
		rpc("net_gesture", cmd)
	else:
		net_gesture(cmd)


@rpc("authority", "call_local", "reliable")
func net_gesture(cmd: String) -> void:
	match cmd:
		"victory":
			gesture_anim = "cieszy"
			gesture_t = 1.6
		"smoke", "tabac":
			gesture_anim = "cigar"
			gesture_t = 2.4
		"takeoff":
			gesture_anim = "wyrzuca"
			gesture_t = 1.4
		"mercy":
			gesture_anim = "bije"
			gesture_t = 0.6
			# Delay the harakiri so the punch/mercy anim reads before we drop.
			if multiplayer.multiplayer_peer == null or is_multiplayer_authority():
				get_tree().create_timer(0.6).timeout.connect(func() -> void:
					if is_instance_valid(self) and not dead:
						take_damage(999.0, display_name, "Mercy", team))
		"kill":
			if multiplayer.multiplayer_peer == null or is_multiplayer_authority():
				take_damage(999.0, display_name, "Suicide", team)
		"brutalkill":
			if multiplayer.multiplayer_peer == null or is_multiplayer_authority():
				take_damage(999.0, display_name, "Brutal", team)
		_:
			pass


func _is_primary_unlocked(idx: int) -> bool:
	if not Settings.advance:
		return true
	if idx < 0 or idx >= ADV_PRIMARY_UNLOCK.size():
		return false
	return advance_kills >= ADV_PRIMARY_UNLOCK[idx]


func _is_secondary_unlocked(idx: int) -> bool:
	if not Settings.advance:
		return true
	if idx < 0 or idx >= ADV_SECONDARY_UNLOCK.size():
		return false
	return advance_kills >= ADV_SECONDARY_UNLOCK[idx]


func advance_receive_kill() -> PackedStringArray:
	# Called by Main._on_kill_scored on the killer. Bumps the kill counter and
	# auto-equips any weapon that just unlocked so the player can try it now.
	var out := PackedStringArray()
	if not Settings.advance:
		return out
	advance_kills += 1
	for i in ADV_PRIMARY_UNLOCK.size():
		if advance_kills == ADV_PRIMARY_UNLOCK[i]:
			out.append(str(weapons[i]["name"]))
			weapon_index = i
			ammo[i] = int(weapons[i]["mag"])
			using_secondary = false
			reloading = false
			reload_t = 0.0
	for i in ADV_SECONDARY_UNLOCK.size():
		if advance_kills == ADV_SECONDARY_UNLOCK[i]:
			out.append(str(secondary[i]["name"]))
			secondary_index = i
			secondary_ammo[i] = int(secondary[i]["mag"])
	return out


func _switch_weapon(idx: int) -> void:
	# Gun Game: your rung IS your weapon. Number-key / hotkey switching is locked.
	if Settings.game_mode == Settings.MODE_GG:
		return
	# Berserker bonus (#78) locks the soldier into the knife slot for the
	# effect duration — swapping to a primary would defeat "no primary use".
	if bonus_kind == "berserker":
		return
	# Advance: block hotkeys pointing to still-locked primaries.
	if Settings.advance and not _is_primary_unlocked(idx):
		return
	# #87: block hotkeys pointing at a weapon we've thrown away.
	if _is_thrown(str(weapons[idx]["name"])):
		return
	# Any primary hotkey while holding secondary swaps us back to a primary AND
	# picks the requested slot — Soldat's classic behavior.
	if using_secondary:
		using_secondary = false
		reloading = false
		reload_t = 0.0
		spin_up_t = 0.0
		lmb_prev = true  # require a fresh click before firing after a slot swap
	if idx == weapon_index:
		return
	# Allow switching mid-reload to cancel it — otherwise the player is hard-locked
	# for LAW's 3s or Spas's 2.5s with no way to defend.
	if reloading:
		reloading = false
		reload_t = 0.0
	weapon_index = idx
	fire_cd = 0.15
	spin_up_t = 0.0
	lmb_prev = true


func _toggle_secondary() -> void:
	# Gun Game: rung IS the weapon — Q swap is locked.
	if Settings.game_mode == Settings.MODE_GG:
		return
	# Berserker locks us on the knife slot (#78) — Q would take us back to
	# a primary, undoing the effect.
	if bonus_kind == "berserker":
		return
	# Advance: don't swap into a slot whose weapon isn't unlocked yet.
	if Settings.advance:
		if using_secondary and not _is_primary_unlocked(weapon_index):
			return
		if not using_secondary and not _is_secondary_unlocked(secondary_index):
			return
	# Weapon drop (#87): don't Q into a slot whose active weapon we just threw
	# away — otherwise Q silently restores a supposedly-discarded weapon.
	if using_secondary:
		if _is_thrown(str(weapons[weapon_index]["name"])):
			return
	else:
		if _is_thrown(str(secondary[secondary_index]["name"])):
			return
	using_secondary = not using_secondary
	if reloading:
		reloading = false
		reload_t = 0.0
	fire_cd = 0.15
	spin_up_t = 0.0
	lmb_prev = true


func _apply_gg_weapon() -> void:
	# Snap the active weapon to the current gg_level rung. Called on spawn and on
	# every level change. Fills the target slot's mag so the new rung is usable
	# immediately (no forced reload) and cancels an in-progress reload.
	if gg_level < 0:
		return
	var rung: Dictionary = GG_LADDER[mini(gg_level, GG_LADDER.size() - 1)]
	var idx: int = int(rung["idx"])
	if bool(rung["sec"]):
		if idx < 0 or idx >= secondary.size():
			return
		secondary_index = idx
		using_secondary = true
		if idx < secondary_ammo.size():
			secondary_ammo[idx] = int(secondary[idx]["mag"])
	else:
		if idx < 0 or idx >= weapons.size():
			return
		weapon_index = idx
		using_secondary = false
		if idx < ammo.size():
			ammo[idx] = int(weapons[idx]["mag"])
	reloading = false
	reload_t = 0.0
	fire_cd = 0.15
	spin_up_t = 0.0
	lmb_prev = true


func _active_weapon() -> Dictionary:
	return secondary[secondary_index] if using_secondary else weapons[weapon_index]


func _active_mag() -> int:
	return secondary_ammo[secondary_index] if using_secondary else ammo[weapon_index]


func _set_active_mag(val: int) -> void:
	if using_secondary:
		secondary_ammo[secondary_index] = val
	else:
		ammo[weapon_index] = val


func _dec_active_mag() -> void:
	_set_active_mag(_active_mag() - 1)


func _bink_for(weapon_name: String) -> float:
	# Strip the "(headshot)" suffix bullet.gd appends so the lookup still matches.
	weapon_name = weapon_name.replace(" (headshot)", "")
	# Linear scan is fine here — <20 entries and this only runs on hit.
	for w in weapons:
		if str(w["name"]) == weapon_name:
			return float(w.get("bink", 0.0))
	for w in secondary:
		if str(w["name"]) == weapon_name:
			return float(w.get("bink", 0.0))
	return 0.0


func _apply_stance_shape() -> void:
	if col_shape == null:
		return
	var want: RectangleShape2D = shape_stand
	if prone:
		want = shape_prone
	elif crouching:
		want = shape_crouch
	# Headroom guard: growing taller (prone→crouch/stand, crouch→stand) under a
	# low ceiling used to shove the box into the terrain and wedge the soldier.
	# If the taller box doesn't fit, stay in the tallest stance that does.
	var cur: RectangleShape2D = col_shape.shape as RectangleShape2D
	if cur != null and want.size.y > cur.size.y and not _stance_fits(want):
		if want == shape_stand and _stance_fits(shape_crouch):
			want = shape_crouch
			crouching = true
			prone = false
		else:
			want = cur
			prone = cur == shape_prone
			crouching = cur == shape_crouch
	if col_shape.shape != want:
		# Feet-anchored swap (#72): the box bottom stays at the body origin, so
		# changing height only moves the top — no body nudge needed, and the
		# soldier neither micro-falls on crouch nor pops out of the floor on stand.
		col_shape.set_deferred("shape", want)
		col_shape.set_deferred("position", Vector2(0, -want.size.y * 0.5))


func _stance_fits(shape: RectangleShape2D) -> bool:
	# Would this (feet-anchored) stance box overlap static terrain right now?
	if not is_inside_tree():
		return true
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, global_position + Vector2(0, -shape.size.y * 0.5 - 0.5))
	q.collision_mask = collision_mask
	q.collide_with_areas = false
	q.exclude = [get_rid()]
	q.margin = -0.5
	for hit in get_world_2d().direct_space_state.intersect_shape(q, 4):
		if hit.get("collider") is StaticBody2D:
			return false
	return true


func _start_reload() -> void:
	var w := _active_weapon()
	if _active_mag() >= int(w["mag"]):
		return
	# Knife swings can't be "reloaded" — skip so R doesn't lock the swing cooldown.
	# Chainsaw (melee_cont) does refuel from its fixed tank when it hits zero.
	var kind_r := str(w.get("kind", "bullet"))
	if kind_r == "melee":
		return
	reloading = true
	reload_t = float(w["reload"])
	Sfx.reload(str(w["name"]))


func _shoot() -> void:
	var w := _active_weapon()
	_dec_active_mag()
	fire_cd = float(w["rate"])
	ceasefire_t = 0.0
	# Predator bonus (#78) breaks the instant we open fire.
	_break_predator_if_active()
	# Local stats: only count the human player's trigger pulls (bots have their own tally in-file, off-Stats).
	if multiplayer.multiplayer_peer == null or is_multiplayer_authority():
		Stats.record_shot()  # firing forfeits spawn protection
	var kind_s := str(w.get("kind", "bullet"))
	var recoil := 240.0 if (kind_s == "rocket" or kind_s == "launcher") else 35.0
	velocity -= aim_dir * recoil
	# Bink penalty: bink_t (0..100) adds up to ~0.18 rad extra spread when maxed.
	var extra_spread := (bink_t / 100.0) * 0.18
	var total_spread := float(w["spread"]) + extra_spread
	var dirs := PackedVector2Array()
	for _i in int(w["pellets"]):
		dirs.append(aim_dir.rotated(randf_range(-total_spread, total_spread)))
	var muzzle: Vector2 = global_position + SoldierArt.muzzle_local(self, aim_dir, facing, str(w["name"]))
	var slot := (100 + secondary_index) if using_secondary else weapon_index
	if Net.is_networked():
		# Mint a base projectile id for this shot — rocket path uses id, id+1, ...
		# per pellet so each rocket gets a unique node path on every peer (#61).
		var base_id := _next_proj_id
		_next_proj_id += maxi(1, int(w["pellets"]))
		rpc("net_shoot", muzzle, dirs, slot, base_id)
	else:
		net_shoot(muzzle, dirs, slot, 0)
	if _active_mag() <= 0:
		_start_reload()


# Melee swing / continuous scan. Applies damage to any enemy soldier within a
# short arc in front of us. Called on LMB in-range for Knife/Chainsaw.
func _perform_melee() -> void:
	var w := _active_weapon()
	fire_cd = float(w["rate"])
	ceasefire_t = 0.0
	# Predator breaks on melee swing too — any offensive action reveals us.
	_break_predator_if_active()
	var kind_m := str(w.get("kind", "melee"))
	# Broadcast so all peers see the swing feedback (muzzle flash + sfx). Damage
	# is applied inside net_shoot with the standard authority guard.
	var slot := (100 + secondary_index) if using_secondary else weapon_index
	var muzzle: Vector2 = global_position + SoldierArt.muzzle_local(self, aim_dir, facing, str(w["name"]))
	# `dirs` carries the swing direction as a single unit vector; range is looked
	# up from the weapon dict on the receiving side.
	var dirs := PackedVector2Array([aim_dir])
	if Net.is_networked():
		rpc("net_shoot", muzzle, dirs, slot, 0)
	else:
		net_shoot(muzzle, dirs, slot, 0)
	# Show a brief punch pose (bije) on each swing — clears itself in _physics_process.
	melee_swing_t = 0.25
	# Chainsaw taps its 200-mag "fuel" per swing; Knife is effectively unlimited.
	# When the fuel hits 0 the caller in _physics_process triggers the reload —
	# don't kick it off here so a swing on the last tick still lands damage.
	if kind_m == "melee_cont":
		_dec_active_mag()


func _find_nearby_m2() -> Node2D:
	for m in get_tree().get_nodes_in_group("m2_gun"):
		if not is_instance_valid(m):
			continue
		if m.get("operator") != null:
			continue
		if global_position.distance_to(m.global_position) < 32.0:
			return m
	return null


func _find_ladder_overlap() -> Node2D:
	# Rect-vs-rect between the soldier body (feet-anchored, ~14×24) and each
	# ladder Area2D's stored bounds. Picks the ladder whose center-x is closest
	# so a soldier straddling two ladders latches onto the nearer one.
	var pcx: float = global_position.x
	var pfeet: float = global_position.y
	var phead: float = pfeet - CLIMB_BODY_PAD_TOP
	var closest: Node2D = null
	var best_dx: float = 1e9
	for lad in get_tree().get_nodes_in_group("ladder"):
		if not is_instance_valid(lad):
			continue
		var lx: float = float(lad.get_meta("center_x", lad.global_position.x))
		var half_w: float = float(lad.get_meta("half_w", 10.0))
		var top: float = float(lad.get_meta("top_y", lad.global_position.y - 60.0))
		var bot: float = float(lad.get_meta("bottom_y", lad.global_position.y + 60.0))
		var dx: float = absf(pcx - lx)
		# X overlap — body half-width ~8 covers both stand + prone stances.
		if dx > half_w + 8.0:
			continue
		# Y overlap — pad the ladder a hair so climbing off the top is smooth.
		if pfeet + CLIMB_BODY_PAD_BOTTOM < top - 2.0 or phead > bot + 2.0:
			continue
		if dx < best_dx:
			best_dx = dx
			closest = lad
	return closest


func mount_m2(m2: Node2D) -> void:
	mounted_m2 = m2


func dismount_m2() -> void:
	mounted_m2 = null


func _drop_active_weapon() -> void:
	# Gun Game locks the rung to the weapon — dropping would strand the player on
	# a non-ladder slot until their next kill re-applies _apply_gg_weapon. Also
	# lets a Knife-rung player free-toss a damaging knife pickup on cooldown.
	# Disable F throw entirely in GG.
	if Settings.game_mode == Settings.MODE_GG:
		return
	var w := _active_weapon()
	var wname := str(w["name"])
	var wmag := _active_mag()
	_thrown[wname] = true
	# Mirror _throw_grenade: throwing a weapon (esp. a Knife pickup that deals
	# contact damage) is an offensive action — drop spawn protection and break
	# Predator invisibility so the thrower can't remain invulnerable/hidden.
	ceasefire_t = 0.0
	_break_predator_if_active()
	if Net.is_networked():
		# Route through the host so only one authoritative RigidBody2D exists per drop.
		# Clients used to spawn their own physics copy that diverged frame to frame.
		if Net.is_host():
			net_drop_weapon(wname, global_position, aim_dir, wmag)
		else:
			rpc_id(1, "net_request_drop", wname, global_position, aim_dir, wmag)
	else:
		net_drop_weapon(wname, global_position, aim_dir, wmag)
	_switch_after_drop()


func _is_thrown(wname: String) -> bool:
	return _thrown.has(wname)


func _first_non_thrown(arr: Array) -> int:
	for i in arr.size():
		if not _is_thrown(str(arr[i]["name"])):
			return i
	return -1


func _switch_after_drop() -> void:
	# Drop the just-thrown weapon from our hands. Prefer the opposite slot, then
	# the first non-thrown weapon in the same slot; if everything is thrown we
	# keep holding the thrown one (it still fires). Respect the Advance-mode
	# unlock gates — dropping the primary was a silent way to jump into a
	# still-locked secondary otherwise.
	if using_secondary:
		var pi := _first_non_thrown_unlocked(weapons, false)
		if pi >= 0:
			_switch_weapon(pi)
			return
		var si := _first_non_thrown_unlocked(secondary, true)
		if si >= 0:
			secondary_index = si
			using_secondary = true
			reloading = false
			reload_t = 0.0
			fire_cd = 0.15
			lmb_prev = true
	else:
		var si := _first_non_thrown_unlocked(secondary, true)
		if si >= 0:
			secondary_index = si
			using_secondary = true
			reloading = false
			reload_t = 0.0
			fire_cd = 0.15
			lmb_prev = true
			return
		var pi := _first_non_thrown_unlocked(weapons, false)
		if pi >= 0:
			_switch_weapon(pi)


func _first_non_thrown_unlocked(arr: Array, is_secondary: bool) -> int:
	for i in arr.size():
		if _is_thrown(str(arr[i]["name"])):
			continue
		if Settings.advance:
			if is_secondary and not _is_secondary_unlocked(i):
				continue
			if not is_secondary and not _is_primary_unlocked(i):
				continue
		return i
	return -1


@rpc("any_peer", "reliable")
func net_request_drop(weapon_name: String, from_pos: Vector2, aim: Vector2, mag: int = -1) -> void:
	if not Net.is_host():
		return
	# Validate: the sender must actually own this body, be alive, and hold the
	# weapon they're dropping. Otherwise a modded client can spawn arbitrary
	# pickups (LAW, Barrett, …) by RPCing net_request_drop with any name.
	var sender := multiplayer.get_remote_sender_id()
	if sender != int(get_multiplayer_authority()):
		return
	if dead:
		return
	if not _loadout_has(weapon_name):
		return
	if _thrown.has(weapon_name):
		return
	# Rate-limit repeated drops (throw cooldown lives on the client; enforce a
	# floor here too so a hostile client can't spam pickup spawns).
	var now := Time.get_ticks_msec()
	if now - _last_drop_ms < 200:
		return
	_last_drop_ms = now
	# Snap the pickup to the player's authoritative position — client-reported
	# from_pos is a hint only. Clamp mag so a modded client can't over-refill on
	# next pickup (upper bound is the weapon's max; -1 = "full" is banned here
	# because a client-hostile default would otherwise turn drop+pickup into a
	# free reload).
	var max_mag: int = _loadout_mag(weapon_name)
	var clamped: int = clampi(mag, 0, max_mag) if mag >= 0 else 0
	net_drop_weapon(weapon_name, global_position, aim, clamped)


func _loadout_has(weapon_name: String) -> bool:
	for w in weapons:
		if str(w["name"]) == weapon_name:
			return true
	for w in secondary:
		if str(w["name"]) == weapon_name:
			return true
	return false


func _loadout_mag(weapon_name: String) -> int:
	for w in weapons:
		if str(w["name"]) == weapon_name:
			return int(w["mag"])
	for w in secondary:
		if str(w["name"]) == weapon_name:
			return int(w["mag"])
	return 0


func try_pickup_weapon(weapon_name: String, mag: int = -1) -> bool:
	# Only the authority peer mutates the loadout — otherwise net_state loops.
	if multiplayer.multiplayer_peer != null and not is_multiplayer_authority():
		return false
	# Only clear the thrown flag if the pickup we're absorbing is one WE threw —
	# otherwise walking over a stranger's pickup silently re-arms a thrown weapon
	# without picking it up (was a free-refill exploit via #87).
	var was_thrown_by_me: bool = _thrown.has(weapon_name)
	var picked: bool = false
	for i in weapons.size():
		if str(weapons[i]["name"]) == weapon_name:
			# -1 preserves legacy full-mag behaviour (world pickups, tests). A
			# drop-and-pickup passes the actual mag so empty→pickup can't refill.
			var full: int = int(weapons[i]["mag"])
			ammo[i] = full if mag < 0 else clampi(mag, 0, full)
			weapon_index = i
			using_secondary = false
			reloading = false
			reload_t = 0.0
			picked = true
			break
	if not picked:
		for i in secondary.size():
			if str(secondary[i]["name"]) == weapon_name:
				var full: int = int(secondary[i]["mag"])
				secondary_ammo[i] = full if mag < 0 else clampi(mag, 0, full)
				secondary_index = i
				using_secondary = true
				reloading = false
				reload_t = 0.0
				picked = true
				break
	if picked and was_thrown_by_me:
		_thrown.erase(weapon_name)
	# Gun Game: keep the rung/weapon coupling intact — re-snap to the current
	# gg_level's weapon so a stray pickup can't force us out of our rung slot.
	if picked and Settings.game_mode == Settings.MODE_GG:
		_apply_gg_weapon()
	return picked


@rpc("any_peer", "call_local", "reliable")
func net_remote_pickup(weapon_name: String, mag: int = -1) -> void:
	# Host-authoritative pickup contact routed to the body's owning peer (#83).
	# Only host may originate — local invocation (sender_id 0) is only valid on host.
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
	# Host-authoritative knife-contact damage routed to the victim's owning peer (#83).
	if multiplayer.multiplayer_peer != null:
		var sender := multiplayer.get_remote_sender_id()
		if sender == 0:
			if not Net.is_host():
				return
		elif sender != 1:
			return
	take_damage(amount, killer, weapon, killer_team)


func _throw_grenade() -> void:
	grenades -= 1
	Sfx.grenade_throw()
	ceasefire_t = 0.0
	_break_predator_if_active()
	var toss := (aim_dir + Vector2(0, -0.55)).normalized()
	var target_pos := global_position + aim_dir * 22.0
	# Short raycast so point-blank wall throws don't spawn the RigidBody2D inside geometry.
	var g_pos := target_pos
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, target_pos)
	query.exclude = [self]
	var hit := space.intersect_ray(query)
	if hit.has("position"):
		g_pos = (hit["position"] as Vector2) - aim_dir * 4.0
	var g_vel := toss * 480.0
	var g_ang := randf_range(-8.0, 8.0)
	if Net.is_networked():
		var pid := _next_proj_id
		_next_proj_id += 1
		rpc("net_grenade", g_pos, g_vel, g_ang, use_cluster, pid)
	else:
		net_grenade(g_pos, g_vel, g_ang, use_cluster, 0)


func _shake(amount: float) -> void:
	# Screen shake is now a 0..2 intensity slider (#73). 0 = fully disabled;
	# 1.0 preserves the old feel; up to 2 for players who like it punchier.
	var mag: float = float(Settings.screen_shake_intensity)
	if mag <= 0.001:
		return
	shake = maxf(shake, amount * mag)


func take_damage(amount: float, killer := "", weapon := "", killer_team := -1) -> void:
	if dead:
		return
	# Damage is only computed on the victim's authority in MP — guard against accidental
	# non-authority callers so they don't spam authority-check errors down the death path.
	if multiplayer.multiplayer_peer != null and not is_multiplayer_authority():
		return
	# Ceasefire (spawn protection) — soaks incoming damage until it expires or we shoot.
	if ceasefire_t > 0.0 and killer != display_name:
		return
	# Bulletproof Vest bonus (#78) — halves incoming damage. Self-damage
	# (harakiri / suicide gestures) still applies at full so /kill still works.
	if bonus_kind == "vest" and killer != display_name:
		amount *= 0.5
	health -= amount
	# Bink kick: apply extra spread proportional to the weapon's Bink stat while active.
	# bink_t caps at 100 so successive hits don't stack past the max penalty.
	var bv := _bink_for(weapon)
	if bv > 0.0:
		bink_t = minf(100.0, bink_t + bv)
	_shake(7.0)
	if killer != "":
		last_killer = killer
		last_weapon = weapon
		last_killer_team = killer_team
	if health <= 0.0:
		if Net.is_networked():
			rpc("net_die", last_killer, last_weapon, last_killer_team)
		else:
			_die()


func _die() -> void:
	if dead:
		return
	dead = true
	Sfx.gib()
	if Net.is_networked():
		# Host emits (not victim) so the kill is not lost if the dying client disconnects
		# between take_damage and the RPC flush.
		if Net.is_host():
			var m := get_parent()
			if m != null:
				m.rpc("net_kill_feed", last_killer, display_name, last_weapon, last_killer_team, team)
	else:
		_emit_kill()
	# defer FX spawn out of the physics flush (bullet body_entered → take_damage path)
	# Lo-fi (#25): skip the CPUParticles2D burst + physics gib pieces on low-end PCs.
	if not Settings.lofi:
		_spawn_gibs.call_deferred()
		_spawn_ragdoll.call_deferred()
	died.emit()
	if Net.is_networked() and Net.is_host():
		# Main owns the timer: a lambda on this (about to be freed) body could
		# be dropped, and the delay must match what the death screen shows.
		var m := get_parent()
		if m != null and m.has_method("_schedule_peer_respawn"):
			m._schedule_peer_respawn(get_multiplayer_authority(), int(team))
	queue_free()


func _emit_kill() -> void:
	if last_killer == "":
		return
	var parent := get_parent()
	if parent != null and parent.has_signal("kill"):
		parent.emit_signal("kill", last_killer, display_name, last_weapon, last_killer_team, team)


# Between-round clean-slate reset (issue #58). Called by main.gd::_reset_round for
# every LIVING soldier in non-survival modes so the next round doesn't start with
# mid-fight HP/ammo. Dead-and-respawning soldiers keep their existing timer path.
# Position is set by the caller (spawn-slot picker); this only restores state.
func restore_for_round() -> void:
	if dead:
		return
	health = 100.0
	fuel = 100.0
	velocity = Vector2.ZERO
	for i in ammo.size():
		ammo[i] = int(weapons[i]["mag"])
	for i in secondary_ammo.size():
		secondary_ammo[i] = int(secondary[i]["mag"])
	grenades = 3
	reloading = false
	reload_t = 0.0
	fire_cd = 0.0
	spin_up_t = 0.0
	lmb_prev = true
	muzzle_t = 0.0
	gesture_anim = ""
	gesture_t = 0.0
	bink_t = 0.0
	roll_t = 0.0
	roll_cd = 0.0
	melee_swing_t = 0.0
	ceasefire_t = CEASEFIRE_SECS
	# #87: thrown weapons come back on the clean-slate reset.
	_thrown.clear()
	# Gun Game: round reset clears the ladder for a fresh race.
	if Settings.game_mode == Settings.MODE_GG:
		gg_level = 0
		_apply_gg_weapon()


# ── RPCs ──────────────────────────────────────────────

@rpc("authority", "call_remote", "unreliable_ordered")
func net_state(pos: Vector2, vel: Vector2, aim: Vector2, face: float, jetting: bool, hp: float, fuel_val: float, wi: int, mag: int, is_reloading: bool, grens: int, sec_i: int, sec_mag: int, use_sec: bool, crouch_f: bool, prone_f: bool, climb_f: bool = false) -> void:
	position = pos
	velocity = vel
	aim_dir = aim
	facing = face
	jet_on = jetting
	health = hp
	fuel = fuel_val
	if wi >= 0 and wi < weapons.size():
		weapon_index = wi
		if ammo.size() > wi:
			ammo[wi] = mag
	if sec_i >= 0 and sec_i < secondary.size():
		secondary_index = sec_i
		if secondary_ammo.size() > sec_i:
			secondary_ammo[sec_i] = sec_mag
	using_secondary = use_sec
	crouching = crouch_f
	prone = prone_f
	# #90: sync climb pose so remote peers see the standing/climbing frame
	# instead of a jumping/falling one (net_state's vel.y goes ±CLIMB_SPEED
	# during a climb which otherwise picks "spada" / "skok").
	climbing = climb_f
	_apply_stance_shape()
	reloading = is_reloading
	grenades = maxi(0, grens)


@rpc("authority", "call_local", "reliable")
func net_shoot(shot_pos: Vector2, dirs: PackedVector2Array, weapon_i: int, base_proj_id: int = 0) -> void:
	# Slots ≥ 100 are secondaries at (slot - 100).
	var w: Dictionary
	if weapon_i >= 100:
		var si := weapon_i - 100
		if si < 0 or si >= secondary.size():
			return
		w = secondary[si]
	else:
		if weapon_i < 0 or weapon_i >= weapons.size():
			return
		w = weapons[weapon_i]
	var kind := str(w.get("kind", "bullet"))
	var is_explosive := kind == "rocket" or kind == "launcher"
	muzzle_t = 0.10 if is_explosive else 0.08
	_shake(6.0 if is_explosive else 3.5)
	Sfx.shoot(str(w["name"]))
	if kind == "melee" or kind == "melee_cont":
		var swing: Vector2 = dirs[0] if dirs.size() > 0 else aim_dir
		var reach: float = float(w.get("range", 32.0))
		var dmg: float = float(w["damage"]) * MatchConfig.mod_damage()
		# Berserker bonus (#78) — one-hit-kill melee. 999 blows through vest halving.
		if bonus_kind == "berserker":
			dmg = 999.0
		# Scan soldiers in a short forward arc — apply damage on the authority peer
		# only (matches how bullet/rocket damage is gated in bullet.gd/rocket.gd).
		for s in get_tree().get_nodes_in_group("soldier"):
			if s == self or not is_instance_valid(s):
				continue
			if bool(s.get("dead")):
				continue
			# Team-mate swings pass through unless host FF is on (#74). Self-melee
			# isn't a thing here (we already skip s == self above).
			if int(s.get("team")) == team and not MatchConfig.friendly_fire_on():
				continue
			var to_s: Vector2 = s.global_position - global_position
			var d: float = to_s.length()
			if d > reach or d < 1.0:
				continue
			if to_s.normalized().dot(swing) < 0.35:  # ~70° arc
				continue
			if s.has_method("take_damage") and (multiplayer.multiplayer_peer == null or s.is_multiplayer_authority()):
				s.take_damage(dmg, display_name, str(w["name"]), team)
		return
	for i in dirs.size():
		var bdir: Vector2 = dirs[i]
		if kind == "rocket" or kind == "launcher":
			var r := rocket_scene.instantiate()
			# #61: shooter mints a deterministic id via `base_proj_id + i` so every
			# peer names the same rocket the same way (needed for per-projectile RPC
			# dispatch to hit the matching node).
			if Net.is_networked() and base_proj_id > 0:
				r.name = "Rocket_%d_%d" % [get_multiplayer_authority(), base_proj_id + i]
			r.global_position = shot_pos + bdir * 4.0
			r.direction = bdir
			r.speed = float(w["speed"])
			r.damage = float(w["damage"]) * MatchConfig.mod_damage()
			r.team = team
			r.killer_name = display_name
			r.weapon_name = str(w["name"])
			# M79 (launcher) lobs — grav>0 flips rocket.gd into ballistic mode.
			r.grav = float(w.get("gravity", 0.0))
			get_parent().add_child(r)
			if Net.is_networked() and base_proj_id > 0:
				r.set_multiplayer_authority(get_multiplayer_authority())
		else:
			var b := bullet_scene.instantiate()
			b.global_position = shot_pos + bdir * 4.0
			b.direction = bdir
			b.speed = float(w["speed"])
			b.damage = float(w["damage"]) * MatchConfig.mod_damage()
			b.team = team
			b.killer_name = display_name
			b.weapon_name = str(w["name"])
			# Kind-specific visuals + physics — flames die fast, arrows sag.
			if kind == "flame":
				b.visual = "flame"
				b.life = float(w.get("life", 0.35))
			elif kind == "arrow":
				b.visual = "arrow"
				b.grav = float(w.get("gravity", 0.0))
			get_parent().add_child(b)


@rpc("authority", "call_local", "reliable")
func net_grenade(g_pos: Vector2, g_vel: Vector2, g_ang: float, cluster: bool = false, proj_id: int = 0) -> void:
	var g := grenade_scene.instantiate()
	# #61: name so every peer's replica lives at the same NodePath — required for
	# per-projectile state RPCs. proj_id==0 is SP; no rename / no authority swap.
	if Net.is_networked() and proj_id > 0:
		g.name = "Grenade_%d_%d" % [get_multiplayer_authority(), proj_id]
	g.global_position = g_pos
	g.team = team
	g.killer_name = display_name
	g.linear_velocity = g_vel
	g.angular_velocity = g_ang
	g.cluster = cluster
	if cluster:
		# Cluster acts as a mid-air airburst — shorter fuse feels correct, and Dmg 1500-like
		# comes from the fragment cascade, not the initial pop.
		g.fuse = 1.4
		g.damage = 40.0
	if Net.is_networked() and proj_id > 0:
		g.set_multiplayer_authority(get_multiplayer_authority())
	get_parent().add_child(g)


@rpc("authority", "call_local", "reliable")
func net_drop_weapon(weapon_name: String, from_pos: Vector2, aim: Vector2, mag: int = -1) -> void:
	var wp := WeaponPickup.new()
	wp.weapon_name = weapon_name
	wp.team = team
	wp.thrower_name = display_name
	wp.damage_on_hit = 55.0 if weapon_name == "Knife" else 0.0
	# Persist thrown magazine count so pickup grants the same rounds instead of a
	# free refill (empty→drop→pickup was an infinite-ammo exploit).
	wp.mag_on_drop = mag
	wp.global_position = from_pos + aim * 20.0
	wp.linear_velocity = aim * 520.0 + Vector2(0, -160.0)
	wp.angular_velocity = randf_range(-8.0, 8.0)
	# In MP the host assigns a stable id so state broadcasts can address this pickup;
	# SP or client-locally-spawned drops don't need one.
	if Net.is_networked() and Net.is_host():
		var m := get_parent()
		if m != null and m.has_method("next_pickup_id"):
			wp.pickup_id = int(m.next_pickup_id())
			# #69: stable name so both peers refer to this pickup by the same path.
			wp.name = "Pickup_%d" % wp.pickup_id
	var parent := get_parent()
	if parent != null:
		parent.add_child(wp)


@rpc("authority", "call_local", "reliable")
func net_die(killer: String, weapon: String, killer_team: int) -> void:
	last_killer = killer
	last_weapon = weapon
	last_killer_team = killer_team
	_die()


func _spawn_gibs() -> void:
	# Deferred from _die: the scene may be changing (round/map switch) by now.
	if not is_inside_tree() or get_parent() == null:
		return
	# Blood/gore visual density is user-tunable (#73). 0 = skip entirely
	# (lo-fi already gates this, but tie the slider to a hard skip too).
	var density: float = clampf(float(Settings.blood_intensity), 0.0, 1.5)
	if density <= 0.01:
		return
	var p := CPUParticles2D.new()
	p.amount = maxi(1, int(60.0 * density))
	p.lifetime = 0.8
	p.explosiveness = 1.0
	p.one_shot = true
	p.emitting = true
	p.global_position = global_position
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = Vector2(0, 620)
	p.initial_velocity_min = 140.0
	p.initial_velocity_max = 480.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 6.0
	p.color = Color(0.9, 0.15, 0.15)
	get_parent().add_child(p)
	get_tree().create_timer(1.3).timeout.connect(p.queue_free)


func _spawn_ragdoll() -> void:
	# Deferred from _die: the scene may be changing (round/map switch) by now.
	if not is_inside_tree() or get_parent() == null:
		return
	# Scale ragdoll piece count with blood_intensity (#73) so lo-gore players
	# get a cleaner corpse. Rounds up to at least 1 piece so the death still reads.
	var density: float = clampf(float(Settings.blood_intensity), 0.0, 1.5)
	var count := maxi(1, int(round(8.0 * density)))
	if density <= 0.01:
		return
	for _i in count:
		var body := RigidBody2D.new()
		# Gibs are purely cosmetic — zero collision so a settled chunk can never
		# snag the player/bots (everything lives on layer 1, so a default
		# RigidBody2D would collide with soldiers and trap them in the gore).
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
		body.linear_velocity = Vector2(randf_range(-280.0, 280.0), randf_range(-560.0, -140.0))
		body.angular_velocity = randf_range(-15.0, 15.0)
		get_tree().create_timer(2.5).timeout.connect(body.queue_free)


func _draw() -> void:
	var w := _active_weapon()
	# For non-authority replicas is_on_floor() is stale (no move_and_slide runs on them),
	# so approximate from vertical velocity.
	var on_floor := is_on_floor()
	if multiplayer.multiplayer_peer != null and not is_multiplayer_authority():
		on_floor = absf(velocity.y) < 5.0
	# #90: while climbing, force the standing pose by pretending we're on the
	# floor with no vertical velocity. Otherwise the ±CLIMB_SPEED vel.y makes
	# gostek pick a jump/fall frame on remote replicas.
	var vel_for_pose: Vector2 = velocity
	if climbing:
		on_floor = true
		vel_for_pose = Vector2.ZERO
	# #60: the currently-inactive weapon slings across the back. When holding
	# secondary, the primary rides back; otherwise the chosen secondary does.
	var back_wn: String = str(weapons[weapon_index]["name"]) if using_secondary else str(secondary[secondary_index]["name"])
	SoldierArt.draw_soldier(
		self,
		color,
		facing,
		aim_dir,
		vel_for_pose,
		jet_on,
		dead,
		w["color"],
		str(w.get("kind", "bullet")),
		muzzle_t,
		health,
		fuel,
		true,
		str(w["name"]),
		on_floor,
		reloading,
		crouching,
		prone,
		melee_swing_t > 0.0,
		gesture_anim,
		roll_t > 0.0,
		ceasefire_t > 0.0,
		cosmetics,
		back_wn,
		grenades,
		use_cluster,
		is_multiplayer_authority(),
	)


# ── Bonus pickups (#78) ───────────────────────────────
# Main routes bonus grants through a call_local RPC named net_bonus_apply on
# the target player, so every peer applies the effect (visuals + gameplay)
# consistently. `apply_bonus` is the public entry from Main after it validates
# host authority — the RPC itself only accepts calls originating on the host.

@rpc("any_peer", "call_local", "reliable")
func net_bonus_apply(kind: String, duration: float) -> void:
	# Only host may originate bonus grants. On the host's own call_local half
	# sender_id is 0; on remote peers applying the broadcast sender_id is 1.
	# Reject anything else — a modded client could otherwise self-grant a vest.
	if multiplayer.multiplayer_peer != null:
		var sender := multiplayer.get_remote_sender_id()
		if sender == 0:
			if not Net.is_host():
				return
		elif sender != 1:
			return
	_apply_bonus_local(kind, duration)


@rpc("any_peer", "call_local", "reliable")
func net_bonus_clear() -> void:
	if multiplayer.multiplayer_peer != null:
		var sender := multiplayer.get_remote_sender_id()
		if sender == 0:
			if not Net.is_host():
				return
		elif sender != 1 and sender != get_multiplayer_authority():
			return  # the owner may clear its own buff (Predator breaks on fire)
	_clear_bonus_local()


func apply_bonus(kind: String, duration: float) -> void:
	# Fire the RPC (call_local) so every peer applies. In SP this just calls
	# the local method — no multiplayer peer to route through.
	if Net.is_networked():
		rpc("net_bonus_apply", kind, duration)
	else:
		_apply_bonus_local(kind, duration)


func _apply_bonus_local(kind: String, duration: float) -> void:
	# Snap out of any prior bonus so saved state doesn't stack.
	if bonus_kind != "":
		_clear_bonus_local()
	bonus_kind = kind
	bonus_t = duration
	match kind:
		"berserker":
			_bonus_saved_using_secondary = using_secondary
			_bonus_saved_secondary_index = secondary_index
			_bonus_saved_color = color
			using_secondary = true
			secondary_index = 1  # Knife slot
			reloading = false
			reload_t = 0.0
			color = Color(1.0, 0.35, 0.25)
		"cluster":
			_bonus_saved_use_cluster = use_cluster
			use_cluster = true
		"predator":
			# Alpha modulate is applied in _physics_process on non-authority replicas.
			pass
		"vest":
			# Damage reduction is applied in take_damage.
			pass


func _clear_bonus_local() -> void:
	var prev := bonus_kind
	bonus_kind = ""
	bonus_t = 0.0
	match prev:
		"berserker":
			using_secondary = _bonus_saved_using_secondary
			secondary_index = _bonus_saved_secondary_index
			color = _bonus_saved_color
		"cluster":
			use_cluster = _bonus_saved_use_cluster
	# Predator: restore full alpha in case we were dimmed on a viewer.
	modulate.a = 1.0


func _break_predator_if_active() -> void:
	# Called from fire/melee/grenade paths on the shooter. Only the authority
	# peer initiates the broadcast so we don't get 4 RPCs from 4 peers.
	if bonus_kind != "predator":
		return
	if Net.is_networked() and is_multiplayer_authority():
		rpc("net_bonus_clear")
	_clear_bonus_local()


# Wedge detection: a rectangular body can come to rest between two steep
# surfaces (a V-crevice, or a ledge edge against a slope) without any of them
# counting as "floor". Then is_on_floor() is false forever → no jump, no fuel
# regen → permanently stuck once the tank is empty. If we're pressed against
# terrain, falling, but not actually moving, treat it as standing.
func _update_wedge(delta: float) -> void:
	if not is_on_floor() and not is_on_ceiling() and get_slide_collision_count() > 0 \
			and velocity.y >= 0.0 and get_real_velocity().length() < 6.0:
		_wedge_t += delta
	else:
		_wedge_t = 0.0


func current_weapon_name() -> String:
	if weapon_index >= 0 and weapon_index < weapons.size():
		return str(weapons[weapon_index]["name"])
	return ""
