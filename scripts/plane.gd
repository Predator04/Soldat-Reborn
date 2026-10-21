extends "res://scripts/buggy.gd"
## Plane (#291): a single-seat fighter. Fast, and it flies like a plane, not
## like the helicopter: it can't hover or stop in mid-air. Below STALL_SPEED the
## wings stop carrying it, the nose drops and it falls until it has speed again.
## It turns by PITCHING — A / D rotate the nose (counter-clockwise / clockwise),
## or the nose follows the mouse cursor (once the mouse moves), the right stick
## or the touch aim stick — and W / S move the throttle lever up / down (it
## stays where you leave it). Loops are possible at speed. It takes off with a
## ground run (the nose can only lift above ROTATE_SPEED) or, on a spawn in open
## air, it hangs there until a pilot gets in and then launches already flying.
## Touchdowns on the wheels are fine; hard impacts hurt by impact speed (a
## nose-dive into the ground or a wall at cruise speed is fatal).
##
## Pilot weapons: a forward machine gun (fire, overheats like the vehicle MGs)
## and a bomb on the grenade key every BOMB_CD seconds (rocket.gd with gravity,
## like the tank shell: every peer flies its own copy, local_only).
##
## Shot down in the air, the pilot is thrown clear (EJECT_DMG) and the wreck
## falls; destroyed on the ground or by a crash, the pilot dies with it.
## F bails out (in the air too — the soldier keeps some of the plane's speed and
## has the jetpack). An empty plane's engine winds down and it glides / falls.
##
## Net: the same model as the other vehicles (buggy.gd): the pilot's peer
## simulates and streams it (net_vehicle_state; `aim_dir.x` carries the throttle
## for the engine look / sound on the other peers), the host owns hp / wreck /
## respawn / seats and checks the stream (match_vehicles._relay_drop). Impacts
## are found by the simulating peer and reported to the host (net_vehicle_crash
## → host_crash), the gun goes through net_vehicle_fire, the bomb through
## net_vehicle_fire_seat (host rate check fire_seat_ready). Replicas smooth the
## heading as well as the position (apply_state / _follow).

# ── Flight model ──────────────────────────────────────
const G_PLANE := 700.0             # px/s² (MatchConfig gravity mod applies)
const THRUST := 560.0              # px/s² at full throttle (less than gravity: no hanging on the engine)
const DRAG_LIN := 0.25             # per second
const DRAG_QUAD := 0.00036         # per px; level top speed ~950 px/s at full throttle
const DIVE_CAP := 1300.0           # extra drag above this (steep dives top out ~1350)
const STALL_SPEED := 300.0         # px/s: below this the wings carry nothing
const STALL_BAND := 140.0          # full lift from STALL_SPEED + STALL_BAND
const ALIGN := 5.0                 # rad/s: how fast the flight path follows the nose
const PITCH_RATE := 2.5            # rad/s at full authority
const STALL_DROP := 2.2            # rad/s the nose falls toward the ground in a stall
const THROTTLE_RATE := 1.2         # lever travel per second (W / S)
const ROTATE_SPEED := 340.0        # on the ground the nose can lift only above this
const GROUND_THRUST := 0.55        # share of the thrust on the wheels (a real take-off run)
const WHEEL_DRAG := 30.0
const WHEEL_BRAKE := 420.0         # throttle closed on the ground
const TAIL_UP := 0.3               # rad: most the nose can rise while the wheels touch
const SAFE_TOUCH := 260.0          # px/s into the ground on the wheels before it hurts
const NOSE_IN_SAFE := 110.0        # ...nose first into the ground
const WALL_SAFE := 160.0           # ...into a wall / ceiling
const CRASH_DMG_PER := 1.1         # damage per px/s over the safe speed
const LAUNCH_SPEED := 620.0        # air spawn: speed it starts flying with
const CEIL_Y := 60.0               # the engine runs out of air above this...
const CEIL_SOFT := 160.0           # ...fading over this band under it
const EDGE := 140.0                # world sides: the plane turns back (via up)
const CRUISE_ALT := 360.0          # bot pilot: height above the ground it cruises at
const MIN_CLEAR := 120.0           # bot pilot: pull up below this much clearance ahead
# ── Weapons ───────────────────────────────────────────
const BOMB_CD := 3.5
const BOMB_DAMAGE := 120.0
const BOMB_BLAST := 150.0
const BOMB_GRAV := 900.0
const NOSE_GUN := Vector2(50, 1.5)
const BOMB_PT := Vector2(-2, 11)

var throttle := 0.0                # 0..1 lever (sim peer: gameplay; others: from the stream)
var bomb_cd := 0.0
var bombs_dropped := 0             # tests
var crashes := 0                   # impact reports applied by the host (tests)
var air_spawn := false             # the spawn point is in open air (decided per respawn)
var air_parked := false            # hanging on an air spawn until a pilot gets in
var _grounded := false             # sim peer: rolling on the wheels
var _decided := false
var _bomb_gate_ms := -100000       # host: last accepted bomb (rate check)
var _bomb_n := 0
var _crash_cd := 0.0
var _turn_t := 0.0
var _turn_cd := 0.0
var _pitch_in := 0.0
var _mouse_steer := false
var _mouse_prev := Vector2.INF
var _g_prev := false
var _target_tilt := 0.0
var _tilt_rate := 0.0
var _last_rx_ms := 0
var _wedge_t := 0.0
var _cs: CollisionShape2D = null
var _ray := PhysicsRayQueryParameters2D.new()
var _hidden_crew: Node2D = null
# Bot pilot (host / single player).
var _bp_t := 0.0
var _bp_noenemy := 0.0
var _bp_nosight := 0.0             # #294: s since the pilot last had its target in sight
var _bp_crash_t: Array = []
var _bp_break := 0.0
var _bp_evade := 0.0
var _bp_evade_dir := 0.0
var _bp_climb := 0.0
var _bp_evade_side := 1.0
var _bp_evade_over := true
var _bp_bail := false
var bot_ban_t := 0.0               # host: bots leave this plane alone for a while after a failed flight
var bot_flown := 0.0               # tests: px a bot pilot flew it while airborne
var bot_claim_id := 0              # host (#294): the bot walking over to fly it (instance id)...
var bot_claim_until := 0           # ...until this msec, so two bots don't race for one plane
# #294: a plane a bot pilot left (bailed out over its goal, gave up on a
# take-off) goes home ABANDON_RETURN s after it comes to rest away from its
# spot, instead of after the full #259 idle timer.
const ABANDON_RETURN := 8.0
# #298: bot pilots with an objective goal (bot._goal_label) commit to it
# (defenders fly home and drop in too).
const OBJ_LABELS := ["flag", "return", "chase", "escort", "zone", "capture", "defend"]
const OBJ_COMMIT := 20.0          # s aloft before passing over the goal means bailing out
const OBJ_COMMIT_HARD := 35.0     # s aloft before the gun runs stop and it heads for the goal
const OBJ_BAIL_DX := 450.0        # px either side of the goal a committed pilot bails out
const OBJ_BAIL_SPEED := 720.0     # ...at up to this speed
var _bot_left := false
# Cosmetic.
var _roll := 1.0
var _gear := 1.0
var _gear_t := 0.0
var _gear_low := true
var _blink_t := 0.0
var _flame_k := 0.0
static var _PS: Dictionary = {}
static var _DBG := OS.get_environment("PLANE_DEBUG")   # 1: crash reports, 2: + bot pilot trace


func _init() -> void:
	kind = "plane"
	LABEL = "PLANE"
	display_name = "Plane"
	LABEL_LIFT = 46.0
	SHAPE_R = 13.0
	SHAPE_LEN = 96.0
	MAX_HP = 380.0
	hp = MAX_HP
	MAX_SPEED = 950.0
	ACCEL = THRUST
	REVERSE_SPEED = 0.0
	HOP_VEL = 0.0
	STEP_UP = 0.0
	GRAVITY = G_PLANE
	ENTER_RADIUS = 72.0
	RUNOVER_MIN_SPEED = 99999.0
	GUN_RATE = 0.08
	GUN_DAMAGE = 12.0
	GUN_SPEED = 1500.0
	GUN_SPREAD = 0.03
	HEAT_PER_SHOT = 0.065         # ~3 s of continuous fire to overheat
	BULLET_ARMOR = 0.6
	EXPLOSIVE_MUL = 1.4
	EXPLODE_RADIUS = 160.0
	EXPLODE_DAMAGE = 120.0
	RESPAWN_TIME = 35.0
	SEATS = [Vector2(4, 2)]
	seats = [null]
	BOT_GUN_RANGE = 950.0
	ENGINE_PITCH = 0.7
	WRECK_WEAPON = "Plane"
	EJECT_DMG = 30.0
	RELAY_MAX_SPEED = 2800.0
	FIRE_REACH = 260.0
	PAINT_BASE = Color(0.37, 0.4, 0.43)     # naval grey
	EXHAUST_PT = Vector2(-54, 0)
	ENGINE_PT = Vector2(-38, -1)
	HEADLIGHT_PT = Vector2(30, 6)
	HEADLIGHT_LEN = 200.0
	DUST_X = [-10.0, 26.0]
	GUN_POST = Vector2(40, 2)
	SUSP_MAX = 0.0
	SHADOW_W = 44.0
	SHADOW_REACH = 380.0


