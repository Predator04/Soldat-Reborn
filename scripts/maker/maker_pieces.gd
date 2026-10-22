extends Object
## Maker mode piece catalog (#286): every ready-made piece of the palette —
## what it is, where it lives in the map JSON, its default size, which edits
## make sense for it — plus the vector art used for the palette thumbnails and
## the editor view (one drawing per piece, so both always match).
##
## kinds:
##   shape   terrain piece (maker.pieces): solid / players-only / bullets-only
##           outline; touching pieces of one class merge (maker_build.gd)
##   hazard  spikes / lava (maker.pieces -> map "hazards"; lava adds a basin)
##   pad     jump pad (maker.pieces -> map "jump_pads")
##   prop    solid crate / sandbags / barrel (maker.pieces -> a "prop"
##           collision box + its scenery sprite)
##   entity  a point the game reads from a map key (spawns, flags, pickups ...)
##   ladder  map "ladders" rect
##   scenery map "scenery" sprite (no collision)

const HazardArt = preload("res://scripts/maker/hazard_art.gd")
const Themes = preload("res://scripts/maker/maker_themes.gd")

const TABS := ["terrain", "hazards", "objectives", "items", "vehicles", "scenery"]
const TAB_LABELS := {
	"terrain": "Terrain", "hazards": "Hazards & helpers", "objectives": "Objectives",
	"items": "Items", "vehicles": "Vehicles", "scenery": "Scenery",
}

const BLUE := Color(0.36, 0.6, 1.0)
const RED := Color(1.0, 0.36, 0.3)
const NEUTRAL := Color(0.86, 0.88, 0.92)
const EMBER := Color(1.0, 0.58, 0.16)
const GOLD := Color(1.0, 0.84, 0.3)
const INK := Color(0.07, 0.08, 0.1)

const WEAPONS := ["AK-74", "MP5", "Steyr AUG", "Spas-12", "Ruger 77", "M79", "Barrett", "Minimi",
	"Minigun", "Flamethrower", "LAW", "Deagles", "USSOCOM", "Rambo Bow", "Knife", "Chainsaw"]
const WEAPON_SPRITE := {
	"Deagles": "res://assets/weapons-gfx/deserteagle.png", "MP5": "res://assets/weapons-gfx/mp5.png",
	"AK-74": "res://assets/weapons-gfx/ak74.png", "Steyr AUG": "res://assets/weapons-gfx/steyraug.png",
	"Spas-12": "res://assets/weapons-gfx/spas12.png", "Ruger 77": "res://assets/weapons-gfx/ruger77.png",
	"M79": "res://assets/weapons-gfx/m79.png", "Barrett": "res://assets/weapons-gfx/barretm82.png",
	"Minimi": "res://assets/weapons-gfx/m249.png", "Minigun": "res://assets/weapons-gfx/minigun.png",
	"USSOCOM": "res://assets/weapons-gfx/colt1911.png", "Knife": "res://assets/weapons-gfx/knife.png",
	"Chainsaw": "res://assets/weapons-gfx/chainsaw.png", "LAW": "res://assets/weapons-gfx/law.png",
	"Flamethrower": "res://assets/weapons-gfx/flamer.png", "Rambo Bow": "res://assets/weapons-gfx/bow.png",
}

