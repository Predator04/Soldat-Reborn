extends CharacterBody2D
## Bot — AI soldier: leads its aim, circle-strafes, dodge-jumps, lobs grenades, jet-boots up.

signal died

@export var color := Color(0.85, 0.3, 0.25)
# Team id — main.gd assigns TEAM_BLUE/RED in team modes, or a unique
# FFA_BOT_TEAM_BASE+i per bot in free-for-all so bots fight each other.
var team := 1000
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
var _wedge_t := 0.0  # seconds resting wedged without floor contact
# Progress watchdog: if the bot hasn't moved 60 px in PROGRESS_WINDOW seconds
# while it has somewhere to go, it's wedged against terrain (no pathfinding) —
# run an escape manoeuvre: reverse direction and jet up for a moment.
var _progress_anchor := Vector2.ZERO
var _progress_t := 0.0
var _escape_t := 0.0
var _escape_dir := 1.0
var _escape_len := 0.0      # length of the current escape (grows on repeats)
var _escape_streak := 0     # consecutive escapes without leaving the area
var _since_escape := 99.0
const PROGRESS_WINDOW := 2.5
const ESCAPE_TIME := 1.6

# ── Brain (v1.14) ─────────────────────────────────────────────────────────
# Every THINK_INTERVAL the bot picks a GOAL (a world position) from the game
# mode — grab / return / deliver flags, capture DOM points, collect PM points,
# grab the Rambo bow, stay in the BR ring, hunt enemies — then follows an A*
# path over the map's baked nav graph (scripts/nav_graph.gd) to reach it.
# Combat (aim/fire) runs independently, so bots shoot while travelling.
const THINK_INTERVAL := 0.35
var _think_cd := 0.0
var _goal := Vector2.INF
var _goal_label := ""          # debug / tests: "flag", "home", "hunt", ...
var _role := ""                # team objective modes: "attack" | "defend"
var _patrol_pos := Vector2.INF
var _patrol_t := 0.0
var _dom_choice: Node2D = null
var _path: PackedVector2Array = PackedVector2Array()
var _path_i := 0
var _path_goal := Vector2.INF
var _repath_t := 0.0
var _target_visible := false
var _visible_check_t := 0.0
var _last_seen_pos := Vector2.INF   # where the current target was last seen
var _refuel_wait := false           # standing still to refill jets before a climb
var _blocked_t := 0.0               # pushing into something without moving
var _gap_ahead := false             # next path link crosses a bottomless gap

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
	"Spas-12":      {"damage": 9.0,   "rate": 0.9,   "speed": 850.0,  "kind": "bullet", "pellets": 8, "spread": 0.26},
	"Ruger 77":     {"damage": 82.0,  "rate": 1.0,   "speed": 1450.0, "kind": "bullet"},
	"M79":          {"damage": 90.0,  "rate": 3.0,   "speed": 470.0,  "kind": "bullet"},
	"Barrett":      {"damage": 245.0, "rate": 2.2,   "speed": 2400.0, "kind": "bullet"},
	"Minimi":       {"damage": 23.0,  "rate": 0.20,  "speed": 1180.0, "kind": "bullet"},
	"Minigun":      {"damage": 13.0,  "rate": 0.066, "speed": 1275.0, "kind": "bullet"},
	"Flamethrower": {"damage": 19.0,  "rate": 0.08,  "speed": 420.0,  "kind": "bullet", "life": 0.35, "visual": "flame"},
	"Rambo Bow":    {"damage": 12.0,  "rate": 1.5,   "speed": 900.0,  "kind": "bullet"},
	"USSOCOM":      {"damage": 27.0,  "rate": 0.167, "speed": 800.0,  "kind": "bullet"},
	"LAW":          {"damage": 90.0,  "rate": 1.6,   "speed": 720.0,  "kind": "rocket"},
	# Gun Game melee rungs: bots don't do full melee arc scans, so approximate with
	# a very-short-life bullet — travels ~60px then dies harmlessly. Damage still
	# routes through take_damage with the correct weapon_name for GG kill scoring.
	"Knife":        {"damage": 55.0,  "rate": 0.5,   "speed": 600.0,  "kind": "bullet", "life": 0.10},
	"Chainsaw":     {"damage": 3.0,   "rate": 0.10,  "speed": 600.0,  "kind": "bullet", "life": 0.10},
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
# #114 — obstacle / burst / pickup state.
# `_ledge_hop_cd` throttles preemptive hops so a bot pressed against a wall
# doesn't spam jumps every frame (feels like a jitter bug).
# `_burst_shots` counts shots in the current burst for auto weapons; when it
# hits the per-weapon burst cap, fire_cd gets a small pause so bots don't
# hose a 100-round mag in one continuous stream.
# `_pickup_target` biases movement toward a nearby weapon / bonus pickup when
# no enemy is closer — bots grab loot instead of running past it.
# `_pickup_scan_cd` throttles the O(pickups) scan so it isn't per-frame.
var _ledge_hop_cd: float = 0.0
var _burst_shots: int = 0
var _burst_cool: float = 0.0
var _pickup_target: Node2D = null
var _pickup_scan_cd: float = 0.0
var _pickup_t: float = 0.0  # seconds spent chasing the current pickup
# Per-weapon burst caps: how many consecutive shots before we pause. Semi-auto
# guns already have generous fire_cd (Barrett 2.2s, Ruger 1.0s) — no cap needed.
# Auto guns get short bursts so the aim jitter (bink) has time to settle and
# the bot reads as thinking rather than as a spray-lock aim-bot.
const BURST_CAP := {
	"MP5": 6,
	"AK-74": 5,
	"Steyr AUG": 5,
	"Minimi": 10,
	"Minigun": 20,
	"Flamethrower": 25,
}
const BURST_PAUSE := 0.35

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
# Ladder awareness (#89) — bots mirror the player's climb engage/dismount so
# ladder-gated targets are reachable. Constants match player.gd so the physics
# and detection footprint read the same.
const CLIMB_SPEED := 150.0
const CLIMB_BODY_PAD_TOP := 24.0
const CLIMB_BODY_PAD_BOTTOM := 6.0
const LADDER_SEEK_RANGE := 150.0   # walk to a ladder within this horizontal band
const LADDER_SEEK_UP := -40.0      # target must be at least this many px above

