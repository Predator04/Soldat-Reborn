extends Area2D
## LAW rocket — slow, straight, area-damage on impact. Trails smoke + fire.

var direction := Vector2.RIGHT
var speed := 720.0
var damage := 90.0
var blast_radius := 130.0
var team := 0
var killer_name := ""
var weapon_name := "LAW"
# Gravity acceleration applied per second — 0 keeps LAW's straight flight, ~980
# gives the M79 grenade its characteristic arc.
var grav := 0.0

var _life := 4.0
var _smoke: CPUParticles2D
var _exploded := false
var _velocity := Vector2.ZERO


func _ready() -> void:
	add_to_group("bullet")
	body_entered.connect(_on_body_entered)
	_velocity = direction * speed
	var shape := CollisionShape2D.new()
	var cs := CircleShape2D.new()
	cs.radius = 5.0
	shape.shape = cs
	add_child(shape)
	_smoke = CPUParticles2D.new()
	_smoke.amount = 22
	_smoke.lifetime = 0.55
	_smoke.one_shot = false
	_smoke.emitting = not Settings.lofi
	_smoke.direction = Vector2(-1, 0)
	_smoke.spread = 22.0
	_smoke.gravity = Vector2(0, -40)
	_smoke.initial_velocity_min = 40.0
	_smoke.initial_velocity_max = 90.0
	_smoke.scale_amount_min = 2.0
	_smoke.scale_amount_max = 4.0
	_smoke.color = Color(0.9, 0.6, 0.35, 0.85)
	add_child(_smoke)


func _physics_process(delta: float) -> void:
	# Straight-flight LAW keeps its constant velocity; M79 lobs by adding gravity to _velocity.
	if grav > 0.0:
		_velocity.y += grav * delta
		position += _velocity * delta
		direction = _velocity.normalized()
	else:
		position += direction * speed * delta
	_smoke.direction = -direction
	_life -= delta
	if _life <= 0.0:
		_explode()
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	# Same-team direct impact: skip damage but still consume the rocket so it doesn't
	# fly through and hit again elsewhere. Splash from the fuse path can still happen.
	if body is CharacterBody2D and body.get("team") == team:
		queue_free()
		return
	_explode()


func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	if weapon_name == "M79":
		Sfx.m79_thump()
	else:
		Sfx.explode()
	for s in get_tree().get_nodes_in_group("soldier"):
		if not is_instance_valid(s):
			continue
		var d: float = global_position.distance_to(s.global_position)
		if d >= blast_radius:
			continue
		# In DM: rockets damage everyone (rocket-jump lives). In team modes: friendly-fire off,
		# but the thrower is always damageable so self-rocket-jumping still works.
		var same_team: bool = int(s.get("team")) == team
		var is_self: bool = s.get("display_name") == killer_name
		if same_team and not is_self and not Settings.friendly_fire_on():
			continue
		var scaled: float = damage * (1.0 - d / blast_radius)
		if s.has_method("take_damage") and (multiplayer.multiplayer_peer == null or s.is_multiplayer_authority()):
			s.take_damage(scaled, killer_name, weapon_name, team)
	if not Settings.lofi:
		var p := CPUParticles2D.new()
		p.amount = 70
		p.lifetime = 0.55
		p.explosiveness = 1.0
		p.one_shot = true
		p.emitting = true
		p.global_position = global_position
		p.direction = Vector2(0, -1)
		p.spread = 180.0
		p.gravity = Vector2(0, 260)
		p.initial_velocity_min = 140.0
		p.initial_velocity_max = 520.0
		p.scale_amount_min = 3.0
		p.scale_amount_max = 7.0
		p.color = Color(1.0, 0.55, 0.2)
		get_parent().add_child(p)
		get_tree().create_timer(0.9).timeout.connect(p.queue_free)
	queue_free()


func _draw() -> void:
	# Warhead + fins + plume
	var back := -direction
	var side := Vector2(-direction.y, direction.x)
	draw_polygon(
		PackedVector2Array([
			direction * 10.0,
			back * 6.0 + side * 4.0,
			back * 6.0 - side * 4.0,
		]),
		PackedColorArray([
			Color(0.9, 0.9, 0.9),
			Color(0.6, 0.6, 0.65),
			Color(0.6, 0.6, 0.65),
		])
	)
	draw_line(back * 6.0 + side * 4.0, back * 12.0 + side * 7.0, Color(0.4, 0.42, 0.5), 2.0)
	draw_line(back * 6.0 - side * 4.0, back * 12.0 - side * 7.0, Color(0.4, 0.42, 0.5), 2.0)
	draw_circle(back * 14.0, 3.5, Color(1.0, 0.85, 0.35, 0.9))
