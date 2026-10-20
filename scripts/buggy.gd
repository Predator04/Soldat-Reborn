extends CharacterBody2D
## Buggy (v1.19) — two-seat ground vehicle. Walk up and press F: the first
## seat is the driver (A/D drive, F gets out), the second the gunner
## on a mounted machine gun. A driver alone can also fire the gun.
## Enemies it hits at speed get run over; bullets and blasts wreck it, and it
## blows up with anyone still inside. Respawns at its spot after a while.
##
## Networking: the node is always owned by the host (damage, destruction,
## respawn). Movement is simulated by whoever is driving (the host when
## nobody is) and streamed to everyone else through Main's net_vehicle_* RPCs.

var MAX_HP := 350.0
var ACCEL := 820.0
var MAX_SPEED := 520.0
var REVERSE_SPEED := 260.0
var BRAKE := 1100.0
var ROLL_DRAG := 260.0
var AIR_CONTROL := 0.25
var GRAVITY := 1700.0
var HOP_VEL := 0.0            # no hop: vehicles stay on the ground (reported)
var STEP_UP := 16.0           # climbs curbs / small lips up to this height
var ENTER_RADIUS := 56.0
var RUNOVER_MIN_SPEED := 190.0
var GUN_RATE := 0.075
var GUN_DAMAGE := 14.0
var GUN_SPEED := 1450.0
var GUN_SPREAD := 0.035
var HEAT_PER_SHOT := 0.035    # ~2 s of continuous fire to overheat
var HEAT_COOL := 0.45         # per second
var RESPAWN_TIME := 25.0
# #259: an untouched, displaced vehicle returns to its spawn point after this
# long (occupied / damaged / entered reset the clock). Overridable for tests.
var idle_respawn_time := 60.0
const STUCK_UNSTICK_TIME := 3.0   # driven but motionless this long -> lift out
var EXPLODE_RADIUS := 150.0
var EXPLODE_DAMAGE := 120.0
var EXPLOSIVE_MUL := 1.6      # rockets / grenades hurt it more than bullets
# Driving and shooting at once (no gunner): slower and sloppier. A crew of
# two is the strong way to run a buggy.
var SOLO_FIRE_SPEED := 0.5    # top speed while the solo driver holds the trigger
var SOLO_FIRE_SPREAD := 2.2   # spread multiplier for a solo driver
var BOT_GUN_RANGE := 900.0
var WRECK_WEAPON := "Buggy"   # kill-feed weapon for the wreck blast
var EJECT_DMG := 30.0         # a crew member thrown clear of a gentle wreck (helicopter)
# #277: host relay sanity cap on a client-simulated vehicle (px/s over >= 250 ms,
# falls included — generous on purpose; honest driving never comes close).
var RELAY_MAX_SPEED := 2000.0
# #291: how far from the body a streamed muzzle may be (host check in
# match_vehicles; the plane's nose gun outruns the host's smoothed copy).
var FIRE_REACH := 90.0
var state_rx := 0             # remote state packets applied (smoke tests)
var respawns := 0             # apply_respawn count (host relay check resets on it)

# Seat offsets (local, facing right, before tilt). The soldier's origin sits
# here; the body is drawn over their legs so they look seated.
var SEATS := [Vector2(4, -30), Vector2(-24, -34)]

var vehicle_id := -1
var kind := "buggy"             # "buggy" | "tank" (subclass)
var LABEL := "BUGGY"
var LABEL_LIFT := 44.0
var SHAPE_R := 11.0
var SHAPE_LEN := 62.0
var ENGINE_PITCH := 0.55
var RUNOVER_DMG_PER_SPEED := 0.3
var BULLET_ARMOR := 1.0         # damage multiplier for non-explosive hits
var spawn_pos := Vector2.ZERO
var hp := MAX_HP
var _last_sent_hp := MAX_HP   # #246: last HP value broadcast to peers
var alive := true
var team := -1                      # driver's team (bullets use this); -1 empty
var display_name := "Buggy"
var seats: Array = [null, null]     # [driver, gunner] soldier nodes
var aim_dir := Vector2.RIGHT
var face := 1.0
var heat := 0.0
var overheated := false
var fire_cd := 0.0
var last_hitter := ""
var last_hitter_team := -1
var _tilt := 0.0
var _wheel_rot := 0.0
var _hop_cd := 0.0
var _net_t := 0.0
var _target_pos := Vector2.INF
var _target_vel := Vector2.ZERO
var _respawn_t := 0.0
var _runover_cd: Dictionary = {}
var _f_prev := true
var _engine: AudioStreamPlayer2D
var _smoke_t := 0.0
var _solo_fire_t := 0.0         # >0 while a lone driver is firing
var _bot_hold := false          # bot gunner letting the barrel cool
var _no_driver_t := 0.0
var _idle_t := 0.0            # #259: seconds since anyone touched the vehicle
var _stuck_t := 0.0           # #259: driver throttling but we're not moving
var _adopt_settle := false    # #259: idle respawned, adopt the rest spot as home
var _bd_check := 0.0            # bot driver: stuck / progress tracking
var _bd_last_x := 0.0
var _bd_stuck_t := 0.0
var _bd_hop := false

const EXPLOSIVE_WEAPONS := ["LAW", "M79", "Grenade", "Cluster", "Tank", "Buggy", "Heli", "Plane"]
const _BARREL_TEX := preload("res://assets/weapons-gfx/m2.png")
const TouchControls = preload("res://scripts/touch_controls.gd")
const VArt = preload("res://scripts/gfx/vehicle_art.gd")
const Gfx = preload("res://scripts/gfx.gd")
const _RIM_SHADER = preload("res://scripts/gfx/rim_light.gdshader")

# ── Look (#276), per kind (subclasses override in _init). Local points are
# facing right, origin on the ground under the middle of the body.
var PAINT_BASE := Color(0.46, 0.43, 0.32)    # desert drab
var EXHAUST_PT := Vector2(-50, -34)
var ENGINE_PT := Vector2(-38, -26)
var HEADLIGHT_PT := Vector2(40, -22)
var HEADLIGHT_LEN := 150.0
var DUST_X: Array = [-22.0, 22.0]
var GUN_POST := Vector2(-18, -28)
var SUSP_MAX := 5.0
var SHADOW_W := 34.0          # soldier_shadows.gd: contact-shadow half width
var SHADOW_REACH := 150.0     # ...and how high above the ground it still shows
# Cosmetic state (never read by the simulation).
var draws := 0                # _draw calls (gate draw-path test)
var _onscr := true            # near the camera this frame (redraws only then)
var _susp := 0.0
var _susp_v := 0.0
var _pitch := 0.0
var _fx_prev_v := Vector2.ZERO
var _gun_kick := 0.0
var _fx_time := 0.0
var _wreck_t := 0.0
var _fx_hp := -1.0
var _hit_flash := 0.0
var _flash_on := false
var _fx_exhaust_t := 0.0
var _fx_dust_t := 0.0
var _fx_spark_t := 0.0
var _fx_smoke_t := 0.0
var _fx_fire_t := 0.0
var _xf_w := Transform2D.IDENTITY
var _xf_b := Transform2D.IDENTITY
var _spots: Array = []
var _col_cache: Dictionary = {}
static var _BS: Dictionary = {}


func _ready() -> void:
	add_to_group("vehicle")
	# Layer 8 like soldiers: bullets / blasts hit it, soldiers walk through it
	# (soldiers don't collide with each other either).
	collision_layer = 8
	collision_mask = 1 | 4
	var cs := CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = SHAPE_R
	cap.height = SHAPE_LEN
	cs.shape = cap
	cs.rotation = PI / 2.0
	cs.position = Vector2(0, -SHAPE_R)
	add_child(cs)
	floor_max_angle = deg_to_rad(58.0)
	floor_snap_length = 18.0
	floor_constant_speed = false
	z_index = 5
	spawn_pos = global_position
	_spots = VArt.bake_spots(vehicle_id + 1, Rect2(-SHAPE_LEN * 0.5, -SHAPE_R * 2.0 - 12.0, SHAPE_LEN, 14.0), 9)
	_fx_hp = hp
	preload("res://scripts/item_label.gd").attach(self, LABEL, Color(0.95, 0.85, 0.5), LABEL_LIFT)
	_engine = AudioStreamPlayer2D.new()
	_engine.max_distance = 1400.0
	add_child(_engine)
	var src: AudioStream = load("res://assets/sfx/chainsaw-m.wav")
	if src is AudioStreamWAV:
		var st := (src as AudioStreamWAV).duplicate() as AudioStreamWAV
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		var bps: int = (2 if st.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if st.stereo else 1)
		st.loop_begin = 0
		st.loop_end = st.data.size() / bps
		_engine.stream = st