func _ready() -> void:
	super()
	floor_snap_length = 6.0
	floor_max_angle = deg_to_rad(46.0)
	for c in get_children():
		if c is CollisionShape2D:
			_cs = c
	if _cs != null:
		_cs.position = Vector2.ZERO
	_ray.collision_mask = 1
	_ray.exclude = [get_rid()]
	_spots = VArt.bake_spots(vehicle_id + 1, Rect2(-40, -6, 76, 11), 9)
	# Jet whine: the jet-boot hum pitched up by the throttle (no new audio files).
	var src: AudioStream = load("res://assets/sfx/hum.wav")
	if src is AudioStreamWAV:
		var st := (src as AudioStreamWAV).duplicate() as AudioStreamWAV
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		var bps: int = (2 if st.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if st.stereo else 1)
		st.loop_begin = 0
		st.loop_end = st.data.size() / bps
		_engine.stream = st


# ── Seats ─────────────────────────────────────────────

func gunner() -> Node2D:
	return null   # single seat


func _seat_toast(_seat: int) -> Array:
	return [LABEL, "W/S throttle · A/D or mouse pitch · click gun · grenade key bomb · F bail out"]


func _enter_hint() -> String:
	return "F: PILOT"


## #299: hovering / flying in place is normal — no wedge reset.
func _wedge_watch() -> bool:
	return false


## Bots only take a plane that is resting on its wheels or waiting on an air
## spawn, and leave one alone for a while after a failed flight.
func bot_board_ok() -> bool:
	if not alive or driver() != null or bot_ban_t > 0.0:
		return false
	if air_parked:
		return true
	return velocity.length() < 60.0 and _ground_below(global_position, SHAPE_R + 14.0) != INF


func set_seat(seat: int, s: Node2D) -> void:
	super(seat, s)
	if seat == 0 and is_instance_valid(s):
		_bot_left = false
		bot_claim_id = 0
		_bp_t = 0.0
		_bp_noenemy = 0.0
		_bp_nosight = 0.0
		_bp_crash_t.clear()
		_bp_bail = false
		_mouse_steer = false
		_mouse_prev = Vector2.INF
		_g_prev = true
		if air_parked:
			# Every peer: the plane starts flying from its air spawn.
			air_parked = false
			_tilt = 0.0 if face > 0.0 else PI
			velocity = Vector2(face, 0.0) * LAUNCH_SPEED
			throttle = 0.8
	_sync_crew()


func clear_seat_of(s: Node2D) -> void:
	var i := seat_of(s)
	if i < 0:
		return
	seats[i] = null
	if is_instance_valid(s):
		(s as CanvasItem).visible = true
		if s.has_method("dismount_m2"):
			s.dismount_m2()
		s.set("f_prev", true)
		# Bail out above the plane (clear of the fuselage), keeping some of
		# its speed: a jump out of a fast plane still flings you.
		s.global_position = global_position + Vector2(0, -34.0)
		var keep := (velocity * 0.4).limit_length(380.0)
		s.set("velocity", keep + Vector2(0, -140.0))
	if _hidden_crew == s:
		_hidden_crew = null
	_update_team()


## The pilot sits inside the cockpit (drawn as a helmet under the glass), so
## the soldier body itself is hidden while seated. Cosmetic; every peer.
func _sync_crew() -> void:
	var d := driver()
	if _hidden_crew != null and _hidden_crew != d:
		if is_instance_valid(_hidden_crew):
			_hidden_crew.visible = true
		_hidden_crew = null
	if d != null and alive:
		if d.visible:
			d.visible = false
		_hidden_crew = d


func _eject(s: Node2D, _i: int) -> void:
	s.visible = true
	s.global_position = global_position + Vector2(0, -36.0)
	s.set("velocity", (velocity * 0.3).limit_length(300.0) + Vector2(0, -300.0))


func _runover() -> void:
	pass


func _bot_gunner(_delta: float) -> void:
	pass


# ── Simulation ────────────────────────────────────────

func _physics_process(delta: float) -> void:
	bomb_cd = maxf(0.0, bomb_cd - delta)
	_crash_cd = maxf(0.0, _crash_cd - delta)
	_turn_cd = maxf(0.0, _turn_cd - delta)
	bot_ban_t = maxf(0.0, bot_ban_t - delta)
	if not _decided and is_inside_tree():
		_decided = true
		_decide_spawn()
	super(delta)
	_sync_crew()


## Ground spawn (wheels within reach of the ground) or air spawn; which way it
## faces: along the longer runway, or toward the middle of the map in the air.
## Pure terrain queries, so every peer decides the same.
func _decide_spawn() -> void:
	var gy := _ground_below(spawn_pos + Vector2(0, -2), SHAPE_R + 40.0)
	air_spawn = gy == INF
	air_parked = air_spawn and alive and driver() == null and global_position.distance_to(spawn_pos) < 4.0
	var mid := _map_w() * 0.5
	var toward_mid := 1.0 if spawn_pos.x <= mid else -1.0
	if air_spawn:
		face = toward_mid
	else:
		var r := _runway(spawn_pos, 1.0)
		var l := _runway(spawn_pos, -1.0)
		face = toward_mid if absf(r - l) < 80.0 else (1.0 if r > l else -1.0)
	_tilt = 0.0 if face > 0.0 else PI
	_target_tilt = _tilt
	_roll = face
	_update_shape()


## Clear, roughly level ground ahead of `from` in direction `dir` (px, <= 900).
func _runway(from: Vector2, dir: float) -> float:
	var gy := _ground_below(from + Vector2(0, -4), SHAPE_R + 40.0)
	if gy == INF:
		return 0.0
	var run := 0.0
	var px := from.x
	var py := gy
	for k in 22:
		var nx := px + dir * 40.0
		if not _ray_hit(Vector2(px, py - 18.0), Vector2(nx, py - 18.0)).is_empty():
			break
		var ny := _ground_below(Vector2(nx, py - 36.0), 76.0)
		if ny == INF or absf(ny - py) > 34.0:
			break
		px = nx
		py = ny
		run += 40.0
	return run


func _map_w() -> float:
	var m := get_parent()
	return float(m.get("MAP_W")) if m != null and m.get("MAP_W") != null else 4800.0


func _update_shape() -> void:
	if _cs != null:
		_cs.rotation = _tilt + PI * 0.5


func _nose() -> Vector2:
	return Vector2.from_angle(_tilt)


## Body-frame point (nose along +x, canopy up) -> world (gameplay geometry).
func _body(p: Vector2) -> Vector2:
	return global_position + Vector2(p.x, p.y * face).rotated(_tilt)


func _seat_world(i: int) -> Vector2:
	return _body(SEATS[i])


func _gun_pivot() -> Vector2:
	return _body(Vector2(38, 2))


func stalled() -> bool:
	return alive and not air_parked and not _grounded and driver() != null and maxf(0.0, velocity.dot(_nose())) < STALL_SPEED + 30.0


func _simulate(delta: float) -> void:
	var d := driver()
	var pitch := 0.0
	var turn_req := false
	if d != null and _owner_peer(d) == _local_id() and _is_local_human(d):
		if d.get("input_locked") != true:
			var pin := _pilot_input(d, delta)
			pitch = pin.x
			turn_req = pin.y > 0.5
	elif d != null and d.get("bot_id") != null and _is_host_side():
		var bi := _bot_pilot(delta)
		pitch = bi.x
		throttle = move_toward(throttle, clampf(bi.y, 0.0, 1.0), THROTTLE_RATE * 1.5 * delta)
	if d == null:
		throttle = move_toward(throttle, 0.0, delta * 0.8)   # engine winds down
	aim_dir = Vector2(throttle, 0.0)   # streamed: engine look / sound elsewhere
	_pitch_in = pitch
	if air_parked:
		velocity = Vector2.ZERO
		_grounded = false
		_update_shape()
		return
	# #259: settle after an idle respawn -> adopt the rest spot as home.
	if _adopt_settle and _grounded and velocity.length() < 8.0:
		_adopt_settle = false
		spawn_pos = global_position
	_fly(delta, pitch, turn_req)


