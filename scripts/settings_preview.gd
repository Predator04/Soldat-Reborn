extends VBoxContainer
## Settings live preview (graphics Phase C, #272): a small SubViewport stage
## shown beside Settings when it's opened from the main menu (in a match the
## world itself is the preview — settings already apply live there).
##
## It loops a 2.6 s skirmish built from the real pieces: the cinematic sky
## shader + parallax ridges (or the brighter classic look), two soldiers drawn
## by soldier_art.gd, a burst with tracers + muzzle flash, hits with a blood
## burst (Blood / Gore slider; none at 0), damage numbers, the kill hit-stop
## (Hit-stop toggle), screen shake (Screen Shake slider), the post grade
## (post_cinematic.gdshader, cinematic vs classic) and the enemy in the
## colour-blind team colour. Graphics quality Low drops the shader sky, the
## grade and most particles, like the game does. Every value is read each
## frame, so a change shows on the next frame.
##
## Cost: one 336×189 viewport, alive only while Settings is open (settings_panel
## frees it on hide). Cosmetic only — own RandomNumberGenerator.

const SKY_SHADER = preload("res://scripts/gfx/sky_cinematic.gdshader")
const POST_SHADER = preload("res://scripts/gfx/post_cinematic.gdshader")
const ParallaxCinematic = preload("res://scripts/gfx/parallax_cinematic.gd")
const SoldierArt = preload("res://scripts/soldier_art.gd")
const TeamColors = preload("res://scripts/team_colors.gd")
const PlayerScript = preload("res://scripts/player.gd")
const VIEW := Vector2i(336, 189)
const LOOP := 2.6

var viewport: SubViewport = null
var _stage: Node2D = null
var _caption: Label = null


class Stage extends Node2D:
	const UITheme = preload("res://scripts/ui_theme.gd")
	var t := 0.0
	var freeze := 0.0
	var shake := 0.0
	var rng := RandomNumberGenerator.new()
	var drops: Array = []        # [pos, vel, life]
	var pops: Array = []         # [pos, text, life]
	var hits_done := 0
	var sky: ColorRect
	var sky_mat: ShaderMaterial
	var ridges: Node2D
	var post: ColorRect
	var post_mat: ShaderMaterial
	var you: Node2D
	var foe: Node2D
	var fx: Node2D
	var center := Vector2(300, -200)

	func _ready() -> void:
		rng.seed = 272

	func cinematic() -> bool:
		return str(Settings.visual_style) == "cinematic" and int(Settings.gfx_quality) > 0

	func _process(delta: float) -> void:
		var calm: bool = bool(Settings.reduce_motion)
		if freeze > 0.0:
			freeze -= delta
		else:
			t = fmod(t + delta, LOOP)
			if t < delta:
				hits_done = 0
				foe.set("dead", false)
		if not calm:
			center.x += 14.0 * delta
		# Hits at 0.55 / 0.85 / 1.15 s; the third one kills.
		var marks := [0.55, 0.85, 1.15]
		while hits_done < marks.size() and t >= float(marks[hits_done]):
			_hit(hits_done == marks.size() - 1)
			hits_done += 1
		for d in drops:
			d[2] -= delta
			d[1].y += 420.0 * delta
			d[0] += d[1] * delta
		drops = drops.filter(func(d) -> bool: return float(d[2]) > 0.0 and d[0].y < float(VIEW.y) - 30.0)
		for p in pops:
			p[2] -= delta
			p[0].y -= 22.0 * delta
		pops = pops.filter(func(p) -> bool: return float(p[2]) > 0.0)
		shake = maxf(0.0, shake - delta * 3.5)
		var amp := shake * shake * 7.0 * float(Settings.screen_shake_intensity)
		position = Vector2(rng.randf_range(-amp, amp), rng.randf_range(-amp, amp)) if amp > 0.05 else Vector2.ZERO
		# Look follows the settings every frame.
		var cine := cinematic()
		sky.visible = int(Settings.gfx_quality) > 0
		sky_mat.set_shader_parameter("time", t + center.x * 0.01)
		sky_mat.set_shader_parameter("cam", center)
		if cine:
			sky_mat.set_shader_parameter("top_col", Vector3(0.02, 0.03, 0.07))
			sky_mat.set_shader_parameter("mid_col", Vector3(0.07, 0.09, 0.18))
			sky_mat.set_shader_parameter("bot_col", Vector3(0.34, 0.18, 0.12))
			sky_mat.set_shader_parameter("night", 1.0)
		else:
			sky_mat.set_shader_parameter("top_col", Vector3(0.28, 0.45, 0.72))
			sky_mat.set_shader_parameter("mid_col", Vector3(0.48, 0.64, 0.84))
			sky_mat.set_shader_parameter("bot_col", Vector3(0.78, 0.82, 0.86))
			sky_mat.set_shader_parameter("night", 0.0)
		ridges.set("center_override", center)
		ridges.set("horizon", Color(0.30, 0.16, 0.13) if cine else Color(0.55, 0.62, 0.68))
		ridges.set("near", Color(0.015, 0.02, 0.03) if cine else Color(0.22, 0.30, 0.22))
		ridges.set("rim_amount", 0.45 if cine else 0.0)
		ridges.queue_redraw()
		post.visible = int(Settings.gfx_quality) > 0
		post_mat.set_shader_parameter("cinematic", 1.0 if cine else 0.0)
		post_mat.set_shader_parameter("vignette", 0.42 if cine else 0.28)
		post_mat.set_shader_parameter("time", t)
		post_mat.set_shader_parameter("impact", clampf(shake, 0.0, 1.0) * 0.6 if bool(Settings.impact_aberration) else 0.0)
		you.queue_redraw()
		foe.queue_redraw()
		fx.queue_redraw()

	func _hit(kill: bool) -> void:
		var blood: float = float(Settings.blood_intensity)
		var hi := int(Settings.gfx_quality)
		var n := int(round((6 if hi == 0 else 18 if hi == 1 else 30) * blood * (2.0 if kill else 1.0)))
		var at: Vector2 = foe.position + Vector2(0, -16)
		for i in n:
			var a := rng.randf_range(-PI * 0.9, -PI * 0.1)
			drops.append([at, Vector2(cos(a), sin(a)) * rng.randf_range(40.0, 150.0) + Vector2(30, 0), rng.randf_range(0.4, 0.9)])
		if bool(Settings.damage_numbers):
			pops.append([at + Vector2(rng.randf_range(-6, 6), -10), "-%d" % (34 if not kill else 52), 0.7])
		shake = minf(1.0, shake + (0.55 if kill else 0.25))
		if kill:
			foe.set("dead", true)
			if bool(Settings.hit_stop) and float(Settings.screen_shake_intensity) > 0.01 and hi > 0:
				freeze = 0.08


