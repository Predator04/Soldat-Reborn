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
	HOP_VEL = 0.0
	ENTER_RADIUS = 70.0
	RUNOVER_MIN_SPEED = 110.0
	RUNOVER_DMG_PER_SPEED = 0.9
	GUN_RATE = 2.4
	GUN_SPEED = 900.0
	GUN_SPREAD = 0.01
	HEAT_PER_SHOT = 0.0
	EXPLOSIVE_MUL = 1.0             # #310: was 0.8 — never wrecked in 60 bot match-minutes
	BULLET_ARMOR = 0.2
	EXPLODE_RADIUS = 190.0
	EXPLODE_DAMAGE = 150.0
	RESPAWN_TIME = 40.0
	SEATS = [Vector2(24, -32), Vector2(-8, -46)]
	BOT_GUN_RANGE = 1300.0
	SOLO_FIRE_SPEED = 0.6
	SOLO_FIRE_SPREAD = 3.0
	ENGINE_PITCH = 0.35
	# Look (#276).
	PAINT_BASE = Color(0.36, 0.39, 0.3)     # olive drab
	EXHAUST_PT = Vector2(-41, -42)
	ENGINE_PT = Vector2(-32, -34)
	HEADLIGHT_PT = Vector2(45, -27)
	HEADLIGHT_LEN = 130.0
	DUST_X = [-40.0, 40.0]
	GUN_POST = Vector2(-4, -40)
	SUSP_MAX = 2.5
	SHADOW_W = 50.0


func _physics_process(delta: float) -> void:
	_recoil = maxf(0.0, _recoil - delta * 30.0)
	super(delta)


func _fx_tick(delta: float) -> void:
	super(delta)
	# Cosmetic: distance the tracks have rolled (drives the link animation)
	# and the antenna whipping with acceleration.
	var dt := minf(delta, 0.05)
	_track_s += velocity.x * dt
	_ant_v += (-_ant * 60.0 - _ant_v * 4.0 - (velocity.x - _ant_prev_vx) * 0.02 * face) * dt
	_ant = clampf(_ant + _ant_v * dt, -0.5, 0.5)
	_ant_prev_vx = velocity.x


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
	# Cosmetic: big muzzle flash (pooled light) + a ring of blast smoke.
	var tip := muzzle + dir * 30.0
	Gfx.muzzle(get_parent(), tip, true, dir)
	var w = _fxw()
	if w != null and VArt.level() >= 1:
		for k in (5 if VArt.level() >= 2 else 3):
			var a := dir.rotated(Gfx.rf(-1.2, 1.2))
			w.smoke(tip + a * 4.0, a * Gfx.rf(40.0, 110.0) + Vector2(0, -12), Gfx.rf(10.0, 16.0), Gfx.rf(0.6, 1.1), Color(0.5, 0.48, 0.45, 0.3))
	Sfx._play_key("law-start", -1.0, preload("res://scripts/gfx.gd").rf(0.6, 0.66), muzzle)
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


# ── drawing (#276) ────────────────────────────────────
# Cosmetic only. Tracks are one belt loop around the sprocket (front), idler
# (rear) and five sprung road wheels; links ride the loop by the distance the
# tank has rolled. The turret recoils with the barrel.

const TRACK_TOP := -19.0
const TRACK_BOT := -1.0
const TRACK_X0 := -40.0
const TRACK_X1 := 40.0
const TRACK_R := 9.0
const ROAD_WHEELS := [-28.0, -14.0, 0.0, 14.0, 28.0]

static var _TS: Dictionary = {}
var _track_s := 0.0
var _ant := 0.0
var _ant_v := 0.0
var _ant_prev_vx := 0.0


static func _tank_shapes() -> Dictionary:
	if not _TS.is_empty():
		return _TS
	# Belt: two straight runs and two half circles (sprocket front, idler rear).
	var belt := PackedVector2Array()
	var cy := (TRACK_TOP + TRACK_BOT) * 0.5
	for i in 9:
		var a := -PI * 0.5 + PI * float(i) / 8.0
		belt.append(Vector2(TRACK_X1, cy) + Vector2(cos(a), sin(a)) * TRACK_R)
	for i in 9:
		var a2 := PI * 0.5 + PI * float(i) / 8.0
		belt.append(Vector2(TRACK_X0, cy) + Vector2(cos(a2), sin(a2)) * TRACK_R)
	_TS["belt"] = belt
	_TS["hull"] = VArt.pv([Vector2(-46, -23), Vector2(-44, -34), Vector2(-20, -36), Vector2(24, -36), Vector2(50, -26), Vector2(48, -22)])
	_TS["skirt"] = VArt.pv([Vector2(-47, -27), Vector2(47, -27), Vector2(45, -18), Vector2(-45, -18)])
	_TS["turret"] = VArt.pv([Vector2(-28, -36), Vector2(-25, -46), Vector2(-8, -50), Vector2(10, -49), Vector2(18, -42), Vector2(16, -36)])
	_TS["stripe"] = VArt.pv([Vector2(-44, -24), Vector2(44, -24), Vector2(43.5, -22), Vector2(-43.5, -22)])
	for k in ["hull", "skirt", "turret"]:
		_TS[k + "_n"] = VArt.normals(_TS[k])
	return _TS


