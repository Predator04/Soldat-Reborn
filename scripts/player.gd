extends CharacterBody2D
## Soldier — Soldat-style movement + weapon system. Net-aware (multiplayer authority).

signal died

@export var color := Color(0.25, 0.75, 0.45)
var team := 0
var display_name := "You"

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
var crouching := false
var prone := false
# Roll — S pressed while running triggers a short forward burst (Soldat's roll).
var roll_t := 0.0
var roll_cd := 0.0
const ROLL_DURATION := 0.32
const ROLL_COOLDOWN := 0.85
const ROLL_SPEED := 520.0
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

# Advance mode — kill count and per-slot unlock kill thresholds. Only enforced
# when Settings.advance is on; otherwise every weapon is available from spawn.
var advance_kills := 0
# Indexed by weapon_index — 12 primaries (matches `weapons` array size).
const ADV_PRIMARY_UNLOCK := [10, 4, 6, 8, 12, 14, 20, 22, 18, 24, 28, 30]
# Indexed by secondary_index — 4 slots (USSOCOM, Knife, Chainsaw, LAW).
const ADV_SECONDARY_UNLOCK := [2, 0, 26, 16]
# Input lock — HUD sets this while the chat/command LineEdit is focused so held
# WASD keys don't leak into movement while the player is typing.
var input_locked := false

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
var shape_crouch: RectangleShape2D
var shape_prone: RectangleShape2D

# ── Physics ────────────────────────────────────────────
const GRAVITY := 1700.0
const RUN_SPEED := 330.0
const BUNNY_SPEED := 640.0
const GROUND_ACCEL := 2800.0
const AIR_ACCEL := 1150.0
const AIR_FRICTION := 45.0
const GROUND_FRICTION := 1700.0
const JUMP_VEL := -470.0
const JET_THRUST := -1250.0
const JET_DRAIN := 40.0
const JET_REGEN := 32.0
const MAX_FALL := 1300.0
const COYOTE_TIME := 0.09
const JUMP_BUFFER := 0.10

var bullet_scene := preload("res://scenes/bullet.tscn")
var grenade_scene := preload("res://scenes/grenade.tscn")
var rocket_scene := preload("res://scenes/rocket.tscn")
const SoldierArt = preload("res://scripts/soldier_art.gd")
const Gostek = preload("res://scripts/gostek.gd")
const WeaponPickup = preload("res://scripts/weapon_pickup.gd")


