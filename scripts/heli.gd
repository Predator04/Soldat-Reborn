extends "res://scripts/buggy.gd"
## Helicopter (#277): two seats. The PILOT flies it (W / jump / jet = collective
## up, S = down, A/D = fly sideways; gamepad left stick; touch stick) and fires a
## pair of forward rockets every 3 s (aim with the mouse within a cone around
## the nose — the helicopter turns to face the side you aim at). The DOOR GUNNER
## works the vehicle MG out of the side door with a wide arc (anything but
## straight up through the rotor).
##
## Flight is arcade and readable: the rotor spins up for ~1 s before it can lift;
## momentum and drag; the body tilts with its sideways speed; with no collective
## input it sinks gently, without a spun-up rotor it falls; an altitude ceiling
## near the top of the world; skids land on terrain and rest. Hard landings,
## hitting walls fast and rotor / tail strikes on terrain hurt it (a fast strike
## hurts a lot). Bullets do half damage, explosives 1.5x. At 0 HP it spins out
## and crashes into a wreck — the crew is ejected, or killed if the crash is
## violent.
##
## Net: the same model as buggies / tanks (buggy.gd): the pilot's peer simulates
## and streams it, the host owns damage / wrecks / respawn / seats and checks
## the stream (match_vehicles._relay_drop). Impacts are found by the simulating
## peer and reported to the host (net_vehicle_crash); the pilot's rockets go
## through net_vehicle_fire_seat, the gunner's MG through net_vehicle_fire.
## Rockets reuse rocket.gd (local_only, like tank shells).

const ROCKET_SALVO := 2
const ROCKET_CD := 3.0
const ROCKET_SPEED := 820.0
const ROCKET_DAMAGE := 85.0
const ROCKET_BLAST := 115.0
const ROCKET_CONE := 0.42          # rad either side of the nose the pilot can aim
const CLIMB := 300.0               # px/s up at full collective
const SINK := 55.0                 # px/s gentle settle with no collective input
const DESCEND := 380.0             # px/s down at full "down"
const VERT_ACCEL := 1000.0
const H_ACCEL := 560.0
const H_DRAG := 1.1                # per second, no sideways input
const H_DRAG_C := 60.0
const SKID_FRICTION := 900.0
const SPINUP := 1.0                # s from still to full rotor speed
const SPINDOWN := 3.0
const LIFT_RPM := 0.85             # rotor speed needed to lift off
const CEIL_Y := 130.0              # body can't climb above this (world top + rotor + margin)
const CEIL_SOFT := 180.0           # climb fades out over this band under the ceiling
const HARD_LAND_V := 380.0         # px/s vertical touchdown before it hurts
const LAND_DMG_PER := 0.5          # damage per px/s over that
const WALL_V := 320.0
const WALL_DMG_PER := 0.4
const ROTOR_HUB := Vector2(-2, -57)
const ROTOR_R := 62.0
const TAIL_ROOT := Vector2(-40, -34)
const TAIL_TIP := Vector2(-104, -46)
const STRIKE_DMG := 30.0
const STRIKE_FAST := 420.0
const STRIKE_CD := 0.5
const SPINOUT_MAX := 3.0           # host: a spin-out ends in a crash by then at the latest
const CRASH_VIOLENT_V := 260.0     # crash speed above which the crew dies with it
const CRUISE_ALT := 300.0          # bot pilot: height above the ground it holds
const ROOF_CLEAR := 105.0          # bot pilot: body this far under terrain overhead (hub 57 + margin)
const ROOF_LOOK := 420.0           # bot pilot: how far up it looks for a roof

var rpm := 0.0                     # 0..1 rotor speed (sim peer: gameplay; others: cosmetic)
var rocket_cd := 0.0
var rockets_fired := 0             # tests
var crashes := 0                   # impact reports applied by the host (tests)
var _rocket_aim := Vector2.RIGHT
var _rocket_n := 0
var _rocket_gate_ms := -100000     # host: last accepted rocket salvo (rate check)
var _strike_cd := 0.0
var _crash_cd := 0.0
var _spin_t := 0.0
var _spin_host_t := 0.0
var _crash_sent := false
var _x_in := 0.0
var _lift_in := 0.0
# Bot pilot.
var _bp_phase := 0
var _bp_t := 0.0
var _bp_noenemy := 0.0
var _bp_flight := 0.0
var _bp_blocked := 0.0             # bot pilot: walled in with no room to climb (s)
var _bp_backoff := 0.0             # bot pilot: backing away from such a wall (s left)
var _bp_backoff_dir := 0.0
var _bp_over_y := 0.0              # bot pilot: altitude to come back over that wall at
var _bp_over_t := 0.0
var _bp_land_here := false         # bot pilot: no way home from here, land in place
# Cosmetic.
var _rotor_ang := 0.0
var _blink_t := 0.0
var _wash_t := 0.0
var _back: Node2D = null
var _ray := PhysicsRayQueryParameters2D.new()
static var _HS: Dictionary = {}


func _init() -> void:
	kind = "heli"
	LABEL = "HELICOPTER"
	display_name = "Helicopter"
	LABEL_LIFT = 78.0
	SHAPE_R = 15.0
	SHAPE_LEN = 92.0
	MAX_HP = 420.0
	hp = MAX_HP
	MAX_SPEED = 470.0
	ACCEL = H_ACCEL
	REVERSE_SPEED = 470.0
	HOP_VEL = 0.0
	STEP_UP = 0.0
	ENTER_RADIUS = 66.0
	RUNOVER_MIN_SPEED = 99999.0
	GUN_RATE = 0.09
	GUN_DAMAGE = 12.0
	GUN_SPEED = 1450.0
	GUN_SPREAD = 0.04
	HEAT_PER_SHOT = 0.065         # ~4-5 s of continuous fire to overheat
	BULLET_ARMOR = 0.5
	EXPLOSIVE_MUL = 1.5
	EXPLODE_RADIUS = 170.0
	EXPLODE_DAMAGE = 130.0
	RESPAWN_TIME = 35.0
	SEATS = [Vector2(27, -20), Vector2(-4, -16)]
	BOT_GUN_RANGE = 1000.0
	ENGINE_PITCH = 0.5
	WRECK_WEAPON = "Heli"
	EJECT_DMG = 30.0
	RELAY_MAX_SPEED = 2000.0
	PAINT_BASE = Color(0.33, 0.36, 0.33)    # grey-green
	EXHAUST_PT = Vector2(-29, -47)
	ENGINE_PT = Vector2(-6, -48)
	HEADLIGHT_PT = Vector2(41, -14)
	HEADLIGHT_LEN = 230.0
	DUST_X = [-24.0, 24.0]
	GUN_POST = Vector2(4, -27)
	SUSP_MAX = 3.0
	SHADOW_W = 46.0
	SHADOW_REACH = 420.0


func _ready() -> void:
	super()
	floor_snap_length = 4.0
	_ray.collision_mask = 1
	_ray.exclude = [get_rid()]
	# Rotor: the jet-boot hum, pitched by rotor speed and chopped at the
	# blade-pass rate in _engine_sound (no new audio files).
	var src: AudioStream = load("res://assets/sfx/hum.wav")
	if src is AudioStreamWAV:
		var st := (src as AudioStreamWAV).duplicate() as AudioStreamWAV
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		var bps: int = (2 if st.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if st.stereo else 1)
		st.loop_begin = 0
		st.loop_end = st.data.size() / bps
		_engine.stream = st
	# The cabin interior sits behind the crew (they're drawn over it, the hull
	# in front of them): one child canvas item, created once.
	_back = Node2D.new()
	_back.name = "Cabin"
	_back.z_index = -6
	_back.show_behind_parent = true
	add_child(_back)
	_back.draw.connect(_draw_cabin)


