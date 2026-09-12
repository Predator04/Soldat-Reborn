extends Area2D
## Bullet — fast projectile with a tracer trail.

var direction := Vector2.RIGHT
var speed := 900.0
var damage := 12.0
var team := 0
var killer_name := ""
var weapon_name := ""


func _ready() -> void:
	add_to_group("bullet")
	body_entered.connect(_on_body_entered)
	var shape := CollisionShape2D.new()
	var cs := CircleShape2D.new()
	cs.radius = 3.0
	shape.shape = cs
	add_child(shape)
	get_tree().create_timer(3.0).timeout.connect(queue_free)


func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	if body is CharacterBody2D:
		if body.get("team") != team and body.has_method("take_damage"):
			# Damage only on the target's authority peer (SP: no peer == local == damage runs).
			if multiplayer.multiplayer_peer == null or body.is_multiplayer_authority():
				body.take_damage(damage, killer_name, weapon_name, team)
			queue_free()
			return
		return
	queue_free()


func _draw() -> void:
	draw_line(-direction * 34.0, Vector2.ZERO, Color(1.0, 0.9, 0.4, 0.55), 2.0)
	draw_circle(Vector2.ZERO, 2.5, Color(1.0, 0.92, 0.4))
