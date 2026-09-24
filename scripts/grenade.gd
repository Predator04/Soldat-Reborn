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

# #61: MP projectile sync — only the spawning peer runs physics; other peers
# freeze the RigidBody2D and lerp position/rotation to broadcast state so the
# grenade lands in the same spot on every screen.
const BROADCAST_HZ := 20.0
const LERP_RATE := 22.0
# #69: hold off broadcasting for ~200ms after spawn so the reliable spawn RPC
# has time to land on remote peers. Without this the unreliable state RPC can
# beat the reliable spawn RPC to the client, producing "Node not found" spam
# until the reliable stream catches up.
var _broadcast_cd: float = 0.20
var _target_pos: Vector2 = Vector2.ZERO
var _target_vel: Vector2 = Vector2.ZERO
var _target_rot: float = 0.0
var _has_target := false
var _exploded := false


func _ready() -> void:
	# Grenades bounce off "only bullets" polys too (terrain layer 2).
	collision_mask = 1 | 2 | 8  # terrain, bullets-only terrain, soldiers
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
	# mod_gravity scales only the fall acceleration; bounce/friction stay tuned so
	# the #30 roll feel isn't regressed under heavier/lighter gravity.
	mass = 0.25
	gravity_scale = 0.9 * MatchConfig.mod_gravity()
	# Non-authority: freeze the body kinematic so we can lerp its transform in from
	# the authority peer without physics fighting us. Explosion is now driven only
	# by the authority's reliable net_explode RPC (#69) so the client never queue_frees
	# ahead of trailing state RPCs. A very long fallback timer catches the case where
	# net_explode is somehow lost, keeping stale grenades from lingering forever.
	if multiplayer.multiplayer_peer != null and not is_multiplayer_authority():
		freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
		freeze = true
		get_tree().create_timer(fuse + 8.0).timeout.connect(_explode)
	else:
		get_tree().create_timer(fuse).timeout.connect(_explode)


func _physics_process(delta: float) -> void:
	queue_redraw()
	if multiplayer.multiplayer_peer == null:
		return
	if is_multiplayer_authority():
		# Cluster fragments don't have stable names across peers (each peer runs
		# its own randomised _explode). Broadcasting their state would target a
		# path the client doesn't have. Their in-flight visual doesn't need sync —
		# the parent's net_explode already synced the impact point (#69).
		if is_fragment:
			return
		# #69: stop broadcasting once we've exploded — otherwise trailing state
		# RPCs land on nodes the client has already queue_freed via the reliable
		# net_explode, producing "Node not found" spam.
		if _exploded:
			return
		_broadcast_cd -= delta
		if _broadcast_cd <= 0.0:
			_broadcast_cd = 1.0 / BROADCAST_HZ
			rpc("net_projectile_state", global_position, linear_velocity, rotation)
	elif _has_target:
		# Extrapolate with the last known velocity so a dropped packet doesn't
		# freeze the grenade in place; snap toward the next authoritative sample
		# on receipt.
		var t: float = clampf(delta * LERP_RATE, 0.0, 1.0)
		global_position = global_position.lerp(_target_pos + _target_vel * delta, t)
		rotation = lerp_angle(rotation, _target_rot, t)


@rpc("authority", "call_remote", "reliable")
func net_projectile_state(pos: Vector2, vel: Vector2, rot: float) -> void:
	_target_pos = pos
	_target_vel = vel
	_target_rot = rot
	_has_target = true


@rpc("authority", "call_remote", "reliable")
func net_explode(pos: Vector2) -> void:
	# Snap to the authority's exact fuse-out position so the blast damage / SFX
	# fire from the same spot on every peer. Idempotent via _exploded guard.
	global_position = pos
	_explode()


func _explode() -> void:
	# _exploded guards both the fuse timer and the authority's net_explode RPC
	# from firing this twice on a peer (#61).
	if _exploded:
		return
	_exploded = true
	# #61: authority broadcasts the exact explode position so non-authority peers
	# blast at the same spot even if their lerped position was slightly behind.
	if multiplayer.multiplayer_peer != null and is_multiplayer_authority():
		rpc("net_explode", global_position)
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
			if same_team and not is_self and not MatchConfig.friendly_fire_on():
				continue
			if multiplayer.multiplayer_peer == null or s.is_multiplayer_authority():
				s.take_damage(damage * MatchConfig.mod_damage() * (1.0 - d / blast_radius), killer_name, wname, team)
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
