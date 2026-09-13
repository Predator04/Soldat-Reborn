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
# `kind` = "hitscan-ish" bullet (default) OR "rocket" (LAW: slow, explodes, splash).
var weapons := [
	{"name": "Deagles", "damage": 34.0, "rate": 0.30, "mag": 14, "reload": 1.5, "auto": false, "spread": 0.02, "speed": 1200.0, "pellets": 1, "color": Color(0.92, 0.78, 0.35), "kind": "bullet"},
	{"name": "AK-74",   "damage": 22.0, "rate": 0.11, "mag": 30, "reload": 2.0, "auto": true,  "spread": 0.055, "speed": 1050.0, "pellets": 1, "color": Color(0.72, 0.72, 0.78), "kind": "bullet"},
	{"name": "MP5",     "damage": 13.0, "rate": 0.075, "mag": 32, "reload": 1.8, "auto": true,  "spread": 0.085, "speed": 950.0, "pellets": 1, "color": Color(0.5, 0.62, 0.8), "kind": "bullet"},
	{"name": "Spas-12", "damage": 9.0,  "rate": 0.6,  "mag": 8,  "reload": 2.5, "auto": false, "spread": 0.26, "speed": 850.0, "pellets": 8, "color": Color(0.88, 0.58, 0.3), "kind": "bullet"},
	{"name": "LAW",     "damage": 90.0, "rate": 1.1,  "mag": 1,  "reload": 3.0, "auto": false, "spread": 0.0,  "speed": 720.0, "pellets": 1, "color": Color(0.85, 0.55, 0.35), "kind": "rocket"},
]
var ammo: Array[int] = []
var weapon_index := 1
var fire_cd := 0.0
var reloading := false
var reload_t := 0.0
var grenades := 3
var grenade_cd := 0.0
var muzzle_t := 0.0

# ── Feel ───────────────────────────────────────────────
var coyote_t := 0.0
var jump_buffer_t := 0.0
var shake := 0.0
var cam: Camera2D
var jet_particles: CPUParticles2D

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


func _ready() -> void:
	add_to_group("soldier")
	# Release the per-instance skeleton state dict when this node is freed so long
	# sessions don't leak dict entries in Gostek._states.
	tree_exited.connect(func() -> void: Gostek.forget(self))
	for w in weapons:
		ammo.append(int(w["mag"]))
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20, 42)
	shape.shape = rect
	add_child(shape)
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
		jet_particles.emitting = jet_on and not dead
		jet_particles.position = Vector2(-facing * 3.3, 1.7)
		queue_redraw()
		return

	var left := Input.is_physical_key_pressed(KEY_A)
	var right := Input.is_physical_key_pressed(KEY_D)
	var jump_pressed := Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_W)

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
	var accel := GROUND_ACCEL if on_floor else AIR_ACCEL
	var cap := RUN_SPEED if on_floor else BUNNY_SPEED
	# Preserve bunny-hop momentum: if a buffered jump will fire this tick,
	# skip the RUN_SPEED clamp so airborne speed isn't clipped on the landing frame.
	if on_floor and jump_buffer_t > 0.0 and coyote_t > 0.0:
		cap = BUNNY_SPEED
	if dir != 0.0:
		velocity.x += dir * accel * delta
	else:
		var fr := GROUND_FRICTION if on_floor else AIR_FRICTION
		velocity.x = move_toward(velocity.x, 0.0, fr * delta)
	velocity.x = clampf(velocity.x, -cap, cap)

	# jet boots
	jet_on = false
	if jump_pressed and not on_floor and fuel > 0.0:
		velocity.y += JET_THRUST * delta
		fuel = maxf(0.0, fuel - JET_DRAIN * delta)
		jet_on = true
	elif on_floor:
		fuel = minf(100.0, fuel + JET_REGEN * delta)

	# jump / bunny hop (coyote + buffer aware)
	if jump_buffer_t > 0.0 and coyote_t > 0.0:
		velocity.y = JUMP_VEL
		velocity.x = clampf(velocity.x * 1.06, -BUNNY_SPEED, BUNNY_SPEED)
		coyote_t = 0.0
		jump_buffer_t = 0.0
		Sfx.jump()

	if not on_floor:
		velocity.y += GRAVITY * delta
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

	# weapon switching
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

	# reload
	if Input.is_physical_key_pressed(KEY_R) and not reloading:
		_start_reload()

	# grenade
	grenade_cd -= delta
	if Input.is_physical_key_pressed(KEY_G) and grenade_cd <= 0.0 and grenades > 0:
		_throw_grenade()
		grenade_cd = 0.6

	# shooting
	fire_cd -= delta
	if reloading:
		reload_t -= delta
		if reload_t <= 0.0:
			reloading = false
			ammo[weapon_index] = int(weapons[weapon_index]["mag"])
	else:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and fire_cd <= 0.0:
			if ammo[weapon_index] > 0:
				_shoot()
			else:
				Sfx.empty()
				fire_cd = 0.25

	muzzle_t = maxf(0.0, muzzle_t - delta * 10.0)

	# jet particles + sfx transitions
	if jet_on and not was_jet:
		Sfx.jet(true)
	elif not jet_on and was_jet:
		Sfx.jet(false)
	was_jet = jet_on
	jet_particles.emitting = jet_on
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
					rpc_id(pid, "net_state", position, velocity, aim_dir, facing, jet_on, health, fuel, weapon_index, ammo[weapon_index], reloading, grenades)
		else:
			# Broadcast so the host relays to other clients (Godot's server_relay).
			# Using rpc_id(1, ...) would freeze non-host peers' views of this body.
			rpc("net_state", position, velocity, aim_dir, facing, jet_on, health, fuel, weapon_index, ammo[weapon_index], reloading, grenades)


