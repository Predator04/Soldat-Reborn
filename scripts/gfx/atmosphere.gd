class_name Atmosphere
extends Node
## Graphics Phase A (#270): sky, parallax, ambient light, post grade and a
## pooled set of real 2D lights. One node per match, added by main.gd.
##
## VISUALS ONLY. Nothing here reads input, touches physics bodies, game state or
## the network; it only draws, and every node it owns lives on its own canvas
## layer or is a light. Settings.visual_style picks the look:
##   cinematic — animated shader sky (map colours graded darker, moon, stars,
##               fbm clouds), five-layer parallax with fog and ruin silhouettes,
##               a soft ambient darkening of the world so lights read, and the
##               filmic split-tone post grade with grain + impact aberration.
##   classic   — the original sky.gd / parallax.gd and the original grade.
## Quality (gfx.gd): Low = classic look regardless (cheapest); Medium = no
## ambient darkening and no real lights; High = everything.

const Gfx = preload("res://scripts/gfx.gd")
const SKY_SHADER = preload("res://scripts/gfx/sky_cinematic.gdshader")
const POST_SHADER = preload("res://scripts/gfx/post_cinematic.gdshader")
const RIM_SHADER = preload("res://scripts/gfx/rim_light.gdshader")
const FLASH_SHADER = preload("res://scripts/gfx/soldier_flash.gdshader")
const ParallaxCinematic = preload("res://scripts/gfx/parallax_cinematic.gd")
const SkyClassic = preload("res://scripts/sky.gd")
const ParallaxClassic = preload("res://scripts/parallax.gd")

const LIGHT_POOL := 24   # #282: jets + rockets keep lights too
const AMBIENT_NIGHT := Color(0.84, 0.86, 0.89)
const AMBIENT_DAY := Color(0.93, 0.93, 0.94)

static var _current: Atmosphere = null
static var _impact := 0.0

var _map: Dictionary = {}
var _top := Color(0, 0, 0, 0)
var _bottom := Color(0, 0, 0, 0)
var _sky_layer: CanvasLayer
var _par_layer: CanvasLayer
var _sky_mat: ShaderMaterial
var _ambient: CanvasModulate
var _lights: Array[PointLight2D] = []
var _light_t: Array[float] = []
var _light_life: Array[float] = []
var _light_e: Array[float] = []
var _next_light := 0
var _light_owner: Array[int] = []   # light_keep key holding each slot (0 = a one-shot)
var _keep: Dictionary = {}          # light_keep key -> slot
var _time := 0.0
var _style := ""
var _rim_mat: ShaderMaterial = null
var _flash_mat: ShaderMaterial = null   # classic look: damage flash only (#271)
var _rim_t := 0.0


static func install(main: Node, map: Dictionary) -> Atmosphere:
	var a := Atmosphere.new()
	a.name = "Atmosphere"
	a._map = map
	var sky_cfg: Variant = map.get("sky", {})
	if typeof(sky_cfg) == TYPE_DICTIONARY and not (sky_cfg as Dictionary).is_empty():
		a._top = _arr_color((sky_cfg as Dictionary).get("top", []))
		a._bottom = _arr_color((sky_cfg as Dictionary).get("bottom", []))
	main.add_child(a)
	return a


## Settings changed mid-match: rebuild the look in place.
static func restyle(tree: SceneTree) -> void:
	if _current != null and is_instance_valid(_current):
		_current._build()


## A nearby explosion / big hit: brief radial colour split, scaled by distance
## from the screen centre. Safe to call from anywhere (no-op without a match).
static func kick_impact(at: Vector2, strength := 1.0) -> void:
	if _current == null or not is_instance_valid(_current) or not Settings.impact_aberration:
		return
	var cam := _current.get_viewport().get_camera_2d()
	if cam == null:
		return
	var d := cam.get_screen_center_position().distance_to(at)
	var k := clampf(1.0 - d / 900.0, 0.0, 1.0) * strength
	_impact = clampf(maxf(_impact, k), 0.0, 1.0)


## A short real light (muzzle flash, explosion) from the pool — no nodes are
## created during play. Ignored unless cinematic + High.
static func light(at: Vector2, col: Color, radius: float, life: float, energy := 1.2) -> void:
	if _current == null or not is_instance_valid(_current) or not _current._lights_on():
		return
	_current._fire_light(at, col, radius, life, energy)


