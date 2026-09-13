extends Node2D
## Draws the Battle-Royale safe zone ring. Reads center + radius from parent Main.


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var main := get_parent()
	if main == null or not main.has_method("br_zone"):
		return
	var z: Dictionary = main.br_zone()
	var center: Vector2 = z.get("center", Vector2.ZERO)
	var radius: float = float(z.get("radius", 0.0))
	if radius <= 0.0:
		return
	# Outer ring — the safe boundary.
	draw_arc(center, radius, 0.0, TAU, 96, Color(1.0, 0.75, 0.25, 0.9), 3.0)
	# Danger tint sweeping outward from the ring (fake radial shading).
	draw_arc(center, radius + 8.0, 0.0, TAU, 96, Color(1.0, 0.35, 0.2, 0.35), 6.0)
