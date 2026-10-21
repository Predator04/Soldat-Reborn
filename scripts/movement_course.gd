extends Object
## Movement course (#262) — the Training micro-map that teaches the v1.34
## movement tech: tap-to-hop vs hold-to-jump, prone-cancel and bunny-hop
## chains. Single source for the map geometry AND the gate rules:
##   * tools/make_movement_course.gd writes assets/maps/movement_course.json
##     from build() (the committed map; tools/movement_course_test.gd fails
##     if the two drift apart),
##   * scripts/training.gd runs the gates with the constants below.
## The map is not in the rotation (not in MapIO.BUNDLED_CLASSICS); Training
## loads it by path like an editor map.
##
## Layout, left to right (x px; the upper deck is TOP_Y, the floor GROUND_Y):
##   [C1 start]  short gap + spike ceiling  [C2]  medium gap  [C3]
##   long gap  [C4 = high ledge]  drop to the floor: target ring,
##   then the bunny-hop lane (start / speed / finish markers).
## The decks are solid columns down to the floor, so every gap is a pit;
## falling in (or touching the spikes) resets you to the section start.
##
## Calibration — measured headlessly in the real player physics (player.gd
## v1.34 constants, 60 Hz, running right at RUN_SPEED and holding → the whole
## time; "dx" = feet travel from the jump frame to touchdown on level ground,
## "rise" = apex height of the feet):
##   jump held 1 frame  dx  96  rise 15     held  8 frames dx 172 rise 45
##   jump held 2 frames dx 110  rise 20     held  9 frames dx 179 rise 48
##   jump held 4 frames dx 131  rise 29     held 10 frames dx 186 rise 52
##   jump held 6 frames dx 152  rise 37     held 12 frames dx 207 rise 58
##   full held jump     dx 242  rise 69     (air 0.35 s tap / 0.62 s full)
## A gap is cleared when the 14 px body still overlaps the far deck, so the
## widest gap a jump clears from the very edge is about dx + 14.
##   * SHORT gap 60 px: any tap clears it from up to ~80 px before the edge.
##     Spike tips hang 74 px above the deck: a 24 px soldier touches them
##     with a rise over 50 px — every jump held 10+ frames (0.17 s), a full
##     jump by 19 px — while every hop held up to 9 frames passes under.
##   * MEDIUM gap 90 px: a 4-frame tap clears it from up to 55 px out.
##   * LONG gap 200 px: a full jump clears it from up to 55 px out (12 frames
##     held: 21 px); 10 frames falls 1 px short, a 6-frame tap 34 px short
##     (plus the 0.09 s coyote time it is still ~20 px short).
##   So "tap" = released within ~9 frames (0.15 s), "hold" = 12+ (0.2 s);
##   10-11 frames is the grey zone that both spikes you and falls short.
## Drop from the ledge (420 px), running off at RUN_SPEED holding →:
##   no prone: lands 277 px past the edge (0.70 s in the air)
##   prone at the edge: 236 px, 0.10 s after: 243, 0.20 s: 256, 0.30 s: 263,
##   0.40-0.45 s: 270, 0.50 s+: 277 (no gain — he is about to land)
##   letting go of → instead: 142 px (prone 127-136), holding ←: ~10 px.
##   A hop / jump off the ledge carries 300-440 px even prone, so the step
##   says "don't jump" (training.gd names it when that is what happened).
##   Air steering is strong (950 px/s²), so the ring also only counts a
##   landing made prone (the gate checks the stance at touchdown).
##   #301: the ring reaches 274 px so a prone press up to ~0.45 s after the
##   edge passes (a human reacts to "I'm falling" 0.2-0.4 s late; at 268 px
##   only presses within 0.37 s did), and training.gd buffers a press made
##   up to 0.25 s BEFORE the edge (prone on the deck would slow the soldier
##   to a crawl: he dribbled off and landed ~192 px, "too short").
## Bunny lane 1400 px: running 6.83 s; chained hops (held jump, or a tap
## within the jump buffer / on the landing frame) 3.37 s at ~415 px/s with
## ~95% of the time airborne; spamming the roll 4.23 s but never airborne.

const Player = preload("res://scripts/player.gd")

const NAME := "Movement Course"
const PATH := "res://assets/maps/movement_course.json"

