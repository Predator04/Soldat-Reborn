extends RefCounted
## Skeletal gostek renderer, driven by .poa frames.
## Each body-part sprite hangs between two skeleton joints (p1, p2) with
## a normalized pivot (cx_frac, cy_frac) — see references/poa-format.md.
##
## Callers pass a gameplay state dict on every draw; we pick the current
## anim from it, advance a per-instance clock, and blit the parts.

const PoaLoader = preload("res://scripts/poa_loader.gd")

const DIR := "res://assets/gostek-gfx/"

# Scale factor from .poa loader units → local Godot pixels. The loader
# already applies Anims.pas SCALE=3; this puts feet at ~+20 (bottom of
# the CharacterBody2D collision box) and head at ~-25.
const POA_TO_PIXEL := 1.0
const FEET_OFFSET_Y := 3.0

# Soldat's mod.ini has DefaultScale=4.5 → gostek sprites are drawn at 1/3 of
# their native pixel size (the PNGs are stored 3x for HD). Missing this makes
# the soldier render 3x too wide ("fat"). Flex formula below is unaffected.
const SPRITE_SCALE := 1.0 / 3.0

# Anims.pas runs its animation counter at physics tick rate (~60 Hz).
const TICK_RATE := 60.0

# Cross-fade between animation states (run→jump, jump→fall, land→idle) instead
# of hard-cutting to frame 0 of the new anim. Frozen-fade-out (the old pose is
# held and lerped toward the animating new one) — over ~0.12s this reads as a
# smooth transition without the cost of advancing both anims in parallel.
const BLEND_TIME := 0.12

# Movement speed above which the soldier plays biega/biegatyl instead of stoi.
const RUN_THRESHOLD := 45.0

# Front-arm (RIGHT_*) aim overlay (#59). Soldat's arms barely follow the aim
# axis — a few degrees is enough to sell "the gun is aimed there" without
# breaking the canned .poa poses. Clamp to ±16°.
const AIM_ARM_LIMIT := 0.28

# Back-to-front draw order. Rows are:
#   [sprite_key, p1, p2, cx_frac, cy_frac, flex_units, color_kind]
# Matches the GostekBase entries in GostekGraphics.inc for a plain
# soldier plus the customizable head + optional torso pieces.
# `sprite_key` may be a resolved name (e.g. "helm") OR a tag like `<head>`
# which draw_body swaps for the current head cosmetic (or skips).
# Detail overlays (#60):
#   <dreadlocks>     dred tuft, sits on top of the head; needs a hair head
#   <dogtag>         metal dogtag hanging from the chain, over the chest
#   <grenade_belt>   frag/cluster grenade sprite riding on the hip belt
#   <secondary_back> the currently-inactive weapon slung across the back
# Blood/damage sprites (ranny/*.png) auto-overlay on top of the wounded body
# parts once health drops below WOUND_HEALTH.
const PARTS := [
	# --- back leg (LEFT_*) ------------------------------
	["udo",    6,  3, 0.20, 0.50, 5.0, "pants"],
	["noga",   3,  2, 0.15, 0.55, 0.0, "pants"],
	["stopa",  2, 18, 0.35, 0.35, 0.0, "none"],
	# --- back arm (LEFT_*) ------------------------------
	["ramie", 11, 14, 0.00, 0.50, 0.0, "main"],
	["reka",  14, 15, 0.00, 0.50, 5.0, "main"],
	["dlon",  15, 19, 0.00, 0.40, 0.0, "skin"],
	# --- back-slung secondary weapon --------------------
	# Aligned along the back's shoulder→hip axis so the gun rests on the back.
	# Drawn before front leg so the torso covers the strap and only the barrel
	# / stock sticks past the body silhouette.
	["<secondary_back>", 5, 10, 0.30, 0.50, 0.0, "none"],
	# --- front leg (RIGHT_*) ----------------------------
	["udo",    5,  4, 0.20, 0.65, 5.0, "pants"],
	["noga",   4,  1, 0.15, 0.55, 0.0, "pants"],
	["stopa",  1, 17, 0.35, 0.35, 0.0, "none"],
	# --- torso / hip / head -----------------------------
	["klata", 10, 11, 0.10, 0.30, 0.0, "main"],
	["<vest>", 10, 11, 0.10, 0.30, 0.0, "main"],
	["<chain>", 10, 11, 0.15, 0.32, 0.0, "none"],
	# Dogtag hangs from chest (joint 10) down toward hip (joint 5). Drawn on
	# top of the chain so it reads as attached.
	["<dogtag>", 10, 5, 0.00, 0.50, 0.0, "none"],
	["biodro", 5,  6, 0.25, 0.60, 0.0, "main"],
	# Grenade on the belt line — hip axis anchors it centered between hips.
	["<grenade_belt>", 5, 6, 0.50, 0.50, 0.0, "none"],
	["morda",  9, 12, 0.00, 0.50, 0.0, "skin"],
	["<cigar>", 9, 12, 0.00, 0.50, 0.0, "none"],
	["<head>", 9, 12, 0.00, 0.50, 0.0, "helm"],
	# Dreadlocks tuft — anchors at top of head and extends toward the neck.
	["<dreadlocks>", 12, 9, 0.00, 0.50, 0.0, "skin"],
	# --- front arm (RIGHT_*) — over torso, holds weapon -
	["ramie", 10, 13, 0.00, 0.60, 0.0, "main"],
	["reka",  13, 16, 0.00, 0.60, 5.0, "main"],
	["dlon",  16, 20, 0.00, 0.50, 0.0, "skin"],
]