class Puppet extends Node2D:
	const SoldierArt = preload("res://scripts/soldier_art.gd")
	const PlayerScript = preload("res://scripts/player.gd")
	var stage: Node2D
	var team := 1
	var facing := 1.0
	var dead := false
	var ds := SoldierDrawState.new()

	func _draw() -> void:
		var t: float = stage.get("t")
		ds.body_color = TeamColors.blue() if team == 1 else TeamColors.red()
		ds.team = team
		ds.facing = facing
		ds.aim_dir = Vector2(facing, -0.04).normalized()
		ds.vel = Vector2.ZERO
		ds.jet_on = team == 1 and t > 1.6
		ds.dead = dead
		ds.weapon_color = Color.WHITE
		ds.weapon_kind = "bullet"
		ds.weapon_name = "AK-74"
		var firing: bool = team == 1 and t > 0.4 and t < 1.2
		ds.muzzle_t = 0.05 if firing and fmod(t, 0.15) < 0.06 else 0.0
		ds.health = 100.0
		ds.show_hp = false
		ds.on_floor = true
		ds.cosmetics = PlayerScript.my_cosmetics() if team == 1 else {}
		ds.back_weapon_name = "USSOCOM"
		ds.grenade_count = 2
		SoldierArt.draw_soldier(self, ds)


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	add_child(UITheme.make_section_header("Live preview"))
	var frame := PanelContainer.new()
	var fs := UITheme.panel_style(Color(0, 0, 0, 0.6), UITheme.COL_BORDER_HI, UITheme.RADIUS)
	fs.content_margin_left = 2
	fs.content_margin_right = 2
	fs.content_margin_top = 2
	fs.content_margin_bottom = 2
	fs.shadow_size = 0
	frame.add_theme_stylebox_override("panel", fs)
	add_child(frame)
	var svc := SubViewportContainer.new()
	svc.name = "PreviewView"
	svc.stretch = true
	svc.custom_minimum_size = Vector2(VIEW)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(svc)
	viewport = SubViewport.new()
	viewport.size = VIEW
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport.handle_input_locally = false
	viewport.gui_disable_input = true
	svc.add_child(viewport)
	_build_stage()
	_caption = Label.new()
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.custom_minimum_size = Vector2(VIEW.x, 0)
	UITheme.style_body(_caption, 12, UITheme.COL_TEXT_DIM)
	add_child(_caption)


