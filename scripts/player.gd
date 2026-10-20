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
	{"name": "Rambo Bow",    "damage": 100.0, "rate": 1.0,   "mag": 1,   "reload": 2.5,  "auto": false, "spread": 0.0,  "speed": 900.0, "pellets": 1, "color": Color(0.6, 0.4, 0.2),  "kind": "arrow", "bink": 0.0, "gravity": 240.0},
]
# Secondary slot — the second weapon the soldier carries (Q to swap primary↔secondary).
var secondary := [
	{"name": "USSOCOM",  "damage": 27.0, "rate": 0.167, "mag": 14,  "reload": 1.0,  "auto": false, "spread": 0.0, "speed": 800.0, "pellets": 1, "color": Color(0.85, 0.8, 0.6),   "kind": "bullet", "bink": 25.0},
	{"name": "Knife",    "damage": 55.0, "rate": 0.5,   "mag": 1,   "reload": 0.05, "auto": false, "spread": 0.0, "speed": 0.0,   "pellets": 0, "color": Color(0.9, 0.9, 0.95),   "kind": "melee",      "range": 34.0, "bink": 0.0},
	{"name": "Chainsaw", "damage": 9.0,  "rate": 0.10,  "mag": 200, "reload": 1.83, "auto": true,  "spread": 0.0, "speed": 0.0,   "pellets": 0, "color": Color(1.0, 0.7, 0.15),   "kind": "melee_cont", "range": 32.0, "bink": 0.0},
	{"name": "LAW",      "damage": 90.0, "rate": 1.1,   "mag": 1,   "reload": 3.0,  "auto": false, "spread": 0.0, "speed": 720.0, "pellets": 1, "color": Color(0.85, 0.55, 0.35), "kind": "rocket", "bink": 0.0},
]
var ammo: Array[int] = []
var secondary_ammo: Array[int] = []
var weapon_index := 2   # default primary = AK-74 (Soldat's #3)
var secondary_index := 0  # default secondary = USSOCOM
var using_secondary := false
var fire_cd := 0.0


## Weapon dict for a net_shoot slot index (≥100 = secondaries); {} if invalid.
func _weapon_for_slot(weapon_i: int) -> Dictionary:
	if weapon_i >= 100:
		var si := weapon_i - 100
		if si < 0 or si >= secondary.size():
			return {}
		return secondary[si]
	if weapon_i < 0 or weapon_i >= weapons.size():
		return {}
	return weapons[weapon_i]


# (#243's minimum gap between a client's shots is now the host's long-run
# rate check in TrustGuard.stamp_check, #266: the gap also dropped honest shots
# the network had bunched together.)
var spin_up_t := 0.0    # ramps up while LMB held for weapons with a startup wind-up (Barrett, Minigun)
var lmb_prev := false   # prev-frame LMB state — resets spin_up_t when the trigger releases
var reloading := false
var reload_t := 0.0
var grenades := 3
var grenade_cd := 0.0
# Grenade cooking: -1 = not holding one; otherwise seconds since the pin was pulled.
const GRENADE_FUSE := 2.2          # frag: pin pulled -> boom
const CLUSTER_FUSE := 1.9
const COOK_FULL_POWER := 0.9       # seconds of holding for the hardest throw
var _cook_t := -1.0
var _cook_cluster := false
var _g_held_prev := false
# Grenade type toggle — press G to swap Frag ↔ Cluster.
var use_cluster := false
var g_prev := false
var muzzle_t := 0.0
# Lag compensation: where this (locally controlled) body was over the last
# ~300 ms, so a remote player's bullet can be tested against the position the
# shooter actually saw. Entries are [msec, hitbox Rect2].
var pos_hist: Array = []
const LAG_COMP_MAX_MS := 200
var q_prev := false     # prev-frame Q — swap on rising edge only, not every physics tick
var x_prev := false     # prev-frame X — prone toggle on rising edge
var s_prev := false     # prev-frame S — roll on rising edge with lateral momentum
var f_prev := false     # prev-frame F — throw current weapon on rising edge
# #87: weapons the player has thrown (name -> true). Thrown weapons are removed
# from the active roster until re-picked up (or respawn).
var _thrown: Dictionary = {}
# Host-side rate-limit on drop RPCs so a modded client can't spam pickup spawns.
var _last_drop_ms: int = 0
# #240: host-owned drop bookkeeping (the client's _thrown never reaches us).
var _drop_times: Dictionary = {}
var _recent_drops: Array = []
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
# Host-side checks on a remote human's reported state (see trust_guard.gd).
var _trust: TrustGuard = null
# #266 (host_hits.gd): on the host, hits on a remote human are decided here and
# sent to the owner (net_hit). Per-frame damage (the BR ring) is batched.
var _hit_pending := 0.0
var _hit_sent_ms := -100000
# Host: shots whose direction disagreed with the last streamed aim wait for
# the next aim sample before their hits count ({ms, dir, spread, a0, hits, done}).
var _aim_pending: Array = []
const HIT_BATCH_MS := 100
# Release-gate only: simulate a modified client (see Net --smoke-cheat).
var test_cheat := ""
# How long the dead body lingers as an inert husk for late packets (see _die).
# A host-forced death (trust_guard) waits longer: the owner keeps sending until
# the death reaches it, which on a slow / loaded client can take a while.
var _husk_secs := 1.5
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
# Radio menu (v1.18) is up: number keys pick a callout, not a weapon.
var radio_open := false
# One queued semi-auto shot (see the fire block in _physics_process).
var _semi_armed := false
var _radio_cd := 0.0

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
var _jump_hold_t := 1.0   # >= JUMP_SUSTAIN when not in a fresh jump (#262)
var _jump_cut_done := true
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
# Movement tech (original tutorial's half/full jump): holding jump sustains
# the rise for a short window (a full-height jump — exactly today's height);
# releasing early cuts the rise (a short hop). Tap-to-hop, hold-to-jump.
const JUMP_SUSTAIN := 0.20      # seconds of reduced gravity while held
const JUMP_SUSTAIN_GRAV := 0.45 # gravity multiplier during the sustain window
const JUMP_CUT_MULT := 0.55     # upward velocity kept when jump is released early
# Prone in the air drops you faster (prone-cancel) — classic momentum killer.
const PRONE_FALL_GRAV := 1.5
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


const FootAudio = preload("res://scripts/foot_audio.gd")
const GameInfo = preload("res://scripts/game_info.gd")
const BonusPickup = preload("res://scripts/bonus_pickup.gd")


func _ready() -> void:
	# Terrain layer 3 (bit 4) = ported "only players collide" polys.
	# Soldiers live on their own layer 4 (bit 8) and don't collide with each
	# other (as in Soldat) — bodies shoving one another used to push soldiers
	# into walls and block narrow tunnels. Bullets/rockets/grenades/pickups
	# mask bit 8 to keep hitting them.
	collision_layer = 8
	collision_mask = 1 | 4
	add_to_group("soldier")
	add_child(FootAudio.new())
	ceasefire_t = CEASEFIRE_SECS
	if cosmetics.is_empty():
		# Your own outfit for your body; other players' bodies wait for theirs
		# (net_cosmetics) instead of showing yours.
		if not Net.is_networked() or not multiplayer.has_multiplayer_peer() or is_multiplayer_authority():
			cosmetics = my_cosmetics()
			if Net.is_networked() and multiplayer.has_multiplayer_peer():
				_send_cosmetics.call_deferred()
		else:
			cosmetics = {"head": "helm", "vest": true}
	# Release the per-instance skeleton state dict when this node is freed so long
	# sessions don't leak dict entries in Gostek._states.
	tree_exited.connect(func() -> void: Gostek.forget(self))
	# #266: the host tests remote humans against rewound hitboxes.
	if Net.is_networked() and Net.is_host() and multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		HostHits.register(self)
		tree_exiting.connect(func() -> void: HostHits.unregister(self))
		_trust_guard()
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

	if not has_peer or is_multiplayer_authority():
		_record_hitbox()

	# One handler per state (#258): a non-authority replica only animates;
	# the local body is either mounted on an M2 / vehicle seat, frozen while
	# the chat line is open, or live.
	if has_peer and not is_multiplayer_authority():
		_physics_replica(delta)
	elif mounted_m2 != null:
		_physics_mounted(delta)
	elif input_locked:
		_physics_input_locked(delta)
	else:
		_physics_live(delta)


## Non-authority replica: state is set by net_state RPCs; just visual bookkeeping.
func _physics_replica(delta: float) -> void:
	# A soldier in a vehicle seat sits where this peer's copy of the vehicle
	# puts it (buggy._place_occupants); pulling it toward its own stream as
	# well left it between two places.
	if _vehicle_seat() < 0:
		_net_smooth(delta)
	if _trust != null:
		# Host (#266): where this body was, for rewound hit tests; batched hits
		# and shots waiting on an aim sample.
		_record_hitbox()
		if _hit_pending > 0.0 and Time.get_ticks_msec() - _hit_sent_ms >= HIT_BATCH_MS:
			_send_hit(_hit_pending, "", "Zone", -1)
		if not _aim_pending.is_empty():
			_resolve_aim(false)
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
	jet_particles.color = jet_particle_color(cosmetics)
	jet_particles.position = Vector2(-facing * 3.3, 1.7)
	queue_redraw()


## Mounted on an M2 — the turret drives position, aim, and firing.
func _physics_mounted(delta: float) -> void:
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