# Head-cosmetic values map straight to sprite basenames in gostek-gfx/.
# The special values "none" (bald) and "helm" (default) are handled inline.
const HEAD_KEYS := ["helm", "kap", "hair1", "hair2", "hair3", "hair4", "none"]
const CHAIN_KEYS := {"silver": "lancuch", "gold": "zlotylancuch"}

# Body-part basenames that have a ranny/*.png blood counterpart. Anything
# below this HP threshold starts blending the wound sprite over the part.
const WOUND_HEALTH := 60.0
const WOUND_KEYS := {"biodro": true, "klata": true, "morda": true, "noga": true, "ramie": true, "reka": true, "udo": true}

# Weapon sprite paths for the back-slung secondary. Keyed by weapon name so
# the caller can pass "AK-74"/"USSOCOM"/etc. and we resolve to the same PNGs
# soldier_art.gd already uses for the in-hand render. Missing entries silently
# skip the overlay.
const BACK_WEAPON_TEX := {
	"Deagles":      "res://assets/weapons-gfx/deserteagle.png",
	"MP5":          "res://assets/weapons-gfx/mp5.png",
	"AK-74":        "res://assets/weapons-gfx/ak74.png",
	"Steyr AUG":    "res://assets/weapons-gfx/steyraug.png",
	"Spas-12":      "res://assets/weapons-gfx/spas12.png",
	"Ruger 77":     "res://assets/weapons-gfx/ruger77.png",
	"M79":          "res://assets/weapons-gfx/m79.png",
	"Barrett":      "res://assets/weapons-gfx/barretm82.png",
	"Minimi":       "res://assets/weapons-gfx/m249.png",
	"Minigun":      "res://assets/weapons-gfx/minigun.png",
	"USSOCOM":      "res://assets/weapons-gfx/colt1911.png",
	"Knife":        "res://assets/weapons-gfx/knife.png",
	"Chainsaw":     "res://assets/weapons-gfx/chainsaw.png",
	"LAW":          "res://assets/weapons-gfx/law.png",
	"Flamethrower": "res://assets/weapons-gfx/flamer.png",
	"Rambo Bow":    "res://assets/weapons-gfx/bow.png",
}

# Grenade belt sprites — cluster/frag come from weapons-gfx/ since they double
# as the world projectile texture.
const GRENADE_BELT_FRAG := "res://assets/weapons-gfx/frag-grenade.png"
const GRENADE_BELT_CLUSTER := "res://assets/weapons-gfx/cluster-grenade.png"

const SKIN := Color(0.98, 0.82, 0.65)

static var _tex_cache: Dictionary = {}
# instance_id (int) -> { anim: String, phase: float, last_msec: int, frame: PackedVector2Array }
static var _states: Dictionary = {}