func spinning_out() -> bool:
	return alive and hp <= 0.0


func _seat_toast(seat: int) -> Array:
	return [LABEL, "W lift · A/D fly · click rockets · F to get out" if seat == 0 else "Door gunner: aim + fire · F to get out"]


func _enter_hint() -> String:
	return "F: PILOT" if driver() == null else "F: GUNNER"


## #299: hovering / flying in place is normal — no wedge reset.
func _wedge_watch() -> bool:
	return false


## Bots only board it on the ground.
func bot_board_ok() -> bool:
	if not alive or velocity.length() > 50.0:
		return false
	# (On its skids at a ledge tip the ray under the middle can miss.)
	if is_sim() and is_on_floor():
		return true
	var gy := _ground_below(global_position + Vector2(0, -6), 60.0)
	return gy != INF and gy - global_position.y < 24.0


func _runover() -> void:
	pass


# ── Simulation ────────────────────────────────────────

func _physics_process(delta: float) -> void:
	rocket_cd = maxf(0.0, rocket_cd - delta)
	_strike_cd = maxf(0.0, _strike_cd - delta)
	_crash_cd = maxf(0.0, _crash_cd - delta)
	# Rotor speed: every peer runs the same rule (pilot aboard + flyable).
	var want := 1.0 if driver() != null and alive and not spinning_out() else 0.0
	rpm = move_toward(rpm, want, delta / (SPINUP if want > rpm else SPINDOWN))
	if not alive:
		rpm = 0.0
	super(delta)
	if spinning_out():
		_spin_t += delta
		if _is_host_side():
			_spin_host_t += delta
			if _spin_host_t >= SPINOUT_MAX:
				_host_destroy(last_hitter, last_hitter_team, true)
	else:
		_spin_t = 0.0
		_spin_host_t = 0.0
		_crash_sent = false


func _simulate(delta: float) -> void:
	var d := driver()
	var x_in := 0.0
	var lift := 0.0
	var falling := spinning_out()
	if not falling and d != null and _owner_peer(d) == _local_id() and _is_local_human(d):
		if d.get("input_locked") != true:
			var pin := _pilot_input()
			x_in = pin.x
			lift = pin.y
	elif not falling and d != null and d.get("bot_id") != null and _is_host_side():
		var bi := _bot_pilot(delta)
		x_in = bi.x
		lift = bi.y
	_x_in = x_in
	_lift_in = lift
	var on_floor := is_on_floor()
	# #259: settle after an idle respawn -> adopt the rest spot as home.
	if _adopt_settle and on_floor and velocity.length() < 8.0:
		_adopt_settle = false
		spawn_pos = global_position
	var g := GRAVITY * MatchConfig.mod_gravity()
	var flying := rpm >= LIFT_RPM and not falling and d != null
	if flying:
		var tv := SINK
		if lift > 0.05:
			tv = -CLIMB * lift
		elif lift < -0.05:
			tv = DESCEND * -lift
		var y := global_position.y
		if tv < 0.0 and y < CEIL_Y + CEIL_SOFT:
			tv *= clampf((y - CEIL_Y) / CEIL_SOFT, 0.0, 1.0)
		if y < CEIL_Y:
			tv = maxf(tv, 80.0)
		velocity.y = move_toward(velocity.y, tv, VERT_ACCEL * delta)
	else:
		# Spinning (up or down) carries part of the weight; a spin-out falls.
		var carry := 0.25 if falling else clampf(rpm / LIFT_RPM, 0.0, 1.0) * 0.55
		velocity.y = minf(velocity.y + g * (1.0 - carry) * delta, 1400.0)
	var grounded := on_floor and not (flying and lift > 0.05)
	if grounded:
		velocity.x = move_toward(velocity.x, 0.0, SKID_FRICTION * delta)
	elif flying:
		if absf(x_in) > 0.05:
			velocity.x = move_toward(velocity.x, x_in * MAX_SPEED, H_ACCEL * delta)
		else:
			velocity.x = move_toward(velocity.x * (1.0 - minf(1.0, H_DRAG * delta)), 0.0, H_DRAG_C * delta)
	else:
		velocity.x *= 1.0 - minf(1.0, 0.4 * delta)
	if falling:
		velocity.x += sin(_spin_t * 5.0) * 260.0 * delta
	var pre := velocity
	move_and_slide()
	_impacts(pre, on_floor)
	_rotor_strike(pre)
	if global_position.y < CEIL_Y - 40.0:
		global_position.y = CEIL_Y - 40.0
		velocity.y = maxf(velocity.y, 0.0)
	# Visual tilt: nose down into the direction of travel; resting on the
	# ground it follows the slope; a spin-out whirls.
	var target_tilt := clampf(velocity.x / MAX_SPEED, -1.0, 1.0) * 0.3
	if falling:
		_tilt = wrapf(_tilt + delta * (4.0 + _spin_t * 3.0) * face, -PI, PI)
	else:
		if is_on_floor() and not flying:
			target_tilt = get_floor_normal().angle() + PI / 2.0
		_tilt = lerp_angle(_tilt, target_tilt, clampf(delta * 5.0, 0.0, 1.0))


func _pilot_input() -> Vector2:
	var x := Input.get_axis("move_left", "move_right")
	var up := 1.0 if Input.is_action_pressed("jump") or Input.is_action_pressed("jet") else 0.0
	var dn := 1.0 if Input.is_action_pressed("crouch") else 0.0
	# Gamepad: left stick up is analog collective (down already maps to crouch).
	for dev in Input.get_connected_joypads():
		var ly := Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y)
		if ly < -0.3:
			up = maxf(up, (-ly - 0.3) / 0.7)
	return Vector2(x, up - dn)


func _ground_below(from: Vector2, depth: float) -> float:
	if not is_inside_tree():
		return INF
	_ray.from = from
	_ray.to = from + Vector2(0, depth)
	var hit := get_world_2d().direct_space_state.intersect_ray(_ray)
	return INF if hit.is_empty() else float((hit.position as Vector2).y)


func _ray_hit(a: Vector2, b: Vector2) -> Dictionary:
	if not is_inside_tree():
		return {}
	_ray.from = a
	_ray.to = b
	return get_world_2d().direct_space_state.intersect_ray(_ray)


## Body-frame point -> world (gameplay geometry, no suspension).
func _local_to_world(p: Vector2) -> Vector2:
	return global_position + Vector2(p.x * face, p.y).rotated(_tilt)


## Sim peer: hard touchdowns, wall / ceiling hits, and the crash that ends a
## spin-out.
func _impacts(pre: Vector2, was_floor: bool) -> void:
	var hit := is_on_floor() or is_on_wall() or is_on_ceiling()
	if spinning_out():
		if hit and not _crash_sent:
			_crash_sent = true
			_report_crash(0.0, pre.length(), true)
		return
	if _crash_cd > 0.0:
		return
	var dmg := 0.0
	if is_on_floor() and not was_floor and pre.y > HARD_LAND_V:
		dmg += (pre.y - HARD_LAND_V) * LAND_DMG_PER
	if is_on_wall() and absf(pre.x) > WALL_V:
		dmg += (absf(pre.x) - WALL_V) * WALL_DMG_PER
	if is_on_ceiling() and -pre.y > WALL_V:
		dmg += (-pre.y - WALL_V) * WALL_DMG_PER
	if dmg > 0.5:
		_crash_cd = 0.4
		_report_crash(dmg, pre.length(), false)