var on_ladder := false
var climbing := false
var _active_ladder: Node2D = null

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
	# Terrain layer 3 (bit 4) = ported "only players collide" polys.
	# Soldiers live on their own layer 4 (bit 8) and don't collide with each
	# other (as in Soldat) — bodies shoving one another used to push soldiers
	# into walls and block narrow tunnels. Bullets/rockets/grenades/pickups
	# mask bit 8 to keep hitting them.
	collision_layer = 8
	collision_mask = 1 | 4
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
	# Same feet-anchored 14×24 box as the player (#72). The old centred 20×42
	# box put the physics floor ~21 px below the sprite's feet — bots hovered
	# above the ground — and needed 42 px of headroom, so bots wedged in
	# tunnels and ledges that players walk through.
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(14, 24)
	shape.shape = rect
	shape.position = Vector2(0, -rect.size.y * 0.5)
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
	_ledge_hop_cd = maxf(0.0, _ledge_hop_cd - delta)
	_burst_cool = maxf(0.0, _burst_cool - delta)
	_refresh_target(delta)
	_scan_pickup(delta)
	_visible_check_t -= delta
	if _visible_check_t <= 0.0:
		_visible_check_t = 0.2
		_target_visible = is_instance_valid(target) and _has_line_of_sight(target)
		if _target_visible:
			_last_seen_pos = target.global_position
	_think_cd -= delta
	if _think_cd <= 0.0:
		_think_cd = THINK_INTERVAL * randf_range(0.8, 1.2)
		_think()

	var on_floor := is_on_floor() or _wedge_t > 0.2  # see _update_wedge
	var dx := 0.0
	var dy := 0.0
	if is_instance_valid(target):
		dx = target.global_position.x - global_position.x
		dy = target.global_position.y - global_position.y
	# #114: when a nearby pickup is worth grabbing, temporarily prefer walking
	# to it — but only if it's closer than the current enemy so we don't run
	# past an enemy for a marginal weapon swap. Overwrites dx/dy for the
	# movement branch only; combat/aim still targets the true enemy so we
	# keep shooting on the way.
	var pickup_override := false
	if is_instance_valid(_pickup_target):
		var p_dx: float = _pickup_target.global_position.x - global_position.x
		var p_dy: float = _pickup_target.global_position.y - global_position.y
		var enemy_far: bool = not is_instance_valid(target) or (dx * dx + dy * dy) > 300.0 * 300.0
		if enemy_far or (p_dx * p_dx + p_dy * p_dy) < 200.0 * 200.0:
			dx = p_dx
			dy = p_dy
			pickup_override = true

	# Self-preservation: entering critical HP starts a brief retreat; keep it
	# refreshing only on the crossing so a low-HP bot still re-engages.
	_retreat_t = maxf(0.0, _retreat_t - delta)
	if health < 35.0 and _prev_health >= 35.0 and not _carrying_flag():
		_retreat_t = 1.8
	_prev_health = health
	# #114: low HP + engaged + not already reloading → reload during the retreat
	# so we come back at full mag. Without this bots would retreat, walk back
	# with a partial mag, get outfought again. Bots pass on this if the active
	# mag is already ≥ half full — no gain to burning the reload window.
	if _retreat_t > 0.0 and not reloading:
		var active_mag: int = secondary_ammo if using_secondary else ammo
		var full_mag: int = int(AMMO_STATS.get(
			"USSOCOM" if using_secondary else loadout,
			AMMO_STATS["AK-74"])["mag"])
		if active_mag < full_mag / 2:
			_start_reload()

	# ── Ladder awareness (#89) — mirrors player.gd::_find_ladder_overlap engage.
	# Engage when overlapping a ladder with the target above; dismount on losing
	# overlap or closing the vertical gap. Constants match the player so climb
	# footprint reads the same on both.
	var new_ladder: Node2D = _find_ladder_overlap()
	on_ladder = new_ladder != null
	var target_above: bool = is_instance_valid(target) and dy < LADDER_SEEK_UP
	if not climbing and on_ladder and target_above:
		climbing = true
		_active_ladder = new_ladder
		if was_jet:
			was_jet = false
		jet_on = false
		velocity.y = 0.0
	if climbing:
		if not on_ladder or not is_instance_valid(target) or absf(dy) <= 10.0:
			climbing = false
			_active_ladder = null
		else:
			_active_ladder = new_ladder
	# Seek a ladder when target is above and one is within LADDER_SEEK_RANGE
	# horizontal — walk to its center-x instead of jetting into the wall.
	var seek_lad: Node2D = null
	if not climbing and target_above:
		seek_lad = _find_seek_ladder(dx, dy)

	if climbing and _active_ladder != null:
		# Ladder physics — vertical toward target, snap horizontal to center.
		var vy_climb: float = 0.0
		if dy < -8.0:
			vy_climb = -CLIMB_SPEED
		elif dy > 8.0:
			vy_climb = CLIMB_SPEED
		velocity.y = vy_climb
		var target_x: float = float(_active_ladder.get_meta("center_x", global_position.x))
		var to_center: float = target_x - global_position.x
		velocity.x = clampf(to_center * 9.0, -CLIMB_SPEED, CLIMB_SPEED)
		if is_instance_valid(target) and absf(dx) > 8.0:
			facing = signf(dx)
		jet_on = false
		if jet_particles != null:
			jet_particles.emitting = false
			jet_particles.position = Vector2(-facing * 3.3, 1.7)
		fuel = minf(100.0, fuel + 32.0 * delta)
		jump_cd = maxf(0.0, jump_cd - delta)
		_hop_cd = maxf(0.0, _hop_cd - delta)
		dodge_cd = maxf(0.0, dodge_cd - delta)
		move_and_slide()
	else:
		# circle-strafe: flip lateral direction periodically while engaged
		strafe_t -= delta
		if strafe_t <= 0.0:
			strafe_dir = 1.0 if randf() < 0.5 else -1.0
			strafe_t = randf_range(0.5, 1.2)

		var dir := 0.0
		if seek_lad != null:
			# Head straight for the ladder's center-x so the next tick's overlap
			# check can engage the climb.
			var lcx: float = float(seek_lad.get_meta("center_x", seek_lad.global_position.x))
			var to_lcx: float = lcx - global_position.x
			dir = 0.0 if absf(to_lcx) < 6.0 else signf(to_lcx)
		elif is_instance_valid(target):
			if _retreat_t > 0.0 or reloading:
				# Back off — can't fight effectively while hurt/reloading, so put
				# distance between us and the target instead of pressing in.
				dir = -signf(dx) if absf(dx) > 12.0 else -strafe_dir
			elif absf(dx) > (24.0 if _is_melee() else 120.0):
				dir = signf(dx)
			else:
				dir = strafe_dir  # close in → strafe around
		else:
			# Idle wander: pick a fresh direction periodically, flip early when we
			# reach the map edge. Prior code hard-coded `dir = 1.0` which piled
			# every targetless bot at the right wall.
			wander_t -= delta
			# Map edges come from the per-map world rect (ported maps are wider
			# or narrower than the 4800 px built-in arena).
			var world_w: float = 4800.0
			var m := get_parent()
			if m != null and m.get("MAP_W") != null:
				world_w = float(m.get("MAP_W"))
			if global_position.x < 200.0:
				wander_dir = 1.0
			elif global_position.x > world_w - 200.0:
				wander_dir = -1.0
			elif wander_t <= 0.0:
				wander_dir = 1.0 if randf() < 0.5 else -1.0
				wander_t = randf_range(WANDER_FLIP_MIN, WANDER_FLIP_MAX)
			dir = wander_dir

		# ── Navigation: follow the A* path toward the brain's goal. Skipped
		# while in a close, visible fight (strafing reads better) unless we're
		# carrying a flag, and while retreating hurt / backing off to reload.
		var nav_up := false
		var navigating := false
		var close_fight: bool = is_instance_valid(target) and _target_visible \
				and absf(dx) < 280.0 and absf(dy) < 180.0
		var busy_retreat: bool = (_retreat_t > 0.0 or reloading) and is_instance_valid(target) and not _carrying_flag()
		# Objective goals (grab / return / deliver / capture) keep the bot moving
		# even mid-fight — it shoots on the way. Hunting/patrol goals yield to
		# close-range strafing.
		var objective: bool = _goal_label in ["flag", "return", "capture", "zone"]
		if _goal != Vector2.INF and seek_lad == null and (not busy_retreat or objective) \
				and (not close_fight or objective or _carrying_flag()):
			var step := _nav_step(_goal, delta)
			if step.z > 0.5:
				dir = step.x
				nav_up = step.y > 0.5
				navigating = true
				# Fuel management: jets are weak (thrust barely beats gravity), a
				# tank lifts ~600 px. If the next climb needs more fuel than we
				# have, stand on the ground and let the tank refill first instead
				# of hopping at the wall with an empty tank forever.
				var rise: float = global_position.y - _path[_path_i].y
				var need: float = clampf(rise / 5.0 + 12.0, 15.0, 100.0)
				if _gap_ahead:
					# Never start across a bottomless gap on a low tank.
					need = maxf(need, 70.0)
					rise = maxf(rise, 46.0)
				if rise > 45.0 and fuel < need and not jet_on and not _carrying_flag_under_fire():
					_refuel_wait = true
				if _refuel_wait:
					# Stop pushing at the wall, drop to the ground (or rest wedged
					# on the slope, which also regenerates) and refill.
					if fuel >= minf(100.0, need + 35.0) or rise <= 45.0 or _carrying_flag_under_fire():
						_refuel_wait = false
					else:
						dir = 0.0
						nav_up = false
			elif _goal_label != "hunt" and (_nav() == null or _nav().is_empty()):
				# No graph (editor map) — walk straight at the objective.
				# (With a graph, "no path" means unreachable from here: walking
				# straight at it just marches the bot off a ledge.)
				var gdx: float = _goal.x - global_position.x
				dir = 0.0 if absf(gdx) < 8.0 else signf(gdx)
				nav_up = _goal.y < global_position.y - 40.0
				navigating = true

		# Pit guard: never run off an edge into a bottomless drop (below the
		# map's kill line) — unless the path is deliberately jetting across a
		# gap with a full tank. Strafing / retreating / wandering turn around.
		if dir != 0.0 and on_floor and not (navigating and _gap_ahead and fuel >= 70.0) and _pit_ahead(dir):
			if navigating:
				dir = 0.0
			else:
				dir = -dir
				strafe_dir = dir
				wander_dir = dir

		# Escape manoeuvre (see _progress_anchor). Only when the bot actually
		# wants to travel — close-range strafing legitimately stays in place.
		var wants_travel: bool = navigating or not is_instance_valid(target) or absf(dx) > 160.0 \
				or not _target_visible
		if global_position.distance_to(_progress_anchor) > 60.0 or not wants_travel:
			_progress_anchor = global_position
			_progress_t = 0.0
		else:
			_progress_t += delta
			if _progress_t > PROGRESS_WINDOW and _escape_t <= 0.0:
				# Repeated escapes from the same dead end run longer each time
				# so the bot actually commits to leaving the pocket.
				_escape_streak = _escape_streak + 1 if _since_escape < 8.0 else 0
				_escape_len = ESCAPE_TIME * float(mini(1 + _escape_streak, 4))
				_since_escape = 0.0
				_escape_t = _escape_len
				_escape_dir = -dir if dir != 0.0 else (1.0 if randf() < 0.5 else -1.0)
				wander_dir = _escape_dir
				wander_t = randf_range(WANDER_FLIP_MIN, WANDER_FLIP_MAX)
				_progress_t = 0.0
				_progress_anchor = global_position
				_repath_t = 0.0  # the path we had led into a dead end — replan
		_since_escape += delta
		if _escape_t > 0.0:
			_escape_t -= delta
			dir = _escape_dir

		velocity.x = move_toward(velocity.x, dir * RUN_SPEED * MatchConfig.mod_speed(), 1300.0 * MatchConfig.mod_speed() * delta)
		_hop_cd = maxf(0.0, _hop_cd - delta)

		# #114 — preemptive ledge/wall hop. If we're walking into a wall or about
		# to walk off a ledge, jump. Independent of the stuck-detection retry so
		# bots skip low walls and small gaps on the first attempt instead of
		# grinding for 0.5s. Throttled to avoid jump-spam when pressed flat.
		if dir != 0.0 and on_floor and jump_cd <= 0.0 and _ledge_hop_cd <= 0.0:
			if _wall_ahead(dir) or _ledge_ahead(dir):
				velocity.y = JUMP_VEL * MatchConfig.mod_gravity()
				velocity.x = dir * maxf(RUN_SPEED * MatchConfig.mod_speed(), absf(velocity.x) * 1.05)
				jump_cd = 0.4
				_ledge_hop_cd = 0.5

		# dodge-jump when an enemy bullet is closing in
		dodge_cd -= delta
		if dodge_cd <= 0.0:
			dodge_cd = 0.1  # scan bullets at 10 Hz, not every tick
			if not _refuel_wait and _bullet_incoming():
				if on_floor:
					velocity.y = JUMP_VEL * MatchConfig.mod_gravity()
					Sfx.jump()
				dodge_cd = 0.5

		# jump / jet toward the target when it's above us
		jet_on = false
		jump_cd -= delta
		# When seeking a ladder we suppress jet/jump — the goal is to walk over
		# to the ladder base, not jet-boot the wall next to it.
		# Pushing into a small lip/step (too low for the chest-height wall ray)
		# without moving → hop over it.
		if navigating and dir != 0.0 and on_floor and absf(get_real_velocity().x) < 15.0:
			_blocked_t += delta
			if _blocked_t > 0.2 and jump_cd <= 0.0:
				velocity.y = JUMP_VEL * MatchConfig.mod_gravity()
				velocity.x = dir * RUN_SPEED * MatchConfig.mod_speed()
				jump_cd = 0.4
				_blocked_t = 0.0
		else:
			_blocked_t = 0.0
		if navigating and _escape_t <= 0.0:
			# Path says "up": hop, then jet while the waypoint is above us.
			# Keep a little fuel in reserve unless the climb is the objective.
			if nav_up:
				# Jets barely out-pull gravity: a climb must START with a jump
				# off the ground. If we arrive falling with ground just below,
				# land first instead of burning the tank sinking (that sank bots
				# into Triumph's pits). Over a void, jet regardless.
				var falling_to_land: bool = not on_floor and velocity.y > 40.0 \
						and not _void_below() and _ground_within(90.0)
				if on_floor and jump_cd <= 0.0:
					velocity.y = JUMP_VEL * MatchConfig.mod_gravity()
					jump_cd = 0.3
					Sfx.jump()
				elif not on_floor and not falling_to_land and fuel > 0.0 and velocity.y > -330.0:
					velocity.y += JET_THRUST * MatchConfig.mod_jet() * MatchConfig.mod_gravity() * delta
					fuel = maxf(0.0, fuel - (40.0 / maxf(0.1, MatchConfig.mod_jet())) * delta)
					jet_on = true
			elif on_floor and jump_cd <= 0.0 and _hop_cd <= 0.0 and dir != 0.0 and fuel > 90.0 \
					and _path_i < _path.size() and absf(_path[_path_i].x - global_position.x) > 200.0:
				# Long flat stretch: bunny-hop for speed like players do.
				velocity.y = JUMP_VEL * MatchConfig.mod_gravity()
				velocity.x = dir * maxf(RUN_SPEED * MatchConfig.mod_speed(), absf(velocity.x) * 1.08)
				jump_cd = 0.35
				_hop_cd = HOP_COOLDOWN
				Sfx.jump()
		elif is_instance_valid(target) and seek_lad == null:
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
		# Escape jet: first part of the escape manoeuvre lifts the bot off
		# whatever lip/pocket it was grinding against.
		if _escape_t > 0.0 and _escape_t > _escape_len - ESCAPE_TIME * 0.55 and fuel > 5.0:
			if on_floor and jump_cd <= 0.0:
				velocity.y = JUMP_VEL * MatchConfig.mod_gravity()
				jump_cd = 0.4
			elif not on_floor:
				velocity.y += JET_THRUST * MatchConfig.mod_jet() * MatchConfig.mod_gravity() * delta
				fuel = maxf(0.0, fuel - (40.0 / maxf(0.1, MatchConfig.mod_jet())) * delta)
				jet_on = true
		# (Sfx.jet is the LOCAL player's single jet loop — bots toggling it made
		# your jet hum start/stop from across the map.)
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
		_update_wedge(delta)

	# lob a grenade at mid-range
	grenade_cd -= delta
	if is_instance_valid(target) and grenade_cd <= 0.0 and grenades > 0 and _target_visible and absf(dx) > 60.0:
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
	elif is_instance_valid(target) and fire_cd <= 0.0 and _retreat_t <= 0.0 and _burst_cool <= 0.0:
		var to_t: Vector2 = target.global_position - global_position
		var t_len: float = to_t.length()
		# LAW bots refuse point-blank rocket shots — 130px splash would kill themselves.
		# When they've swapped to the USSOCOM secondary (#79) the pistol is safe at any range.
		if loadout == "LAW" and not using_secondary and t_len < ROCKET_MIN_RANGE:
			pass
		elif _is_melee() and t_len > 70.0:
			pass  # knife/chainsaw only swing when in reach
		elif t_len < _skill_engage_range and _target_visible:
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
				# (Skipped while following a nav path / refuelling — the path
				# follower handles climbs, and this hop burned the landing frames
				# bots need to regenerate jet fuel.)
				if is_on_floor() and jump_cd <= 0.0 and _goal == Vector2.INF and not _refuel_wait:
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
	# v1.14 target scoring: distance, but enemies we can actually SEE count
	# as 3x closer, enemy flag carriers (running off with our flag) 4x, and
	# weakened enemies a bit closer — so bots stop fixating on someone behind
	# a wall while another enemy shoots them.
	var best: Node2D = null
	var best_d2: float = INF
	var my_flag_carrier := _enemy_carrying_our_flag()
	for s in get_tree().get_nodes_in_group("soldier"):
		if s == self or s.get("team") == team or s.get("dead"):
			continue
		var d2: float = (s.global_position - global_position).length_squared()
		if d2 < 900.0 * 900.0 and _has_line_of_sight(s):
			d2 /= 9.0
		if s == my_flag_carrier:
			d2 /= 16.0
		var hp: float = float(s.get("health")) if s.get("health") != null else 100.0
		d2 *= lerpf(0.7, 1.0, clampf(hp / 100.0, 0.0, 1.0))
		if d2 < best_d2:
			best_d2 = d2
			best = s
	# #114: switching targets resets the auto-weapon burst counter — a fresh
	# enemy should get a fresh burst instead of inheriting mid-mag cooldown.
	if best != target:
		_burst_shots = 0
	target = best