## If the HUD command/chat line is open, freeze inputs: drop x-velocity, apply
## gravity so we still fall to ground, and skip all movement/shooting handling.
func _physics_input_locked(delta: float) -> void:
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


## Live local body: input → stance → ladder → movement → aim → move, then
## weapons, timers, effects and the state stream. Same order as ever.
func _physics_live(delta: float) -> void:
	var left := Input.is_action_pressed("move_left")
	var right := Input.is_action_pressed("move_right")
	var jump_pressed := Input.is_action_pressed("jump")
	_live_stance(jump_pressed)
	var climb_down_pressed := _live_ladder(delta)
	_live_move(delta, left, right, jump_pressed, climb_down_pressed)
	_live_aim(delta)
	move_and_slide()
	_update_wedge(delta)
	_live_weapon_keys()
	_live_grenade(delta)
	_live_trigger(delta)
	_live_timers(delta)
	_live_fx(delta)
	queue_redraw()
	_send_state(delta)


func _live_stance(jump_pressed: bool) -> void:
	# Crouch (S hold) + prone (X toggle). Prone locks out crouching.
	# W/Space or another X press stands us up from prone.
	var x_now := Input.is_action_pressed("prone")
	if x_now and not x_prev:
		prone = not prone
		Sfx.prone(global_position, prone)
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
		Sfx.roll(global_position)
	s_prev = s_now
	crouching = s_now and roll_t <= 0.0 and not climbing
	_apply_stance_shape()


## Returns whether climb-down (S) is held this tick.
func _live_ladder(delta: float) -> bool:
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
				Sfx.jump(global_position)
	return climb_down_pressed


func _live_move(delta: float, left: bool, right: bool, jump_pressed: bool, climb_down_pressed: bool) -> void:
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
			_jump_hold_t = 0.0
			_jump_cut_done = false
			# Scale the hop's lateral clamp by speed_mul so the Predator/Berserker
			# bonuses (and any host speed mod) can boost a hop above the base
			# BUNNY_SPEED cap — otherwise the powerup felt inert while airborne (#86.5).
			var hop_cap: float = BUNNY_SPEED * speed_mul
			velocity.x = clampf(velocity.x * 1.06, -hop_cap, hop_cap)
			coyote_t = 0.0
			jump_buffer_t = 0.0
			Sfx.jump(global_position)

		if not on_floor:
			var g_mul := 1.0
			# #262 hold-scaling: fresh jump + button held + still rising →
			# reduced gravity for the sustain window (full-height jump).
			if _jump_hold_t < JUMP_SUSTAIN and jump_pressed and velocity.y < 0.0 and not jet_on:
				g_mul = JUMP_SUSTAIN_GRAV
				_jump_hold_t += delta
			else:
				_jump_hold_t = JUMP_SUSTAIN
			# Released early while rising → cut the hop short (once per jump).
			if not _jump_cut_done and not jump_pressed and velocity.y < -100.0 and not jet_on:
				velocity.y *= JUMP_CUT_MULT
				_jump_cut_done = true
			# Prone-cancel: prone in the air drops you faster.
			if prone:
				g_mul = maxf(g_mul, PRONE_FALL_GRAV)
			velocity.y += GRAVITY * g_mul * mg * delta
			velocity.y = minf(velocity.y, MAX_FALL)


func _live_aim(delta: float) -> void:
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
	_update_camera_lead(stick, delta)


func _live_weapon_keys() -> void:
	# primary weapon switching (keys 1..9,0). Numbers map to Soldat's classic slot order.
	if radio_open:
		pass
	elif Input.is_action_pressed("weapon_1"):
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


func _live_grenade(delta: float) -> void:
	# grenade — locked out in Gun Game so grenade kills can't skip the ladder.
	# Soldat-style cooking: pressing pulls the pin and starts the fuse; holding
	# winds up a harder throw; releasing throws with whatever fuse is left.
	# Hold past the fuse and it goes off in your hand.
	grenade_cd -= delta
	var g_held := Input.is_action_pressed("grenade")
	if _cook_t >= 0.0:
		_cook_t += delta
		queue_redraw()
		if _cook_t >= _cook_fuse():
			_explode_in_hand()
		elif not g_held:
			_throw_grenade(_cook_t)
			_cook_t = -1.0
			grenade_cd = 0.6
	elif Settings.game_mode != Settings.MODE_GG \
			and g_held and not _g_held_prev and grenade_cd <= 0.0 and grenades > 0:
		_cook_t = 0.0
		_cook_cluster = use_cluster
		Sfx.grenade_pull()
	_g_held_prev = g_held


func _live_trigger(delta: float) -> void:
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
		var is_auto: bool = bool(w_active.get("auto", false))
		# Semi-auto: a fresh click arms one shot. The Barrett (semi-auto with a
		# wind-up) keeps that shot queued through its wind-up even if you let go —
		# before 1.18 the "wait for release" check was already true by the time
		# the wind-up finished, so it clicked and never fired.
		if lmb and not lmb_prev and not is_auto:
			_semi_armed = true
		if not lmb and startup <= 0.0:
			_semi_armed = false
		var want: bool = lmb if is_auto else _semi_armed
		if want:
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
		if want and fire_cd <= 0.0:
			var can_fire := true
			if startup > 0.0 and spin_up_t < startup:
				can_fire = false
			if can_fire:
				if not is_auto:
					_semi_armed = false
					spin_up_t = 0.0   # every Barrett shot has its own wind-up
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


func _live_timers(delta: float) -> void:
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


func _live_fx(delta: float) -> void:
	# jet particles + sfx transitions
	if jet_on and not was_jet:
		Sfx.jet(true)
	elif not jet_on and was_jet:
		Sfx.jet(false)
	was_jet = jet_on
	jet_particles.emitting = jet_on and not Settings.lofi
	jet_particles.color = jet_particle_color(cosmetics)
	jet_particles.position = Vector2(-facing * 3.3, 1.7)

	# Camera shake lives in scripts/gfx/screen_feel.gd now (#271): trauma-based,
	# applied to this camera in _process from its own noise — never the global
	# random stream from inside the physics tick.


func _send_state(delta: float) -> void:
	# Broadcast authoritative state to peers who have finished handshake (spawned us).
	# On host: parent Main tracks ready peers. On client: peer 1 (host) is always ready
	# because we only spawn locally after receiving spawn RPCs from host.
	# 30 Hz state stream (was every physics frame): remote peers smooth between
	# packets (see _net_smooth), so this halves bandwidth without visible chop.
	_state_send_acc += delta
	if Net.is_networked() and multiplayer.has_multiplayer_peer() and _state_send_acc >= 1.0 / STATE_SEND_HZ:
		_state_send_acc = 0.0
		if Net.is_host():
			var m := get_parent()
			if m != null and m.has_method("ready_peer_ids"):
				for pid in m.ready_peer_ids():
					rpc_id(pid, "net_state", position, velocity, aim_dir, facing, jet_on, health, fuel, weapon_index, ammo[weapon_index], reloading, grenades, secondary_index, secondary_ammo[secondary_index], using_secondary, crouching, prone, climbing, Time.get_ticks_msec())
		else:
			# To the host only; it relays to ready peers (see net_state).
			rpc_id(1, "net_state", position, velocity, aim_dir, facing, jet_on, health, fuel, weapon_index, ammo[weapon_index], reloading, grenades, secondary_index, secondary_ammo[secondary_index], using_secondary, crouching, prone, climbing, 0, HostHits.game_ms())


# ── /command console (gestures) ────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if dead:
		return
	# Only the local (authority) player opens the console.
	if multiplayer.multiplayer_peer != null and not is_multiplayer_authority():
		return
	if input_locked:
		return
	# Gamepad: L3 opens team radio (the chat / console keys are keyboard only).
	if event is InputEventJoypadButton and event.is_action_pressed("radio"):
		var ph = get_parent().get("hud") if get_parent() != null else null
		if ph != null and ph.has_method("toggle_radio"):
			ph.toggle_radio()
			get_viewport().set_input_as_handled()
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
	elif event.is_action_pressed("radio"):
		if hud != null and hud.has_method("toggle_radio"):
			hud.toggle_radio()
			get_viewport().set_input_as_handled()


