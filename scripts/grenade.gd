extends RigidBody2D
## Grenade — bounces, fuses, explodes with area damage.

var team := 0
var killer_name := ""
var fuse := 1.7
var damage := 72.0
var blast_radius := 120.0
# Cluster mode: on explosion, spawn a burst of smaller fragment grenades that also explode.
var cluster := false
var is_fragment := false  # true for the child mini-grenades from a cluster


func _ready() -> void:
	var shape := CollisionShape2D.new()
	var cs := CircleShape2D.new()
	cs.radius = 5.0
	shape.shape = cs
	add_child(shape)
	# Soldat 2 tuning (#30): bouncier restitution + noticeably lower friction so
	# grenades keep rolling instead of dying on their first bounce.
	# Also nudge damping so a live grenade on a slope keeps sliding toward the target.
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.72
	mat.friction = 0.18
	mat.rough = false
	physics_material_override = mat
	linear_damp = 0.35
	angular_damp = 0.4
	# Encourage roll — a spinning grenade converts angular velocity into more
	# horizontal travel on contact (mass_low + gravity_scale slightly < 1).
	mass = 0.25
	gravity_scale = 0.9
	get_tree().create_timer(fuse).timeout.connect(_explode)


func _physics_process(_delta: float) -> void:
	queue_redraw()


func _explode() -> void:
	if cluster:
		Sfx.cluster_explode()
	else:
		Sfx.explode()
	var wname: String = "Cluster" if (cluster or is_fragment) else "Grenade"
	for s in get_tree().get_nodes_in_group("soldier"):
		if not is_instance_valid(s):
			continue
		var d: float = global_position.distance_to(s.global_position)
		if d < blast_radius:
			var same_team: bool = int(s.get("team")) == team
			var is_self: bool = s.get("display_name") == killer_name
			if same_team and not is_self and not Settings.friendly_fire_on():
				continue
			if multiplayer.multiplayer_peer == null or s.is_multiplayer_authority():
				s.take_damage(damage * float(Settings.mod_damage) * (1.0 - d / blast_radius), killer_name, wname, team)
	# Lo-fi (#25): skip the CPUParticles2D flame burst. The Sfx call above still fires.
	if not Settings.lofi:
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
	# Cluster parent spawns 5 fragment sub-grenades on death; short random fuses cascade the pops.
	if cluster:
		var parent := get_parent()
		var frag_scene: PackedScene = load("res://scenes/grenade.tscn") as PackedScene
		if frag_scene != null and parent != null:
			for i in 5:
				var frag := frag_scene.instantiate()
				frag.global_position = global_position + Vector2(randf_range(-6.0, 6.0), -8.0)
				frag.team = team
				frag.killer_name = killer_name
				frag.is_fragment = true
				frag.fuse = randf_range(0.4, 0.9)
				frag.damage = 45.0
				frag.blast_radius = 90.0
				var ang: float = randf_range(-PI, 0.0)
				var spd: float = randf_range(180.0, 320.0)
				frag.linear_velocity = Vector2(cos(ang), sin(ang)) * spd
				frag.angular_velocity = randf_range(-10.0, 10.0)
				parent.add_child(frag)
	queue_free()


func _draw() -> void:
	if cluster:
		draw_circle(Vector2.ZERO, 5.5, Color(0.5, 0.25, 0.15))
		draw_circle(Vector2.ZERO, 2.2, Color(1.0, 0.7, 0.25))
	elif is_fragment:
		draw_circle(Vector2.ZERO, 3.5, Color(0.55, 0.25, 0.15))
	else:
		draw_circle(Vector2.ZERO, 5.0, Color(0.35, 0.42, 0.3))
		draw_circle(Vector2.ZERO, 2.0, Color(0.5, 0.55, 0.4))
