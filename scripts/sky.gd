extends Node2D
## Sky — screen-space gradient + stars + drifting clouds, drawn behind the arena.
##
## Gradient goes deep night at top → warm dusk band near the horizon. A drifting
## cloud layer sits between the stars and the parallax mountains for depth.

var _time := 0.0
# Optional per-map gradient (ported Soldat maps ship their own BgColorTop/Btm).
# Alpha 0 = unset → keep the default dusk sky.
var map_top := Color(0, 0, 0, 0)
var map_bottom := Color(0, 0, 0, 0)


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
	var has_map_sky := map_top.a > 0.0 and map_bottom.a > 0.0
	if has_map_sky:
		top = Color(map_top, 1.0)
		bottom = Color(map_bottom, 1.0)
		mid = top.lerp(bottom, 0.5)
	for i in steps:
		var t := float(i) / float(steps)
		var c := top.lerp(mid, minf(1.0, t * 2.0)) if t < 0.5 else mid.lerp(bottom, (t - 0.5) * 2.0)
		draw_rect(Rect2(0.0, view.y * t, view.x, view.y / float(steps) + 1.0), c)
	# Stars — pinned to a seeded RNG so they don't twinkle-shift every frame.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	# Stars only read on dark skies — skip them over a daylight map gradient.
	var star_count := 90
	if has_map_sky and top.get_luminance() > 0.3:
		star_count = 0
	for _i in star_count:
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
		var cc := Color(0.85, 0.88, 0.96, alpha)
		if has_map_sky:
			cc = Color(top.lerp(Color.WHITE, 0.45), alpha * 0.8)
		_draw_cloud(Vector2(x, y), w, h, cc)


func _draw_cloud(center: Vector2, w: float, h: float, col: Color) -> void:
	# Soft, puffy cloud with a flat-ish base: overlapping puffs, each drawn as
	# a few concentric discs of falling alpha (a cheap blur), brighter tops.
	var puffs := 7
	for i in puffs:
		var t := (float(i) + 0.5) / float(puffs)
		var cx := center.x - w * 0.5 + t * w
		var bump := sin(t * PI)
		var r := h * (0.55 + 0.75 * bump) * (0.9 + 0.2 * sin(float(i) * 2.3))
		var cy := center.y - r * 0.35 * bump
		for k in 4:
			var f := 1.0 - float(k) * 0.22
			draw_circle(Vector2(cx, cy), r * (1.0 + float(k) * 0.28), Color(col, col.a * 0.55 * f))
		# Lit crown.
		draw_circle(Vector2(cx, cy - r * 0.25), r * 0.6, Color(col.lightened(0.3), col.a * 0.35))
	# Flatten the underside: a wide, faint base band.
	draw_rect(Rect2(center.x - w * 0.45, center.y - h * 0.1, w * 0.9, h * 0.35), Color(col, col.a * 0.25))
