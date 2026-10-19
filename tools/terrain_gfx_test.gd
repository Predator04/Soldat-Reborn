extends SceneTree
## HD terrain (#283) — gate stage F: every bundled + built-in map resolves to
## an HD material and a background theme; every material / normal map / edge
## strip exists and imports with mipmaps; maps of different themes build the
## HD path (headless normally takes the classic path, so
## TerrainHD.force_hd_for_tests is set): fill mesh + shader, outline AO,
## painted edges, classic polygon nodes hidden, a handful of canvas items, no
## collision objects; reloading a map leaves the node count flat; a live
## switch to the classic look puts every classic node back.
##   godot --headless --fixed-fps 60 -s tools/terrain_gfx_test.gd

# map index (0-2 built-in, 3+ = MapIO.BUNDLED_CLASSICS + 3) and a label.
const RUNS := [[57, "jungle"], [39, "desert"], [70, "mrsnowman"], [47, "factory"], [89, "steel"], [0, "ascent"], [57, "jungle"], [57, "jungle"]]

var _n := 0
var _st := 0
var _run := 0
var _saved := []
var _bad: Array = []
var _log: Array = []
var _counts: Dictionary = {}
var HD = null
var TT = null


func _process(_d: float) -> bool:
	_n += 1
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _st == 0:
		HD = load("res://scripts/gfx/terrain_hd.gd")
		TT = load("res://scripts/gfx/terrain_theme.gd")
		_saved = [st.bot_count, st.game_mode, st.map_index, st.custom_map_path, st.gfx_quality, st.visual_style]
		_static_checks()
		HD.force_hd_for_tests = true
		st.bot_count = 0
		st.game_mode = 0
		st.custom_map_path = ""
		st.set_gfx_quality(2)
		st.visual_style = "cinematic"
		root.get_node("Net").set_singleplayer()
		_load(st)
		return false
	var m = current_scene
	if m == null or m.get("player") == null or m.get_node_or_null("TerrainHD") == null:
		return false
	var hd = m.get_node("TerrainHD")
	match _st:
		1:
			if _n < 40:
				return false
			_check_map(m, hd)
			if _run == 0:
				# Live switch: classic look puts the classic nodes back.
				st.visual_style = "classic"
				_st = 2
				_n = 0
				return false
			_next(st)
		2:
			if _n < 5:
				return false
			if hd.on or hd.visible:
				_bad.append("HD still on in the classic look")
			var hidden := 0
			for it in hd.items:
				for nd in it.get("nodes", []):
					if is_instance_valid(nd) and not (nd as CanvasItem).visible:
						hidden += 1
			# Ported maps keep their invisible safety floor/walls out of the list,
			# so every registered node must be visible again.
			if hidden > 0:
				_bad.append("%d classic nodes still hidden after switching to classic" % hidden)
			var tfx = m.get("terrain_fx")
			if tfx != null and not tfx.visible:
				_bad.append("terrain_fx left hidden in classic")
			st.visual_style = "cinematic"
			_st = 3
			_n = 0
		3:
			if _n < 5:
				return false
			if not hd.on:
				_bad.append("HD did not come back after switching to cinematic")
			_next(st)
	return false


func _load(st) -> void:
	st.map_index = int(RUNS[_run][0])
	change_scene_to_file("res://scenes/main.tscn")
	_st = 1
	_n = 0


func _next(st) -> void:
	_run += 1
	if _run >= RUNS.size():
		_finish(st)
		return
	_load(st)


func _check_map(m, hd) -> void:
	var label: String = RUNS[_run][1]
	if not hd.on or not hd.built:
		_bad.append("%s: HD path not built (on=%s built=%s)" % [label, hd.on, hd.built])
		return
	for s in hd.slots:
		if not TT.MATERIALS.has(s):
			_bad.append("%s: unknown material slot %s" % [label, s])
	if hd.slots.is_empty():
		_bad.append("%s: no material" % label)
	var fill = hd.get_node_or_null("Fill")
	if fill == null or not (fill is MeshInstance2D) or not (fill.material is ShaderMaterial):
		_bad.append("%s: fill mesh / shader missing" % label)
	elif not (fill.texture is CanvasTexture) or fill.texture.normal_texture == null:
		_bad.append("%s: fill has no CanvasTexture with a normal map (2D lights)" % label)
	if int(hd.tris_built) <= 0:
		_bad.append("%s: no triangles" % label)
	if int(hd.edge_counts.get("ao", 0)) <= 0:
		_bad.append("%s: no outline AO" % label)
	var painted := 0
	for k in hd.edge_counts:
		if k != "ao":
			painted += int(hd.edge_counts[k])
	if painted <= 0:
		_bad.append("%s: no painted edges" % label)
	var items := 0
	for c in hd.get_children():
		if c is CanvasItem:
			items += 1
	if items > 12 or items < 2:
		_bad.append("%s: %d canvas items under TerrainHD" % [label, items])
	for c in _all(hd):
		if c is CollisionObject2D or c is CollisionPolygon2D or c is CollisionShape2D:
			_bad.append("%s: collision node under TerrainHD" % label)
			break
	var visible_classic := 0
	for it in hd.items:
		for nd in it.get("nodes", []):
			if is_instance_valid(nd) and (nd as CanvasItem).visible:
				visible_classic += 1
	if visible_classic > 0:
		_bad.append("%s: %d classic terrain nodes still visible" % [label, visible_classic])
	var tfx = m.get("terrain_fx")
	if tfx != null and tfx.visible:
		_bad.append("%s: terrain_fx not hidden" % label)
	# Reloads: the HD subtree is identical and the whole tree does not grow
	# (a few transient sound / timer nodes come and go, hence the slack).
	var count := get_node_count()
	var hd_count := _all(hd).size()
	if _counts.has(label):
		var was: Array = _counts[label]
		if int(was[1]) != hd_count:
			_bad.append("%s: TerrainHD nodes %d -> %d on reload" % [label, int(was[1]), hd_count])
		if count > int(was[0]) + 8:
			_bad.append("%s: node count grew %d -> %d on reload" % [label, int(was[0]), count])
	else:
		_counts[label] = [count, hd_count]
	_log.append("nodes=%d/hd%d" % [count, hd_count])
	_log.append("%s=%s/%d tris/%s %dms" % [label, "+".join(hd.slots), int(hd.tris_built), _edge_str(hd.edge_counts), int(hd.build_ms)])