## The flight model (sim peer). Arcade but physical enough to loop and stall:
## gravity always; the wings cancel the part of it across the nose (in
## proportion to airspeed above the stall); the flight path turns toward the
## nose; thrust along the nose; linear + quadratic drag.
func _fly(delta: float, pitch_in: float, turn_req: bool) -> void:
	var g := G_PLANE * MatchConfig.mod_gravity()
	var spd := velocity.length()
	var pos := global_position
	var nose := _nose()
	# Airspeed over the wings = speed along the nose (a belly-first fall
	# doesn't fly).
	var fwd := maxf(0.0, velocity.dot(nose))
	var eff := clampf((fwd - STALL_SPEED) / STALL_BAND, 0.0, 1.0)
	# Less agile slow, and a stalled wing barely answers the stick.
	var auth := clampf((fwd - STALL_SPEED * 0.6) / 420.0, 0.3, 1.0) * lerpf(0.45, 1.0, eff)
	var pitch := pitch_in
	# World sides: the nose is brought round (over the top) back into the map.
	var mw := _map_w()
	if not _grounded and ((pos.x < EDGE and nose.x < 0.25) or (pos.x > mw - EDGE and nose.x > -0.25)):
		var back := 1.0 if pos.x < EDGE else -1.0
		pitch = clampf(angle_difference(_tilt, Vector2(back * 0.6, -1.0).angle()) * 3.0, -1.0, 1.0)
	if _grounded:
		var tan := _ground_tangent()
		var base := tan.angle()
		var up := -angle_difference(base, _tilt) * face      # nose-up angle above the ground
		up += -pitch * face * PITCH_RATE * delta
		up = clampf(up, 0.0, TAIL_UP if spd >= ROTATE_SPEED else 0.0)
		# Turn round on the spot: slow and pushing the nose down (or asked to).
		if spd < 50.0 and (pitch * face > 0.5 or turn_req):
			_turn_t += delta
			if _turn_t > 0.25 and _turn_cd <= 0.0:
				_turn_t = 0.0
				_turn_cd = 0.8
				face = -face
				velocity = Vector2.ZERO
				tan = _ground_tangent()
				base = tan.angle()
				up = 0.0
		else:
			_turn_t = 0.0
		_tilt = wrapf(base - up * face, -PI, PI)
	else:
		_turn_t = 0.0
		_tilt += pitch * PITCH_RATE * auth * delta
		if eff < 1.0:
			# Stall: the nose drops toward the ground.
			_tilt += clampf(angle_difference(_tilt, PI * 0.5), -1.0, 1.0) * (1.0 - eff) * STALL_DROP * delta
		_tilt = wrapf(_tilt, -PI, PI)
		var c := cos(_tilt)
		if face > 0.0 and c < -0.2:
			face = -1.0
		elif face < 0.0 and c > 0.2:
			face = 1.0
	nose = _nose()
	velocity.y += g * delta
	var perp := Vector2(-nose.y, nose.x)
	velocity -= perp * Vector2(0.0, g).dot(perp) * eff * delta
	spd = velocity.length()
	if spd > 1.0:
		var va := velocity.angle()
		var rate := ALIGN * eff * delta
		var r := clampf(angle_difference(va, _tilt), -rate, rate)
		velocity = Vector2.from_angle(va + r) * spd * (1.0 - absf(r) * 0.05)
	var thr := throttle * THRUST * (GROUND_THRUST if _grounded else 1.0)
	if pos.y < CEIL_Y + CEIL_SOFT:
		thr *= clampf((pos.y - CEIL_Y) / CEIL_SOFT, 0.0, 1.0)
	velocity += nose * thr * delta
	spd = velocity.length()
	if spd > 0.5:
		var dr := DRAG_LIN * spd + DRAG_QUAD * spd * spd + maxf(0.0, spd - DIVE_CAP) * 3.0
		velocity -= velocity / spd * minf(spd, dr * delta)
	if _grounded:
		# Wheels: roll along the ground; the brakes come on with the throttle closed.
		var tan2 := _ground_tangent()
		var n := Vector2(tan2.y, -tan2.x) * face
		var vt := velocity.dot(tan2)
		var vn := velocity.dot(n)
		vt = move_toward(vt, 0.0, (WHEEL_DRAG + (WHEEL_BRAKE if throttle < 0.05 else 0.0)) * delta)
		velocity = tan2 * vt + n * vn
	var pre := velocity
	_update_shape()
	move_and_slide()
	_contacts(pre)
	# On the floor = on the wheels (a nose-in has been reported as a crash
	# above; it then rests on the ground like any other landing).
	_grounded = is_on_floor()
	# Limits: the top of the sky, the sides of the world.
	if global_position.y < CEIL_Y - 60.0:
		global_position.y = CEIL_Y - 60.0
		velocity.y = maxf(velocity.y, 0.0)
	if global_position.x < -150.0 or global_position.x > mw + 150.0:
		global_position.x = clampf(global_position.x, -150.0, mw + 150.0)
		velocity.x = 0.0
	# Wedged (throttle open, not moving, touching something): lift it out.
	if throttle > 0.5 and spd < 15.0 and (is_on_floor() or is_on_wall()):
		_wedge_t += delta
		if _wedge_t > 2.5:
			_wedge_t = 0.0
			unstick()
	else:
		_wedge_t = maxf(0.0, _wedge_t - delta)


func _ground_tangent() -> Vector2:
	var n := get_floor_normal() if is_on_floor() else Vector2.UP
	var t := Vector2(-n.y, n.x)
	if t.x * face < 0.0:
		t = -t
	return t


## Sim peer: the hardest hit this step. Speed into the surface over the safe
## limit (lower nose-first or into a wall) hurts; a gentle one is a landing.
func _contacts(pre: Vector2) -> void:
	var worst := 0.0
	var wn := Vector2.ZERO
	var at := global_position
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		var vn := -pre.dot(n)
		if vn > worst:
			worst = vn
			wn = n
			at = c.get_position()
	if worst <= 0.0:
		return
	var floorish := wn.y < -0.6
	var safe := SAFE_TOUCH if floorish else WALL_SAFE
	if floorish and _nose().dot(wn) < -0.35:
		safe = NOSE_IN_SAFE
	elif _grounded:
		safe = SAFE_TOUCH    # rolling over a lip / bump on the runway
	var dmg := (worst - safe) * CRASH_DMG_PER
	if dmg < 4.0 or _crash_cd > 0.0:
		return
	_crash_cd = 0.35
	velocity += wn * worst * 0.35
	_report_crash(dmg, pre.length(), false)
	var w = _fxw()
	if w != null and VArt.level() >= 1:
		w.vehicle_sparks(at, wn, 8)
	Sfx._play_key("ric", -4.0, Gfx.rf(0.6, 0.75), at)


func _report_crash(dmg: float, speed: float, final: bool) -> void:
	if _is_host_side():
		host_crash(dmg, speed, final)
		return
	var main := get_parent()
	if main != null and main.has_method("net_vehicle_crash"):
		main.rpc_id(1, "net_vehicle_crash", vehicle_id, dmg, speed, final)


## Host: apply a reported impact (match_vehicles checked the sender).
func host_crash(dmg: float, _speed: float, _final: bool) -> void:
	if not alive or not _is_host_side():
		return
	crashes += 1
	if _DBG != "":
		print("PLANE crash dmg=%.0f at %s v=%s tilt=%.2f grounded=%s pilot=%s" % [dmg, str(global_position.round()), str(velocity.round()), _tilt, str(_grounded), str(driver().get("display_name")) if driver() != null else "-"])
	if driver() != null and driver().get("bot_id") != null:
		_bp_crash_t.append(Time.get_ticks_msec())
	if dmg > 0.0:
		take_damage(dmg, "", "Crash", -1)


func take_damage(amount: float, killer := "", weapon := "", killer_team := -1) -> void:
	if not alive or not _is_host_side():
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
		hp = 0.0
		if main != null and main.has_method("vehicle_send"):
			main.vehicle_send("net_vehicle_hp", [vehicle_id, hp], true)
		# Shot down in the air: the pilot is thrown clear. A crash, or a
		# wreck on the ground, takes the pilot with it.
		var violent := weapon == "Crash" or _on_ground_now()
		_host_destroy(last_hitter, last_hitter_team, violent)
		return
	if absf(_last_sent_hp - hp) >= MAX_HP * 0.05:
		_last_sent_hp = hp
		if main != null and main.has_method("vehicle_send"):
			main.vehicle_send("net_vehicle_hp", [vehicle_id, hp], true)


