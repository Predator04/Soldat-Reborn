extends CharacterBody2D
## Soldier — Soldat-style movement + weapon system (2026 feel).

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
var weapons := [
	{"name": "Deagles", "damage": 34.0, "rate": 0.30, "mag": 14, "reload": 1.5, "auto": false, "spread": 0.02, "speed": 1200.0, "pellets": 1, "color": Color(0.92, 0.78, 0.35)},
	{"name": "AK-74",   "damage": 22.0, "rate": 0.11, "mag": 30, "reload": 2.0, "auto": true,  "spread": 0.055, "speed": 1050.0, "pellets": 1, "color": Color(0.72, 0.72, 0.78)},
	{"name": "MP5",     "damage": 13.0, "rate": 0.075, "mag": 32, "reload": 1.8, "auto": true,  "spread": 0.085, "speed": 950.0, "pellets": 1, "color": Color(0.5, 0.62, 0.8)},
	{"name": "Spas-12", "damage": 9.0,  "rate": 0.6,  "mag": 8,  "reload": 2.5, "auto": false, "spread": 0.26, "speed": 850.0, "pellets": 8, "color": Color(0.88, 0.58, 0.3)},
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


func _ready() -> void:
	add_to_group("soldier")
	for w in weapons:
		ammo.append(int(w["mag"]))
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(22, 40)
	shape.shape = rect
	add_child(shape)
	cam = Camera2D.new()
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	cam.zoom = Vector2(1.35, 1.35)
	add_child(cam)
	jet_particles = CPUParticles2D.new()
	jet_particles.amount = 34
	jet_particles.lifetime = 0.4
	jet_particles.one_shot = false
	jet_particles.explosiveness = 0.0
	jet_particles.emitting = false
	jet_particles.direction = Vector2(0, 1)
	jet_particles.spread = 16.0
	jet_particles.gravity = Vector2(0, 340)
	jet_particles.initial_velocity_min = 60.0
	jet_particles.initial_velocity_max = 170.0
	jet_particles.scale_amount_min = 2.0
	jet_particles.scale_amount_max = 4.5
	jet_particles.color = Color(0.35, 0.75, 1.0)
	add_child(jet_particles)


func _physics_process(delta: float) -> void:
	if dead:
		velocity = Vector2.ZERO
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
		if aim_dir.x != 0.0:
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

	# jet particles follow the back
	if jet_on and not was_jet:
		Sfx.jet(true)
	elif not jet_on and was_jet:
		Sfx.jet(false)
	was_jet = jet_on
	jet_particles.emitting = jet_on
	jet_particles.position = Vector2(facing * -14.0, 4.0)

	# camera shake decay
	if shake > 0.0:
		cam.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake
		shake = maxf(0.0, shake - delta * 26.0)
	else:
		cam.offset = Vector2.ZERO

	queue_redraw()


func _switch_weapon(idx: int) -> void:
	if idx == weapon_index or reloading:
		return
	weapon_index = idx
	fire_cd = 0.15


func _start_reload() -> void:
	var w = weapons[weapon_index]
	if ammo[weapon_index] >= int(w["mag"]):
		return
	reloading = true
	reload_t = float(w["reload"])
	Sfx.reload()


func _shoot() -> void:
	var w = weapons[weapon_index]
	ammo[weapon_index] -= 1
	fire_cd = float(w["rate"])
	muzzle_t = 0.08
	_shake(3.5)
	Sfx.shoot(str(w["name"]))
	for _i in int(w["pellets"]):
		var bdir := aim_dir.rotated(randf_range(-float(w["spread"]), float(w["spread"])))
		var b := bullet_scene.instantiate()
		b.global_position = global_position + bdir * 26.0
		b.direction = bdir
		b.speed = float(w["speed"])
		b.damage = float(w["damage"])
		b.team = team
		b.killer_name = display_name
		b.weapon_name = str(w["name"])
		get_parent().add_child(b)
	velocity -= aim_dir * 35.0
	if ammo[weapon_index] <= 0:
		_start_reload()


func _throw_grenade() -> void:
	grenades -= 1
	var g := grenade_scene.instantiate()
	g.global_position = global_position + aim_dir * 22.0
	g.team = team
	g.killer_name = display_name
	var toss := (aim_dir + Vector2(0, -0.55)).normalized()
	g.linear_velocity = toss * 480.0
	g.angular_velocity = randf_range(-8.0, 8.0)
	get_parent().add_child(g)


func _shake(amount: float) -> void:
	if not Settings.screen_shake:
		return
	shake = maxf(shake, amount)


func take_damage(amount: float, killer := "", weapon := "", killer_team := -1) -> void:
	if dead:
		return
	health -= amount
	_shake(7.0)
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
	# defer FX spawn out of the physics flush (bullet body_entered → take_damage path)
	_spawn_gibs.call_deferred()
	_spawn_ragdoll.call_deferred()
	died.emit()
	queue_free()


func _emit_kill() -> void:
	if last_killer == "":
		return
	var parent := get_parent()
	if parent != null and parent.has_signal("kill"):
		parent.emit_signal("kill", last_killer, display_name, last_weapon, last_killer_team)


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
	# physics gib chunks: rigid bodies that fly out and settle on terrain
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
	var body_col := color if not dead else color.darkened(0.4)
	# jet flame triangle
	if jet_on and not dead:
		var fl := 24.0 + sin(Time.get_ticks_msec() * 0.05) * 7.0
		var back := facing * -1.0
		draw_polygon(
			PackedVector2Array([
				Vector2(back * 14.0 - 4.0, 2.0),
				Vector2(back * 14.0 + 4.0, 2.0),
				Vector2(back * (14.0 + fl), 2.0 + sin(Time.get_ticks_msec() * 0.07) * 5.0)
			]),
			PackedColorArray([
				Color(0.3, 0.7, 1.0, 0.9),
				Color(0.3, 0.7, 1.0, 0.9),
				Color(1.0, 1.0, 1.0, 0.0)
			])
		)
	# legs / torso / head / jetpack
	draw_rect(Rect2(-9, 0, 7, 10), body_col.darkened(0.3))
	draw_rect(Rect2(2, 0, 7, 10), body_col.darkened(0.3))
	draw_rect(Rect2(-11, -30, 22, 30), body_col)
	draw_circle(Vector2(facing * 2.0, -34), 6.0, body_col.lightened(0.15))
	draw_rect(Rect2(-facing * 16.0 - 3.0, -26, 5, 18), body_col.darkened(0.15))
	# gun barrel toward aim
	var w = weapons[weapon_index]
	draw_line(Vector2(facing * 4.0, -22.0), Vector2(facing * 4.0, -22.0) + aim_dir * 20.0, w["color"], 3.0)
	# muzzle flash
	if muzzle_t > 0.0:
		draw_circle(aim_dir * 30.0, 4.0 + muzzle_t * 30.0, Color(1.0, 0.95, 0.5, clampf(muzzle_t * 9.0, 0.0, 1.0)))
	# health / fuel bars
	draw_rect(Rect2(-16, -48, 32, 4), Color(0.0, 0.0, 0.0, 0.55))
	draw_rect(Rect2(-16, -48, 32.0 * clampf(health / 100.0, 0.0, 1.0), 4), Color(0.9, 0.2, 0.2))
	draw_rect(Rect2(-16, -43, 32, 3), Color(0.0, 0.0, 0.0, 0.55))
	draw_rect(Rect2(-16, -43, 32.0 * clampf(fuel / 100.0, 0.0, 1.0), 3), Color(0.3, 0.7, 1.0))
