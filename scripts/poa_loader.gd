extends RefCounted
## Loader for Soldat's .poa keyframe animation files.
## Verified against shared/Anims.pas + client/GostekGraphics.inc — see
## references/poa-format.md.
##
## A frame is a PackedVector2Array of length 20 indexed by (joint_id - 1).
## Joint coordinates match Anims.pas semantics:
##   X = -SCALE * raw_x / 1.1     (SCALE = 3)
##   Y = -SCALE * raw_z
## The file's middle float (raw_y) is discarded — the rig is planar.

const ANIM_DIR := "res://assets/anims/"
const SCALE := 3.0
const JOINT_COUNT := 20

# name (no extension) → Array[PackedVector2Array]
static var _cache: Dictionary = {}

# Speed / loop table (from Anims.pas.LoadAnimObjects). Any file not listed
# defaults to speed=1, loop=false. Speed is "physics ticks per animation
# frame" in Soldat; we treat it as a divisor on our anim clock.
const ANIM_META := {
	"stoi":            {"speed": 3, "loop": true},
	"biega":           {"speed": 1, "loop": true},
	"biegatyl":        {"speed": 1, "loop": true},
	"skok":            {"speed": 1, "loop": false},
	"skokwbok":        {"speed": 1, "loop": false},
	"spada":           {"speed": 1, "loop": false},
	"kuca":            {"speed": 1, "loop": false},
	"kucaidzie":       {"speed": 2, "loop": true},
	"kucaidzietyl":    {"speed": 2, "loop": true},
	"laduje":          {"speed": 2, "loop": false},
	"rzuca":           {"speed": 1, "loop": false},
	"odrzut":          {"speed": 1, "loop": false},
	"odrzut2":         {"speed": 1, "loop": false},
	"shotgun":         {"speed": 1, "loop": false},
	"clipout":         {"speed": 3, "loop": false},
	"clipin":          {"speed": 3, "loop": false},
	"slideback":       {"speed": 2, "loop": true},
	"change":          {"speed": 1, "loop": false},
	"wyrzuca":         {"speed": 1, "loop": false},
	"bezbroni":        {"speed": 3, "loop": false},
	"bije":            {"speed": 1, "loop": false},
	"strzala":         {"speed": 1, "loop": false},
	"barret":          {"speed": 9, "loop": false},
	"skokdolobrot":    {"speed": 1, "loop": false},
	"skokdolobrottyl": {"speed": 1, "loop": false},
	"lezy":            {"speed": 1, "loop": false},
	"lezyidzie":       {"speed": 2, "loop": true},
	"wstaje":          {"speed": 1, "loop": false},
	"celuje":          {"speed": 2, "loop": false},
	"celujeodrzut":    {"speed": 1, "loop": false},
	"gora":            {"speed": 2, "loop": false},
	"goraodrzut":      {"speed": 1, "loop": false},
	"takeoff":         {"speed": 2, "loop": false},
	"cieszy":          {"speed": 2, "loop": false},
	"cigar":           {"speed": 3, "loop": false},
	"smoke":           {"speed": 3, "loop": false},
}

# Anims the gameplay layer needs preloaded on boot.
const REQUIRED := [
	"stoi", "biega", "biegatyl", "skok", "spada",
	"celuje", "odrzut", "odrzut2",
	"clipin", "clipout", "laduje", "rzuca",
	"lezy", "wstaje", "kuca", "kucaidzie", "kucaidzietyl",
	"zmienbron", "change", "takeoff",
]


static func preload_all() -> void:
	for anim_name in REQUIRED:
		if _cache.has(anim_name):
			continue
		var path: String = ANIM_DIR + String(anim_name) + ".poa"
		if not FileAccess.file_exists(path):
			continue
		_cache[anim_name] = parse_file(path)
	if OS.get_environment("POA_SMOKE") == "1":
		smoke_test()


static func get_frames(anim_name: String) -> Array:
	if not _cache.has(anim_name):
		var path: String = ANIM_DIR + anim_name + ".poa"
		if FileAccess.file_exists(path):
			_cache[anim_name] = parse_file(path)
		else:
			_cache[anim_name] = []
	return _cache[anim_name]


static func meta_for(anim_name: String) -> Dictionary:
	return ANIM_META.get(anim_name, {"speed": 1, "loop": false})


static func parse_file(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("PoaLoader: cannot open %s" % path)
		return []
	var text := f.get_as_text()
	f.close()
	return parse_text(text)


static func parse_text(text: String) -> Array:
	var lines := text.split("\n", false)
	var frames: Array = []
	var cur := _blank_frame()
	var has_data := false

	var i := 0
	while i < lines.size():
		var line := String(lines[i]).strip_edges()
		i += 1
		if line.is_empty():
			continue
		if line == "ENDFILE":
			if has_data:
				frames.append(cur)
			break
		if line == "NEXTFRAME":
			if has_data:
				frames.append(cur)
			# Soldat reuses the previous frame's positions for any joint the
			# next frame doesn't overwrite; carry the values forward.
			cur = cur.duplicate()
			has_data = false
			continue

		# Expect: id, raw_x, raw_y (discarded), raw_z
		if not line.is_valid_int():
			# Real .poa files have no comments/garbage — if we see something else,
			# int(line)==0 would silently skip 3 lines and misalign the whole rest of the file.
			push_warning("PoaLoader: expected int part_id, got '%s' — aborting parse" % line)
			break
		var part_id := int(line)
		if i + 2 >= lines.size():
			break
		var raw_x := String(lines[i]).strip_edges().to_float(); i += 1
		# discard raw_y (planar rig)
		i += 1
		var raw_z := String(lines[i]).strip_edges().to_float(); i += 1
		if part_id >= 1 and part_id <= JOINT_COUNT:
			cur[part_id - 1] = Vector2(-SCALE * raw_x / 1.1, -SCALE * raw_z)
			has_data = true

	# File ended without ENDFILE marker — don't lose the last in-progress frame.
	if has_data:
		frames.append(cur)
	return frames


static func _blank_frame() -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(JOINT_COUNT)
	return out


# Sanity self-check — prints frame counts. Gated behind POA_SMOKE=1 so it
# stays quiet in production; run via `POA_SMOKE=1 godot --headless ...`.
static func smoke_test() -> void:
	print("[PoaLoader] smoke_test: cached anims = %d" % _cache.size())
	for anim_name in REQUIRED:
		var frames: Array = _cache.get(anim_name, [])
		var joints_first := 0
		var joints_last := 0
		if frames.size() > 0:
			joints_first = _nonzero_joints(frames[0])
			joints_last = _nonzero_joints(frames[frames.size() - 1])
		print("  %-16s frames=%3d  first_nz=%2d  last_nz=%2d" % [
			anim_name, frames.size(), joints_first, joints_last,
		])


static func _nonzero_joints(frame: PackedVector2Array) -> int:
	var n := 0
	for v in frame:
		if v != Vector2.ZERO:
			n += 1
	return n
