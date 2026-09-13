extends Node2D
## Sky — screen-space gradient + stars + drifting clouds, drawn behind the arena.
##
## Gradient goes deep night at top → warm dusk band near the horizon. A drifting
## cloud layer sits between the stars and the parallax mountains for depth.

var _time := 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var view := get_viewport_rect().size
	# Sky gradient — deep indigo → warm dusk band near horizon (blends with parallax haze).
	var steps := 64
	var top := Color(0.03, 0.04, 0.11)
	var mid := Color(0.10, 0.14, 0.26)
	var bottom := Color(0.34, 0.24, 0.28)
	for i in steps:
		var t := float(i) / float(steps)
		var c := top.lerp(mid, minf(1.0, t * 2.0)) if t < 0.5 else mid.lerp(bottom, (t - 0.5) * 2.0)
		draw_rect(Rect2(0.0, view.y * t, view.x, view.y / float(steps) + 1.0), c)
	# Stars — pinned to a seeded RNG so they don't twinkle-shift every frame.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for _i in 90:
		var x := rng.randf_range(0.0, view.x)
		var y := rng.randf_range(0.0, view.y * 0.55)
		var r := rng.randf_range(0.6, 1.7)
		var a := rng.randf_range(0.2, 0.85)
		# Gentle twinkle so night skies don't feel dead.
		a *= 0.75 + 0.25 * sin(_time * 1.8 + x * 0.017 + y * 0.023)
		draw_circle(Vector2(x, y), r, Color(1, 1, 1, a))
	# Drifting clouds — soft ellipses across the upper third of the sky.
	var cloud_rng := RandomNumberGenerator.new()
	cloud_rng.seed = 4242
	for _i in 6:
		var base_x := cloud_rng.randf_range(0.0, view.x)
		var y := cloud_rng.randf_range(view.y * 0.10, view.y * 0.32)
		var speed := cloud_rng.randf_range(6.0, 18.0)
		var w := cloud_rng.randf_range(160.0, 340.0)
		var h := cloud_rng.randf_range(22.0, 42.0)
		var alpha := cloud_rng.randf_range(0.08, 0.16)
		var x := fposmod(base_x + _time * speed, view.x + w) - w * 0.5
		_draw_cloud(Vector2(x, y), w, h, Color(0.85, 0.88, 0.96, alpha))


func _draw_cloud(center: Vector2, w: float, h: float, col: Color) -> void:
	# Stacked circles fake a soft cloud silhouette without a texture asset.
	var count := 5
	for i in count:
		var t := (float(i) + 0.5) / float(count)
		var cx := center.x - w * 0.5 + t * w
		var cy := center.y + sin(t * PI) * -h * 0.3
		var r := h * (0.9 + 0.5 * sin(t * PI))
		draw_circle(Vector2(cx, cy), r, col)