# ── Seats ─────────────────────────────────────────────

func driver() -> Node2D:
	return seats[0] if is_instance_valid(seats[0]) else null


func gunner() -> Node2D:
	return seats[1] if is_instance_valid(seats[1]) else null


func seat_of(s: Node) -> int:
	for i in seats.size():
		if seats[i] == s:
			return i
	return -1


func free_seat() -> int:
	for i in seats.size():
		if not is_instance_valid(seats[i]):
			return i
	return -1


func can_enter(s: Node2D) -> bool:
	if not alive or free_seat() < 0 or seat_of(s) >= 0:
		return false
	# Team modes: no climbing into the other team's occupied buggy.
	if Settings.is_team_mode():
		for o in seats:
			if is_instance_valid(o) and int(o.get("team")) != int(s.get("team")):
				return false
	return s.global_position.distance_to(global_position) < ENTER_RADIUS


# Called by the soldier who pressed F (their own peer). Routed through Main so
# the host picks the seat in multiplayer.
# Player F handler calls mount() on whatever _find_nearby_m2 returned.
func mount(s: Node2D) -> void:
	request_enter(s)


func request_enter(s: Node2D) -> void:
	var main := get_parent()
	if main != null and main.has_method("vehicle_request_seat"):
		main.vehicle_request_seat(self, s, true)


func request_exit(s: Node2D) -> void:
	var main := get_parent()
	if main != null and main.has_method("vehicle_request_seat"):
		main.vehicle_request_seat(self, s, false)


# Applied on every peer (Main.net_vehicle_seat).
func set_seat(seat: int, s: Node2D) -> void:
	if seat < 0 or seat >= seats.size():
		return
	_idle_t = 0.0   # #259: entering counts as touching
	var old = seats[seat]
	if is_instance_valid(old) and old != s and old.has_method("dismount_m2"):
		old.dismount_m2()
	seats[seat] = s
	if is_instance_valid(s) and s.has_method("mount_m2"):
		s.mount_m2(self)
		if s.has_method("_pickup_toast"):
			var tt: Array = _seat_toast(seat)
			s._pickup_toast(str(tt[0]), str(tt[1]), Color(0.95, 0.85, 0.5))
	_update_team()


## Toast on getting in: [title, how to use this seat].
func _seat_toast(seat: int) -> Array:
	return [LABEL, "A/D drive · aim + fire the gun · F to get out" if seat == 0 else "Gunner: aim + fire · F to get out"]


func clear_seat_of(s: Node2D) -> void:
	var i := seat_of(s)
	if i < 0:
		return
	seats[i] = null
	if is_instance_valid(s) and s.has_method("dismount_m2"):
		s.dismount_m2()
		# The F press that got us out must not also count as "F: get in" (or
		# "throw weapon") in the soldier's own input this frame.
		s.set("f_prev", true)
		# Step out beside the buggy, a little above the ground.
		s.global_position = global_position + Vector2(-face * 34.0, -26.0)
		s.set("velocity", velocity * 0.5 + Vector2(0, -120))
	_update_team()


func _update_team() -> void:
	var d := driver()
	var g := gunner()
	var o: Node2D = d if d != null else g
	team = int(o.get("team")) if o != null else -1
	display_name = str(o.get("display_name")) if o != null else LABEL.capitalize()


# ── Simulation ────────────────────────────────────────

func _local_id() -> int:
	return Net.local_id() if Net.is_networked() else 1


func _owner_peer(s: Node) -> int:
	if not is_instance_valid(s):
		return -1
	if not Net.is_networked():
		return 1
	return int(s.get_multiplayer_authority())


# Who runs the physics: the driver's peer, else the host.
func sim_peer() -> int:
	var d := driver()
	if d != null:
		return _owner_peer(d)
	return 1


func is_sim() -> bool:
	return not Net.is_networked() or sim_peer() == _local_id()


func _physics_process(delta: float) -> void:
	# Seats whose soldier died / left / was freed free up on every peer.
	for i in seats.size():
		var o = seats[i]
		if o != null and (not is_instance_valid(o) or o.get("dead") == true):
			seats[i] = null
			if is_instance_valid(o) and o.has_method("dismount_m2"):
				o.dismount_m2()
			_update_team()
	fire_cd = maxf(0.0, fire_cd - delta)
	_hop_cd = maxf(0.0, _hop_cd - delta)
	_solo_fire_t = maxf(0.0, _solo_fire_t - delta)
	heat = maxf(0.0, heat - HEAT_COOL * delta)
	if overheated and heat <= 0.25:
		overheated = false
	if not alive:
		_tick_dead(delta)
		return
	if is_sim():
		_simulate(delta)
		_send_state(delta)
		_touch_tick(delta)
	else:
		_follow(delta)
	_place_occupants()
	_record_hist()
	_local_occupant_input()
	if _is_host_side():
		_bot_gunner(delta)
		_runover()
		var kill_y: float = float(get_parent().get("KILL_Y")) if get_parent() != null and get_parent().get("KILL_Y") != null else INF
		if global_position.y > kill_y:
			_host_destroy(last_hitter, last_hitter_team)
	_engine_sound()
	_wheel_rot += velocity.x * delta / 11.0
	_redraw()


func _is_host_side() -> bool:
	return not Net.is_networked() or Net.is_host()


# ── Host-side lag compensation (#266) ──
# A remote human in a seat is tested where its shooter saw it (rewound), so the
# vehicle carrying it is too — else the hull, where the host has it now, stops
# rounds that met the crew on the shooter's screen.
var _hist: Array = []   # host: [ms, position, collision shape's global transform]
var _hull: CollisionShape2D = null


func _record_hist() -> void:
	if not Net.is_networked() or not Net.is_host():
		return
	if _hull == null:
		for c in get_children():
			if c is CollisionShape2D and (c as CollisionShape2D).shape is CapsuleShape2D:
				_hull = c
				break
	var now := Time.get_ticks_msec()
	_hist.append([now, global_position, _hull.global_transform if _hull != null else Transform2D()])
	while _hist.size() > 2 and now - int(_hist[0][0]) > HostHits.HIST_MS:
		_hist.pop_front()


## Host: index of the newest record at or before `ms_ago` ms ago, and how far
## toward the next one that moment lies ([i, t]); [-1, 0] with no history.
func _hist_at(ms_ago: int) -> Array:
	if _hist.is_empty():
		return [-1, 0.0]
	var want := Time.get_ticks_msec() - ms_ago
	var i := _hist.size() - 1
	while i > 0 and int(_hist[i][0]) > want:
		i -= 1
	if i >= _hist.size() - 1 or int(_hist[i][0]) > want:
		return [i, 0.0]
	var t0 := int(_hist[i][0])
	var t1 := int(_hist[i + 1][0])
	return [i, float(want - t0) / float(maxi(1, t1 - t0))]


## Host: where this vehicle was `ms_ago` ms ago (interpolated).
func pos_at(ms_ago: int) -> Vector2:
	var h := _hist_at(ms_ago)
	if ms_ago <= 0 or int(h[0]) < 0:
		return global_position
	var i: int = h[0]
	if float(h[1]) <= 0.0:
		return _hist[i][1]
	return (_hist[i][1] as Vector2).lerp(_hist[i + 1][1], float(h[1]))


## Host: a remote human is aboard (its hits are rewound, so this hull is too).
func carries_remote_human() -> bool:
	for o in seats:
		if is_instance_valid(o) and HostHits.is_remote_human(o):
			return true
	return false


