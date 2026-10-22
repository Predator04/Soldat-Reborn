extends RefCounted
## Vehicle art (#276): the procedural drawing kit shared by the buggy, the tank
## and the helicopter. COSMETIC ONLY — every function here only draws on the
## canvas item it is handed (or reads Settings / quality); nothing touches a
## physics body, game state, timers, the network or the global random stream.
##
## Look: dark gunmetal hulls with a vertical light-to-shadow gradient, panel
## lines, grime and wear, a bright team trim plus a team MARK whose shape (not
## just colour) tells the sides apart (Settings.team_colors picks the palette in
## TeamColors, #306), a cool rim along the edges that face the key light
## (the same direction the cinematic rim_light.gdshader uses — the shader finds
## edges from texture alpha, which flat polygon draws don't have, so vehicles
## paint their rim themselves), subtle neon instrument / underglow accents.
## Quality: Low = flat shapes, no extras; Medium = gradients, grime, damage
## marks, light cones; High = everything (+ real pooled lights, done by the
## vehicles through Atmosphere.light_keep). The classic visual style keeps the
## shading but drops the rim and the neon.
##
## Shapes are built once (static caches); per-frame work is colour picks and
## draw calls only.

const Gfx = preload("res://scripts/gfx.gd")
const TeamColors = preload("res://scripts/team_colors.gd")

const LIGHT_DIR := Vector2(0.5512, -0.8344)   # rim_light.gdshader light_from, normalised
const RIM_COL := Color(0.70, 0.84, 1.0)
const BOUNCE_COL := Color(1.0, 0.62, 0.38)
const STEEL := Color(0.135, 0.145, 0.155)
const STEEL_HI := Color(0.34, 0.36, 0.38)
const RUBBER := Color(0.055, 0.055, 0.06)
const CHAR := Color(0.065, 0.06, 0.055)
const CHAR_HI := Color(0.16, 0.13, 0.11)
const NEON := Color(0.30, 0.88, 1.0)
const NEUTRAL_TRIM := Color(1.0, 0.6, 0.2)
const SOOT := Color(0.03, 0.028, 0.025)


static func level() -> int:
	return clampi(Gfx.q(), 0, 2)


## Cinematic look (Medium+). Unlike Atmosphere.cinematic() this does not bail
## out headless, so the gate's draw-path smoke test runs every branch.
static func cinematic() -> bool:
	return Settings.visual_style == "cinematic" and Gfx.on(Gfx.MEDIUM)


## Hull paint: the kind's drab base, nudged toward the team colour in team modes
## and graded darker for the cinematic look.
static func paint(base: Color, team: int, team_mode: bool) -> Color:
	var c := base
	if team_mode and (team == 1 or team == 2):
		c = c.lerp(TeamColors.for_team(team), 0.2)
	if cinematic():
		c = c.darkened(0.18)
	return c


## Bright team trim (stripes, mark, underglow). Neutral ember when nobody's in
## it or the mode has no teams.
static func trim(team: int, team_mode: bool) -> Color:
	if team_mode and (team == 1 or team == 2):
		return TeamColors.for_team(team, true)
	return NEUTRAL_TRIM


# ── shape helpers ────────────────────────────────────────────────────────