static func draw_body(node: CanvasItem, gs: Dictionary, body_color: Color) -> void:
	var frame := _tick(node, gs)
	if frame.is_empty():
		return

	var facing: float = float(gs.get("facing", 1.0))
	var flip := facing < 0.0
	var dead: bool = bool(gs.get("dead", false))
	var pants := body_color.darkened(0.35)
	var tint := body_color if not dead else body_color.darkened(0.4)
	var skin_tint := SKIN if not dead else SKIN.darkened(0.4)
	var pants_tint := pants if not dead else pants.darkened(0.4)

	# Front-arm aim overlay (#59). Cache alongside facing so joint_pos() can
	# reuse it — the weapon anchors at the animated wrist and needs the same
	# offset so the gun tracks with the arm.
	var aim_offset := _compute_aim_offset(gs, facing)
	var st_id := node.get_instance_id()
	var st: Dictionary = _states.get(st_id, {})
	st["aim_offset"] = aim_offset
	var arm_pivot: Vector2 = _joint_local(frame, 10, flip)

	var cos: Dictionary = gs.get("cosmetics", {})
	# Damage overlay strength (#60). Blood sprites blend over the wounded parts
	# once HP dips below WOUND_HEALTH; capped so a nearly-dead soldier still
	# reads as their base color instead of pure red.
	var wound_alpha := 0.0
	if not dead:
		var hp: float = float(gs.get("health", 100.0))
		if hp < WOUND_HEALTH:
			wound_alpha = clampf((WOUND_HEALTH - hp) / (WOUND_HEALTH - 10.0), 0.0, 0.9)
	for spec in PARTS:
		var key: String = spec[0]
		var p1_id: int = spec[1]
		var p2_id: int = spec[2]
		var cx_frac: float = spec[3]
		var cy_frac: float = spec[4]
		var flex: float = spec[5]
		var col_kind: String = spec[6]
		# Track the raw body-part key (pre-cosmetic-resolve) so we can look up
		# the ranny/*.png wound sprite on the same transform.
		var wound_key: String = key if WOUND_KEYS.has(key) else ""

		# Resolve cosmetic placeholders. Missing / disabled → skip the row.
		match key:
			"<head>":
				var h: String = str(cos.get("head", "helm"))
				if h == "none":
					continue
				if not HEAD_KEYS.has(h):
					h = "helm"
				# Hair uses skin-tone shading; helm/kap darken with the main color.
				key = h
				if h.begins_with("hair"):
					col_kind = "skin"
			"<vest>":
				if not bool(cos.get("vest", false)):
					continue
				key = "kamizelka"
			"<chain>":
				var c: String = str(cos.get("chain", "none"))
				if not CHAIN_KEYS.has(c):
					continue
				key = str(CHAIN_KEYS[c])
			"<cigar>":
				if not bool(cos.get("cigar", false)):
					continue
				key = "cygaro"
			"<dogtag>":
				if not bool(cos.get("dogtag", false)):
					continue
				key = "metal"
			"<dreadlocks>":
				if not bool(cos.get("dreadlocks", false)):
					continue
				# Dreads only make sense with a hair head — skip on helm/kap/bald so
				# a tuft doesn't float over a helmet.
				if not str(cos.get("head", "helm")).begins_with("hair"):
					continue
				key = "dred"
			"<grenade_belt>":
				var g_count: int = int(gs.get("grenades", 0))
				if g_count <= 0:
					continue
				key = GRENADE_BELT_CLUSTER if bool(gs.get("use_cluster", false)) else GRENADE_BELT_FRAG
			"<secondary_back>":
				var bw: String = str(gs.get("back_weapon", ""))
				if bw == "" or not BACK_WEAPON_TEX.has(bw):
					continue
				key = str(BACK_WEAPON_TEX[bw])

		var p1 := _joint_local(frame, p1_id, flip)
		var p2 := _joint_local(frame, p2_id, flip)
		# Skip parts anchored on a missing joint — _joint_local returns Vector2.INF
		# when a frame slot is unset (see #86.4).
		if not p1.is_finite() or not p2.is_finite():
			continue
		# Front arm (RIGHT_*) — rotate joints 13/16/20 around the RIGHT shoulder
		# (joint 10) so the arm nudges toward aim_dir. Small clamp; canned .poa
		# still owns the base pose.
		if aim_offset != 0.0 and _is_front_arm(p1_id, p2_id):
			p1 = _arm_adjust(p1, arm_pivot, aim_offset)
			p2 = _arm_adjust(p2, arm_pivot, aim_offset)
		var bone := p2 - p1
		if bone.is_zero_approx():
			continue
		var angle := bone.angle()

		var tex := _tex(key, false)
		var sy := 1.0
		var use_cy_frac := cy_frac
		if flip:
			var mirror := _tex(key, true)
			if mirror != null:
				tex = mirror
				use_cy_frac = 1.0 - cy_frac
			else:
				sy = -1.0
		if tex == null:
			continue

		var w := float(tex.get_width()) * SPRITE_SCALE
		var h := float(tex.get_height()) * SPRITE_SCALE
		var sx := 1.0
		if flex > 0.0:
			var ref_len := flex * POA_TO_PIXEL
			sx = minf(1.5, bone.length() / ref_len)
		var cx := cx_frac * w
		var cy := use_cy_frac * h

		var col: Color = Color.WHITE
		match col_kind:
			"main":  col = tint
			"pants": col = pants_tint
			"skin":  col = skin_tint
			"helm":
				# Helm reads as a distinct piece rather than blending into the body silhouette.
				col = tint.darkened(0.35) if not dead else tint.darkened(0.6)
			_:
				# "none" parts (feet) still darken on death so corpses don't have
				# full-brightness white boots against the darkened body.
				col = Color(0.4, 0.4, 0.4, 1.0) if dead else Color.WHITE

		node.draw_set_transform(p1, angle, Vector2(sx, sy))
		node.draw_texture_rect(tex, Rect2(-cx, -cy, w, h), false, col)

		# Wound blood overlay (#60). Same transform + rect, so the blood sits
		# in register on top of the part. Ranny PNGs mirror the base body-part
		# dimensions so re-using `w`/`h`/`cx`/`cy` keeps alignment.
		if wound_alpha > 0.0 and wound_key != "":
			var wound_tex := _tex("ranny/" + wound_key, false)
			if flip:
				var w_mirror := _tex("ranny/" + wound_key, true)
				if w_mirror != null:
					wound_tex = w_mirror
			if wound_tex != null:
				node.draw_texture_rect(wound_tex, Rect2(-cx, -cy, w, h), false, Color(1.0, 1.0, 1.0, wound_alpha))

	node.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Local-space position of the given .poa joint (1..20) for the CURRENT
