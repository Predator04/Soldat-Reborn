class_name SoldierFeel
extends RefCounted
## Graphics Phase B (#271): per-soldier animation polish, read from the draw
## state every redraw — squash-and-stretch on landings / take-offs, a
## procedural recoil kick of the body + gun on each shot, and a white damage
## flash for a couple of frames when health drops. VISUAL ONLY: it fills the
## fx_* fields of SoldierDrawState (soldier_art.gd applies them to the drawn
## sprite, never to the node, so the collision shape is untouched) and sets the
## `flash` instance uniform of the soldier's rim / flash material. Runs on
## every peer from replicated state (velocity, muzzle_t, health). Low quality:
## neutral.

const Gfx = preload("res://scripts/gfx.gd")
const RIM_SHADER = preload("res://scripts/gfx/rim_light.gdshader")
const FLASH_SHADER = preload("res://scripts/gfx/soldier_flash.gdshader")

var squash := 0.0          # >0 squashed (landing), <0 stretched (jump)
var kick := 0.0            # recoil 0..~1.4
var flash := 0.0           # seconds of damage flash left
var flashes := 0           # tests
var _sv := 0.0
var _last_us := 0
var _prev_floor := true
var _air_vy := 0.0
var _prev_hp := -1.0
var _prev_muzzle := 0.0
var _prev_roll := false
var _flash_set := false


func update(node: CanvasItem, ds: SoldierDrawState) -> void:
	var now := Time.get_ticks_usec()
	var dt := clampf(float(now - _last_us) / 1000000.0, 0.0, 0.05) if _last_us > 0 else 0.0
	_last_us = now
	if not Gfx.on(Gfx.MEDIUM) or ds.dead:
		ds.fx_scale = Vector2.ONE
		ds.fx_offset = Vector2.ZERO
		ds.fx_rot = 0.0
		ds.fx_kick = 0.0
		_prev_hp = ds.health
		_set_flash(node, 0.0)
		return
	# Landing / take-off → spring impulse.
	if not ds.on_floor:
		_air_vy = maxf(_air_vy, ds.vel.y)
	if ds.on_floor and not _prev_floor:
		if _air_vy > 240.0:
			_sv += clampf((_air_vy - 240.0) / 650.0, 0.18, 1.0) * 9.0
		_air_vy = 0.0
	elif not ds.on_floor and _prev_floor and ds.vel.y < -180.0:
		_sv -= 5.5
	_prev_floor = ds.on_floor
	# Damped spring back to rest.
	_sv += (-squash * 260.0 - _sv * 16.0) * dt
	squash = clampf(squash + _sv * dt, -0.9, 1.0)
	if absf(squash) < 0.002 and absf(_sv) < 0.02:
		squash = 0.0
		_sv = 0.0
	# Recoil: a fresh muzzle flash kicks.
	if ds.muzzle_t > _prev_muzzle + 0.01:
		kick = minf(1.4, kick + (1.4 if ds.weapon_kind == "rocket" or ds.weapon_kind == "launcher" else 0.8))
	_prev_muzzle = ds.muzzle_t
	kick *= exp(-dt * 14.0)
	if kick < 0.01:
		kick = 0.0
	ds.fx_scale = Vector2(1.0 + squash * 0.14, 1.0 - squash * 0.17)
	ds.fx_offset = -ds.aim_dir * kick * 1.3
	ds.fx_rot = -ds.facing * kick * 0.045
	ds.fx_kick = kick
	# Damage flash (~2 frames).
	if _prev_hp >= 0.0 and ds.health < _prev_hp - 0.5:
		flash = 0.04
		flashes += 1
	_prev_hp = ds.health
	flash = maxf(0.0, flash - dt)
	_set_flash(node, 1.0 if flash > 0.0 else 0.0)
	# Dodge roll kicks up dust.
	if ds.rolling and not _prev_roll and node is Node2D and (node as Node2D).get_parent() != null:
		Gfx.dust((node as Node2D).get_parent(), (node as Node2D).global_position, 0.6)
	_prev_roll = ds.rolling


func _set_flash(node: CanvasItem, v: float) -> void:
	var on := v > 0.0
	if on == _flash_set:
		return
	var sm := node.material as ShaderMaterial
	if sm == null or (sm.shader != RIM_SHADER and sm.shader != FLASH_SHADER):
		_flash_set = false
		return
	node.set_instance_shader_parameter("flash", v)
	_flash_set = on
