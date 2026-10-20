extends Object
## Piece lists of the bundled FEATURED levels (#295) — SOURCE maps in the
## Maker's own format (maker_build.gd: entities in the normal map keys,
## terrain / hazards / pads / props as maker pieces). tools/make_featured.gd
## compiles them into assets/levels/featured/<slug>.json. Edit here, then
## re-run make_featured (and the checks: tools/featured_test.gd, map_audit).
## Entity y values only need to be ABOVE the surface they stand on: the
## generator drops them onto the terrain.

const B = preload("res://scripts/maker/maker_build.gd")


## A small builder: pieces + entity lists, mirrored copies for symmetric maps.
class Lv:
	var m := {}
	var pcs: Array = []
	var W := 4800.0
	var H := 2000.0

	func _init(size_idx: int, bottom: String) -> void:
		var s: Array = B.SIZES[size_idx]
		W = float(s[1])
		H = float(s[2])
		m = {"name": "", "platforms": [], "ladders": [], "bot_spawns": [], "player_spawn": Vector2(W * 0.5, 100),
			"team_spawns": {1: [], 2: []}}
		m["maker"] = {"v": B.VERSION, "theme": "grassland", "grid": 20, "w": W, "h": H, "bottom": bottom, "pieces": pcs}

	func p(id: String, cx: float, cy: float, w: float, h: float, r: int = 0, f: int = 0) -> void:
		pcs.append(B.make_piece(id, Vector2(cx, cy), Vector2(w, h), r, f))

	## Solid ground from x0 to x1 with its top at `top`.
	func ground(x0: float, x1: float, top: float, depth: float = 400.0, id: String = "block") -> void:
		p(id, (x0 + x1) * 0.5, top + depth * 0.5, x1 - x0, depth)

	## A ramp from (x0, y0) to (x1, y1) (either way round) with solid under it.
	func ramp(x0: float, y0: float, x1: float, y1: float) -> void:
		var w := absf(x1 - x0)
		var h := absf(y1 - y0)
		var lo := maxf(y0, y1)
		var rising_right := (x1 > x0) == (y1 < y0)
		p("slope_up_30", (x0 + x1) * 0.5, lo - h * 0.5, w, h, 0, 0 if rising_right else 1)

	func ledge(x0: float, x1: float, top: float, id: String = "ledge") -> void:
		p(id, (x0 + x1) * 0.5, top + 8.0, x1 - x0, 16.0)

	func island(cx: float, top: float, w: float = 320.0, h: float = 80.0) -> void:
		p("float", cx, top + h * 0.5, w, h)

	## Spikes lying on a surface (point up).
	func spikes(x0: float, x1: float, surface: float) -> void:
		p("spikes", (x0 + x1) * 0.5, surface - 14.0, x1 - x0, 28.0)

	## A lava pool whose surface is at `top` (the rock basin hangs under it).
	func lava(x0: float, x1: float, top: float, h: float = 80.0) -> void:
		p("lava", (x0 + x1) * 0.5, top + h * 0.5, x1 - x0, h)

	func pad(x: float, surface: float, big: bool = false) -> void:
		p("pad_big" if big else "pad", x, surface - 10.0, 64.0, 20.0)

	func prop(id: String, x: float, surface: float) -> void:
		var d := {"crate": Vector2(60, 60), "crate_big": Vector2(100, 100), "sandbags": Vector2(120, 32), "barrel": Vector2(44, 44)}
		var s: Vector2 = d[id]
		p(id, x, surface - s.y * 0.5, s.x, s.y)

	func ladder(x: float, top: float, bottom: float) -> void:
		(m["ladders"] as Array).append({"x": x - 10.0, "y": top, "w": 20.0, "h": bottom - top})

	func spawn(team: int, x: float, y: float) -> void:
		(m["team_spawns"][team] as Array).append(Vector2(x, y))

	func ffa(x: float, y: float) -> void:
		(m["bot_spawns"] as Array).append(Vector2(x, y))

	func add(key: String, x: float, y: float) -> void:
		var arr: Array = m.get(key, [])
		arr.append(Vector2(x, y))
		m[key] = arr

	func weapon(name: String, x: float, y: float) -> void:
		var arr: Array = m.get("weapon_pickups", [])
		arr.append({"pos": Vector2(x, y), "weapon": name})
		m["weapon_pickups"] = arr

	## Decoration standing on `surface` (scale from the sprite's height).
	func deco(tex: String, x: float, surface: float, scale: float, sink: float = 4.0) -> void:
		var path := "res://assets/scenery/%s.png" % tex
		var t := load(path) as Texture2D
		var hh := (t.get_size().y if t != null else 100.0) * scale
		var arr: Array = m.get("scenery", [])
		arr.append({"tex": path, "pos": Vector2(x, surface - hh * 0.5 + sink), "scale": scale})
		m["scenery"] = arr

	## Mirror every piece added since `from` about the map's centre line.
	func mirror_pieces(from: int) -> void:
		var n := pcs.size()
		for i in range(from, n):
			var q: Dictionary = pcs[i]
			var t := str(q["t"])
			var fl := int(q["f"])
			var r := int(q["r"])
			if t.begins_with("slope") or t == "float":
				fl = 1 - fl
			if r % 2 == 1:
				r = (r + 2) % 4   # wall spikes point the other way
			pcs.append(B.make_piece(t, Vector2(W - float(q["x"]), float(q["y"])), Vector2(float(q["w"]), float(q["h"])), r, fl))

	func mirror_ladders() -> void:
		var arr: Array = m["ladders"]
		for i in arr.size():
			var l: Dictionary = arr[i]
			arr.append({"x": W - float(l["x"]) - float(l["w"]), "y": l["y"], "w": l["w"], "h": l["h"]})

	func mirror_scenery() -> void:
		var arr: Array = m.get("scenery", [])
		for i in arr.size():
			var s: Dictionary = arr[i]
			arr.append({"tex": s["tex"], "pos": Vector2(W - (s["pos"] as Vector2).x, (s["pos"] as Vector2).y), "scale": s["scale"]})

	func done() -> Dictionary:
		m["maker"]["pieces"] = pcs
		return m