# The world is only 80 px taller than the 720 px view, so the camera barely
# moves vertically: from the deck you see the spikes above you and the ring
# on the floor 420 px below, and the Training panel sits at the left, behind
# a player running right.
const W := 4700.0
const H := 800.0
const GROUND_Y := 690.0
const TOP_Y := 270.0           # upper deck surface (ledge is 420 px above the floor)

# Decks (solid columns from TOP_Y to the floor): [left x, right x].
const C1 := Vector2(0.0, 700.0)
const C2 := Vector2(760.0, 1260.0)
const C3 := Vector2(1350.0, 1850.0)
const C4 := Vector2(2050.0, 2550.0)
const LEDGE_X := 2550.0        # C4's right edge — the prone drop
# Spike ceiling over the short gap: a solid block whose spike tips are
# SPIKE_CLEAR px above the deck.
const SPIKE_X := Vector2(540.0, 920.0)
const SPIKE_CLEAR := 74.0
const SPIKE_LEN := 12.0
const SPIKE_BLOCK := 30.0
# Target ring on the floor, as feet x past LEDGE_X.
const RING := Vector2(196.0, 274.0)
# Bunny-hop lane on the floor.
const LANE := Vector2(3050.0, 4450.0)
const MARKER_STEP := 200.0
# Time limit: the lane at 1.75x running speed (chained hops average ~2x,
# RUN_SPEED is read from player.gd so a retune moves the gate with it).
const LANE_SPEED_MULT := 1.75
# Hop check over the lane's velocity history: at least this share of the
# samples faster than RUN_SPEED and airborne.
const LANE_FAST_SHARE := 0.5
const LANE_AIR_SHARE := 0.5
# Below the deck by this much = fell into a pit.
const PIT_DROP := 40.0

# Course steps, in order (training.gd keys its text and gates off these).
enum { S_SHORT, S_MEDIUM, S_LONG, S_DROP, S_BUNNY }
const STEP_COUNT := 5


static func lane_limit() -> float:
	return (LANE.y - LANE.x) / (Player.RUN_SPEED * LANE_SPEED_MULT)


static func run_speed() -> float:
	return Player.RUN_SPEED


## Where a section (re)starts: feet position, standing still.
static func step_start(step: int) -> Vector2:
	match step:
		S_SHORT: return Vector2(460.0, TOP_Y - 1.0)   # right of the Training panel
		S_MEDIUM: return Vector2(1000.0, TOP_Y - 1.0)
		S_LONG: return Vector2(1460.0, TOP_Y - 1.0)
		S_DROP: return Vector2(2170.0, TOP_Y - 1.0)
		S_BUNNY: return Vector2(LEDGE_X + (RING.x + RING.y) * 0.5, GROUND_Y - 1.0)
	return step_start(S_SHORT)


## The deck a gap step lands on ([left, right]); the step is done once you
## stand on it.
static func landing_deck(step: int) -> Vector2:
	match step:
		S_SHORT: return C2
		S_MEDIUM: return C3
		S_LONG: return C4
	return Vector2.ZERO


## Solid ceiling block + its spikes; touching it counts as a hit.
static func spike_rect() -> Rect2:
	var bottom := TOP_Y - SPIKE_CLEAR - SPIKE_LEN
	# Bottom edge = the spike tips exactly (Rect2.intersects ignores touching).
	return Rect2(SPIKE_X.x - 1.0, bottom - SPIKE_BLOCK - 1.0, SPIKE_X.y - SPIKE_X.x + 2.0, SPIKE_BLOCK + SPIKE_LEN + 1.0)


static func _deck(c: Vector2) -> Dictionary:
	return {"p": Vector2((c.x + c.y) * 0.5, (TOP_Y + GROUND_Y) * 0.5), "s": Vector2(c.y - c.x, GROUND_Y - TOP_Y)}


static func _deco(pts: Array, col: Color) -> Dictionary:
	return {"points": PackedVector2Array(pts), "color": col, "texture": "", "col": 3}


static func _post(x: float, h: float, col: Color) -> Dictionary:
	return _deco([Vector2(x - 3, GROUND_Y - h), Vector2(x + 3, GROUND_Y - h), Vector2(x + 3, GROUND_Y), Vector2(x - 3, GROUND_Y)], col)


