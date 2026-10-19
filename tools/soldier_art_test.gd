extends SceneTree
## Operator soldier art (#280, gate stage F).
##   godot --headless -s tools/soldier_art_test.gd
## Checks that every Operator part in rig.json exists in both facings with a
## normal map and mipmaps, that every trim / accent / wound layer has its
## mirror, and that the draw path paints
## soldiers in every pose and look with the Operator art forced on: all head
## cosmetics, vest with / without paint, dead, prone, jetting both ways, low
## HP. The jet flame leaves the pack behind the soldier. The setting picks the
## look (classic wins; Low quality and headless stay classic unless forced).
## Zero script errors (the gate greps the log).

const PUPPET_SRC := """
extends Node2D
var ds
var art
var pose := {}
var draws := 0
func _process(_d):
	queue_redraw()
func _draw():
	for k in pose:
		ds.set(k, pose[k])
	art.draw_soldier(self, ds)
	draws += 1
"""

var _n := 0
var _bad: Array = []
var _log: Array = []
var _puppets: Array = []
var _G = null


func _check_assets() -> void:
	# Every part in rig.json: base + mirror, a normal map for each, mipmaps, and
	# every extra layer (_trim / _acc / _wound) present in both facings.
	_G._load_rig()
	var keys: Array = _G._rig.keys()
	keys.erase("__none__")
	for want in ["klata", "biodro", "udo", "noga", "stopa", "ramie", "reka", "dlon", "morda", "helm", "kap",
			"hair1", "hair2", "hair3", "hair4", "kamizelka", "jetpack", "lancuch", "zlotylancuch", "metal", "cygaro", "dred"]:
		if not keys.has(want):
			_bad.append("rig.json has no %s" % want)
	for key in keys:
		for mir in [false, true]:
			var sfx := "2" if mir else ""
			var hd = _G._tex_hd(key, mir)
			if hd == null:
				_bad.append("missing %s%s" % [key, sfx])
				continue
			if not (hd is CanvasTexture) or (hd as CanvasTexture).normal_texture == null:
				_bad.append("%s%s has no normal map" % [key, sfx])
			var diff: Texture2D = hd.diffuse_texture if hd is CanvasTexture else hd
			var img := diff.get_image()
			if img != null and not img.has_mipmaps():
				_bad.append("%s%s imported without mipmaps (set mipmaps/generate=true in its .import)" % [key, sfx])
			for lay in ["_trim", "_acc", "_wound"]:
				var base_has: bool = _G._tex_hd(key + lay, false) != null
				var mir_has: bool = _G._tex_hd(key + lay, true) != null
				if base_has != mir_has:
					_bad.append("%s%s has no mirror pair" % [key, lay])
	_log.append("assets %d parts" % keys.size())


func _poses() -> Array:
	var B := Color(0.35, 0.55, 1.0)
	var R := Color(0.85, 0.3, 0.25)
	var out := []
	for h in ["helm", "kap", "hair1", "hair2", "hair3", "hair4", "none"]:
		out.append({"body_color": B, "weapon_name": "AK-74", "cosmetics": {"head": h, "dreadlocks": h == "hair1"}})
	out.append({"body_color": R, "facing": -1.0, "aim_dir": Vector2.LEFT, "weapon_name": "Spas-12",
		"cosmetics": {"vest": true, "vfinish": "gold", "chain": "gold", "cigar": true, "dogtag": true}})
	out.append({"body_color": R, "facing": -1.0, "aim_dir": Vector2.LEFT, "weapon_name": "MP5", "cosmetics": {"vest": true}})
	out.append({"body_color": B, "jet_on": true, "on_floor": false, "vel": Vector2(60, -200), "weapon_name": "LAW"})
	out.append({"body_color": R, "jet_on": true, "on_floor": false, "facing": -1.0, "aim_dir": Vector2.LEFT, "vel": Vector2(-60, -200)})
	out.append({"body_color": B, "prone": true, "weapon_name": "Barrett"})
	out.append({"body_color": R, "crouching": true, "facing": -1.0, "aim_dir": Vector2.LEFT})
	out.append({"body_color": B, "dead": true})
	out.append({"body_color": B, "health": 20.0, "vel": Vector2(215, 0), "grenade_count": 3, "back_weapon_name": "USSOCOM",
		"cosmetics": {"head": "hair4", "dreadlocks": true, "chain": "silver"}})
	out.append({"body_color": R, "rolling": true, "vel": Vector2(300, 0)})
	return out


func _process(_d: float) -> bool:
	_n += 1
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _n == 2:
		_G = load("res://scripts/gostek.gd")
		_check_assets()
		# Headless (and Low) stay classic unless a test forces the Operator art.
		if _G.operator_on():
			_bad.append("operator_on() true in a headless run")
		_G.force_operator_for_tests = true
		var art = load("res://scripts/soldier_art.gd")
		var dsc = load("res://scripts/soldier_draw_state.gd")
		var scr := GDScript.new()
		scr.source_code = PUPPET_SRC
		scr.reload()
		var i := 0
		for p in _poses():
			var n := Node2D.new()
			n.set_script(scr)
			n.ds = dsc.new()
			n.art = art
			n.pose = p
			n.position = Vector2(40 * i, 0)
			root.add_child(n)
			_puppets.append(n)
			i += 1
		return false
	if _n == 40:
		for p in _puppets:
			if int(p.draws) < 5:
				_bad.append("puppet %d drew %d times" % [_puppets.find(p), int(p.draws)])
		# every Operator layer the poses need was actually loaded
		for k in ["klata", "klata_trim", "klata_acc", "helm", "helm_trim", "helm_acc", "kap", "morda_trim", "jetpack",
				"jetpack_acc", "kamizelka", "stopa", "dlon", "udo_trim", "noga_trim", "ramie_acc", "reka_trim", "biodro_trim",
				"klata2", "helm2", "jetpack2", "morda2", "hair1", "hair2", "hair3", "hair4", "dred", "cygaro", "zlotylancuch",
				"metal", "klata_wound", "udo_wound"]:
			if _G._hd_cache.get(k) == null:
				_bad.append("layer %s never drawn" % k)
		# jet flame comes out of the pack, behind the soldier
		for idx in [9, 10]:
			var p: Node2D = _puppets[idx]
			var nz: Array = _G.jet_nozzle(p)
			var facing: float = float(p.pose.get("facing", 1.0))
			if nz.is_empty():
				_bad.append("no jet nozzle (puppet %d)" % idx)
			elif (nz[0] as Vector2).x * facing >= 0.0:
				_bad.append("jet nozzle %s not behind a soldier facing %d" % [str(nz[0]), int(facing)])
			else:
				_log.append("nozzle %s" % str((nz[0] as Vector2).round()))
		# the setting wins over everything but the test flag
		_G.force_operator_for_tests = false
		var keep = st.soldier_look
		st.soldier_look = "classic"
		if _G.operator_on():
			_bad.append("classic look still drew Operator")
		st.soldier_look = keep
		_log.append("puppets %d" % _puppets.size())
		var ok := _bad.is_empty()
		print("SOLDIER-ART-TEST %s %s%s" % ["ok" if ok else "FAIL", " | ".join(_log), "" if ok else " | " + "; ".join(_bad)])
		quit(0 if ok else 1)
	return false