# ── 1. Twin Forts — mirrored CTF arena (grassland, M, bottomless) ─────────────
static func src_twin_forts() -> Dictionary:
	var L := Lv.new(1, "void")
	var start := L.pcs.size()
	L.ground(0, 1000, 1400, 480)                  # base plateau
	L.p("block", 240, 1280, 240, 240)             # the keep
	L.ledge(360, 660, 1160)                       # rampart off the keep (flag below)
	L.prop("sandbags", 900, 1400)
	L.prop("crate", 760, 1400)
	L.ramp(1000, 1400, 1400, 1630)                # down to the valley
	L.island(1000, 1160)                          # sky route: keep -> A -> B -> C
	L.island(1620, 1000, 400)
	L.pad(1900, 1620, true)                       # valley -> B
	L.mirror_pieces(start)
	L.ground(1000, 3800, 1620, 260)               # valley floor
	L.p("hill", 2400, 1540, 900, 160)             # centre hill (HTF flag)
	L.island(2400, 880, 480)
	# Blue side (mirrored for red below).
	L.m["ctf_flags"] = [Vector2(500, 1380), Vector2(4300, 1380)]
	for x in [420.0, 620.0, 800.0]:
		L.spawn(1, x, 1380)
		L.spawn(2, L.W - x, 1380)
	L.spawn(1, 240, 1140)
	L.spawn(2, L.W - 240, 1140)
	L.m["htf_flag"] = Vector2(2400, 1400)
	L.m["player_spawn"] = Vector2(700, 1380)
	for v in [Vector2(240, 1140), Vector2(4560, 1140), Vector2(1000, 1140), Vector2(3800, 1140), Vector2(1550, 1600),
			Vector2(3250, 1600), Vector2(2050, 1600), Vector2(2750, 1600), Vector2(2400, 860)]:
		L.ffa(v.x, v.y)
	L.weapon("Barrett", 2400, 860)
	L.weapon("LAW", 1620, 980)
	L.weapon("LAW", 3180, 980)
	L.weapon("Spas-12", 2400, 1400)
	L.add("medkits", 660, 1380)
	L.add("medkits", 4140, 1380)
	L.add("grenade_kits", 330, 1380)
	L.add("grenade_kits", 4470, 1380)
	L.add("medkits", 2300, 860)
	L.deco("tree2", 80, 1160, 0.7)
	L.deco("bush3", 960, 1400, 0.8)
	L.deco("tree5", 1560, 1620, 0.75)
	L.deco("grass3", 2100, 1620, 0.45)
	L.mirror_scenery()
	return L.done()


