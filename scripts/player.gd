extends CharacterBody2D
## Soldier — Soldat-style movement: run, bunny hop, jet boots, shoot.

signal died

@export var color := Color(0.25, 0.75, 0.45)
var team := 0

var health := 100.0
var fuel := 100.0
var facing := 1.0
var jet_on := false
var dead := false
var fire_cd := 0.0
var aim_dir := Vector2.RIGHT

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
const BULLET_SPEED := 950.0
const FIRE_RATE := 0.11

var bullet_scene := preload("res://scenes/bullet.tscn")


func _ready() -> void:
	add_to_group("soldier")
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(22, 40)
	shape.shape = rect
	add_child(shape)


func _physics_process(delta: float) -> void:
	if dead:
		velocity = Vector2.ZERO
		return

	var left := Input.is_physical_key_pressed(KEY_A)
	var right := Input.is_physical_key_pressed(KEY_D)
	var jump := Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_W)

	var dir := 0.0
	if left:
		dir -= 1.0
	if right:
		dir += 1.0

	var on_floor := is_on_floor()

	# Horizontal acceleration (weaker in air so bunny-hopping carries momentum)
	var accel := GROUND_ACCEL if on_floor else AIR_ACCEL
	var cap := RUN_SPEED if on_floor else BUNNY_SPEED
	if dir != 0.0:
		velocity.x += dir * accel * delta
	else:
		var fr := GROUND_FRICTION if on_floor else AIR_FRICTION
		velocity.x = move_toward(velocity.x, 0.0, fr * delta)
	velocity.x = clampf(velocity.x, -cap, cap)

	# Jet boots — hold jump in the air to thrust; fuel regens on ground
	jet_on = false
	if jump and not on_floor and fuel > 0.0:
		velocity.y += JET_THRUST * delta
		fuel = maxf(0.0, fuel - JET_DRAIN * delta)
		jet_on = true
	elif on_floor:
		fuel = minf(100.0, fuel + JET_REGEN * delta)

	# Jump / bunny hop — a small speed boost on each ground jump
	if jump and on_floor:
		velocity.y = JUMP_VEL
		velocity.x = clampf(velocity.x * 1.06, -BUNNY_SPEED, BUNNY_SPEED)

	# Gravity
	if not on_floor:
		velocity.y += GRAVITY * delta
		velocity.y = minf(velocity.y, MAX_FALL)

	# Aim from mouse, face the aim direction
	var mouse := get_global_mouse_position()
	var to_mouse := mouse - global_position
	if to_mouse.length() > 1.0:
		aim_dir = to_mouse.normalized()
		if aim_dir.x != 0.0:
			facing = signf(aim_dir.x)

	move_and_slide()

	# Shooting
	fire_cd -= delta
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and fire_cd <= 0.0:
		_shoot()


func _shoot() -> void:
	var b := bullet_scene.instantiate()
	b.global_position = global_position + aim_dir * 26.0
	b.direction = aim_dir
	b.speed = BULLET_SPEED
	b.team = team
	get_parent().add_child(b)
	fire_cd = FIRE_RATE
	velocity -= aim_dir * 40.0  # slight recoil


func take_damage(amount: float) -> void:
	if dead:
		return
	health -= amount
	if health <= 0.0:
		_die()


func _die() -> void:
	if dead:
		return
	dead = true
	_spawn_gibs()
	died.emit()
	queue_free()


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


func _draw() -> void:
	var body_col := color if not dead else color.darkened(0.4)
	# legs
	draw_rect(Rect2(-9, 0, 7, 10), body_col.darkened(0.3))
	draw_rect(Rect2(2, 0, 7, 10), body_col.darkened(0.3))
	# torso
	draw_rect(Rect2(-11, -30, 22, 30), body_col)
	# head
	draw_circle(Vector2(facing * 2.0, -34), 6.0, body_col.lightened(0.15))
	# jetpack on the back
	draw_rect(Rect2(-facing * 16.0 - 3.0, -26, 5, 18), body_col.darkened(0.15))
	# jet flame
	if jet_on and not dead:
		var fl := 26.0 + sin(Time.get_ticks_msec() * 0.05) * 7.0
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
	# health bar
	draw_rect(Rect2(-16, -48, 32, 4), Color(0.0, 0.0, 0.0, 0.55))
	draw_rect(Rect2(-16, -48, 32.0 * clampf(health / 100.0, 0.0, 1.0), 4), Color(0.9, 0.2, 0.2))
	# fuel bar
	draw_rect(Rect2(-16, -43, 32, 3), Color(0.0, 0.0, 0.0, 0.55))
	draw_rect(Rect2(-16, -43, 32.0 * clampf(fuel / 100.0, 0.0, 1.0), 3), Color(0.3, 0.7, 1.0))
