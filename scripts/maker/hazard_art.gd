extends Object
## Vector art for the Maker-mode map hazards (#286): spike rows, lava pools
## and jump pads. Shared by the in-game visual (scripts/maker/hazard_visual.gd),
## the editor view and the palette thumbnails, so all three always match.
## Pure drawing: no state, no RNG (time comes in as an argument).

const STEEL_LIT := Color(0.86, 0.88, 0.92)
const STEEL_MID := Color(0.56, 0.6, 0.66)
const STEEL_DARK := Color(0.24, 0.26, 0.3)
const LAVA_HOT := Color(1.0, 0.86, 0.36)
const LAVA_MID := Color(1.0, 0.42, 0.08)
const LAVA_DEEP := Color(0.52, 0.06, 0.03)
const PAD_COL := Color(0.30, 0.88, 1.0)       # normal pad (UITheme neon)
const PAD_BIG_COL := Color(1.0, 0.62, 0.18)   # big pad (UITheme ember)
const PAD_W := 64.0
const PAD_H := 14.0


## A row of spikes filling `r`, tips pointing `dir` (0 up, 1 right, 2 down,
## 3 left).
static func draw_spikes(ci: CanvasItem, r: Rect2, dir: int = 0) -> void:
	var c := r.get_center()
	var along := r.size.x if dir % 2 == 0 else r.size.y
	var tall := r.size.y if dir % 2 == 0 else r.size.x
	ci.draw_set_transform(c, float(dir) * PI * 0.5, Vector2.ONE)
	var x0 := -along * 0.5
	var base_y := tall * 0.5
	var plate := maxf(3.0, tall * 0.16)
	ci.draw_rect(Rect2(x0, base_y - plate, along, plate), STEEL_DARK)
	ci.draw_rect(Rect2(x0, base_y - plate, along, maxf(1.0, plate * 0.3)), STEEL_MID)
	var n := maxi(1, int(round(along / 18.0)))
	var sw := along / float(n)
	for i in n:
		var l := x0 + sw * float(i) + sw * 0.08
		var rr := x0 + sw * float(i + 1) - sw * 0.08
		var mid := (l + rr) * 0.5
		var tip := Vector2(mid, -tall * 0.5)
		var b := base_y - plate
		ci.draw_colored_polygon(PackedVector2Array([Vector2(l, b), tip, Vector2(mid, b)]), STEEL_LIT)
		ci.draw_colored_polygon(PackedVector2Array([Vector2(mid, b), tip, Vector2(rr, b)]), STEEL_MID)
		ci.draw_line(Vector2(mid, b), tip, STEEL_DARK.lightened(0.2), 1.0, true)
		ci.draw_circle(tip + Vector2(0, 1.5), 1.2, Color(1, 1, 1, 0.8))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A lava pool filling `r`. `t` = seconds (surface waves / bubbles).
static func draw_lava(ci: CanvasItem, r: Rect2, t: float = 0.0, glow: bool = true) -> void:
	var top := r.position.y
	var bot := r.end.y
	var n := clampi(int(r.size.x / 24.0), 4, 160)
	var surf := PackedVector2Array()
	for i in n + 1:
		var x := r.position.x + r.size.x * float(i) / float(n)
		var y := top + 3.0 + sin(x * 0.045 + t * 2.1) * 2.2 + sin(x * 0.11 - t * 3.3) * 1.2
		surf.append(Vector2(x, y))
	if glow:
		var gh := minf(36.0, 18.0 + r.size.x * 0.02)
		ci.draw_polygon(PackedVector2Array([Vector2(r.position.x, top - gh), Vector2(r.end.x, top - gh), Vector2(r.end.x, top + 4), Vector2(r.position.x, top + 4)]),
			PackedColorArray([Color(LAVA_MID, 0.0), Color(LAVA_MID, 0.0), Color(LAVA_MID, 0.3), Color(LAVA_MID, 0.3)]))
	# Body: hot under the surface, deep red at the bottom.
	var body := PackedVector2Array(surf)
	body.append(Vector2(r.end.x, bot))
	body.append(Vector2(r.position.x, bot))
	var cols := PackedColorArray()
	for _p in surf:
		cols.append(LAVA_MID)
	cols.append(LAVA_DEEP)
	cols.append(LAVA_DEEP)
	ci.draw_polygon(body, cols)
	# Bright crust line + a few drifting bubbles (deterministic per index).
	ci.draw_polyline(surf, LAVA_HOT, 3.0, true)
	var nb := clampi(int(r.size.x / 70.0), 1, 40)
	for i in nb:
		var ph := fposmod(t * 0.45 + float(i) * 0.618, 1.0)
		var bx := r.position.x + r.size.x * fposmod(float(i) * 0.381 + 0.13, 1.0)
		var by := lerpf(bot - 4.0, top + 6.0, ph)
		if by < bot - 2.0:
			ci.draw_circle(Vector2(bx, by), 2.0 + 2.0 * ph, Color(LAVA_HOT, 0.75 * (1.0 - ph * 0.6)))


## A jump pad standing on `foot` (bottom centre). `fired` = seconds since it
## last launched someone (animates the plate), `big` = the strong variant.
static func draw_pad(ci: CanvasItem, foot: Vector2, big: bool = false, fired: float = 9.0, scale_px: float = 1.0) -> void:
	var col := PAD_BIG_COL if big else PAD_COL
	var w := PAD_W * scale_px
	var h := PAD_H * scale_px
	var push := clampf(1.0 - fired / 0.35, 0.0, 1.0)
	# Base housing.
	ci.draw_colored_polygon(PackedVector2Array([foot + Vector2(-w * 0.5, 0), foot + Vector2(w * 0.5, 0),
		foot + Vector2(w * 0.42, -h * 0.55), foot + Vector2(-w * 0.42, -h * 0.55)]), STEEL_DARK)
	ci.draw_line(foot + Vector2(-w * 0.42, -h * 0.55), foot + Vector2(w * 0.42, -h * 0.55), STEEL_MID, maxf(1.0, scale_px * 1.5), true)
	# Plate (pops up when it fires).
	var py := -h * 0.55 - h * 0.25 - push * h * 0.9
	ci.draw_rect(Rect2(foot + Vector2(-w * 0.38, py - h * 0.28), Vector2(w * 0.76, h * 0.34)), col)
	ci.draw_rect(Rect2(foot + Vector2(-w * 0.38, py - h * 0.28), Vector2(w * 0.76, h * 0.1)), col.lightened(0.45))
	# Chevrons.
	var a := 0.45 + 0.55 * push
	var chevrons := 3 if big else 2
	for i in chevrons:
		var y := foot.y + py - h * 0.7 - float(i) * h * 0.75
		ci.draw_polyline(PackedVector2Array([Vector2(foot.x - w * 0.18, y + h * 0.32), Vector2(foot.x, y), Vector2(foot.x + w * 0.18, y + h * 0.32)]),
			Color(col, a * (1.0 - float(i) * 0.25)), maxf(1.5, 3.0 * scale_px), true)