## Where a segment a->b first enters this hull (0..1) — its collision capsule
## as it was `ms_ago` ms ago, turned as it was (a plane's follows its nose) —
## or -1.
func segment_t_at(a: Vector2, b: Vector2, ms_ago: int) -> float:
	if _hull == null or not _hull.shape is CapsuleShape2D:
		return -1.0
	var xf: Transform2D = _hull.global_transform
	var h := _hist_at(ms_ago)
	if ms_ago > 0 and int(h[0]) >= 0:
		var i: int = h[0]
		xf = _hist[i][2]
		if float(h[1]) > 0.0:
			xf = xf.interpolate_with(_hist[i + 1][2], float(h[1]))
	# In the capsule's own frame it stands upright: a core box with a cap at
	# each end.
	var inv := xf.affine_inverse()
	var la := inv * a
	var lb := inv * b
	var cap := _hull.shape as CapsuleShape2D
	var r := cap.radius
	var half := maxf(0.0, cap.height * 0.5 - r)
	var best := -1.0
	var tr: float = preload("res://scripts/bullet.gd").segment_rect_t(la, lb, Rect2(-r, -half, r * 2.0, half * 2.0))
	if tr >= 0.0:
		best = tr
	for cy in [-half, half]:
		var tc := _segment_circle_t(la, lb, Vector2(0.0, cy), r)
		if tc >= 0.0 and (best < 0.0 or tc < best):
			best = tc
	return best


static func _segment_circle_t(a: Vector2, b: Vector2, c: Vector2, r: float) -> float:
	var d := b - a
	var f := a - c
	var qa := d.dot(d)
	if qa < 0.000001:
		return 0.0 if f.length() <= r else -1.0
	var qb := 2.0 * f.dot(d)
	var qc := f.dot(f) - r * r
	if qc <= 0.0:
		return 0.0   # starts inside
	var disc := qb * qb - 4.0 * qa * qc
	if disc < 0.0:
		return -1.0
	var t := (-qb - sqrt(disc)) / (2.0 * qa)
	return t if t >= 0.0 and t <= 1.0 else -1.0


## #259: abandoned or wedged vehicles don't stay that way. Runs on whichever
## peer simulates this body. While occupied (or recently damaged/entered) the
## clock stays at zero; an empty vehicle displaced from its spawn for
## idle_respawn_time goes home through the same respawn RPC a wreck uses.
## A driver who's throttling into something without moving gets lifted out of
## the terrain (unstick) after a few seconds — teleporting an OCCUPIED vehicle
## would be jarring, so the full reset only ever fires while empty.
func _touch_tick(delta: float) -> void:
	var occupied := false
	for o in seats:
		if o != null and is_instance_valid(o):
			occupied = true
			break
	if occupied:
		_idle_t = 0.0
		_stuck_t = maxf(0.0, _stuck_t - delta)
		return
	_idle_t += delta
	# Stuck-while-driven tracking lives in _simulate where throttle is known;
	# for the empty case only the idle clock matters.
	if _is_host_side() and idle_respawn_time > 0.0 and _idle_t >= idle_respawn_time \
			and global_position.distance_to(spawn_pos) > 24.0:
		_idle_t = 0.0
		var main := get_parent()
		if main != null and main.has_method("vehicle_send"):
			main.vehicle_send("net_vehicle_respawn", [vehicle_id], true)
		else:
			apply_respawn()


func _simulate(delta: float) -> void:
	var throttle := 0.0
	var hop := false
	var d := driver()
	if d != null and _owner_peer(d) == _local_id() and _is_local_human(d):
		throttle = Input.get_axis("move_left", "move_right")
		hop = Input.is_action_pressed("jump")
	elif d != null and d.get("bot_id") != null and _is_host_side():
		var bi := _bot_drive(delta)
		throttle = bi.x
		hop = bi.y > 0.5
	var on_floor := is_on_floor()
	# #259: after an idle respawn, once the body has settled at rest, adopt
	# that spot as home — otherwise a spawn recorded mid-fall re-triggers the
	# idle reset every cycle (gentle 60 s bobbing).
	if _adopt_settle and on_floor and velocity.length() < 8.0:
		_adopt_settle = false
		spawn_pos = global_position
	# #259: driver wants to move, we're grounded, but nothing is happening —
	# count it up and lift the body out of whatever it's wedged in.
	if throttle != 0.0 and on_floor and absf(velocity.x) < 8.0 and absf(velocity.y) < 20.0:
		_stuck_t += delta
		if _stuck_t >= STUCK_UNSTICK_TIME:
			_stuck_t = 0.0
			unstick()
	else:
		_stuck_t = maxf(0.0, _stuck_t - delta * 2.0)
	if on_floor:
		if throttle != 0.0:
			var cap: float = MAX_SPEED if signf(throttle) == face or absf(velocity.x) < 30.0 else REVERSE_SPEED
			if _solo_fire_t > 0.0:
				cap *= SOLO_FIRE_SPEED
			if signf(velocity.x) != 0.0 and signf(velocity.x) != signf(throttle):
				velocity.x = move_toward(velocity.x, 0.0, BRAKE * delta)
			else:
				velocity.x = move_toward(velocity.x, throttle * cap, ACCEL * delta)
			if absf(velocity.x) > 40.0 and signf(velocity.x) == signf(throttle):
				face = signf(throttle)
		else:
			velocity.x = move_toward(velocity.x, 0.0, ROLL_DRAG * delta)
		if hop and _hop_cd <= 0.0 and HOP_VEL < 0.0:
			velocity.y = HOP_VEL * MatchConfig.mod_gravity()
			_hop_cd = 0.9
			Sfx.jump(global_position)
	else:
		velocity.x = move_toward(velocity.x, throttle * MAX_SPEED, ACCEL * AIR_CONTROL * delta)
	var was_air := not on_floor
	var fall_v := velocity.y
	velocity.y = minf(velocity.y + GRAVITY * MatchConfig.mod_gravity() * delta, 1400.0)
	move_and_slide()
	# Wheels roll up curbs and small lips instead of jumping them: when the
	# buggy is blocked while driving on the ground, lift it onto the step if
	# there's room above and ahead.
	# Only a near-vertical face counts as a curb, so steep slopes stay steep.
	if on_floor and throttle != 0.0 and is_on_wall() and STEP_UP > 0.0 and absf(get_wall_normal().y) < 0.25:
		var ahead := Vector2(signf(throttle) * 6.0, 0.0)
		for h in [4.0, 8.0, 12.0, STEP_UP]:
			var up := global_transform.translated(Vector2(0.0, -h))
			if not test_move(global_transform, Vector2(0.0, -h)) and not test_move(up, ahead):
				global_position += Vector2(ahead.x, -h)
				break
	if is_on_floor() and was_air and fall_v > 520.0:
		Sfx.land(global_position, true)
	# Visual tilt follows the ground; in the air it eases toward level.
	var target_tilt := 0.0
	if is_on_floor():
		var n := get_floor_normal()
		target_tilt = n.angle() + PI / 2.0
	else:
		target_tilt = clampf(velocity.y * 0.0006 * face, -0.5, 0.5)
	_tilt = lerp_angle(_tilt, target_tilt, clampf(delta * 10.0, 0.0, 1.0))


func _follow(delta: float) -> void:
	if _target_pos == Vector2.INF:
		return
	_target_pos += _target_vel * delta
	global_position = global_position.lerp(_target_pos, clampf(delta * 14.0, 0.0, 1.0))
	velocity = _target_vel


func _send_state(delta: float) -> void:
	if not Net.is_networked():
		return
	_net_t -= delta
	if _net_t > 0.0:
		return
	_net_t = 0.05
	var main := get_parent()
	if main != null and main.has_method("vehicle_send"):
		main.vehicle_send("net_vehicle_state", [vehicle_id, global_position, velocity, _tilt, face, aim_dir], false)


# Remote state (Main.net_vehicle_state).
func apply_state(pos: Vector2, vel: Vector2, tilt: float, f: float, aim: Vector2) -> void:
	if is_sim():
		return
	state_rx += 1
	if _target_pos == Vector2.INF or pos.distance_to(global_position) > 300.0:
		global_position = pos
	_target_pos = pos
	_target_vel = vel
	_tilt = tilt
	face = f
	aim_dir = aim


func _seat_world(i: int) -> Vector2:
	var off: Vector2 = SEATS[i]
	off.x *= face
	return global_position + off.rotated(_tilt)


func _place_occupants() -> void:
	for i in seats.size():
		var o = seats[i]
		if not is_instance_valid(o):
			continue
		o.global_position = _seat_world(i)
		o.set("velocity", Vector2.ZERO)
		o.set("facing", face if i == 0 else (1.0 if aim_dir.x >= 0.0 else -1.0))