# Team radio callout (see radio_menu.gd). Rate-limited so it can't be spammed.
func send_radio(code: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _radio_cd:
		return
	_radio_cd = now + 1.5
	var parent := get_parent()
	if parent == null or not parent.has_method("net_radio"):
		return
	if Net.is_networked():
		parent.rpc("net_radio", display_name, code, team)
	else:
		parent.net_radio(display_name, code, team)


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
		_cast("net_gesture", [cmd])
	else:
		net_gesture(cmd)


@rpc("any_peer", "call_remote", "reliable")
func net_gesture(cmd: String) -> void:
	if not _net_accept("net_gesture", [cmd]):
		return
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
	# #256: banned weapons can't be switched to (the menu hides them; this
	# covers number keys and any programmatic switch). idx is a PRIMARY slot.
	if idx >= 0 and idx < weapons.size() and MatchConfig.weapon_banned(str(weapons[idx]["name"])):
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
		_semi_armed = false
	if idx == weapon_index:
		return
	# Allow switching mid-reload to cancel it — otherwise the player is hard-locked
	# for LAW's 3s or Spas's 2.5s with no way to defend.
	if reloading:
		reloading = false
		reload_t = 0.0
	weapon_index = idx
	if _sfx_at() == Sfx.NOWHERE:
		Sfx.weapon_switch()
	# Your last hotkey pick is also what you respawn with (limbo menu shows it).
	if idx < 10:
		Settings.spawn_primary = idx
	fire_cd = 0.15
	spin_up_t = 0.0
	lmb_prev = true
	_semi_armed = false


func _toggle_secondary() -> void:
	# Gun Game: rung IS the weapon — Q swap is locked.
	if Settings.game_mode == Settings.MODE_GG:
		return
	# Berserker locks us on the knife slot (#78) — Q would take us back to
	# a primary, undoing the effect.
	if bonus_kind == "berserker":
		return
	# #256: Q must not swap into a banned weapon on either side.
	if using_secondary and MatchConfig.weapon_banned(str(weapons[weapon_index]["name"])):
		return
	if not using_secondary and MatchConfig.weapon_banned(str(secondary[secondary_index]["name"])):
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
	if _sfx_at() == Sfx.NOWHERE:
		Sfx.weapon_switch()
	if reloading:
		reloading = false
		reload_t = 0.0
	fire_cd = 0.15
	spin_up_t = 0.0
	lmb_prev = true
	_semi_armed = false


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
	_semi_armed = false
	if _trust != null:
		_trust.refill_all()   # the new rung starts with a full magazine


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
	Sfx.reload(str(w["name"]), _sfx_at())


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
		_cast("net_shoot", [muzzle, dirs, slot, base_id, HostHits.view_now(), HostHits.game_ms()])
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
		_cast("net_shoot", [muzzle, dirs, slot, 0, HostHits.view_now(), HostHits.game_ms()])
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
	# Buggies first (v1.19) — they share the F-to-mount path with the M2.
	for v in get_tree().get_nodes_in_group("vehicle"):
		if is_instance_valid(v) and v.can_enter(self):
			return v
	for m in get_tree().get_nodes_in_group("m2_gun"):
		if not is_instance_valid(m):
			continue
		if m.get("operator") != null:
			continue
		if global_position.distance_to(m.global_position) < 32.0:
			return m
	return null


func _find_ladder_overlap() -> Node2D:
	return find_ladder_overlap(get_tree(), global_position)


## Shared ladder sensing (player + bot both use it — the two copies had
## drifted in wording only, but kept as one so they can't drift in behavior).
## Rect-vs-rect between the soldier body (feet-anchored, ~14×24) and each
## ladder Area2D's stored bounds. Picks the ladder whose center-x is closest
## so a soldier straddling two ladders latches onto the nearer one.
static func find_ladder_overlap(tree: SceneTree, pos: Vector2) -> Node2D:
	var pcx: float = pos.x
	var pfeet: float = pos.y
	var phead: float = pfeet - CLIMB_BODY_PAD_TOP
	var closest: Node2D = null
	var best_dx: float = 1e9
	for lad in tree.get_nodes_in_group("ladder"):
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


# Run over by a buggy or tank: the host decides (the damage arrives as
# net_hit, #266); the victim's own peer takes the knock-back.
@rpc("any_peer", "call_remote", "reliable")
func net_vehicle_hurt(_dmg: float, _killer: String, _killer_team: int, vel: Vector2, _weapon: String) -> void:
	if multiplayer.get_remote_sender_id() != 1 or not is_multiplayer_authority():
		return
	ceasefire_t = 0.0
	if not dead:
		velocity = Vector2(vel.x * 0.9, -260.0)


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
	# #254: mirror the host's bounds locally BEFORE marking the weapon thrown.
	# The host rejects out-of-bounds drops (below), and a client that had
	# already switched away would silently lose the weapon for the life.
	if not _drop_bounds_ok(wname):
		return
	_thrown[wname] = true
	Sfx.throw_gun(_sfx_at())
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
			_semi_armed = false
	else:
		var si := _first_non_thrown_unlocked(secondary, true)
		if si >= 0:
			secondary_index = si
			using_secondary = true
			reloading = false
			reload_t = 0.0
			fire_cd = 0.15
			lmb_prev = true
			_semi_armed = false
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
	# #240: _thrown (above) is authority-local state that is never
	# synchronized — for a CLIENT's body it always read empty, so only the
	# rate floor below bounded abuse. Bound drops with host-owned replica
	# state instead: per-weapon spacing (a real throw→pickup→throw cycle
	# takes seconds) plus a rolling per-peer budget, so pickup-spam from a
	# modded client can't grow the 10 Hz pickup broadcast for everyone.
	# #254: the dropper runs the same check before sending, so a legit client
	# never has a drop rejected after it already switched weapons away.
	if not _drop_bounds_ok(weapon_name):
		return
	# Snap the pickup to the player's authoritative position — client-reported
	# from_pos is a hint only. Clamp mag so a modded client can't over-refill on
	# next pickup (upper bound is the weapon's max; -1 = "full" is banned here
	# because a client-hostile default would otherwise turn drop+pickup into a
	# free reload).
	var max_mag: int = _loadout_mag(weapon_name)
	var clamped: int = clampi(mag, 0, max_mag) if mag >= 0 else 0
	net_drop_weapon(weapon_name, global_position, aim, clamped)


## #240/#254: drop bounds — ≥600 ms apart, ≤1 drop of a given weapon per 8 s,
## ≤4 drops per rolling 10 s. Records the drop when accepted (so the dropper's
## local mirror and the host's authoritative copy stay in sync — both run
## this). Re-grabbing a weapon clears its 8 s gate (toss-and-catch is legit).
func _drop_bounds_ok(wname: String) -> bool:
	var now := Time.get_ticks_msec()
	if now - _last_drop_ms < 600:
		return false
	if now - int(_drop_times.get(wname, 0)) < 8000:
		return false
	_recent_drops = _recent_drops.filter(func(t): return now - int(t) < 10000)
	if _recent_drops.size() >= 4:
		return false
	_recent_drops.append(now)
	_drop_times[wname] = now
	_last_drop_ms = now
	return true


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
	# #256: banned weapons never enter the match.
	if MatchConfig.weapon_banned(weapon_name):
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
		# #254: re-grabbing re-arms the drop gate too — toss-catch-toss is
		# legitimate play and must not wait out the 8 s window.
		_drop_times.erase(weapon_name)
	if picked and not was_thrown_by_me:
		_pickup_toast(weapon_name.to_upper(), GameInfo.weapon_desc(weapon_name), Color(0.95, 0.9, 0.6))
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


func _cook_fuse() -> float:
	return CLUSTER_FUSE if _cook_cluster else GRENADE_FUSE


func _explode_in_hand() -> void:
	# Held too long: it detonates right here (and usually kills you).
	_cook_t = -1.0
	grenade_cd = 0.6
	grenades -= 1
	var fuse_left := 0.02
	if Net.is_networked():
		var pid := _next_proj_id
		_next_proj_id += 1
		_cast("net_grenade", [global_position + Vector2(0, -8), Vector2.ZERO, 0.0, _cook_cluster, pid, fuse_left, HostHits.game_ms()])
	else:
		net_grenade(global_position + Vector2(0, -8), Vector2.ZERO, 0.0, _cook_cluster, 0, fuse_left)
	# A grenade going off in your fist is not survivable (the blast alone
	# falls off with distance and could leave you standing).
	take_damage(999.0, display_name, "Grenade", int(team))


func _throw_grenade(cook: float = 0.0) -> void:
	grenades -= 1
	Sfx.grenade_throw(_sfx_at())
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
	# A tap lobs it (~300); a full wind-up throws hard (~650).
	var power: float = clampf(cook / COOK_FULL_POWER, 0.0, 1.0)
	var g_vel := toss * lerpf(300.0, 650.0, power)
	var g_ang := randf_range(-8.0, 8.0)
	var fuse_left: float = maxf(0.05, _cook_fuse() - cook)
	if Net.is_networked():
		var pid := _next_proj_id
		_next_proj_id += 1
		_cast("net_grenade", [g_pos, g_vel, g_ang, _cook_cluster, pid, fuse_left, HostHits.game_ms()])
	else:
		net_grenade(g_pos, g_vel, g_ang, _cook_cluster, 0, fuse_left)


func _shake(amount: float) -> void:
	# Screen shake is now a 0..2 intensity slider (#73). 0 = fully disabled;
	# 1.0 preserves the old feel; up to 2 for players who like it punchier.
	var mag: float = float(Settings.screen_shake_intensity)
	if mag <= 0.001:
		return
	# Only the soldier whose camera you are looking through shakes your screen
	# (net_shoot also runs on remote replicas of other players).
	if cam == null or not cam.is_current():
		return
	ScreenFeel.shake(amount * mag)


# Where this soldier's sounds come from: the local player's own sounds play
# centred at full volume; everyone else's are positional.
func _sfx_at() -> Vector2:
	if not multiplayer.has_multiplayer_peer() or is_multiplayer_authority():
		return Sfx.NOWHERE
	return global_position


func take_damage(amount: float, killer := "", weapon := "", killer_team := -1) -> void:
	if dead:
		return
	# Release-gate only (--smoke-cheat=godmode): play a client that ignores hits.
	if test_cheat == "godmode" and killer != display_name:
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
			_cast("net_die", [last_killer, last_weapon, last_killer_team])
		else:
			_die()


func _die() -> void:
	if dead:
		return
	dead = true
	# Killed while cooking a grenade: it drops at your feet, still live.
	if _cook_t >= 0.0 and grenades > 0:
		var left: float = maxf(0.05, _cook_fuse() - _cook_t)
		_cook_t = -1.0
		grenades -= 1
		if Net.is_networked() and multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
			var pid := _next_proj_id
			_next_proj_id += 1
			_cast("net_grenade", [global_position + Vector2(0, -8), Vector2(0, -60), 0.0, _cook_cluster, pid, left, HostHits.game_ms()])
		elif not Net.is_networked():
			net_grenade(global_position + Vector2(0, -8), Vector2(0, -60), 0.0, _cook_cluster, 0, left)
	Sfx.gib(global_position)
	Sfx.death(global_position, last_weapon.ends_with("(headshot)"))
	if Net.is_networked():
		# Host emits (not victim) so the kill is not lost if the dying client disconnects
		# between take_damage and the RPC flush.
		if Net.is_host():
			var m := get_parent()
			if m != null:
				m.bcast("net_kill_feed", [last_killer, display_name, last_weapon, last_killer_team, team], true)
	else:
		_emit_kill()
	# defer FX spawn out of the physics flush (bullet body_entered → take_damage path)
	# Lo-fi (#25): skip the CPUParticles2D burst + physics gib pieces on low-end PCs.
	if not Settings.lofi:
		_spawn_gibs.call_deferred()
	died.emit()
	if Net.is_networked() and Net.is_host():
		# Main owns the timer: a lambda on this (about to be freed) body could
		# be dropped, and the delay must match what the death screen shows.
		var m := get_parent()
		if m != null and m.has_method("_schedule_peer_respawn"):
			m._schedule_peer_respawn(get_multiplayer_authority(), int(team))
	if Net.is_networked():
		# Keep an inert husk under the same name for a moment: state / shot
		# packets already in flight from the owner still address this path,
		# and a freed node makes every peer log "Node not found". The husk
		# ignores them (dead) and the respawn renames it out of the way.
		_become_husk()
		get_tree().create_timer(_husk_secs).timeout.connect(func() -> void:
			if is_instance_valid(self):
				queue_free())
	else:
		queue_free()


func _become_husk() -> void:
	remove_from_group("soldier")
	hide()
	collision_layer = 0
	collision_mask = 0
	velocity = Vector2.ZERO
	set_physics_process(false)
	set_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)


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
	_semi_armed = false
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
	_drop_times.clear()
	_recent_drops.clear()
	# Gun Game: round reset clears the ladder for a fresh race.
	if Settings.game_mode == Settings.MODE_GG:
		gg_level = 0
		_apply_gg_weapon()