# ── 2. Magma Crown — king-of-the-hill DOM between lava pits (desert, M, bottomless) ─
static func src_magma_crown() -> Dictionary:
	var L := Lv.new(1, "void")
	var start := L.pcs.size()
	L.ground(0, 800, 1400, 480)                   # spawn plateau
	L.ramp(800, 1400, 1040, 1480)
	L.ground(800, 1640, 1480, 400)                # point A ground
	L.lava(1640, 2000, 1540)                      # lava pit
	L.ground(1600, 2040, 1680, 200)               # rock under its basin (merges with it, #296)
	L.ledge(1640, 1804, 1480, "bridge")           # broken plank bridge over it: hop the gap
	L.ledge(1836, 2000, 1480, "bridge")
	L.island(1820, 1150, 260)                     # hot rock over the lava
	L.prop("sandbags", 1250, 1480)
	L.prop("barrel", 1500, 1480)
	L.prop("crate", 560, 1400)
	L.mirror_pieces(start)
	L.ground(2000, 2800, 1480, 400)               # the crown's base
	L.p("hill", 2400, 1370, 560, 220)             # the crown (point B on top)
	L.m["dom_points"] = [Vector2(1300, 1460), Vector2(2400, 1240), Vector2(3500, 1460)]
	for x in [200.0, 380.0, 640.0]:
		L.spawn(1, x, 1380)
		L.spawn(2, L.W - x, 1380)
	L.m["player_spawn"] = Vector2(380, 1380)
	for v in [Vector2(250, 1380), Vector2(4550, 1380), Vector2(1100, 1460), Vector2(3700, 1460), Vector2(2150, 1460),
			Vector2(2650, 1460), Vector2(1820, 1130), Vector2(2980, 1130), Vector2(2400, 1240)]:
		L.ffa(v.x, v.y)
	L.weapon("Minigun", 2400, 1240)
	L.weapon("M79", 1820, 1130)
	L.weapon("M79", 2980, 1130)
	L.weapon("Ruger 77", 700, 1380)
	L.weapon("Ruger 77", 4100, 1380)
	L.add("medkits", 1050, 1460)
	L.add("medkits", 3750, 1460)
	L.add("grenade_kits", 2150, 1460)
	L.add("grenade_kits", 2650, 1460)
	L.add("bonus_spawns", 2400, 1240)
	L.deco("_dcactus3", 120, 1400, 0.45)
	L.deco("_dcactus3", 1450, 1480, 0.35)
	L.deco("rocks2", 900, 1440, 0.8)
	L.deco("mnp-skulls1", 2130, 1480, 0.25)
	L.mirror_scenery()
	return L.done()