func _build_stage() -> void:
	var st := Stage.new()
	_stage = st
	st.name = "Stage"
	viewport.add_child(st)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.06)
	bg.position = Vector2(-16, -16)
	bg.size = Vector2(VIEW) + Vector2(32, 32)
	st.add_child(bg)
	st.sky = ColorRect.new()
	st.sky.position = Vector2(-16, -16)
	st.sky.size = Vector2(VIEW) + Vector2(32, 32)
	st.sky_mat = ShaderMaterial.new()
	st.sky_mat.shader = SKY_SHADER
	st.sky_mat.set_shader_parameter("view", Vector2(VIEW))
	st.sky_mat.set_shader_parameter("moon_pos", Vector2(0.78, 0.22))
	st.sky_mat.set_shader_parameter("cloud_amount", 0.5)
	st.sky.material = st.sky_mat
	st.add_child(st.sky)
	st.ridges = ParallaxCinematic.new()
	st.add_child(st.ridges)
	st.ridges.set_process(false)
	var ground := Polygon2D.new()
	var gy := float(VIEW.y) - 34.0
	ground.polygon = PackedVector2Array([Vector2(-20, gy), Vector2(120, gy - 4), Vector2(230, gy + 2), Vector2(VIEW.x + 20, gy - 3),
			Vector2(VIEW.x + 20, VIEW.y + 20), Vector2(-20, VIEW.y + 20)])
	ground.color = Color(0.16, 0.15, 0.14)
	st.add_child(ground)
	var edge := Line2D.new()
	edge.points = PackedVector2Array([Vector2(-20, gy), Vector2(120, gy - 4), Vector2(230, gy + 2), Vector2(VIEW.x + 20, gy - 3)])
	edge.width = 2.0
	edge.default_color = Color(0.42, 0.40, 0.34)
	st.add_child(edge)
	st.you = Puppet.new()
	st.you.stage = st
	st.you.team = 1
	st.you.facing = 1.0
	st.you.position = Vector2(92, gy - 2)
	st.you.scale = Vector2(2.4, 2.4)
	st.add_child(st.you)
	st.foe = Puppet.new()
	st.foe.stage = st
	st.foe.team = 2
	st.foe.facing = -1.0
	st.foe.position = Vector2(250, gy + 1)
	st.foe.scale = Vector2(2.4, 2.4)
	st.add_child(st.foe)
	st.fx = Node2D.new()
	st.fx.draw.connect(_draw_fx)
	st.add_child(st.fx)
	st.post = ColorRect.new()
	st.post.size = Vector2(VIEW) + Vector2(24, 24)
	st.post.position = Vector2(-12, -12)
	st.post_mat = ShaderMaterial.new()
	st.post_mat.shader = POST_SHADER
	st.post_mat.set_shader_parameter("grain", 0.03)
	st.post.material = st.post_mat
	st.add_child(st.post)


func _draw_fx() -> void:
	var st := _stage as Stage
	var f: Node2D = st.fx
	var t: float = st.t
	# Tracers during the burst.
	if t > 0.4 and t < 1.2:
		var ph := fmod(t, 0.15) / 0.15
		var from: Vector2 = st.you.position + Vector2(34, -30)
		var to: Vector2 = st.foe.position + Vector2(-6, -30)
		var head := from.lerp(to, ph)
		f.draw_line(head - (to - from).normalized() * 26.0, head, Color(1.0, 0.85, 0.45, 0.9), 1.6)
	var hi := int(Settings.gfx_quality)
	for d in st.drops:
		var a := clampf(float(d[2]) * 2.0, 0.0, 1.0)
		f.draw_circle(d[0], 1.6 if hi > 0 else 2.2, Color(0.62, 0.03, 0.02, a))
	for p in st.pops:
		var font: Font = UITheme.font("head")
		var a2 := clampf(float(p[2]) * 2.0, 0.0, 1.0)
		f.draw_string_outline(font, p[0], str(p[1]), HORIZONTAL_ALIGNMENT_CENTER, -1, 15, 3, Color(0, 0, 0, a2))
		f.draw_string(font, p[0], str(p[1]), HORIZONTAL_ALIGNMENT_CENTER, -1, 15, Color(1.0, 0.86, 0.4, a2))


func _process(_d: float) -> void:
	if _caption == null:
		return
	var q: Array = ["Low", "Medium", "High"]
	var txt := "%s look · %s · blood %.1fx · shake %.1fx" % [str(Settings.visual_style).capitalize(),
			q[clampi(int(Settings.gfx_quality), 0, 2)], float(Settings.blood_intensity), float(Settings.screen_shake_intensity)]
	if bool(Settings.hit_stop):
		txt += " · hit-stop"
	if str(Settings.team_colors) != "classic":
		txt += " · %s teams" % ("colour-blind" if str(Settings.team_colors) == "colorblind" else "high-contrast")
	if _caption.text != txt:
		_caption.text = txt