func _on_ground_now() -> bool:
	return _ground_below(global_position, SHAPE_R + 16.0) != INF


func apply_destroy(at: Vector2, killer: String, killer_team: int, quiet := false, violent := true) -> void:
	if is_instance_valid(_hidden_crew):
		_hidden_crew.visible = true
	_hidden_crew = null
	super(at, killer, killer_team, quiet, violent)
	throttle = 0.0
	air_parked = false
	_bot_left = false


## #294: see ABANDON_RETURN. The #259 idle clock (buggy._touch_tick) does the
## actual return; this only winds it forward once the abandoned plane is at rest.
func _touch_tick(delta: float) -> void:
	if _bot_left and driver() == null and _is_host_side() and idle_respawn_time > ABANDON_RETURN \
			and velocity.length() < 30.0 and global_position.distance_to(spawn_pos) > 24.0:
		_idle_t = maxf(_idle_t, idle_respawn_time - ABANDON_RETURN)
	super(delta)


## The wreck falls to the ground as a husk on every peer (same start, same
## terrain); collision_layer is 0 so it hurts nobody.
func _tick_dead(delta: float) -> void:
	# (Not is_on_floor(): a plane destroyed right after leaving the ground
	# still reports the last floor contact.)
	if _ground_below(global_position, SHAPE_R + 4.0) == INF or velocity.y < 0.0:
		velocity.x *= 1.0 - minf(1.0, 0.8 * delta)
		velocity.y = minf(velocity.y + 1700.0 * MatchConfig.mod_gravity() * delta, 1400.0)
		move_and_slide()
		if is_on_floor():
			velocity = Vector2.ZERO
	super(delta)


func apply_respawn() -> void:
	# Level the body before buggy.apply_respawn unsticks it at the spawn.
	_tilt = 0.0
	_update_shape()
	super()
	throttle = 0.0
	bomb_cd = 0.0
	_crash_cd = 1.0    # settling on its wheels at the spot isn't a crash
	_bp_crash_t.clear()
	_bot_left = false
	_decide_spawn()
	_grounded = not air_spawn


# ── Network smoothing ─────────────────────────────────

func apply_state(pos: Vector2, vel: Vector2, tilt: float, f: float, aim: Vector2) -> void:
	if is_sim():
		return
	state_rx += 1
	var now := Time.get_ticks_msec()
	var dt := float(now - _last_rx_ms) / 1000.0
	if _last_rx_ms > 0 and dt > 0.01 and dt < 0.5:
		_tilt_rate = clampf(angle_difference(_target_tilt, tilt) / dt, -6.0, 6.0)
	else:
		_tilt_rate = 0.0
	_last_rx_ms = now
	if _target_pos == Vector2.INF or pos.distance_to(global_position) > 300.0:
		global_position = pos
		_tilt = tilt
	_target_pos = pos
	_target_vel = vel
	_target_tilt = tilt
	face = f
	aim_dir = aim
	throttle = clampf(aim.x, 0.0, 1.0)
	air_parked = vel == Vector2.ZERO and air_spawn and pos.distance_to(spawn_pos) < 4.0


## Replicas: position like the other vehicles (buggy._follow) and the heading
## extrapolated by its last turn rate and eased, so loops look smooth at 20 Hz.
func _follow(delta: float) -> void:
	if _target_pos == Vector2.INF:
		return
	super(delta)
	_target_tilt = wrapf(_target_tilt + _tilt_rate * delta, -PI, PI)
	_tilt = wrapf(lerp_angle(_tilt, _target_tilt, clampf(delta * 14.0, 0.0, 1.0)), -PI, PI)
	_update_shape()


func _exit_tree() -> void:
	if is_instance_valid(_hidden_crew):
		_hidden_crew.visible = true
	_hidden_crew = null


# ── Pilot input / weapons ─────────────────────────────

## Local human pilot: throttle lever (W / S), pitch from A / D, else the nose
## follows the right stick / touch aim stick / mouse cursor (once it moves).
## Returns (pitch -1..1, turn-round request).
func _pilot_input(me: Node2D, delta: float) -> Vector2:
	if Input.is_action_pressed("jump") or Input.is_action_pressed("jet"):
		throttle = minf(1.0, throttle + THROTTLE_RATE * delta)
	if Input.is_action_pressed("crouch"):
		throttle = maxf(0.0, throttle - THROTTLE_RATE * delta)
	var x := Input.get_axis("move_left", "move_right")
	if absf(x) > 0.1:
		_mouse_steer = false
		return Vector2(x, 0.0)
	var want := Vector2.ZERO
	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down", 0.2)
	var tc = TouchControls.instance
	if stick.length() > 0.3:
		want = stick
	elif tc != null and is_instance_valid(tc) and int(tc.get("_aim_touch")) >= 0:
		want = tc.aim_dir
	else:
		var mp := me.get_viewport().get_mouse_position()
		if _mouse_prev != Vector2.INF and mp.distance_to(_mouse_prev) > 3.0:
			_mouse_steer = true
		_mouse_prev = mp
		if _mouse_steer:
			want = me.get_global_mouse_position() - global_position
	if want.length() < 1.0:
		return Vector2.ZERO
	var turn := 1.0 if _grounded and want.x * face < -0.3 and velocity.length() < 50.0 else 0.0
	return Vector2(clampf(angle_difference(_tilt, want.angle()) * 3.0, -1.0, 1.0), turn)


func _occupant_controls(me: Node2D, my_seat: int) -> void:
	if my_seat != 0:
		return
	if Input.is_action_pressed("fire") and fire_cd <= 0.0 and not overheated:
		_fire(me)
	var g := Input.is_action_pressed("grenade")
	if g and not _g_prev and bomb_cd <= 0.0:
		_drop_bomb(me)
	_g_prev = g


func _fire(me: Node2D) -> void:
	if me != driver() or air_parked:
		return
	var muzzle := _body(NOSE_GUN)
	var dir := _nose().rotated(randf_range(-GUN_SPREAD, GUN_SPREAD))
	fire_cd = GUN_RATE
	var main := get_parent()
	if Net.is_networked() and main != null and main.has_method("vehicle_send"):
		main.vehicle_send("net_vehicle_fire", [vehicle_id, muzzle, dir], true)
		return
	apply_fire(muzzle, dir)


## Every peer spawns the round; it leaves the nose at gun speed plus the
## plane's own forward speed (damage is applied by each victim's owner).
func apply_fire(muzzle: Vector2, dir: Vector2) -> void:
	fire_cd = GUN_RATE
	var shooter := driver()
	if shooter == null:
		return
	var b = preload("res://scenes/bullet.tscn").instantiate()
	b.global_position = muzzle
	b.direction = dir
	b.speed = GUN_SPEED + maxf(0.0, velocity.dot(dir))
	b.damage = GUN_DAMAGE * MatchConfig.mod_damage()
	b.team = int(shooter.get("team"))
	b.killer_name = str(shooter.get("display_name"))
	b.weapon_name = "Plane MG"
	b.ignore_bodies = [self] + seats.filter(func(o): return is_instance_valid(o))
	get_parent().add_child(b)
	Gfx.muzzle(get_parent(), muzzle, false, dir)
	_gun_kick = 2.0
	if Sfx._throttle("plane_mg_%d" % vehicle_id, 60):
		Sfx._play_key("m249-fire", -9.0, Gfx.rf(1.08, 1.16), muzzle)
	heat += HEAT_PER_SHOT
	if heat >= 1.0 and not overheated:
		overheated = true
		Sfx._play_key("m2overheat", -6.0, 1.1, muzzle)


func _drop_bomb(me: Node2D) -> void:
	if bomb_cd > 0.0 or me != driver() or air_parked:
		return
	var at := _body(BOMB_PT)
	var dir := velocity.normalized() if velocity.length() > 20.0 else Vector2(0, 1)
	bomb_cd = BOMB_CD
	var main := get_parent()
	if Net.is_networked() and main != null and main.has_method("vehicle_send"):
		main.vehicle_send("net_vehicle_fire_seat", [vehicle_id, 0, at, dir], true)
		return
	apply_fire_seat(0, at, dir)


## Host rate check for a client's bomb (match_vehicles, before relaying).
func fire_seat_ready(seat: int) -> bool:
	if seat != 0:
		return false
	return Time.get_ticks_msec() - _bomb_gate_ms >= int(BOMB_CD * 800.0)