# frame — useful for anchoring the weapon sprite to the right wrist (16).
# Applies the aim overlay (#59) for RIGHT-arm joints so the weapon anchors
# at the aim-adjusted wrist, keeping gun and arm visually attached.
static func joint_pos(node: CanvasItem, joint_id_1based: int) -> Vector2:
	var st: Dictionary = _states.get(node.get_instance_id(), {})
	var frame: PackedVector2Array = st.get("frame", PackedVector2Array())
	if frame.is_empty():
		return Vector2.ZERO
	var facing: float = float(st.get("facing", 1.0))
	var flip := facing < 0.0
	var pos := _joint_local(frame, joint_id_1based, flip)
	# Preserve the pre-#86.4 external contract: callers (soldier_art.gd) gate on
	# has_frame() but still assume a finite return, so translate the internal
	# "unset joint" sentinel back to Vector2.ZERO here.
	if not pos.is_finite():
		return Vector2.ZERO
	var aim_offset: float = float(st.get("aim_offset", 0.0))
	if aim_offset != 0.0 and (joint_id_1based == 13 or joint_id_1based == 16 or joint_id_1based == 20):
		var pivot := _joint_local(frame, 10, flip)
		pos = _arm_adjust(pos, pivot, aim_offset)
	return pos


static func forget(node: CanvasItem) -> void:
	_states.erase(node.get_instance_id())


static func _gc_states() -> void:
	# Drop entries whose instance_from_id resolves to null — those soldiers were
	# freed without an explicit forget() call. Cheap when it runs; the guard in
	# _tick keeps it out of the hot path unless the dict grows past ~a match's
	# worth of live entries.
	var stale: Array = []
	for id in _states.keys():
		if instance_from_id(int(id)) == null:
			stale.append(id)
	for id in stale:
		_states.erase(id)


static func has_frame(node: CanvasItem) -> bool:
	var st: Dictionary = _states.get(node.get_instance_id(), {})
	var frame: PackedVector2Array = st.get("frame", PackedVector2Array())
	return not frame.is_empty()


# ── internals ──────────────────────────────────────────

