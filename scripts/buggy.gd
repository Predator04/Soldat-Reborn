extends CharacterBody2D
## Buggy (v1.19) — two-seat ground vehicle. Walk up and press F: the first
## seat is the driver (A/D drive, W hops, F gets out), the second the gunner
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
var HOP_VEL := -430.0
var ENTER_RADIUS := 56.0
var RUNOVER_MIN_SPEED := 190.0
var GUN_RATE := 0.075
var GUN_DAMAGE := 14.0
var GUN_SPEED := 1450.0
var GUN_SPREAD := 0.035
var HEAT_PER_SHOT := 0.035    # ~2 s of continuous fire to overheat
var HEAT_COOL := 0.45         # per second
var RESPAWN_TIME := 25.0
var EXPLODE_RADIUS := 150.0
var EXPLODE_DAMAGE := 120.0
var EXPLOSIVE_MUL := 1.6      # rockets / grenades hurt it more than bullets
# Driving and shooting at once (no gunner): slower and sloppier. A crew of
# two is the strong way to run a buggy.
var SOLO_FIRE_SPEED := 0.5    # top speed while the solo driver holds the trigger
var SOLO_FIRE_SPREAD := 2.2   # spread multiplier for a solo driver
var BOT_GUN_RANGE := 900.0

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
var _bd_check := 0.0            # bot driver: stuck / progress tracking
var _bd_last_x := 0.0
var _bd_stuck_t := 0.0
var _bd_hop := false

const EXPLOSIVE_WEAPONS := ["LAW", "M79", "Grenade", "Cluster", "Tank", "Buggy"]
const _BARREL_TEX := preload("res://assets/weapons-gfx/m2.png")
const TouchControls = preload("res://scripts/touch_controls.gd")


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
	var old = seats[seat]
	if is_instance_valid(old) and old != s and old.has_method("dismount_m2"):
		old.dismount_m2()
	seats[seat] = s
	if is_instance_valid(s) and s.has_method("mount_m2"):
		s.mount_m2(self)
		if s.has_method("_pickup_toast"):
			s._pickup_toast("BUGGY", "A/D drive · W hop · aim + fire the gun · F to get out" if seat == 0 else "Gunner: aim + fire · F to get out", Color(0.95, 0.85, 0.5))
	_update_team()


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
	else:
		_follow(delta)
	_place_occupants()
	_local_occupant_input()
	if _is_host_side():
		_bot_gunner(delta)
		_runover()
		var kill_y: float = float(get_parent().get("KILL_Y")) if get_parent() != null and get_parent().get("KILL_Y") != null else INF
		if global_position.y > kill_y:
			_host_destroy(last_hitter, last_hitter_team)
	_engine_sound()
	_wheel_rot += velocity.x * delta / 11.0
	queue_redraw()


func _is_host_side() -> bool:
	return not Net.is_networked() or Net.is_host()


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
		main.vehicle_send("net_vehicle_fire", [vehicle_id, muzzle, dir], true)
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
	get_parent().add_child(b)
	if not Sfx._throttle("buggy_mg_%d" % vehicle_id, 60):
		pass
	else:
		Sfx._play_key("m2fire", -8.0, randf_range(0.97, 1.03), muzzle)
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
	if want == Vector2.ZERO or want.y > 0.55:
		return   # out of reach / can't depress that far
	aim_dir = aim_dir.slerp(want, clampf(delta * 7.0, 0.0, 1.0)).normalized()
	if heat > 0.85:
		_bot_hold = true
	elif heat < 0.3:
		_bot_hold = false
	if not overheated and not _bot_hold and fire_cd <= 0.0 and absf(aim_dir.angle_to(want)) < 0.12:
		_fire(g)


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
	if killer != "":
		last_hitter = killer
		last_hitter_team = killer_team
	var main := get_parent()
	if main != null and main.has_method("vehicle_send"):
		main.vehicle_send("net_vehicle_hp", [vehicle_id, hp], true)
	if hp <= 0.0:
		_host_destroy(last_hitter, last_hitter_team)


func apply_hp(v: float) -> void:
	hp = v


func _host_destroy(killer: String, killer_team: int) -> void:
	if not alive:
		return
	var main := get_parent()
	if main != null and main.has_method("vehicle_send"):
		main.vehicle_send("net_vehicle_destroy", [vehicle_id, global_position, killer, killer_team], true)
	else:
		apply_destroy(global_position, killer, killer_team)


# Every peer: blast, eject/kill occupants, hide, start the respawn timer.
func apply_destroy(at: Vector2, killer: String, killer_team: int, quiet := false) -> void:
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
	var kname: String = killer if killer != "" else "Buggy"
	for s in get_tree().get_nodes_in_group("soldier"):
		if not is_instance_valid(s) or s.get("dead") == true:
			continue
		var dist: float = (s as Node2D).global_position.distance_to(at)
		var dmg := 0.0
		if s in occupants:
			dmg = 999.0
		elif dist < EXPLODE_RADIUS:
			dmg = EXPLODE_DAMAGE * (1.0 - dist / EXPLODE_RADIUS)
		if dmg <= 0.0:
			continue
		if multiplayer.multiplayer_peer == null or s.is_multiplayer_authority():
			s.take_damage(dmg, kname, "Buggy", killer_team)
	_respawn_t = RESPAWN_TIME
	_smoke_t = 0.0
	velocity = Vector2.ZERO
	collision_layer = 0
	if not Settings.lofi:
		var p := CPUParticles2D.new()
		p.amount = 90
		p.lifetime = 0.8
		p.explosiveness = 1.0
		p.one_shot = true
		p.emitting = true
		p.global_position = at
		p.direction = Vector2(0, -1)
		p.spread = 180.0
		p.gravity = Vector2(0, 300)
		p.initial_velocity_min = 120.0
		p.initial_velocity_max = 480.0
		p.scale_amount_min = 2.5
		p.scale_amount_max = 5.5
		p.color = Color(1.0, 0.6, 0.2)
		get_parent().add_child(p)
		get_tree().create_timer(1.5).timeout.connect(p.queue_free)


