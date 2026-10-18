class_name ScreenFeel
extends Node
## Graphics Phase B (#271): screen feel — trauma-based screen shake, hit-stop
## on your kills / heavy hits, a slow-mo LOOK on multi-kills. One per match
## (match_world.gd).
##
## PRESENTATION ONLY. Multiplayer means the host and every client simulate in
## real time, so nothing here may pause or slow the game: Engine.time_scale,
## physics, timers and the network are never touched.
##   hit-stop  holds the last rendered frame (one viewport read-back into a
##             reused ImageTexture, shown full-screen on top for 50–90 ms) while
##             the match keeps running underneath, then lets go.
##   slow-mo   a ~0.65 s post effect (post_cinematic.gdshader `punch` zoom,
##             radial time-smear, desaturation) plus an sfx duck. The world
##             still runs at full speed.
##   shake     trauma 0..1 (adds up, decays), offset = MAX × trauma² × smooth
##             noise, applied to the local player's camera only.
## Only the local player's own kills / big hits trigger hit-stop + slow-mo.
## Settings.hit_stop turns both off; the Screen Shake slider at 0 turns off
## shake AND them; Low quality has no hit-stop / slow-mo.

const Gfx = preload("res://scripts/gfx.gd")

const MAX_OFFSET := 18.0
const TRAUMA_CAP := 0.9
const TRAUMA_DECAY := 1.9
const HITSTOP_KILL := 0.07
const HITSTOP_HEAVY := 0.09
const HITSTOP_HIT := 0.05
const HITSTOP_COOLDOWN := 0.3
const SLOWMO_TIME := 0.65
const SLOWMO_COOLDOWN := 2.0
const MULTI_WINDOW := 1.6

static var current: ScreenFeel = null

var main: Node = null
var trauma := 0.0
var hold_t := 0.0
var hold_len := 0.0
var slowmo_t := 0.0
var hitstops := 0
var slowmos := 0
var captured := 0
var _t := 0.0
var _ph := PackedFloat32Array([0.0, 1.7, 3.1, 4.6])
var _hold_layer: CanvasLayer = null
var _hold: TextureRect = null
var _hold_tex: ImageTexture = null
var _hold_cd := 0.0
var _slow_cd := 0.0
var _kills: Array[float] = []
var _offset_on := false
var _want_capture := false
var _post_on := false


static func install(m: Node) -> ScreenFeel:
	var f := ScreenFeel.new()
	f.name = "ScreenFeel"
	f.main = m
	m.add_child(f)
	return f


## Old `_shake(px)` scale: 1.2 spin-up wobble … 7 getting hit. Callers fold in
## Settings.screen_shake_intensity already.
static func shake(amount: float) -> void:
	if current == null or not is_instance_valid(current) or amount <= 0.0:
		return
	var a := amount / 16.0
	current.trauma = minf(TRAUMA_CAP, maxf(current.trauma, a) + a * 0.3)


## A blast near the camera shakes it (distance falloff), on every peer — it
## is driven by the replicated explosion, never sent.
static func explosion(at: Vector2, radius: float) -> void:
	if current == null or not is_instance_valid(current):
		return
	var mag := float(Settings.screen_shake_intensity)
	if mag <= 0.001:
		return
	var cam := current.get_viewport().get_camera_2d()
	if cam == null:
		return
	var k := clampf(1.0 - cam.get_screen_center_position().distance_to(at) / 800.0, 0.0, 1.0)
	if k <= 0.0:
		return
	shake(k * clampf(radius / 90.0, 0.4, 1.6) * 8.0 * mag)


static func enabled() -> bool:
	return bool(Settings.hit_stop) and float(Settings.screen_shake_intensity) > 0.01 and Gfx.on(Gfx.MEDIUM) and not Net.is_dedicated


## The local player scored a kill (hud.gd, from the replicated kill feed).
static func local_kill(weapon := "") -> void:
	if current == null or not is_instance_valid(current) or not enabled():
		return
	var f := current
	var heavy := weapon.ends_with("(headshot)") or weapon in ["LAW", "M79", "Grenade", "Cluster", "Barrett"]
	f._begin_hold(HITSTOP_HEAVY if heavy else HITSTOP_KILL)
	var now := f._t
	f._kills.append(now)
	while not f._kills.is_empty() and now - f._kills[0] > MULTI_WINDOW:
		f._kills.pop_front()
	if f._kills.size() >= 2 and f._slow_cd <= 0.0:
		f._begin_slowmo()