# ── 3. Skyline Tower — zig-zag jump-pad tower, flag on the roof (urban, M, floor) ──
static func src_skyline_tower() -> Dictionary:
	var L := Lv.new(1, "floor")
	var start := L.pcs.size()
	# street level = 1900 (the solid floor)
	L.ground(700, 1100, 1660, 240)                # low building, ramp up its side
	L.ramp(1100, 1660, 1520, 1900)
	L.prop("crate_big", 1650, 1900)
	L.prop("sandbags", 380, 1900)
	L.pad(1860, 1900, true)                       # street -> level 1
	L.pad(2040, 1300, true)                       # level 1 -> level 2
	L.pad(2210, 700)                              # level 2 -> roof
	L.p("glass", 1990, 1240, 24, 120)             # bullet-proof panes on level 1
	L.mirror_pieces(start)
	L.p("block", 2400, 1320, 900, 40)             # level 1 (600 up)
	L.p("block", 2400, 720, 500, 40)              # level 2
	L.p("block", 2400, 400, 160, 40)              # the roof
	L.m["htf_flag"] = Vector2(2400, 370)
	for x in [220.0, 460.0, 900.0]:
		L.spawn(1, x, 1640 if x == 900.0 else 1880)
		L.spawn(2, L.W - x, 1640 if x == 900.0 else 1880)
	L.m["player_spawn"] = Vector2(460, 1880)
	for v in [Vector2(220, 1880), Vector2(4580, 1880), Vector2(900, 1640), Vector2(3900, 1640), Vector2(2400, 1880),
			Vector2(2150, 1280), Vector2(2650, 1280), Vector2(2400, 680)]:
		L.ffa(v.x, v.y)
	L.weapon("Barrett", 2400, 680)
	L.weapon("LAW", 2250, 1280)
	L.weapon("LAW", 2550, 1280)
	L.weapon("MP5", 900, 1640)
	L.weapon("MP5", 3900, 1640)
	L.weapon("Spas-12", 2400, 1880)
	L.add("medkits", 2400, 1280)
	L.add("medkits", 600, 1880)
	L.add("medkits", 4200, 1880)
	L.add("grenade_kits", 2300, 680)
	L.deco("l_lamp_tl-sk", 1300, 1900, 0.8)
	L.deco("barbwire", 1000, 1900, 0.6)
	L.mirror_scenery()
	return L.done()


# ── 4. Iron Valley — vehicle warfare: buggy, tank, heli, plane per base (jungle, L, floor) ─
static func src_iron_valley() -> Dictionary:
	var L := Lv.new(2, "floor")
	var start := L.pcs.size()
	# valley floor = 2500
	L.ground(0, 1800, 2140, 360)                  # base plateau + runway
	L.ramp(1800, 2140, 2400, 2500)
	L.prop("sandbags", 2900, 2500)                # (the plateau stays clear: it's the runway)
	L.mirror_pieces(start)
	L.p("hill", 3600, 2400, 1300, 200)            # the hill in the middle
	L.m["ctf_flags"] = [Vector2(1250, 2120), Vector2(5950, 2120)]
	for x in [880.0, 1150.0, 1400.0]:
		L.spawn(1, x, 2120)
		L.spawn(2, L.W - x, 2120)
	L.m["player_spawn"] = Vector2(1150, 2120)
	L.add("plane_spawns", 160, 2120)              # the runway: the whole back of the plateau
	L.add("plane_spawns", L.W - 160, 2120)
	L.add("heli_spawns", 1600, 2120)
	L.add("heli_spawns", L.W - 1600, 2120)
	L.add("vehicle_spawns", 1700, 2120)
	L.add("vehicle_spawns", L.W - 1700, 2120)
	L.add("tank_spawns", 2650, 2480)
	L.add("tank_spawns", L.W - 2650, 2480)
	for v in [Vector2(900, 2120), Vector2(6300, 2120), Vector2(2600, 2480), Vector2(4600, 2480), Vector2(3600, 2280),
			Vector2(3100, 2480), Vector2(4100, 2480), Vector2(1450, 2120)]:
		L.ffa(v.x, v.y)
	L.weapon("LAW", 3600, 2280)
	L.weapon("LAW", 1000, 2120)
	L.weapon("LAW", 6200, 2120)
	L.weapon("Barrett", 3200, 2480)
	L.weapon("Barrett", 4000, 2480)
	L.add("medkits", 1320, 2120)
	L.add("medkits", 5880, 2120)
	L.add("grenade_kits", 2900, 2480)
	L.add("grenade_kits", 4300, 2480)
	L.deco("jungletree", 420, 2140, 0.85)
	L.deco("veg_palm_7", 1700, 2140, 0.8)
	L.deco("jungletree", 2500, 2500, 0.8)
	L.deco("bush3", 3000, 2500, 0.8)
	L.mirror_scenery()
	return L.done()