## Every peer drops its own copy of the bomb (same start, same arc): rocket.gd
## with gravity and the bomb look; like tank shells, damage lands only on
## bodies this peer owns and vehicle damage comes from the host's copy.
func apply_fire_seat(seat: int, at: Vector2, dir: Vector2) -> void:
	if seat != 0:
		return
	var shooter := driver()
	if shooter == null:
		return
	_bomb_gate_ms = Time.get_ticks_msec()
	bomb_cd = BOMB_CD
	_bomb_n += 1
	var r = preload("res://scenes/rocket.tscn").instantiate()
	r.name = "PlaneBomb_%d_%d" % [vehicle_id, _bomb_n]
	r.local_only = true
	r.bomb_look = true
	r.ignore_bodies = [self] + seats.filter(func(o): return is_instance_valid(o))
	r.global_position = at
	r.direction = dir
	r.speed = clampf(velocity.length(), 0.0, 1100.0) * 0.95 + 20.0
	r.grav = BOMB_GRAV
	r.damage = BOMB_DAMAGE * MatchConfig.mod_damage()
	r.blast_radius = BOMB_BLAST
	r.team = int(shooter.get("team"))
	r.killer_name = str(shooter.get("display_name"))
	r.weapon_name = "Plane"
	get_parent().add_child(r)
	bombs_dropped += 1
	Sfx._play_key("grenade-throw", -4.0, Gfx.rf(0.7, 0.8), at)


# ── Bot pilot (host / single player) ─────────────────
# Simple and robust: full throttle down the runway, rotate at speed, climb to
# a cruise height over the terrain, fly toward the goal (or the target), gun
# runs when the nose bears on the target, a bomb when its predicted impact is
# on the target. Safety first every frame: pull up when the flight path ahead
# comes too close to the ground (look-ahead along the velocity), lower the
# nose when slow, stay under the ceiling. Bails out over the goal, when hurt,
# after two crashes, or when the take-off fails — and then leaves this plane
# alone for a while (bot_ban_t).

func _bot_pilot(delta: float) -> Vector2:
	var d := driver()
	_bp_t += delta
	var pos := global_position
	var spd := velocity.length()
	var mw := _map_w()
	var t = d.get("target")
	var tv: bool = t != null and is_instance_valid(t) and t.get("dead") != true
	var goal: Vector2 = d.get("_goal") if d.get("_goal") != null else Vector2.INF
	# #294: a target the pilot hasn't seen for a while (inside Fortress's keep)
	# is no reason to keep circling: no gun runs at it, and it doesn't stop the
	# bail-out over the goal.
	_bp_nosight = 0.0 if tv and d.get("_target_visible") == true else _bp_nosight + delta
	if _bp_nosight > 3.0:
		tv = false
	_bp_noenemy = 0.0 if tv else _bp_noenemy + delta
	var now := Time.get_ticks_msec()
	while not _bp_crash_t.is_empty() and now - int(_bp_crash_t[0]) > 20000:
		_bp_crash_t.pop_front()
	if not _grounded:
		bot_flown += spd * delta
	# Give up: hurt, crashing, can't get airborne, been at it long enough.
	if hp < MAX_HP * 0.25 or _bp_crash_t.size() >= 2 or (_grounded and _bp_t > 9.0 and spd < 80.0) or _bp_t > 150.0:
		_bp_bail = true
	if _bp_bail:
		_bot_leave(d, 20.0)
		return Vector2(0.0, 0.0)
	if _grounded:
		return _bot_takeoff(spd)
	var ground := _ground_y(pos.x, pos.y - 20.0)
	var alt := (ground - pos.y) if ground != INF else 9999.0
	var center := 1.0 if pos.x < mw * 0.5 else -1.0
	# Where to: the target (gun run / bomb run) or the goal at cruise height.
	var want := Vector2.ZERO
	var attack := false
	_bp_break = maxf(0.0, _bp_break - delta)
	_bp_evade = maxf(0.0, _bp_evade - delta)
	_bp_climb = maxf(0.0, _bp_climb - delta)
	# #298: an objective goal (the enemy flag, our flag to return, a carrier to
	# chase / escort, a DOM zone, home to defend) wins over the dogfight in two
	# steps: after OBJ_COMMIT s aloft the pilot bails out whenever it passes
	# over the goal, enemies about or not (gun runs still go on until then);
	# after OBJ_COMMIT_HARD s no more gun runs either (the gun still fires
	# when the nose happens to bear) — it flies to the goal and drops in.
	# Hunting / roaming pilots keep dogfighting.
	var objective: bool = goal != Vector2.INF and str(d.get("_goal_label")) in OBJ_LABELS
	var commit: bool = objective and _bp_t > OBJ_COMMIT
	var hard: bool = objective and _bp_t > OBJ_COMMIT_HARD
	# (Any height: soldiers take no fall damage and steer down onto the goal;
	# a committed pilot looping over its goal rarely came through low.)
	if commit and absf(goal.x - pos.x) < OBJ_BAIL_DX and spd < OBJ_BAIL_SPEED and alt > 60.0 and _solid_below(pos):
		_bot_leave(d, 20.0)
		return Vector2.ZERO
	if hard and tv and d.get("_target_visible") == true and fire_cd <= 0.0 and not overheated and heat < 0.8:
		var to_t: Vector2 = (t as Node2D).global_position + Vector2(0, -12) - pos
		if to_t.length() < BOT_GUN_RANGE and absf(angle_difference(_tilt, to_t.angle())) < 0.09:
			_fire(d)
	if tv and _bp_break <= 0.0 and not hard:
		var tp: Vector2 = (t as Node2D).global_position + Vector2(0, -12)
		var to := tp - pos
		if t is CharacterBody2D:
			to += (t as CharacterBody2D).velocity * (to.length() / (GUN_SPEED + spd))
		# (No gun runs at targets hugging the sides of the world.)
		if to.length() < 1400.0 and tp.x > 380.0 and tp.x < mw - 380.0:
			attack = true
			want = to
			if want.y > 0.0 and alt < 260.0:
				want.y = 0.0   # no low, steep gun runs: level out
			if to.length() < 230.0 or (to.y > 0.0 and alt < 220.0 and to.normalized().y > 0.55):
				_bp_break = 1.6   # too close / too steep near the ground: climb away
			if to.length() < BOT_GUN_RANGE and absf(angle_difference(_tilt, to.angle())) < 0.09 \
					and fire_cd <= 0.0 and not overheated and heat < 0.8 and d.get("_target_visible") == true:
				_fire(d)
			if bomb_cd <= 0.0 and tp.y > pos.y + 90.0 and _bomb_on_target(tp):
				_drop_bomb(d)
	if not attack:
		var tx := goal.x if goal != Vector2.INF else (mw * 0.5 + sin(_bp_t * 0.2) * mw * 0.3)
		tx = clampf(tx, 420.0, mw - 420.0)
		var dirx := signf(tx - pos.x)
		if absf(tx - pos.x) < 300.0:
			dirx = face
		var ahead := _ground_y(pos.x + dirx * 450.0, pos.y - 600.0)
		var want_y := minf(ground if ground != INF else pos.y + CRUISE_ALT, ahead if ahead != INF else INF) - CRUISE_ALT
		want_y = maxf(want_y, CEIL_Y + 160.0)
		var climb := clampf((pos.y - want_y) / 700.0, -0.45, 0.6)
		want = Vector2(dirx * cos(climb), -sin(climb))
		# Over the goal with nothing to fight (or committed to it, #298): slow
		# down and bail out.
		if goal != Vector2.INF and absf(goal.x - pos.x) < (OBJ_BAIL_DX if commit else 380.0) \
				and ((_bp_noenemy > 4.0 and _bp_t > 6.0) or commit):
			if spd < (OBJ_BAIL_SPEED if commit else 560.0) and alt > 60.0 and alt < 900.0 and _solid_below(pos):
				_bot_leave(d, 20.0)
				return Vector2.ZERO
			# Bleed speed with a gentle climb — unless already too high to
			# bail (#298: pilots used to climb pass after pass to the ceiling
			# and circle up there for the rest of the 150 s).
			want = Vector2(face, 0.45) if alt > 700.0 else Vector2(face, -0.25)
	var desired := want.angle()
	var thr := 1.0
	if _bp_break > 0.0:
		desired = Vector2(face * 0.8, -1.0).angle()
	if goal != Vector2.INF and not attack and absf(goal.x - pos.x) < 380.0:
		thr = 0.35
	if pos.y < CEIL_Y + 200.0 and Vector2.from_angle(desired).y < 0.0:
		desired = Vector2(face, 0.15).angle()
	# Committed evasive turns (no flip-flopping between goals frame to frame):
	# the side of the world or a wall ahead -> turn back toward the middle
	# (over the top when fast, under when slow and high); ground ahead -> climb.
	var lead := maxf(absf(velocity.x), 300.0) * 1.5
	var edge := (velocity.x >= 0.0 and pos.x + lead > mw - 260.0) or (velocity.x <= 0.0 and pos.x - lead < 260.0)
	var blk := _path_blocked(pos, spd)
	if (edge and Vector2.from_angle(_tilt).x * center < 0.3) or blk == 2:
		if _bp_evade <= 0.0:
			_bp_evade = 1.8
			_bp_evade_side = center
			# Over the top with room above and speed (or too low to go under),
			# else under (a split-S trades height for speed).
			var room := pos.y - CEIL_Y
			_bp_evade_over = (room > 650.0 and (spd > 520.0 or alt < 450.0)) or alt < 350.0
			_bp_evade_dir = Vector2(center * 0.7, -1.0).angle() if _bp_evade_over else Vector2(center, 0.6).angle()
		elif blk == 2 and not _bp_evade_over and _bp_evade < 1.2:
			# Still a wall ahead going under: climb out over it instead.
			_bp_evade_over = true
			_bp_evade_dir = Vector2(_bp_evade_side * 0.7, -1.0).angle()
	if blk == 1:
		_bp_climb = maxf(_bp_climb, 0.45)
	if _bp_evade > 0.0:
		desired = _bp_evade_dir
		thr = 1.0
	if _bp_climb > 0.0:
		# Pull up — toward the side the evasive turn is heading, if any.
		desired = Vector2((_bp_evade_side if _bp_evade > 0.0 else face) * 0.35, -1.0).angle()
		thr = 1.0
	# Too slow to fly: nose down (away from the side of the world) to get speed.
	if spd < STALL_SPEED + 90.0 and _bp_climb <= 0.0:
		desired = Vector2(center if edge else face, 0.45 if alt > 160.0 else 0.0).angle()
		thr = 1.0
	var pitch := clampf(angle_difference(_tilt, desired) * 3.0, -1.0, 1.0)
	# Turning round (target / goal behind): go under (a split-S) when there's
	# little sky left above and height to spare, else over the top.
	if absf(angle_difference(_tilt, desired)) > 1.7 and _bp_evade <= 0.0 and _bp_climb <= 0.0:
		var under := pos.y - CEIL_Y < 700.0 and alt > 450.0
		var cw := fposmod(desired - _tilt, TAU)
		var cw_down := fposmod(PI * 0.5 - _tilt, TAU) < cw
		pitch = 1.0 if cw_down == under else -1.0
	if _DBG == "2" and fmod(_bp_t, 0.25) < delta:
		print("PLANE bot %s pos=%s v=%d tilt=%.2f want=%.2f pitch=%.2f alt=%d atk=%s blk=%d ev=%.1f cl=%.1f" % [str(d.get("display_name")),
			str(pos.round()), int(spd), _tilt, desired, pitch, int(alt), str(attack), blk, _bp_evade, _bp_climb])
	return Vector2(pitch, thr)