## Fixed pieces. Weapons + scenery entries are added by catalog().
const BASE := {
	# ── Terrain ──
	"block": {"tab": "terrain", "label": "Ground", "kind": "shape", "shape": "rect", "w": 400.0, "h": 200.0,
		"tip": "A solid block of ground. Solid pieces that touch merge into one smooth piece of terrain."},
	"wide": {"tab": "terrain", "label": "Wide ground", "kind": "shape", "shape": "rect", "w": 1200.0, "h": 300.0,
		"tip": "A long stretch of ground: the base of most maps."},
	"slope_up_30": {"tab": "terrain", "label": "Ramp up 30°", "kind": "shape", "shape": "slope", "w": 400.0, "h": 230.0,
		"tip": "A gentle ramp going up to the right (flip it with F)."},
	"slope_dn_30": {"tab": "terrain", "label": "Ramp down 30°", "kind": "shape", "shape": "slope", "w": 400.0, "h": 230.0, "f": 1,
		"tip": "A gentle ramp going down to the right."},
	"slope_up_45": {"tab": "terrain", "label": "Ramp up 45°", "kind": "shape", "shape": "slope", "w": 300.0, "h": 300.0,
		"tip": "A steep ramp going up to the right — jets or a run-up get you over it."},
	"slope_dn_45": {"tab": "terrain", "label": "Ramp down 45°", "kind": "shape", "shape": "slope", "w": 300.0, "h": 300.0, "f": 1,
		"tip": "A steep ramp going down to the right."},
	"hill": {"tab": "terrain", "label": "Round hill", "kind": "shape", "shape": "hill", "w": 640.0, "h": 200.0,
		"tip": "A smooth rounded hill. Put it on a ground block and they merge."},
	"float": {"tab": "terrain", "label": "Floating", "kind": "shape", "shape": "island", "w": 320.0, "h": 80.0,
		"tip": "A floating island to jump or jet up to."},
	"ledge": {"tab": "terrain", "label": "Thin ledge", "kind": "shape", "shape": "rect", "w": 240.0, "h": 16.0, "col": 2,
		"tip": "A thin ledge soldiers stand on — bullets fly through it."},
	"bridge": {"tab": "terrain", "label": "Bridge", "kind": "shape", "shape": "rect", "w": 480.0, "h": 16.0, "col": 2, "tint": "wood",
		"tip": "A plank bridge over a gap. Bullets pass between the planks."},
	"glass": {"tab": "terrain", "label": "Bullet wall", "kind": "shape", "shape": "rect", "w": 24.0, "h": 160.0, "col": 1, "tint": "glass",
		"tip": "A see-through barrier: soldiers walk through it, bullets stop."},
	"pillar": {"tab": "terrain", "label": "Pillar", "kind": "shape", "shape": "rect", "w": 80.0, "h": 360.0,
		"tip": "A tall column to hide behind or climb onto."},
	"wall": {"tab": "terrain", "label": "Wall", "kind": "shape", "shape": "rect", "w": 40.0, "h": 520.0,
		"tip": "A tall thin wall."},
	# ── Hazards & helpers ──
	"spikes": {"tab": "hazards", "label": "Spikes", "kind": "hazard", "hz": "spikes", "w": 160.0, "h": 28.0, "rot": true, "flip": false,
		"tip": "Instant death to the touch. Rotate (R) for ceiling or wall spikes."},
	"lava": {"tab": "hazards", "label": "Lava pit", "kind": "hazard", "hz": "lava", "w": 360.0, "h": 80.0, "rot": false, "flip": false,
		"tip": "A pool of lava on a rock basin. Drop it into a gap between two blocks."},
	"pad": {"tab": "hazards", "label": "Jump pad", "kind": "pad", "power": 1150.0, "w": 64.0, "h": 20.0, "resize": false, "rot": false, "flip": false,
		"tip": "Launches whoever steps on it high into the air."},
	"pad_big": {"tab": "hazards", "label": "Big jump pad", "kind": "pad", "power": 1600.0, "w": 64.0, "h": 20.0, "resize": false, "rot": false, "flip": false,
		"tip": "A much stronger launch — reach the top of the map."},
	"ladder": {"tab": "hazards", "label": "Ladder", "kind": "ladder", "w": 20.0, "h": 240.0, "rot": false, "flip": false,
		"tip": "A ladder soldiers can climb. Drag the handles to make it taller."},
	"crate": {"tab": "hazards", "label": "Crate", "kind": "prop", "tex": "res://assets/scenery/crate.png", "w": 60.0, "h": 60.0, "rot": false,
		"tip": "A solid wooden crate — cover you can stand on."},
	"crate_big": {"tab": "hazards", "label": "Big crate", "kind": "prop", "tex": "res://assets/scenery/bigcrate.png", "w": 100.0, "h": 100.0, "rot": false,
		"tip": "A big solid crate."},
	"sandbags": {"tab": "hazards", "label": "Sandbags", "kind": "prop", "tex": "res://assets/scenery/sandbags.png", "w": 120.0, "h": 32.0, "rot": false,
		"tip": "Low solid cover: crouch behind it."},
	"barrel": {"tab": "hazards", "label": "Barrel", "kind": "prop", "tex": "res://assets/scenery/barrel.png", "w": 44.0, "h": 44.0, "rot": false,
		"tip": "A solid barrel."},
	# ── Objectives ──
	"player_start": {"tab": "objectives", "label": "Player start", "kind": "entity", "key": "player_spawn", "single": true, "anchor": "feet",
		"tip": "Where you start in free-for-all modes (there is always one — drag it)."},
	"spawn_blue": {"tab": "objectives", "label": "Blue spawn", "kind": "entity", "key": "team_spawns", "team": 1, "anchor": "feet",
		"tip": "A spawn point for the Blue team (team modes)."},
	"spawn_red": {"tab": "objectives", "label": "Red spawn", "kind": "entity", "key": "team_spawns", "team": 2, "anchor": "feet",
		"tip": "A spawn point for the Red team (team modes)."},
	"spawn_any": {"tab": "objectives", "label": "FFA spawn", "kind": "entity", "key": "bot_spawns", "anchor": "feet",
		"tip": "A free-for-all spawn point (deathmatch, bots)."},
	"flag_blue": {"tab": "objectives", "label": "Blue flag", "kind": "entity", "key": "ctf_flags", "slot": 0, "anchor": "feet",
		"tip": "Blue team's flag base (Capture the Flag)."},
	"flag_red": {"tab": "objectives", "label": "Red flag", "kind": "entity", "key": "ctf_flags", "slot": 1, "anchor": "feet",
		"tip": "Red team's flag base (Capture the Flag)."},
	"flag_inf": {"tab": "objectives", "label": "INF flag", "kind": "entity", "key": "inf_flag", "single": true, "anchor": "feet",
		"tip": "Infiltration: the flag Red carries to Blue's base."},
	"flag_htf": {"tab": "objectives", "label": "HTF flag", "kind": "entity", "key": "htf_flag", "single": true, "anchor": "feet",
		"tip": "Hold the Flag: the one flag both teams fight over."},
	"dom": {"tab": "objectives", "label": "DOM point", "kind": "entity", "key": "dom_points", "max": 5, "anchor": "center",
		"tip": "A Domination control point (up to five)."},
	"rambo": {"tab": "objectives", "label": "Rambo bow", "kind": "entity", "key": "rambo_pos", "single": true, "anchor": "feet",
		"tip": "Where the Rambo Bow lies (Rambomatch)."},
	"point": {"tab": "objectives", "label": "Point", "kind": "entity", "key": "point_spawns", "anchor": "center",
		"tip": "A Pointmatch diamond (+1 point)."},
	# Bomb Defusal (#304): resizable areas -> map "bomb_sites".
	"site_a": {"tab": "objectives", "label": "Bomb site A", "kind": "site", "site": "A", "w": 240.0, "h": 150.0, "rot": false, "flip": false,
		"tip": "Bomb Defusal: attackers plant the bomb inside this area. Stretch it over ground soldiers can stand on."},
	"site_b": {"tab": "objectives", "label": "Bomb site B", "kind": "site", "site": "B", "w": 240.0, "h": 150.0, "rot": false, "flip": false,
		"tip": "Bomb Defusal: the second bomb site. Put it somewhere else than A so the defenders have to split."},
	# ── Items ──
	"bonus": {"tab": "items", "label": "Bonus box", "kind": "entity", "key": "bonus_spawns", "anchor": "feet",
		"tip": "A power-up crate spot (Predator / Berserker / Vest / Cluster)."},
	"medkit": {"tab": "items", "label": "Medikit", "kind": "entity", "key": "medkits", "anchor": "feet",
		"tip": "Heals to full."},
	"grenades": {"tab": "items", "label": "Grenade kit", "kind": "entity", "key": "grenade_kits", "anchor": "feet",
		"tip": "Refills grenades."},
	# ── Vehicles ──
	"buggy": {"tab": "vehicles", "label": "Buggy", "kind": "entity", "key": "vehicle_spawns", "anchor": "feet",
		"tip": "A buggy. Give it a long, open stretch of ground."},
	"tank": {"tab": "vehicles", "label": "Tank", "kind": "entity", "key": "tank_spawns", "anchor": "feet",
		"tip": "A tank. Wide maps only: it needs a long flat run."},
	"heli": {"tab": "vehicles", "label": "Heli pad", "kind": "entity", "key": "heli_spawns", "anchor": "feet",
		"tip": "A helicopter pad: flat ground with open sky above."},
	"plane": {"tab": "vehicles", "label": "Plane", "kind": "entity", "key": "plane_spawns", "anchor": "feet",
		"tip": "A plane. On the ground it needs a long, flat runway; up in open air it starts already flying."},
	"m2": {"tab": "vehicles", "label": "M2 gun", "kind": "entity", "key": "m2_mounts", "anchor": "feet",
		"tip": "A mounted M2 machine gun (press F next to it)."},
}

