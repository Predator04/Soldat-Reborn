extends Object
## MapIO — JSON serialization for custom maps + map directory helpers.
## Map dict shape matches main.gd's MAPS entries so a loaded map is a drop-in
## replacement for a hardcoded one: name, platforms=[{p, s}], player_spawn,
## bot_spawns=[Vector2], plus optional ctf_flags / inf_flag / htf_flag /
## rambo_pos / dom_points / m2_mounts for mode-specific entities.

const MAPS_DIR := "user://maps/"


static func ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(MAPS_DIR):
		DirAccess.make_dir_recursive_absolute(MAPS_DIR)


static func map_to_json(m: Dictionary) -> String:
	var out := {}
	out["name"] = str(m.get("name", "Custom"))
	var pls: Array = []
	for pl in m.get("platforms", []):
		var p: Vector2 = pl.get("p", Vector2.ZERO)
		var s: Vector2 = pl.get("s", Vector2.ZERO)
		pls.append({"p": [p.x, p.y], "s": [s.x, s.y]})
	out["platforms"] = pls
	var ps: Vector2 = m.get("player_spawn", Vector2(200, 1775))
	out["player_spawn"] = [ps.x, ps.y]
	var bs: Array = []
	for b in m.get("bot_spawns", []):
		bs.append([b.x, b.y])
	out["bot_spawns"] = bs
	for list_key in ["m2_mounts", "ctf_flags", "dom_points"]:
		if m.has(list_key):
			var arr: Array = []
			for v in m[list_key]:
				arr.append([v.x, v.y])
			out[list_key] = arr
	for key in ["inf_flag", "htf_flag", "rambo_pos"]:
		if m.has(key):
			var v: Vector2 = m[key]
			out[key] = [v.x, v.y]
	# Optional terrain polygons — serialize as an array of flat float arrays.
	if m.has("polys"):
		var polys_out: Array = []
		for poly in m["polys"]:
			var pts: PackedVector2Array = poly.get("points", PackedVector2Array())
			var flat: Array = []
			for p in pts:
				flat.append(p.x)
				flat.append(p.y)
			polys_out.append({"points": flat})
		out["polys"] = polys_out
	for key in ["terrain_color", "terrain_texture", "floor_texture"]:
		if m.has(key) and typeof(m[key]) == TYPE_STRING:
			out[key] = m[key]
	return JSON.stringify(out, "  ")


static func _v2(v: Variant, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if typeof(v) != TYPE_ARRAY or v.size() < 2:
		return fallback
	return Vector2(float(v[0]), float(v[1]))


static func json_to_map(text: String) -> Dictionary:
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var m := {}
	m["name"] = str(parsed.get("name", "Custom"))
	var pls: Array = []
	for pl in parsed.get("platforms", []):
		pls.append({"p": _v2(pl.get("p")), "s": _v2(pl.get("s"))})
	m["platforms"] = pls
	m["player_spawn"] = _v2(parsed.get("player_spawn"), Vector2(200, 1775))
	var bs: Array = []
	for b in parsed.get("bot_spawns", []):
		bs.append(_v2(b))
	m["bot_spawns"] = bs
	for list_key in ["m2_mounts", "ctf_flags", "dom_points"]:
		if parsed.has(list_key):
			var arr: Array = []
			for b in parsed[list_key]:
				arr.append(_v2(b))
			m[list_key] = arr
	for key in ["inf_flag", "htf_flag", "rambo_pos"]:
		if parsed.has(key):
			m[key] = _v2(parsed[key])
	if parsed.has("polys"):
		var polys: Array = []
		for poly in parsed["polys"]:
			var flat: Array = poly.get("points", [])
			var pts := PackedVector2Array()
			var i := 0
			while i + 1 < flat.size():
				pts.append(Vector2(float(flat[i]), float(flat[i + 1])))
				i += 2
			polys.append({"points": pts})
		m["polys"] = polys
	for key in ["terrain_texture", "floor_texture"]:
		if parsed.has(key):
			m[key] = str(parsed[key])
	if parsed.has("ctf_ground_y"):
		m["ctf_ground_y"] = float(parsed["ctf_ground_y"])
	return m


static func save_to_file(display_name: String, m: Dictionary) -> String:
	ensure_dir()
	var safe := safe_filename(display_name)
	var path := MAPS_DIR + safe + ".json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(map_to_json(m))
	f.close()
	return path


static func load_from_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var t := f.get_as_text()
	f.close()
	return json_to_map(t)


# Filenames (without extension) bundled under res://assets/maps/ — the classic
# .pms maps converted by tools/pms_to_map.py (closes #53). Order here is the
# order they appear in the map picker.
const BUNDLED_CLASSICS := [
	"nuubia", "maya", "aftermath", "hormone", "viet",
	"scorpion", "warehouse", "baire", "airpirates", "bunker",
]


static func load_bundled_classics() -> Array:
	# Loads the bundled classic maps from res://assets/maps/*.json. Returns
	# each as a Dictionary matching the MAPS entry shape used in main.gd.
	var out: Array = []
	for stem in BUNDLED_CLASSICS:
		var path := "res://assets/maps/%s.json" % stem
		if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var t := f.get_as_text()
		f.close()
		var m := json_to_map(t)
		if m.is_empty():
			continue
		# json_to_map defaults player_spawn if missing but we already have it.
		# Ensure platforms is at least an empty array (main.gd iterates it).
		if not m.has("platforms"):
			m["platforms"] = []
		out.append(m)
	return out


static func list_files() -> Array:
	ensure_dir()
	var out: Array = []
	var d := DirAccess.open(MAPS_DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if not d.current_is_dir() and f.ends_with(".json"):
			out.append(MAPS_DIR + f)
		f = d.get_next()
	out.sort()
	return out


static func safe_filename(n: String) -> String:
	var s := n.strip_edges().to_lower()
	if s == "":
		return "map"
	var out := ""
	for i in s.length():
		var c: String = s.substr(i, 1)
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
		elif c == " " or c == "-" or c == "_":
			out += "_"
	if out == "":
		out = "map"
	return out