static func pv(arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in arr:
		out.append(p)
	return out


## Outward edge normals of a closed polygon (edge i = pts[i] -> pts[i+1]).
static func normals(pts: PackedVector2Array) -> PackedVector2Array:
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= maxf(1.0, float(pts.size()))
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var e := (b - a).normalized()
		var nn := Vector2(e.y, -e.x)
		if nn.dot((a + b) * 0.5 - c) < 0.0:
			nn = -nn
		out.append(nn)
	return out


## Per-vertex vertical gradient colours (light at y0, shadow at y1).
static func vgrad(pts: PackedVector2Array, top: Color, bottom: Color, y0: float, y1: float) -> PackedColorArray:
	var out := PackedColorArray()
	var span := maxf(0.01, y1 - y0)
	for p in pts:
		out.append(top.lerp(bottom, clampf((p.y - y0) / span, 0.0, 1.0)))
	return out


## A shaded hull piece: gradient fill (flat on Low) + optional dark outline.
static func part(ci: CanvasItem, pts: PackedVector2Array, cols: PackedColorArray, flat: Color, outline: Color, w := 1.2) -> void:
	if level() >= 1 and cols.size() == pts.size():
		ci.draw_polygon(pts, cols)
	else:
		ci.draw_colored_polygon(pts, flat)
	if outline.a > 0.0:
		ci.draw_polyline(pts, outline, w)
		ci.draw_line(pts[pts.size() - 1], pts[0], outline, w)


## Rim light on the edges of `pts` that face the key light, given the draw
## transform the vehicle uses (x flipped by `face`, then rotated by `tilt`).
## Cinematic only; the far edges get a faint warm bounce on High.
static func rim(ci: CanvasItem, pts: PackedVector2Array, nrm: PackedVector2Array, face: float, tilt: float, strength := 1.0, width := 1.5) -> void:
	if not cinematic():
		return
	var n := pts.size()
	var hi := level() >= 2
	for i in n:
		var ln := nrm[i]
		var wn := Vector2(ln.x * face, ln.y).rotated(tilt)
		var d := wn.dot(LIGHT_DIR)
		if d > 0.2:
			var c := RIM_COL
			c.a = clampf((d - 0.2) * 1.4, 0.0, 1.0) * 0.8 * strength
			ci.draw_line(pts[i], pts[(i + 1) % n], c, width)
		elif hi and d < -0.55:
			var b := BOUNCE_COL
			b.a = clampf((-d - 0.55) * 2.0, 0.0, 1.0) * 0.16 * strength
			ci.draw_line(pts[i], pts[(i + 1) % n], b, width)


## Tube (roll cage, struts, skids): dark core, lit top edge.
static func tube(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, w: float) -> void:
	ci.draw_line(a, b, col.darkened(0.45), w + 1.0)
	ci.draw_line(a, b, col, w)
	if level() >= 1:
		var off := Vector2(0, -w * 0.28)
		ci.draw_line(a + off, b + off, col.lightened(0.35), maxf(0.8, w * 0.32))


## Wheel: knobbly tyre, dished rim with a lit arc, spokes — or, at speed, a
## motion-blurred disc with streaks. `burnt`: a wreck's bare charred rim.
static func wheel(ci: CanvasItem, c: Vector2, r: float, rot: float, speed: float, rim_col: Color, burnt := false) -> void:
	var lv := level()
	if burnt:
		ci.draw_circle(c, r * 0.72, CHAR)
		ci.draw_arc(c, r * 0.72, 0.0, TAU, 12, CHAR_HI, 1.4)
		for k in 4:
			var a := rot + k * TAU / 4.0
			ci.draw_line(c, c + Vector2(cos(a), sin(a)) * r * 0.62, CHAR_HI, 1.4)
		return
	ci.draw_circle(c, r, RUBBER)
	if lv >= 1:
		# Tread knobs ride the tyre's edge.
		var kc := Color(0.12, 0.12, 0.125)
		for k in 10:
			var a := rot + k * TAU / 10.0
			var dir := Vector2(cos(a), sin(a))
			ci.draw_line(c + dir * (r - 1.6), c + dir * (r + 0.4), kc, 2.2)
		ci.draw_arc(c, r - 0.6, -PI * 0.85, -PI * 0.25, 6, Color(0.3, 0.3, 0.32, 0.5), 1.0)
	var rr := r * 0.6
	ci.draw_circle(c, rr, rim_col.darkened(0.35))
	ci.draw_circle(c, rr * 0.82, rim_col)
	var blur := absf(speed) > 240.0 and lv >= 1
	if blur:
		var bc := rim_col.darkened(0.2)
		bc.a = 0.7
		ci.draw_circle(c, rr * 0.7, bc)
		for k in 3:
			var a0 := rot * 0.25 + k * TAU / 3.0
			ci.draw_arc(c, rr * (0.45 + k * 0.12), a0, a0 + 1.6, 5, Color(0.08, 0.08, 0.09, 0.55), 1.0)
	else:
		for k in 5:
			var a := rot + k * TAU / 5.0
			ci.draw_line(c + Vector2(cos(a), sin(a)) * rr * 0.25, c + Vector2(cos(a), sin(a)) * rr * 0.78, rim_col.darkened(0.5), 1.6)
	if lv >= 1:
		ci.draw_arc(c, rr * 0.9, -PI * 0.8, -PI * 0.2, 6, rim_col.lightened(0.45), 1.0)
	ci.draw_circle(c, rr * 0.28, Color(0.08, 0.08, 0.085))
	ci.draw_circle(c + Vector2(-0.4, -0.4), rr * 0.12, STEEL_HI)


## Coil-over spring between two points (suspension).
static func spring(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, coils := 4) -> void:
	var d := b - a
	var side := Vector2(-d.y, d.x).normalized() * 2.4
	var prev := a
	var n := coils * 2
	for i in range(1, n + 1):
		var t := float(i) / float(n + 1)
		var p := a + d * t + side * (1.0 if i % 2 == 0 else -1.0)
		ci.draw_line(prev, p, col, 1.2)
		prev = p
	ci.draw_line(prev, b, col, 1.2)


## Team mark, a shape per side so it reads without colour: roundel (blue),
## chevron (red / orange), small diamond (no team).
static func mark(ci: CanvasItem, at: Vector2, team: int, team_mode: bool, s: float) -> void:
	var col := trim(team, team_mode)
	var dark := Color(0.02, 0.02, 0.025, 0.85)
	if team_mode and team == 1:
		ci.draw_circle(at, s + 1.2, dark)
		ci.draw_circle(at, s, col)
		ci.draw_circle(at, s * 0.45, dark)
	elif team_mode and team == 2:
		var pts := PackedVector2Array([at + Vector2(-s, -s * 0.9), at + Vector2(0, -s * 0.1), at + Vector2(s, -s * 0.9),
			at + Vector2(s, -s * 0.1), at + Vector2(0, s * 0.8), at + Vector2(-s, -s * 0.1)])
		ci.draw_colored_polygon(pts, col)
		ci.draw_polyline(pts, dark, 1.0)
	else:
		var pts2 := PackedVector2Array([at + Vector2(0, -s * 0.8), at + Vector2(s * 0.8, 0), at + Vector2(0, s * 0.8), at + Vector2(-s * 0.8, 0)])
		ci.draw_colored_polygon(pts2, col.darkened(0.15))


## Soft light cone (head / search lights): bright at the lamp, fading out.
## Drawn with normal blending so it reads in both looks; Medium+.
static func cone(ci: CanvasItem, o: Vector2, dir: Vector2, length: float, half: float, col: Color) -> void:
	if level() < 1:
		return
	var far := col
	far.a = 0.0
	var mid := col
	mid.a *= 0.35
	var a := dir.rotated(-half) * length
	var b := dir.rotated(half) * length
	ci.draw_polygon(PackedVector2Array([o, o + a * 0.55, o + b * 0.55]), PackedColorArray([col, mid, mid]))
	ci.draw_polygon(PackedVector2Array([o + a * 0.55, o + a, o + b, o + b * 0.55]), PackedColorArray([mid, far, far, mid]))


## Flickering flame tongue (damage fire / wreck), deterministic from `t`.
static func flame(ci: CanvasItem, at: Vector2, size: float, t: float, seed_f: float) -> void:
	for k in 3:
		var f := 1.0 - k * 0.3
		var h := size * f * (1.25 + 0.35 * sin(t * 13.0 + seed_f + k * 2.1) + 0.2 * sin(t * 29.0 + seed_f * 1.7))
		var w := size * 0.42 * f
		var sway := sin(t * 7.0 + seed_f + k) * w * 0.5
		var col: Color = [Color(1.0, 0.38, 0.1, 0.55), Color(1.0, 0.62, 0.2, 0.75), Color(1.0, 0.9, 0.55, 0.9)][k]
		ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-w, 0), at + Vector2(-w * 0.5, -h * 0.45), at + Vector2(sway, -h),
			at + Vector2(w * 0.5, -h * 0.45), at + Vector2(w, 0), at + Vector2(0, w * 0.35)]), col)