# ── RPCs ──────────────────────────────────────────────

# any_peer + explicit sender check: a client sends its state to the HOST only,
# and the host relays it to the peers that have finished loading. The old
# rpc() broadcast went through Godot's server relay to every peer, including
# ones still loading the match ("Node not found: Main/Player_N" spam).
@rpc("any_peer", "call_remote", "unreliable_ordered")
func net_state(pos: Vector2, vel: Vector2, aim: Vector2, face: float, jetting: bool, hp: float, fuel_val: float, wi: int, mag: int, is_reloading: bool, grens: int, sec_i: int, sec_mag: int, use_sec: bool, crouch_f: bool, prone_f: bool, climb_f: bool = false, host_ms: int = 0, gstamp: int = 0) -> void:
	var sender := multiplayer.get_remote_sender_id()
	var auth := get_multiplayer_authority()
	if sender != auth and sender != 1:
		return   # only the owner (or the host relaying it) may move this body
	# #266: the host stamps what it sends with its clock; our shots tell it
	# which of its moments we were looking at (view_ms in net_shoot).
	if sender == 1 and host_ms > 0 and not Net.is_host():
		HostHits.note_view(host_ms)
	if dead:
		return
	if Net.is_host() and sender == auth and auth != 1:
		# Check the owner's story before anyone else hears it (trust_guard.gd).
		fuel_val = clampf(fuel_val, 0.0, 100.0)
		var g := _trust_guard()
		TrustGuard.clock_note(auth, gstamp)
		if g != null:
			var riding := _trust_riding()
			var force := g.check_move(pos, _trust_world(), riding)
			# Health is the host's ledger (#266): the client's figure is only
			# compared, and corrected when it drifts.
			if g.check_hp(hp, health, _owner_rtt(), display_name):
				_send_hit(0.0, "", "", -1)
			hp = health
			var mj: float = MatchConfig.mod_jet()
			var fv: Dictionary = g.check_fuel(jetting, fuel_val, JET_DRAIN / maxf(0.1, mj), JET_REGEN * mj, 0.0 if Settings.realistic else 100.0)
			fuel_val = float(fv["fuel"])
			if force == "":
				force = str(fv["force"])
			g.note_aim(aim)
			g.note_track(gstamp, pos, vel, aim)
			# A reload the host saw refills that magazine (shot checks, #266).
			var slot := (100 + sec_i) if use_sec else wi
			var rw := _weapon_for_slot(slot)
			if not rw.is_empty():
				g.note_reload(slot, is_reloading, int(rw["mag"]), float(rw["reload"]), gstamp)
			if force != "":
				_trust_force_death(force)
				return
			if not _aim_pending.is_empty():
				_resolve_aim(true)
		var m := get_parent()
		if m != null and m.has_method("ready_peer_ids"):
			for pid in m.ready_peer_ids():
				if int(pid) != auth:
					rpc_id(int(pid), "net_state", pos, vel, aim, face, jetting, hp, fuel_val, wi, mag, is_reloading, grens, sec_i, sec_mag, use_sec, crouch_f, prone_f, climb_f, Time.get_ticks_msec())
	net_apply_pos(pos, vel)
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


@rpc("any_peer", "call_remote", "reliable")
func net_shoot(shot_pos: Vector2, dirs: PackedVector2Array, weapon_i: int, base_proj_id: int = 0, view_ms: int = 0, stamp: int = 0) -> void:
	# Resolve the weapon FIRST so the fire-rate gate runs before _net_accept
	# relays the shot (#254) — a shot the host rejects must not be fanned out
	# to the other clients either. Slots ≥ 100 are secondaries at (slot - 100).
	var w := _weapon_for_slot(weapon_i)
	if w.is_empty():
		return
	# #266: the host checks a remote human's shot before it counts or is
	# relayed (pellets, muzzle at the body, aim, magazine, long-run rate).
	var spawn_at := shot_pos
	var hold: Dictionary = {}
	var rw_shot := -1   # host: rewind for this shot's hits on remote humans
	if _host_checks_sender():
		var chk := _host_shot_check(shot_pos, dirs, w, weapon_i, stamp)
		if not bool(chk["ok"]):
			return
		dirs = chk["dirs"]
		spawn_at = chk["pos"]
		hold = chk["hold"]
		rw_shot = HostHits.rewind_from_view(view_ms, _owner_rtt())
		if OS.get_cmdline_user_args().has("--hosthits-log"):
			print("HOSTRECV shot=%d rewind=%d by=%s view_age=%d rtt=%d" % [base_proj_id, rw_shot, display_name, Time.get_ticks_msec() - view_ms if view_ms > 0 else -1, _owner_rtt()])
	if not _net_accept("net_shoot", [shot_pos, dirs, weapon_i, base_proj_id, view_ms, stamp]):
		return
	_trust_note_attack()
	var kind := str(w.get("kind", "bullet"))
	var is_explosive := kind == "rocket" or kind == "launcher"
	muzzle_t = 0.10 if is_explosive else 0.08
	_shake(6.0 if is_explosive else 3.5)
	if kind != "melee" and kind != "melee_cont" and get_parent() != null:
		var GfxS = preload("res://scripts/gfx.gd")
		GfxS.muzzle(get_parent(), shot_pos, is_explosive, dirs[0] if dirs.size() > 0 else aim_dir)
		if kind == "bullet":
			GfxS.casing(get_parent(), global_position + Vector2(facing * 2.0, -10.0), facing, str(w["name"]) == "Spas-12")
	Sfx.shoot(str(w["name"]), _sfx_at())
	if kind == "melee" or kind == "melee_cont":
		var swing: Vector2 = dirs[0] if dirs.size() > 0 else aim_dir
		var reach: float = float(w.get("range", 32.0))
		var dmg: float = float(w["damage"]) * MatchConfig.mod_damage()
		# Berserker bonus (#78) — one-hit-kill melee. 999 blows through vest halving.
		if bonus_kind == "berserker":
			dmg = 999.0
		# Scan soldiers in a short forward arc. Whoever decides each body's hits
		# applies it (host_hits.gd): the host for humans, the owner for bots.
		# #266: on the host, a remote swinger's reach is measured from where it
		# says it is, against remote humans as the swinger saw them (rewound).
		var origin_h := _net_base_pos() if _trust != null else global_position
		var at_swing = _trust.pos_at_stamp(stamp) if _trust != null else null
		if at_swing != null:
			origin_h = at_swing
		var rw := maxi(0, rw_shot)
		for s in get_tree().get_nodes_in_group("soldier"):
			if s == self or not is_instance_valid(s):
				continue
			if bool(s.get("dead")):
				continue
			# Team-mate swings pass through unless host FF is on (#74). Self-melee
			# isn't a thing here (we already skip s == self above).
			if int(s.get("team")) == team and not MatchConfig.friendly_fire_on():
				continue
			if not _melee_reaches(s, swing, reach, origin_h, rw):
				continue
			HostHits.damage(s, dmg, display_name, str(w["name"]), team)
			preload("res://scripts/bullet.gd").local_hit_feedback(get_tree(), display_name, s.global_position, dmg, true, s)
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
			r.global_position = spawn_at + bdir * 4.0
			if not hold.is_empty():
				r.hold = hold
			r.rewind_ms = rw_shot
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
			b.global_position = spawn_at + bdir * 4.0
			if not hold.is_empty():
				b.hold = hold
			b.rewind_override = rw_shot
			b.shot_id = base_proj_id
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
			if Net.is_networked() and multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
				b.lag_ms = lag_comp_ms()
			if Gostek.Custom.TRACERS.has(str(cosmetics.get("tracer", ""))):
				b.tint = Gostek.Custom.TRACERS[str(cosmetics.get("tracer", ""))]
			get_parent().add_child(b)