## Sim peer: main / tail rotor blades against terrain.
func _rotor_strike(pre: Vector2) -> void:
	if rpm < 0.3 or _strike_cd > 0.0 or not alive:
		return
	var hub := _local_to_world(ROTOR_HUB)
	var tips := [hub + Vector2(ROTOR_R, 0).rotated(_tilt), hub + Vector2(-ROTOR_R, 0).rotated(_tilt)]
	var hit_at := Vector2.INF
	for tip: Vector2 in tips:
		var h := _ray_hit(hub, tip)
		if not h.is_empty():
			hit_at = h.position
			break
	if hit_at == Vector2.INF:
		var h2 := _ray_hit(_local_to_world(TAIL_ROOT), _local_to_world(TAIL_TIP))
		if not h2.is_empty():
			hit_at = h2.position
	if hit_at == Vector2.INF:
		return
	_strike_cd = STRIKE_CD
	var spd := pre.length()
	var dmg := STRIKE_DMG + spd * 0.12 + maxf(0.0, spd - STRIKE_FAST) * 0.6
	# Knocked away from what we hit.
	var away := (global_position + Vector2(0, -30) - hit_at).normalized()
	velocity = velocity * 0.3 + away * 220.0
	if spinning_out():
		if not _crash_sent:
			_crash_sent = true
			_report_crash(0.0, spd, true)
		return
	_report_crash(dmg, spd, false)
	var w = _fxw()
	if w != null and VArt.level() >= 1:
		w.vehicle_sparks(hit_at, away, 8)
	Sfx._play_key("ric", -4.0, Gfx.rf(0.7, 0.85), hit_at)


func _report_crash(dmg: float, speed: float, final: bool) -> void:
	if _is_host_side():
		host_crash(dmg, speed, final)
		return
	var main := get_parent()
	if main != null and main.has_method("net_vehicle_crash"):
		main.rpc_id(1, "net_vehicle_crash", vehicle_id, dmg, speed, final)


## Host: apply a reported impact (match_vehicles checked the sender).
func host_crash(dmg: float, speed: float, final: bool) -> void:
	if not alive or not _is_host_side():
		return
	crashes += 1
	if spinning_out():
		if final or dmg > 0.0:
			_host_destroy(last_hitter, last_hitter_team, speed > CRASH_VIOLENT_V or not _resting())
		return
	if dmg > 0.0:
		take_damage(dmg, "", "Crash", -1)


func _resting() -> bool:
	var gy := _ground_below(global_position + Vector2(0, -6), 40.0)
	return gy != INF and absf(velocity.y) < 60.0


func take_damage(amount: float, killer := "", weapon := "", killer_team := -1) -> void:
	if not alive or not _is_host_side() or spinning_out():
		return
	if killer_team >= 0 and killer_team == team and not MatchConfig.friendly_fire_on() and team >= 0:
		return
	if weapon != "Crash" and not (weapon in EXPLOSIVE_WEAPONS):
		amount *= BULLET_ARMOR
	hp -= amount
	_idle_t = 0.0
	if killer != "":
		last_hitter = killer
		last_hitter_team = killer_team
	var main := get_parent()
	if hp <= 0.0:
		# Not a wreck yet: it spins out (every peer sees hp 0) and the crash
		# decides (host_crash / SPINOUT_MAX). Landed and still it goes at once.
		hp = 0.0
		_last_sent_hp = 0.0
		if main != null and main.has_method("vehicle_send"):
			main.vehicle_send("net_vehicle_hp", [vehicle_id, hp], true)
		if is_on_floor() and velocity.length() < 40.0 and driver() == null:
			_host_destroy(last_hitter, last_hitter_team, false)
		return
	if absf(_last_sent_hp - hp) >= MAX_HP * 0.05:
		_last_sent_hp = hp
		if main != null and main.has_method("vehicle_send"):
			main.vehicle_send("net_vehicle_hp", [vehicle_id, hp], true)


## A wreck that went up in the air (a spin-out timed out) falls to the ground
## as a husk on every peer (same start, same terrain); it can't hit anyone
## (collision_layer 0) and the respawn puts it back on its pad.
func _tick_dead(delta: float) -> void:
	if not is_on_floor() or velocity.y < 0.0:
		velocity.x *= 1.0 - minf(1.0, 0.8 * delta)
		velocity.y = minf(velocity.y + GRAVITY * MatchConfig.mod_gravity() * delta, 1400.0)
		move_and_slide()
		if is_on_floor():
			velocity = Vector2.ZERO
	super(delta)


func apply_respawn() -> void:
	super()
	rpm = 0.0
	rocket_cd = 0.0
	_spin_t = 0.0
	_spin_host_t = 0.0
	_crash_sent = false
	_bp_phase = 0
	_bp_t = 0.0


## #300: a new pilot starts a fresh flight. The bot pilot's phase
## used to reset only on a respawn, so after one bot had landed (phase 2) every
## later bot pilot found it "landing", got straight back out, and the heli sat
## on the ground until it was wrecked or idle-returned.
func set_seat(seat: int, s: Node2D) -> void:
	var fresh: bool = seat == 0 and s != null and s != seats[0]
	super(seat, s)
	if fresh:
		_bp_phase = 0
		_bp_t = 0.0
		_bp_noenemy = 0.0
		_bp_flight = 0.0
		_bp_blocked = 0.0
		_bp_backoff = 0.0
		_bp_over_t = 0.0
		_bp_land_here = false


func _eject(s: Node2D, i: int) -> void:
	# Thrown out of the door / cockpit, away from the wreck.
	var side := face * (1.0 if i == 0 else -1.0)
	s.global_position = global_position + Vector2(side * 40.0, -24.0)
	s.set("velocity", Vector2(side * 190.0, -280.0))


# ── Seats / weapons ───────────────────────────────────

func _occupant_controls(me: Node2D, my_seat: int) -> void:
	if spinning_out():
		return
	if my_seat == 1:
		aim_dir = _read_aim(me)
		if Input.is_action_pressed("fire") and fire_cd <= 0.0 and not overheated:
			_fire(me)
	elif my_seat == 0:
		_rocket_aim = _read_rocket_aim(me)
		if Input.is_action_pressed("fire") and rocket_cd <= 0.0:
			_fire_rockets(me)


## Door gun: anything but up through the rotor.
func _aim_ok(want: Vector2) -> bool:
	return want.y >= -0.5


func _read_aim(me: Node2D) -> Vector2:
	var a := _raw_aim(me, _gun_pivot())
	if a.y < -0.5:
		a = Vector2(signf(a.x) if absf(a.x) > 0.01 else face, -0.5).normalized()
	return a


func _raw_aim(me: Node2D, from: Vector2) -> Vector2:
	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down", 0.2)
	var a := aim_dir
	if stick.length() > 0.0:
		a = stick.normalized()
	elif TouchControls.instance != null and TouchControls.instance.aim_dir.length() > 0.001:
		a = TouchControls.instance.aim_dir.normalized()
	else:
		var to_m: Vector2 = me.get_global_mouse_position() - from
		if to_m.length() > 1.0:
			a = to_m.normalized()
	return a


## Pilot: aiming at the other side turns the helicopter round; rockets go
## within ROCKET_CONE of the nose.
func _read_rocket_aim(me: Node2D) -> Vector2:
	var a := _raw_aim(me, _rocket_muzzle())
	if a.x * face < -0.25:
		face = -face
	return _clamp_to_nose(a)


func _nose_dir() -> Vector2:
	return Vector2(face, 0.0).rotated(_tilt + 0.06 * face)


func _clamp_to_nose(a: Vector2) -> Vector2:
	var nose := _nose_dir()
	var ang := clampf(nose.angle_to(a), -ROCKET_CONE, ROCKET_CONE)
	return nose.rotated(ang)