## Decoration sprites for the Scenery tab: [label, texture, scale].
const SCENERY := [
	["Tree", "res://assets/scenery/tree2.png", 0.75], ["Oak", "res://assets/scenery/tree5.png", 0.8],
	["Palm", "res://assets/scenery/veg_palm_7.png", 0.8], ["Jungle tree", "res://assets/scenery/jungletree.png", 0.85],
	["Dead tree", "res://assets/scenery/mnp-deadtree1.png", 0.45], ["Bush", "res://assets/scenery/bush3.png", 0.8],
	["Shrub", "res://assets/scenery/bush.png", 0.55], ["Grass", "res://assets/scenery/grass3.png", 0.45],
	["Cactus", "res://assets/scenery/_dcactus3.png", 0.45], ["Rocks", "res://assets/scenery/rocks2.png", 0.8],
	["Stone", "res://assets/scenery/xt_jh_stone01.png", 0.6], ["Fence", "res://assets/scenery/woodfence.png", 0.6],
	["Barbed wire", "res://assets/scenery/barbwire.png", 0.6], ["Lamp", "res://assets/scenery/l_lamp_tl-sk.png", 0.8],
	["Gravestone", "res://assets/scenery/gravestone2.png", 0.35], ["Skulls", "res://assets/scenery/mnp-skulls1.png", 0.3],
]

static var _cat: Dictionary = {}
static var _tabs: Dictionary = {}
static var _tex: Dictionary = {}


static func catalog() -> Dictionary:
	if not _cat.is_empty():
		return _cat
	for k in BASE:
		_cat[k] = BASE[k]
	for w in WEAPONS:
		_cat["w_" + _slug(w)] = {"tab": "items", "label": w, "kind": "entity", "key": "weapon_pickups", "weapon": w,
			"anchor": "center", "tip": "A %s lying on the ground to pick up." % w}
	for i in SCENERY.size():
		var s: Array = SCENERY[i]
		_cat["sc_%d" % i] = {"tab": "scenery", "label": s[0], "kind": "scenery", "tex": s[1], "scale": s[2],
			"rot": false, "tip": "Decoration (no collision)."}
	return _cat


