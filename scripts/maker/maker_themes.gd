extends Object
## Maker mode themes (#286). A theme is the look a Maker map compiles to:
## the classic terrain texture (it decides the HD material family through
## terrain_theme.gd TEXTURE_MATERIAL), per-vertex colours by depth below the
## surface (top lip -> body -> deep rock; terrain_theme.weights() turns green
## into grass, brown into dirt, white into snow ...), the sky gradient, the
## weather and the colours of man-made pieces (bridges, props). The textures
## are light / neutral ones so the vertex colours carry the hue in both the
## classic and the HD look.

const ORDER := ["grassland", "desert", "snow", "urban", "jungle", "cave", "night"]

const THEMES := {
	"grassland": {
		"label": "Grassland", "tex": "res://assets/textures/default.png",
		"top": Color(0.34, 0.6, 0.14), "body": Color(0.6, 0.41, 0.23), "deep": Color(0.42, 0.38, 0.34),
		"sky_top": [0.33, 0.55, 0.84], "sky_bottom": [0.80, 0.88, 0.93], "weather": "",
		"wood": Color(0.66, 0.46, 0.27), "accent": Color(0.55, 0.78, 0.3),
	},
	"desert": {
		"label": "Desert", "tex": "res://assets/textures/kokos.png",
		"top": Color(1.0, 0.96, 0.84), "body": Color(0.98, 0.84, 0.64), "deep": Color(0.80, 0.62, 0.47),
		"sky_top": [0.40, 0.62, 0.88], "sky_bottom": [0.98, 0.85, 0.62], "weather": "",
		"wood": Color(0.70, 0.50, 0.30), "accent": Color(0.98, 0.78, 0.45),
	},
	"snow": {
		"label": "Snow", "tex": "res://assets/textures/cytryna.png",
		"top": Color(1.0, 1.0, 1.0), "body": Color(0.80, 0.86, 0.95), "deep": Color(0.50, 0.56, 0.67),
		"sky_top": [0.44, 0.56, 0.72], "sky_bottom": [0.86, 0.90, 0.95], "weather": "snow",
		"wood": Color(0.58, 0.42, 0.30), "accent": Color(0.85, 0.93, 1.0),
	},
	"urban": {
		"label": "Urban", "tex": "res://assets/textures/ctf_steel.png",
		"top": Color(0.88, 0.89, 0.91), "body": Color(0.62, 0.66, 0.72), "deep": Color(0.40, 0.42, 0.47),
		"sky_top": [0.28, 0.34, 0.47], "sky_bottom": [0.88, 0.62, 0.43], "weather": "",
		"wood": Color(0.52, 0.55, 0.60), "accent": Color(0.95, 0.66, 0.3),
	},
	"jungle": {
		"label": "Jungle", "tex": "res://assets/textures/default.png",
		"top": Color(0.26, 0.56, 0.12), "body": Color(0.33, 0.45, 0.17), "deep": Color(0.25, 0.3, 0.2),
		"sky_top": [0.24, 0.45, 0.42], "sky_bottom": [0.74, 0.86, 0.68], "weather": "",
		"wood": Color(0.56, 0.40, 0.22), "accent": Color(0.4, 0.8, 0.3),
	},
	"cave": {
		"label": "Cave", "tex": "res://assets/textures/default.png",
		"top": Color(0.62, 0.58, 0.52), "body": Color(0.47, 0.43, 0.39), "deep": Color(0.30, 0.28, 0.27),
		"sky_top": [0.11, 0.09, 0.09], "sky_bottom": [0.33, 0.27, 0.22], "weather": "",
		"wood": Color(0.52, 0.38, 0.24), "accent": Color(0.95, 0.6, 0.3),
	},
	"night": {
		"label": "Night", "tex": "res://assets/textures/default.png",
		"top": Color(0.32, 0.46, 0.38), "body": Color(0.30, 0.28, 0.37), "deep": Color(0.19, 0.19, 0.26),
		"sky_top": [0.04, 0.06, 0.14], "sky_bottom": [0.17, 0.21, 0.36], "weather": "",
		"wood": Color(0.40, 0.32, 0.26), "accent": Color(0.55, 0.7, 1.0),
	},
}


static func get_theme(id: String) -> Dictionary:
	return THEMES.get(id, THEMES["grassland"])


static func label(id: String) -> String:
	return str(get_theme(id).get("label", id))


static func sky(id: String) -> Dictionary:
	var t := get_theme(id)
	return {"top": (t["sky_top"] as Array).duplicate(), "bottom": (t["sky_bottom"] as Array).duplicate()}


static func sky_color(id: String, top: bool) -> Color:
	var a: Array = get_theme(id)["sky_top" if top else "sky_bottom"]
	return Color(float(a[0]), float(a[1]), float(a[2]))


## Vertex colour at `depth` px below the surface above it (0 = on the top
## lip). `jitter` (-1..1, from a position hash, never the RNG) breaks up flat
## areas a little.
static func depth_color(id: String, depth: float, jitter: float = 0.0) -> Color:
	var t := get_theme(id)
	var top: Color = t["top"]
	var body: Color = t["body"]
	var deep: Color = t["deep"]
	var c: Color
	if depth <= 6.0:
		c = top
	elif depth < 56.0:
		c = top.lerp(body, smoothstep(6.0, 56.0, depth))
	else:
		c = body.lerp(deep, smoothstep(56.0, 420.0, depth))
	var k := 1.0 + 0.05 * jitter
	return Color(clampf(c.r * k, 0.0, 1.0), clampf(c.g * k, 0.0, 1.0), clampf(c.b * k, 0.0, 1.0), 1.0)