# ── 5. The Bunker — tight three-deck deathmatch under a concrete roof (night, S, floor) ─
static func src_the_bunker() -> Dictionary:
	var L := Lv.new(0, "floor")
	# ground floor = 1500, mid deck 1100, upper deck 700, roof underside 300
	L.p("block", 1600, 150, 3200, 300)            # the roof
	var start := L.pcs.size()
	L.p("block", 770, 1120, 1220, 40)             # mid deck, left (160 .. 1380)
	L.p("block", 580, 720, 840, 40)               # upper deck, left (160 .. 1000)
	L.p("wall", 700, 1210, 40, 140)               # hanging wall under the mid deck
	L.p("hill", 160, 360, 240, 60, 2)             # roof drips
	L.prop("crate", 420, 1500)
	L.prop("sandbags", 1100, 1500)
	L.prop("crate", 380, 1100)
	L.prop("barrel", 860, 700)
	L.mirror_pieces(start)
	L.p("block", 1600, 720, 800, 40)              # upper deck, middle (1200 .. 2000)
	L.prop("crate_big", 1600, 1500)
	L.ladder(90, 700, 1500)
	L.ladder(3110, 700, 1500)
	L.ladder(1190, 700, 1100)
	L.ladder(L.W - 1190, 700, 1100)
	# Every objective placed by hand (the auto-placer would stand them on the roof).
	L.m["rambo_pos"] = Vector2(1600, 680)
	L.m["inf_flag"] = Vector2(1600, 1380)
	L.m["htf_flag"] = Vector2(1600, 1380)
	L.m["ctf_flags"] = [Vector2(200, 1480), Vector2(3000, 1480)]
	L.m["dom_points"] = [Vector2(560, 1480), Vector2(1600, 680), Vector2(2640, 1480)]
	for v in [Vector2(300, 1480), Vector2(1000, 1480), Vector2(2200, 1480), Vector2(2900, 1480), Vector2(520, 1080),
			Vector2(2680, 1080), Vector2(1250, 1080), Vector2(1950, 1080), Vector2(560, 680), Vector2(2640, 680)]:
		L.ffa(v.x, v.y)
	L.m["player_spawn"] = Vector2(1250, 1480)
	L.spawn(1, 260, 1480)
	L.spawn(1, 520, 1080)
	L.spawn(1, 560, 680)
	L.spawn(2, 2940, 1480)
	L.spawn(2, 2680, 1080)
	L.spawn(2, 2640, 680)
	L.weapon("Spas-12", 1000, 1080)
	L.weapon("Spas-12", 2200, 1080)
	L.weapon("Minimi", 1600, 680)
	L.weapon("Chainsaw", 1350, 1480)
	L.weapon("M79", 300, 680)
	L.weapon("MP5", 2900, 680)
	L.add("medkits", 800, 1480)
	L.add("medkits", 2400, 1480)
	L.add("grenade_kits", 1800, 1080)
	L.add("bonus_spawns", 1400, 680)
	L.deco("l_lamp_tl-sk", 1000, 1500, 0.7)
	L.deco("barbwire", 2300, 1500, 0.5)
	L.deco("gravestone2", 2700, 700, 0.25)
	return L.done()


