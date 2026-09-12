extends Area2D
## Bullet — fast projectile that damages opposing-team soldiers and dies on terrain.

var direction := Vector2.RIGHT
var speed := 900.0
var damage := 12.0
var team := 0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	var shape := CollisionShape2D.new()
	var cs := CircleShape2D.new()
	cs.radius = 3.0
	shape.shape = cs
	add_child(shape)
	get_tree().create_timer(3.0).timeout.connect(queue_free)


func _physics_process(delta: float) -> void:
	position += direction * speed * delta


func _on_body_entered(body: Node) -> void:
	if body is CharacterBody2D:
		if body.get("team") != team and body.has_method("take_damage"):
			body.take_damage(damage)
			queue_free()
			return
		# Same-team soldier (e.g. the shooter) — pass through
		return
	# Terrain / walls
	queue_free()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 2.5, Color(1.0, 0.92, 0.4))
