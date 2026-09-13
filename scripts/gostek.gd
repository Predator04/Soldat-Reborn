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
const POA_TO_PIXEL := 2.4
const FEET_OFFSET_Y := 20.0

# Anims.pas runs its animation counter at physics tick rate (~60 Hz).
const TICK_RATE := 60.0

# Movement speed above which the soldier plays biega/biegatyl instead of stoi.
const RUN_THRESHOLD := 45.0

# Back-to-front draw order. Rows are:
#   [sprite_key, p1, p2, cx_frac, cy_frac, flex_units, color_kind]
# Matches the GostekBase entries in GostekGraphics.inc for a plain
# soldier (no vest / no chains / no cigar) plus the helmet on top.
const PARTS := [
	# --- back leg (LEFT_*) ------------------------------
	["udo",    6,  3, 0.20, 0.50, 5.0, "pants"],
	["noga",   3,  2, 0.15, 0.55, 0.0, "pants"],
	["stopa",  2, 18, 0.35, 0.35, 0.0, "none"],
	# --- back arm (LEFT_*) ------------------------------
	["ramie", 11, 14, 0.00, 0.50, 0.0, "main"],
	["reka",  14, 15, 0.00, 0.50, 5.0, "main"],
	["dlon",  15, 19, 0.00, 0.40, 0.0, "skin"],
	# --- front leg (RIGHT_*) ----------------------------
	["udo",    5,  4, 0.20, 0.65, 5.0, "pants"],
	["noga",   4,  1, 0.15, 0.55, 0.0, "pants"],
	["stopa",  1, 17, 0.35, 0.35, 0.0, "none"],
	# --- torso / hip / head -----------------------------
	["klata", 10, 11, 0.10, 0.30, 0.0, "main"],
	["biodro", 5,  6, 0.25, 0.60, 0.0, "main"],
	["morda",  9, 12, 0.00, 0.50, 0.0, "skin"],
	["helm",   9, 12, 0.00, 0.50, 0.0, "main"],
	# --- front arm (RIGHT_*) — over torso, holds weapon -
	["ramie", 10, 13, 0.00, 0.60, 0.0, "main"],
	["reka",  13, 16, 0.00, 0.60, 5.0, "main"],
	["dlon",  16, 20, 0.00, 0.50, 0.0, "skin"],
]

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

	for spec in PARTS:
		var key: String = spec[0]
		var p1_id: int = spec[1]
		var p2_id: int = spec[2]
		var cx_frac: float = spec[3]
		var cy_frac: float = spec[4]
		var flex: float = spec[5]
		var col_kind: String = spec[6]

		var p1 := _joint_local(frame, p1_id, flip)
		var p2 := _joint_local(frame, p2_id, flip)
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

		var w := float(tex.get_width())
		var h := float(tex.get_height())
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
			_:
				# "none" parts (feet) still darken on death so corpses don't have
				# full-brightness white boots against the darkened body.
				col = Color(0.4, 0.4, 0.4, 1.0) if dead else Color.WHITE

		node.draw_set_transform(p1, angle, Vector2(sx, sy))
		node.draw_texture_rect(tex, Rect2(-cx, -cy, w, h), false, col)

	node.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Local-space position of the given .poa joint (1..20) for the CURRENT
# frame — useful for anchoring the weapon sprite to the right wrist (16).
static func joint_pos(node: CanvasItem, joint_id_1based: int) -> Vector2:
	var st: Dictionary = _states.get(node.get_instance_id(), {})
	var frame: PackedVector2Array = st.get("frame", PackedVector2Array())
	if frame.is_empty():
		return Vector2.ZERO
	var facing: float = float(st.get("facing", 1.0))
	return _joint_local(frame, joint_id_1based, facing < 0.0)


static func forget(node: CanvasItem) -> void:
	_states.erase(node.get_instance_id())


# ── internals ──────────────────────────────────────────

static func _tick(node: CanvasItem, gs: Dictionary) -> PackedVector2Array:
	var id := node.get_instance_id()
	var st: Dictionary = _states.get(id, {})
	if st.is_empty():
		st = {
			"anim": "",
			"phase": 0.0,
			"last_msec": Time.get_ticks_msec(),
			"frame": PackedVector2Array(),
			"facing": 1.0,
		}
		_states[id] = st

	var target := _pick_anim(gs)
	if target != st["anim"]:
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
	st["facing"] = float(gs.get("facing", 1.0))
	return frames[idx]


static func _pick_anim(gs: Dictionary) -> String:
	if bool(gs.get("dead", false)):
		return "lezy"
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
	if absf(vx) > RUN_THRESHOLD:
		var same_dir: bool = signf(vx) == signf(facing)
		return "biega" if same_dir else "biegatyl"
	return "stoi"


static func _joint_local(frame: PackedVector2Array, joint_id_1based: int, flip: bool) -> Vector2:
	var idx := joint_id_1based - 1
	if idx < 0 or idx >= frame.size():
		return Vector2.ZERO
	var v := frame[idx]
	var out := Vector2(v.x * POA_TO_PIXEL, v.y * POA_TO_PIXEL + FEET_OFFSET_Y)
	if flip:
		out.x = -out.x
	return out


static func _tex(key: String, mirror: bool) -> Texture2D:
	var nm: String = key + ("2" if mirror else "")
	if _tex_cache.has(nm):
		return _tex_cache[nm]
	var path: String = DIR + nm + ".png"
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	# Fall back to unmirrored sprite if the "2" variant doesn't exist.
	if tex == null and mirror:
		var base_path: String = DIR + key + ".png"
		if ResourceLoader.exists(base_path):
			tex = load(base_path) as Texture2D
	_tex_cache[nm] = tex
	return tex
