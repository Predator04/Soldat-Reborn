extends Node2D
## Flag visual — waving cloth on a pole, drawn for the CTF / INF / HTF flag
## Area2D it's parented to. Three looks, picked every frame from the parent's
## metadata (so it works identically on host and clients):
##   • at home   — upright on a stone base with a soft pulsing team glow
##   • carried   — smaller flag strapped to the carrier's back, leaning with
##                 their facing and streaming behind them as they move
##   • dropped   — pole planted at an angle plus a blinking beacon so players
##                 can find it
## Pure _draw(): no textures, so it scales with the soldier art and stays
## crisp at any zoom.

const CLOTH_W := 34.0
const CLOTH_H := 22.0
const POLE_H := 58.0
const SEGMENTS := 10

var team: int = 0
var _t := 0.0
var _last_pos := Vector2.ZERO
var _vel_x := 0.0


func _ready() -> void:
	var p := get_parent()
	if p != null and p.has_meta("team"):
		team = int(p.get_meta("team"))
	_t = randf() * 10.0
	_last_pos = global_position


func _process(delta: float) -> void:
	_t += delta
	# Smoothed horizontal speed drives how hard the cloth streams.
	if delta > 0.0:
		var vx := (global_position.x - _last_pos.x) / delta
		_vel_x = lerpf(_vel_x, clampf(vx, -600.0, 600.0), minf(1.0, delta * 6.0))
	_last_pos = global_position
	queue_redraw()


func _team_color() -> Color:
	match team:
		1: return Color(0.22, 0.46, 1.0)   # BLUE
		2: return Color(0.93, 0.22, 0.18)  # RED
		_: return Color(0.98, 0.78, 0.18)  # neutral (INF / HTF)


func _carrier() -> Node2D:
	var p := get_parent()
	if p == null or not p.has_meta("carrier"):
		return null
	var c: Variant = p.get_meta("carrier")
	# Carrier can be freed (killed bot) before main.gd clears the meta.
	if c == null or not is_instance_valid(c):
		return null
	if c is Node2D and not bool((c as Node2D).get("dead")):
		return c
	return null


func _draw() -> void:
	var col := _team_color()
	var carrier := _carrier()
	if carrier != null:
		_draw_carried(carrier, col)
		return
	var p := get_parent()
	var home: Vector2 = p.get_meta("home") if p != null and p.has_meta("home") else global_position
	if (p as Node2D).position.distance_to(home) <= 12.0:
		_draw_home(col)
	else:
		_draw_dropped(col)


# ── states ────────────────────────────────────────────────────────────────

func _draw_home(col: Color) -> void:
	# Pulsing ground glow.
	var pulse := 0.5 + 0.5 * sin(_t * 2.4)
	for i in 3:
		var r := 22.0 + float(i) * 7.0 + pulse * 3.0
		_draw_ellipse(Vector2(0, -1), Vector2(r, r * 0.28), Color(col, 0.10 - float(i) * 0.025))
	# Stone base.
	_draw_ellipse(Vector2(0, 0), Vector2(15, 4.5), Color(0.12, 0.12, 0.14, 0.55))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-11, 0), Vector2(-8, -6), Vector2(8, -6), Vector2(11, 0)]), Color(0.38, 0.37, 0.36))
	draw_line(Vector2(-8, -6), Vector2(8, -6), Color(0.62, 0.6, 0.57), 1.5)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-5, -6), Vector2(-4, -10), Vector2(4, -10), Vector2(5, -6)]), Color(0.3, 0.29, 0.28))
	_draw_flag(Vector2(0, -10), Vector2(0, -10 - POLE_H), 1.0, 1.0, col, 0.0)