func _is_local_human(s: Node) -> bool:
	var main := get_parent()
	return main != null and main.get("player") == s


# Exit / aim / fire for whoever is sitting in this buggy on this machine.
func _local_occupant_input() -> void:
	var me: Node2D = null
	var my_seat := -1
	for i in seats.size():
		if is_instance_valid(seats[i]) and _is_local_human(seats[i]) and _owner_peer(seats[i]) == _local_id():
			me = seats[i]
			my_seat = i
	if me == null:
		_f_prev = true
		return
	if me.get("input_locked") == true:
		return
	var f_now := Input.is_action_pressed("weapon_throw")
	if f_now and not _f_prev:
		_f_prev = f_now
		request_exit(me)
		return
	_f_prev = f_now
	_occupant_controls(me, my_seat)


## Aim / fire for the local human in `my_seat` (exit is handled above).
func _occupant_controls(me: Node2D, my_seat: int) -> void:
	# The gunner owns the gun; a driver alone gets it too.
	var gun_owner := 1 if gunner() != null else 0
	if my_seat != gun_owner:
		return
	aim_dir = _read_aim(me)
	if Input.is_action_pressed("fire") and fire_cd <= 0.0 and not overheated:
		_fire(me)


func _read_aim(me: Node2D) -> Vector2:
	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down", 0.2)
	var a := aim_dir
	if stick.length() > 0.0:
		a = stick.normalized()
	elif TouchControls.instance != null and TouchControls.instance.aim_dir.length() > 0.001:
		a = TouchControls.instance.aim_dir.normalized()
	else:
		var to_m: Vector2 = me.get_global_mouse_position() - _gun_pivot()
		if to_m.length() > 1.0:
			a = to_m.normalized()
	# Can't shoot down through the chassis.
	if a.y > 0.55:
		a = Vector2(signf(a.x) if absf(a.x) > 0.01 else face, 0.55).normalized()
	return a


func _gun_pivot() -> Vector2:
	var off := Vector2(-18.0 * face, -28.0)
	return global_position + off.rotated(_tilt)


func _fire(me: Node2D) -> void:
	var muzzle := _gun_pivot() + aim_dir * 24.0
	var spread := GUN_SPREAD
	if gunner() == null and me == driver():
		spread *= SOLO_FIRE_SPREAD
		_solo_fire_t = 0.3
	var dir := aim_dir.rotated(randf_range(-spread, spread))
	fire_cd = GUN_RATE
	var main := get_parent()
	if Net.is_networked() and main != null and main.has_method("vehicle_send"):
		main.vehicle_send("net_vehicle_fire", [vehicle_id, muzzle, dir, HostHits.game_ms()], true)
		return
	apply_fire(muzzle, dir)


# Every peer spawns the round (damage is applied by each victim's owner).
func apply_fire(muzzle: Vector2, dir: Vector2) -> void:
	fire_cd = GUN_RATE
	var shooter: Node2D = gunner() if gunner() != null else driver()
	if shooter == null:
		return
	var b = preload("res://scenes/bullet.tscn").instantiate()
	b.global_position = muzzle
	b.direction = dir
	b.speed = GUN_SPEED
	b.damage = GUN_DAMAGE * MatchConfig.mod_damage()
	b.team = int(shooter.get("team"))
	b.killer_name = str(shooter.get("display_name"))
	b.weapon_name = "Buggy MG"
	b.ignore_bodies = [self] + seats.filter(func(o): return is_instance_valid(o))
	# #266: the gun isn't predicted — its shooter sees the round only once the
	# host has relayed it, against bodies one hop behind the host's, i.e. where
	# the host has them now: no rewind.
	b.rewind_override = 0
	get_parent().add_child(b)
	# Cosmetic: muzzle flash (pooled light + star), brass, the barrel kicks.
	Gfx.muzzle(get_parent(), muzzle, false, dir)
	Gfx.casing(get_parent(), _gun_pivot(), 1.0 if dir.x >= 0.0 else -1.0)
	_gun_kick = 3.0
	if not Sfx._throttle("buggy_mg_%d" % vehicle_id, 60):
		pass
	else:
		Sfx._play_key("m2fire", -8.0, preload("res://scripts/gfx.gd").rf(0.97, 1.03), muzzle)
	heat += HEAT_PER_SHOT
	if heat >= 1.0 and not overheated:
		overheated = true
		Sfx._play_key("m2overheat", -6.0, 1.0, muzzle)


# A bot at the wheel (host / single-player): drive toward its goal, hop when
# blocked, stop and get out at the destination, in front of a drop into the
# void, when stuck, or when the buggy is nearly wrecked. Returns (throttle, hop).
func _bot_drive(delta: float) -> Vector2:
	var d := driver()
	var goal: Vector2 = d.get("_goal")
	var t = d.get("target")
	if goal == Vector2.INF and t != null and is_instance_valid(t):
		goal = (t as Node2D).global_position
	var dx: float = goal.x - global_position.x if goal != Vector2.INF else 0.0
	var leave := goal == Vector2.INF or absf(dx) < 260.0 or hp < MAX_HP * 0.25
	var dir: float = signf(dx)
	# Don't drive off into the void.
	var main := get_parent()
	if not leave and main != null and main.has_method("_geom_ground_y") and absf(velocity.x) > 20.0:
		var ky: float = float(main.get("KILL_Y"))
		var gy: float = main._geom_ground_y(global_position.x + dir * 70.0, global_position.y - 30.0)
		if gy == INF or gy > ky:
			leave = true
	# Stuck: not getting anywhere for a while (hop once, then give up).
	_bd_check += delta
	if _bd_check > 1.0:
		var moved: float = absf(global_position.x - _bd_last_x)
		_bd_last_x = global_position.x
		_bd_check = 0.0
		if moved < 40.0:
			_bd_stuck_t += 1.0
			_bd_hop = true
		else:
			_bd_stuck_t = 0.0
	if _bd_stuck_t >= 3.0:
		leave = true
	if leave and absf(velocity.x) < 60.0:
		_bd_stuck_t = 0.0
		if Net.is_networked() and main != null and main.has_method("net_vehicle_seat_bot"):
			main.bcast("net_vehicle_seat_bot", [vehicle_id, 0, int(d.get("bot_id")), false], true)
		else:
			clear_seat_of(d)
		return Vector2.ZERO
	var hop := 1.0 if _bd_hop else 0.0
	_bd_hop = false
	# A bot driving alone shoots what it sees (with the solo penalty).
	if gunner() == null and t != null and is_instance_valid(t) and d.get("_target_visible") == true:
		var to: Vector2 = (t as Node2D).global_position - _gun_pivot()
		var want := _aim_solution(to)
		if to.length() < BOT_GUN_RANGE * 0.8 and want != Vector2.ZERO and want.y < 0.55:
			aim_dir = aim_dir.slerp(want, clampf(delta * 6.0, 0.0, 1.0)).normalized()
			if fire_cd <= 0.0 and not overheated and heat < 0.7 and absf(aim_dir.angle_to(want)) < 0.15:
				_fire(d)
	return Vector2(0.0 if leave else dir, hop)


# A bot in the gun seat (host / single-player): aim at its target with lead,
# fire in bursts and let the barrel cool before it overheats. Hops out if
# the driver leaves.
func _bot_gunner(delta: float) -> void:
	var g := gunner()
	if g == null or g.get("bot_id") == null:
		_no_driver_t = 0.0
		return
	if driver() == null:
		_no_driver_t += delta
		if _no_driver_t > 1.5:
			_no_driver_t = 0.0
			var main := get_parent()
			if Net.is_networked() and main != null and main.has_method("net_vehicle_seat_bot"):
				main.bcast("net_vehicle_seat_bot", [vehicle_id, 1, int(g.get("bot_id")), false], true)
			else:
				clear_seat_of(g)
		return
	_no_driver_t = 0.0
	var t = g.get("target")
	if t == null or not is_instance_valid(t) or t.get("dead") == true or seat_of(t) >= 0:
		return
	var piv := _gun_pivot()
	var to: Vector2 = (t as Node2D).global_position + Vector2(0, -6) - piv
	if to.length() > BOT_GUN_RANGE or g.get("_target_visible") != true:
		return
	if t is CharacterBody2D:
		to += (t as CharacterBody2D).velocity * (to.length() / GUN_SPEED)
	var want := _aim_solution(to)
	if want == Vector2.ZERO or not _aim_ok(want):
		return   # out of reach / can't depress that far
	aim_dir = aim_dir.slerp(want, clampf(delta * 7.0, 0.0, 1.0)).normalized()
	if heat > 0.85:
		_bot_hold = true
	elif heat < 0.3:
		_bot_hold = false
	if not overheated and not _bot_hold and fire_cd <= 0.0 and absf(aim_dir.angle_to(want)) < 0.12:
		_fire(g)


