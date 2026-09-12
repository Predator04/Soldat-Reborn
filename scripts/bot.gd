extends CharacterBody2D
## Bot — AI soldier: leads its aim, circle-strafes, dodge-jumps, lobs grenades, jet-boots up.

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

# grenades
var grenades := 3
var grenade_cd := 0.0

# strafe / dodge
var strafe_dir := 1.0
var strafe_t := 0.0
var dodge_cd := 0.0

const GRAVITY := 1700.0
const RUN_SPEED := 230.0
const JUMP_VEL := -430.0
const JET_THRUST := -1050.0
const MAX_FALL := 1300.0
const BULLET_SPEED := 720.0
const ENGAGE_RANGE := 720.0

var bullet_scene := preload("res://scenes/bullet.tscn")
var grenade_scene := preload("res://scenes/grenade.tscn")


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

	_refresh_target()

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
		dir = 1.0  # idle wander toward the right

	velocity.x = move_toward(velocity.x, dir * RUN_SPEED, 1300.0 * delta)

	# dodge-jump when an enemy bullet is closing in
	dodge_cd -= delta
	if dodge_cd <= 0.0 and _bullet_incoming():
		if on_floor:
			velocity.y = JUMP_VEL
		dodge_cd = 0.5

	# jump / jet toward the target when it's above us
	jet_on = false
	jump_cd -= delta
	if is_instance_valid(target):
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

	# lob a grenade at mid-range
	grenade_cd -= delta
	if is_instance_valid(target) and grenade_cd <= 0.0 and grenades > 0:
		var dist: float = sqrt(dx * dx + dy * dy)
		if dist > 300.0 and dist < 560.0:
			_throw_grenade(dx, dy, dist)
			grenade_cd = 2.5

	# shoot with lead aim
	fire_cd -= delta
	if is_instance_valid(target) and fire_cd <= 0.0:
		var to_t: Vector2 = target.global_position - global_position
		if to_t.length() < ENGAGE_RANGE:
			_shoot(to_t)

	queue_redraw()


func _refresh_target() -> void:
	if is_instance_valid(target) and not target.get("dead"):
		return
	target = null
	for s in get_tree().get_nodes_in_group("soldier"):
		if s.get("team") != team and s != self and not s.get("dead"):
			target = s
			break


func _bullet_incoming() -> bool:
	for b in get_tree().get_nodes_in_group("bullet"):
		if not is_instance_valid(b) or int(b.get("team")) == team:
			continue
		var to_b: Vector2 = b.global_position - global_position
		var d: float = to_b.length()
		if d < 150.0 and d > 1.0:
			var bvel: Vector2 = b.get("direction") * float(b.get("speed"))
			if to_b.normalized().dot(bvel.normalized()) > 0.6:
				return true
	return false


func _throw_grenade(dx: float, dy: float, dist: float) -> void:
	grenades -= 1
	var g := grenade_scene.instantiate()
	g.global_position = global_position + Vector2(signf(dx) * 10.0, -8.0)
	g.team = team
	var toss := (Vector2(dx, dy) / dist + Vector2(0, -0.6)).normalized()
	g.linear_velocity = toss * 460.0
	g.angular_velocity = randf_range(-8.0, 8.0)
	get_parent().add_child(g)


func _shoot(to_t: Vector2) -> void:
	var aim := to_t.normalized()
	# lead the target by its velocity (predictive aim)
	if is_instance_valid(target) and target is CharacterBody2D:
		var t_est: float = to_t.length() / BULLET_SPEED
		var lead: Vector2 = target.global_position + target.velocity * t_est
		aim = (lead - global_position).normalized()
	var b := bullet_scene.instantiate()
	b.global_position = global_position + aim * 26.0
	b.direction = aim
	b.speed = BULLET_SPEED
	b.damage = 12.0
	b.team = team
	get_parent().add_child(b)
	fire_cd = 0.45


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
	# defer FX spawn out of the physics flush (bullet body_entered → take_damage path)
	_spawn_gibs.call_deferred()
	_spawn_ragdoll.call_deferred()
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