## A point `s` px along the belt loop (clockwise from the top-rear corner).
static func _belt_at(s: float) -> Array:
	var run := TRACK_X1 - TRACK_X0
	var arc := PI * TRACK_R
	var per := 2.0 * run + 2.0 * arc
	var t := fposmod(s, per)
	var cy := (TRACK_TOP + TRACK_BOT) * 0.5
	if t < run:
		return [Vector2(TRACK_X0 + t, TRACK_TOP + 0.5), 0.0]
	t -= run
	if t < arc:
		var a := -PI * 0.5 + t / TRACK_R
		return [Vector2(TRACK_X1, cy) + Vector2(cos(a), sin(a)) * TRACK_R, a + PI * 0.5]
	t -= arc
	if t < run:
		return [Vector2(TRACK_X1 - t, TRACK_BOT - 0.5), PI]
	t -= run
	var a2 := PI * 0.5 + t / TRACK_R
	return [Vector2(TRACK_X0, cy) + Vector2(cos(a2), sin(a2)) * TRACK_R, a2 + PI * 0.5]


func _draw_hull(lv: int) -> void:
	var S := _tank_shapes()
	var paint := _team_color()
	var trim := VArt.trim(team, _team_mode())
	var cine := VArt.cinematic()
	var line := Color(0.02, 0.02, 0.025, 0.9)
	var running := driver() != null
	var steel := VArt.STEEL if cine else VArt.STEEL.lightened(0.12)
	var roll := _track_s * face
	# ── Running gear (wheel frame) ──
	draw_set_transform_matrix(_xf_w)
	draw_colored_polygon(S["belt"], Color(0.07, 0.07, 0.07))
	draw_polyline(S["belt"], Color(0.24, 0.24, 0.23), 2.2)
	draw_line(S["belt"][S["belt"].size() - 1], S["belt"][0], Color(0.24, 0.24, 0.23), 2.2)
	var spd := velocity.x
	var k := clampf(absf(spd) / MAX_SPEED, 0.0, 1.0)
	for i in ROAD_WHEELS.size():
		var wx: float = ROAD_WHEELS[i]
		var bob := sin(_track_s * 0.09 + i * 1.9) * 1.2 * k
		var c := Vector2(wx, -8.0 + bob)
		draw_circle(c, 6.4, Color(0.06, 0.06, 0.06))
		draw_circle(c, 5.4, Color(0.3, 0.31, 0.28) if not cine else Color(0.26, 0.27, 0.25))
		draw_circle(c, 2.4, Color(0.12, 0.12, 0.11))
		if lv >= 1:
			for b in 5:
				var a := roll / 6.0 + b * TAU / 5.0
				draw_circle(c + Vector2(cos(a), sin(a)) * 3.5, 0.7, Color(0.45, 0.45, 0.42))
			draw_arc(c, 5.4, -PI * 0.85, -PI * 0.2, 5, Color(0.5, 0.5, 0.47, 0.6), 0.9)
	# Drive sprocket (front) + idler (rear) with teeth turning.
	var cy := (TRACK_TOP + TRACK_BOT) * 0.5
	for e: Vector2 in [Vector2(TRACK_X1, 7.0), Vector2(TRACK_X0, 6.0)]:
		var cc := Vector2(e.x, cy)
		var er := e.y
		draw_circle(cc, er, Color(0.22, 0.22, 0.21))
		draw_circle(cc, er * 0.4, Color(0.1, 0.1, 0.1))
		for t in 8:
			var a2 := roll / er + t * TAU / 8.0
			draw_line(cc + Vector2(cos(a2), sin(a2)) * (er - 2.0), cc + Vector2(cos(a2), sin(a2)) * (er + 0.6), Color(0.35, 0.35, 0.33), 1.6)
	# Track links (grousers) riding the loop.
	var step := 5.5 if lv >= 1 else 11.0
	var per := 2.0 * (TRACK_X1 - TRACK_X0) + 2.0 * PI * TRACK_R
	var n := int(per / step)
	var lc := Color(0.27, 0.27, 0.25) if lv >= 1 else Color(0.25, 0.25, 0.24)
	for i in n:
		var b2: Array = _belt_at(i * step + roll)
		var p: Vector2 = b2[0]
		var ang: float = b2[1]
		var nrm := Vector2(0, -1).rotated(ang)
		draw_line(p - nrm * 1.2, p + nrm * 1.2, lc, 2.2)
	# ── Hull (body frame) ──
	draw_set_transform_matrix(_xf_b)
	VArt.part(self, S["hull"], _cols("hull", S["hull"], paint.lightened(0.26), paint.darkened(0.42), -36.0, -22.0), paint, line, 1.4)
	# Engine deck grille + exhaust stack at the rear.
	if lv >= 1:
		for gx in range(-40, -22, 3):
			draw_line(Vector2(gx, -35.5), Vector2(gx + 1.5, -33.0), Color(0.03, 0.03, 0.03, 0.8), 1.0)
	VArt.tube(self, Vector2(-38, -35), Vector2(-41, -41), Color(0.36, 0.33, 0.3), 3.0)
	# Side skirt over the upper track run: team stripe, bolts, grime.
	VArt.part(self, S["skirt"], _cols("skirt", S["skirt"], paint.lightened(0.05), paint.darkened(0.5), -27.0, -18.0), paint.darkened(0.15), line)
	draw_colored_polygon(S["stripe"], trim.darkened(0.15) if cine else trim)
	if lv >= 1:
		for bx in range(-42, 46, 8):
			draw_circle(Vector2(bx, -20.0), 0.8, VArt.STEEL_HI)
		VArt.grime(self, -46.0, 46.0, -23.0, -18.0, 0.6 if cine else 0.4)
		draw_line(Vector2(-14, -27), Vector2(-14, -18), Color(0, 0, 0, 0.5), 1.0)
		draw_line(Vector2(16, -27), Vector2(16, -18), Color(0, 0, 0, 0.5), 1.0)
		VArt.scorch(self, _spots, _dmg())
	# Headlight + tow hook.
	if running:
		VArt.cone(self, HEADLIGHT_PT, Vector2(1.0, 0.12).normalized(), HEADLIGHT_LEN, 0.22, Color(1.0, 0.93, 0.75, 0.14 if cine else 0.09))
	VArt.lamp(self, HEADLIGHT_PT, Color(1.0, 0.92, 0.7), 2.0, running)
	VArt.tube(self, Vector2(48, -24), Vector2(51, -22), steel.lightened(0.2), 1.6)
	# ── Turret (body frame, jolts back with the shot) ──
	var jolt := -_recoil * 0.35
	draw_set_transform_matrix(_xf_b * Transform2D(0.0, Vector2(jolt, 0.0)))
	var tp := paint.lightened(0.06)
	VArt.part(self, S["turret"], _cols("turret", S["turret"], tp.lightened(0.16), tp.darkened(0.35), -50.0, -36.0), tp, line, 1.4)
	draw_rect(Rect2(-13, -54, 9, 4), steel.lightened(0.1))
	draw_rect(Rect2(-13, -54, 9, 4), line, false, 1.0)
	VArt.mark(self, Vector2(-4.0, -42.0), team, _team_mode(), 3.8)
	if lv >= 1:
		draw_line(Vector2(-25, -40), Vector2(14, -40), Color(0, 0, 0, 0.45), 1.0)
		draw_rect(Rect2(-27, -45, 4, 6), Color(0.2, 0.2, 0.17))
	# Antenna whipping about.
	var ab := Vector2(-20, -48)
	var at := ab + Vector2(0, -30).rotated(-0.25 + _ant)
	draw_line(ab, ab.lerp(at, 0.5) + Vector2(_ant * 3.0, 0), Color(0.1, 0.1, 0.1), 1.0)
	draw_line(ab.lerp(at, 0.5) + Vector2(_ant * 3.0, 0), at, Color(0.1, 0.1, 0.1), 1.0)
	draw_circle(at, 1.0, trim)
	if cine:
		var rt := _tilt + _pitch * face
		VArt.rim(self, S["turret"], S["turret_n"], face, rt, 1.0)
		draw_set_transform_matrix(_xf_b)
		VArt.rim(self, S["hull"], S["hull_n"], face, rt, 0.85)
		VArt.rim(self, S["skirt"], S["skirt_n"], face, rt, 0.5)
		if running:
			draw_line(Vector2(-11, -51), Vector2(-6, -51), Color(VArt.NEON.r, VArt.NEON.g, VArt.NEON.b, 0.6), 1.0)
	elif lv >= 1:
		draw_set_transform_matrix(_xf_b)
		draw_line(Vector2(-44, -34), Vector2(24, -36), paint.lightened(0.38), 1.0)
	draw_set_transform_matrix(_xf_b)
	var d := _dmg()
	if d >= 0.75 and lv >= 1:
		VArt.flame(self, ENGINE_PT + Vector2(0, 2), 8.0 + (d - 0.75) * 18.0, _fx_time, float(vehicle_id))
	elif d >= 0.55 and lv == 0:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var t := fmod(_fx_time, 1.0)
		draw_circle(_world_pt(ENGINE_PT) - global_position + Vector2(0, -t * 36.0), 6.0 + t * 9.0, Color(0.15, 0.15, 0.15, 0.45 * (1.0 - t)))