## Whether the gun can point that way (the buggy can't shoot down through its
## own chassis; the helicopter's door gun can't shoot up through the rotor).
func _aim_ok(want: Vector2) -> bool:
	return want.y <= 0.55


# Direction to fire to hit something at `to` (relative to the gun). Straight
# for the machine gun; the tank overrides it with a lobbed-shell solution.
func _aim_solution(to: Vector2) -> Vector2:
	return to.normalized()


# Run over enemies at speed (host / single-player decides).
func _runover() -> void:
	var d := driver()
	if d == null or absf(velocity.x) < RUNOVER_MIN_SPEED:
		return
	var now := Time.get_ticks_msec()
	for s in get_tree().get_nodes_in_group("soldier"):
		if not is_instance_valid(s) or s.get("dead") == true or seat_of(s) >= 0:
			continue
		var rel: Vector2 = (s as Node2D).global_position - global_position
		if absf(rel.x) > 38.0 or rel.y < -44.0 or rel.y > 14.0:
			continue
		if int(s.get("team")) == int(d.get("team")) and not MatchConfig.friendly_fire_on():
			continue
		if now - int(_runover_cd.get(s.get_instance_id(), 0)) < 500:
			continue
		_runover_cd[s.get_instance_id()] = now
		var dmg: float = absf(velocity.x) * RUNOVER_DMG_PER_SPEED
		var main := get_parent()
		if main != null and main.has_method("vehicle_hit_soldier"):
			main.vehicle_hit_soldier(s, dmg, str(d.get("display_name")), int(d.get("team")), velocity, LABEL.capitalize())


# ── Damage ────────────────────────────────────────────

func take_damage(amount: float, killer := "", weapon := "", killer_team := -1) -> void:
	if not alive or not _is_host_side():
		return
	# Occupants' own team can't wreck it (friendly fire off).
	if killer_team >= 0 and killer_team == team and not MatchConfig.friendly_fire_on() and team >= 0:
		return
	if not (weapon in EXPLOSIVE_WEAPONS):
		amount *= BULLET_ARMOR
	hp -= amount
	_idle_t = 0.0   # #259: taking a hit counts as touching
	if killer != "":
		last_hitter = killer
		last_hitter_team = killer_team
	# #246: a hosed vehicle used to fire a reliable RPC per bullet (~15/s for
	# a Minigun) on the same channel as the state streams. Only sync HP once
	# it has moved meaningfully; the destroy path always sends.
	var main := get_parent()
	if hp <= 0.0:
		if main != null and main.has_method("vehicle_send"):
			main.vehicle_send("net_vehicle_hp", [vehicle_id, hp], true)
		_host_destroy(last_hitter, last_hitter_team)
		return
	if absf(_last_sent_hp - hp) >= MAX_HP * 0.05:
		_last_sent_hp = hp
		if main != null and main.has_method("vehicle_send"):
			main.vehicle_send("net_vehicle_hp", [vehicle_id, hp], true)


func apply_hp(v: float) -> void:
	hp = v


## `violent`: the crew dies with it (always, for buggies and tanks); a
## helicopter that comes down gently ejects them instead (#277).
func _host_destroy(killer: String, killer_team: int, violent := true) -> void:
	if not alive:
		return
	var main := get_parent()
	if main != null and main.has_method("vehicle_send"):
		main.vehicle_send("net_vehicle_destroy", [vehicle_id, global_position, killer, killer_team, violent], true)
	else:
		apply_destroy(global_position, killer, killer_team, false, violent)


# Every peer: blast, eject/kill occupants, hide, start the respawn timer.
func apply_destroy(at: Vector2, killer: String, killer_team: int, quiet := false, violent := true) -> void:
	if not alive:
		return
	alive = false
	hp = 0.0
	global_position = at
	var occupants: Array = []
	for i in seats.size():
		if is_instance_valid(seats[i]):
			occupants.append(seats[i])
			if seats[i].has_method("dismount_m2"):
				seats[i].dismount_m2()
		seats[i] = null
	_update_team()
	_respawn_t = RESPAWN_TIME
	velocity = Vector2.ZERO
	collision_layer = 0
	if quiet:   # a late joiner mirroring an already-burnt wreck
		return
	Sfx.explode(at)
	Sfx._play_key("m2explode", -2.0, 0.9, at)
	if get_parent() != null:
		preload("res://scripts/gfx.gd").explosion(get_parent(), at, 140.0)
	var kname: String = killer if killer != "" else WRECK_WEAPON
	for s in get_tree().get_nodes_in_group("soldier"):
		if not is_instance_valid(s) or s.get("dead") == true:
			continue
		var dist: float = (s as Node2D).global_position.distance_to(at)
		var dmg := 0.0
		if s in occupants:
			dmg = 999.0 if violent else EJECT_DMG
			if not violent:
				_eject(s, occupants.find(s))
		elif dist < EXPLODE_RADIUS:
			dmg = EXPLODE_DAMAGE * (1.0 - dist / EXPLODE_RADIUS)
		if dmg <= 0.0:
			continue
		HostHits.damage(s, dmg, kname, WRECK_WEAPON, killer_team)
	_respawn_t = RESPAWN_TIME
	_smoke_t = 0.0
	velocity = Vector2.ZERO
	collision_layer = 0
	# Cosmetic: hull panels + burning bits + a smoke column (pooled, #276).
	_wreck_t = 0.0
	var w = _fxw()
	if w != null and VArt.level() >= 1:
		w.vehicle_wreck(at + Vector2(0, -SHAPE_R), EXPLODE_RADIUS * 0.8, _team_color())


## A survivor thrown clear of a gentle wreck (every peer; the owner's copy is
## the one that counts — replicas get corrected by the owner's stream).
func _eject(s: Node2D, i: int) -> void:
	var side := -1.0 if i % 2 == 0 else 1.0
	s.global_position = global_position + Vector2(side * 36.0, -22.0)
	s.set("velocity", Vector2(side * 170.0, -260.0))


func _tick_dead(delta: float) -> void:
	_engine.stop()
	_smoke_t += delta
	_redraw()
	if not _is_host_side():
		return
	_respawn_t -= delta
	if _respawn_t <= 0.0:
		var main := get_parent()
		if main != null and main.has_method("vehicle_send"):
			main.vehicle_send("net_vehicle_respawn", [vehicle_id], true)
		else:
			apply_respawn()


# Lift out of any terrain we start inside (bad spot, editor maps): a body that
# starts overlapping gets pushed the wrong way and wedges in the floor.
func unstick() -> void:
	var cs: CollisionShape2D = null
	for c in get_children():
		if c is CollisionShape2D:
			cs = c
	if cs == null or not is_inside_tree():
		return
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = cs.shape
	q.collision_mask = collision_mask
	q.exclude = [get_rid()]
	var space := get_world_2d().direct_space_state
	for _i in 60:
		q.transform = cs.global_transform
		if space.intersect_shape(q, 1).is_empty():
			return
		global_position.y -= 4.0


func apply_respawn() -> void:
	respawns += 1
	alive = true
	hp = MAX_HP
	_last_sent_hp = MAX_HP
	_idle_t = 0.0
	_stuck_t = 0.0
	heat = 0.0
	overheated = false
	global_position = spawn_pos
	velocity = Vector2.ZERO
	_tilt = 0.0
	unstick()
	_target_pos = Vector2.INF
	collision_layer = 8
	last_hitter = ""
	last_hitter_team = -1


# Rockets / grenades (called from their blast code on every peer; the host's
# copy is the one that counts).
static func splash(tree: SceneTree, at: Vector2, radius: float, dmg: float, killer: String, weapon: String, killer_team: int) -> void:
	for v in tree.get_nodes_in_group("vehicle"):
		if not is_instance_valid(v) or not v.get("alive"):
			continue
		var d: float = (v as Node2D).global_position.distance_to(at)
		if d < radius + 20.0:
			v.take_damage(dmg * float(v.get("EXPLOSIVE_MUL")) * (1.0 - clampf(d - 20.0, 0.0, radius) / radius), killer, weapon, killer_team)