## The local player took a heavy hit (hud.gd hp watch).
static func local_hit(damage: float) -> void:
	if damage < 40.0 or current == null or not is_instance_valid(current) or not enabled():
		return
	current._begin_hold(HITSTOP_HIT)


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null
	Sfx.fx_duck_db = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var r := Gfx.rng
	for i in 4:
		_ph[i] = r.randf() * TAU
	_hold_layer = CanvasLayer.new()
	_hold_layer.name = "HitStopLayer"
	_hold_layer.layer = 126
	add_child(_hold_layer)
	_hold = TextureRect.new()
	_hold.name = "HeldFrame"
	_hold.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hold.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hold.stretch_mode = TextureRect.STRETCH_SCALE
	_hold.visible = false
	_hold_layer.add_child(_hold)


func holding() -> bool:
	return hold_t > 0.0


func _begin_hold(length: float) -> void:
	if hold_t > 0.0 or _hold_cd > 0.0:
		return
	hold_len = length
	hold_t = length
	_hold_cd = HITSTOP_COOLDOWN + length
	hitstops += 1
	# The read-back happens in _process: kills arrive from inside physics
	# callbacks (bullet → take_damage → kill feed), no place for a GPU stall.
	_want_capture = DisplayServer.get_name() != "headless"


func _capture() -> void:
	_want_capture = false
	var vt := get_viewport().get_texture()
	var img: Image = vt.get_image() if vt != null else null
	if img == null or img.is_empty():
		return
	if _hold_tex == null or Vector2i(_hold_tex.get_size()) != img.get_size():
		_hold_tex = ImageTexture.create_from_image(img)
	else:
		_hold_tex.update(img)
	captured += 1
	_hold.texture = _hold_tex
	_hold.modulate = Color(1.3, 1.3, 1.3)
	_hold.visible = true


func _begin_slowmo() -> void:
	slowmo_t = SLOWMO_TIME
	_slow_cd = SLOWMO_COOLDOWN
	slowmos += 1


func _process(delta: float) -> void:
	_t += delta
	_hold_cd = maxf(0.0, _hold_cd - delta)
	_slow_cd = maxf(0.0, _slow_cd - delta)
	# Hit-stop: a held frame, a flash on its first frames, then let go.
	if _want_capture and hold_t > 0.0:
		_capture()
	if hold_t > 0.0:
		hold_t = maxf(0.0, hold_t - delta)
		var k := 1.0 - hold_t / maxf(0.001, hold_len)
		var b := 1.0 + 0.3 * maxf(0.0, 1.0 - k * 3.0)
		_hold.modulate = Color(b, b, b)
		if hold_t <= 0.0:
			_hold.visible = false
	# Shake.
	trauma = maxf(0.0, trauma - TRAUMA_DECAY * delta)
	var cam: Camera2D = null
	if main != null and is_instance_valid(main):
		var p = main.get("player")
		if p != null and is_instance_valid(p):
			cam = p.get("cam") as Camera2D
	if cam != null and is_instance_valid(cam):
		if trauma > 0.0:
			var tt := _t * 24.0
			var nx := sin(tt * 1.13 + _ph[0]) * 0.6 + sin(tt * 2.31 + _ph[1]) * 0.4
			var ny := sin(tt * 1.27 + _ph[2]) * 0.6 + sin(tt * 2.07 + _ph[3]) * 0.4
			cam.offset = Vector2(nx, ny) * MAX_OFFSET * trauma * trauma
			_offset_on = true
		elif _offset_on:
			cam.offset = Vector2.ZERO
			_offset_on = false
	# Slow-mo look.
	var e := 0.0
	if slowmo_t > 0.0:
		slowmo_t = maxf(0.0, slowmo_t - delta)
		var k2 := slowmo_t / SLOWMO_TIME
		e = minf(1.0, (1.0 - k2) * SLOWMO_TIME / 0.06) * pow(k2, 0.8)
	if e > 0.0 or _post_on:
		_set_post(e)
		_post_on = e > 0.0
		Sfx.fx_duck_db = -9.0 * e


func _set_post(e: float) -> void:
	if main == null or not is_instance_valid(main):
		return
	var hud = main.get("hud")
	if hud == null or not is_instance_valid(hud):
		return
	var fx = hud.get("post_fx")
	if fx == null or not is_instance_valid(fx):
		return
	var sm := (fx as ColorRect).material as ShaderMaterial
	if sm == null:
		return
	sm.set_shader_parameter("punch", e)
	sm.set_shader_parameter("smear", e)
	sm.set_shader_parameter("desat", e * 0.75)