func _draw_wreck(lv: int) -> void:
	var S := _tank_shapes()
	draw_set_transform_matrix(_xf_w * Transform2D(0.03, Vector2(0, 1.5)))
	draw_colored_polygon(S["belt"], Color(0.05, 0.05, 0.05))
	for wx in ROAD_WHEELS:
		draw_circle(Vector2(wx, -7.0), 6.0, VArt.CHAR_HI)
		draw_circle(Vector2(wx, -7.0), 2.2, VArt.CHAR)
	VArt.part(self, S["hull"], _cols("husk_h", S["hull"], VArt.CHAR_HI, VArt.CHAR, -36.0, -22.0), VArt.CHAR, Color(0, 0, 0, 0.85))
	VArt.part(self, S["skirt"], PackedColorArray(), VArt.CHAR, Color(0, 0, 0, 0.85))
	# Turret knocked askew, barrel drooping.
	draw_set_transform_matrix(_xf_w * Transform2D(-0.12, Vector2(-4, 3)))
	VArt.part(self, S["turret"], PackedColorArray(), VArt.CHAR.lightened(0.03), Color(0, 0, 0, 0.85))
	draw_line(Vector2(14, -42), Vector2(46, -34), Color(0.05, 0.05, 0.05), 4.5)
	draw_set_transform_matrix(_xf_w)
	if lv >= 1:
		VArt.scorch(self, _spots, 1.0)
		if _wreck_t < 7.0:
			var f := clampf(1.0 - _wreck_t / 7.0, 0.3, 1.0)
			VArt.flame(self, Vector2(-8, -48), 11.0 * f, _fx_time, 2.0)
			VArt.flame(self, Vector2(-34, -34), 8.0 * f, _fx_time, 5.0)
			VArt.flame(self, Vector2(22, -36), 6.0 * f, _fx_time, 9.0)