@rpc("any_peer", "call_remote", "reliable")
func net_grenade(g_pos: Vector2, g_vel: Vector2, g_ang: float, cluster: bool = false, proj_id: int = 0, fuse_left: float = -1.0, stamp: int = 0) -> void:
	if _host_checks_sender():
		# #266: no more grenades than the soldier carries, from its own hand,
		# no harder than a full wind-up throws.
		var why := ""
		var off := g_pos.distance_to(_net_base_pos())
		if not _trust_riding() and not _trust.placed_recently() and off > 60.0 + _net_vel.length() * 0.1:
			why = "thrown %.0f px from its body" % off
		elif g_vel.length() > 700.0 or not is_finite(g_vel.x) or not is_finite(g_vel.y):
			why = "thrown at %.0f px/s" % g_vel.length()
		elif not _trust.take_grenade(stamp):
			why = "more grenades than it carries (or faster than it can throw)"
		if why != "":
			if _trust.flag("grenade", why):
				_trust_force_death("shots (grenades)")
			return
		fuse_left = minf(fuse_left, maxf(GRENADE_FUSE, CLUSTER_FUSE))
	if not _net_accept("net_grenade", [g_pos, g_vel, g_ang, cluster, proj_id, fuse_left, stamp]):
		return
	_trust_note_attack()
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
	if fuse_left >= 0.0:
		g.fuse = fuse_left   # cooked in hand before the throw
	if Net.is_networked() and proj_id > 0:
		g.set_multiplayer_authority(get_multiplayer_authority())
	get_parent().add_child(g)


@rpc("authority", "call_local", "reliable")
func net_drop_weapon(weapon_name: String, from_pos: Vector2, aim: Vector2, mag: int = -1) -> void:
	_trust_note_attack()
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


@rpc("any_peer", "call_remote", "reliable")
func net_die(killer: String, weapon: String, killer_team: int) -> void:
	# The victim names its own killer; the host only passes on credit for
	# someone who was actually attacking (trust_guard.gd).
	if Net.is_host() and multiplayer.multiplayer_peer != null and not dead:
		var sender := multiplayer.get_remote_sender_id()
		if sender != 0 and sender != 1 and sender == get_multiplayer_authority() \
				and not TrustGuard.kill_credit_ok(killer, display_name, int(team)):
			print("TRUST kill credit stripped: %s claimed by %s (%s)" % [killer, display_name, weapon])
			killer = ""
			killer_team = -1
	if not _net_accept("net_die", [killer, weapon, killer_team]):
		return
	last_killer = killer
	last_weapon = weapon
	last_killer_team = killer_team
	_die()


func _spawn_gibs() -> void:
	# Deferred from _die: the scene may be changing (round/map switch) by now.
	if not is_inside_tree() or get_parent() == null:
		return
	# Phase B (#271): pooled limb gibs + blood (scripts/gfx/fx_world.gd) — no
	# CPUParticles2D / RigidBody2D per death. Blood slider 0 = none (#73).
	if float(Settings.blood_intensity) <= 0.01:
		return
	var w := FxWorld.ensure(get_parent())
	if w != null:
		w.gib(global_position, velocity, color, cosmetics, _gib_explosive(last_weapon), facing)


static func _gib_explosive(weapon: String) -> bool:
	return weapon in ["LAW", "M79", "Grenade", "Cluster", "Buggy", "Tank", "Heli", "Plane", "M2"] or weapon.begins_with("Grenade")


## Compact snapshot for match replays (replay_recorder.gd).
func replay_state() -> Array:
	var w := _active_weapon()
	var back_wn: String = str(weapons[weapon_index]["name"]) if using_secondary else str(secondary[secondary_index]["name"])
	var on_floor := is_on_floor() if (multiplayer.multiplayer_peer == null or is_multiplayer_authority()) else absf(velocity.y) < 5.0
	var bits := (1 if jet_on else 0) | (2 if dead else 0) | (4 if (on_floor or climbing) else 0) \
		| (8 if crouching else 0) | (16 if prone else 0) | (32 if reloading else 0)
	return [snappedf(global_position.x, 0.1), snappedf(global_position.y, 0.1), snappedf(aim_dir.angle(), 0.01), int(signf(facing)),
		roundi(velocity.x), roundi(velocity.y), bits, str(w["name"]), back_wn, roundi(health)]


## Reused every frame by _draw() (SoldierArt.draw_soldier input).
var _draw_state := SoldierDrawState.new()
var _feel := SoldierFeel.new()   # squash / recoil / damage flash (#271), visual only


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
	var ds := _draw_state
	ds.body_color = color
	ds.facing = facing
	ds.aim_dir = aim_dir
	ds.vel = vel_for_pose
	ds.jet_on = jet_on
	ds.dead = dead
	ds.weapon_color = w["color"]
	ds.weapon_kind = str(w.get("kind", "bullet"))
	ds.muzzle_t = muzzle_t
	ds.health = health
	ds.fuel = fuel
	ds.show_fuel = true
	ds.weapon_name = str(w["name"])
	ds.on_floor = on_floor
	ds.reloading = reloading
	ds.crouching = crouching
	ds.prone = prone
	ds.melee_swing = melee_swing_t > 0.0
	ds.gesture_anim = gesture_anim
	ds.rolling = roll_t > 0.0
	ds.ceasefire = ceasefire_t > 0.0
	ds.cosmetics = cosmetics
	ds.back_weapon_name = back_wn
	ds.grenade_count = grenades
	ds.use_cluster = use_cluster
	ds.is_local = is_multiplayer_authority()
	_feel.update(self, ds)
	SoldierArt.draw_soldier(self, ds)
	if _cook_t >= 0.0:
		# Grenade in hand + a fuse ring that empties (and flashes red) as it cooks.
		var left: float = clampf(1.0 - _cook_t / _cook_fuse(), 0.0, 1.0)
		var hand := Vector2(aim_dir.x * 10.0, -18.0 + aim_dir.y * 6.0)
		draw_circle(hand, 4.2, Color(0, 0, 0, 0.8))
		draw_circle(hand, 3.2, Color(0.35, 0.45, 0.22))
		var warn: bool = left < 0.35 and int(_cook_t * 10.0) % 2 == 0
		var ring_col := Color(1.0, 0.25, 0.2) if left < 0.35 else Color(1.0, 0.85, 0.3)
		draw_arc(Vector2(0, -60), 9.0, 0.0, TAU, 24, Color(0, 0, 0, 0.55), 4.5)
		draw_arc(Vector2(0, -60), 9.0, -PI * 0.5, -PI * 0.5 + TAU * left, 24, ring_col if not warn else Color(1, 1, 1), 3.0)


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
		# Host relays the owner's clear to the other loaded peers.
		if Net.is_host() and sender != 0 and sender == get_multiplayer_authority():
			_fanout("net_bonus_clear", [], sender)
	_clear_bonus_local()


# Medikit / grenade kit (v1.18). Host decides, every peer applies (the owner's
# copy is the one that counts; its state sync carries it from there).
func apply_kit(kind: String) -> void:
	_apply_kit_local(kind)
	if Net.is_networked() and Net.is_host() and multiplayer.has_multiplayer_peer():
		_fanout("net_kit_apply", [kind], -1)


@rpc("any_peer", "call_remote", "reliable")
func net_kit_apply(kind: String) -> void:
	if multiplayer.multiplayer_peer != null and multiplayer.get_remote_sender_id() != 1:
		return
	_apply_kit_local(kind)


# Explain a pickup on the local player's HUD (never for other soldiers).
func _pickup_toast(title: String, desc: String, col: Color) -> void:
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
	var m := get_parent()
	if m == null or m.get("player") != self or m.get("hud") == null:
		return
	if m.hud.has_method("toast"):
		m.hud.toast(title, desc, col)


func _apply_kit_local(kind: String) -> void:
	if dead:
		return
	_pickup_toast(GameInfo.item_label(kind), "healed to full" if kind == "medkit" else "grenades refilled to 3",
		Color(0.55, 1.0, 0.55) if kind == "medkit" else Color(0.85, 0.95, 0.55))
	if kind == "medkit":
		health = 100.0   # on the host's copy of a remote human: the ledger (#266)
		if _trust != null:
			_trust.note_ledger(health)
	elif kind == "grenades":
		grenades = 3
		if _trust != null:
			_trust.grenades = 3


