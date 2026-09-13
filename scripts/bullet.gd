extends Area2D
## Bullet — fast projectile with a tracer trail.

var direction := Vector2.RIGHT
var speed := 900.0
var damage := 12.0
var team := 0
var killer_name := ""
var weapon_name := ""
# Visual style overrides. "flame" = short-lived orange puff, "arrow" = long thin shaft.
# Default "" = classic yellow tracer.
var visual := ""
# Custom lifetime; 0 = default 3s. Flames get ~0.35s so the cone is short.
var life := 0.0
# Optional gravity — arrows sag slightly, standard bullets are 0.
var gravity := 0.0
var _hit := false
var _velocity := Vector2.ZERO


func _ready() -> void:
	add_to_group("bullet")
	body_entered.connect(_on_body_entered)
	var shape := CollisionShape2D.new()
	var cs := CircleShape2D.new()
	cs.radius = 3.0
	shape.shape = cs
	add_child(shape)
	_velocity = direction * speed
	var l := life if life > 0.0 else 3.0
	get_tree().create_timer(l).timeout.connect(queue_free)


func _physics_process(delta: float) -> void:
	if gravity > 0.0:
		_velocity.y += gravity * delta
		position += _velocity * delta
		direction = _velocity.normalized()
	else:
		position += direction * speed * delta
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	# queue_free() is deferred; a second body_entered in the same physics flush would
	# otherwise apply damage to a second soldier stacked on the first.
	if _hit:
		return
	if body is CharacterBody2D:
		if body.get("team") != team and body.has_method("take_damage"):
			_hit = true
			# Damage only on the target's authority peer (SP: no peer == local == damage runs).
			if multiplayer.multiplayer_peer == null or body.is_multiplayer_authority():
				body.take_damage(damage, killer_name, weapon_name, team)
			queue_free()
			return
		return
	_hit = true
	queue_free()


func _draw() -> void:
	if visual == "flame":
		# Small orange puff, brighter core — no long tracer.
		draw_circle(Vector2.ZERO, 6.0, Color(1.0, 0.35, 0.05, 0.35))
		draw_circle(Vector2.ZERO, 4.0, Color(1.0, 0.55, 0.1, 0.7))
		draw_circle(Vector2.ZERO, 2.2, Color(1.0, 0.9, 0.55, 0.95))
	elif visual == "arrow":
		draw_line(-direction * 18.0, Vector2.ZERO, Color(0.75, 0.55, 0.3, 0.9), 1.6)
		draw_line(Vector2.ZERO, direction * 3.0, Color(0.9, 0.9, 0.9), 2.0)
	else:
		draw_line(-direction * 12.0, Vector2.ZERO, Color(1.0, 0.9, 0.4, 0.55), 2.0)
		draw_circle(Vector2.ZERO, 2.5, Color(1.0, 0.92, 0.4))
