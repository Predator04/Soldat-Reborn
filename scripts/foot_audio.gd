extends Node
## FootAudio (v1.18) — footsteps and landing thuds for any soldier.
## Added as a child of player.gd / bot.gd. Works from the parent's actual
## on-screen movement, so it sounds the same on host, clients and replicas.

const STEP_DIST := 44.0        # px of ground travel per footstep
const CROUCH_STEP_DIST := 58.0
const LAND_MIN_VY := 380.0     # fall speed (px/s) that earns a thud
const LAND_HARD_VY := 950.0

var _prev := Vector2.INF
var _step_acc := 0.0
var _air_t := 0.0
var _peak_vy := 0.0
var _grounded := true
var _still_frames := 0


func _physics_process(delta: float) -> void:
	var body := get_parent() as CharacterBody2D
	if body == null or delta <= 0.0:
		return
	var pos := body.global_position
	if _prev == Vector2.INF or body.get("dead") == true:
		_prev = pos
		_air_t = 0.0
		_peak_vy = 0.0
		return
	var d := pos - _prev
	_prev = pos
	# Teleports (respawn, round reset) are not footsteps.
	if d.length() > 200.0:
		return
	if Settings.sfx_volume <= 0.0:
		return
	var vy := d.y / delta
	var on_floor: bool
	if not body.multiplayer.has_multiplayer_peer() or body.is_multiplayer_authority():
		on_floor = body.is_on_floor()
	else:
		# Replica: no move_and_slide, so infer from vertical motion.
		_still_frames = _still_frames + 1 if absf(vy) < 25.0 else 0
		on_floor = _still_frames >= 3
	if not on_floor:
		_air_t += delta
		_peak_vy = maxf(_peak_vy, vy)
		_step_acc = 0.0
	else:
		if not _grounded and _air_t > 0.18 and _peak_vy > LAND_MIN_VY:
			Sfx.land(pos, _peak_vy > LAND_HARD_VY)
			_step_acc = 0.0
		_air_t = 0.0
		_peak_vy = 0.0
		var crouched: bool = body.get("crouching") == true or body.get("prone") == true
		_step_acc += absf(d.x)
		var need := CROUCH_STEP_DIST if crouched else STEP_DIST
		if _step_acc >= need:
			_step_acc -= need
			Sfx.footstep(pos, crouched)
	_grounded = on_floor