func apply_bonus(kind: String, duration: float) -> void:
	# Fire the RPC (call_local) so every peer applies. In SP this just calls
	# the local method — no multiplayer peer to route through.
	# Host-only grant, fanned out to peers that have loaded the match (a
	# plain rpc() also hit peers still loading: "Node not found").
	_apply_bonus_local(kind, duration)
	if Net.is_networked() and Net.is_host() and multiplayer.has_multiplayer_peer():
		_fanout("net_bonus_apply", [kind, duration], -1)


func _apply_bonus_local(kind: String, duration: float) -> void:
	# Snap out of any prior bonus so saved state doesn't stack.
	if bonus_kind != "":
		_clear_bonus_local()
	bonus_kind = kind
	bonus_t = duration
	_pickup_toast(GameInfo.item_label(kind), GameInfo.item_desc(kind), BonusPickup.kind_color(kind))
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
	if Net.is_networked() and is_multiplayer_authority() and multiplayer.has_multiplayer_peer():
		if Net.is_host():
			_fanout("net_bonus_clear", [], -1)
		else:
			rpc_id(1, "net_bonus_clear")
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

# Replica smoothing: remote bodies ease toward the latest authoritative
# position (extrapolated by its velocity for up to 0.1 s) instead of snapping
# to every packet — reads smooth over real-world latency / jitter.
var _net_pos := Vector2.INF
var _net_vel := Vector2.ZERO
var _net_age := 0.0
const NET_SNAP_DIST := 160.0
const STATE_SEND_HZ := 30.0
var _state_send_acc := 0.0


func hitbox_now() -> Rect2:
	var sz: Vector2 = shape_stand.size
	if col_shape != null and col_shape.shape is RectangleShape2D:
		sz = (col_shape.shape as RectangleShape2D).size
	return Rect2(global_position + Vector2(-sz.x * 0.5, -sz.y), sz)


func _record_hitbox() -> void:
	var now := Time.get_ticks_msec()
	var box := hitbox_now()
	# Riding: the seat on this peer's copy of the vehicle, as every other
	# screen shows it (#266) — whatever order the two bodies move in.
	var seat := _vehicle_seat()
	if seat >= 0:
		var at: Vector2 = mounted_m2._seat_world(seat)
		box.position = at + Vector2(-box.size.x * 0.5, -box.size.y)
	pos_hist.append([now, box])
	while pos_hist.size() > 2 and now - int(pos_hist[0][0]) > HostHits.HIST_MS:
		pos_hist.pop_front()


# Hitbox as it was `ms_ago` milliseconds ago (the newest frame recorded at or
# before then; the oldest one kept if it is older than the history).
func hitbox_at(ms_ago: int) -> Rect2:
	if pos_hist.is_empty():
		return hitbox_now()
	var want := Time.get_ticks_msec() - ms_ago
	var lo := 0
	var hi := pos_hist.size() - 1
	if int(pos_hist[hi][0]) <= want:
		return pos_hist[hi][1]
	if int(pos_hist[0][0]) > want:
		return pos_hist[0][1]
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if int(pos_hist[mid][0]) <= want:
			lo = mid
		else:
			hi = mid
	# Between two recorded frames: blend them (same stance shape on both).
	var a: Rect2 = pos_hist[lo][1]
	var b: Rect2 = pos_hist[hi][1]
	var t0 := int(pos_hist[lo][0])
	var t1 := int(pos_hist[hi][0])
	if t1 <= t0 or a.size != b.size:
		return a
	return Rect2(a.position.lerp(b.position, float(want - t0) / float(t1 - t0)), a.size)


# How far back a bullet fired by this (remote) shooter should check the local
# player: both players' latency to the host, capped so nobody gets shot
# around a corner they turned long ago.
func lag_comp_ms() -> int:
	var m := get_tree().current_scene
	if m == null or m.get("peer_pings") == null:
		return 0
	var pings: Dictionary = m.peer_pings
	var lp = m.get("player")
	var mine: int = int(pings.get(str(lp.display_name), 0)) if lp != null and is_instance_valid(lp) else 0
	var theirs: int = int(pings.get(display_name, 0))
	return clampi(int((mine + theirs) * 0.75), 0, LAG_COMP_MAX_MS)


# ── host-side trust checks (trust_guard.gd) ──

func _trust_guard() -> TrustGuard:
	if _trust == null and TrustGuard.enabled() and multiplayer.multiplayer_peer != null \
			and get_multiplayer_authority() != 1:
		_trust = TrustGuard.new(int(CEASEFIRE_SECS * 1000.0), _owner_rtt())
	return _trust


## Host: the round trip to this body's owner (0 if unknown).
func _owner_rtt() -> int:
	var m := get_parent()
	if m == null or m.get("_net") == null or not m._net.has_method("peer_rtt_ms"):
		return 0
	return int(m._net.peer_rtt_ms(get_multiplayer_authority()))


## The vehicle seat this soldier sits in (mounted_m2 is the vehicle), or -1.
func _vehicle_seat() -> int:
	if mounted_m2 == null or not is_instance_valid(mounted_m2) or not mounted_m2.has_method("_seat_world"):
		return -1
	return int(mounted_m2.seat_of(self))


## Seated in a buggy / tank or on an M2: the body is placed by the vehicle
## (getting in snaps it to the seat), so movement isn't the soldier's own.
func _trust_riding() -> bool:
	if mounted_m2 != null:
		return true
	for v in get_tree().get_nodes_in_group("vehicle"):
		if v.has_method("seat_of") and int(v.seat_of(self)) >= 0:
			return true
	return false


func _trust_world() -> Rect2:
	var m := get_parent()
	if m == null or m.get("MAP_W") == null:
		return Rect2()
	# Sky is open (jets), so only the sides and far below are checked.
	return Rect2(0.0, -100000.0, float(m.get("MAP_W")), 100000.0 + float(m.get("MAP_H")))


func _trust_note_attack() -> void:
	if not TrustGuard.enabled():
		return
	TrustGuard.note_activity(display_name, int(team))
	if _trust != null:
		_trust.note_fired()


## Host only (#266): a hit on this remote human, decided by the host's own
## hit detection (bullets with rewind, melee, splash, vehicles, the BR ring).
## Mirrors take_damage: spawn protection (unless the caller clears it, like a
## run-over), the vest halving, then the ledger (this copy's `health`). The
## owner is told the result; at zero the host declares the death.
func host_damage(amount: float, killer := "", weapon := "", killer_team := -1, ignore_protection := false, coalesce := false) -> void:
	if dead or not Net.is_host():
		return
	var g := _trust_guard()
	if g == null:
		return
	if killer != display_name and not ignore_protection and g.protected():
		HostHits.count("hits_protected")
		return
	if bonus_kind == "vest" and killer != display_name:
		amount *= 0.5
	if amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	g.note_ledger(health)
	if killer != "":
		last_killer = killer
		last_weapon = weapon
		last_killer_team = killer_team
		if killer != display_name:
			g.note_hitter(killer, weapon, killer_team)
	HostHits.count("hits")
	HostHits.count("damage", amount)
	if killer != "" and not coalesce:
		var rec: Array = HostHits.by_shooter.get(killer, [0, 0.0])
		HostHits.by_shooter[killer] = [int(rec[0]) + 1, float(rec[1]) + amount]
	if OS.get_cmdline_user_args().has("--hosthits-log"):
		print("HOSTHIT %s -> %s %.1f (%s) hp %.1f" % [killer, display_name, amount, weapon, health])
	if coalesce and health > 0.0:
		_hit_pending += amount
		if Time.get_ticks_msec() - _hit_sent_ms >= HIT_BATCH_MS:
			_send_hit(_hit_pending, "", weapon, -1)
		return
	_send_hit(amount + _hit_pending, killer, weapon, killer_team)
	if health <= 0.0:
		_host_kill()


## Host only: heal this remote human's ledger (the Rambo bow regen).
func host_heal(amount: float) -> void:
	if dead or not Net.is_host() or _trust == null:
		return
	health = minf(100.0, health + amount)


func _send_hit(amount: float, killer: String, weapon: String, killer_team: int) -> void:
	_hit_pending = 0.0
	_hit_sent_ms = Time.get_ticks_msec()
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().has(get_multiplayer_authority()):
		rpc_id(get_multiplayer_authority(), "net_hit", health, amount, killer, weapon, killer_team)


## The ledger reached zero: everyone (the owner included) hears the death
## from the host, with the credit the ledger holds.
func _host_kill() -> void:
	var k := last_killer
	var kw := last_weapon
	var kt := last_killer_team
	if not TrustGuard.kill_credit_ok(k, display_name, int(team)):
		k = ""
		kt = -1
	HostHits.count("deaths")
	_fanout("net_die", [k, kw, kt], -1)
	_die()


## Owner (#266): the host decided a hit on us (or, with `amount` 0, says what
## our health is). `hp_after` is the host's ledger; the effects of a hit (bink,
## shake, credit) play here, the death comes from the host right after.
@rpc("any_peer", "call_remote", "reliable")
func net_hit(hp_after: float, amount: float, killer: String, weapon: String, killer_team: int) -> void:
	if multiplayer.get_remote_sender_id() != 1 or not is_multiplayer_authority() or dead:
		return
	# Release-gate only (--smoke-cheat): a modified client that ignores the
	# host (godmode) or takes half of every hit (partial).
	if test_cheat == "godmode":
		return
	if test_cheat == "partial":
		health = maxf(1.0, health - amount * 0.5)
		return
	HostHits.count("hits_taken")
	if amount > 0.0:
		HostHits.count("damage_taken", amount)
		var bv := _bink_for(weapon)
		if bv > 0.0:
			bink_t = minf(100.0, bink_t + bv)
		_shake(7.0)
		if killer != "":
			last_killer = killer
			last_weapon = weapon
			last_killer_team = killer_team
	health = clampf(hp_after, 0.0, 100.0)


