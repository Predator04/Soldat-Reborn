extends CanvasLayer
## Animated main-menu backdrop (graphics Phase C, #272): the Phase A cinematic
## look as a slow establishing shot behind the menus.
##
## Layers (back → front, all on this CanvasLayer under the menu UI, so the UI
## scale setting never stretches them): the cinematic shader sky (moon, stars,
## drifting fbm clouds, ember horizon), the five-layer parallax ridges with ruin
## silhouettes (parallax_cinematic.gd, fed a drifting centre instead of a
## camera), drifting embers / ash (capped, additive), a slow diagonal light
## sweep, and a vignette + top / bottom grade bands that keep text readable.
##
## Cost: two canvas items with a few dozen primitives plus the sky shader.
## Graphics quality Low keeps the old baked-photo backdrop (no shader).
## Reduce motion: the shot freezes (no drift, no embers, no sweep).
## Cosmetic only — own RandomNumberGenerator, no global RNG, no game state.

const SKY_SHADER = preload("res://scripts/gfx/sky_cinematic.gdshader")
const ParallaxCinematic = preload("res://scripts/gfx/parallax_cinematic.gd")
const EMBERS := 36
const DRIFT := 18.0      # px / s of "camera" drift

var _sky: ColorRect = null
var _sky_mat: ShaderMaterial = null
var _par: Node2D = null
var _fx: Control = null
var _t := 0.0
var _center := Vector2(400, -220)
var _rng := RandomNumberGenerator.new()
var _emb: Array = []      # [pos, vel, life, max_life, size]
var _sweep_t := 2.5
var animated := true


var _low := false
var _root: Control = null


func _ready() -> void:
	layer = -10
	_rng.seed = 272
	_build()


## (Re)build for the current graphics quality (Low = the photo backdrop).
func _build() -> void:
	if _root != null:
		_root.queue_free()
	_sky = null
	_sky_mat = null
	_par = null
	_emb.clear()
	var root := Control.new()
	_root = root
	root.name = "BackdropRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.027, 0.035, 0.05)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	var low: bool = int(Settings.gfx_quality) <= 0
	_low = low
	if low:
		_build_photo(root)
	else:
		_sky = ColorRect.new()
		_sky.name = "Sky"
		_sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sky_mat = ShaderMaterial.new()
		_sky_mat.shader = SKY_SHADER
		_sky_mat.set_shader_parameter("top_col", Vector3(0.018, 0.026, 0.062))
		_sky_mat.set_shader_parameter("mid_col", Vector3(0.06, 0.08, 0.16))
		_sky_mat.set_shader_parameter("bot_col", Vector3(0.34, 0.17, 0.11))
		_sky_mat.set_shader_parameter("night", 1.0)
		_sky_mat.set_shader_parameter("cloud_amount", 0.5)
		_sky_mat.set_shader_parameter("cloud_col", Vector3(0.48, 0.52, 0.66))
		_sky_mat.set_shader_parameter("moon_pos", Vector2(0.80, 0.22))
		_sky.material = _sky_mat
		root.add_child(_sky)
		_par = ParallaxCinematic.new()
		_par.name = "Ridges"
		_par.horizon = Color(0.30, 0.16, 0.13)
		_par.near = Color(0.012, 0.016, 0.028)
		_par.rim = Color(0.72, 0.82, 1.0)
		_par.rim_amount = 0.45
		root.add_child(_par)
	_fx = Control.new()
	_fx.name = "Embers"
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_fx.material = add
	_fx.draw.connect(_draw_fx)
	root.add_child(_fx)
	root.add_child(_grade_rect())
	for i in EMBERS:
		_emb.append(_new_ember(true))
	_apply_state()


func _build_photo(root: Control) -> void:
	# Low quality: a real in-game view (baked screenshots, assets/menu_bg)
	# behind a dark veil — no shader cost.
	var pics := []
	for i in range(1, 9):
		var pth := "res://assets/menu_bg/bg%d.jpg" % i
		if ResourceLoader.exists(pth):
			pics.append(pth)
	if pics.is_empty():
		return
	var pic := TextureRect.new()
	pic.texture = load(pics[_rng.randi() % pics.size()])
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pic.modulate = Color(0.55, 0.57, 0.66)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(pic)


