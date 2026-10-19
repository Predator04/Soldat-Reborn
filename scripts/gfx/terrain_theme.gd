extends RefCounted
## HD terrain mapping (#283): which high-resolution material (assets/terrain-hd,
## painted by tools/gen_terrain_gfx.py) stands in for a map's classic texture,
## which material an individual polygon gets from its colour, which painted
## edge goes on an outline, and which background theme the parallax uses.
## Pure functions + a texture-mean cache; cosmetic only.

const DIR := "res://assets/terrain-hd/"
const MAT_EXT := ".webp"      # <material>.webp + <material>_n.webp (2048 px)
const MATERIALS := ["rock", "dirt", "soil", "grass", "sand", "snow", "metal", "concrete", "wood", "brick", "masonry", "ice"]

## Classic Soldat texture (file stem, lower case) -> material. Every texture a
## bundled map uses is listed; anything else (custom maps) goes through
## guess_material() on the texture's mean colour.
const TEXTURE_MATERIAL := {
	"ananas": "rock", "ancientwall": "rock", "awokado": "dirt", "banana": "concrete",
	"ctf_cobra2": "grass", "ctf_steel": "metal", "cytryna": "snow", "dankoe": "dirt",
	"default": "rock", "dorothy": "brick", "drymud": "dirt", "drysand": "dirt",
	"earthen": "sand", "grejfrut": "dirt", "grunge9": "concrete", "gruszka": "rock",
	"jablko": "grass", "kamibeach": "sand", "kiwi": "rock", "kokos": "sand",
	"malaga": "dirt", "malina": "rock", "mandarynka": "concrete", "melon": "concrete",
	"metroid": "metal", "mossgreen": "grass", "mtex_desert": "sand", "mtk_death": "sand",
	"pomarancz": "concrete", "porzeczka": "rock", "porzeczkasc6": "rock", "potato": "dirt",
	"potato2": "dirt", "poziomka": "concrete", "riverbed": "dirt", "rodzynka": "grass",
	"rustedmetal": "metal", "sk_aztec": "masonry", "snakedesert": "sand", "snowice": "ice",
	"stone03": "rock", "truskawka": "rock", "ut_ground3": "dirt", "vtt_wct (34)": "metal",
	"wisnia": "dirt", "wisnia2": "rock", "xt_ap_grasrock_02": "rock",
	"xt_autumgrassrock": "grass", "xt_forrestdirtrock": "soil", "zak_grassstone6": "grass",
}

## How much of the material's own hue survives the map tint (0 = pure map
## colour with the material's detail, 1 = the material's own colours at the
## map's brightness), and the world size of one texture tile in pixels.
const KEEP := {"rock": 0.12, "dirt": 0.25, "soil": 0.3, "grass": 0.25, "sand": 0.3, "snow": 0.55,
	"metal": 0.3, "concrete": 0.15, "wood": 0.45, "brick": 0.45, "masonry": 0.2, "ice": 0.5}
const TILE := {"rock": 960.0, "dirt": 680.0, "soil": 680.0, "grass": 680.0, "sand": 900.0, "snow": 900.0,
	"metal": 720.0, "concrete": 880.0, "wood": 640.0, "brick": 560.0, "masonry": 820.0, "ice": 820.0}

static var _tex_mean: Dictionary = {}


## A material's albedo / normal texture. `half` (Medium quality): a 1024 px
## copy made at load (VRAM 5.6 MB instead of 22 MB per texture; High keeps
## the full 2048 px). Halved copies are kept for the current map only.
static var _half: Dictionary = {}


static func material_texture(mat: String, normal: bool, half: bool) -> Texture2D:
	var path := DIR + mat + ("_n" if normal else "") + MAT_EXT
	var tex := load(path) as Texture2D
	if not half or tex == null:
		return tex
	if _half.has(path):
		return _half[path]
	var img: Image = tex.get_image()
	if img == null:
		return tex
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.resize(maxi(1, img.get_width() / 2), maxi(1, img.get_height() / 2), Image.INTERPOLATE_BILINEAR)
	img.generate_mipmaps()
	var it := ImageTexture.create_from_image(img)
	_half[path] = it
	return it