func _edge_str(d: Dictionary) -> String:
	var parts := []
	for k in d:
		parts.append("%s%d" % [str(k).substr(0, 3), int(d[k])])
	return ",".join(parts)


func _all(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		out.append(c)
		out.append_array(_all(c))
	return out


func _static_checks() -> void:
	# Assets: albedo + normal per material, mean colour in materials.json,
	# edge strips; all importing with mipmaps.
	var meta: Dictionary = HD._load_meta()
	var files: Array = []
	for mat in TT.MATERIALS:
		files.append(mat + TT.MAT_EXT)
		files.append(mat + "_n" + TT.MAT_EXT)
		if not meta.has(mat):
			_bad.append("materials.json: no mean for %s" % mat)
	for k in HD.EDGE_LINE:
		files.append("edge_%s.png" % k)
	for f in files:
		var path: String = TT.DIR + f
		if not ResourceLoader.exists(path) or load(path) == null:
			_bad.append("missing %s" % f)
			continue
		var imp := FileAccess.get_file_as_string(path + ".import")
		if imp.find("mipmaps/generate=true") < 0:
			_bad.append("%s imports without mipmaps" % f)
	# Every map resolves: classic texture -> material, theme, edge styles.
	var MapIO = load("res://scripts/map_io.gd")
	var maps: Array = MapIO.load_bundled_classics()
	if maps.size() < 99:
		_bad.append("only %d bundled maps" % maps.size())
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	for t in ["xt_ap_grasrock_02", "earthen", "riverbed"]:
		if main_src.find(t) < 0:
			_bad.append("built-in map texture %s moved — update the test" % t)
	maps.append({"name": "Ascent", "terrain_texture": "res://assets/textures/xt_ap_grasrock_02.png", "polys": []})
	maps.append({"name": "Towers", "terrain_texture": "res://assets/textures/earthen.png", "polys": []})
	maps.append({"name": "Pillars", "terrain_texture": "res://assets/textures/riverbed.png", "polys": []})
	maps.append({"name": "Custom", "terrain_texture": "", "terrain_color": Color(0.3, 0.5, 0.2), "polys": []})
	var by_mat: Dictionary = {}
	var by_theme: Dictionary = {}
	for mp in maps:
		var prim: String = TT.primary_for(mp)
		if not TT.MATERIALS.has(prim):
			_bad.append("%s: material %s" % [mp.get("name", "?"), prim])
		var stem: String = TT.stem(str(mp.get("terrain_texture", "")))
		if stem != "" and not TT.TEXTURE_MATERIAL.has(stem):
			_bad.append("%s: texture %s not in TEXTURE_MATERIAL" % [mp.get("name", "?"), stem])
		var th: String = TT.theme_for(mp)
		if not ["rock", "urban", "desert", "snow", "jungle", "ruins"].has(th):
			_bad.append("%s: theme %s" % [mp.get("name", "?"), th])
		var avg: Color = TT.average_color(mp)
		var cm: String = TT.classify(prim, avg, TT.snowy(mp))
		if not TT.MATERIALS.has(cm):
			_bad.append("%s: classify -> %s" % [mp.get("name", "?"), cm])
		var w: Dictionary = TT.weights(prim, avg, TT.snowy(mp))
		var tot := 0.0
		for k in w:
			tot += float(w[k])
		if absf(tot - 1.0) > 0.01:
			_bad.append("%s: weights sum %.3f" % [mp.get("name", "?"), tot])
		by_mat[prim] = int(by_mat.get(prim, 0)) + 1
		by_theme[th] = int(by_theme.get(th, 0)) + 1
	_log.append("maps=%d mats=%s themes=%s" % [maps.size(), str(by_mat), str(by_theme)])


func _finish(st) -> void:
	HD.force_hd_for_tests = false
	st.bot_count = _saved[0]
	st.game_mode = _saved[1]
	st.map_index = _saved[2]
	st.custom_map_path = _saved[3]
	st.set_gfx_quality(_saved[4])
	st.visual_style = _saved[5]
	print("TERRAIN-TEST %s %s | %s" % ["ok" if _bad.is_empty() else "FAIL", str(_bad), " ".join(_log)])
	quit()