# ── Presentation (#276) ───────────────────────────────
# Everything below is COSMETIC: it reads the replicated state (position,
# velocity, tilt, face, hp, alive, seats, heat, fire_cd) and only draws or
# spawns pooled effects (FxWorld / Atmosphere light pool, Gfx.rng). Nothing
# here touches physics, net state, timers or the gameplay random stream.

func _engine_sound() -> void:
	if _engine.stream == null or Settings.sfx_volume <= 0.0:
		return
	var running := driver() != null
	if not running:
		if _engine.playing:
			_engine.stop()
		return
	if not _engine.playing:
		_engine.play()
	var sp: float = clampf(absf(velocity.x) / MAX_SPEED, 0.0, 1.0)
	_engine.pitch_scale = ENGINE_PITCH + sp * 0.6
	_engine.volume_db = -20.0 + sp * 6.0 + linear_to_db(clampf(Settings.sfx_volume, 0.0001, 1.0))


func _team_mode() -> bool:
	return team >= 0 and Settings.is_team_mode()


# Hull paint: the kind's drab base nudged toward the team (VehicleArt.paint).
func _team_color() -> Color:
	return VArt.paint(PAINT_BASE, team, _team_mode())


func _process(delta: float) -> void:
	_fx_tick(delta)


## Redraw only while on (or near) the screen: an off-screen vehicle's drawing
## is never seen, and it is the costliest thing a vehicle does per frame.
func _redraw() -> void:
	if _onscr or draws == 0:
		queue_redraw()


func _on_screen() -> bool:
	var vp := get_viewport()
	var cam := vp.get_camera_2d() if vp != null else null
	if cam == null:
		return true
	var half := vp.get_visible_rect().size * 0.5 / cam.zoom
	var c := cam.get_screen_center_position()
	var m := 140.0 + SHADOW_REACH
	return absf(global_position.x - c.x) < half.x + m and absf(global_position.y - c.y) < half.y + m


func _fxw() -> Object:
	var w = FxWorld.current
	return w if w != null and is_instance_valid(w) and w.is_inside_tree() else null


func _dmg() -> float:
	return clampf(1.0 - hp / maxf(1.0, MAX_HP), 0.0, 1.0)


## Wheel frame (ground contact, follows the ground tilt) and body frame (rides
## the suspension: bob + pitch) for this frame's draw.
func _frames() -> void:
	_xf_w = Transform2D(_tilt, Vector2(face, 1.0), 0.0, Vector2.ZERO)
	_xf_b = _xf_w * Transform2D(_pitch, Vector2(0.0, _susp))


func _world_pt(local: Vector2, body := true) -> Vector2:
	return global_position + (_xf_b if body else _xf_w) * local


func _fx_tick(delta: float) -> void:
	var dt := minf(delta, 0.05)
	if dt <= 0.0:
		return
	# Suspension: landings compress the springs, throttle / brakes pitch the
	# body, rough ground jiggles it with speed.
	var drop := _fx_prev_v.y - velocity.y
	if alive and drop > 140.0:
		_susp_v += minf(drop, 900.0) * 0.03
	_susp_v += (-_susp * 170.0 - _susp_v * 11.0) * dt
	_susp = clampf(_susp + _susp_v * dt, -3.0, SUSP_MAX)
	var ax := (velocity.x - _fx_prev_v.x) / dt
	var want_pitch := clampf(-ax * face * 0.00008, -0.06, 0.06) if alive else 0.0
	_pitch = lerpf(_pitch, want_pitch, clampf(dt * 6.0, 0.0, 1.0))
	_fx_prev_v = velocity
	_gun_kick = maxf(0.0, _gun_kick - dt * 40.0)
	_fx_time += dt
	var was := _onscr
	_onscr = _on_screen()
	if _onscr and not was:
		queue_redraw()
	if not alive:
		_wreck_t += dt
	else:
		_wreck_t = 0.0
	_frames()
	var lv := VArt.level()
	# A hit: sparks off the hull (and the cinematic flash uniform).
	var took := hp < _fx_hp - 0.5 and alive
	_fx_hp = hp
	_hit_flash = maxf(0.0, _hit_flash - dt)
	if took:
		_hit_flash = 0.05
	_set_hit_flash(_hit_flash > 0.0)
	if lv == 0 or get_parent() == null:
		return
	var w = _fxw()
	if w == null:
		return
	var r := Gfx.rng
	if took:
		var hp_pt := _world_pt(Vector2(r.randf_range(-SHAPE_LEN * 0.4, SHAPE_LEN * 0.4), -SHAPE_R * 2.0 + r.randf_range(-6, 4)))
		w.vehicle_sparks(hp_pt, Vector2(0, -1).rotated(r.randf_range(-1.0, 1.0)), 4 if lv >= 2 else 2)
	if not alive:
		_fx_wreck(w, dt, lv)
		return
	_fx_running(w, dt, lv)
	_fx_damage(w, dt, lv)


## Exhaust, wheel dust, headlights while someone's in it.
func _fx_running(w: Object, dt: float, lv: int) -> void:
	var r := Gfx.rng
	var spd := absf(velocity.x)
	var running := driver() != null
	_fx_exhaust_t -= dt
	if running and _fx_exhaust_t <= 0.0:
		_fx_exhaust_t = (0.07 if lv >= 2 else 0.13) * r.randf_range(0.8, 1.2)
		var ex := _world_pt(EXHAUST_PT)
		var heavy := clampf(absf((velocity.x - _fx_prev_v.x)) * 0.02 + spd / MAX_SPEED * 0.5, 0.0, 1.0)
		w.smoke(ex, Vector2(-face * r.randf_range(20, 50) - velocity.x * 0.2, r.randf_range(-40, -18)), r.randf_range(5.0, 8.0) * (1.0 + heavy * 0.6),
			r.randf_range(0.5, 0.9), Color(0.42, 0.42, 0.42, 0.22 + heavy * 0.1))
	_fx_dust_t -= dt
	if spd > 110.0 and absf(velocity.y) < 80.0 and _fx_dust_t <= 0.0:
		_fx_dust_t = (0.05 if lv >= 2 else 0.1)
		var k := clampf(spd / MAX_SPEED, 0.0, 1.0)
		for wx in DUST_X:
			w.wheel_dust(_world_pt(Vector2(wx, -1.0), false), velocity.x, k)
	if running:
		var lamp := _world_pt(HEADLIGHT_PT)
		var dir := (_xf_b.basis_xform(Vector2(1.0, 0.1))).normalized()
		Atmosphere.light_keep(get_instance_id() * 8 + 1, lamp + dir * HEADLIGHT_LEN * 0.6, Color(1.0, 0.9, 0.7), HEADLIGHT_LEN * 0.7, 0.55)


## Damage states: sparks (< 70 %), engine smoke (< 45 %), fire (< 25 %).
func _fx_damage(w: Object, dt: float, lv: int) -> void:
	var d := _dmg()
	if d < 0.3:
		return
	var r := Gfx.rng
	var eng := _world_pt(ENGINE_PT)
	_fx_spark_t -= dt
	if _fx_spark_t <= 0.0:
		_fx_spark_t = r.randf_range(0.5, 1.6) * (1.2 - d)
		w.vehicle_sparks(eng + Vector2(r.randf_range(-8, 8), r.randf_range(-4, 4)), Vector2(0, -1), 3 if lv >= 2 else 2)
	if d >= 0.55:
		_fx_smoke_t -= dt
		if _fx_smoke_t <= 0.0:
			_fx_smoke_t = (0.09 if lv >= 2 else 0.16)
			var dark := clampf((d - 0.55) / 0.35, 0.0, 1.0)
			w.smoke(eng, Vector2(r.randf_range(-15, 15) - velocity.x * 0.3, r.randf_range(-60, -30)), r.randf_range(9.0, 14.0),
				r.randf_range(0.9, 1.5), Color(0.4, 0.4, 0.4, 0.3).lerp(Color(0.06, 0.06, 0.06, 0.5), dark))
	if d >= 0.75:
		_fx_fire_t -= dt
		if _fx_fire_t <= 0.0:
			_fx_fire_t = (0.1 if lv >= 2 else 0.18)
			w.vehicle_burn(eng, clampf((d - 0.75) * 4.0, 0.3, 1.0))
		Atmosphere.light_keep(get_instance_id() * 8 + 2, eng + Vector2(0, -8), Color(1.0, 0.5, 0.2), 90.0, 0.55 + 0.25 * sin(_fx_time * 23.0))