func _bot_takeoff(spd: float) -> Vector2:
	var tan := _ground_tangent()
	# Runway blocked right ahead while slow: turn round (or give up).
	var pos := global_position
	var blocked := not _ray_hit(pos + Vector2(0, -6), pos + Vector2(0, -6) + tan * (90.0 + spd * 0.5)).is_empty()
	if blocked and spd < 120.0:
		return Vector2(face, 0.0) if _turn_cd <= 0.0 else Vector2.ZERO   # nose-down push = turn round
	if blocked and spd < ROTATE_SPEED:
		return Vector2(0.0, 0.0)   # brake
	if spd > ROTATE_SPEED + 20.0:
		return Vector2(-face, 1.0)  # rotate: nose up
	return Vector2(0.0, 1.0)


## Ground under (x) at or below from_y: the match's plain-geometry query, or a ray.
func _ground_y(x: float, from_y: float) -> float:
	var m := get_parent()
	if m != null and m.has_method("_geom_ground_y"):
		var gy: float = m._geom_ground_y(x, from_y)
		var ky = m.get("KILL_Y")
		if gy == INF and ky != null and float(ky) != INF:
			return float(ky)
		return gy
	return _ground_below(Vector2(x, from_y), 3000.0)


## 0 clear, 1 ground ahead (climb), 2 a wall ahead (turn back).
func _path_blocked(pos: Vector2, spd: float) -> int:
	var v := velocity if spd > 1.0 else _nose()
	var h := _ray_hit(pos, pos + v * 0.9)
	if not h.is_empty() and absf((h.normal as Vector2).y) < 0.5:
		return 2
	# Look ahead about as far as a pull-out takes (~450 px of turn at speed).
	var tmax := clampf(0.4 + 450.0 / maxf(spd, 1.0), 0.8, 1.2)
	for k in [0.25, 0.5, 0.75, 1.0]:
		var p: Vector2 = pos + v * float(k) * tmax
		var gy := _ground_y(p.x, p.y - 260.0)
		if gy != INF and gy - p.y < MIN_CLEAR:
			return 1
	return 0 if h.is_empty() else 1


## Real ground under `pos` (not the void down to the kill line).
func _solid_below(pos: Vector2) -> bool:
	var m := get_parent()
	if m != null and m.has_method("_geom_ground_y"):
		var gy: float = m._geom_ground_y(pos.x, pos.y)
		var ky = m.get("KILL_Y")
		return gy != INF and (ky == null or gy < float(ky))
	return _ground_below(pos, 1200.0) != INF


func _bomb_on_target(tp: Vector2) -> bool:
	var g := BOMB_GRAV * MatchConfig.mod_gravity()
	var dy := tp.y - global_position.y
	var vy := velocity.y
	var disc := vy * vy + 2.0 * g * dy
	if disc < 0.0:
		return false
	var tt := (-vy + sqrt(disc)) / g
	var ix := global_position.x + velocity.x * tt
	return absf(ix - tp.x) < 70.0 and tt < 3.5


func _bot_leave(d: Node, ban: float) -> void:
	bot_ban_t = ban
	_bot_left = true
	var main := get_parent()
	if Net.is_networked() and main != null and main.has_method("net_vehicle_seat_bot"):
		main.bcast("net_vehicle_seat_bot", [vehicle_id, 0, int(d.get("bot_id")), false], true)
	else:
		clear_seat_of(d)


# ── Terrain queries ───────────────────────────────────

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


# ── Presentation (#291, cosmetic only) ───────────────
# Reads the replicated state (position, velocity, heading, face, throttle,
# hp, alive, seats, heat, bomb_cd) and only draws / spawns pooled effects.

func _engine_sound() -> void:
	if _engine.stream == null or Settings.sfx_volume <= 0.0:
		return
	var running := alive and (driver() != null or throttle > 0.03)
	if not running:
		if _engine.playing:
			_engine.stop()
		return
	if not _engine.playing:
		_engine.play()
	var sp := clampf(velocity.length() / MAX_SPEED, 0.0, 1.0)
	_engine.pitch_scale = 0.75 + throttle * 0.55 + sp * 0.25
	_engine.volume_db = -19.0 + throttle * 8.0 + linear_to_db(clampf(Settings.sfx_volume, 0.0001, 1.0))


func _frames() -> void:
	var sy := _roll
	if absf(sy) < 0.16:
		sy = 0.16 if sy >= 0.0 else -0.16
	_xf_w = Transform2D(_tilt, Vector2(1.0, sy), 0.0, Vector2.ZERO)
	_xf_b = _xf_w


func _rim_face() -> float:
	return 1.0 if _roll >= 0.0 else -1.0


func _rim_tilt() -> float:
	return _tilt if _roll >= 0.0 else _tilt + PI