func _ready() -> void:
	add_to_group("soldier")
	ceasefire_t = CEASEFIRE_SECS
	# Release the per-instance skeleton state dict when this node is freed so long
	# sessions don't leak dict entries in Gostek._states.
	tree_exited.connect(func() -> void: Gostek.forget(self))
	for w in weapons:
		ammo.append(int(w["mag"]))
	for w in secondary:
		secondary_ammo.append(int(w["mag"]))
	col_shape = CollisionShape2D.new()
	shape_stand = RectangleShape2D.new()
	shape_stand.size = Vector2(20, 42)
	shape_crouch = RectangleShape2D.new()
	shape_crouch.size = Vector2(22, 28)
	shape_prone = RectangleShape2D.new()
	shape_prone.size = Vector2(36, 14)
	col_shape.shape = shape_stand
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
		queue_redraw()
		return

	# If the HUD command/chat line is open, freeze inputs: drop x-velocity, apply
	# gravity so we still fall to ground, and skip all movement/shooting handling.
	if input_locked:
		velocity.x = move_toward(velocity.x, 0.0, GROUND_FRICTION * delta)
		if not is_on_floor():
			velocity.y += GRAVITY * delta
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
		queue_redraw()
		return

	var left := Input.is_physical_key_pressed(KEY_A)
	var right := Input.is_physical_key_pressed(KEY_D)
	var jump_pressed := Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_W)

	# Crouch (S hold) + prone (X toggle). Prone locks out crouching.
	# W/Space or another X press stands us up from prone.
	var x_now := Input.is_physical_key_pressed(KEY_X)
	if x_now and not x_prev:
		prone = not prone
		if prone:
			crouching = false
	x_prev = x_now
	if prone and jump_pressed:
		prone = false
	var s_now := Input.is_physical_key_pressed(KEY_S) and not prone
	# Roll: press S with lateral momentum → brief burst, skokdolobrot anim, no crouch shape.
	if s_now and not s_prev and is_on_floor() and roll_cd <= 0.0 and absf(velocity.x) > 60.0:
		roll_t = ROLL_DURATION
		roll_cd = ROLL_COOLDOWN
		velocity.x = signf(velocity.x) * ROLL_SPEED
		Sfx.jump()
	s_prev = s_now
	crouching = s_now and roll_t <= 0.0
	_apply_stance_shape()

	var dir := 0.0
	if left:
		dir -= 1.0
	if right:
		dir += 1.0

	var on_floor := is_on_floor()

	# coyote time + jump buffering
	coyote_t = COYOTE_TIME if on_floor else maxf(0.0, coyote_t - delta)
	jump_buffer_t = JUMP_BUFFER if jump_pressed else maxf(0.0, jump_buffer_t - delta)

	# horizontal
	var speed_mul: float = float(Settings.mod_speed)
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
	if dir != 0.0:
		velocity.x += dir * accel * delta
	else:
		var fr := GROUND_FRICTION if on_floor else AIR_FRICTION
		velocity.x = move_toward(velocity.x, 0.0, fr * delta)
	velocity.x = clampf(velocity.x, -cap, cap)

	# jet boots (RMB, matching Soldat's default controls). Realistic mode locks
	# the boots — Soldat's Realistic ruleset removes fuel entirely.
	var jet_pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not Settings.realistic
	jet_on = false
	if jet_pressed and not on_floor and fuel > 0.0:
		velocity.y += JET_THRUST * delta
		fuel = maxf(0.0, fuel - JET_DRAIN * delta)
		jet_on = true
	elif on_floor:
		fuel = minf(100.0, fuel + JET_REGEN * float(Settings.mod_jet) * delta)

	# jump / bunny hop (coyote + buffer aware)
	if jump_buffer_t > 0.0 and coyote_t > 0.0:
		velocity.y = JUMP_VEL
		velocity.x = clampf(velocity.x * 1.06, -BUNNY_SPEED, BUNNY_SPEED)
		coyote_t = 0.0
		jump_buffer_t = 0.0
		Sfx.jump()

	if not on_floor:
		velocity.y += GRAVITY * float(Settings.mod_gravity) * delta
		velocity.y = minf(velocity.y, MAX_FALL)

	# aim
	var mouse := get_global_mouse_position()
	var to_mouse := mouse - global_position
	if to_mouse.length() > 1.0:
		aim_dir = to_mouse.normalized()
		# Small deadband around vertical so facing doesn't pop as the mouse crosses through x=0.
		if absf(aim_dir.x) > 0.05:
			facing = signf(aim_dir.x)

	move_and_slide()

	# primary weapon switching (keys 1..9,0). Numbers map to Soldat's classic slot order.
	if Input.is_physical_key_pressed(KEY_1):
		_switch_weapon(0)
	elif Input.is_physical_key_pressed(KEY_2):
		_switch_weapon(1)
	elif Input.is_physical_key_pressed(KEY_3):
		_switch_weapon(2)
	elif Input.is_physical_key_pressed(KEY_4):
		_switch_weapon(3)
	elif Input.is_physical_key_pressed(KEY_5):
		_switch_weapon(4)
	elif Input.is_physical_key_pressed(KEY_6):
		_switch_weapon(5)
	elif Input.is_physical_key_pressed(KEY_7):
		_switch_weapon(6)
	elif Input.is_physical_key_pressed(KEY_8):
		_switch_weapon(7)
	elif Input.is_physical_key_pressed(KEY_9):
		_switch_weapon(8)
	elif Input.is_physical_key_pressed(KEY_0):
		_switch_weapon(9)

	# Q toggles primary ↔ secondary — swap on the rising edge so a held key doesn't ping-pong.
	var q_now := Input.is_physical_key_pressed(KEY_Q)
	if q_now and not q_prev:
		_toggle_secondary()
	q_prev = q_now

	# reload
	if Input.is_physical_key_pressed(KEY_R) and not reloading:
		_start_reload()

	# Grenade type toggle (G — rising edge only, matches Q swap pattern)
	var g_now := Input.is_physical_key_pressed(KEY_G)
	if g_now and not g_prev:
		use_cluster = not use_cluster
	g_prev = g_now

	# F — mount an M2 if we're standing on one, otherwise throw the current
	# weapon (issue #11). Mount only when we're not already mounted.
	var f_now := Input.is_physical_key_pressed(KEY_F)
	if f_now and not f_prev:
		var m2 := _find_nearby_m2()
		if m2 != null and mounted_m2 == null:
			m2.mount(self)
		else:
			_drop_active_weapon()
	f_prev = f_now

	# grenade
	grenade_cd -= delta
	if Input.is_physical_key_pressed(KEY_E) and grenade_cd <= 0.0 and grenades > 0:
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
		var lmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
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
					rpc_id(pid, "net_state", position, velocity, aim_dir, facing, jet_on, health, fuel, weapon_index, ammo[weapon_index], reloading, grenades, secondary_index, secondary_ammo[secondary_index], using_secondary, crouching, prone)
		else:
			# Broadcast so the host relays to other clients (Godot's server_relay).
			# Using rpc_id(1, ...) would freeze non-host peers' views of this body.
			rpc("net_state", position, velocity, aim_dir, facing, jet_on, health, fuel, weapon_index, ammo[weapon_index], reloading, grenades, secondary_index, secondary_ammo[secondary_index], using_secondary, crouching, prone)


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
	# ALT + a..z / 0..9 → send a canned taunt over global chat.
	if event.alt_pressed and hud != null:
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
	match event.physical_keycode:
		KEY_SLASH:
			if hud != null:
				hud.open_command()
				get_viewport().set_input_as_handled()
		KEY_T:
			if hud != null:
				hud.open_chat("global")
				get_viewport().set_input_as_handled()
		KEY_Y:
			if hud != null:
				hud.open_chat("team")
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
	# Advance: block hotkeys pointing to still-locked primaries.
	if Settings.advance and not _is_primary_unlocked(idx):
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
	# Advance: don't swap into a slot whose weapon isn't unlocked yet.
	if Settings.advance:
		if using_secondary and not _is_primary_unlocked(weapon_index):
			return
		if not using_secondary and not _is_secondary_unlocked(secondary_index):
			return
	using_secondary = not using_secondary
	if reloading:
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
	if col_shape.shape != want:
		# set_deferred so the swap doesn't race with physics evaluating the current shape.
		col_shape.set_deferred("shape", want)


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
	ceasefire_t = 0.0  # firing forfeits spawn protection
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
		rpc("net_shoot", muzzle, dirs, slot)
	else:
		net_shoot(muzzle, dirs, slot)
	if _active_mag() <= 0:
		_start_reload()


