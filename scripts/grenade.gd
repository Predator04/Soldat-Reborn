extends RigidBody2D
## Grenade — bounces, fuses, explodes with area damage.

var team := 0
var killer_name := ""
var fuse := 1.7
var damage := 72.0
var blast_radius := 120.0


func _ready() -> void:
	var shape := CollisionShape2D.new()
	var cs := CircleShape2D.new()
	cs.radius = 5.0
	shape.shape = cs
	add_child(shape)
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.55
	mat.friction = 0.4
	physics_material_override = mat
	get_tree().create_timer(fuse).timeout.connect(_explode)


func _physics_process(_delta: float) -> void:
	queue_redraw()


func _explode() -> void:
	Sfx.explode()
	for s in get_tree().get_nodes_in_group("soldier"):
		if not is_instance_valid(s) or s.get("team") == team:
			continue
		var d: float = global_position.distance_to(s.global_position)
		if d < blast_radius:
			# Damage only on target's authority peer (SP: no peer == local == damage runs).
			if multiplayer.multiplayer_peer == null or s.is_multiplayer_authority():
				s.take_damage(damage * (1.0 - d / blast_radius), killer_name, "Grenade", team)
	var p := CPUParticles2D.new()
	p.amount = 55
	p.lifetime = 0.5
	p.explosiveness = 1.0
	p.one_shot = true
	p.emitting = true
	p.global_position = global_position
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = Vector2(0, 300)
	p.initial_velocity_min = 100.0
	p.initial_velocity_max = 420.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 6.0
	p.color = Color(1.0, 0.6, 0.2)
	get_parent().add_child(p)
	get_tree().create_timer(0.8).timeout.connect(p.queue_free)
	queue_free()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 5.0, Color(0.35, 0.42, 0.3))
	draw_circle(Vector2.ZERO, 2.0, Color(0.5, 0.55, 0.4))
