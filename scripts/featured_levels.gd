extends Object
## Featured levels (#295): hand-built Maker levels bundled with the game, so
## the LEVELS browser (FEATURED tab) and the Maker's "Start from" list are
## never empty — offline too, no server involved.
##
## Each level is the COMPILED map the Maker saves (maker_build.gd compile(),
## written by tools/make_featured.gd) under assets/levels/featured/<slug>.json,
## maker block kept, so EDIT A COPY decompiles it back into editable pieces.
## LEVELS below is the catalog: card text + the modes each level was built and
## tested for (tools/featured_test.gd checks every one validates, audits clean,
## routes for bots and plays).

const MapIO = preload("res://scripts/map_io.gd")
const Build = preload("res://scripts/maker/maker_build.gd")
const LevelThumb = preload("res://scripts/level_thumb.gd")

const DIR := "res://assets/levels/featured/"
const CACHE_DIR := "user://levels/featured/"
const AUTHOR := "Tracerfall team"
const ID_PREFIX := "featured:"

## slug, title, Maker theme, modes (levels_panel MODE_KEYS, first = the default
## for PLAY), one-line description.
const LEVELS := [
	{"slug": "twin_forts", "title": "Twin Forts", "theme": "grassland", "modes": "ctf htf tdm dm",
		"blurb": "A mirrored CTF arena: two hilltop forts, a sky route of floating islands and a jump pad up from the valley."},
	{"slug": "magma_crown", "title": "Magma Crown", "theme": "desert", "modes": "dom tdm dm",
		"blurb": "King of the hill: hold the crown between two lava pits. Narrow bridges, long falls."},
	{"slug": "skyline_tower", "title": "Skyline Tower", "theme": "urban", "modes": "htf tdm dm",
		"blurb": "Jump pads launch you up a zig-zag tower to the flag on the roof. Hold it as long as you can."},
	{"slug": "iron_valley", "title": "Iron Valley", "theme": "jungle", "modes": "tdm ctf dm",
		"blurb": "Wide open warfare: each base has a buggy, a tank, a heli pad and a plane on its runway."},
	{"slug": "the_bunker", "title": "The Bunker", "theme": "night", "modes": "dm rm tdm gg",
		"blurb": "Three tight decks under a concrete roof, ladders and shotguns. Fast, close-quarters deathmatch."},
	{"slug": "frostbite", "title": "Frostbite", "theme": "snow", "modes": "ctf inf tdm dm",
		"blurb": "Two snowy peaks over a bottomless chasm. One ice bridge and a frozen pillar are the only way across."},
	{"slug": "hollow_deep", "title": "Hollow Deep", "theme": "cave", "modes": "dom ctf tdm dm",
		"blurb": "A dark cavern of stalactites, spike pits and ladders. Three points to hold in the deep."},
	{"slug": "last_ridge", "title": "Last Ridge", "theme": "grassland", "modes": "br dm gg",
		"blurb": "A big Battle Royale ridge: towers, bunkers and loot everywhere. The ring closes on the summit."},
]

## Maker theme -> level_thumb.gd sky (THEME_SKY keys).
const THUMB_THEME := {"grassland": "jungle", "jungle": "jungle", "desert": "desert", "snow": "snow",
	"urban": "urban", "cave": "rock", "night": "rock"}

## Menu -> map editor hand-off for EDIT A COPY (the editor's _ready picks it up).
static var pending_edit := ""

static var _json: Dictionary = {}   # slug -> parsed map JSON (plain values)
static var _entries: Array = []     # card entries (thumbs built once)


static func slugs() -> Array:
	var out: Array = []
	for e in LEVELS:
		out.append(str(e["slug"]))
	return out


static func meta(slug: String) -> Dictionary:
	for e in LEVELS:
		if str(e["slug"]) == slug:
			return e
	return {}


static func is_featured_id(id: String) -> bool:
	return id.begins_with(ID_PREFIX)


static func slug_of(id: String) -> String:
	return id.substr(ID_PREFIX.length()) if is_featured_id(id) else ""


static func path(slug: String) -> String:
	return DIR + slug + ".json"


## The bundled map as plain JSON values (what LevelThumb / mode_hints read).
static func json(slug: String) -> Dictionary:
	if _json.has(slug):
		return _json[slug]
	var d: Variant = null
	if FileAccess.file_exists(path(slug)):
		d = JSON.parse_string(FileAccess.get_file_as_string(path(slug)))
	_json[slug] = d if d is Dictionary else {}
	return _json[slug]


## The playable map (map_io form: Vector2s, PackedVector2Arrays ...).
static func load_map(slug: String) -> Dictionary:
	return MapIO.load_from_file(path(slug)) if FileAccess.file_exists(path(slug)) else {}


## Editable source form for the Maker (pieces back in the maker block).
static func source(slug: String) -> Dictionary:
	var m := load_map(slug)
	if m.is_empty():
		return {}
	var src := Build.decompile(m)
	Build.ensure_maker(src)
	return src


## A card entry in the LEVELS browser's shape (levels_api list rows).
static func entry(slug: String) -> Dictionary:
	var e := meta(slug)
	if e.is_empty():
		return {}
	return {"id": ID_PREFIX + slug, "code": "", "title": str(e["title"]), "author": AUTHOR, "modes": str(e["modes"]),
		"plays": 0, "likes": 0, "theme": str(THUMB_THEME.get(str(e["theme"]), "")), "featured": true,
		"blurb": str(e["blurb"]), "thumb": LevelThumb.from_map(json(slug))}


static func entries() -> Array:
	if _entries.is_empty():
		for s in slugs():
			var e := entry(s)
			if not e.is_empty() and not (e["thumb"] as Dictionary).is_empty():
				_entries.append(e)
	return _entries.duplicate(true)


## A user:// copy to play / host (the file name is what a hosted game's
## server-list entry shows: "Custom: <title>"). "" on failure.
static func local_copy(slug: String) -> String:
	var e := meta(slug)
	var src := path(slug)
	if e.is_empty() or not FileAccess.file_exists(src):
		return ""
	var d := CACHE_DIR + slug + "/"
	DirAccess.make_dir_recursive_absolute(d)
	var dst := d + MapIO.safe_filename(str(e["title"])) + ".json"
	var text := FileAccess.get_file_as_string(src)
	if FileAccess.file_exists(dst) and FileAccess.get_file_as_string(dst) == text:
		return dst
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(text)
	f.close()
	return dst