# Melee swing / continuous scan. Applies damage to any enemy soldier within a
# short arc in front of us. Called on LMB in-range for Knife/Chainsaw.
func _perform_melee() -> void:
	var w := _active_weapon()
	fire_cd = float(w["rate"])
	ceasefire_t = 0.0
	var kind_m := str(w.get("kind", "melee"))
	# Broadcast so all peers see the swing feedback (muzzle flash + sfx). Damage
	# is applied inside net_shoot with the standard authority guard.
	var slot := (100 + secondary_index) if using_secondary else weapon_index
	var muzzle: Vector2 = global_position + SoldierArt.muzzle_local(self, aim_dir, facing, str(w["name"]))
	# `dirs` carries the swing direction as a single unit vector; range is looked
	# up from the weapon dict on the receiving side.
	var dirs := PackedVector2Array([aim_dir])
	if Net.is_networked():
		rpc("net_shoot", muzzle, dirs, slot)
	else:
		net_shoot(muzzle, dirs, slot)
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


func mount_m2(m2: Node2D) -> void:
	mounted_m2 = m2


func dismount_m2() -> void:
	mounted_m2 = null


func _drop_active_weapon() -> void:
	var w := _active_weapon()
	var wname := str(w["name"])
	if Net.is_networked():
		rpc("net_drop_weapon", wname, global_position, aim_dir)
	else:
		net_drop_weapon(wname, global_position, aim_dir)


func try_pickup_weapon(weapon_name: String) -> bool:
	# Only the authority peer mutates the loadout — otherwise net_state loops.
	if multiplayer.multiplayer_peer != null and not is_multiplayer_authority():
		return false
	for i in weapons.size():
		if str(weapons[i]["name"]) == weapon_name:
			ammo[i] = int(weapons[i]["mag"])
			weapon_index = i
			using_secondary = false
			reloading = false
			reload_t = 0.0
			return true
	for i in secondary.size():
		if str(secondary[i]["name"]) == weapon_name:
			secondary_ammo[i] = int(secondary[i]["mag"])
			secondary_index = i
			using_secondary = true
			reloading = false
			reload_t = 0.0
			return true
	return false