func _tick_dead(delta: float) -> void:
	_engine.stop()
	_smoke_t += delta
	queue_redraw()
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
	alive = true
	hp = MAX_HP
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


# ── Presentation ──────────────────────────────────────

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


func _team_color() -> Color:
	var main := get_parent()
	if team >= 0 and main != null and Settings.is_team_mode():
		return (main.get_script() as GDScript).bot_color_for_team(team).lerp(Color(0.5, 0.48, 0.36), 0.35)
	return Color(0.52, 0.5, 0.36)


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, _tilt, Vector2(face, 1.0))
	if not alive:
		# Burnt-out frame, smoking, until it respawns.
		draw_rect(Rect2(-34, -22, 68, 12), Color(0.12, 0.11, 0.1))
		draw_circle(Vector2(-22, -9), 9.0, Color(0.08, 0.08, 0.08))
		draw_circle(Vector2(22, -9), 9.0, Color(0.08, 0.08, 0.08))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for i in 5:
			var t := fmod(_smoke_t * 0.6 + i * 0.2, 1.0)
			draw_circle(Vector2(sin(i * 1.7 + _smoke_t) * 8.0, -20.0 - t * 70.0), 6.0 + t * 10.0, Color(0.2, 0.2, 0.2, 0.35 * (1.0 - t)))
		return
	var body := _team_color()
	var dark := body.darkened(0.45)
	# Chassis.
	var hull := PackedVector2Array([Vector2(-36, -8), Vector2(-34, -22), Vector2(-10, -24), Vector2(4, -30), Vector2(20, -30), Vector2(36, -18), Vector2(36, -8)])
	draw_colored_polygon(hull, body)
	draw_polyline(hull + PackedVector2Array([hull[0]]), dark, 1.5)
	# Roll cage.
	draw_line(Vector2(-12, -24), Vector2(-6, -44), dark, 2.5)
	draw_line(Vector2(-6, -44), Vector2(14, -44), dark, 2.5)
	draw_line(Vector2(14, -44), Vector2(20, -30), dark, 2.5)
	# Headlight + bumper.
	draw_circle(Vector2(34, -20), 2.5, Color(1.0, 0.95, 0.7))
	draw_rect(Rect2(34, -12, 5, 5), dark)
	# Wheels with spokes that spin.
	for wx in [-22.0, 22.0]:
		var c := Vector2(wx, -9)
		draw_circle(c, 9.5, Color(0.1, 0.1, 0.1))
		draw_circle(c, 5.0, Color(0.45, 0.45, 0.45))
		for k in 3:
			var a: float = _wheel_rot * face + k * TAU / 3.0
			draw_line(c, c + Vector2(cos(a), sin(a)) * 8.0, Color(0.2, 0.2, 0.2), 2.0)
	# Damage smoke from the engine when badly hurt.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if hp < MAX_HP * 0.35:
		var t := fmod(Time.get_ticks_msec() / 1000.0, 1.0)
		draw_circle(Vector2(20 * face, -34 - t * 30.0), 5.0 + t * 7.0, Color(0.15, 0.15, 0.15, 0.4 * (1.0 - t)))
	# Gun on its post (world-space so aim isn't mirrored twice).
	var piv := _gun_pivot() - global_position
	draw_line(piv + Vector2(0, 10), piv, Color(0.2, 0.2, 0.2), 3.0)
	if _BARREL_TEX != null:
		var bs := _BARREL_TEX.get_size() / 3.0
		draw_set_transform(piv, aim_dir.angle(), Vector2(1.0, -1.0 if aim_dir.x < 0.0 else 1.0))
		draw_texture_rect(_BARREL_TEX, Rect2(Vector2(-bs.x * 0.15, -bs.y * 0.5), bs), false, Color(1, 0.6, 0.6) if overheated else Color.WHITE)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# HP bar when damaged.
	if hp < MAX_HP:
		draw_rect(Rect2(-24, -58, 48, 4), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-24, -58, 48.0 * hp / MAX_HP, 4), Color(0.9, 0.3, 0.2).lerp(Color(0.4, 0.9, 0.3), hp / MAX_HP))
	# Enter hint.
	if free_seat() >= 0:
		var main := get_parent()
		var p = main.get("player") if main != null else null
		if p != null and is_instance_valid(p) and seat_of(p) < 0 and (p as Node2D).global_position.distance_to(global_position) < ENTER_RADIUS:
			draw_string(ThemeDB.fallback_font, Vector2(-40, -64), "F: DRIVE" if driver() == null else "F: GUNNER", HORIZONTAL_ALIGNMENT_CENTER, 80, 12, Color(0.95, 0.9, 0.5))
