extends Node2D
## Sky — screen-space gradient + stars, drawn behind the arena.


func _draw() -> void:
	var view := get_viewport_rect().size
	var steps := 48
	var top := Color(0.04, 0.05, 0.13)
	var bottom := Color(0.14, 0.22, 0.36)
	for i in steps:
		var t := float(i) / float(steps)
		draw_rect(Rect2(0.0, view.y * t, view.x, view.y / float(steps) + 1.0), top.lerp(bottom, t))
	# stars
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for _i in 70:
		var x := rng.randf_range(0.0, view.x)
		var y := rng.randf_range(0.0, view.y * 0.7)
		var r := rng.randf_range(0.6, 1.6)
		var a := rng.randf_range(0.2, 0.8)
		draw_circle(Vector2(x, y), r, Color(1, 1, 1, a))