func _throw_grenade() -> void:
	grenades -= 1
	Sfx.grenade_throw()
	ceasefire_t = 0.0
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
		rpc("net_grenade", g_pos, g_vel, g_ang, use_cluster)
	else:
		net_grenade(g_pos, g_vel, g_ang, use_cluster)


func _shake(amount: float) -> void:
	if not Settings.screen_shake:
		return
	shake = maxf(shake, amount)


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
		var peer_id := get_multiplayer_authority()
		var m := get_parent()
		var mode_at_schedule: int = Net.mode
		# Survival: don't respawn until the round resets — main.gd::_reset_round
		# rebuilds bodies for everyone at that point.
		var survival_gate: bool = Settings.survival
		get_tree().create_timer(2.0).timeout.connect(func() -> void:
			# Bail if we've since torn down / rehosted / joined — don't respawn into a stale scene.
			if Net.mode != mode_at_schedule:
				return
			if get_tree().current_scene != m:
				return
			if survival_gate and is_instance_valid(m) and bool(m.get("round_active")):
				return
			if is_instance_valid(m) and m.has_method("_respawn_peer"):
				m._respawn_peer(peer_id))
	queue_free()


func _emit_kill() -> void:
	if last_killer == "":
		return
	var parent := get_parent()
	if parent != null and parent.has_signal("kill"):
		parent.emit_signal("kill", last_killer, display_name, last_weapon, last_killer_team, team)


# ── RPCs ──────────────────────────────────────────────

@rpc("authority", "call_remote", "unreliable_ordered")
func net_state(pos: Vector2, vel: Vector2, aim: Vector2, face: float, jetting: bool, hp: float, fuel_val: float, wi: int, mag: int, is_reloading: bool, grens: int, sec_i: int, sec_mag: int, use_sec: bool, crouch_f: bool, prone_f: bool) -> void:
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
	_apply_stance_shape()
	reloading = is_reloading
	grenades = maxi(0, grens)


@rpc("authority", "call_local", "reliable")
func net_shoot(shot_pos: Vector2, dirs: PackedVector2Array, weapon_i: int) -> void:
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
		var dmg: float = float(w["damage"]) * float(Settings.mod_damage)
		# Scan soldiers in a short forward arc — apply damage on the authority peer
		# only (matches how bullet/rocket damage is gated in bullet.gd/rocket.gd).
		for s in get_tree().get_nodes_in_group("soldier"):
			if s == self or not is_instance_valid(s):
				continue
			if int(s.get("team")) == team or bool(s.get("dead")):
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
			r.global_position = shot_pos + bdir * 4.0
			r.direction = bdir
			r.speed = float(w["speed"])
			r.damage = float(w["damage"]) * float(Settings.mod_damage)
			r.team = team
			r.killer_name = display_name
			r.weapon_name = str(w["name"])
			# M79 (launcher) lobs — grav>0 flips rocket.gd into ballistic mode.
			r.grav = float(w.get("gravity", 0.0))
			get_parent().add_child(r)
		else:
			var b := bullet_scene.instantiate()
			b.global_position = shot_pos + bdir * 4.0
			b.direction = bdir
			b.speed = float(w["speed"])
			b.damage = float(w["damage"]) * float(Settings.mod_damage)
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
func net_grenade(g_pos: Vector2, g_vel: Vector2, g_ang: float, cluster: bool = false) -> void:
	var g := grenade_scene.instantiate()
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
	get_parent().add_child(g)


@rpc("authority", "call_local", "reliable")
func net_drop_weapon(weapon_name: String, from_pos: Vector2, aim: Vector2) -> void:
	var wp := WeaponPickup.new()
	wp.weapon_name = weapon_name
	wp.team = team
	wp.thrower_name = display_name
	wp.damage_on_hit = 55.0 if weapon_name == "Knife" else 0.0
	wp.global_position = from_pos + aim * 20.0
	wp.linear_velocity = aim * 520.0 + Vector2(0, -160.0)
	wp.angular_velocity = randf_range(-8.0, 8.0)
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
	var p := CPUParticles2D.new()
	p.amount = 60
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
	var count := 8
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
	SoldierArt.draw_soldier(
		self,
		color,
		facing,
		aim_dir,
		velocity,
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
	)
