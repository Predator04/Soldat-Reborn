extends "res://scripts/buggy.gd"
## Light tank: slow, armored, two seats. The driver steers; whoever holds the
## gun (gunner, or the driver alone at a penalty) fires a lobbed high-explosive
## shell from the turret. Bullets barely scratch it (BULLET_ARMOR) — bring a
## LAW, M79 or grenades. Everything else (seats, net sync, bots, wrecks) comes
## from buggy.gd.

const SHELL_GRAV := 520.0
const SHELL_DAMAGE := 110.0
const SHELL_BLAST := 150.0

var _shell_n := 0
var _recoil := 0.0


func _init() -> void:
	kind = "tank"
	LABEL = "TANK"
	display_name = "Tank"
	LABEL_LIFT = 58.0
	SHAPE_R = 15.0
	SHAPE_LEN = 88.0
	MAX_HP = 900.0
	hp = MAX_HP
	ACCEL = 420.0
	MAX_SPEED = 230.0
	REVERSE_SPEED = 140.0
	BRAKE = 900.0
	ROLL_DRAG = 420.0
	HOP_VEL = -300.0
	ENTER_RADIUS = 70.0
	RUNOVER_MIN_SPEED = 110.0
	RUNOVER_DMG_PER_SPEED = 0.9
	GUN_RATE = 2.4
	GUN_SPEED = 900.0
	GUN_SPREAD = 0.01
	HEAT_PER_SHOT = 0.0
	EXPLOSIVE_MUL = 0.8
	BULLET_ARMOR = 0.2
	EXPLODE_RADIUS = 190.0
	EXPLODE_DAMAGE = 150.0
	RESPAWN_TIME = 40.0
	SEATS = [Vector2(24, -32), Vector2(-8, -46)]
	BOT_GUN_RANGE = 1300.0
	SOLO_FIRE_SPEED = 0.6
	SOLO_FIRE_SPREAD = 3.0
	ENGINE_PITCH = 0.35


func _physics_process(delta: float) -> void:
	_recoil = maxf(0.0, _recoil - delta * 30.0)
	super(delta)


func _gun_pivot() -> Vector2:
	var off := Vector2(-4.0 * face, -40.0)
	return global_position + off.rotated(_tilt)


func _read_aim(me: Node2D) -> Vector2:
	var a := super(me)
	# The turret can't point below the horizon much.
	if a.y > 0.25:
		a = Vector2(signf(a.x) if absf(a.x) > 0.01 else face, 0.25).normalized()
	return a


# Every peer flies its own copy of the shell (same start, same ballistics);
# like the machine-gun rounds, damage is applied by each victim's owner and
# vehicle damage by the host (see rocket.gd `local_only`).
func apply_fire(muzzle: Vector2, dir: Vector2) -> void:
	fire_cd = GUN_RATE
	var shooter: Node2D = gunner() if gunner() != null else driver()
	if shooter == null:
		return
	_shell_n += 1
	var r = preload("res://scenes/rocket.tscn").instantiate()
	r.name = "TankShell_%d_%d" % [vehicle_id, _shell_n]
	r.local_only = true
	r.ignore_bodies = [self] + seats.filter(func(o): return is_instance_valid(o))
	r.global_position = muzzle + dir * 34.0
	r.direction = dir
	r.speed = GUN_SPEED
	r.grav = SHELL_GRAV
	r.damage = SHELL_DAMAGE * MatchConfig.mod_damage()
	r.blast_radius = SHELL_BLAST
	r.team = int(shooter.get("team"))
	r.killer_name = str(shooter.get("display_name"))
	r.weapon_name = "Tank"
	get_parent().add_child(r)
	Sfx._play_key("law-start", -1.0, randf_range(0.6, 0.66), muzzle)
	Sfx._play_far("dist-m79", -4.0, 0.7, muzzle)
	_recoil = 8.0
	if is_sim():
		velocity.x -= dir.x * 90.0