func _fx_tick(delta: float) -> void:
	var dt := minf(delta, 0.05)
	_roll = move_toward(_roll, face, dt * 5.5)
	_blink_t += dt
	_flame_k = move_toward(_flame_k, throttle if alive and (driver() != null or throttle > 0.03) else 0.0, dt * 3.0)
	# Landing gear: down on the ground / near it at low speed, up in flight.
	_gear_t -= dt
	if _gear_t <= 0.0 and alive:
		_gear_t = 0.25
		_gear_low = air_parked or (velocity.length() < 520.0 and _ground_below(global_position, 150.0) != INF)
	_gear = move_toward(_gear, 1.0 if _gear_low else 0.0, dt * 1.6)
	super(delta)
	if not alive or VArt.level() == 0 or not _onscr:
		return
	var w = _fxw()
	if w == null:
		return
	var r := Gfx.rng
	var nose := _nose()
	var noz := _world_pt(Vector2(-55, -0.5))
	if _flame_k > 0.05:
		Atmosphere.light_keep(get_instance_id() * 8 + 1, noz - nose * (10.0 + _flame_k * 18.0), Color(1.0, 0.6, 0.3),
			55.0 + _flame_k * 75.0, 0.55 + _flame_k * 0.45)
		_fx_exhaust_t -= dt
		if _fx_exhaust_t <= 0.0:
			_fx_exhaust_t = (0.05 if VArt.level() >= 2 else 0.1)
			w.smoke(noz - nose * 8.0, -nose * r.randf_range(60, 120) + Vector2(r.randf_range(-10, 10), r.randf_range(-14, 4)),
				r.randf_range(3.0, 5.0) * (0.6 + _flame_k), r.randf_range(0.25, 0.5), Color(0.55, 0.55, 0.58, 0.08 + _flame_k * 0.06))
	# Nav strobe on the fin tip, landing light with the gear down.
	if driver() != null and fmod(_blink_t, 1.2) < 0.08:
		Atmosphere.light_keep(get_instance_id() * 8 + 3, _world_pt(Vector2(-47, -25)), Color(1.0, 0.2, 0.15), 40.0, 0.9, 0.05)
	if driver() != null and _gear > 0.5:
		var lamp := _world_pt(HEADLIGHT_PT)
		Atmosphere.light_keep(get_instance_id() * 8 + 4, lamp + nose * 90.0, Color(1.0, 0.92, 0.75), 110.0, 0.55)


func _fx_running(w: Object, dt: float, lv: int) -> void:
	# Wheel spray on a fast ground run (the exhaust / lights live in _fx_tick).
	var spd := velocity.length()
	_fx_dust_t -= dt
	if spd > 140.0 and _gear > 0.9 and absf(velocity.y) < 60.0 and _fx_dust_t <= 0.0:
		var gy := _ground_below(global_position, SHAPE_R + 8.0)
		if gy != INF:
			_fx_dust_t = 0.06 if lv >= 2 else 0.12
			w.wheel_dust(Vector2(global_position.x - face * 10.0, gy), velocity.x, clampf(spd / 600.0, 0.2, 1.0))


static func _plane_shapes() -> Dictionary:
	if not _PS.is_empty():
		return _PS
	# Nose along +x, canopy up (-y), origin on the centre line.
	_PS["body"] = VArt.pv([Vector2(50, 1.5), Vector2(45, -2), Vector2(35, -5), Vector2(22, -7), Vector2(8, -8), Vector2(-14, -7.5),
		Vector2(-34, -6), Vector2(-46, -4.5), Vector2(-50, -2.5), Vector2(-50, 2.5), Vector2(-44, 4.5), Vector2(-24, 6.5),
		Vector2(4, 7.5), Vector2(24, 6), Vector2(39, 3.8)])
	_PS["belly"] = VArt.pv([Vector2(39, 3.8), Vector2(24, 6), Vector2(4, 7.5), Vector2(-24, 6.5), Vector2(-44, 4.5), Vector2(-40, 2.0),
		Vector2(-10, 3.2), Vector2(20, 2.6)])
	_PS["glass"] = VArt.pv([Vector2(27, -6.4), Vector2(18, -12.5), Vector2(8, -14), Vector2(-2, -12.6), Vector2(-8, -8), Vector2(10, -7.8)])
	_PS["fin"] = VArt.pv([Vector2(-27, -6.3), Vector2(-40, -24), Vector2(-48, -25.5), Vector2(-50.5, -24), Vector2(-48, -4.6)])
	_PS["stab"] = VArt.pv([Vector2(-33, 0.5), Vector2(-50, -1.5), Vector2(-55, 0.5), Vector2(-50, 2.8)])
	_PS["wing"] = VArt.pv([Vector2(14, 1.2), Vector2(-4, 2.8), Vector2(-27, 4.6), Vector2(-31, 3.2), Vector2(-14, 0.8)])
	_PS["intake"] = VArt.pv([Vector2(17, -3.0), Vector2(6, -4.4), Vector2(6, 2.6), Vector2(17, 1.6)])
	_PS["nozzle"] = VArt.pv([Vector2(-46, -4.4), Vector2(-55, -4.8), Vector2(-55, 3.8), Vector2(-46, 3.6)])
	_PS["stripe"] = VArt.pv([Vector2(-34.8, -14.5), Vector2(-44.6, -15.3), Vector2(-45.6, -12.2), Vector2(-33.0, -11.6)])
	_PS["topline"] = VArt.pv([Vector2(45, -2), Vector2(35, -5), Vector2(22, -7), Vector2(8, -8), Vector2(-14, -7.5), Vector2(-34, -6), Vector2(-46, -4.5)])
	_PS["bomb"] = VArt.pv([Vector2(6, 9.6), Vector2(3, 8.6), Vector2(-6, 8.6), Vector2(-9, 9.6), Vector2(-6, 10.8), Vector2(3, 10.8)])
	_PS["husk"] = VArt.pv([Vector2(44, 2), Vector2(34, -5), Vector2(8, -8), Vector2(-30, -6), Vector2(-46, -3), Vector2(-46, 3),
		Vector2(-20, 6), Vector2(24, 6)])
	for k in ["body", "fin", "glass", "stab"]:
		_PS[k + "_n"] = VArt.normals(_PS[k])
	return _PS