static func _tick(node: CanvasItem, gs: Dictionary) -> PackedVector2Array:
	var id := node.get_instance_id()
	# Sweep stale entries — if a soldier is freed without a Gostek.forget()
	# call, its instance_id never gets resolved back to a live node. Drop those
	# so the static _states dict doesn't leak across scene reloads (#86.3).
	if _states.size() > 32:
		_gc_states()
	var st: Dictionary = _states.get(id, {})
	if st.is_empty():
		st = {
			"anim": "",
			"phase": 0.0,
			"last_msec": Time.get_ticks_msec(),
			"frame": PackedVector2Array(),
			"facing": 1.0,
			"blend_t": -1.0,
			"prev_frame": PackedVector2Array(),
		}
		_states[id] = st

	var target := _pick_anim(gs)
	if target != st["anim"]:
		st["prev_frame"] = st.get("frame", PackedVector2Array())
		st["blend_t"] = 0.0
		st["anim"] = target
		st["phase"] = 0.0

	var now := Time.get_ticks_msec()
	var dt: float = (now - int(st["last_msec"])) / 1000.0
	st["last_msec"] = now
	if dt < 0.0 or dt > 0.25:
		dt = 1.0 / 60.0
	st["phase"] = float(st["phase"]) + dt

	var frames: Array = PoaLoader.get_frames(target)
	if frames.is_empty():
		st["frame"] = PackedVector2Array()
		return PackedVector2Array()

	var meta: Dictionary = PoaLoader.meta_for(target)
	var speed: float = maxf(1.0, float(meta.get("speed", 1)))
	var loops: bool = bool(meta.get("loop", false))
	var frame_rate: float = TICK_RATE / speed
	var idx: int = int(float(st["phase"]) * frame_rate)
	if loops:
		idx = posmod(idx, frames.size())
	else:
		idx = min(idx, frames.size() - 1)

	st["frame"] = frames[idx]
	# Cross-fade from the previous anim's held pose to the animating new one so
	# state changes (run→jump, land→run) read smooth instead of snapping.
	var blend_t: float = float(st.get("blend_t", -1.0))
	if blend_t >= 0.0 and blend_t < BLEND_TIME:
		var prev: PackedVector2Array = st.get("prev_frame", PackedVector2Array())
		if not prev.is_empty():
			var k: float = clampf(blend_t / BLEND_TIME, 0.0, 1.0)
			k = k * k * (3.0 - 2.0 * k)  # smoothstep ease-in-out
			var blended := PackedVector2Array()
			blended.resize(frames[idx].size())
			for i in frames[idx].size():
				var p: Vector2 = prev[i] if i < prev.size() else frames[idx][i]
				blended[i] = p.lerp(frames[idx][i], k)
			st["frame"] = blended
		st["blend_t"] = blend_t + dt
	st["facing"] = float(gs.get("facing", 1.0))
	return st["frame"]


static func _pick_anim(gs: Dictionary) -> String:
	if bool(gs.get("dead", false)):
		return "lezy"
	# Gestures (from /commands) win over everything except death — they should
	# read clearly regardless of what the soldier is otherwise doing.
	var gest: String = str(gs.get("gesture_anim", ""))
	if gest != "":
		return gest
	# Roll (S pressed while running) — dive-forward / dive-backward tumble.
	if bool(gs.get("rolling", false)):
		var vel_r: Vector2 = gs.get("velocity", Vector2.ZERO)
		var facing_r: float = float(gs.get("facing", 1.0))
		return "skokdolobrot" if signf(vel_r.x) == signf(facing_r) else "skokdolobrottyl"
	# Melee swing (Knife/Chainsaw) takes priority over reload/run so the punch pose reads.
	if bool(gs.get("melee_swing", false)):
		return "bije"
	if bool(gs.get("reloading", false)):
		return "laduje"
	var on_floor: bool = bool(gs.get("on_floor", true))
	var vel: Vector2 = gs.get("velocity", Vector2.ZERO)
	if not on_floor:
		if bool(gs.get("jet_on", false)):
			return "takeoff"
		return "spada" if vel.y > 0.0 else "skok"
	var vx := vel.x
	var facing: float = float(gs.get("facing", 1.0))
	# Prone → flat on the floor. Crawl anim if moving, static prone otherwise.
	if bool(gs.get("prone", false)):
		return "lezyidzie" if absf(vx) > 5.0 else "lezy"
	# Crouch → kuca stack (idle / forward-shuffle / backward-shuffle).
	if bool(gs.get("crouching", false)):
		if absf(vx) > 5.0:
			var same_dir_c: bool = signf(vx) == signf(facing)
			return "kucaidzie" if same_dir_c else "kucaidzietyl"
		return "kuca"
	if absf(vx) > RUN_THRESHOLD:
		var same_dir: bool = signf(vx) == signf(facing)
		return "biega" if same_dir else "biegatyl"
	return "stoi"