func _rocket_muzzle() -> Vector2:
	return _local_to_world(Vector2(26, -11))


func _gun_pivot() -> Vector2:
	return _local_to_world(Vector2(4, -27))


func _fire_rockets(me: Node2D) -> void:
	if rocket_cd > 0.0 or me != driver():
		return
	var muzzle := _rocket_muzzle()
	var dir := _rocket_aim
	rocket_cd = ROCKET_CD
	var main := get_parent()
	if Net.is_networked() and main != null and main.has_method("vehicle_send"):
		main.vehicle_send("net_vehicle_fire_seat", [vehicle_id, 0, muzzle, dir, HostHits.game_ms()], true)
		return
	apply_fire_seat(0, muzzle, dir)


## Host rate check for a client's salvo (match_vehicles, before relaying).
## Seconds between salvos from `seat` (host checks, #266).
func seat_fire_rate(_seat: int) -> float:
	return ROCKET_CD


func fire_seat_ready(seat: int) -> bool:
	if seat != 0:
		return false
	return Time.get_ticks_msec() - _rocket_gate_ms >= int(ROCKET_CD * 800.0)


## Every peer flies its own pair of rockets (same start, same flight); like
## tank shells, damage lands only on bodies this peer owns and vehicle damage
## comes from the host's copy (rocket.gd local_only).
func apply_fire_seat(seat: int, muzzle: Vector2, dir: Vector2) -> void:
	if seat != 0:
		return
	var shooter := driver()
	if shooter == null:
		return
	_rocket_gate_ms = Time.get_ticks_msec()
	rocket_cd = ROCKET_CD
	var side := Vector2(-dir.y, dir.x)
	for i in ROCKET_SALVO:
		_rocket_n += 1
		var off := -1.0 if i == 0 else 1.0
		var r = preload("res://scenes/rocket.tscn").instantiate()
		r.name = "HeliRocket_%d_%d" % [vehicle_id, _rocket_n]
		r.local_only = true
		r.ignore_bodies = [self] + seats.filter(func(o): return is_instance_valid(o))
		r.global_position = muzzle + side * off * 3.0 + dir * 6.0
		r.direction = dir.rotated(off * 0.03)
		r.speed = ROCKET_SPEED
		r.damage = ROCKET_DAMAGE * MatchConfig.mod_damage()
		r.blast_radius = ROCKET_BLAST
		r.team = int(shooter.get("team"))
		r.killer_name = str(shooter.get("display_name"))
		r.weapon_name = "Heli"
		get_parent().add_child(r)
	rockets_fired += ROCKET_SALVO
	Gfx.muzzle(get_parent(), muzzle, true, dir)
	Sfx._play_key("law-start", -2.0, Gfx.rf(0.95, 1.08), muzzle)


func apply_fire(muzzle: Vector2, dir: Vector2) -> void:
	# The MG is the door gunner's; a pilot alone has the rockets.
	if gunner() == null:
		return
	super(muzzle, dir)


# ── Bot pilot (host / single player) ─────────────────
# Simple and robust: wait on the pad for the rotor (and a moment for a
# gunner), climb to a cruise height above the ground, hold a stand-off from
# the nearest enemy (strafing back and forth) and fire rockets when the nose
# is on it, climb over terrain ahead, go home / land when hurt, land and get
# out when there's nothing to do.