func _draw_hull(lv: int) -> void:
	var S := _plane_shapes()
	var paint := _team_color()
	var trim := VArt.trim(team, _team_mode())
	var cine := VArt.cinematic()
	var line := Color(0.02, 0.02, 0.025, 0.9)
	var steel := VArt.STEEL if cine else VArt.STEEL.lightened(0.12)
	var rf := _rim_face()
	var rt := _rim_tilt()
	draw_set_transform_matrix(_xf_b)
	# Afterburner (behind the nozzle): core + outer flame, longer with throttle.
	if _flame_k > 0.04:
		var fl := 6.0 + _flame_k * 24.0 * (0.9 + 0.1 * sin(_fx_time * 41.0 + float(vehicle_id)))
		var o := Vector2(-55, -0.5)
		draw_colored_polygon(PackedVector2Array([o + Vector2(0, -3.6), o + Vector2(-fl * 0.55, -2.6), o + Vector2(-fl, 0), o + Vector2(-fl * 0.55, 2.6),
			o + Vector2(0, 3.6)]), Color(1.0, 0.45, 0.15, 0.55))
		draw_colored_polygon(PackedVector2Array([o + Vector2(0, -2.0), o + Vector2(-fl * 0.6, -0.9), o + Vector2(-fl * 0.62, 0.9), o + Vector2(0, 2.0)]),
			Color(1.0, 0.86, 0.55, 0.85))
		if lv >= 1:
			draw_circle(o + Vector2(-1.5, 0), 3.6, Color(1.0, 0.7, 0.35, 0.35))
	# Far-side stabiliser (darker), landing gear.
	VArt.part(self, S["stab"], PackedColorArray(), paint.darkened(0.45), Color(0, 0, 0, 0))
	if _gear > 0.02:
		_draw_gear(lv, steel)
	# Fuselage, belly shade, wing, intake, nozzle.
	VArt.part(self, S["body"], _cols("body", S["body"], paint.lightened(0.28), paint.darkened(0.5), -8.0, 7.5), paint, line, 1.3)
	if lv >= 1:
		var bc := paint.darkened(0.6)
		bc.a = 0.45
		var b0 := bc
		b0.a = 0.0
		draw_polygon(S["belly"], PackedColorArray([bc, bc, bc, bc, bc, b0, b0, b0]))
	VArt.part(self, S["wing"], _cols("wing", S["wing"], paint.lightened(0.12), paint.darkened(0.42), 0.8, 4.6), paint.darkened(0.15), line, 1.0)
	draw_colored_polygon(S["intake"], Color(0.03, 0.03, 0.035))
	if lv >= 1:
		draw_line(Vector2(17, -3.0), Vector2(17, 1.6), steel.lightened(0.3), 1.0)
	VArt.part(self, S["nozzle"], _cols("nozzle", S["nozzle"], steel.lightened(0.25), steel.darkened(0.35), -4.8, 3.8), steel, line, 1.0)
	if lv >= 1:
		for nx in [-48.0, -50.5, -53.0]:
			draw_line(Vector2(nx, -4.2), Vector2(nx, 3.4), Color(0.02, 0.02, 0.02, 0.6), 0.8)
	# Tail fin with the team stripe + mark (shape per team).
	VArt.part(self, S["fin"], _cols("fin", S["fin"], paint.lightened(0.18), paint.darkened(0.35), -25.0, -5.0), paint, line, 1.2)
	draw_colored_polygon(S["stripe"], trim.darkened(0.15) if cine else trim)
	VArt.mark(self, Vector2(-14.0, -1.0), team, _team_mode(), 3.4)
	# Panel lines, rivets, gun port, damage marks.
	if lv >= 1:
		var pl := Color(0.02, 0.02, 0.02, 0.5)
		draw_line(Vector2(30, -5.6), Vector2(31, 4.4), pl, 0.9)
		draw_line(Vector2(-22, -7.0), Vector2(-21, 6.3), pl, 0.9)
		draw_line(Vector2(-8, -7.8), Vector2(-14, -7.5), pl, 0.9)
		for rx in range(-40, 40, 7):
			draw_circle(Vector2(rx, -0.6), 0.6, VArt.STEEL_HI)
		VArt.grime(self, -44.0, 30.0, 3.0, 6.8, 0.45 if cine else 0.3)
		VArt.scorch(self, _spots, _dmg())
	draw_circle(Vector2(46.5, 1.6), 1.1, Color(0.02, 0.02, 0.02))
	if fire_cd > GUN_RATE * 0.4 and lv >= 1:
		draw_circle(Vector2(51, 1.5), 2.6, Color(1.0, 0.78, 0.35, 0.8))
	# Bomb on its rack while it's loaded.
	if bomb_cd <= 0.0:
		draw_line(Vector2(-2, 7.4), Vector2(-2, 8.8), steel, 1.4)
		draw_colored_polygon(S["bomb"], Color(0.2, 0.22, 0.2))
		if lv >= 1:
			draw_line(Vector2(3, 9.0), Vector2(-6, 9.0), Color(0.42, 0.45, 0.4), 0.8)
			draw_line(Vector2(-6, 9.7), Vector2(-10, 8.2), Color(0.15, 0.15, 0.15), 1.0)
			draw_line(Vector2(-6, 9.7), Vector2(-10, 11.2), Color(0.15, 0.15, 0.15), 1.0)
	# Canopy: pilot's helmet + visor under tinted glass, reflection streak.
	var d := driver()
	if d != null:
		var hc := Color(0.16, 0.17, 0.18)
		draw_circle(Vector2(8, -9.6), 3.6, hc)
		draw_colored_polygon(PackedVector2Array([Vector2(9, -11), Vector2(12.4, -10.4), Vector2(12, -8), Vector2(9, -8.4)]), trim if _team_mode() else Color(0.95, 0.6, 0.2))
		draw_line(Vector2(5, -7.8), Vector2(2, -6.8), Color(0.1, 0.1, 0.1), 2.0)
	var gtop := Color(0.25, 0.42, 0.52, 0.45) if cine else Color(0.42, 0.62, 0.72, 0.5)
	var gbot := Color(0.05, 0.1, 0.14, 0.62)
	if lv >= 1:
		draw_polygon(S["glass"], _cols("glass", S["glass"], gtop, gbot, -14.0, -6.4))
		draw_line(Vector2(17, -11.6), Vector2(23, -8.0), Color(1, 1, 1, 0.42), 1.2)
		draw_line(Vector2(4, -13.2), Vector2(9, -13.4), Color(1, 1, 1, 0.3), 1.0)
		if cine and d != null:
			draw_line(Vector2(19, -7.4), Vector2(23, -7.4), Color(VArt.NEON.r, VArt.NEON.g, VArt.NEON.b, 0.7), 0.9)
	else:
		draw_colored_polygon(S["glass"], Color(0.2, 0.32, 0.4, 0.6))
	draw_polyline(S["glass"], line, 1.0)
	draw_line(S["glass"][S["glass"].size() - 1], S["glass"][0], line, 1.0)
	# Lamps: fin strobe, landing light with the gear down.
	var on := d != null
	VArt.lamp(self, Vector2(-47, -25), Color(1.0, 0.2, 0.15), 1.3, on and fmod(_blink_t, 1.2) < 0.08)
	VArt.lamp(self, Vector2(-44, -3.5), Color(1, 1, 1), 1.0, on and fmod(_blink_t * 1.7, 1.0) < 0.05)
	if on and _gear > 0.5:
		VArt.cone(self, HEADLIGHT_PT, Vector2(1.0, 0.18).normalized(), HEADLIGHT_LEN * 0.6, 0.14, Color(1.0, 0.93, 0.75, 0.12 if cine else 0.08))
		VArt.lamp(self, HEADLIGHT_PT, Color(1.0, 0.92, 0.7), 1.5, true)
	# Rim (cinematic) / lit top line (classic).
	if cine:
		VArt.rim(self, S["body"], S["body_n"], rf, rt, 1.0)
		VArt.rim(self, S["fin"], S["fin_n"], rf, rt, 0.8)
		VArt.rim(self, S["glass"], S["glass_n"], rf, rt, 0.5)
	elif lv >= 1:
		draw_polyline(S["topline"], paint.lightened(0.4), 1.0)
	# Damage fire licking out of the engine bay (pooled smoke / embers: _fx_tick).
	var dm := _dmg()
	if dm >= 0.75 and lv >= 1:
		draw_set_transform(_world_pt(ENGINE_PT) - global_position, 0.0, Vector2.ONE)
		VArt.flame(self, Vector2.ZERO, 6.0 + (dm - 0.75) * 14.0, _fx_time, float(vehicle_id))
	elif dm >= 0.55 and lv == 0:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var tt := fmod(_fx_time, 1.0)
		draw_circle(_world_pt(ENGINE_PT) - global_position + Vector2(0, -tt * 30.0), 5.0 + tt * 7.0, Color(0.15, 0.15, 0.15, 0.4 * (1.0 - tt)))


func _draw_gear(lv: int, steel: Color) -> void:
	var k := _gear
	# Struts swing back into the belly as the gear retracts.
	for g in [[Vector2(26, 5.5), 3.0], [Vector2(-10, 6.0), 3.6]]:
		var root: Vector2 = g[0]
		var r: float = g[1]
		var hub := root + Vector2(-(1.0 - k) * 8.0, 4.5 * k + 0.6)
		VArt.tube(self, root, hub, steel.lightened(0.15), 1.6)
		if k > 0.3:
			VArt.wheel(self, hub, r * (0.6 + 0.4 * k), _wheel_rot, velocity.length() if _gear_low else 0.0, Color(0.5, 0.5, 0.5))
	if lv >= 1 and k < 0.95:
		draw_line(Vector2(22, 6.2), Vector2(30, 5.0), Color(0, 0, 0, 0.5), 0.8)


func _draw_gun(_lv: int) -> void:
	pass   # fixed nose gun, drawn with the hull


func _draw_wreck(lv: int) -> void:
	var S := _plane_shapes()
	# Broken in the dirt: charred fuselage nose-down, the fin snapped off.
	draw_set_transform_matrix(Transform2D(0.12 * face, Vector2(face, 1.0), 0.0, Vector2(0, 4)))
	VArt.part(self, S["husk"], _cols("husk", S["husk"], VArt.CHAR_HI, VArt.CHAR, -8.0, 6.0), VArt.CHAR, Color(0, 0, 0, 0.85), 1.3)
	draw_colored_polygon(S["glass"], Color(0.02, 0.02, 0.02, 0.9))
	draw_set_transform_matrix(Transform2D(0.12 * face, Vector2(face, 1.0), 0.0, Vector2(0, 4)) * Transform2D(0.9, Vector2(-30, 6)))
	draw_colored_polygon(S["fin"], VArt.CHAR)
	draw_set_transform_matrix(Transform2D(0.12 * face, Vector2(face, 1.0), 0.0, Vector2(0, 4)))
	VArt.tube(self, Vector2(-14, 3), Vector2(-26, 7), VArt.CHAR_HI, 1.8)
	if lv >= 1:
		VArt.scorch(self, _spots, 1.0)
		if _wreck_t < 7.0:
			var f := clampf(1.0 - _wreck_t / 7.0, 0.3, 1.0)
			draw_set_transform(Vector2(0, 4), 0.0, Vector2.ONE)
			VArt.flame(self, Vector2(-10 * face, -4), 10.0 * f, _fx_time, 2.0)
			VArt.flame(self, Vector2(16 * face, -2), 7.0 * f, _fx_time, 5.0)


func _draw_overlay() -> void:
	super()
	if driver() != null and bomb_cd > 0.0:
		draw_rect(Rect2(-24, -LABEL_LIFT - 7.0, 48.0 * (1.0 - bomb_cd / BOMB_CD), 3), Color(0.95, 0.8, 0.3, 0.8))