func _wall_ahead(dir: float) -> bool:
	# #114: cast a short forward ray at chest height to detect an immediate wall.
	# Only returns true when there's static terrain within ~24px in our travel
	# direction — that's the case where a hop is worth the fuel over a normal
	# run. Ignores dynamic bodies (soldiers, pickups) so we don't jump on them.
	if dir == 0.0:
		return false
	var space := get_world_2d().direct_space_state
	var from := global_position + Vector2(0, -6)
	var to := from + Vector2(dir * 24.0, 0)
	var q := PhysicsRayQueryParameters2D.create(from, to, 1 | 4)  # terrain soldiers collide with
	q.exclude = [self]
	q.collide_with_areas = false
	q.collide_with_bodies = true
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return false
	# Bots share the same collision layer as soldiers — filter out dynamic
	# bodies so we only react to terrain (StaticBody2D platforms + walls).
	var col: Object = hit.get("collider", null)
	return col is StaticBody2D


func _ledge_ahead(dir: float) -> bool:
	# #114: floor drops off within a step forward — reads as a ledge the bot
	# would otherwise walk off. Cast a downward probe just past the foot to
	# see if there's ground below at a reachable depth. Used to bias wanderers
	# away from cliffs so they don't repeatedly plunge into the map floor.
	if dir == 0.0 or not is_on_floor():
		return false
	var space := get_world_2d().direct_space_state
	# Sample one step-length ahead + ~40px below current feet — jump-recoverable.
	var from := global_position + Vector2(dir * 22.0, 0)
	var to := from + Vector2(0, 46.0)
	var q := PhysicsRayQueryParameters2D.create(from, to, 1 | 4)
	q.exclude = [self]
	q.collide_with_areas = false
	q.collide_with_bodies = true
	var hit := space.intersect_ray(q)
	return hit.is_empty()


