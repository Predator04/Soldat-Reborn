extends RefCounted
## Graphics helpers shared by the game: quality level, light glows, smoke,
## shell casings, dust, scorch marks. Everything here is cosmetic and
## capped so a minigun / rocket spam can't flood the scene.
##
## Quality (Settings.gfx_quality): 0 Low (the old Lo-fi: no particles, no
## glow, no post), 1 Medium (glows, smoke, casings, shadows, light post FX —
## phones default here), 2 High (+ bloom, real 2D lights on explosions,
## terrain grass, ambient particles).
##
## Phase B (#271): nothing here creates a node any more. Every effect is a slot
## in a fixed-size pool owned by scripts/gfx/fx_world.gd (one per match, drawn
## by a handful of batched canvas items), and every random number comes from
## `rng` below — never the global randf(), which gameplay (weapon spread, bot
## AI, spawn picks) uses. Cosmetics must not shift the gameplay random stream.

const LOW := 0
const MEDIUM := 1
const HIGH := 2

## The FX random stream (also used by sfx-pitch / popup / gore code). Seeded
## once; gameplay never reads it.
static var rng := _make_rng()

static var _glow_tex: Texture2D = null
static var _soft_tex: Texture2D = null
static var _dot_tex: Texture2D = null
static var _add_mat: CanvasItemMaterial = null
# Live counts per effect kind, kept by fx_world.gd (tests + diagnostics).
static var live_glows := 0
static var live_smoke := 0
static var live_casings := 0
# High caps (Medium is about half — see fx_world.gd KIND_CAP).
const MAX_GLOWS := 40
const MAX_SMOKE := 60
const MAX_CASINGS := 64
const MAX_SCORCH := 24


static func _make_rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.randomize()
	return r


static func rf(a: float, b: float) -> float:
	return rng.randf_range(a, b)


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


## Tiny 8 px soft dot for embers / sparks drawn a few pixels wide (the big
## gradients have no mipmaps, so shrunk to 3 px they read as hard squares).
static func dot_tex() -> Texture2D:
	if _dot_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.width = 8
		t.height = 8
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		_dot_tex = t
	return _dot_tex


static func add_mat() -> CanvasItemMaterial:
	if _add_mat == null:
		_add_mat = CanvasItemMaterial.new()
		_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add_mat


static func _world(parent: Node):
	return FxWorld.ensure(parent)


## A flash of light: additive glow that blooms out and fades. On High a real
## light from the Atmosphere pool comes with big ones so nearby terrain lights up.
static func flash(parent: Node, at: Vector2, col: Color, radius: float, life: float, real_light := false) -> void:
	if parent == null or not on(MEDIUM):
		return
	var w = _world(parent)
	if w == null:
		return
	w.glow(at, col, radius, life)
	if real_light and on(HIGH):
		Atmosphere.light_any(at, col, radius, life * 1.6, 1.6)


## Muzzle flash. `dir` (aim) adds a directional flash star + sparks.
static func muzzle(parent: Node, at: Vector2, explosive := false, dir := Vector2.ZERO) -> void:
	# Cinematic + High: muzzle flashes light the walls and soldiers around them
	# (pooled lights, scripts/gfx/atmosphere.gd).
	Atmosphere.light(at, Color(1.0, 0.72, 0.38), 120.0 if explosive else 70.0, 0.07 if not explosive else 0.12, 0.9)
	if explosive:
		flash(parent, at, Color(1.0, 0.6, 0.25), 70.0, 0.12)
	else:
		flash(parent, at, Color(1.0, 0.78, 0.4), 46.0, 0.06)
	if parent == null or not on(MEDIUM) or dir == Vector2.ZERO:
		return
	var w = _world(parent)
	if w != null:
		w.muzzle_star(at, dir.normalized(), explosive)


static func explosion(parent: Node, at: Vector2, radius: float) -> void:
	if parent == null:
		return
	Atmosphere.kick_impact(at, clampf(radius / 90.0, 0.3, 1.0))
	ScreenFeel.explosion(at, radius)
	flash(parent, at, Color(1.0, 0.55, 0.2), radius * 2.2, 0.4, true)
	flash(parent, at, Color(1.0, 0.9, 0.6), radius * 0.9, 0.12)
	if not on(MEDIUM):
		return
	var w = _world(parent)
	if w != null:
		w.explosion(at, radius)


static func smoke(parent: Node, at: Vector2, vel: Vector2, size: float, life: float, col := Color(0.6, 0.6, 0.6, 0.4)) -> void:
	if parent == null or not on(MEDIUM):
		return
	var w = _world(parent)
	if w != null:
		w.smoke(at, vel, size, life, col)


## Brass flying out of the gun (dir = +1 / -1 soldier facing).
static func casing(parent: Node, at: Vector2, facing: float, shell := false) -> void:
	if parent == null or not on(MEDIUM):
		return
	var w = _world(parent)
	if w != null:
		w.casing(at, facing, shell)


static func dust(parent: Node, at: Vector2, strength := 1.0) -> void:
	if parent == null or not on(MEDIUM):
		return
	var w = _world(parent)
	if w != null:
		w.dust(at, strength)


## Dark blast mark left on the ground for a while (a decal in the pool).
static func scorch(parent: Node, at: Vector2, radius: float) -> void:
	if parent == null or not on(MEDIUM):
		return
	var w = _world(parent)
	if w != null:
		w.scorch(at, radius)