# ── 6. Frostbite — two snowy peaks over a bottomless chasm (snow, M, bottomless) ──
static func src_frostbite() -> Dictionary:
	var L := Lv.new(1, "void")
	var start := L.pcs.size()
	L.ground(0, 1000, 1250, 650)                  # the peak (blue base)
	L.p("hill", 260, 1190, 400, 120)              # snow drift behind the flag
	L.ramp(1000, 1250, 1400, 1450)
	L.ground(1000, 1700, 1450, 450)               # shelf over the chasm
	L.ledge(1700, 2320, 1450)                     # ice bridge to the pillar
	L.prop("crate", 1550, 1450)
	L.prop("sandbags", 820, 1250)
	L.mirror_pieces(start)
	L.p("block", 2400, 1525, 160, 750)            # ice pillar in the chasm (INF flag on top)
	L.m["ctf_flags"] = [Vector2(560, 1230), Vector2(4240, 1230)]
	L.m["inf_flag"] = Vector2(2400, 1130)
	for x in [400.0, 700.0, 900.0]:
		L.spawn(1, x, 1230)
		L.spawn(2, L.W - x, 1230)
	L.m["player_spawn"] = Vector2(700, 1230)
	for v in [Vector2(300, 1150), Vector2(4500, 1150), Vector2(1550, 1430), Vector2(3250, 1430), Vector2(2000, 1430),
			Vector2(2800, 1430), Vector2(2400, 1130), Vector2(1200, 1340)]:
		L.ffa(v.x, v.y)
	L.weapon("Barrett", 2400, 1130)
	L.weapon("AK-74", 1550, 1430)
	L.weapon("AK-74", 3250, 1430)
	L.weapon("LAW", 900, 1230)
	L.weapon("LAW", 3900, 1230)
	L.add("medkits", 1650, 1430)
	L.add("medkits", 3150, 1430)
	L.add("grenade_kits", 120, 1230)
	L.add("grenade_kits", 4680, 1230)
	L.deco("mnp-deadtree1", 80, 1250, 0.3)
	L.deco("tree2", 980, 1260, 0.55)
	L.deco("xt_jh_stone01", 1450, 1450, 0.5)
	L.mirror_scenery()
	return L.done()


# ── 7. Hollow Deep — cavern with spike pits, ladders and three points (cave, M, bottomless) ─
static func src_hollow_deep() -> Dictionary:
	var L := Lv.new(1, "void")
	L.p("block", 2400, 350, 4800, 700)            # cave roof (underside at 700)
	var start := L.pcs.size()
	L.ground(0, 1100, 1500, 400)                  # blue cavern
	L.ground(1100, 1500, 1700, 200)               # spike pit floor
	L.spikes(1100, 1500, 1700)
	L.ledge(1100, 1280, 1500)                     # broken ledge over the pit (a hop in the middle)
	L.ledge(1320, 1500, 1500)
	L.ledge(1700, 2100, 1150)                     # upper gallery (ladder up)
	L.p("hill", 1200, 760, 420, 120, 2)           # stalactites
	L.p("hill", 2000, 760, 300, 100, 2)
	L.p("hill", 600, 760, 300, 140, 2)
	L.prop("crate", 900, 1500)
	L.prop("sandbags", 1650, 1500)
	L.mirror_pieces(start)
	L.ground(1500, 3300, 1500, 400)               # the central chamber
	L.p("hill", 2400, 1420, 800, 160)             # mound (point B)
	L.ladder(1740, 1150, 1500)
	L.ladder(L.W - 1740, 1150, 1500)
	L.m["dom_points"] = [Vector2(800, 1470), Vector2(2400, 1310), Vector2(4000, 1470)]
	L.m["ctf_flags"] = [Vector2(260, 1480), Vector2(4540, 1480)]
	L.m["htf_flag"] = Vector2(2400, 1320)
	L.m["inf_flag"] = Vector2(2400, 1320)
	L.m["rambo_pos"] = Vector2(2300, 1340)
	for x in [180.0, 420.0, 620.0]:
		L.spawn(1, x, 1480)
		L.spawn(2, L.W - x, 1480)
	L.m["player_spawn"] = Vector2(420, 1480)
	for v in [Vector2(300, 1480), Vector2(4500, 1480), Vector2(1000, 1480), Vector2(3800, 1480), Vector2(1900, 1130),
			Vector2(2900, 1130), Vector2(2000, 1480), Vector2(2800, 1480)]:
		L.ffa(v.x, v.y)
	L.weapon("Barrett", 1900, 1130)
	L.weapon("Barrett", 2900, 1130)
	L.weapon("Flamethrower", 2400, 1310)
	L.weapon("Steyr AUG", 700, 1480)
	L.weapon("Steyr AUG", 4100, 1480)
	L.add("medkits", 1600, 1480)
	L.add("medkits", 3200, 1480)
	L.add("grenade_kits", 2400, 1480)
	L.deco("mnp-skulls1", 1300, 1700, 0.25)
	L.deco("rocks2", 500, 1500, 0.8)
	L.deco("xt_jh_stone01", 2200, 1500, 0.5)
	L.mirror_scenery()
	return L.done()