func _scan_pickup(delta: float) -> void:
	# #114: prefer a nearby pickup over closing on an enemy when the pickup is
	# beneficial and close enough that the detour pays. Bots understand:
	# • bonus boxes: always desirable — grant timed buffs.
	# • weapon pickups: only weapons try_pickup_weapon accepts (AK-74 / LAW).
	# The scan is throttled to ~4 Hz so a 20-bot match doesn't linear-scan
	# every frame. If we're already heading to a pickup, keep it unless it's
	# invalidated (freed, consumed).
	_pickup_scan_cd -= delta
	if is_instance_valid(_pickup_target) and _pickup_target.get_parent() != null:
		# Give up on a pickup we can't reach within a few seconds.
		_pickup_t += delta
		if _pickup_t < 4.0:
			return
		_pickup_scan_cd = 3.0
	_pickup_target = null
	if _pickup_scan_cd > 0.0:
		return
	_pickup_scan_cd = 0.25
	# Only pursue pickups when we're not in the middle of a retreat / hurt.
	if _retreat_t > 0.0 or health < 30.0:
		return
	# Bots don't pick up weapons in Gun Game (loadout is locked to the rung).
	var can_swap: bool = Settings.game_mode != Settings.MODE_GG
	var best: Node2D = null
	var best_d2: float = 240.0 * 240.0  # within ~240px is a reasonable detour
	for wp in get_tree().get_nodes_in_group("weapon_pickup"):
		if not is_instance_valid(wp):
			continue
		if not can_swap:
			continue
		var wname: String = str(wp.get("weapon_name"))
		# Bots today accept AK-74 / LAW / their current loadout — anything else
		# would ghost-consume (see weapon_pickup._body_has_weapon fallback).
		if wname != "AK-74" and wname != "LAW":
			continue
		# Don't detour to swap the weapon we already carry.
		if wname == loadout:
			continue
		var d2: float = (wp.global_position - global_position).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best = wp
	# (Bonus crates are a player-only perk — main.gd::_on_bonus_touched ignores
	# bots — so chasing them just made bots circle a box they can never take.)
	_pickup_target = best
	_pickup_t = 0.0