## Damage marks over the hull: scorch blotches + bullet holes, more of them as
## `dmg` (0 pristine .. 1 wrecked) rises. `spots` = [pos, radius] pairs baked
## per vehicle from its own seeded stream.
static func scorch(ci: CanvasItem, spots: Array, dmg: float) -> void:
	if level() < 1 or dmg < 0.25:
		return
	var n := int(ceil(spots.size() * clampf((dmg - 0.25) / 0.6, 0.0, 1.0)))
	for i in mini(n, spots.size()):
		var s: Array = spots[i]
		var p: Vector2 = s[0]
		var r: float = s[1]
		if i % 3 == 2:
			# Bullet hole: dark pit, bright torn rim.
			ci.draw_circle(p, 1.3, Color(0.02, 0.02, 0.02, 0.95))
			ci.draw_arc(p, 1.7, -PI * 0.9, -PI * 0.1, 4, Color(0.7, 0.66, 0.6, 0.6), 0.8)
		else:
			ci.draw_circle(p, r, Color(0.04, 0.035, 0.03, 0.45))
			ci.draw_circle(p, r * 0.55, Color(0.02, 0.018, 0.015, 0.55))


## Bake damage-mark spots inside a box, from a stream seeded per vehicle (never
## the global random stream).
static func bake_spots(seed_i: int, box: Rect2, n: int) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = seed_i * 7919 + 17
	var out: Array = []
	for i in n:
		out.append([Vector2(r.randf_range(box.position.x, box.end.x), r.randf_range(box.position.y, box.end.y)), r.randf_range(2.5, 5.5)])
	return out