## Round reset: the owner is about to jump to a spawn at full health (and a
## fresh magazine, grenades, fuel and spawn protection).
func trust_amnesty() -> void:
	if _trust != null:
		health = 100.0
		_trust.amnesty(int(CEASEFIRE_SECS * 1000.0), _owner_rtt())


## Host: where the owner last said this body is (unsmoothed, extrapolated a
## little) — the muzzle of a shot it fires is measured from here.
func _net_base_pos() -> Vector2:
	if _net_pos == Vector2.INF:
		return global_position
	return _net_pos + _net_vel * minf(_net_age, 0.1)


## Host: is the RPC being handled the remote owner speaking for this body?
func _host_checks_sender() -> bool:
	return _trust != null and Net.is_host() and multiplayer.multiplayer_peer != null and not dead \
			and multiplayer.get_remote_sender_id() == get_multiplayer_authority()


## Melee reach (same arc as ever). On the host a remote human victim is taken
## where a remote swinger saw it (`rw` ms back) from where the swinger is.
func _melee_reaches(s: Node, swing: Vector2, reach: float, origin_h: Vector2, rw: int) -> bool:
	var origin := global_position
	var pts: Array = [(s as Node2D).global_position]
	if HostHits.is_remote_human(s):
		origin = origin_h
		pts = [HostHits.pos_at(s, rw)]
	for p in pts:
		var to_s: Vector2 = (p as Vector2) - origin
		var d: float = to_s.length()
		if d > reach or d < 1.0:
			continue
		if to_s.normalized().dot(swing) < 0.35:  # ~70° arc
			continue
		return true
	return false


## Host (#266): check a remote human's net_shoot before it counts. Returns
## {ok, dirs (unit), pos (where the host's copy starts), hold (aim re-check)}.
func _host_shot_check(shot_pos: Vector2, dirs: PackedVector2Array, w: Dictionary, slot: int, stamp: int) -> Dictionary:
	var no := {"ok": false}
	var g := _trust
	var wname := str(w["name"])
	var kind := str(w.get("kind", "bullet"))
	var melee := kind == "melee" or kind == "melee_cont"
	var want: int = 1 if melee else int(w["pellets"])
	if dirs.size() != want:
		if g.flag("shot", "%d directions for a %s shot (%d)" % [dirs.size(), wname, want]):
			_trust_force_death("shots (malformed)")
		return no
	var nd := PackedVector2Array()
	for d in dirs:
		if not is_finite(d.x) or not is_finite(d.y) or absf(d.length() - 1.0) > 0.02:
			if g.flag("shot", "%s shot direction of length %.2f" % [wname, d.length()]):
				_trust_force_death("shots (malformed)")
			return no
		nd.append(d.normalized())
	# Where it was when it fired, by its own clock (else where it last said).
	var base := _net_base_pos()
	var at_shot = g.pos_at_stamp(stamp)
	if at_shot != null:
		base = at_shot
	var riding := _trust_riding()
	var origin_wait := false
	if not riding:
		# Beyond where its own timeline puts the body around that moment.
		var off := g.origin_off(shot_pos, stamp)
		if off == INF:
			# No state near that moment yet (its stream is running late): the
			# shot's hits wait for one (`hold`) unless it is at the body anyway.
			origin_wait = shot_pos.distance_to(_net_base_pos()) > 80.0 + _net_vel.length() * 0.1
		elif off > 80.0:
			# Just spawned / reset: the body may have moved to a spot the host
			# hasn't heard about yet — refuse quietly (no flag) until it has.
			if g.placed_recently():
				HostHits.count("refused_origin_quiet")
				return no
			if g.flag("origin", "%s fired %.0f px from its body (max 80)" % [wname, off]):
				_trust_force_death("shots (origin)")
			return no
	var rc := g.stamp_check(get_multiplayer_authority(), wname, float(w["rate"]), stamp)
	if rc != TrustGuard.RATE_OK:
		if rc == TrustGuard.RATE_FAST and g.flag("rate", "%s fired faster than %.3f s a shot" % [wname, float(w["rate"])]):
			_trust_force_death("shots (fire rate)")
		return no
	if kind != "melee" and not g.take_round(slot, int(w["mag"]), stamp, float(w["reload"])):
		if g.flag("ammo", "%s fired past its %d-round magazine without a reload (%s)" % [wname, int(w["mag"]), g.mag_note(slot, stamp)]):
			_trust_force_death("shots (magazine)")
		return no
	var hold := {}
	var spread := float(w["spread"])
	# The streamed aims either side of the shot's own moment (its game clock).
	var around: Array = g.aims_around(stamp)
	# No aim sample yet (just spawned) or one that disagrees: hold the shot's
	# hits until the next samples show where it was really aiming.
	if melee:
		# A swing lands at once and reaches ~34 px, and an aim can reverse in
		# one frame (stick, flick past the body), so a swing is never refused
		# on aim — only counted.
		if g.last_aim() != null and not g.aim_ok_now(nd[0], spread):
			HostHits.count("melee_aim_off")
	elif around[0] != null and around[1] != null:
		# Both samples either side of its own moment are in: it must lie on
		# the arc they span.
		var off := TrustGuard.aim_off_arc(nd[0], float(around[0]), float(around[1]))
		if off > spread + TrustGuard.BINK_MAX + TrustGuard.AIM_ARC_SLACK:
			_aim_refuse(off, spread, wname, true)
			return no
	elif g.last_aim() == null or not g.aim_ok_now(nd[0], spread):
		# Maybe a flick between two aim samples: its hits wait for the next ones.
		hold = {"ms": Time.get_ticks_msec(), "dir": nd[0], "spread": spread, "angles": [around[0] if around[0] != null else g.last_aim()],
				"hits": [], "done": false, "ok": true, "weapon": wname, "stamp": stamp}
		_aim_pending.append(hold)
		HostHits.count("aim_held")
	if origin_wait and not melee:
		if hold.is_empty():
			hold = {"ms": Time.get_ticks_msec(), "dir": nd[0], "spread": spread, "angles": [], "aim_ok": true,
					"hits": [], "done": false, "ok": true, "weapon": wname, "stamp": stamp}
			_aim_pending.append(hold)
		hold["origin"] = shot_pos
		HostHits.count("origin_held")
	# A muzzle poking through a wall doesn't shoot through it: the host's copy
	# starts just before the wall.
	var pos := shot_pos
	if not melee and not riding:
		var chest := base + Vector2(0.0, -hitbox_now().size.y * 0.5)
		var tip := shot_pos + nd[0] * 4.0
		var hit := HostHits.solid_ray(get_world_2d(), chest, tip)
		if not hit.is_empty():
			var u := (tip - chest).normalized()
			pos = (hit["position"] as Vector2) - u * 2.0 - nd[0] * 4.0
			HostHits.count("muzzle_in_wall")
	return {"ok": true, "dirs": nd, "pos": pos, "hold": hold}


## Host: settle shots held for an aim re-check. A shot is fine if it lies on
## the arc the aim swept around it: the streamed aims either side of its own
## game-clock moment, as soon as the one after it is in (at most AIM_HOLD_MS, or STREAM_WAIT_MS while the stream lags);
## else the samples that arrived around it, else the one sample there is.
## Then its hits count or are dropped.
const AIM_HOLD_MS := 800
# While the owner's own stream hasn't reached the shot's moment yet (a client
# running seconds behind on a starved machine), wait this long for it.
const STREAM_WAIT_MS := 5000