func _bot_pilot(delta: float) -> Vector2:
	var d := driver()
	_bp_t += delta
	var pos := global_position
	var t = d.get("target")
	var tv: bool = t != null and is_instance_valid(t) and t.get("dead") != true and seat_of(t) < 0
	var goal: Vector2 = d.get("_goal") if d.get("_goal") != null else Vector2.INF
	var low_hp := hp < MAX_HP * 0.35
	_bp_noenemy = 0.0 if tv else _bp_noenemy + delta
	var gy := _ground_below(pos + Vector2(0, -4), 1600.0)
	match _bp_phase:
		0:
			if low_hp:
				_bot_leave(d)
				return Vector2.ZERO
			if rpm >= LIFT_RPM and _bp_t > 1.8:
				_bp_phase = 1
				_bp_t = 0.0
				_bp_flight = 0.0
			return Vector2(0.0, 0.0)
		1:
			_bp_flight += delta
			if low_hp or _bp_flight > 90.0 or (_bp_noenemy > 14.0 and (goal == Vector2.INF or absf(goal.x - pos.x) < 300.0)):
				_bp_phase = 2
				_bp_t = 0.0
	var mw: float = float(get_parent().get("MAP_W")) if get_parent() != null and get_parent().get("MAP_W") != null else 4800.0
	var tx := pos.x
	var want_y := (gy if gy != INF else pos.y + CRUISE_ALT) - CRUISE_ALT
	var roof := _roof_above(pos)
	# #300: a target out of sight above the roof over us (it sits on top of
	# the rock we're under) can't be reached from here — hovering under the
	# ceiling for it got nowhere; carry on toward the goal instead.
	var cut_off: bool = tv and roof != -INF and goal != Vector2.INF and d.get("_target_visible") != true \
			and roof + ROOF_CLEAR > (t as Node2D).global_position.y + 20.0
	if _bp_phase == 1:
		if tv and not cut_off:
			var tp: Vector2 = (t as Node2D).global_position
			var sd := signf(pos.x - tp.x)
			if sd == 0.0:
				sd = -face
			# #300: a stand-off spot past the world side would pin
			# it against the edge (it climbs to the ceiling and hangs there):
			# take the other side.
			if tp.x + sd * 460.0 < 160.0 or tp.x + sd * 460.0 > mw - 160.0:
				sd = -sd
			# Stand off ~460 px and ~130 px above it: shallow enough for the
			# nose-mounted rockets to bear, strafing back and forth.
			tx = tp.x + sd * 460.0 + sin(_bp_t * 0.7) * 140.0
			face = -sd
			want_y = tp.y - 130.0
			if gy != INF:
				want_y = minf(want_y, gy - 110.0)
		elif goal != Vector2.INF:
			tx = goal.x
			if absf(tx - pos.x) > 60.0:
				face = signf(tx - pos.x)
	else:
		# Landing: hurt -> back toward the pad first; otherwise right here.
		if low_hp and absf(spawn_pos.x - pos.x) > 200.0 and not _bp_land_here:
			tx = spawn_pos.x
			face = signf(tx - pos.x) if absf(tx - pos.x) > 1.0 else face
		else:
			if is_on_floor() and absf(velocity.x) < 40.0:
				_bot_leave(d)
				return Vector2.ZERO
			want_y = (gy if gy != INF else pos.y) + 4.0
	tx = clampf(tx, 160.0, mw - 160.0)
	# Terrain ahead: stay well above the highest ground on the way.
	var look := clampf(velocity.x * 0.9, -420.0, 420.0) + signf(tx - pos.x) * 90.0
	var ahead := _bot_ground(Vector2(pos.x + look, maxf(CEIL_Y, pos.y - 500.0)), 2200.0)
	if ahead != INF and (_bp_phase == 1 or absf(tx - pos.x) > 120.0):
		want_y = minf(want_y, ahead - 190.0)
	want_y = maxf(want_y, CEIL_Y + 50.0)
	var x_in := clampf((tx - pos.x) / 250.0, -1.0, 1.0)
	# A wall right ahead at our height: stop and climb. #300: looked
	# for at skid, cabin and rotor height, far enough ahead to stop from the
	# current speed (470 px/s needs ~200 px), and braked against — letting go
	# of the stick only drifts to a stop and it hit the wall rotor first.
	var walled := false
	var wdir := signf(look)
	if absf(look) > 1.0:
		var reach := 150.0 + pow(maxf(0.0, velocity.x * wdir), 2.0) / (2.0 * H_ACCEL)
		for hy in [-12.0, -30.0, -57.0]:
			if not _bot_hit(pos + Vector2(0, hy), pos + Vector2(wdir * reach, hy)).is_empty():
				walled = true
				break
		if walled:
			x_in = -wdir * clampf(velocity.x * wdir / 200.0, 0.0, 1.0)
			want_y = minf(want_y, pos.y - 120.0)
	# #300: terrain overhead (caves, overhangs, shafts) caps the
	# climb so the rotor stays clear of it — it used to climb into a cave
	# ceiling chasing "above the ground ahead" and rotor-strike itself to death.
	if roof != -INF:
		want_y = maxf(want_y, roof + ROOF_CLEAR)
	# A wall ahead it can't climb over from here. Under an overhang with open
	# sky behind: back out for a moment, climb in the open and come round over
	# the top. In a cave (a roof behind too) or when that keeps failing: set
	# down and get out instead of hovering against the wall.
	# #300: limping home and walled in under a roof — it hovered there for
	# good; set down right here instead.
	if walled and want_y > pos.y - 30.0 and _bp_phase == 2:
		_bp_land_here = true
	if walled and want_y > pos.y - 30.0 and _bp_phase == 1:
		_bp_blocked += delta
		if _bp_backoff <= 0.0 and _bp_blocked > 0.6:
			var back := pos + Vector2(-wdir * 320.0, 0.0)
			if _roof_above(back) == -INF and _bot_hit(pos + Vector2(0, -30), back + Vector2(0, -30)).is_empty():
				_bp_backoff = 1.6
				_bp_backoff_dir = -wdir
				# Come back over the top: the topmost surface just ahead.
				var top := _bot_ground(Vector2(pos.x + wdir * 160.0, CEIL_Y), 6000.0)
				_bp_over_y = maxf((top if top != INF else pos.y) - 190.0, CEIL_Y + 50.0)
				_bp_over_t = 7.0
			else:
				_bp_blocked = 99.0
	else:
		_bp_blocked = maxf(0.0, _bp_blocked - delta * 0.25)
	if _bp_over_t > 0.0 and _bp_phase == 1:
		_bp_over_t -= delta
		want_y = minf(want_y, _bp_over_y)
		if roof != -INF:
			want_y = maxf(want_y, roof + ROOF_CLEAR)
		# Climb there in the open before heading back in (still under the
		# overhang: keep backing out from under it).
		if pos.y > _bp_over_y + 80.0:
			x_in = _bp_backoff_dir * 0.6 if roof != -INF else 0.0
	if _bp_backoff > 0.0 and _bp_phase == 1:
		_bp_backoff -= delta
		# Slow enough that the climb keeps up with rising ground; terrain that
		# way too: no way round from here, set down instead.
		x_in = _bp_backoff_dir * 0.6
		for hy in [-12.0, -30.0, -57.0]:
			if not _bot_hit(pos + Vector2(0, hy), pos + Vector2(_bp_backoff_dir * 170.0, hy)).is_empty():
				_bp_backoff = 0.0
				_bp_over_t = 0.0
				_bp_blocked = 99.0
				x_in = 0.0
				break
	# #300: set down under a roof too low to lift off from (want_y capped at
	# its own height): no flight from here — give up instead of idling on
	# the ground with the rotor running.
	if _bp_phase == 1 and is_on_floor() and want_y > pos.y - 25.0:
		_bp_blocked += delta * 2.0
	if _bp_blocked > 6.0 and _bp_phase == 1:
		_bp_phase = 2
		_bp_t = 0.0
		_bp_blocked = 0.0
		_bp_backoff = 0.0
		_bp_over_t = 0.0
	var lift := clampf((pos.y - want_y) / 110.0, -1.0, 1.0)
	if _bp_phase == 2 and lift < 0.0:
		lift = maxf(lift, -0.55)
	# Rockets when the nose is on the target.
	if tv and _bp_phase == 1 and rocket_cd <= 0.0 and d.get("_target_visible") == true:
		var to: Vector2 = (t as Node2D).global_position + Vector2(0, -8) - _rocket_muzzle()
		if to.length() < 1000.0 and absf(_nose_dir().angle_to(to)) < ROCKET_CONE:
			_rocket_aim = _clamp_to_nose(to.normalized())
			_fire_rockets(d)
	return Vector2(x_in, lift)


## Bot pilot: the lowest terrain over the rotor disc (rays up from just past
## either blade tip, mid-blade and the hub — a shaft narrower than the disc
## counts as a roof), -INF when the sky above is open. The rays start at skid
## height: one starting inside a roof the rotor already touches finds nothing.
func _roof_above(pos: Vector2) -> float:
	var roof := -INF
	for dx in [-ROTOR_R - 26.0, -ROTOR_R * 0.5, 0.0, ROTOR_R * 0.5, ROTOR_R + 26.0]:
		var a: Vector2 = pos + Vector2(dx, -8.0)
		var h := _bot_hit(a, a + Vector2(0.0, -ROOF_LOOK))
		if not h.is_empty():
			roof = maxf(roof, float((h.position as Vector2).y))
	return roof


## #300: bot-pilot terrain queries see everything the body collides with —
## players-only terrain (layer 3) too: on Cobra the heli hovered for good
## under a players-only slab its wall / roof rays (terrain mask 1) missed.
## Gameplay rays (rotor strikes, landing, boarding) keep mask 1.
func _bot_hit(a: Vector2, b: Vector2) -> Dictionary:
	_ray.collision_mask = collision_mask
	var h := _ray_hit(a, b)
	_ray.collision_mask = 1
	return h


func _bot_ground(from: Vector2, depth: float) -> float:
	_ray.collision_mask = collision_mask
	var g := _ground_below(from, depth)
	_ray.collision_mask = 1
	return g


func _bot_leave(d: Node) -> void:
	var main := get_parent()
	if Net.is_networked() and main != null and main.has_method("net_vehicle_seat_bot"):
		main.bcast("net_vehicle_seat_bot", [vehicle_id, 0, int(d.get("bot_id")), false], true)
	else:
		clear_seat_of(d)


# ── Presentation (#277, cosmetic only) ────────────────

func _engine_sound() -> void:
	if _engine.stream == null or Settings.sfx_volume <= 0.0:
		return
	if rpm < 0.02 or not alive:
		if _engine.playing:
			_engine.stop()
		return
	if not _engine.playing:
		_engine.play()
	var sp := clampf(velocity.length() / MAX_SPEED, 0.0, 1.0)
	_engine.pitch_scale = 0.42 + rpm * 0.45 + sp * 0.08
	# Blade-pass chop: two blades, so twice per rotor turn.
	var chop := 0.5 + 0.5 * cos(_rotor_ang * 2.0)
	_engine.volume_db = -17.0 + rpm * 7.0 - chop * 7.0 * rpm + linear_to_db(clampf(Settings.sfx_volume, 0.0001, 1.0))