## Barrel along the aim (world space): slides back into the mantlet when it
## fires (_recoil), muzzle brake and bore evacuator.
func _draw_gun(lv: int) -> void:
	var paint := _team_color()
	var piv := _gun_pivot() - global_position - aim_dir * _recoil * 0.35
	var back := piv - aim_dir * 2.0
	var tip := piv + aim_dir * (42.0 - _recoil)
	var dark := paint.darkened(0.6)
	draw_line(back, tip, dark, 6.5)
	draw_line(back, tip, paint.lightened(0.05), 4.0)
	if lv >= 1:
		var side := Vector2(-aim_dir.y, aim_dir.x)
		draw_line(back - side * 1.0, tip - side * 1.0, paint.lightened(0.35), 1.0)
		var mid := piv + aim_dir * (24.0 - _recoil * 0.5)
		draw_line(mid - aim_dir * 3.0, mid + aim_dir * 3.0, dark, 7.5)
	draw_line(tip - aim_dir * 7.0, tip, dark, 8.0)
	draw_line(tip - aim_dir * 6.0, tip - aim_dir * 1.0, Color(0.32, 0.32, 0.3), 5.0)
	# Mantlet over the barrel root.
	draw_circle(piv, 5.0, dark)
	draw_circle(piv, 3.8, paint)
	if fire_cd > 0.0 and fire_cd < GUN_RATE and lv >= 1 and fire_cd > GUN_RATE - 0.4:
		var hot := Color(1.0, 0.5, 0.2, (fire_cd - (GUN_RATE - 0.4)) / 0.4 * 0.8)
		draw_line(tip - aim_dir * 6.0, tip, hot, 3.0)


func _draw_overlay() -> void:
	super()
	if fire_cd > 0.0 and fire_cd < GUN_RATE:
		draw_rect(Rect2(-24, -LABEL_LIFT - 7.0, 48.0 * (1.0 - fire_cd / GUN_RATE), 3), Color(0.95, 0.8, 0.3, 0.8))