func _has_line_of_sight(t: Node2D) -> bool:
	# Cast a ray from the bot's chest to the target's chest. If any StaticBody2D
	# terrain sits in the way we skip the shot — otherwise the bot happily plinks
	# through walls, which reads as an aim-bot to human players.
	if not is_instance_valid(t):
		return false
	var space := get_world_2d().direct_space_state
	var from := global_position + Vector2(0, -8)
	var to := t.global_position + Vector2(0, -8)
	var q := PhysicsRayQueryParameters2D.create(from, to, 1 | 2)  # terrain that stops bullets
	q.exclude = [self, t]
	q.collide_with_areas = false
	q.collide_with_bodies = true
	var hit := space.intersect_ray(q)
	return hit.is_empty()


func _find_ladder_overlap() -> Node2D:
	# Mirrors player.gd::_find_ladder_overlap — rect-vs-rect against each
	# ladder Area2D's stored bounds. Body half-width ~7 (bot shape 14×24, feet-anchored).
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
		var dxl: float = absf(pcx - lx)
		if dxl > half_w + 8.0:
			continue
		if pfeet + CLIMB_BODY_PAD_BOTTOM < top - 2.0 or phead > bot + 2.0:
			continue
		if dxl < best_dx:
			best_dx = dxl
			closest = lad
	return closest


func _find_seek_ladder(dx: float, dy: float) -> Node2D:
	# When the target is above and out of jet range, pick the nearest ladder
	# within LADDER_SEEK_RANGE horizontal that spans the target vertically —
	# so the bot walks to the ladder base instead of jet-booting the wall.
	if dy >= LADDER_SEEK_UP:
		return null
	var target_y: float = global_position.y + dy
	var pcx: float = global_position.x
	var best: Node2D = null
	var best_d: float = LADDER_SEEK_RANGE
	for lad in get_tree().get_nodes_in_group("ladder"):
		if not is_instance_valid(lad):
			continue
		var lx: float = float(lad.get_meta("center_x", lad.global_position.x))
		var top: float = float(lad.get_meta("top_y", lad.global_position.y - 60.0))
		var bot: float = float(lad.get_meta("bottom_y", lad.global_position.y + 60.0))
		# The ladder must overlap our current Y (or below) up to the target's Y.
		if top > global_position.y + 8.0:
			continue
		if bot < target_y - 32.0:
			continue
		# Only pull toward a ladder that lies between us and the target x,
		# or is at least on the same side. Cross-map ladders don't help.
		var to_lad: float = lx - pcx
		if signf(dx) != 0.0 and signf(to_lad) != 0.0 and signf(to_lad) != signf(dx):
			continue
		var d: float = absf(to_lad)
		if d < best_d:
			best_d = d
			best = lad
	return best


