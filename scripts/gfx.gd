extends RefCounted
## Graphics helpers shared by the game: quality level, light glows, smoke,
## shell casings, dust, scorch marks. Everything here is cosmetic and
## capped so a minigun / rocket spam can't flood the scene.
##
## Quality (Settings.gfx_quality): 0 Low (the old Lo-fi: no particles, no
## glow, no post), 1 Medium (glows, smoke, casings, shadows, light post FX —
## phones default here), 2 High (+ bloom, real 2D lights on explosions,
## terrain grass, ambient particles).

const LOW := 0
const MEDIUM := 1
const HIGH := 2

static var _glow_tex: Texture2D = null
static var _soft_tex: Texture2D = null
static var _add_mat: CanvasItemMaterial = null
static var live_glows := 0
static var live_smoke := 0
static var live_casings := 0
static var live_scorch: Array = []
const MAX_GLOWS := 40
const MAX_SMOKE := 60
const MAX_CASINGS := 40
const MAX_SCORCH := 24


static func q() -> int:
	if DisplayServer.get_name() == "headless":
		return LOW if Settings.lofi else int(Settings.gfx_quality)
	return int(Settings.gfx_quality)


static func on(level: int) -> bool:
	return q() >= level


## Soft radial white blob (glows, smoke, light textures).
static func glow_tex() -> Texture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.25, 0.6, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.14), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.width = 128
		t.height = 128
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		_glow_tex = t
	return _glow_tex


static func soft_tex() -> Texture2D:
	if _soft_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.width = 64
		t.height = 64
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		_soft_tex = t
	return _soft_tex


static func add_mat() -> CanvasItemMaterial:
	if _add_mat == null:
		_add_mat = CanvasItemMaterial.new()
		_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add_mat


## A flash of light: additive glow that blooms out and fades. On High a real
## PointLight2D (no shadows) comes with big ones so nearby terrain lights up.
static func flash(parent: Node, at: Vector2, col: Color, radius: float, life: float, real_light := false) -> void:
	if parent == null or not on(MEDIUM) or live_glows >= MAX_GLOWS:
		return
	var n := _Glow.new()
	n.col = col
	n.radius = radius
	n.life = life
	n.position = at
	parent.add_child(n)
	if real_light and on(HIGH):
		var l := PointLight2D.new()
		l.texture = glow_tex()
		l.color = col
		l.energy = 1.6
		l.texture_scale = radius / 40.0
		l.position = at
		parent.add_child(l)
		var tw := l.create_tween()
		tw.tween_property(l, "energy", 0.0, life * 1.6)
		tw.tween_callback(l.queue_free)


static func muzzle(parent: Node, at: Vector2, explosive := false) -> void:
	if explosive:
		flash(parent, at, Color(1.0, 0.6, 0.25), 70.0, 0.12)
	else:
		flash(parent, at, Color(1.0, 0.78, 0.4), 46.0, 0.06)


static func explosion(parent: Node, at: Vector2, radius: float) -> void:
	if parent == null:
		return
	flash(parent, at, Color(1.0, 0.55, 0.2), radius * 2.2, 0.4, true)
	flash(parent, at, Color(1.0, 0.9, 0.6), radius * 0.9, 0.12)
	for i in 7:
		var a := randf() * TAU
		smoke(parent, at + Vector2.RIGHT.rotated(a) * randf_range(4.0, radius * 0.35),
			Vector2.RIGHT.rotated(a) * randf_range(20.0, 70.0) + Vector2(0, -30), randf_range(18.0, 34.0), randf_range(1.2, 2.2), Color(0.18, 0.17, 0.16, 0.55))
	scorch(parent, at, radius)


static func smoke(parent: Node, at: Vector2, vel: Vector2, size: float, life: float, col := Color(0.6, 0.6, 0.6, 0.4)) -> void:
	if parent == null or not on(MEDIUM) or live_smoke >= MAX_SMOKE:
		return
	var n := _Smoke.new()
	n.vel = vel
	n.size = size
	n.life = life
	n.col = col
	n.position = at
	parent.add_child(n)


## Brass flying out of the gun (dir = +1 / -1 soldier facing).
static func casing(parent: Node, at: Vector2, facing: float, shell := false) -> void:
	if parent == null or not on(MEDIUM) or live_casings >= MAX_CASINGS:
		return
	var n := _Casing.new()
	n.vel = Vector2(-facing * randf_range(60.0, 130.0), randf_range(-190.0, -120.0))
	n.spin = randf_range(-20.0, 20.0)
	n.col = Color(0.75, 0.2, 0.15) if shell else Color(0.92, 0.74, 0.32)
	n.len = 3.4 if shell else 2.4
	n.position = at
	parent.add_child(n)