## Burnt husk: burns hard for a few seconds, then smoulders until respawn.
func _fx_wreck(w: Object, dt: float, lv: int) -> void:
	var r := Gfx.rng
	var core := _world_pt(ENGINE_PT * 0.5 + Vector2(0, 4))
	_fx_fire_t -= dt
	if _fx_fire_t <= 0.0:
		if _wreck_t < 7.0:
			_fx_fire_t = (0.1 if lv >= 2 else 0.2)
			w.vehicle_burn(core + Vector2(r.randf_range(-SHAPE_LEN * 0.3, SHAPE_LEN * 0.3), 0), clampf(1.0 - _wreck_t / 7.0, 0.3, 1.0))
		else:
			_fx_fire_t = r.randf_range(0.35, 0.6)
			w.smoke(core + Vector2(r.randf_range(-10, 10), -6), Vector2(r.randf_range(-10, 10), r.randf_range(-45, -25)), r.randf_range(12.0, 18.0),
				r.randf_range(1.6, 2.4), Color(0.12, 0.12, 0.12, 0.35))
	if _wreck_t < 8.0:
		Atmosphere.light_keep(get_instance_id() * 8 + 2, core + Vector2(0, -10), Color(1.0, 0.48, 0.18),
			140.0 * clampf(1.0 - _wreck_t / 8.0, 0.2, 1.0), 0.7 + 0.3 * sin(_fx_time * 19.0))


func _set_hit_flash(on: bool) -> void:
	if on == _flash_on:
		return
	var sm := material as ShaderMaterial
	if sm == null or sm.shader != _RIM_SHADER:
		_flash_on = false
		return
	set_instance_shader_parameter("flash", 0.35 if on else 0.0)
	_flash_on = on


# ── drawing ───────────────────────────────────────────

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


## Low quality has no particle pools: a couple of drawn puffs keep a damaged
## or burnt-out vehicle readable.
func _draw_lofi_smoke(n: int) -> void:
	for i in n:
		var t := fmod(_fx_time * 0.6 + i * 0.2, 1.0)
		draw_circle(Vector2(sin(i * 1.7 + _fx_time) * 8.0, -20.0 - t * 70.0), 6.0 + t * 10.0, Color(0.2, 0.2, 0.2, 0.35 * (1.0 - t)))


static func _buggy_shapes() -> Dictionary:
	if not _BS.is_empty():
		return _BS
	_BS["tub"] = VArt.pv([Vector2(-30, -12), Vector2(-33, -20), Vector2(-20, -23), Vector2(18, -23), Vector2(30, -19), Vector2(32, -12), Vector2(18, -10), Vector2(-18, -10)])
	_BS["shell"] = VArt.pv([Vector2(-37, -18), Vector2(-35, -27), Vector2(-14, -28), Vector2(-4, -33), Vector2(16, -34), Vector2(30, -27),
		Vector2(40, -21), Vector2(39, -16), Vector2(22, -18), Vector2(-28, -17)])
	_BS["engine"] = VArt.pv([Vector2(-45, -19), Vector2(-45, -30), Vector2(-33, -31), Vector2(-31, -19)])
	_BS["stripe"] = VArt.pv([Vector2(-35, -23), Vector2(37, -21.5), Vector2(38.5, -19), Vector2(-36, -20.5)])
	_BS["top"] = VArt.pv([Vector2(-35, -27), Vector2(-14, -28), Vector2(-4, -33), Vector2(16, -34), Vector2(30, -27), Vector2(40, -21)])
	_BS["seat"] = VArt.pv([Vector2(-6, -42), Vector2(-2, -42), Vector2(0, -29), Vector2(-5, -29)])
	for k in ["tub", "shell", "engine"]:
		_BS[k + "_n"] = VArt.normals(_BS[k])
	return _BS


func _cols(key: String, pts: PackedVector2Array, top: Color, bottom: Color, y0: float, y1: float) -> PackedColorArray:
	# Gradient colours per hull piece, rebuilt only when the paint changes.
	var c = _col_cache.get(key)
	if c == null or c[0] != top or c[1] != bottom:
		c = [top, bottom, VArt.vgrad(pts, top, bottom, y0, y1)]
		_col_cache[key] = c
	return c[2]