func _fx_tick(delta: float) -> void:
	var dt := minf(delta, 0.05)
	_rotor_ang = fposmod(_rotor_ang + rpm * 30.0 * dt, TAU * 8.0)
	_blink_t += dt
	super(delta)
	if _back != null and _onscr:
		_back.queue_redraw()
	if not alive or VArt.level() == 0:
		return
	var w = _fxw()
	if w == null:
		return
	var r := Gfx.rng
	var lv := VArt.level()
	# Rotor wash: dust blown out along the ground under the rotor, stronger
	# the lower it hovers.
	_wash_t -= dt
	if rpm > 0.45 and _wash_t <= 0.0:
		_wash_t = 0.06 if lv >= 2 else 0.12
		var hub := _world_pt(ROTOR_HUB)
		var gy := _cosmetic_ground(hub, 300.0)
		if gy != INF:
			var k := clampf(1.0 - (gy - global_position.y) / 300.0, 0.0, 1.0) * rpm
			if k > 0.05:
				w.rotor_wash(Vector2(global_position.x, gy), k, 150.0)
	# Spin-out: trailing fire + black smoke.
	if spinning_out():
		_fx_fire_t -= dt
		if _fx_fire_t <= 0.0:
			_fx_fire_t = 0.05 if lv >= 2 else 0.1
			w.vehicle_burn(_world_pt(ENGINE_PT), 1.0)
	# Searchlight on the ground ahead (High: a real pooled light where it lands).
	if driver() != null and rpm > 0.5:
		var o := _world_pt(HEADLIGHT_PT)
		var dir := _search_dir()
		var h := _ray_hit(o, o + dir * HEADLIGHT_LEN * 1.6) if Gfx.on(Gfx.HIGH) else {}
		var at: Vector2 = h.position if not h.is_empty() else o + dir * HEADLIGHT_LEN
		Atmosphere.light_keep(get_instance_id() * 8 + 1, at, Color(0.9, 0.95, 1.0), 120.0, 0.7)
	# Nav lights blink red / green (pooled lights, High).
	if rpm > 0.1:
		var ph := fmod(_blink_t, 1.0)
		if ph < 0.12:
			Atmosphere.light_keep(get_instance_id() * 8 + 3, _world_pt(Vector2(-60, -36)), Color(1.0, 0.15, 0.1), 46.0, 0.9, 0.05)
		elif ph > 0.5 and ph < 0.62:
			Atmosphere.light_keep(get_instance_id() * 8 + 4, _world_pt(Vector2(-102, -58)), Color(0.2, 1.0, 0.35), 40.0, 0.8, 0.05)
	# Faint engine exhaust haze.
	_fx_exhaust_t -= dt
	if rpm > 0.3 and _fx_exhaust_t <= 0.0:
		_fx_exhaust_t = 0.16 if lv >= 2 else 0.3
		w.smoke(_world_pt(EXHAUST_PT), Vector2(-face * 30.0 - velocity.x * 0.2, -20.0) + Vector2(r.randf_range(-8, 8), r.randf_range(-8, 8)),
			r.randf_range(6.0, 9.0), r.randf_range(0.4, 0.7), Color(0.35, 0.35, 0.36, 0.14))


func _fx_running(w: Object, dt: float, lv: int) -> void:
	# Skids scraping along the ground kick up dust (no wheels, no headlamp here).
	var spd := absf(velocity.x)
	_fx_dust_t -= dt
	if spd > 90.0 and absf(velocity.y) < 30.0 and _fx_dust_t <= 0.0:
		var gy := _cosmetic_ground(global_position + Vector2(0, -6), 14.0)
		if gy != INF:
			_fx_dust_t = 0.08
			w.wheel_dust(Vector2(global_position.x, gy), velocity.x, clampf(spd / MAX_SPEED, 0.2, 1.0))


func _cosmetic_ground(from: Vector2, depth: float) -> float:
	# Read-only ray for effects (rotor wash, skid dust).
	return _ground_below(from, depth)


func _search_dir() -> Vector2:
	return _xf_b.basis_xform(Vector2(1.0, 0.0).rotated(0.5)).normalized()


static func _heli_shapes() -> Dictionary:
	if not _HS.is_empty():
		return _HS
	# Full fuselage outline (silhouette / rim / cabin interior).
	_HS["hull"] = VArt.pv([Vector2(-36, -15), Vector2(-38, -30), Vector2(-26, -41), Vector2(4, -44), Vector2(24, -41), Vector2(38, -32),
		Vector2(46, -22), Vector2(42, -15), Vector2(28, -11), Vector2(-22, -10)])
	# Front pieces drawn over the crew, around the door and the glass.
	_HS["rear"] = VArt.pv([Vector2(-36, -15), Vector2(-38, -30), Vector2(-26, -41), Vector2(-16, -42.4), Vector2(-16, -10.6), Vector2(-22, -10)])
	_HS["roof"] = VArt.pv([Vector2(-16, -42.4), Vector2(4, -44), Vector2(24, -41), Vector2(24, -39), Vector2(12, -40), Vector2(7, -37), Vector2(-16, -37)])
	_HS["nose"] = VArt.pv([Vector2(7, -37), Vector2(12, -40), Vector2(12, -30), Vector2(20, -26), Vector2(30, -22), Vector2(43.5, -22.6),
		Vector2(46, -22), Vector2(42, -15), Vector2(28, -11), Vector2(7, -11.4)])
	_HS["belly"] = VArt.pv([Vector2(-16, -16), Vector2(7, -16), Vector2(7, -11.4), Vector2(-16, -10.6)])
	_HS["glass"] = VArt.pv([Vector2(12, -40), Vector2(24, -39), Vector2(37, -31), Vector2(43.5, -22.6), Vector2(30, -22), Vector2(20, -26), Vector2(12, -30)])
	_HS["door"] = VArt.pv([Vector2(-16, -37), Vector2(7, -37), Vector2(7, -16), Vector2(-16, -16)])
	_HS["cowl"] = VArt.pv([Vector2(-21, -42), Vector2(-16, -51), Vector2(10, -51), Vector2(16, -43)])
	_HS["boom"] = VArt.pv([Vector2(-34, -37), Vector2(-94, -33), Vector2(-94, -30), Vector2(-34, -24)])
	_HS["fin"] = VArt.pv([Vector2(-88, -33), Vector2(-100, -58), Vector2(-104, -58), Vector2(-99, -30), Vector2(-94, -29)])
	_HS["stab"] = VArt.pv([Vector2(-78, -30), Vector2(-86, -26), Vector2(-90, -26), Vector2(-84, -31)])
	_HS["pod"] = VArt.pv([Vector2(-4, -13.5), Vector2(20, -13.5), Vector2(26, -11), Vector2(20, -8.5), Vector2(-4, -8.5)])
	_HS["stripe"] = VArt.pv([Vector2(-36, -33.5), Vector2(-92, -31.6), Vector2(-92, -30.2), Vector2(-36, -31)])
	_HS["soot"] = VArt.pv([Vector2(-34, -36.5), Vector2(-70, -34), Vector2(-70, -32), Vector2(-34, -31)])
	_HS["roofline"] = VArt.pv([Vector2(-38, -30), Vector2(-26, -41), Vector2(4, -44), Vector2(24, -41)])
	_HS["boom_stub"] = VArt.pv([Vector2(0, -16), Vector2(-34, -12), Vector2(-34, -9), Vector2(0, -6)])
	for k in ["hull", "boom", "fin", "cowl", "pod"]:
		_HS[k + "_n"] = VArt.normals(_HS[k])
	return _HS


func _draw() -> void:
	draws += 1
	_frames()
	var lv := VArt.level()
	if not alive:
		_draw_wreck(lv)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if lv == 0:
			_draw_lofi_smoke(5)
		return
	_draw_hull(lv)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_gun(lv)
	_draw_overlay()