static func dust(parent: Node, at: Vector2, strength := 1.0) -> void:
	if not on(MEDIUM):
		return
	for i in int(3 + strength * 3):
		smoke(parent, at + Vector2(randf_range(-8, 8), -2), Vector2(randf_range(-70, 70) * strength, randf_range(-40, -10)),
			randf_range(6.0, 11.0) * (0.7 + strength * 0.4), randf_range(0.4, 0.7), Color(0.72, 0.66, 0.56, 0.35))


## Dark blast mark left on the ground for a while.
static func scorch(parent: Node, at: Vector2, radius: float) -> void:
	if parent == null or not on(MEDIUM) or not (parent is Node2D) or not parent.is_inside_tree():
		return
	# Only on the ground: find it straight below (a mid-air blast leaves none).
	var space := (parent as Node2D).get_world_2d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters2D.create(at + Vector2(0, -6), at + Vector2(0, radius * 0.7), 1))
	if hit.is_empty():
		return
	var s := Sprite2D.new()
	s.texture = soft_tex()
	s.modulate = Color(0.05, 0.04, 0.03, 0.6)
	s.scale = Vector2.ONE * (radius / 32.0) * Vector2(1.2, 0.42)
	s.position = (hit.position as Vector2) + Vector2(0, 7)
	s.z_index = -1
	parent.add_child(s)
	live_scorch.append(s)
	while live_scorch.size() > MAX_SCORCH:
		var old = live_scorch.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var tw := s.create_tween()
	tw.tween_interval(14.0)
	tw.tween_property(s, "modulate:a", 0.0, 4.0)
	tw.tween_callback(func() -> void:
		live_scorch.erase(s)
		s.queue_free())


class _Glow extends Sprite2D:
	var col := Color.WHITE
	var radius := 40.0
	var life := 0.1
	var _t := 0.0

	func _ready() -> void:
		var G = load("res://scripts/gfx.gd")
		G.live_glows += 1
		texture = G.glow_tex()
		material = G.add_mat()
		z_index = 60
		modulate = col
		scale = Vector2.ONE * (radius / 64.0)

	func _exit_tree() -> void:
		var G = load("res://scripts/gfx.gd")
		G.live_glows -= 1

	func _process(delta: float) -> void:
		_t += delta
		var k := _t / life
		if k >= 1.0:
			queue_free()
			return
		modulate.a = col.a * (1.0 - k) * (1.0 - k)
		scale = Vector2.ONE * (radius / 64.0) * (0.85 + 0.3 * k)


class _Smoke extends Sprite2D:
	var vel := Vector2.ZERO
	var size := 16.0
	var life := 1.0
	var col := Color(0.6, 0.6, 0.6, 0.4)
	var _t := 0.0
	var _rot := 0.0

	func _ready() -> void:
		var G = load("res://scripts/gfx.gd")
		G.live_smoke += 1
		texture = G.soft_tex()
		z_index = 4
		modulate = col
		_rot = randf_range(-1.0, 1.0)
		scale = Vector2.ONE * (size / 64.0)

	func _exit_tree() -> void:
		var G = load("res://scripts/gfx.gd")
		G.live_smoke -= 1

	func _process(delta: float) -> void:
		_t += delta
		var k := _t / life
		if k >= 1.0:
			queue_free()
			return
		position += vel * delta
		vel *= 1.0 - minf(1.0, delta * 2.2)
		vel.y -= 12.0 * delta
		rotation += _rot * delta
		scale = Vector2.ONE * (size / 64.0) * (1.0 + k * 1.6)
		modulate.a = col.a * (1.0 - k)


class _Casing extends Node2D:
	var vel := Vector2.ZERO
	var spin := 0.0
	var col := Color.WHITE
	var len := 2.4
	var _t := 0.0

	func _ready() -> void:
		var G = load("res://scripts/gfx.gd")
		G.live_casings += 1
		z_index = 3

	func _exit_tree() -> void:
		var G = load("res://scripts/gfx.gd")
		G.live_casings -= 1

	func _process(delta: float) -> void:
		_t += delta
		if _t > 0.9:
			queue_free()
			return
		vel.y += 700.0 * delta
		position += vel * delta
		rotation += spin * delta
		if _t > 0.6:
			modulate.a = (0.9 - _t) / 0.3
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(-len * 0.5, -0.7, len, 1.4), col)
