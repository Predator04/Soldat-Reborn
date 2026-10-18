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
const ParallaxCinematic = preload("res://scripts/gfx/parallax_cinematic.gd")
const SkyClassic = preload("res://scripts/sky.gd")
const ParallaxClassic = preload("res://scripts/parallax.gd")

const LIGHT_POOL := 16
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
var _time := 0.0
var _style := ""


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


func cinematic() -> bool:
	return Settings.visual_style == "cinematic" and Gfx.on(Gfx.MEDIUM) and DisplayServer.get_name() != "headless"


func _lights_on() -> bool:
	return cinematic() and Gfx.on(Gfx.HIGH)


func _night() -> float:
	if _top.a <= 0.0:
		return 1.0
	return 1.0 - smoothstep(0.22, 0.42, _top.get_luminance())


func _build() -> void:
	_style = "cinematic" if cinematic() else "classic"
	for n in [_sky_layer, _par_layer, _ambient]:
		if n != null and is_instance_valid(n):
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


func _fire_light(at: Vector2, col: Color, radius: float, life: float, energy: float) -> void:
	if _lights.is_empty():
		return
	var i := _next_light
	_next_light = (_next_light + 1) % _lights.size()
	var l := _lights[i]
	if not is_instance_valid(l):
		return
	l.global_position = at
	l.color = col
	l.texture_scale = radius / 40.0
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
	var fx := _post_rect()
	if fx != null:
		var sm := fx.material as ShaderMaterial
		if sm != null:
			if sm.shader != POST_SHADER:
				_apply_post()
			sm.set_shader_parameter("time", _time)
			sm.set_shader_parameter("impact", _impact)
			sm.set_shader_parameter("aberration_enabled", Settings.impact_aberration)
