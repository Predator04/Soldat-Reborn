extends RefCounted
## HD weapon sprites (#284): assets/weapons-hd/<name>.png, painted by
## tools/gen_weapons_gfx.py. Each is exactly 3x its classic
## assets/weapons-gfx/<name>.png and is always drawn into the CLASSIC rect
## (classic size * Gostek.SPRITE_SCALE) with the classic pivot, so the grip,
## barrel length, muzzle and bullet spawn never move. Used only while
## Gostek.operator_on() (Operator look, Medium+ quality, not headless); the
## textures are mipmapped, so whoever draws them samples with
## TEXTURE_FILTER_LINEAR_WITH_MIPMAPS. `<name>_n.png` = normal map (unused yet).

const CLASSIC_DIR := "res://assets/weapons-gfx/"
const HD_DIR := "res://assets/weapons-hd/"

static var _cache: Dictionary = {}


## The HD twin of a classic weapons-gfx texture path, or null when there is none.
static func hd_for_path(classic_path: String) -> Texture2D:
	if _cache.has(classic_path):
		return _cache[classic_path]
	var t: Texture2D = null
	if classic_path.begins_with(CLASSIC_DIR):
		var p := HD_DIR + classic_path.substr(CLASSIC_DIR.length())
		if ResourceLoader.exists(p):
			t = load(p) as Texture2D
	_cache[classic_path] = t
	return t


## Normal map next to the HD sprite (for the dynamic-lighting pass), or null.
static func normal_for_path(classic_path: String) -> Texture2D:
	if not classic_path.begins_with(CLASSIC_DIR):
		return null
	var p := HD_DIR + classic_path.substr(CLASSIC_DIR.length()).get_basename() + "_n.png"
	return load(p) as Texture2D if ResourceLoader.exists(p) else null