## A pooled real light in either look (High only): the Phase B route for
## explosion lights, which used to create a PointLight2D node per blast in the
## classic look.
static func light_any(at: Vector2, col: Color, radius: float, life: float, energy := 1.2) -> void:
	if _current == null or not is_instance_valid(_current) or not Gfx.on(Gfx.HIGH):
		return
	_current._fire_light(at, col, radius, life, energy)


## A light a vehicle keeps on (head / search / nav / fire lights, #276): `key`
## names the owner's lamp, and while the owner keeps refreshing it every frame
## it holds on to the same pool slot instead of claiming a new one. Stop
## calling and it fades out after `hold` seconds. High only (either look).
static func light_keep(key: int, at: Vector2, col: Color, radius: float, energy := 1.0, hold := 0.12) -> void:
	if _current == null or not is_instance_valid(_current) or not Gfx.on(Gfx.HIGH):
		return
	_current._keep_light(key, at, col, radius, energy, hold)


## True when the cinematic look with real lights is running (gfx.gd routes
## its lights through the pool then).
static func pooled_lights() -> bool:
	return _current != null and is_instance_valid(_current) and _current._lights_on()


static func _arr_color(a: Variant) -> Color:
	if typeof(a) == TYPE_COLOR:
		return a
	if typeof(a) != TYPE_ARRAY or (a as Array).size() < 3:
		return Color(0, 0, 0, 0)
	var arr: Array = a
	return Color(float(arr[0]), float(arr[1]), float(arr[2]), 1.0)


func _ready() -> void:
	_current = self
	_impact = 0.0
	_build()


func _exit_tree() -> void:
	if _current == self:
		_current = null


## Release-gate only: run the cinematic paths in a headless test (shaders don't
## draw there, but every node, pool and material assignment does).
static var force_cinematic_for_tests := false


func cinematic() -> bool:
	if force_cinematic_for_tests:
		return Settings.visual_style == "cinematic"
	return Settings.visual_style == "cinematic" and Gfx.on(Gfx.MEDIUM) and DisplayServer.get_name() != "headless"


## For tests / diagnostics.
func lights_lit() -> int:
	var n := 0
	for l in _lights:
		if is_instance_valid(l) and l.enabled:
			n += 1
	return n


func style() -> String:
	return _style


func _lights_on() -> bool:
	return cinematic() and (Gfx.on(Gfx.HIGH) or force_cinematic_for_tests)


func _night() -> float:
	if _top.a <= 0.0:
		return 1.0
	return 1.0 - smoothstep(0.22, 0.42, _top.get_luminance())


func _build() -> void:
	_style = "cinematic" if cinematic() else "classic"
	for n in [_sky_layer, _par_layer, _ambient]:
		if n != null and is_instance_valid(n):
			# Detach first so the rebuilt layers get the same node names.
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.queue_free()
	_sky_layer = null
	_par_layer = null
	_ambient = null
	_sky_mat = null
	var main := get_parent()
	if main == null:
		return
	_sky_layer = CanvasLayer.new()
	_sky_layer.layer = -20
	_sky_layer.name = "SkyLayer"
	_par_layer = CanvasLayer.new()
	_par_layer.layer = -15
	_par_layer.name = "ParallaxLayer"
	if _style == "cinematic":
		_build_cinematic_sky()
	else:
		_build_classic_sky()
	main.add_child(_sky_layer)
	main.add_child(_par_layer)
	if _style == "cinematic" and Gfx.on(Gfx.HIGH):
		_ambient = CanvasModulate.new()
		_ambient.name = "Ambient"
		_ambient.color = AMBIENT_DAY.lerp(AMBIENT_NIGHT, _night())
		main.add_child(_ambient)
	_ensure_lights(main)
	_apply_post()
	_apply_rim()


func _graded(c: Color, amount: float, keep_hue := 0.85) -> Color:
	# Darker and slightly cooler, but the map keeps its own hue (an orange
	# desert dusk stays orange, a green jungle stays green).
	var g := c.darkened(amount)
	var l := g.get_luminance()
	g = Color(l, l, l).lerp(g, keep_hue)
	return Color(g.r * 0.97, g.g * 0.99, minf(1.0, g.b * 1.04))