## Thin grime band along the bottom of a hull piece (dirt / oil), Medium+.
static func grime(ci: CanvasItem, x0: float, x1: float, y_top: float, y_bot: float, a: float) -> void:
	if level() < 1:
		return
	var c0 := Color(0.09, 0.075, 0.055, 0.0)
	var c1 := Color(0.09, 0.075, 0.055, a)
	ci.draw_polygon(PackedVector2Array([Vector2(x0, y_top), Vector2(x1, y_top), Vector2(x1, y_bot), Vector2(x0, y_bot)]),
		PackedColorArray([c0, c0, c1, c1]))


## HP bar (above the vehicle, world space).
static func hp_bar(ci: CanvasItem, at: Vector2, w: float, frac: float) -> void:
	ci.draw_rect(Rect2(at.x - w * 0.5 - 1, at.y - 1, w + 2, 6), Color(0, 0, 0, 0.6))
	ci.draw_rect(Rect2(at.x - w * 0.5, at.y, w * clampf(frac, 0.0, 1.0), 4), Color(0.9, 0.3, 0.2).lerp(Color(0.4, 0.9, 0.3), frac))


## Small lamp lens with a glow halo (head / tail / nav lights).
static func lamp(ci: CanvasItem, at: Vector2, col: Color, r: float, on: bool) -> void:
	if not on:
		ci.draw_circle(at, r, col.darkened(0.7))
		return
	if level() >= 1:
		var h := col
		h.a = 0.22
		ci.draw_circle(at, r * 3.2, h)
		h.a = 0.4
		ci.draw_circle(at, r * 1.8, h)
	ci.draw_circle(at, r, col.lightened(0.4))