static func _joint_local(frame: PackedVector2Array, joint_id_1based: int, flip: bool) -> Vector2:
	var idx := joint_id_1based - 1
	if idx < 0 or idx >= frame.size():
		return Vector2.INF
	var v := frame[idx]
	# Blank frame slots surface as Vector2.INF — an unambiguous "unset" sentinel
	# so callers can distinguish missing joints from a joint legitimately at
	# origin (previously Vector2.ZERO conflated the two — see #86.4).
	if v == Vector2.ZERO:
		return Vector2.INF
	var out := Vector2(v.x * POA_TO_PIXEL, v.y * POA_TO_PIXEL + FEET_OFFSET_Y)
	if flip:
		out.x = -out.x
	return out


# Signed radians from facing-forward to aim_dir, clamped small. Returns 0 for
# dead soldiers (canned lezy pose already reads as a corpse) and for missing
# aim data. In flipped/left-facing coords the joint layout is mirrored, so the
# rotation sign flips too.
static func _compute_aim_offset(gs: Dictionary, facing: float) -> float:
	if bool(gs.get("dead", false)):
		return 0.0
	var aim: Vector2 = gs.get("aim_dir", Vector2.ZERO)
	if aim == Vector2.ZERO:
		return 0.0
	var forward := Vector2(facing, 0.0)
	var off := clampf(forward.angle_to(aim), -AIM_ARM_LIMIT, AIM_ARM_LIMIT)
	if facing < 0.0:
		off = -off
	return off


static func _is_front_arm(p1_id: int, p2_id: int) -> bool:
	# RIGHT arm chain (front, holds weapon): 10→13→16→20.
	return (p1_id == 10 and p2_id == 13) \
		or (p1_id == 13 and p2_id == 16) \
		or (p1_id == 16 and p2_id == 20)


static func _arm_adjust(pos: Vector2, pivot: Vector2, aim_offset: float) -> Vector2:
	# Skip rotation when there's no aim offset or when the caller passes the
	# explicit "unset joint" sentinel (Vector2.INF from _joint_local). Comparing
	# against Vector2.ZERO used to conflate "unset" with "joint legitimately at
	# origin" — a real risk once FEET_OFFSET_Y is tweaked or a joint blends
	# through (0,0) during a cross-fade. (#86.4)
	if aim_offset == 0.0 or not pos.is_finite() or not pivot.is_finite():
		return pos
	return pivot + (pos - pivot).rotated(aim_offset)


static func _tex(key: String, mirror: bool) -> Texture2D:
	# Two extra key shapes (#60):
	#   "ranny/<part>"  — wound sprite in the ranny/ subfolder
	#   "res://…/foo.png" — absolute path (back-slung weapon, belt grenade)
	# Absolute paths have no *2.png mirror variant; return null on mirror so
	# draw_body falls back to sy=-1.0 flipping.
	if key.begins_with("res://"):
		if mirror:
			return null
		if _tex_cache.has(key):
			return _tex_cache[key]
		var abs_tex: Texture2D = null
		if ResourceLoader.exists(key):
			abs_tex = load(key) as Texture2D
		_tex_cache[key] = abs_tex
		return abs_tex
	var base: String = key
	var subdir: String = ""
	var slash: int = key.rfind("/")
	if slash >= 0:
		subdir = key.substr(0, slash + 1)
		base = key.substr(slash + 1)
	var nm: String = subdir + base + ("2" if mirror else "")
	if _tex_cache.has(nm):
		return _tex_cache[nm]
	var path: String = DIR + nm + ".png"
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	# NOTE: no fall back to the unmirrored sprite when the "2" variant is missing —
	# draw_body's else branch handles it correctly with sy = -1.0.
	_tex_cache[nm] = tex
	return tex