func _draw_dropped(col: Color) -> void:
	# Planted at a lean, with a blinking beacon above so it's easy to spot.
	var lean := Vector2(0.28, -1.0).normalized()
	var base := Vector2(0, 0)
	var top := base + lean * (POLE_H * 0.85)
	_draw_ellipse(Vector2(0, 0), Vector2(10, 3), Color(0, 0, 0, 0.4))
	_draw_flag(base, top, 0.85, 1.0, col, 0.0)
	# Bobbing "pick me up" chevron above the dropped flag.
	var blink := 0.5 + 0.5 * sin(_t * 7.0)
	var bp := top + Vector2(0, -14.0 - 4.0 * sin(_t * 4.0))
	var chev := PackedVector2Array([bp + Vector2(-7, -5), bp + Vector2(7, -5), bp + Vector2(0, 3)])
	draw_colored_polygon(chev, Color(col.lightened(0.2), 0.55 + 0.45 * blink))
	draw_polyline(PackedVector2Array([chev[0], chev[1], chev[2], chev[0]]), Color(0, 0, 0, 0.6), 1.0, true)


func _draw_carried(carrier: Node2D, col: Color) -> void:
	# The parent Area2D sits at carrier_feet + (0, -30) (main.gd keeps that
	# offset for its scoring distance checks); draw relative to the feet.
	var facing: float = float(carrier.get("facing")) if carrier.get("facing") != null else 1.0
	if facing == 0.0:
		facing = 1.0
	var feet := carrier.global_position - global_position
	var base := feet + Vector2(-facing * 4.0, -8.0)
	var top := feet + Vector2(-facing * 13.0, -52.0)
	# Stream harder against the direction of travel.
	var stream := clampf(absf(_vel_x) / 300.0, 0.0, 1.0)
	_draw_flag(base, top, 0.72, -facing, col, stream)


# ── primitives ────────────────────────────────────────────────────────────

func _draw_flag(base: Vector2, top: Vector2, s: float, dir: float, col: Color, stream: float) -> void:
	# Pole: dark core + lit edge + gold finial.
	var axis := (top - base).normalized()
	var side := Vector2(-axis.y, axis.x)
	draw_line(base, top, Color(0.2, 0.18, 0.16), 3.2 * s)
	draw_line(base + side * 0.8 * s, top + side * 0.8 * s, Color(0.72, 0.68, 0.6), 1.1 * s)
	draw_circle(top + axis * 2.5 * s, 3.0 * s, Color(0.85, 0.68, 0.22))
	draw_circle(top + axis * 2.5 * s + Vector2(-0.8, -0.8) * s, 1.2 * s, Color(1, 0.95, 0.7))
	# Cloth: a waving strip hanging off the pole top, rendered as a polygon
	# strip with per-vertex shading (crests lighter, troughs darker).
	var w := CLOTH_W * s
	var h := CLOTH_H * s
	var attach := top + axis * -1.0 * s
	var amp := (3.2 - 1.2 * stream) * s
	var droop := (1.0 - stream) * 5.0 * s
	var speed := 5.5 + 5.0 * stream
	var topl := PackedVector2Array()
	var botl := PackedVector2Array()
	var shade := PackedFloat32Array()
	for i in SEGMENTS + 1:
		var u := float(i) / float(SEGMENTS)
		var ph := _t * speed - u * 5.0
		var wave := sin(ph) * amp * u
		var x := dir * u * w
		var y_off := wave + droop * u * u
		topl.append(attach + Vector2(x, y_off))
		botl.append(attach + Vector2(x, y_off + h * (1.0 - 0.08 * u)))
		shade.append(0.5 + 0.5 * cos(ph))
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in SEGMENTS + 1:
		pts.append(topl[i])
		cols.append(col.lightened(0.18 * shade[i]).darkened(0.12 * (1.0 - shade[i])))
	for i in range(SEGMENTS, -1, -1):
		pts.append(botl[i])
		cols.append(col.darkened(0.18 + 0.22 * (1.0 - shade[i])))
	draw_polygon(pts, cols)
	# Emblem: a white chevron-star in the middle of the cloth.
	var mid_i := SEGMENTS / 2
	var c := (topl[mid_i] + botl[mid_i]) * 0.5
	_draw_star(c, 5.0 * s, Color(1, 1, 1, 0.85))
	# Crisp outline + stitched hem along the pole side.
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, Color(0, 0, 0, 0.55), 1.2, true)
	draw_line(topl[0], botl[0], Color(1, 1, 1, 0.35), 2.0 * s)


func _draw_star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + float(i) * PI / 5.0
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, col)


func _draw_ellipse(c: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * float(i) / 20.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_colored_polygon(pts, col)