static func _slug(s: String) -> String:
	return s.to_lower().replace(" ", "_").replace("-", "_")


static func def(id: String) -> Dictionary:
	return catalog().get(id, {})


static func ids_for_tab(tab: String) -> Array:
	if _tabs.has(tab):
		return _tabs[tab]
	var out: Array = []
	var order: Array = BASE.keys()
	for k in catalog().keys():
		if not order.has(k):
			order.append(k)
	for k in order:
		if str(catalog()[k].get("tab", "")) == tab:
			out.append(k)
	_tabs[tab] = out
	return out


## Pieces stored in maker.pieces (vs. entities written straight to map keys).
static func is_piece(id: String) -> bool:
	return str(def(id).get("kind", "")) in ["shape", "hazard", "pad", "prop", "site"]


static func can_resize(id: String) -> bool:
	var d := def(id)
	return bool(d.get("resize", d.get("kind", "") in ["shape", "hazard", "prop", "ladder", "scenery", "site"]))


static func can_rotate(id: String) -> bool:
	var d := def(id)
	return bool(d.get("rot", d.get("kind", "") == "shape"))


static func can_flip(id: String) -> bool:
	var d := def(id)
	return bool(d.get("flip", d.get("kind", "") == "shape"))


## Entity id for a map key / index (editor hit tests -> palette art).
static func entity_id_for(key: String, team: int = 0, slot: int = 0, weapon: String = "") -> String:
	match key:
		"player_spawn": return "player_start"
		"team_spawns": return "spawn_blue" if team == 1 else "spawn_red"
		"bot_spawns": return "spawn_any"
		"ctf_flags": return "flag_blue" if slot == 0 else "flag_red"
		"inf_flag": return "flag_inf"
		"htf_flag": return "flag_htf"
		"dom_points": return "dom"
		"rambo_pos": return "rambo"
		"point_spawns": return "point"
		"bonus_spawns": return "bonus"
		"medkits": return "medkit"
		"grenade_kits": return "grenades"
		"vehicle_spawns": return "buggy"
		"tank_spawns": return "tank"
		"heli_spawns": return "heli"
		"plane_spawns": return "plane"
		"m2_mounts": return "m2"
		"weapon_pickups": return "w_" + _slug(weapon)
	return ""


static func tex(path: String) -> Texture2D:
	if path == "":
		return null
	if not _tex.has(path):
		_tex[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _tex[path]


# ── Local shapes (centred on 0, before rotation / flip) ──────────────────────

static func local_shape(shape: String, w: float, h: float) -> PackedVector2Array:
	var hw := w * 0.5
	var hh := h * 0.5
	match shape:
		"slope":
			return PackedVector2Array([Vector2(-hw, hh), Vector2(hw, hh), Vector2(hw, -hh)])
		"hill":
			var pts := PackedVector2Array([Vector2(hw, hh), Vector2(-hw, hh)])
			var n := 18
			for i in n + 1:
				var t := float(i) / float(n)
				pts.append(Vector2(-hw + w * t, hh - h * (0.5 - 0.5 * cos(TAU * t))))
			return pts
		"island":
			var cut := minf(h * 0.55, w * 0.2)
			return PackedVector2Array([Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, -hh + h * 0.45),
				Vector2(hw - cut, hh), Vector2(-hw + cut, hh), Vector2(-hw, -hh + h * 0.45)])
	return PackedVector2Array([Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)])


static func transform_shape(pts: PackedVector2Array, center: Vector2, rot: int, flip: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	var ang := float(posmod(rot, 4)) * PI * 0.5
	for p in pts:
		var q := Vector2(-p.x if flip else p.x, p.y)
		out.append(center + q.rotated(ang))
	if flip:
		out.reverse()   # keep the winding
	return out


# ── Art ──────────────────────────────────────────────────────────────────────

## Palette thumbnail: the piece drawn to fit `r`.
static func draw_thumb(ci: CanvasItem, id: String, r: Rect2, theme: String) -> void:
	var d := def(id)
	var kind := str(d.get("kind", ""))
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y)
	match kind:
		"shape":
			var w := float(d.get("w", 100.0))
			var h := float(d.get("h", 100.0))
			var k := minf(r.size.x * 0.92 / w, r.size.y * 0.8 / h)
			k = minf(k, 1.0e9)
			var sw := maxf(w * k, 6.0)
			var sh := maxf(h * k, 5.0)
			var pts := transform_shape(local_shape(str(d.get("shape", "rect")), sw, sh), c, 0, int(d.get("f", 0)) == 1)
			draw_shape_preview(ci, pts, theme, int(d.get("col", 0)), str(d.get("tint", "")))
		"hazard":
			if str(d.get("hz", "")) == "lava":
				var lr := Rect2(c.x - s * 0.38, c.y - s * 0.14, s * 0.76, s * 0.26)
				draw_shape_preview(ci, PackedVector2Array([Vector2(lr.position.x - 7, lr.position.y), Vector2(lr.position.x, lr.position.y),
					Vector2(lr.position.x, lr.end.y), Vector2(lr.end.x, lr.end.y), Vector2(lr.end.x, lr.position.y), Vector2(lr.end.x + 7, lr.position.y),
					Vector2(lr.end.x + 7, lr.end.y + 12), Vector2(lr.position.x - 7, lr.end.y + 12)]), theme, 0, "")
				HazardArt.draw_lava(ci, lr, 0.6, false)
			else:
				HazardArt.draw_spikes(ci, Rect2(c.x - s * 0.42, c.y - s * 0.16, s * 0.84, s * 0.3), 0)
		"pad":
			HazardArt.draw_pad(ci, c + Vector2(0, s * 0.3), float(d.get("power", 1150.0)) > 1400.0, 9.0, s / 80.0)
		"ladder":
			draw_ladder(ci, Rect2(c.x - s * 0.14, c.y - s * 0.42, s * 0.28, s * 0.84))
		"site":
			draw_site(ci, Rect2(c.x - s * 0.44, c.y - s * 0.3, s * 0.88, s * 0.6), str(d.get("site", "A")))
		"prop", "scenery":
			draw_sprite_fit(ci, str(d.get("tex", "")), r.grow(-r.size.x * 0.06))
		"entity":
			draw_entity(ci, id, c + Vector2(0, s * 0.42), s * 0.84)