# Lobbed shell: low-arc ballistic solution, ZERO when the target is out of reach.
func _aim_solution(to: Vector2) -> Vector2:
	var g := SHELL_GRAV * MatchConfig.mod_gravity()
	var v := GUN_SPEED
	var dx := absf(to.x)
	var dy := -to.y     # up is positive
	if dx < 4.0:
		return Vector2(0, -1) if dy > 0.0 else Vector2.ZERO
	var disc := v * v * v * v - g * (g * dx * dx + 2.0 * dy * v * v)
	if disc < 0.0:
		return Vector2.ZERO
	var th := atan((v * v - sqrt(disc)) / (g * dx))
	return Vector2(signf(to.x) * cos(th), -sin(th))


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, _tilt, Vector2(face, 1.0))
	if not alive:
		draw_rect(Rect2(-46, -26, 92, 18), Color(0.12, 0.11, 0.1))
		draw_rect(Rect2(-18, -38, 30, 12), Color(0.09, 0.09, 0.08))
		draw_line(Vector2(10, -34), Vector2(40, -30), Color(0.08, 0.08, 0.08), 4.0)
		for wx in [-34.0, -17.0, 0.0, 17.0, 34.0]:
			draw_circle(Vector2(wx, -8), 7.0, Color(0.07, 0.07, 0.07))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for i in 6:
			var t := fmod(_smoke_t * 0.5 + i * 0.17, 1.0)
			draw_circle(Vector2(sin(i * 1.3 + _smoke_t) * 10.0, -30.0 - t * 90.0), 7.0 + t * 13.0, Color(0.18, 0.18, 0.18, 0.4 * (1.0 - t)))
		return
	var body := _team_color().darkened(0.1)
	var dark := body.darkened(0.5)
	# Tracks: a rounded belt around five road wheels.
	var belt := PackedVector2Array([Vector2(-46, -12), Vector2(-40, -18), Vector2(40, -18), Vector2(47, -12), Vector2(42, -1), Vector2(-42, -1)])
	draw_colored_polygon(belt, Color(0.13, 0.13, 0.12))
	for wx in [-34.0, -17.0, 0.0, 17.0, 34.0]:
		var c := Vector2(wx, -9)
		draw_circle(c, 7.0, Color(0.32, 0.32, 0.3))
		draw_circle(c, 2.5, Color(0.18, 0.18, 0.17))
		var a: float = _wheel_rot * face
		draw_line(c, c + Vector2(cos(a), sin(a)) * 6.0, Color(0.2, 0.2, 0.2), 1.5)
	# Track links scroll with the wheels.
	var off := fmod(_wheel_rot * 7.0 * face, 10.0)
	for i in 10:
		var x := -44.0 + fposmod(i * 10.0 + off, 88.0)
		draw_line(Vector2(x, -18), Vector2(x, -16), Color(0.25, 0.25, 0.24), 2.0)
	# Hull.
	var hull := PackedVector2Array([Vector2(-44, -18), Vector2(-40, -30), Vector2(30, -30), Vector2(46, -20), Vector2(44, -18)])
	draw_colored_polygon(hull, body)
	draw_polyline(hull + PackedVector2Array([hull[0]]), dark, 1.5)
	draw_line(Vector2(-38, -24), Vector2(28, -24), dark, 1.0)
	# Turret dome.
	var tur := PackedVector2Array([Vector2(-22, -30), Vector2(-18, -44), Vector2(10, -44), Vector2(16, -30)])
	draw_colored_polygon(tur, body.lightened(0.08))
	draw_polyline(tur + PackedVector2Array([tur[0]]), dark, 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Barrel along the aim (world-space).
	var piv := _gun_pivot() - global_position
	var tip := piv + aim_dir * (40.0 - _recoil)
	draw_line(piv, tip, dark, 6.0)
	draw_line(piv, tip, body.lightened(0.15), 3.5)
	draw_line(tip - aim_dir * 6.0, tip, dark, 7.5)
	if hp < MAX_HP * 0.35:
		var t := fmod(Time.get_ticks_msec() / 1000.0, 1.0)
		draw_circle(Vector2(-30 * face, -34 - t * 36.0), 6.0 + t * 9.0, Color(0.15, 0.15, 0.15, 0.45 * (1.0 - t)))
	if fire_cd > 0.0 and fire_cd < GUN_RATE:
		draw_rect(Rect2(-24, -72, 48.0 * (1.0 - fire_cd / GUN_RATE), 3), Color(0.95, 0.8, 0.3, 0.8))
	if hp < MAX_HP:
		draw_rect(Rect2(-30, -66, 60, 4), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-30, -66, 60.0 * hp / MAX_HP, 4), Color(0.9, 0.3, 0.2).lerp(Color(0.4, 0.9, 0.3), hp / MAX_HP))
	if free_seat() >= 0:
		var main := get_parent()
		var p = main.get("player") if main != null else null
		if p != null and is_instance_valid(p) and seat_of(p) < 0 and (p as Node2D).global_position.distance_to(global_position) < ENTER_RADIUS:
			draw_string(ThemeDB.fallback_font, Vector2(-40, -78), "F: DRIVE" if driver() == null else "F: GUNNER", HORIZONTAL_ALIGNMENT_CENTER, 80, 12, Color(0.95, 0.9, 0.5))