func _build_cinematic_sky() -> void:
	var night := _night()
	var top := Color(0.025, 0.03, 0.08)
	var bottom := Color(0.30, 0.20, 0.24)
	if _top.a > 0.0:
		top = _graded(_top, 0.42, 0.85)
		bottom = _graded(_bottom, 0.22, 1.0)
	var mid := top.lerp(bottom, 0.45)
	var rect := ColorRect.new()
	rect.name = "Sky"
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = SKY_SHADER
	_sky_mat.set_shader_parameter("top_col", Vector3(top.r, top.g, top.b))
	_sky_mat.set_shader_parameter("mid_col", Vector3(mid.r, mid.g, mid.b))
	_sky_mat.set_shader_parameter("bot_col", Vector3(bottom.r, bottom.g, bottom.b))
	_sky_mat.set_shader_parameter("night", night)
	var cl := bottom.lerp(Color(0.7, 0.74, 0.85), 0.45)
	_sky_mat.set_shader_parameter("cloud_col", Vector3(cl.r, cl.g, cl.b))
	_sky_mat.set_shader_parameter("cloud_amount", 0.5 if night > 0.5 else 0.62)
	# Moon somewhere in the upper sky, stable per map.
	var seed_v := str(_map.get("name", "")).hash()
	_sky_mat.set_shader_parameter("moon_pos", Vector2(0.62 + float(absi(seed_v) % 30) / 100.0, 0.14 + float(absi(seed_v >> 5) % 10) / 100.0))
	rect.material = _sky_mat
	_sky_layer.add_child(rect)
	var par := ParallaxCinematic.new()
	par.name = "Parallax"
	par.horizon = bottom.lerp(top, 0.1).lightened(0.06)
	par.near = top.darkened(0.7)
	par.rim = Color(0.72, 0.8, 1.0) if night > 0.5 else bottom.lightened(0.5)
	par.rim_amount = 0.22 if night > 0.5 else 0.14
	par.theme = preload("res://scripts/gfx/terrain_theme.gd").theme_for(_map)   # #283
	_par_layer.add_child(par)


func _build_classic_sky() -> void:
	var sky := Node2D.new()
	sky.name = "Sky"
	sky.set_script(SkyClassic)
	if _top.a > 0.0 and _bottom.a > 0.0:
		sky.set("map_top", _top)
		sky.set("map_bottom", _bottom)
	_sky_layer.add_child(sky)
	var par := Node2D.new()
	par.name = "Parallax"
	par.set_script(ParallaxClassic)
	if _bottom.a > 0.0:
		par.set("tint", _bottom)
	_par_layer.add_child(par)


func _ensure_lights(main: Node) -> void:
	if not _lights.is_empty():
		return
	for i in LIGHT_POOL:
		var l := PointLight2D.new()
		l.name = "PoolLight%d" % i
		l.texture = Gfx.glow_tex()
		l.enabled = false
		l.shadow_enabled = false
		l.blend_mode = Light2D.BLEND_MODE_ADD
		main.add_child.call_deferred(l)
		_lights.append(l)
		_light_t.append(0.0)
		_light_life.append(0.0)
		_light_e.append(0.0)
		_light_owner.append(0)


func _fire_light(at: Vector2, col: Color, radius: float, life: float, energy: float) -> void:
	if _lights.is_empty():
		return
	var i := _next_light
	_next_light = (_next_light + 1) % _lights.size()
	_light_owner[i] = 0
	_set_light(i, at, col, radius, life, energy)


func _keep_light(key: int, at: Vector2, col: Color, radius: float, energy: float, hold: float) -> void:
	if _lights.is_empty():
		return
	var i: int = int(_keep.get(key, -1))
	if i < 0 or i >= _lights.size() or _light_owner[i] != key or _light_t[i] <= 0.0:
		i = _next_light
		_next_light = (_next_light + 1) % _lights.size()
		_keep[key] = i
	_light_owner[i] = key
	_set_light(i, at, col, radius, hold, energy)