## A terrain outline in the theme's colours (top lip, body gradient, dark rim).
static func draw_shape_preview(ci: CanvasItem, pts: PackedVector2Array, theme: String, col: int, tint: String, alpha: float = 1.0) -> void:
	if pts.size() < 3:
		return
	var top := INF
	var bot := -INF
	for p in pts:
		top = minf(top, p.y)
		bot = maxf(bot, p.y)
	var cols := PackedColorArray()
	for p in pts:
		var c := tint_color(theme, tint, (p.y - top) * 2.2)
		c.a *= alpha
		cols.append(c)
	if Geometry2D.triangulate_polygon(pts).is_empty():
		return
	ci.draw_polygon(pts, cols)
	var th := Themes.get_theme(theme)
	var lip: Color = (th["top"] as Color).lightened(0.25) if tint == "" else tint_color(theme, tint, 0.0).lightened(0.2)
	lip.a = alpha
	var n := pts.size()
	for i in n:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		var e := b - a
		if e.length() < 0.5:
			continue
		# Outward normal (shapes wind clockwise on screen): up-facing edges get the lip.
		var nrm := Vector2(e.y, -e.x).normalized()
		if nrm.y < -0.45:
			ci.draw_line(a, b, lip, 2.0, true)
		else:
			ci.draw_line(a, b, Color(0, 0, 0, 0.45 * alpha), 1.0, true)
	if col == 2:
		ci.draw_line(pts[0], pts[1], Color(1, 1, 1, 0.5 * alpha), 1.0, true)


static func tint_color(theme: String, tint: String, depth: float) -> Color:
	var th := Themes.get_theme(theme)
	match tint:
		"wood":
			var w: Color = th["wood"]
			return w.darkened(clampf(depth / 80.0, 0.0, 0.35))
		"glass":
			return Color(0.62, 0.86, 1.0, 0.5)
	return Themes.depth_color(theme, depth)


## A bomb site (#304): faint zone, ground strip, corner brackets, its letter.
static func draw_site(ci: CanvasItem, r: Rect2, letter: String, alpha: float = 1.0) -> void:
	var col := Color(1.0, 0.62, 0.2, alpha)
	ci.draw_rect(r, Color(col.r, col.g, col.b, 0.14 * alpha))
	var lw := maxf(1.0, minf(r.size.x, r.size.y) * 0.03)
	ci.draw_line(Vector2(r.position.x, r.end.y), r.end, col, lw * 1.6)
	var L := minf(r.size.x, r.size.y) * 0.22
	for c in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
		var sx := 1.0 if c.x <= r.get_center().x else -1.0
		var sy := 1.0 if c.y <= r.get_center().y else -1.0
		ci.draw_line(c, c + Vector2(L * sx, 0), col, lw)
		ci.draw_line(c, c + Vector2(0, L * sy), col, lw)
	_text(ci, r.get_center(), letter, int(clampf(minf(r.size.x, r.size.y) * 0.5, 8.0, 64.0)), Color(1, 0.8, 0.5, alpha))


static func draw_ladder(ci: CanvasItem, r: Rect2, col: Color = Color(0.82, 0.62, 0.32)) -> void:
	ci.draw_rect(r, Color(0.35, 0.24, 0.12, 0.25))
	var inset := clampf(r.size.x * 0.15, 1.5, 6.0)
	var lx := r.position.x + inset
	var rx := r.end.x - inset
	var lw := maxf(2.5, r.size.x * 0.14)
	ci.draw_line(Vector2(lx, r.position.y), Vector2(lx, r.end.y), col, lw)
	ci.draw_line(Vector2(rx, r.position.y), Vector2(rx, r.end.y), col, lw)
	var step := clampf(r.size.x, 8.0, 20.0)
	var y := r.position.y + step * 0.5
	while y < r.end.y:
		ci.draw_line(Vector2(lx, y), Vector2(rx, y), col, maxf(1.0, lw * 0.8))
		y += step