func _resolve_aim(new_sample: bool) -> void:
	if _trust == null:
		_aim_pending.clear()
		return
	var now := Time.get_ticks_msec()
	var a1 = _trust.last_aim()
	var keep: Array = []
	for h in _aim_pending:
		var angles: Array = h["angles"]
		if new_sample and a1 != null:
			angles.append(a1)
		# The samples either side of the shot's own moment, once the one after
		# it is in (a sample that arrived later may belong to a later moment).
		var st := int(h.get("stamp", 0))
		var waited := now - int(h["ms"])
		# The stream still behind the shot's moment: its own samples are on
		# the way, wait for them.
		var behind: bool = st > 0 and _trust.track_newest() < st and waited < STREAM_WAIT_MS
		# A muzzle with no state near its moment yet: once there is one, it
		# must be at the body then (else, at the timeout, where it last was).
		var origin_off := 0.0
		if h.has("origin"):
			origin_off = _trust.origin_off(h["origin"], st)
			if origin_off == INF and (waited < AIM_HOLD_MS or behind):
				keep.append(h)
				continue
			if origin_off == INF:
				origin_off = maxf(0.0, (h["origin"] as Vector2).distance_to(_net_base_pos()) - _net_vel.length() * 0.1)
		var around: Array = _trust.aims_around(st) if st > 0 else [null, null]
		var aim_ok: bool = bool(h.get("aim_ok", false))
		var stamped: bool = aim_ok or (around[0] != null and around[1] != null)
		# (A stamped shot waits for the sample after its moment — a stall can
		# hold that back a while; an unstamped one for two more arrivals.)
		if not stamped and ((st > 0 and (waited < AIM_HOLD_MS or behind)) or (st <= 0 and angles.size() < 3 and waited < 250)):
			keep.append(h)
			continue
		if origin_off > 80.0:
			h["done"] = true
			h["ok"] = false
			HostHits.count("refused_origin_quiet")
			HostHits.count("aim_refused_hits", float((h["hits"] as Array).size()))
			continue
		# How far outside the arc the aim swept around the shot.
		var off := INF
		if aim_ok:
			off = 0.0
		elif stamped:
			off = TrustGuard.aim_off_arc(h["dir"], float(around[0]), float(around[1]))
		else:
			for i in range(angles.size() - 1):
				if angles[i] != null and angles[i + 1] != null:
					off = minf(off, TrustGuard.aim_off_arc(h["dir"], float(angles[i]), float(angles[i + 1])))
			# Still nothing either side: the one sample there is, if any.
			if off == INF:
				for a in [around[0], around[1]] + angles:
					if a != null:
						off = TrustGuard.aim_off_arc(h["dir"], float(a), float(a))
						break
		var tol: float = float(h["spread"]) + TrustGuard.BINK_MAX + TrustGuard.AIM_ARC_SLACK
		# (INF: nothing to compare with after all. Without the owner's own
		# samples either side of the shot — its stream ran out the wait — the
		# shot can't be judged: it stands, counted.)
		var ok := off == INF or off <= tol or not stamped
		if off != INF and off > tol and not stamped:
			HostHits.count("aim_unverified")
		h["done"] = true
		h["ok"] = ok
		if ok:
			for e in h["hits"]:
				if is_instance_valid(e[0]):
					HostHits.damage(e[0], float(e[1]), str(e[2]), str(e[3]), int(e[4]))
			continue
		HostHits.count("aim_refused_hits", float((h["hits"] as Array).size()))
		# (Only the owner's own samples either side of the shot can prove it
		# off its aim; anything else is refused quietly.)
		if _aim_refuse(off, float(h["spread"]), str(h["weapon"]), stamped and not aim_ok):
			return
	_aim_pending = keep


## Count / log a shot refused for lying `off` rad outside the aim arc around
## it. Only far off is a flag; nearer (odd but possible input), or fired
## before any aim sample (just spawned), it is refused quietly — no proof of a
## cheat. Returns true when the refusal ended this life (a forced death).
func _aim_refuse(off: float, spread: float, wname: String, had_sample: bool) -> bool:
	var tol: float = spread + TrustGuard.BINK_MAX + TrustGuard.AIM_ARC_SLACK
	if not had_sample or off < tol + TrustGuard.AIM_FLAG_RAD:
		HostHits.count("aim_refused_quiet")
		return false
	if _trust.flag("aim", "%s shot %.0f° off the aim it streams" % [wname, rad_to_deg(off)]):
		_trust_force_death("shots (aim)")
		return true
	return false


## Host: the host routed a weapon pickup to this body's owner (full magazine).
func host_note_pickup(weapon_name: String) -> void:
	if _trust == null:
		return
	for i in weapons.size():
		if str(weapons[i]["name"]) == weapon_name:
			_trust.refill_slot(i)
	for i in secondary.size():
		if str(secondary[i]["name"]) == weapon_name:
			_trust.refill_slot(100 + i)


## Host-side death for a client whose reported state failed the checks.
## Everyone (the owner included) is told, the host's copy dies and schedules
## the normal respawn, and a strike is recorded; enough strikes is a kick.
func _trust_force_death(reason: String) -> void:
	if dead or not Net.is_host():
		return
	var auth := get_multiplayer_authority()
	var k := ""
	var kw := "Server"
	var kt := -1
	if _trust != null and TrustGuard.kill_credit_ok(_trust.last_hitter, display_name, int(team)):
		k = _trust.last_hitter
		kw = _trust.last_hitter_weapon
		kt = _trust.last_hitter_team
	print("TRUST forced death: %s (peer %d) — %s" % [display_name, auth, reason])
	last_killer = k
	last_weapon = kw
	last_killer_team = kt
	_fanout("net_die", [k, kw, kt], -1)
	_husk_secs = 5.0
	_die()
	var strikes := TrustGuard.add_strike(auth)
	if strikes >= TrustGuard.STRIKES_TO_KICK:
		var m := get_tree().current_scene
		if m != null and m.has_method("trust_kick"):
			m.trust_kick(auth, display_name)


func net_apply_pos(pos: Vector2, vel: Vector2) -> void:
	if _net_pos == Vector2.INF or position.distance_to(pos) > NET_SNAP_DIST:
		position = pos
	_net_pos = pos
	_net_vel = vel
	_net_age = 0.0


func _net_smooth(delta: float) -> void:
	if _net_pos == Vector2.INF:
		return
	_net_age += delta
	var tgt: Vector2 = _net_pos + _net_vel * minf(_net_age, 0.1)
	position = position.lerp(tgt, clampf(delta * 18.0, 0.0, 1.0))



# Soldat-style look-ahead: the view slides toward where you aim (mouse: by the
# cursor's distance from screen centre; stick / touch: along the aim), so you
# see threats in front of your gun instead of behind you.
const CAM_LEAD_MAX := 260.0

func _update_camera_lead(stick: Vector2, delta: float) -> void:
	if cam == null or not cam.enabled:
		return
	var lead := Vector2.ZERO
	if Settings.camera_lead and not dead:
		if stick.length() > 0.0:
			lead = aim_dir * 170.0
		elif TouchControls.instance != null:
			lead = aim_dir * 120.0
		else:
			var vp := get_viewport()
			var c := vp.get_visible_rect().size * 0.5
			lead = (vp.get_mouse_position() - c) * 0.45 / maxf(0.1, cam.zoom.x)
		lead = lead.limit_length(CAM_LEAD_MAX)
	cam.position = cam.position.lerp(lead, clampf(delta * 6.0, 0.0, 1.0))



# ── Owner → everyone RPC fan-out ─────────────────────────────────────────────
# The owning peer runs the effect locally, then: the host sends it to every
# peer that has finished loading; a client sends it to the host, which relays
# it (see _net_accept). A plain rpc() also reached peers still loading the
# match via Godot's server relay ("Node not found: Main/Player_N" spam).
static func jet_particle_color(cos: Dictionary) -> Color:
	var c: Color = Gostek.Custom.JET_COLORS.get(str(cos.get("jet", "")), Color(1.0, 0.35, 0.1))
	return c.lerp(Color(1, 1, 1), 0.15)


static func my_cosmetics() -> Dictionary:
	var C := Gostek.Custom
	return {
		"head": Settings.cos_head,
		"vest": Settings.cos_vest,
		"chain": Settings.cos_chain,
		"cigar": Settings.cos_cigar,
		"dreadlocks": Settings.cos_dreadlocks,
		"dogtag": Settings.cos_dogtag,
		"finish": C.allowed("finish", Settings.cos_finish),
		"vfinish": C.allowed("vfinish", Settings.cos_vfinish),
		"pants": C.allowed("pants", Settings.cos_pants),
		"skin": C.allowed("skin", Settings.cos_skin),
		"wskin": C.allowed("wskin", Settings.cos_wskin),
		"jet": C.allowed("jet", Settings.cos_jet),
		"tracer": C.allowed("tracer", Settings.cos_tracer),
	}


func _send_cosmetics() -> void:
	if is_inside_tree() and not dead:
		_cast("net_cosmetics", [cosmetics])


@rpc("any_peer", "call_remote", "reliable")
func net_cosmetics(c: Dictionary) -> void:
	if not _net_accept("net_cosmetics", [c]):
		return
	var out := {}
	for k in ["head", "chain", "finish", "vfinish", "pants", "skin", "wskin", "jet", "tracer"]:
		if c.has(k):
			out[k] = str(c[k]).left(16)
	for k in ["vest", "cigar", "dreadlocks", "dogtag"]:
		if c.has(k):
			out[k] = bool(c[k])
	cosmetics = out


func _cast(method: StringName, args: Array) -> void:
	callv(method, args)
	if not (Net.is_networked() and multiplayer.has_multiplayer_peer()):
		return
	if Net.is_host():
		_fanout(method, args, -1)
	else:
		callv("rpc_id", [1, method] + args)


func _fanout(method: StringName, args: Array, except_pid: int) -> void:
	var m := get_parent()
	if m == null or not m.has_method("ready_peer_ids"):
		return
	for pid in m.ready_peer_ids():
		if int(pid) != except_pid and int(pid) != multiplayer.get_unique_id():
			callv("rpc_id", [int(pid), method] + args)


# Gate for the fan-out RPCs above: accept local calls, the body's owner, or
# the host relaying the owner; the host relays an owner's call onward.
func _net_accept(method: StringName, args: Array) -> bool:
	if not is_inside_tree() or multiplayer.multiplayer_peer == null:
		return true
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return true
	var auth := get_multiplayer_authority()
	if sender != auth and sender != 1:
		return false
	if dead:
		return false   # husk of a dead body: late packets from its owner
	if Net.is_host() and sender == auth and auth != 1:
		_fanout(method, args, auth)
	return true