func _bullet_incoming() -> bool:
	var me := global_position
	for b in get_tree().get_nodes_in_group("bullet"):
		if not is_instance_valid(b):
			continue
		var to_b: Vector2 = (b as Node2D).global_position - me
		if to_b.length_squared() > 62500.0:  # distance cull before property reads
			continue
		if int(b.get("team")) == team:
			continue
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
		_bcast("net_bot_grenade", [g_pos, g_vel, g_ang, pid])
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
		_bcast("net_bot_shoot", [muzzle, aim, pid])
	else:
		net_bot_shoot(muzzle, aim, 0)
	# Fire cadence tracks the active weapon's rate (#80) — a Barrett bot no
	# longer fires at AK cadence, a Minigun no longer at 0.45s.
	fire_cd = float(stats["rate"])
	# #114: burst control for auto weapons — after BURST_CAP shots in a row,
	# insert BURST_PAUSE seconds so the bink can settle and bots don't hose
	# the entire mag as one continuous stream. Semi-auto weapons (not in the
	# table) get no burst cap because their fire_cd is already ≥ BURST_PAUSE.
	var cap: int = int(BURST_CAP.get(active_weapon, 0))
	if cap > 0:
		_burst_shots += 1
		if _burst_shots >= cap:
			_burst_cool = BURST_PAUSE
			_burst_shots = 0
	else:
		_burst_shots = 0


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
		# Spas-12 fires a pellet fan like the player's (#review: was 1 pellet).
		# Spread is seeded from the aim so host and clients draw the same fan.
		var pellets: int = int(stats.get("pellets", 1))
		var spread: float = float(stats.get("spread", 0.0))
		for pi in pellets:
			var dir := aim
			if pellets > 1:
				dir = aim.rotated(lerpf(-spread, spread, float(pi) / float(pellets - 1)))
			var b := bullet_scene.instantiate()
			b.global_position = muzzle
			b.direction = dir
			b.speed = float(stats["speed"])
			b.damage = float(stats["damage"]) * dmg_mul
			b.weapon_name = active_weapon
			b.team = team
			b.killer_name = display_name
			# Gun Game melee rungs (Knife/Chainsaw) + flames set a short "life".
			if stats.has("life"):
				b.life = float(stats["life"])
			if stats.has("visual"):
				b.visual = str(stats["visual"])
			get_parent().add_child(b)
			if Net.is_client():
				Net.bot_bullets_seen += 1


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
	# Bots understand AK-74 / LAW swaps, and the Rambo Bow in Rambomatch
	# (without it bots crowded the bow forever and could never score).
	if weapon_name == "LAW" or weapon_name == "AK-74" \
			or (weapon_name == "Rambo Bow" and Settings.game_mode == Settings.MODE_RM):
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
	# MP host: route the kill through net_kill_feed (call_local) so clients get
	# the feed line / streak banners too; SP emits locally.
	if Net.is_networked() and Net.is_host() and last_killer != "" and multiplayer.has_multiplayer_peer():
		var mm := get_parent()
		if mm != null and mm.has_method("net_kill_feed"):
			mm.rpc("net_kill_feed", last_killer, display_name, last_weapon, last_killer_team, team)
		else:
			_emit_kill()
	else:
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
	# Deferred from _die: the scene may be changing (round/map switch) by now.
	if not is_inside_tree() or get_parent() == null:
		return
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
	# Deferred from _die: the scene may be changing (round/map switch) by now.
	if not is_inside_tree() or get_parent() == null:
		return
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


# ── Brain (v1.14) ─────────────────────────────────────────────────────────

func _main() -> Node:
	return get_parent()


func _nav() -> RefCounted:
	var m := _main()
	if m == null:
		return null
	return m.get("nav")


func _flags() -> Array:
	var m := _main()
	if m == null or m.get("flags") == null:
		return []
	return m.get("flags")


func _flag_carrier(f: Node) -> Node:
	if f == null or not is_instance_valid(f) or not f.has_meta("carrier"):
		return null
	var c: Variant = f.get_meta("carrier")
	if c == null or not is_instance_valid(c) or bool((c as Node).get("dead")):
		return null
	return c


func _carrying_flag() -> bool:
	for f in _flags():
		if _flag_carrier(f) == self:
			return true
	return false


func _enemy_carrying_our_flag() -> Node:
	for f in _flags():
		if not is_instance_valid(f):
			continue
		var c := _flag_carrier(f)
		if c == null or int(c.get("team")) == team:
			continue
		# CTF: our own flag; INF/HTF: the single neutral flag.
		var ft: int = int(f.get_meta("team")) if f.has_meta("team") else 0
		if ft == team or ft == 0:
			return c
	return null


func _pick_role() -> void:
	if _role != "":
		return
	# ~60% attackers / 40% defenders, stable per bot.
	var h: int = absi(hash(display_name))
	_role = "defend" if h % 5 < 2 else "attack"


func _patrol(center: Vector2, radius: float) -> Vector2:
	_patrol_t -= THINK_INTERVAL
	var nav := _nav()
	if _patrol_pos == Vector2.INF or _patrol_t <= 0.0 or _patrol_pos.distance_to(center) > radius * 1.5 \
			or global_position.distance_to(_patrol_pos) < 30.0:
		_patrol_t = randf_range(3.0, 6.0)
		if nav != null and not nav.is_empty():
			_patrol_pos = nav.random_point_near(center, radius)
		else:
			_patrol_pos = center + Vector2(randf_range(-radius, radius), 0)
	return _patrol_pos


func _set_goal(pos: Vector2, label: String) -> void:
	_goal = pos
	_goal_label = label