## Drop halved copies the current map does not use.
static func keep_half_only(used: Array) -> void:
	for k in _half.keys():
		if not used.has(k):
			_half.erase(k)


static func stem(path: String) -> String:
	return path.get_file().get_basename().to_lower()


## Typical colour of a classic texture (cached; WHITE when it doesn't load —
## the classic path then draws the polygon colour untextured as well). Mostly
## a low per-channel percentile of a point sample: a high-contrast texture (black
## with sparse white streaks, e.g. mtk_death) LOOKS dark although its mean is
## mid grey, and the HD fill should read like the classic surface does.
static func tex_mean(path: String) -> Color:
	if path == "":
		return Color.WHITE
	if _tex_mean.has(path):
		return _tex_mean[path]
	var c := Color.WHITE
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		var img: Image = tex.get_image() if tex != null else null
		if img != null:
			img = img.duplicate()
			if img.is_compressed():
				img.decompress()
			img.resize(48, 48, Image.INTERPOLATE_NEAREST)
			var rs := PackedFloat32Array()
			var gs := PackedFloat32Array()
			var bs := PackedFloat32Array()
			for y in 48:
				for x in 48:
					var p := img.get_pixel(x, y)
					rs.append(p.r)
					gs.append(p.g)
					bs.append(p.b)
			var mean := Vector3.ZERO
			for k in rs.size():
				mean += Vector3(rs[k], gs[k], bs[k])
			mean /= float(rs.size())
			rs.sort()
			gs.sort()
			bs.sort()
			var q := rs.size() * 2 / 5   # 40th percentile
			var med := Vector3(rs[q], gs[q], bs[q])
			var v := mean.lerp(med, 0.7)
			c = Color(v.x, v.y, v.z)
	_tex_mean[path] = c
	return c


## A small, area-averaged copy of a classic texture (~16 px per texel) for
## per-vertex colour lookups: several classic textures are atlases (a grass
## strip over rock, a white and a black region) and polygons pick their part
## through their UVs. Brightness is scaled like tex_mean() (high-contrast
## textures read darker than their mean).
static var _tex_small: Dictionary = {}


static func tex_small(path: String) -> Image:
	if path == "" or not ResourceLoader.exists(path):
		return null
	if _tex_small.has(path):
		return _tex_small[path]
	var tex := load(path) as Texture2D
	var img: Image = tex.get_image() if tex != null else null
	if img != null:
		img = img.duplicate()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		var w := maxi(4, img.get_width() / 16)
		var h := maxi(4, img.get_height() / 16)
		# Halve repeatedly (box filter) so every texel is a true area average.
		while img.get_width() > w * 2 or img.get_height() > h * 2:
			img.resize(maxi(w, img.get_width() / 2), maxi(h, img.get_height() / 2), Image.INTERPOLATE_BILINEAR)
		img.resize(w, h, Image.INTERPOLATE_BILINEAR)
		# Match the perceived level of tex_mean().
		var acc := Vector3.ZERO
		for y in h:
			for x in w:
				var p := img.get_pixel(x, y)
				acc += Vector3(p.r, p.g, p.b)
		acc /= float(w * h)
		var want := tex_mean(path)
		var k := Vector3(want.r / maxf(acc.x, 0.01), want.g / maxf(acc.y, 0.01), want.b / maxf(acc.z, 0.01))
		for y in h:
			for x in w:
				var p := img.get_pixel(x, y)
				img.set_pixel(x, y, Color(clampf(p.r * k.x, 0, 1), clampf(p.g * k.y, 0, 1), clampf(p.b * k.z, 0, 1), p.a))
	_tex_small[path] = img
	return img


