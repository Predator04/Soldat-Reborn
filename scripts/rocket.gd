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

# #61: MP transform sync. Only the shooter runs the ballistic integration and
# broadcasts pos/vel/rot at physics rate; other peers lerp toward the incoming
# state. Preserves the existing damage authority guard in _explode().
const BROADCAST_HZ := 20.0
const LERP_RATE := 22.0
# #69: hold off first broadcast for ~200ms so the reliable spawn RPC
# (net_bot_shoot / net_shoot) has time to deliver the spawn on remote peers
# before the unreliable state stream begins. Without this the state RPC beats
# the spawn RPC and produces "Node not found: Main/BotRocket_1_1" spam.
var _broadcast_cd: float = 0.20
var _target_pos: Vector2 = Vector2.ZERO
var _target_dir: Vector2 = Vector2.RIGHT
var _has_target := false


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
	if multiplayer.multiplayer_peer != null and not is_multiplayer_authority():
		# Non-authority: lerp toward the shooter's broadcast transform so shooter
		# and victim see the rocket + explosion at the same spot (#61). We used to
		# self-destruct via _life so client-side cleanup fires if RPCs stop arriving,
		# but that raced with the authority's net_explode + reliable state broadcasts
		# — the client would queue_free just as a trailing state RPC arrived. #69:
		# extend the fallback life so the reliable net_explode always wins.
		if _has_target:
			var t: float = clampf(delta * LERP_RATE, 0.0, 1.0)
			position = position.lerp(_target_pos + _target_dir * speed * delta, t)
			direction = _target_dir
			_smoke.direction = -direction
		_life -= delta
		if _life <= -6.0:
			_explode()
		queue_redraw()
		return
	# Straight-flight LAW keeps its constant velocity; M79 lobs by adding gravity to _velocity.
	# mod_gravity scales the fall accel so an M79 arc matches the world's gravity mod (LAW
	# has grav==0, so straight flight is unaffected — no regression there).
	if grav > 0.0:
		_velocity.y += grav * MatchConfig.mod_gravity() * delta
		position += _velocity * delta
		direction = _velocity.normalized()
	else:
		position += direction * speed * delta
	_smoke.direction = -direction
	_life -= delta
	if _life <= 0.0:
		_explode()
	queue_redraw()
	# Broadcast transform to non-authority peers (#61).
	# #69: once we've exploded, stop broadcasting — the client has queue_freed
	# via reliable net_explode and any trailing state RPC would print "Node not found".
	if multiplayer.multiplayer_peer != null and not _exploded:
		_broadcast_cd -= delta
		if _broadcast_cd <= 0.0:
			_broadcast_cd = 1.0 / BROADCAST_HZ
			rpc("net_projectile_state", global_position, direction)


@rpc("authority", "call_remote", "reliable")
func net_projectile_state(pos: Vector2, dir: Vector2) -> void:
	_target_pos = pos
	_target_dir = dir
	_has_target = true


@rpc("authority", "call_remote", "reliable")
func net_explode(pos: Vector2) -> void:
	# Snap to the authority's impact position before the local explosion so the
	# blast damage falloff matches what the shooter saw.
	global_position = pos
	_explode()


func _on_body_entered(body: Node) -> void:
	# Same-team direct impact: skip damage but still consume the rocket so it doesn't
	# fly through and hit again elsewhere. Splash from the fuse path can still happen.
	# #69: non-authority peers must NOT self-explode — they'd queue_free ahead of any
	# trailing state RPC from the authority. Only the shooter decides when to blow.
	if multiplayer.multiplayer_peer != null and not is_multiplayer_authority():
		return
	# Same-team direct impact used to always no-damage-consume the rocket. With FF
	# on (#74) we let the rocket explode on a teammate too so the blast can splash.
	if body is CharacterBody2D and body.get("team") == team and not MatchConfig.friendly_fire_on():
		queue_free()
		return
	_explode()


func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	# #61: authority tells remotes to explode at the same instant so shooter and
	# victim see the impact fireball in the same spot. Local `_exploded` guard
	# above keeps this idempotent.
	if multiplayer.multiplayer_peer != null and is_multiplayer_authority():
		rpc("net_explode", global_position)
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
		if same_team and not is_self and not MatchConfig.friendly_fire_on():
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