func _draw_hull(lv: int) -> void:
	var S := _buggy_shapes()
	var paint := _team_color()
	var trim := VArt.trim(team, _team_mode())
	var cine := VArt.cinematic()
	var steel := VArt.STEEL if cine else VArt.STEEL.lightened(0.12)
	var line := Color(0.02, 0.02, 0.025, 0.9)
	var spd := velocity.x
	var running := driver() != null
	# Wheel frame: tyres, suspension arms + springs (body pivots ride the bob).
	draw_set_transform_matrix(_xf_w)
	var bt := Transform2D(_pitch, Vector2(0.0, _susp))
	for wx in [-22.0, 22.0]:
		var hub := Vector2(wx, -9.0)
		var piv: Vector2 = bt * Vector2(wx * 0.45, -15.0)
		VArt.tube(self, piv, hub, steel.lightened(0.1), 2.2)
		if lv >= 1:
			VArt.spring(self, bt * Vector2(wx * 0.7, -21.0), hub + Vector2(-signf(wx) * 2.0, -3.0), Color(0.75, 0.55, 0.2) if cine else Color(0.8, 0.7, 0.3))
	# Body frame.
	draw_set_transform_matrix(_xf_b)
	VArt.part(self, S["tub"], _cols("tub", S["tub"], steel.lightened(0.15), steel.darkened(0.3), -23.0, -10.0), steel, line)
	# Engine block: exposed fins, exhaust pipe curling up and back.
	VArt.part(self, S["engine"], _cols("engine", S["engine"], VArt.STEEL_HI, steel.darkened(0.2), -31.0, -19.0), steel.lightened(0.1), line)
	if lv >= 1:
		for fx in [-43.0, -40.0, -37.0, -34.0]:
			draw_line(Vector2(fx, -29.0), Vector2(fx, -21.0), Color(0.05, 0.05, 0.05, 0.8), 1.0)
	VArt.tube(self, Vector2(-38, -22), Vector2(-47, -26), Color(0.45, 0.42, 0.38), 2.4)
	VArt.tube(self, Vector2(-47, -26), Vector2(-50, -33), Color(0.45, 0.42, 0.38), 2.4)
	# Spare tyre strapped over the engine.
	if lv >= 1:
		VArt.wheel(self, Vector2(-39, -36), 6.5, 0.4, 0.0, Color(0.32, 0.32, 0.3))
	# Wheels (outside the body).
	draw_set_transform_matrix(_xf_w)
	var rim_col := Color(0.42, 0.42, 0.4) if cine else Color(0.55, 0.55, 0.52)
	for wx in [-22.0, 22.0]:
		VArt.wheel(self, Vector2(wx, -9.0), 9.5, _wheel_rot, spd, rim_col)
	draw_set_transform_matrix(_xf_b)
	# Fenders over the wheels.
	for wx in [-22.0, 22.0]:
		draw_arc(Vector2(wx, -9.0), 12.5, PI * 1.08, PI * 1.92, 8, line, 3.4)
		draw_arc(Vector2(wx, -9.0), 12.5, PI * 1.12, PI * 1.88, 8, paint.darkened(0.25), 2.0)
	# Main shell.
	VArt.part(self, S["shell"], _cols("shell", S["shell"], paint.lightened(0.3), paint.darkened(0.45), -34.0, -16.0), paint, line, 1.4)
	if lv >= 1:
		VArt.grime(self, -36.0, 38.0, -22.0, -16.5, 0.55 if cine else 0.35)
	# Team trim stripe + mark (shape per team, readable without colour).
	draw_colored_polygon(S["stripe"], trim.darkened(0.15) if cine else trim)
	VArt.mark(self, Vector2(8.0, -27.0), team, _team_mode(), 3.6)
	# Panel lines, rivets.
	if lv >= 1:
		var pl := Color(0.02, 0.02, 0.02, 0.55)
		draw_line(Vector2(-4, -33), Vector2(-6, -18), pl, 1.0)
		draw_line(Vector2(17, -33), Vector2(25, -19), pl, 1.0)
		draw_line(Vector2(-28, -26), Vector2(-28, -18), pl, 1.0)
		for rx in range(-24, 28, 8):
			draw_circle(Vector2(rx, -14.5), 0.8, VArt.STEEL_HI)
		VArt.scorch(self, _spots, _dmg())
	# Lit top edge (classic) / rim (cinematic).
	if cine:
		VArt.rim(self, S["shell"], S["shell_n"], face, _tilt + _pitch * face, 1.0)
		VArt.rim(self, S["engine"], S["engine_n"], face, _tilt + _pitch * face, 0.7)
	elif lv >= 1:
		draw_polyline(S["top"], paint.lightened(0.4), 1.0)
	# Seat back + roll cage + bull bar.
	draw_colored_polygon(S["seat"], Color(0.08, 0.075, 0.07))
	var cage := Color(0.3, 0.31, 0.32) if cine else Color(0.38, 0.38, 0.36)
	VArt.tube(self, Vector2(-14, -28), Vector2(-8, -47), cage, 2.4)
	VArt.tube(self, Vector2(-8, -47), Vector2(13, -47), cage, 2.4)
	VArt.tube(self, Vector2(13, -47), Vector2(22, -32), cage, 2.4)
	if lv >= 1:
		VArt.tube(self, Vector2(-8, -47), Vector2(4, -33), cage, 1.6)
	VArt.tube(self, Vector2(39, -27), Vector2(45, -16), cage, 2.2)
	VArt.tube(self, Vector2(45, -16), Vector2(40, -10), cage, 2.2)
	VArt.tube(self, Vector2(-20, -10.5), Vector2(20, -10.5), steel.lightened(0.2), 1.6)
	# Lights: headlamp + its cone, roof bar, tail light; a faint neon dash glow.
	if running:
		VArt.cone(self, HEADLIGHT_PT, Vector2(1.0, 0.1).normalized(), HEADLIGHT_LEN, 0.2, Color(1.0, 0.93, 0.75, 0.16 if cine else 0.1))
	VArt.lamp(self, HEADLIGHT_PT, Color(1.0, 0.92, 0.7), 2.2, running)
	VArt.lamp(self, Vector2(3, -48.5), Color(1.0, 0.8, 0.45), 1.3, running and lv >= 1)
	VArt.lamp(self, Vector2(10, -48.5), Color(1.0, 0.8, 0.45), 1.3, running and lv >= 1)
	VArt.lamp(self, Vector2(-45.5, -25), Color(1.0, 0.18, 0.12), 1.5, running)
	if cine and running:
		draw_line(Vector2(9, -33.5), Vector2(15, -33.5), Color(VArt.NEON.r, VArt.NEON.g, VArt.NEON.b, 0.65), 1.0)
		var ug := trim
		ug.a = 0.22
		draw_line(Vector2(-24, -8.5), Vector2(24, -8.5), ug, 2.0)
	# Damage fire licking out of the engine (the pooled embers / glow come from _fx_tick).
	var d := _dmg()
	if d >= 0.75 and lv >= 1:
		VArt.flame(self, ENGINE_PT + Vector2(0, 6), 7.0 + (d - 0.75) * 16.0, _fx_time, float(vehicle_id))
	elif d >= 0.55 and lv == 0:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var t := fmod(_fx_time, 1.0)
		draw_circle(_world_pt(ENGINE_PT) - global_position + Vector2(0, -t * 30.0), 5.0 + t * 7.0, Color(0.15, 0.15, 0.15, 0.4 * (1.0 - t)))


func _draw_wreck(lv: int) -> void:
	var S := _buggy_shapes()
	draw_set_transform_matrix(_xf_w * Transform2D(0.06, Vector2(0, 2)))
	VArt.part(self, S["tub"], PackedColorArray(), VArt.CHAR, Color(0, 0, 0, 0.8))
	var husk := _cols("husk", S["shell"], VArt.CHAR_HI, VArt.CHAR, -34.0, -16.0)
	VArt.part(self, S["shell"], husk, VArt.CHAR, Color(0, 0, 0, 0.8))
	VArt.part(self, S["engine"], PackedColorArray(), VArt.CHAR.lightened(0.04), Color(0, 0, 0, 0.8))
	# Bent cage, bare rims.
	VArt.tube(self, Vector2(-14, -28), Vector2(-4, -44), VArt.CHAR_HI, 2.2)
	VArt.tube(self, Vector2(-4, -44), Vector2(16, -38), VArt.CHAR_HI, 2.2)
	VArt.tube(self, Vector2(16, -38), Vector2(22, -30), VArt.CHAR_HI, 2.2)
	if lv >= 1:
		VArt.scorch(self, _spots, 1.0)
		var glow := Color(1.0, 0.42, 0.12, 0.35 * clampf(1.0 - _wreck_t / 9.0, 0.0, 1.0))
		if glow.a > 0.01:
			draw_line(Vector2(-30, -19), Vector2(30, -20), glow, 2.0)
	draw_set_transform_matrix(_xf_w)
	for wx in [-22.0, 22.0]:
		VArt.wheel(self, Vector2(wx, -7.0), 9.5, wx * 0.1, 0.0, VArt.CHAR_HI, true)
	if lv >= 1 and _wreck_t < 7.0:
		draw_set_transform_matrix(_xf_w)
		VArt.flame(self, Vector2(-10, -22), 9.0 * clampf(1.0 - _wreck_t / 7.0, 0.35, 1.0), _fx_time, 3.0)
		VArt.flame(self, Vector2(14, -20), 7.0 * clampf(1.0 - _wreck_t / 7.0, 0.3, 1.0), _fx_time, 7.0)


## Gun on its post (world-space so the aim isn't mirrored twice), recoiling
## along the aim when it fires, glowing as it heats up.
func _draw_gun(lv: int) -> void:
	var piv := _gun_pivot() - global_position
	var post_base: Vector2 = _xf_b * Vector2(GUN_POST.x, GUN_POST.y + 10.0)
	draw_line(post_base, piv, Color(0.12, 0.12, 0.12), 3.5)
	draw_line(post_base, piv, Color(0.32, 0.32, 0.33), 1.5)
	if lv >= 1:
		draw_rect(Rect2(post_base + Vector2(-4, -4), Vector2(7, 5)), Color(0.22, 0.24, 0.16))
	if _BARREL_TEX != null:
		var bs := _BARREL_TEX.get_size() / 3.0
		var kick := aim_dir * -_gun_kick
		draw_set_transform(piv + kick, aim_dir.angle(), Vector2(1.0, -1.0 if aim_dir.x < 0.0 else 1.0))
		var tint := Color.WHITE.lerp(Color(1.0, 0.55, 0.45), clampf(heat * 1.2 - 0.2, 0.0, 1.0)) if not overheated else Color(1, 0.5, 0.45)
		draw_texture_rect(_BARREL_TEX, Rect2(Vector2(-bs.x * 0.15, -bs.y * 0.5), bs), false, tint)
		if lv >= 1 and heat > 0.4:
			draw_line(Vector2(bs.x * 0.35, 0), Vector2(bs.x * 0.82, 0), Color(1.0, 0.4, 0.15, (heat - 0.4) * 0.9), 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## HP bar, enter hint (world space, never mirrored).
func _draw_overlay() -> void:
	if hp < MAX_HP:
		VArt.hp_bar(self, Vector2(0, -LABEL_LIFT - 14.0), 48.0 if kind == "buggy" else 60.0, hp / MAX_HP)
	if free_seat() >= 0:
		var main := get_parent()
		var p = main.get("player") if main != null else null
		if p != null and is_instance_valid(p) and seat_of(p) < 0 and (p as Node2D).global_position.distance_to(global_position) < ENTER_RADIUS:
			draw_string(ThemeDB.fallback_font, Vector2(-40, -LABEL_LIFT - 20.0), _enter_hint(), HORIZONTAL_ALIGNMENT_CENTER, 80, 12, Color(0.95, 0.9, 0.5))


func _enter_hint() -> String:
	return "F: DRIVE" if driver() == null else "F: GUNNER"