## Bilinear, wrapping lookup in tex_small() at a tile-space UV.
static func tex_at(img: Image, uv: Vector2) -> Color:
	var w := img.get_width()
	var h := img.get_height()
	var x := fposmod(uv.x, 1.0) * w - 0.5
	var y := fposmod(uv.y, 1.0) * h - 0.5
	var x0 := int(floor(x))
	var y0 := int(floor(y))
	var fx := x - x0
	var fy := y - y0
	var c00 := img.get_pixel(posmod(x0, w), posmod(y0, h))
	var c10 := img.get_pixel(posmod(x0 + 1, w), posmod(y0, h))
	var c01 := img.get_pixel(posmod(x0, w), posmod(y0 + 1, h))
	var c11 := img.get_pixel(posmod(x0 + 1, w), posmod(y0 + 1, h))
	return c00.lerp(c10, fx).lerp(c01.lerp(c11, fx), fy)


static func guess_material(c: Color) -> String:
	var h := c.h * 360.0
	if c.v > 0.78 and c.s < 0.12:
		return "snow"
	if c.s > 0.22 and h > 60.0 and h < 170.0:
		return "grass"
	if c.s > 0.25 and h >= 25.0 and h <= 55.0 and c.v > 0.5:
		return "sand"
	if c.s > 0.25 and h < 40.0:
		return "dirt"
	if c.s < 0.1:
		return "concrete" if c.v > 0.5 else "rock"
	return "rock"


static func primary_for(map: Dictionary) -> String:
	var tex := str(map.get("terrain_texture", ""))
	var st := stem(tex)
	if TEXTURE_MATERIAL.has(st):
		return TEXTURE_MATERIAL[st]
	if tex != "" and ResourceLoader.exists(tex):
		return guess_material(tex_mean(tex))
	return guess_material(map.get("terrain_color", Color(0.3, 0.32, 0.3)))


static func snowy(map: Dictionary) -> bool:
	return str(map.get("weather", "")).strip_edges().to_lower() == "snow"


static func is_green(c: Color) -> bool:
	var h := c.h * 360.0
	return c.s > 0.2 and h > 62.0 and h < 170.0 and c.v > 0.1


static func is_warm_brown(c: Color) -> bool:
	var h := c.h * 360.0
	return c.s > 0.38 and h >= 12.0 and h <= 45.0 and c.v > 0.12 and c.v < 0.7


static func _win(h: float, a: float, b: float, soft: float) -> float:
	return smoothstep(a - soft, a + soft, h) * (1.0 - smoothstep(b - soft, b + soft, h))


## Material weights for one classic colour: the map's primary material, plus
## the siblings the colour clearly asks for — a green slope on a rock map
## grows grass, a grey boulder on a dirt map is rock, a brown beam in a
## concrete bunker is wood, a white drift on a snow map is snow. Continuous,
## so per-vertex weights blend smoothly along the classic colour gradients.
static func weights(primary: String, c: Color, snow_map: bool) -> Dictionary:
	var h := c.h * 360.0
	var s := c.s
	var v := c.v
	var man_made := primary in ["metal", "concrete", "brick", "wood", "masonry"]
	var w: Dictionary = {}
	var green := _win(h, 62.0, 168.0, 8.0) * smoothstep(0.14, 0.3, s) * smoothstep(0.05, 0.12, v)
	if primary == "metal":
		green = 0.0
	elif man_made:
		green *= smoothstep(0.28, 0.42, s)
	if primary == "grass":
		var rest := 1.0 - green
		var tint := smoothstep(0.08, 0.2, s)
		w["grass"] = green
		w["soil"] = rest * tint
		w["rock"] = rest * (1.0 - tint)
		return w
	if green > 0.0:
		w["grass"] = green
	var left := 1.0 - green
	if snow_map and primary != "metal":
		var sn := smoothstep(0.6, 0.76, v) * (1.0 - smoothstep(0.12, 0.2, s)) * left
		if sn > 0.0:
			w["snow"] = sn
			left -= sn
	var brown := smoothstep(0.32, 0.45, s) * _win(h, 12.0, 46.0, 5.0) * smoothstep(0.1, 0.16, v) * (1.0 - smoothstep(0.62, 0.75, v))
	match primary:
		"concrete", "masonry", "brick":
			var wd := brown * left
			var mt := smoothstep(0.1, 0.2, s) * _win(h, 188.0, 255.0, 8.0) * left
			if wd > 0.0:
				w["wood"] = wd
			if mt > 0.0:
				w["metal"] = mt
			left -= wd + mt
		"rock":
			var dt := brown * smoothstep(0.42, 0.55, s) * left
			if dt > 0.0:
				w["dirt"] = dt
				left -= dt
		"dirt", "soil", "sand":
			var rk := (1.0 - smoothstep(0.06, 0.14, s)) * (1.0 - smoothstep(0.45, 0.6, v)) * left
			if rk > 0.0:
				w["rock"] = rk
				left -= rk
	w[primary] = float(w.get(primary, 0.0)) + maxf(left, 0.0)
	return w