func _think() -> void:
	_goal = Vector2.INF
	_goal_label = ""
	var mode: int = Settings.game_mode
	var flags := _flags()
	# Grabbing a close, useful pickup beats everything except flag duty.
	if is_instance_valid(_pickup_target) and not _carrying_flag():
		_set_goal(_pickup_target.global_position, "pickup")
		return
	if mode == Settings.MODE_CTF and flags.size() == 2:
		_think_ctf(flags)
	elif mode == Settings.MODE_INF and flags.size() == 1:
		_think_inf(flags[0])
	elif mode == Settings.MODE_HTF and flags.size() == 1:
		_think_htf(flags[0])
	elif mode == Settings.MODE_DOM:
		_think_dom()
	elif mode == Settings.MODE_PM:
		_think_pm()
	elif mode == Settings.MODE_RM:
		_think_rambo()
	elif mode == Settings.MODE_BR:
		_think_br()
	if _goal == Vector2.INF:
		_think_hunt()


func _think_hunt() -> void:
	# Go where the enemy is: current target (if we can't already see it up
	# close), else where we last saw it, else roam the map.
	if is_instance_valid(target):
		var d: float = global_position.distance_to(target.global_position)
		if not _target_visible or d > _skill_engage_range * 0.75 or (_is_melee() and d > 40.0):
			_set_goal(target.global_position, "hunt")
		return
	if _last_seen_pos != Vector2.INF and global_position.distance_to(_last_seen_pos) > 60.0:
		_set_goal(_last_seen_pos, "hunt")
		return
	_last_seen_pos = Vector2.INF
	var nav := _nav()
	if nav != null and not nav.is_empty():
		if _patrol_pos == Vector2.INF or global_position.distance_to(_patrol_pos) < 40.0:
			_patrol_pos = nav.random_point(global_position)
		_set_goal(_patrol_pos, "roam")


func _think_ctf(flags: Array) -> void:
	_pick_role()
	var own: Node2D = null
	var enemy: Node2D = null
	for f in flags:
		if not is_instance_valid(f):
			continue
		if int(f.get_meta("team")) == team:
			own = f
		else:
			enemy = f
	if own == null or enemy == null:
		return
	var own_home: Vector2 = own.get_meta("home")
	var own_carrier := _flag_carrier(own)
	var enemy_carrier := _flag_carrier(enemy)
	# 1) We have their flag → run it home.
	if enemy_carrier == self:
		_set_goal(own_home, "capture")
		return
	# 2) Our flag was taken → defenders (and anyone close) chase the carrier.
	#    If a teammate is already holding THEIR flag, nobody can score until
	#    ours comes back — then everyone hunts our carrier.
	if own_carrier != null and int(own_carrier.get("team")) != team:
		var standoff: bool = enemy_carrier != null and int(enemy_carrier.get("team")) == team
		if standoff or _role == "defend" or global_position.distance_to(own_carrier.global_position) < 700.0:
			_set_goal(own_carrier.global_position, "chase")
			return
	# 3) Our flag is lying in the field → nearest bots go touch it to return it.
	if own_carrier == null and own.position.distance_to(own_home) > 12.0:
		if _role == "defend" or global_position.distance_to(own.position) < 600.0:
			_set_goal(own.position, "return")
			return
	if _role == "attack":
		if enemy_carrier != null and int(enemy_carrier.get("team")) == team:
			# A teammate has it — escort them home.
			_set_goal(enemy_carrier.global_position, "escort")
		else:
			_set_goal(enemy.position, "flag")
	else:
		# Defend: patrol around our base, but fight anyone who shows up.
		if is_instance_valid(target) and _target_visible \
				and target.global_position.distance_to(own_home) < 700.0:
			return
		_set_goal(_patrol(own_home, 260.0), "defend")


func _think_inf(f: Node2D) -> void:
	var carrier := _flag_carrier(f)
	var home: Vector2 = f.get_meta("home")
	var capture: Vector2 = f.get_meta("capture_point") if f.has_meta("capture_point") else home
	if team == 2:  # RED = attackers
		if carrier == self:
			_set_goal(capture, "capture")
		elif carrier != null and int(carrier.get("team")) == team:
			_set_goal(carrier.global_position, "escort")
		else:
			_set_goal(f.position, "flag")
	else:          # BLUE = defenders
		if carrier != null and int(carrier.get("team")) != team:
			_set_goal(carrier.global_position, "chase")
		elif f.position.distance_to(home) > 12.0:
			_set_goal(f.position, "return")
		else:
			_set_goal(_patrol(capture, 300.0), "defend")


func _think_htf(f: Node2D) -> void:
	var carrier := _flag_carrier(f)
	if carrier == self:
		# Keep moving, away from the nearest enemy.
		var nav := _nav()
		var threat: Vector2 = target.global_position if is_instance_valid(target) else global_position
		if _patrol_pos == Vector2.INF or global_position.distance_to(_patrol_pos) < 60.0 \
				or _patrol_pos.distance_to(threat) < 300.0:
			var best := global_position
			var best_d := -1.0
			for _i in 6:
				var c: Vector2 = nav.random_point_near(global_position, 700.0) if nav != null and not nav.is_empty() \
						else global_position + Vector2(randf_range(-500, 500), 0)
				var dd := c.distance_to(threat)
				if dd > best_d:
					best_d = dd
					best = c
			_patrol_pos = best
		_set_goal(_patrol_pos, "capture")
	elif carrier != null and int(carrier.get("team")) == team:
		_set_goal(carrier.global_position, "escort")
	elif carrier != null:
		_set_goal(carrier.global_position, "chase")
	else:
		_set_goal(f.position, "flag")


func _think_dom() -> void:
	var m := _main()
	if m == null or not m.has_method("dom_points"):
		return
	var pts: Array = m.dom_points()
	if pts.is_empty():
		return
	# Stick with a chosen point until it's ours, then pick the nearest point
	# that isn't (or defend a random owned one if we hold them all).
	if is_instance_valid(_dom_choice) and int(_dom_choice.get_meta("owner_team")) != team:
		_set_goal(_dom_choice.global_position + Vector2(0, 30), "capture")
		return
	var best: Node2D = null
	var best_d := INF
	for a in pts:
		if not is_instance_valid(a) or int(a.get_meta("owner_team")) == team:
			continue
		var d: float = global_position.distance_to(a.global_position) * randf_range(0.8, 1.2)
		if d < best_d:
			best_d = d
			best = a
	if best == null:
		best = pts[randi() % pts.size()]
	_dom_choice = best
	_set_goal(best.global_position + Vector2(0, 30), "capture")