func _grade_rect() -> TextureRect:
	# Vertical grade (dark top for the logo, dark bottom for the footer) times a
	# radial vignette, in one texture.
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.22, 0.62, 1.0])
	g.colors = PackedColorArray([Color(0.01, 0.014, 0.022, 0.78), Color(0.01, 0.014, 0.022, 0.12),
			Color(0.01, 0.014, 0.022, 0.18), Color(0.01, 0.014, 0.022, 0.9)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 128
	var r := TextureRect.new()
	r.name = "Grade"
	r.texture = gt
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vg := Gradient.new()
	vg.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	vg.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.12), Color(0, 0, 0, 0.62)])
	var vt := GradientTexture2D.new()
	vt.gradient = vg
	vt.fill = GradientTexture2D.FILL_RADIAL
	vt.fill_from = Vector2(0.5, 0.5)
	vt.fill_to = Vector2(1.1, 1.1)
	vt.width = 128
	vt.height = 128
	var v := TextureRect.new()
	v.name = "Vignette"
	v.texture = vt
	v.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	v.stretch_mode = TextureRect.STRETCH_SCALE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(v)
	return r


## Reduce motion / quality changed while the menu is up.
func _apply_state() -> void:
	animated = not bool(Settings.reduce_motion)
	if _fx != null:
		_fx.visible = animated
	if _par != null:
		_par.set_process(false)   # redrawn from here, only when the shot moves
		_par.center_override = _center
		_par.queue_redraw()
	if _sky_mat != null:
		_sky_mat.set_shader_parameter("time", _t)
		_sky_mat.set_shader_parameter("cam", _center)
		_sky_mat.set_shader_parameter("view", get_viewport().get_visible_rect().size)


func _new_ember(anywhere: bool) -> Array:
	var vp := get_viewport().get_visible_rect().size
	var p := Vector2(_rng.randf_range(-40.0, vp.x), vp.y + _rng.randf_range(0.0, 60.0))
	if anywhere:
		p.y = _rng.randf_range(vp.y * 0.25, vp.y)
	var life := _rng.randf_range(5.0, 11.0)
	var v := Vector2(_rng.randf_range(6.0, 26.0), -_rng.randf_range(14.0, 38.0))
	return [p, v, life * (_rng.randf() if anywhere else 1.0), life, _rng.randf_range(0.8, 2.2), _rng.randf() * TAU]


func _process(delta: float) -> void:
	if _low != (int(Settings.gfx_quality) <= 0):
		_build()
	if animated != not bool(Settings.reduce_motion):
		_apply_state()
	if not animated:
		return
	_t += delta
	_center.x += DRIFT * delta
	_center.y = -220.0 + sin(_t * 0.07) * 40.0
	if _sky_mat != null:
		_sky_mat.set_shader_parameter("time", _t)
		_sky_mat.set_shader_parameter("cam", _center)
		_sky_mat.set_shader_parameter("view", get_viewport().get_visible_rect().size)
	if _par != null:
		_par.center_override = _center
		_par.queue_redraw()
	for i in _emb.size():
		var e: Array = _emb[i]
		e[2] -= delta
		if e[2] <= 0.0:
			_emb[i] = _new_ember(false)
			continue
		e[0] += (e[1] + Vector2(sin(_t * 0.6 + e[5]) * 8.0, 0.0)) * delta
	_sweep_t -= delta
	if _sweep_t < -6.0:
		_sweep_t = _rng.randf_range(5.0, 9.0)
	_fx.queue_redraw()


func _draw_fx() -> void:
	var vp := _fx.size
	for e in _emb:
		var k: float = clampf(float(e[2]) / float(e[3]), 0.0, 1.0)
		var fade := sin(k * PI)
		var flick := 0.75 + 0.25 * sin(_t * 9.0 + float(e[5]) * 3.0)
		var a := 0.55 * fade * flick
		var col := Color(1.0, 0.55 + 0.25 * k, 0.22, a)
		var p: Vector2 = e[0]
		_fx.draw_circle(p, float(e[4]) * 2.6, Color(col, a * 0.18))
		_fx.draw_circle(p, float(e[4]), col)
	# Slow diagonal light sweep (6 s across), soft-edged.
	if _sweep_t < 0.0:
		var ph := clampf(-_sweep_t / 6.0, 0.0, 1.0)
		var w := vp.x * 0.22
		var x := lerpf(-w * 2.0, vp.x + w, ph)
		var a := 0.055 * sin(ph * PI)
		var cm := Color(0.75, 0.88, 1.0, a)
		var c0 := Color(0.75, 0.88, 1.0, 0.0)
		var sk := vp.y * 0.45
		_fx.draw_polygon(PackedVector2Array([Vector2(x, vp.y), Vector2(x + sk, 0), Vector2(x + sk + w * 0.5, 0), Vector2(x + w * 0.5, vp.y)]),
				PackedColorArray([c0, c0, cm, cm]))
		_fx.draw_polygon(PackedVector2Array([Vector2(x + w * 0.5, vp.y), Vector2(x + sk + w * 0.5, 0), Vector2(x + sk + w, 0), Vector2(x + w, vp.y)]),
				PackedColorArray([cm, cm, c0, c0]))