func _switch_weapon(idx: int) -> void:
	if idx == weapon_index:
		return
	# Allow switching mid-reload to cancel it — otherwise the player is hard-locked
	# for LAW's 3s or Spas's 2.5s with no way to defend.
	if reloading:
		reloading = false
		reload_t = 0.0
	weapon_index = idx
	fire_cd = 0.15


func _start_reload() -> void:
	var w = weapons[weapon_index]
	if ammo[weapon_index] >= int(w["mag"]):
		return
	reloading = true
	reload_t = float(w["reload"])
	Sfx.reload(str(w["name"]))


func _shoot() -> void:
	var w = weapons[weapon_index]
	ammo[weapon_index] -= 1
	fire_cd = float(w["rate"])
	var recoil := 240.0 if str(w.get("kind", "bullet")) == "rocket" else 35.0
	velocity -= aim_dir * recoil
	var dirs := PackedVector2Array()
	for _i in int(w["pellets"]):
		dirs.append(aim_dir.rotated(randf_range(-float(w["spread"]), float(w["spread"]))))
	if Net.is_networked():
		rpc("net_shoot", global_position, dirs, weapon_index)
	else:
		net_shoot(global_position, dirs, weapon_index)
	if ammo[weapon_index] <= 0:
		_start_reload()


func _throw_grenade() -> void:
	grenades -= 1
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
		rpc("net_grenade", g_pos, g_vel, g_ang)
	else:
		net_grenade(g_pos, g_vel, g_ang)


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
	health -= amount
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
	_spawn_gibs.call_deferred()
	_spawn_ragdoll.call_deferred()
	died.emit()
	if Net.is_networked() and Net.is_host():
		var peer_id := get_multiplayer_authority()
		var m := get_parent()
		var mode_at_schedule: int = Net.mode
		get_tree().create_timer(2.0).timeout.connect(func() -> void:
			# Bail if we've since torn down / rehosted / joined — don't respawn into a stale scene.
			if Net.mode != mode_at_schedule:
				return
			if get_tree().current_scene != m:
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
func net_state(pos: Vector2, vel: Vector2, aim: Vector2, face: float, jetting: bool, hp: float, fuel_val: float, wi: int, mag: int, is_reloading: bool, grens: int) -> void:
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
	reloading = is_reloading
	grenades = maxi(0, grens)


@rpc("authority", "call_local", "reliable")
func net_shoot(shot_pos: Vector2, dirs: PackedVector2Array, weapon_i: int) -> void:
	if weapon_i < 0 or weapon_i >= weapons.size():
		return
	var w = weapons[weapon_i]
	muzzle_t = 0.10 if str(w.get("kind", "bullet")) == "rocket" else 0.08
	_shake(6.0 if str(w.get("kind", "bullet")) == "rocket" else 3.5)
	Sfx.shoot(str(w["name"]))
	var kind := str(w.get("kind", "bullet"))
	for i in dirs.size():
		var bdir: Vector2 = dirs[i]
		if kind == "rocket":
			var r := rocket_scene.instantiate()
			r.global_position = shot_pos + bdir * 26.0
			r.direction = bdir
			r.speed = float(w["speed"])
			r.damage = float(w["damage"])
			r.team = team
			r.killer_name = display_name
			r.weapon_name = str(w["name"])
			get_parent().add_child(r)
		else:
			var b := bullet_scene.instantiate()
			b.global_position = shot_pos + bdir * 26.0
			b.direction = bdir
			b.speed = float(w["speed"])
			b.damage = float(w["damage"])
			b.team = team
			b.killer_name = display_name
			b.weapon_name = str(w["name"])
			get_parent().add_child(b)


@rpc("authority", "call_local", "reliable")
func net_grenade(g_pos: Vector2, g_vel: Vector2, g_ang: float) -> void:
	var g := grenade_scene.instantiate()
	g.global_position = g_pos
	g.team = team
	g.killer_name = display_name
	g.linear_velocity = g_vel
	g.angular_velocity = g_ang
	get_parent().add_child(g)


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
	var w = weapons[weapon_index]
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
	)