func _think_pm() -> void:
	var best: Node2D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("point_pickup"):
		if not is_instance_valid(p) or not (p as CanvasItem).visible:
			continue
		var d: float = global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	if best != null and (not is_instance_valid(target) or not _target_visible or best_d < 500.0):
		_set_goal(best.global_position, "capture")


func _think_rambo() -> void:
	for wp in get_tree().get_nodes_in_group("weapon_pickup"):
		if is_instance_valid(wp) and wp.has_meta("rambo_spawn"):
			_set_goal(wp.global_position, "flag")
			return
	if loadout == "Rambo Bow":
		return  # we're Rambo — hunt normally
	# Hunt whoever carries the bow (players included — main tracks the id).
	var cid: int = int(_main().get("_rambo_carrier_id")) if _main() != null else 0
	for s in get_tree().get_nodes_in_group("soldier"):
		if s != self and is_instance_valid(s) and not bool(s.get("dead")) and s.get_instance_id() == cid:
			_set_goal(s.global_position, "chase")
			return


func _think_br() -> void:
	var m := _main()
	if m == null or not m.has_method("br_zone"):
		return
	var z: Dictionary = m.br_zone()
	var c: Vector2 = z.get("center", global_position)
	var r: float = float(z.get("radius", 99999.0))
	if global_position.distance_to(c) > r * 0.8:
		_set_goal(c, "zone")


func _nav_step(goal: Vector2, delta: float) -> Vector3:
	# Returns (dir_x, want_up, valid). Replans when the goal moves, every
	# ~1.2 s, or after an escape.
	var nav := _nav()
	if nav == null or nav.is_empty():
		return Vector3.ZERO
	_repath_t -= delta
	# Only replan with feet on something: a mid-jet replan snaps to the node
	# BELOW us (nearest-node is biased to the surface we'd land on) and the
	# bot abandons the climb halfway up.
	var grounded: bool = is_on_floor() or _wedge_t > 0.2
	if _path.is_empty() or (grounded and (_repath_t <= 0.0 or _path_goal.distance_to(goal) > 96.0)):
		_path = nav.path(global_position, goal)
		if _path.is_empty():
			# Goal unreachable from the node we're nearest to (e.g. we fell
			# into a one-way pocket): at least get back onto the graph by
			# heading for the closest node, then replan from there.
			var n: int = nav.nearest(global_position, 900.0)
			if n >= 0:
				_path = PackedVector2Array([nav.point(n)])
		_path_i = 0
		_repath_t = randf_range(1.0, 1.4)
		_path_goal = goal
	if _path.is_empty():
		return Vector3.ZERO
	# Advance past waypoints we've reached. A later waypoint that's already
	# level with us and close counts too (we overshot on a hop).
	while _path_i < _path.size() - 1:
		var w: Vector2 = _path[_path_i]
		var ddy: float = w.y - global_position.y
		if absf(w.x - global_position.x) < 20.0 and ddy > -30.0 and ddy < 44.0:
			_path_i += 1
		else:
			break
	var wp: Vector2 = _path[_path_i]
	var dx: float = wp.x - global_position.x
	var dy: float = wp.y - global_position.y
	var d := 0.0 if absf(dx) < 6.0 else signf(dx)
	var up := 1.0 if dy < -18.0 else 0.0
	# Near-vertical climb: go straight up; a sideways drift off a lip is how
	# bots slid into pits.
	if up > 0.5 and absf(dx) < 24.0 and absf(dy) > 60.0:
		d = 0.0
	# Gap crossing (nothing under the midpoint before the kill line, e.g.
	# between Airpirates' ships): hold altitude with jets instead of arcing
	# down into the void.
	_gap_ahead = _is_gap(global_position, wp)
	if _gap_ahead and global_position.y > wp.y - 120.0:
		up = 1.0  # jump at the lip and jet the whole way (jets barely beat gravity)
	return Vector3(d, up, 1.0)


func _is_gap(a: Vector2, b: Vector2) -> bool:
	if absf(b.x - a.x) < 40.0:
		return false
	var m := _main()
	if m == null or not m.has_method("_geom_ground_y"):
		return false
	var kill_y: float = float(m.get("KILL_Y"))
	if kill_y == INF:
		return false
	# A gap = no ground under the middle of the hop, or ground so far below
	# both ends (a deep pit) that dropping in means dying or a long climb.
	var mid := (a + b) * 0.5
	var gy: float = m._geom_ground_y(mid.x, mid.y)
	return gy == INF or gy > kill_y or gy > maxf(a.y, b.y) + 160.0


func _carrying_flag_under_fire() -> bool:
	# A flag carrier with an enemy on its tail doesn't stop to refuel.
	return _carrying_flag() and is_instance_valid(target) and _target_visible \
			and global_position.distance_to(target.global_position) < 400.0


func _pit_ahead(dir: float) -> bool:
	# Ground under the next ~30 px of travel ends below the kill line?
	var m := _main()
	if m == null or not m.has_method("_geom_ground_y"):
		return false
	var kill_y: float = float(m.get("KILL_Y"))
	if kill_y == INF:
		return false
	for off in [14.0, 30.0]:
		var x: float = global_position.x + dir * off
		var gy: float = m._geom_ground_y(x, global_position.y - 6.0)
		if gy == INF or gy > kill_y:
			return true
	return false


func _void_below() -> bool:
	var m := _main()
	if m == null or not m.has_method("_geom_ground_y"):
		return false
	var kill_y: float = float(m.get("KILL_Y"))
	if kill_y == INF:
		return false
	var gy: float = m._geom_ground_y(global_position.x, global_position.y)
	return gy == INF or gy > kill_y


func _ground_within(dist: float) -> bool:
	var m := _main()
	if m == null or not m.has_method("_geom_ground_y"):
		return true
	var gy: float = m._geom_ground_y(global_position.x, global_position.y)
	return gy != INF and gy - global_position.y <= dist


func _is_melee() -> bool:
	var w: String = "USSOCOM" if using_secondary else loadout
	return w == "Knife" or w == "Chainsaw"


# Host → self + ACKED peers only. A plain rpc() also reached peers that were
# still loading the match, spamming "Node not found: Main/Bot_N" on joiners.
func _bcast(method: StringName, args: Array) -> void:
	callv(method, args)
	var m := get_parent()
	if m == null or not m.has_method("ready_peer_ids"):
		return
	for pid in m.ready_peer_ids():
		callv("rpc_id", [int(pid), method] + args)