## Cabin interior behind the crew (child canvas item, drawn under soldiers).
func _draw_cabin() -> void:
	if not alive or _back == null:
		return
	var S := _heli_shapes()
	_back.draw_set_transform_matrix(_xf_b)
	var dark := Color(0.045, 0.05, 0.055)
	_back.draw_colored_polygon(S["hull"], dark)
	# Far-side wall, seats, a hint of the gunner's bench.
	_back.draw_rect(Rect2(-14, -35, 19, 17), Color(0.07, 0.075, 0.08))
	_back.draw_line(Vector2(-14, -22), Vector2(5, -22), Color(0.12, 0.12, 0.12), 2.0)
	_back.draw_rect(Rect2(17, -33, 3, 13), Color(0.1, 0.1, 0.1))
	if VArt.level() >= 1:
		var lamp := Color(1.0, 0.25, 0.15, 0.35) if driver() != null else Color(0.3, 0.3, 0.3, 0.2)
		_back.draw_circle(Vector2(-6, -34), 1.5, lamp)


func _draw_hull(lv: int) -> void:
	var S := _heli_shapes()
	var paint := _team_color()
	var trim := VArt.trim(team, _team_mode())
	var cine := VArt.cinematic()
	var line := Color(0.02, 0.02, 0.025, 0.9)
	var steel := VArt.STEEL if cine else VArt.STEEL.lightened(0.12)
	var rt := _tilt + _pitch * face
	draw_set_transform_matrix(_xf_b)
	# Tail: boom, fin, stabiliser, tail rotor (behind the cabin).
	VArt.part(self, S["boom"], _cols("boom", S["boom"], paint.lightened(0.12), paint.darkened(0.45), -37.0, -24.0), paint, line)
	if lv >= 1:
		# Exhaust soot streaking down the boom.
		var soot := VArt.SOOT
		soot.a = 0.0
		var soot2 := VArt.SOOT
		soot2.a = 0.5 if cine else 0.35
		draw_polygon(S["soot"], PackedColorArray([soot2, soot, soot, soot2]))
	draw_colored_polygon(S["stripe"], trim.darkened(0.15) if cine else trim)
	VArt.part(self, S["fin"], _cols("fin", S["fin"], paint.lightened(0.1), paint.darkened(0.35), -58.0, -29.0), paint, line)
	VArt.part(self, S["stab"], PackedColorArray(), paint.darkened(0.2), line)
	_draw_tail_rotor(lv)
	# Skids: far one darker and offset, struts, the near tube with an upturned toe.
	var sk := Color(0.24, 0.25, 0.26) if cine else Color(0.32, 0.32, 0.31)
	VArt.tube(self, Vector2(-28, -2.0), Vector2(28, -2.0), sk.darkened(0.45), 2.0)
	VArt.tube(self, Vector2(-15, -11), Vector2(-19, -1), sk, 2.0)
	VArt.tube(self, Vector2(15, -12), Vector2(19, -1), sk, 2.0)
	VArt.tube(self, Vector2(-32, -0.8), Vector2(31, -0.8), sk, 2.4)
	VArt.tube(self, Vector2(31, -0.8), Vector2(37, -5), sk, 2.4)
	# Cabin pieces around the open door and the glass (crew shows through).
	var top := paint.lightened(0.2)
	var bot := paint.darkened(0.45)
	VArt.part(self, S["rear"], _cols("rear", S["rear"], top, bot, -42.0, -10.0), paint, Color(0, 0, 0, 0))
	VArt.part(self, S["roof"], _cols("roof", S["roof"], top.lightened(0.05), paint, -44.0, -37.0), paint, Color(0, 0, 0, 0))
	VArt.part(self, S["nose"], _cols("nose", S["nose"], top, bot, -40.0, -11.0), paint, Color(0, 0, 0, 0))
	VArt.part(self, S["belly"], _cols("belly", S["belly"], paint.darkened(0.2), bot, -16.0, -10.0), paint.darkened(0.2), Color(0, 0, 0, 0))
	if lv >= 1:
		VArt.grime(self, -36.0, 44.0, -16.0, -10.0, 0.5 if cine else 0.3)
	# Glass: tinted, the pilot visible through it, a sky reflection streak.
	var gtop := Color(0.25, 0.42, 0.5, 0.42) if cine else Color(0.4, 0.6, 0.7, 0.45)
	var gbot := Color(0.05, 0.1, 0.14, 0.62)
	if lv >= 1:
		draw_polygon(S["glass"], _cols("glass", S["glass"], gtop, gbot, -40.0, -22.0))
	else:
		draw_colored_polygon(S["glass"], Color(0.2, 0.32, 0.4, 0.55))
	if lv >= 1:
		draw_line(Vector2(17, -37.5), Vector2(33, -29), Color(1, 1, 1, 0.38), 1.6)
		draw_line(Vector2(21, -38.2), Vector2(27, -35.2), Color(1, 1, 1, 0.55), 1.0)
		if cine and driver() != null:
			draw_line(Vector2(31, -24.5), Vector2(37, -24.5), Color(VArt.NEON.r, VArt.NEON.g, VArt.NEON.b, 0.7), 1.0)
	# Frames + silhouette.
	draw_polyline(S["glass"], line, 1.2)
	draw_line(S["glass"][S["glass"].size() - 1], S["glass"][0], line, 1.2)
	draw_polyline(S["door"], line, 1.4)
	draw_line(S["door"][3], S["door"][0], line, 1.4)
	draw_polyline(S["hull"], line, 1.4)
	draw_line(S["hull"][S["hull"].size() - 1], S["hull"][0], line, 1.4)
	# Door rail + sliding door pushed back over the rear.
	if lv >= 1:
		draw_line(Vector2(-16, -38.5), Vector2(7, -38.5), Color(0.1, 0.1, 0.1), 1.0)
		draw_line(Vector2(-31, -36), Vector2(-31, -16), Color(0, 0, 0, 0.5), 1.0)
		draw_line(Vector2(-31, -36), Vector2(-17, -36), Color(0, 0, 0, 0.5), 1.0)
		for rx in range(-34, 44, 8):
			draw_circle(Vector2(rx, -13.2), 0.7, VArt.STEEL_HI)
		VArt.scorch(self, _spots, _dmg())
	VArt.mark(self, Vector2(-27.0, -26.0), team, _team_mode(), 3.8)
	# Engine cowling, intake, exhaust.
	VArt.part(self, S["cowl"], _cols("cowl", S["cowl"], steel.lightened(0.25), steel.darkened(0.2), -51.0, -42.0), steel, line)
	if lv >= 1:
		for gx in range(-12, 8, 3):
			draw_line(Vector2(gx, -49.5), Vector2(gx, -45.5), Color(0.02, 0.02, 0.02, 0.8), 1.0)
	VArt.tube(self, Vector2(-19, -46), Vector2(-29, -47), Color(0.36, 0.33, 0.3), 3.0)
	# Rocket pod on its pylon (the pilot's weapon).
	VArt.tube(self, Vector2(6, -16), Vector2(6, -13), steel, 1.6)
	VArt.part(self, S["pod"], _cols("pod", S["pod"], steel.lightened(0.3), steel.darkened(0.25), -13.5, -8.5), steel, line)
	draw_circle(Vector2(25, -11), 1.6, Color(0.02, 0.02, 0.02))
	if rocket_cd > ROCKET_CD - 0.25 and lv >= 1:
		draw_circle(Vector2(27, -11), 3.0, Color(1.0, 0.6, 0.25, (rocket_cd - (ROCKET_CD - 0.25)) * 3.0))
	# Searchlight + its beam, nav lights (blinking red / green), tail strobe.
	var on := driver() != null and rpm > 0.5
	if on:
		VArt.cone(self, HEADLIGHT_PT, Vector2(1, 0).rotated(0.5), HEADLIGHT_LEN, 0.16, Color(0.9, 0.95, 1.0, 0.13 if cine else 0.08))
	VArt.lamp(self, HEADLIGHT_PT, Color(0.92, 0.96, 1.0), 2.0, on)
	var ph := fmod(_blink_t, 1.0)
	VArt.lamp(self, Vector2(-60, -36), Color(1.0, 0.18, 0.12), 1.5, rpm > 0.1 and ph < 0.12)
	VArt.lamp(self, Vector2(-102, -58), Color(0.25, 1.0, 0.4), 1.4, rpm > 0.1 and ph > 0.5 and ph < 0.62)
	VArt.lamp(self, Vector2(-105, -36), Color(1, 1, 1), 1.2, rpm > 0.1 and fmod(_blink_t * 1.7, 1.0) < 0.05)
	# Rim on the silhouette (cinematic) / lit roof line (classic).
	if cine:
		VArt.rim(self, S["hull"], S["hull_n"], face, rt, 1.0)
		VArt.rim(self, S["boom"], S["boom_n"], face, rt, 0.8)
		VArt.rim(self, S["fin"], S["fin_n"], face, rt, 0.8)
		VArt.rim(self, S["cowl"], S["cowl_n"], face, rt, 0.7)
	elif lv >= 1:
		draw_polyline(S["roofline"], paint.lightened(0.4), 1.0)
	# Damage fire at the engine.
	var d := _dmg()
	if (d >= 0.75 or spinning_out()) and lv >= 1:
		VArt.flame(self, ENGINE_PT + Vector2(-8, 2), 8.0 + d * 8.0, _fx_time, float(vehicle_id))
	elif d >= 0.55 and lv == 0:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var t := fmod(_fx_time, 1.0)
		draw_circle(_world_pt(ENGINE_PT) - global_position + Vector2(0, -t * 30.0), 5.0 + t * 7.0, Color(0.15, 0.15, 0.15, 0.4 * (1.0 - t)))
		draw_set_transform_matrix(_xf_b)
	# Main rotor last (over everything).
	_draw_main_rotor(lv)


