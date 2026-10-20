extends SceneTree
## Dev tool (#295): builds the bundled FEATURED levels from the piece lists in
## tools/featured_src.gd and writes each one as the Maker saves it —
## maker_build.gd compile() through map_io — to assets/levels/featured/<slug>.json.
##   godot --headless -s tools/make_featured.gd [-- --only=slug,slug]
## Feet-anchored entities (spawns, flags, kits, vehicles ...) are dropped onto
## the terrain under the position given in the source (so the sources can say
## "about here"); DOM points end up 28 px over the ground, pickups 16 px. Each
## level must validate with no errors and no warnings for its listed modes.
## Run python3 tools/map_audit.py on the files afterwards.

const MODE_IDX := {"dm": 0, "tdm": 1, "ctf": 2, "inf": 3, "htf": 4, "rm": 5, "pm": 6, "dom": 7, "br": 8, "gg": 9}
const FEET_KEYS := ["bot_spawns", "ctf_flags", "medkits", "grenade_kits", "bonus_spawns",
	"vehicle_spawns", "tank_spawns", "heli_spawns", "plane_spawns", "m2_mounts"]
const FEET_SINGLE := ["player_spawn", "inf_flag", "htf_flag", "rambo_pos"]

var _only: Array = []
var _n := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = Array(a.substr(7).split(",", false))


func _process(_d: float) -> bool:
	_n += 1
	if _n < 2:
		return false
	var B = load("res://scripts/maker/maker_build.gd")
	var IO = load("res://scripts/map_io.gd")
	var FL = load("res://scripts/featured_levels.gd")
	var Src = load("res://tools/featured_src.gd")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FL.DIR))
	var bad := 0
	var have := {}
	for mt in (Src as GDScript).get_script_method_list():
		have[str(mt["name"])] = true
	for e in FL.LEVELS:
		var slug := str(e["slug"])
		if not _only.is_empty() and not _only.has(slug):
			continue
		if not have.has("src_" + slug):
			print("FEATURED %-14s (no source yet)" % slug)
			bad += 1
			continue
		var src: Dictionary = Src.call("src_" + slug)
		src["name"] = str(e["title"])
		src["maker"]["theme"] = str(e["theme"])
		_snap(B, src)
		var c: Dictionary = B.compile(src)
		c["name"] = str(e["title"])
		c.erase("_mk_outlines")
		var probs: Array = []
		for k in str(e["modes"]).split(" ", false):
			for p in B.validate(c, int(MODE_IDX[k])):
				probs.append("%s %s: %s at %s" % [k, p["lvl"], p["msg"], str(p["at"])])
		var f := FileAccess.open(ProjectSettings.globalize_path(FL.path(slug)), FileAccess.WRITE)
		f.store_string(IO.map_to_json(c))
		f.close()
		var nh: int = (c.get("hazards", []) as Array).size()
		var np: int = (c.get("jump_pads", []) as Array).size()
		print("FEATURED %-14s pieces=%d polys=%d coll=%d hazards=%d pads=%d auto=%s %s" % [slug, (src["maker"]["pieces"] as Array).size(),
			(c["polys"] as Array).size(), (c["collision"] as Array).size(), nh, np, str(c["maker"].get("auto", [])),
			"ok" if probs.is_empty() else "PROBLEMS"])
		for p in probs:
			print("   ", p)
		if not probs.is_empty():
			bad += 1
	print("MAKE-FEATURED %s" % ("ok" if bad == 0 else "%d levels with problems" % bad))
	quit(0 if bad == 0 else 1)
	return true


## Drop feet-anchored entities onto the terrain under them; DOM points sit 28 px
## over it, weapon pickups 16 px.
func _snap(B, src: Dictionary) -> void:
	var c: Dictionary = B.compile(src)
	var solids: Array = B._solids(c)
	var w: Dictionary = c["world"]
	var limit := float(w.get("kill_y", w.get("ground_y", 1900.0)))
	if bool(w.get("floor_visible", false)):
		limit = float(w["ground_y"])
	var drop_col := func(p: Vector2) -> Vector2:
		var y := p.y - 40.0
		while B._in_solid(solids, Vector2(p.x, y)) and y > p.y - 400.0:
			y -= 4.0
		while y < limit:
			if B._in_solid(solids, Vector2(p.x, y)):
				var top := y - 2.0
				while top < y and not B._in_solid(solids, Vector2(p.x, top)):
					top += 0.5
				return Vector2(p.x, floorf(top) - 2.0)
			y += 2.0
		if bool(w.get("floor_visible", false)):
			return Vector2(p.x, limit - 2.0)
		push_warning("make_featured: nothing under %s" % str(p))
		return p
	# The soldier box is 14 px wide: on a slope its uphill side decides.
	var drop := func(p: Vector2) -> Vector2:
		var y := INF
		for dx in [-8.0, 0.0, 8.0]:
			y = minf(y, (drop_col.call(Vector2(p.x + dx, p.y)) as Vector2).y)
		return Vector2(p.x, y)
	for k in FEET_SINGLE:
		if src.has(k):
			src[k] = drop.call(src[k])
	for k in FEET_KEYS:
		if src.has(k):
			var arr: Array = []
			for v in src[k]:
				arr.append(drop.call(v))
			src[k] = arr
	if src.has("team_spawns"):
		for t in src["team_spawns"]:
			var arr: Array = []
			for v in src["team_spawns"][t]:
				arr.append(drop.call(v))
			src["team_spawns"][t] = arr
	if src.has("dom_points"):
		var arr: Array = []
		for v in src["dom_points"]:
			arr.append(drop.call(v) + Vector2(0, -28))
		src["dom_points"] = arr
	if src.has("point_spawns"):
		var arr: Array = []
		for v in src["point_spawns"]:
			arr.append(drop.call(v) + Vector2(0, -24))
		src["point_spawns"] = arr
	if src.has("weapon_pickups"):
		for wp in src["weapon_pickups"]:
			wp["pos"] = drop.call(wp["pos"]) + Vector2(0, -16)