## The dominant material of a colour (edges, tests).
static func classify(primary: String, c: Color, snow_map: bool) -> String:
	var w := weights(primary, c, snow_map)
	var best := primary
	var bw := -1.0
	for k in w:
		if float(w[k]) > bw:
			bw = float(w[k])
			best = k
	return best


## Painted lip on a top-facing outline.
static func top_edge(mat: String, c: Color, snow_map: bool) -> String:
	if snow_map or mat == "snow" or mat == "ice":
		return "snow"
	match mat:
		"grass":
			return "grass"
		"soil", "dirt":
			return "grass" if is_green(c) else "dirt"
		"sand":
			return "sand"
		"metal":
			return "metal"
		"concrete", "brick", "wood", "masonry":
			return "grass" if is_green(c) and c.s > 0.38 else "rock"
	return "grass" if is_green(c) else "rock"


## Hanging detail under a downward-facing outline ("" = none).
static func under_edge(mat: String, c: Color, snow_map: bool) -> String:
	if snow_map or mat == "snow" or mat == "ice":
		return "icicles"
	if mat == "grass" or ((mat == "soil" or mat == "dirt") and is_green(c)):
		return "roots"
	return ""


## Background theme for the parallax (parallax_cinematic.gd `theme`).
static func theme_for(map: Dictionary) -> String:
	var prim := primary_for(map)
	if snowy(map) or prim == "snow" or prim == "ice":
		return "snow"
	if prim == "sand":
		return "desert"
	if prim in ["metal", "concrete", "brick", "wood"]:
		return "urban"
	if prim == "masonry":
		return "ruins"
	var avg := average_color(map)
	if prim == "grass" or prim == "soil" or is_green(avg):
		return "jungle"
	return "rock"


## Rough average colour of the map's polygons (classic texture x vertex
## colours), sampled from up to 300 polygons.
static func average_color(map: Dictionary) -> Color:
	var base := tex_mean(str(map.get("terrain_texture", "")))
	var acc := Vector3.ZERO
	var n := 0
	var polys: Array = map.get("polys", [])
	var step := maxi(1, polys.size() / 300)
	for i in range(0, polys.size(), step):
		var vc: PackedColorArray = polys[i].get("vc", PackedColorArray())
		for c in vc:
			if c.a < 0.3:
				continue
			acc += Vector3(c.r * base.r, c.g * base.g, c.b * base.b)
			n += 1
	if n == 0:
		var tc: Color = map.get("terrain_color", Color(0.3, 0.32, 0.3))
		return Color(base.r * tc.r, base.g * tc.g, base.b * tc.b)
	acc /= float(n)
	return Color(acc.x, acc.y, acc.z)