## Main rotor seen edge-on: mast + hub, a blurred disc that fades in with rotor
## speed, blades whose projected length swings with their angle and smear into
## motion-blur ghosts as they speed up.
func _draw_main_rotor(lv: int) -> void:
	var h := ROTOR_HUB
	draw_line(Vector2(-2, -51), h, Color(0.12, 0.12, 0.12), 3.0)
	if lv >= 1 and rpm > 0.05:
		draw_set_transform_matrix(_xf_b * Transform2D(0.0, Vector2(1.0, 0.075), 0.0, h))
		draw_circle(Vector2.ZERO, ROTOR_R, Color(0.08, 0.085, 0.09, 0.16 * rpm))
		draw_arc(Vector2.ZERO, ROTOR_R, 0.0, TAU, 24, Color(0.75, 0.8, 0.85, 0.12 * rpm), 1.2)
		draw_set_transform_matrix(_xf_b)
	var ghosts := 0 if lv == 0 else (1 + int(rpm * 3.0))
	for b in 2:
		for gi in range(ghosts, -1, -1):
			var a := _rotor_ang + b * PI - gi * 0.22 * rpm
			var tip := h + Vector2(cos(a) * ROTOR_R, sin(a) * 3.0)
			var alpha := (1.0 - rpm * 0.55) * (1.0 - float(gi) / float(ghosts + 1))
			draw_line(h, tip, Color(0.06, 0.06, 0.065, alpha), 2.6 if gi == 0 else 2.0)
	draw_circle(h, 3.2, Color(0.1, 0.1, 0.1))
	draw_circle(h + Vector2(-0.6, -0.8), 1.2, VArt.STEEL_HI)


func _draw_tail_rotor(lv: int) -> void:
	var c := Vector2(-99, -46)
	var tr := 11.0
	if lv >= 1 and rpm > 0.05:
		draw_circle(c, tr, Color(0.1, 0.1, 0.11, 0.18 * rpm))
		draw_arc(c, tr, 0.0, TAU, 14, Color(0.7, 0.75, 0.8, 0.14 * rpm), 1.0)
	var ta := _rotor_ang * 2.7
	for b in 2:
		var a := ta + b * PI
		var dv := Vector2(cos(a), sin(a)) * tr
		draw_line(c - dv * 0.1, c + dv, Color(0.07, 0.07, 0.07, 1.0 - rpm * 0.5), 1.8)
	draw_circle(c, 1.8, Color(0.15, 0.15, 0.15))


func _draw_wreck(lv: int) -> void:
	var S := _heli_shapes()
	# On its side in the dirt: charred cabin, the boom snapped and bent, rotor
	# stubs, skids crushed flat.
	draw_set_transform_matrix(_xf_w * Transform2D(-0.18, Vector2(0, 4)))
	VArt.part(self, S["hull"], _cols("husk", S["hull"], VArt.CHAR_HI, VArt.CHAR, -44.0, -10.0), VArt.CHAR, Color(0, 0, 0, 0.85), 1.4)
	draw_colored_polygon(S["glass"], Color(0.02, 0.02, 0.02, 0.9))
	VArt.part(self, S["cowl"], PackedColorArray(), VArt.CHAR.lightened(0.04), Color(0, 0, 0, 0.85))
	draw_line(Vector2(-2, -51), Vector2(-4, -58), Color(0.05, 0.05, 0.05), 3.0)
	draw_line(Vector2(-4, -58), Vector2(-26, -50), VArt.CHAR_HI, 2.4)
	draw_line(Vector2(-4, -58), Vector2(14, -64), VArt.CHAR_HI, 2.4)
	draw_set_transform_matrix(_xf_w * Transform2D(0.25, Vector2(-34, -16)))
	draw_colored_polygon(S["boom_stub"], VArt.CHAR)
	draw_set_transform_matrix(_xf_w)
	VArt.tube(self, Vector2(-30, -1.5), Vector2(28, -1.0), VArt.CHAR_HI, 2.0)
	if lv >= 1:
		VArt.scorch(self, _spots, 1.0)
		if _wreck_t < 7.0:
			var f := clampf(1.0 - _wreck_t / 7.0, 0.3, 1.0)
			VArt.flame(self, Vector2(-6, -36), 12.0 * f, _fx_time, 1.0)
			VArt.flame(self, Vector2(18, -26), 8.0 * f, _fx_time, 4.0)
			VArt.flame(self, Vector2(-30, -22), 7.0 * f, _fx_time, 8.0)


## Door gun on its pintle (world space), recoiling along the aim.
func _draw_gun(lv: int) -> void:
	var piv := _gun_pivot() - global_position
	var mount: Vector2 = _xf_b * Vector2(4, -20)
	draw_line(mount, piv, Color(0.12, 0.12, 0.12), 2.5)
	if _BARREL_TEX != null:
		var bs := _BARREL_TEX.get_size() / 3.4
		var kick := aim_dir * -_gun_kick
		draw_set_transform(piv + kick, aim_dir.angle(), Vector2(1.0, -1.0 if aim_dir.x < 0.0 else 1.0))
		var tint := Color.WHITE.lerp(Color(1.0, 0.55, 0.45), clampf(heat * 1.2 - 0.2, 0.0, 1.0)) if not overheated else Color(1, 0.5, 0.45)
		draw_texture_rect(_BARREL_TEX, Rect2(Vector2(-bs.x * 0.15, -bs.y * 0.5), bs), false, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_overlay() -> void:
	super()
	# Pilot's rocket reload strip (only while reloading).
	if rocket_cd > 0.0 and driver() != null:
		draw_rect(Rect2(-24, -LABEL_LIFT - 7.0, 48.0 * (1.0 - rocket_cd / ROCKET_CD), 3), Color(0.95, 0.8, 0.3, 0.8))