## The map dict (main.gd / MapIO shape).
static func build() -> Dictionary:
	var spike_bottom := TOP_Y - SPIKE_CLEAR - SPIKE_LEN
	var platforms: Array = [_deck(C1), _deck(C2), _deck(C3), _deck(C4),
		{"p": Vector2((SPIKE_X.x + SPIKE_X.y) * 0.5, spike_bottom - SPIKE_BLOCK * 0.5), "s": Vector2(SPIKE_X.y - SPIKE_X.x, SPIKE_BLOCK)}]
	var polys: Array = []
	# Spike teeth (decorative — the gate treats the whole block as the hazard).
	var red := Color(0.86, 0.18, 0.14)
	var x := SPIKE_X.x
	while x < SPIKE_X.y - 1.0:
		polys.append(_deco([Vector2(x, spike_bottom), Vector2(x + 20.0, spike_bottom), Vector2(x + 10.0, spike_bottom + SPIKE_LEN)], red))
		x += 20.0
	# Danger stripes on the pit floors.
	for gap in [Vector2(C1.y, C2.x), Vector2(C2.y, C3.x), Vector2(C3.y, C4.x)]:
		polys.append(_deco([Vector2(gap.x, GROUND_Y - 6), Vector2(gap.y, GROUND_Y - 6), Vector2(gap.y, GROUND_Y), Vector2(gap.x, GROUND_Y)], Color(0.9, 0.55, 0.1)))
	# Target ring: a band on the floor between two flags.
	var r0 := LEDGE_X + RING.x
	var r1 := LEDGE_X + RING.y
	polys.append(_deco([Vector2(r0, GROUND_Y - 5), Vector2(r1, GROUND_Y - 5), Vector2(r1, GROUND_Y), Vector2(r0, GROUND_Y)], Color(1.0, 0.85, 0.2)))
	polys.append(_deco([Vector2(r0 + 10, GROUND_Y - 5), Vector2(r1 - 10, GROUND_Y - 5), Vector2(r1 - 10, GROUND_Y - 2), Vector2(r0 + 10, GROUND_Y - 2)], red))
	for rx in [r0, r1]:
		polys.append(_post(rx, 40.0, Color(1.0, 0.85, 0.2)))
	# Lane: green start, speed markers, chequered-yellow finish.
	polys.append(_post(LANE.x, 90.0, Color(0.3, 0.9, 0.4)))
	var mx := LANE.x + MARKER_STEP
	while mx < LANE.y - 1.0:
		polys.append(_post(mx, 34.0, Color(0.55, 0.75, 1.0)))
		mx += MARKER_STEP
	polys.append(_post(LANE.y, 90.0, Color(1.0, 0.85, 0.2)))
	for i in 4:
		var y0 := GROUND_Y - 90.0 + i * 12.0
		polys.append(_deco([Vector2(LANE.y + 3, y0), Vector2(LANE.y + 27, y0), Vector2(LANE.y + 27, y0 + 6), Vector2(LANE.y + 3, y0 + 6)],
			Color(0.1, 0.1, 0.1) if i % 2 == 0 else Color(1.0, 0.85, 0.2)))
	return {
		"name": NAME,
		"world": {"w": W, "h": H, "ground_y": GROUND_Y},
		"terrain_texture": "res://assets/textures/ctf_steel.png",
		"platforms": platforms,
		"polys": polys,
		"player_spawn": step_start(S_SHORT),
		# No bot spawns: no bots, and no random bonus crates (they fall back
		# to bot spawns) — a Predator speed boost would trivialise the lane.
		"bot_spawns": [],
		# Mode entities on open ground so the map audit's default-position
		# checks pass; Training only ever plays it as Deathmatch.
		"ctf_flags": [Vector2(120.0, TOP_Y - 2.0), Vector2(W - 120.0, GROUND_Y - 2.0)],
		"inf_flag": Vector2(3800.0, GROUND_Y - 2.0),
		"htf_flag": Vector2(3800.0, GROUND_Y - 2.0),
		"rambo_pos": Vector2(3800.0, GROUND_Y - 40.0),
		"dom_points": [Vector2(1100.0, TOP_Y - 30.0), Vector2(2300.0, TOP_Y - 30.0), Vector2(3800.0, GROUND_Y - 30.0)],
	}