func _set_light(i: int, at: Vector2, col: Color, radius: float, life: float, energy: float) -> void:
	var l := _lights[i]
	if not is_instance_valid(l):
		return
	l.global_position = at
	l.color = col
	l.texture_scale = radius / 40.0
	# #282: normal-mapped sprites (Operator soldiers, HD weapons / terrain) are
	# shaded by the angle to the light; a light at height 0 only grazes them.
	# Lift it with its size so faces toward it light up and the far side falls off.
	l.height = radius * 0.55
	l.energy = energy
	l.enabled = true
	_light_t[i] = life
	_light_life[i] = life
	_light_e[i] = energy


## Post shader lives on the HUD's PostFX rect (hud.gd keeps setting bloom /
## vignette / hit on it); this swaps in the cinematic shader, uniforms intact.
func _apply_post() -> void:
	var fx := _post_rect()
	if fx == null:
		return
	var sm := fx.material as ShaderMaterial
	if sm == null:
		return
	if sm.shader != POST_SHADER:
		sm.shader = POST_SHADER
	sm.set_shader_parameter("cinematic", 1.0 if _style == "cinematic" else 0.0)
	sm.set_shader_parameter("grain", 0.035 if Gfx.on(Gfx.HIGH) else 0.0)


func _apply_rim() -> void:
	var want := _style == "cinematic"
	if want and _rim_mat == null:
		_rim_mat = ShaderMaterial.new()
		_rim_mat.shader = RIM_SHADER
	if want:
		_rim_mat.set_shader_parameter("rim_strength", 0.6 if _night() > 0.5 else 0.4)
	# Classic + Medium/High: soldiers still get a (shared) material carrying the
	# Phase B damage-flash instance uniform; Low gets none.
	var flash_ok := not want and Gfx.on(Gfx.MEDIUM)
	if flash_ok and _flash_mat == null:
		_flash_mat = ShaderMaterial.new()
		_flash_mat.shader = FLASH_SHADER
	for grp in ["soldier", "vehicle"]:
		for n in get_tree().get_nodes_in_group(grp):
			var ci := n as CanvasItem
			if ci == null:
				continue
			var ours: bool = ci.material == null or ci.material == _rim_mat or (_flash_mat != null and ci.material == _flash_mat)
			if not ours:
				continue
			var target: Material = null
			if want:
				target = _rim_mat
			elif flash_ok and grp == "soldier":
				target = _flash_mat
			if ci.material != target:
				ci.material = target


func _post_rect() -> ColorRect:
	var main := get_parent()
	if main == null:
		return null
	var hud = main.get("hud")
	if hud == null or not is_instance_valid(hud):
		return null
	var fx = hud.get("post_fx")
	return fx as ColorRect if fx != null and is_instance_valid(fx) else null


func _process(delta: float) -> void:
	_time += delta
	var want := "cinematic" if cinematic() else "classic"
	if want != _style:
		_build()
	if _sky_mat != null:
		_sky_mat.set_shader_parameter("time", _time)
		var cam := get_viewport().get_camera_2d()
		if cam != null:
			_sky_mat.set_shader_parameter("cam", cam.get_screen_center_position())
		_sky_mat.set_shader_parameter("view", get_viewport().get_visible_rect().size)
	for i in _lights.size():
		if _light_t[i] <= 0.0:
			continue
		_light_t[i] -= delta
		var l := _lights[i]
		if not is_instance_valid(l):
			continue
		if _light_t[i] <= 0.0:
			l.enabled = false
		else:
			l.energy = _light_e[i] * (_light_t[i] / maxf(0.001, _light_life[i]))
	_impact = maxf(0.0, _impact - delta * 3.0)
	# Rim light on soldiers + vehicles (cinematic). New bodies spawn all match
	# long, so re-check a few times a second; assigning a shared material is free.
	_rim_t -= delta
	if _rim_t <= 0.0:
		_rim_t = 0.25
		_apply_rim()
	var fx := _post_rect()
	if fx != null:
		var sm := fx.material as ShaderMaterial
		if sm != null:
			if sm.shader != POST_SHADER:
				_apply_post()
			sm.set_shader_parameter("time", _time)
			sm.set_shader_parameter("impact", _impact)
			sm.set_shader_parameter("aberration_enabled", Settings.impact_aberration)