static func draw_sprite_fit(ci: CanvasItem, path: String, r: Rect2, mod: Color = Color.WHITE) -> void:
	var t := tex(path)
	if t == null:
		ci.draw_rect(r, Color(1, 1, 1, 0.2))
		return
	var ts := t.get_size()
	var k := minf(r.size.x / ts.x, r.size.y / ts.y)
	var sz := ts * k
	ci.draw_texture_rect(t, Rect2(r.get_center() - sz * 0.5, sz), false, mod)


static func _text(ci: CanvasItem, at: Vector2, s: String, size: int, col: Color) -> void:
	var f := UITheme.font("head")
	if f == null:
		return
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	ci.draw_string(f, at + Vector2(-w * 0.5, size * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## An entity marker standing on `foot` (bottom centre) in a box of size `s`.
## `label` overrides the corner tag (DOM letters).
static func draw_entity(ci: CanvasItem, id: String, foot: Vector2, s: float, alpha: float = 1.0, label: String = "") -> void:
	var d := def(id)
	var c := foot - Vector2(0, s * 0.5)
	var h := s * 0.5
	var lw := maxf(1.2, s * 0.05)
	match id:
		"player_start", "spawn_blue", "spawn_red", "spawn_any":
			var col := EMBER if id == "player_start" else (BLUE if id == "spawn_blue" else (RED if id == "spawn_red" else NEUTRAL))
			col.a = alpha
			# Spawn ring on the ground + a soldier silhouette.
			ci.draw_set_transform(foot, 0.0, Vector2(1.0, 0.32))
			ci.draw_arc(Vector2.ZERO, h * 0.8, 0.0, TAU, 28, col, lw * 2.0, true)
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			var body := Color(col.r * 0.55, col.g * 0.55, col.b * 0.55, alpha)
			ci.draw_circle(c + Vector2(0, -h * 0.55), h * 0.2, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.26, -h * 0.3), c + Vector2(h * 0.26, -h * 0.3),
				c + Vector2(h * 0.2, h * 0.25), c + Vector2(-h * 0.2, h * 0.25)]), col)
			ci.draw_line(c + Vector2(-h * 0.1, h * 0.25), c + Vector2(-h * 0.18, h * 0.95), col, lw * 2.2, true)
			ci.draw_line(c + Vector2(h * 0.1, h * 0.25), c + Vector2(h * 0.18, h * 0.95), col, lw * 2.2, true)
			ci.draw_line(c + Vector2(-h * 0.1, -h * 0.12), c + Vector2(h * 0.5, -h * 0.05), body.lightened(0.2), lw * 2.0, true)
			if id == "player_start":
				_star(ci, c + Vector2(h * 0.55, -h * 0.65), h * 0.22, Color(GOLD, alpha))
		"flag_blue", "flag_red", "flag_inf", "flag_htf":
			var fc := BLUE if id == "flag_blue" else (RED if id == "flag_red" else (GOLD if id == "flag_inf" else EMBER))
			fc.a = alpha
			ci.draw_rect(Rect2(foot + Vector2(-h * 0.45, -lw * 2.0), Vector2(h * 0.9, lw * 2.0)), Color(0.2, 0.22, 0.26, alpha))
			ci.draw_line(foot + Vector2(-h * 0.25, 0), foot + Vector2(-h * 0.25, -s * 0.95), Color(0.85, 0.86, 0.9, alpha), lw * 1.6, true)
			var top := foot + Vector2(-h * 0.25, -s * 0.95)
			ci.draw_colored_polygon(PackedVector2Array([top, top + Vector2(h * 0.85, h * 0.12), top + Vector2(h * 0.7, h * 0.42),
				top + Vector2(h * 0.95, h * 0.62), top + Vector2(0, h * 0.62)]), fc)
			if id == "flag_inf" or id == "flag_htf":
				_text(ci, top + Vector2(h * 0.36, h * 0.32), "I" if id == "flag_inf" else "H", int(maxf(8.0, s * 0.24)), Color(INK, alpha))
		"dom":
			ci.draw_arc(c, h * 0.82, 0.0, TAU, 32, Color(GOLD, alpha), lw * 2.0, true)
			ci.draw_circle(c, h * 0.6, Color(GOLD.r, GOLD.g, GOLD.b, 0.25 * alpha))
			_text(ci, c, label if label != "" else "DOM", int(maxf(8.0, s * (0.42 if label != "" else 0.26))), Color(1, 1, 1, alpha))
		"rambo":
			var bc := Color(0.62, 0.95, 0.55, alpha)
			ci.draw_arc(c + Vector2(h * 0.25, 0), h * 0.85, PI * 0.62, PI * 1.38, 16, bc, lw * 2.2, true)
			var ta := c + Vector2(h * 0.25, 0) + Vector2.from_angle(PI * 0.62) * h * 0.85
			var tb := c + Vector2(h * 0.25, 0) + Vector2.from_angle(PI * 1.38) * h * 0.85
			ci.draw_line(ta, tb, Color(1, 1, 1, 0.8 * alpha), lw, true)
			ci.draw_line(c + Vector2(-h * 0.7, 0), c + Vector2(h * 0.75, 0), Color(0.9, 0.85, 0.7, alpha), lw * 1.3, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(h * 0.9, 0), c + Vector2(h * 0.65, -h * 0.13), c + Vector2(h * 0.65, h * 0.13)]), Color(0.9, 0.9, 0.95, alpha))
		"point":
			var pc := Color(GOLD, alpha)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h * 0.8), c + Vector2(h * 0.6, 0), c + Vector2(0, h * 0.8), c + Vector2(-h * 0.6, 0)]), pc)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h * 0.8), c + Vector2(h * 0.6, 0), c]), Color(1, 1, 1, 0.35 * alpha))
		"bonus":
			_box(ci, c + Vector2(0, h * 0.3), h * 0.7, Color(0.55, 0.38, 0.95, alpha))
			_text(ci, c + Vector2(0, h * 0.3), "?", int(maxf(8.0, s * 0.42)), Color(1, 1, 1, alpha))
		"medkit":
			_box(ci, c + Vector2(0, h * 0.3), h * 0.7, Color(0.95, 0.96, 0.97, alpha))
			var t := h * 0.2
			ci.draw_rect(Rect2(c.x - t * 0.5, c.y + h * 0.3 - h * 0.45, t, h * 0.9), Color(0.9, 0.2, 0.2, alpha))
			ci.draw_rect(Rect2(c.x - h * 0.45, c.y + h * 0.3 - t * 0.5, h * 0.9, t), Color(0.9, 0.2, 0.2, alpha))
		"grenades":
			_box(ci, c + Vector2(0, h * 0.3), h * 0.7, Color(0.42, 0.5, 0.3, alpha))
			UITheme.draw_icon(ci, "grenade", c + Vector2(0, h * 0.3), h * 0.8, Color(0.85, 0.95, 0.7, alpha))
		"buggy":
			_vehicle(ci, foot, s, false, alpha)
		"tank":
			_vehicle(ci, foot, s, true, alpha)
		"heli":
			ci.draw_set_transform(foot + Vector2(0, -lw), 0.0, Vector2(1.0, 0.34))
			ci.draw_circle(Vector2.ZERO, h * 0.95, Color(0.25, 0.28, 0.3, alpha))
			ci.draw_arc(Vector2.ZERO, h * 0.95, 0.0, TAU, 32, Color(1, 0.86, 0.3, alpha), lw * 2.6, true)
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			_text(ci, foot + Vector2(0, -h * 0.75), "H", int(maxf(8.0, s * 0.5)), Color(1, 0.86, 0.3, alpha))
		"plane":
			_plane(ci, foot, s, alpha)
		"m2":
			var mc := Color(0.6, 0.66, 0.7, alpha)
			ci.draw_line(foot + Vector2(-h * 0.5, 0), c + Vector2(0, h * 0.15), mc, lw * 1.6, true)
			ci.draw_line(foot + Vector2(h * 0.5, 0), c + Vector2(0, h * 0.15), mc, lw * 1.6, true)
			ci.draw_line(foot, c + Vector2(0, h * 0.15), mc, lw * 1.6, true)
			ci.draw_rect(Rect2(c + Vector2(-h * 0.35, -h * 0.05), Vector2(h * 0.6, h * 0.3)), Color(0.3, 0.33, 0.36, alpha))
			ci.draw_line(c + Vector2(h * 0.2, h * 0.05), c + Vector2(h * 1.0, -h * 0.12), mc, lw * 2.0, true)
		_:
			if str(d.get("key", "")) == "weapon_pickups":
				var wt := tex(str(WEAPON_SPRITE.get(str(d.get("weapon", "")), "")))
				if wt != null:
					draw_sprite_fit(ci, str(WEAPON_SPRITE.get(str(d.get("weapon", "")), "")), Rect2(c - Vector2(h, h * 0.55), Vector2(s, s * 0.55)), Color(1, 1, 1, alpha))
				else:
					_text(ci, c, str(d.get("label", "?")).substr(0, 3), int(maxf(8.0, s * 0.3)), Color(1, 1, 1, alpha))


