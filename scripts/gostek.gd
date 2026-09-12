extends RefCounted
## Static gostek — assembles the real Soldat body-part PNGs into one
## standing soldier pose. No animation yet; the full .poa-driven rig
## is a follow-up. See references/poa-format.md.

const DIR := "res://assets/gostek-gfx/"

# Part offsets, tuned for a right-facing soldier. Each entry is
# (filename_root, local_position, rotation_deg, layer_hint).
# Layer_hint is only used for draw ordering below.
const PARTS := [
	{"key": "biodro", "pos": Vector2(0, 2), "rot": 0.0, "layer": 0},
	{"key": "udo",    "pos": Vector2(-1, 8), "rot": 88.0, "layer": 1},
	{"key": "noga",   "pos": Vector2(-2, 22), "rot": 92.0, "layer": 2},
	{"key": "stopa",  "pos": Vector2(-2, 34), "rot": 4.0, "layer": 3},
	{"key": "klata",  "pos": Vector2(0, -15), "rot": 0.0, "layer": 4},
	{"key": "kamizelka", "pos": Vector2(0, -14), "rot": 0.0, "layer": 5},
	{"key": "ramie",  "pos": Vector2(4, -18), "rot": 0.0, "layer": 6},
	{"key": "reka",   "pos": Vector2(9, -16), "rot": 0.0, "layer": 7},
	{"key": "dlon",   "pos": Vector2(20, -14), "rot": 0.0, "layer": 8},
	{"key": "morda",  "pos": Vector2(3, -32), "rot": 0.0, "layer": 9},
	{"key": "helm",   "pos": Vector2(3, -38), "rot": 0.0, "layer": 10},
]

static var _tex_cache: Dictionary = {}


static func draw_body(node: CanvasItem, facing: float, body_color: Color, dead: bool) -> void:
	var flip := facing < 0.0
	var tint := body_color if not dead else body_color.darkened(0.4)

	for part in PARTS:
		var tex := _texture(String(part["key"]), flip)
		if tex == null:
			continue
		var pos: Vector2 = part["pos"]
		if flip:
			pos.x = -pos.x
		var rot_deg: float = float(part["rot"])
		if flip:
			rot_deg = -rot_deg
		var modulate := Color.WHITE
		# Only the torso pieces pick up the team color, so faces / limbs
		# stay their painted skin tones.
		if part["key"] in ["klata", "kamizelka", "biodro", "udo", "noga", "ramie", "helm"]:
			modulate = tint
		_blit(node, tex, pos, deg_to_rad(rot_deg), modulate)


static func _blit(node: CanvasItem, tex: Texture2D, center: Vector2, rot: float, tint: Color) -> void:
	var size := tex.get_size()
	node.draw_set_transform(center, rot, Vector2.ONE)
	node.draw_texture_rect(tex, Rect2(-size * 0.5, size), false, tint)
	node.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _texture(key: String, flip: bool) -> Texture2D:
	var name := key + ("2" if flip else "")
	if _tex_cache.has(name):
		return _tex_cache[name]
	var path := DIR + name + ".png"
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	# Fall back to the non-mirrored sprite if a "2" variant is missing.
	if tex == null and flip:
		var base_path := DIR + key + ".png"
		if ResourceLoader.exists(base_path):
			tex = load(base_path) as Texture2D
	_tex_cache[name] = tex
	return tex