# ── 8. Last Ridge — big Battle Royale ridge (grassland, L, floor) ─────────────────
static func src_last_ridge() -> Dictionary:
	var L := Lv.new(2, "floor")
	# floor = 2500; the ring closes on the summit (3600, ~1560)
	L.p("hill", 1150, 2375, 1300, 250)
	L.p("hill", 2500, 2350, 1200, 300)
	L.ground(3150, 4050, 2150, 350)               # the summit block...
	L.p("hill", 3600, 2050, 900, 200)             # ...and its crest
	L.ramp(2800, 2500, 3150, 2150)
	L.ramp(4050, 2150, 4400, 2500)
	L.p("hill", 4700, 2350, 1200, 300)
	L.p("hill", 6050, 2375, 1300, 250)
	# bunkers: a roof on two short walls (walk in under the roof)
	for bx in [1800.0, 5400.0]:
		L.p("block", bx, 2330, 360, 40)
		L.p("wall", bx - 160, 2390, 40, 80)
		L.p("wall", bx + 160, 2390, 40, 80)
	# sniper towers in the corners + the pads up
	L.p("block", 150, 2200, 200, 600)
	L.p("block", L.W - 150, 2200, 200, 600)
	L.pad(340, 2500, true)
	L.pad(L.W - 340, 2500, true)
	L.p("block", 3600, 1600, 300, 40)             # sky deck over the summit
	L.pad(3300, 2150, true)
	L.pad(3900, 2150, true)
	L.prop("crate_big", 1250, 2500)
	L.prop("crate", 5950, 2500)
	L.prop("sandbags", 2900, 2500)
	L.prop("sandbags", 4300, 2500)
	L.prop("barrel", 3450, 2150)
	for v in [Vector2(150, 1880), Vector2(7050, 1880), Vector2(1000, 2250), Vector2(1800, 2480), Vector2(2500, 2210), Vector2(3000, 2400),
			Vector2(3600, 1830), Vector2(4200, 2400), Vector2(4700, 2210), Vector2(5400, 2480), Vector2(6200, 2250),
			Vector2(6900, 2480), Vector2(3600, 1570)]:
		L.ffa(v.x, v.y)
	L.m["player_spawn"] = Vector2(1400, 2480)
	L.weapon("Barrett", 3600, 1570)
	L.weapon("AK-74", 1000, 2250)
	L.weapon("Steyr AUG", 6200, 2250)
	L.weapon("Spas-12", 1800, 2480)
	L.weapon("MP5", 5400, 2480)
	L.weapon("Minimi", 2500, 2210)
	L.weapon("M79", 4700, 2210)
	L.weapon("LAW", 3600, 1830)
	L.weapon("Ruger 77", 300, 2480)
	L.weapon("Deagles", 6900, 2480)
	L.add("medkits", 1800, 2480)
	L.add("medkits", 5400, 2480)
	L.add("medkits", 3600, 1830)
	L.add("medkits", 600, 2480)
	L.add("medkits", 6600, 2480)
	L.add("grenade_kits", 2500, 2210)
	L.add("grenade_kits", 4700, 2210)
	L.add("bonus_spawns", 3000, 2400)
	L.add("bonus_spawns", 4200, 2400)
	L.add("bonus_spawns", 1000, 2250)
	L.add("bonus_spawns", 6200, 2250)
	L.deco("tree2", 150, 2500, 0.75)
	L.deco("tree5", 1500, 2500, 0.8)
	L.deco("tree2", 2200, 2500, 0.7)
	L.deco("bush3", 3300, 2160, 0.8)
	L.deco("tree5", 5000, 2500, 0.8)
	L.deco("tree2", 5800, 2500, 0.7)
	L.deco("bush3", 7000, 2500, 0.8)
	L.deco("grass3", 3800, 2160, 0.45)
	return L.done()