static func _box(ci: CanvasItem, c: Vector2, hs: float, col: Color) -> void:
	ci.draw_rect(Rect2(c - Vector2(hs, hs), Vector2(hs, hs) * 2.0), col)
	ci.draw_rect(Rect2(c - Vector2(hs, hs), Vector2(hs, hs) * 2.0), Color(0, 0, 0, 0.45 * col.a), false, maxf(1.0, hs * 0.08))
	ci.draw_rect(Rect2(c - Vector2(hs, hs), Vector2(hs * 2.0, hs * 0.3)), Color(1, 1, 1, 0.2 * col.a))


static func _star(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + TAU * float(i) / 10.0
		pts.append(c + Vector2.from_angle(a) * (r if i % 2 == 0 else r * 0.45))
	ci.draw_colored_polygon(pts, col)


static func _vehicle(ci: CanvasItem, foot: Vector2, s: float, tank: bool, alpha: float) -> void:
	var h := s * 0.5
	var body := Color(0.5, 0.56, 0.36, alpha) if tank else Color(0.86, 0.66, 0.3, alpha)
	var dark := Color(0.12, 0.13, 0.15, alpha)
	if tank:
		ci.draw_rect(Rect2(foot + Vector2(-h * 0.95, -h * 0.34), Vector2(h * 1.9, h * 0.34)), dark)
		for i in 5:
			ci.draw_circle(foot + Vector2(-h * 0.76 + float(i) * h * 0.38, -h * 0.17), h * 0.12, Color(0.32, 0.33, 0.35, alpha))
		ci.draw_colored_polygon(PackedVector2Array([foot + Vector2(-h * 0.95, -h * 0.34), foot + Vector2(h * 0.95, -h * 0.34),
			foot + Vector2(h * 0.75, -h * 0.62), foot + Vector2(-h * 0.85, -h * 0.62)]), body)
		ci.draw_rect(Rect2(foot + Vector2(-h * 0.35, -h * 0.9), Vector2(h * 0.7, h * 0.3)), body.darkened(0.15))
		ci.draw_line(foot + Vector2(h * 0.3, -h * 0.76), foot + Vector2(h * 1.05, -h * 0.84), body.darkened(0.3), maxf(1.5, s * 0.07), true)
	else:
		ci.draw_colored_polygon(PackedVector2Array([foot + Vector2(-h * 0.95, -h * 0.3), foot + Vector2(h * 0.95, -h * 0.3),
			foot + Vector2(h * 0.8, -h * 0.62), foot + Vector2(h * 0.2, -h * 0.66), foot + Vector2(-h * 0.05, -h * 0.9),
			foot + Vector2(-h * 0.45, -h * 0.9), foot + Vector2(-h * 0.7, -h * 0.62), foot + Vector2(-h * 0.95, -h * 0.55)]), body)
		ci.draw_line(foot + Vector2(-h * 0.05, -h * 0.9), foot + Vector2(-h * 0.45, -h * 0.9), Color(0.6, 0.85, 1.0, 0.8 * alpha), maxf(1.0, s * 0.04), true)
		for wx in [-h * 0.58, h * 0.58]:
			ci.draw_circle(foot + Vector2(wx, -h * 0.26), h * 0.26, dark)
			ci.draw_circle(foot + Vector2(wx, -h * 0.26), h * 0.11, Color(0.6, 0.62, 0.66, alpha))


## Plane thumbnail (#291): side-on jet resting on its gear, nose right.
static func _plane(ci: CanvasItem, foot: Vector2, s: float, alpha: float) -> void:
	var h := s * 0.5
	var body := Color(0.62, 0.68, 0.74, alpha)
	var dark := Color(0.12, 0.13, 0.15, alpha)
	var c := foot + Vector2(0, -h * 0.42)
	ci.draw_line(c + Vector2(h * 0.5, h * 0.05), foot + Vector2(h * 0.52, -h * 0.08), dark, maxf(1.0, s * 0.03), true)
	ci.draw_line(c + Vector2(-h * 0.2, h * 0.05), foot + Vector2(-h * 0.22, -h * 0.1), dark, maxf(1.0, s * 0.03), true)
	ci.draw_circle(foot + Vector2(h * 0.52, -h * 0.08), h * 0.08, dark)
	ci.draw_circle(foot + Vector2(-h * 0.22, -h * 0.1), h * 0.1, dark)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(h * 1.0, h * 0.04), c + Vector2(h * 0.7, -h * 0.12), c + Vector2(h * 0.1, -h * 0.17),
		c + Vector2(-h * 0.7, -h * 0.12), c + Vector2(-h * 1.0, -h * 0.05), c + Vector2(-h * 1.0, h * 0.06), c + Vector2(-h * 0.6, h * 0.14),
		c + Vector2(h * 0.6, h * 0.12)]), body)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.55, -h * 0.12), c + Vector2(-h * 0.85, -h * 0.55), c + Vector2(-h * 1.0, -h * 0.55),
		c + Vector2(-h * 0.98, -h * 0.08)]), body.darkened(0.15))
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(h * 0.25, h * 0.03), c + Vector2(-h * 0.55, h * 0.1), c + Vector2(-h * 0.25, h * 0.0)]), body.darkened(0.3))
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(h * 0.55, -h * 0.13), c + Vector2(h * 0.35, -h * 0.3), c + Vector2(h * 0.08, -h * 0.3),
		c + Vector2(-h * 0.05, -h * 0.16)]), Color(0.55, 0.82, 1.0, 0.9 * alpha))
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 1.0, -h * 0.06), c + Vector2(-h * 1.28, -h * 0.03), c + Vector2(-h * 1.0, h * 0.04)]),
		Color(1.0, 0.62, 0.25, 0.85 * alpha))
