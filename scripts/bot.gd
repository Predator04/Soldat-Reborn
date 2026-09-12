extends CharacterBody2D
## Bot — simple AI soldier: chases the player, jet-boots up, shoots.

@export var color := Color(0.85, 0.3, 0.25)
var team := 1

var health := 100.0
var fuel := 100.0
var facing := 1.0
var jet_on := false
var dead := false
var fire_cd := 0.5
var jump_cd := 0.0
var target: Node2D = null

const GRAVITY := 1700.0
const RUN_SPEED := 230.0
const JUMP_VEL := -430.0
const JET_THRUST := -1050.0
const MAX_FALL := 1300.0

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
		return

	# Acquire the nearest enemy soldier (team 0)
	if not is_instance_valid(target):
		target = null
		for s in get_tree().get_nodes_in_group("soldier"):
			if s.get("team") == 0 and s != self:
				target = s
				break

	var dir := 0.0
	if is_instance_valid(target):
		var dx: float = target.global_position.x - global_position.x
		if absf(dx) > 70.0:
			dir = 1.0 if dx > 0.0 else -1.0
	else:
		dir = 1.0  # idle wander toward the right

	var on_floor := is_on_floor()

	velocity.x = move_toward(velocity.x, dir * RUN_SPEED, 1300.0 * delta)

	# Jump / jet toward the target when it's above us
	jet_on = false
	jump_cd -= delta
	if is_instance_valid(target):
		var dy: float = target.global_position.y - global_position.y
		if dy < -50.0 and on_floor and jump_cd <= 0.0:
			velocity.y = JUMP_VEL
			jump_cd = 0.9
		elif dy < -80.0 and not on_floor and fuel > 0.0:
			velocity.y += JET_THRUST * delta
			fuel = maxf(0.0, fuel - 40.0 * delta)
			jet_on = true
	if on_floor:
		fuel = minf(100.0, fuel + 32.0 * delta)

	if not on_floor:
		velocity.y += GRAVITY * delta
		velocity.y = minf(velocity.y, MAX_FALL)

	if dir != 0.0:
		facing = dir

	move_and_slide()

	# Shoot at the player when reasonably close
	fire_cd -= delta
	if is_instance_valid(target) and fire_cd <= 0.0:
		var to_t: Vector2 = target.global_position - global_position
		if to_t.length() < 720.0:
			var aim := to_t.normalized()
			var b := bullet_scene.instantiate()
			b.global_position = global_position + aim * 26.0
			b.direction = aim
			b.speed = 720.0
			b.team = team
			get_parent().add_child(b)
			fire_cd = 0.45

	queue_redraw()


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
	var body_col := color
	draw_rect(Rect2(-9, 0, 7, 10), body_col.darkened(0.3))
	draw_rect(Rect2(2, 0, 7, 10), body_col.darkened(0.3))
	draw_rect(Rect2(-11, -30, 22, 30), body_col)
	draw_circle(Vector2(facing * 2.0, -34), 6.0, body_col.lightened(0.15))
	draw_rect(Rect2(-facing * 16.0 - 3.0, -26, 5, 18), body_col.darkened(0.15))
	if jet_on:
		var fl := 24.0 + sin(Time.get_ticks_msec() * 0.05) * 6.0
		var back := facing * -1.0
		draw_polygon(
			PackedVector2Array([
				Vector2(back * 14.0 - 4.0, 2.0),
				Vector2(back * 14.0 + 4.0, 2.0),
				Vector2(back * (14.0 + fl), 2.0)
			]),
			PackedColorArray([
				Color(1.0, 0.6, 0.2, 0.9),
				Color(1.0, 0.6, 0.2, 0.9),
				Color(1.0, 1.0, 1.0, 0.0)
			])
		)
	draw_rect(Rect2(-16, -48, 32, 4), Color(0.0, 0.0, 0.0, 0.55))
	draw_rect(Rect2(-16, -48, 32.0 * clampf(health / 100.0, 0.0, 1.0), 4), Color(0.9, 0.2, 0.2))
