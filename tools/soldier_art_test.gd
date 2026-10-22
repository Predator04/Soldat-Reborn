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
## #306 team readability: the team-paint (_acc) layers exist and cover big
## areas (helmet dome, plates, pads, gaiter, cap crown, vest, jetpack); team
## modes paint them in the team colour (cosmetic paint loses there) while
## free-for-all keeps the player's colours; the palette setting (classic /
## colour-blind / high contrast) applies at once; enemies get a stronger
## outline than allies; Low quality gets the cheap team-edge material in team
## modes (none otherwise); team markers show allies always and enemies only
## when aimed at / close, never a cloaked one.
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
	# #306: the team paint covers big areas (fraction of the part's own pixels).
	var want_cov := {"helm": 0.45, "kap": 0.5, "klata": 0.2, "kamizelka": 0.3, "ramie": 0.4, "jetpack": 0.15, "morda": 0.1}
	for key in want_cov:
		for mir in [false, true]:
			var acc = _G._tex_hd(key + "_acc", mir)
			var base = _G._tex_hd(key, mir)
			if acc == null or base == null:
				_bad.append("no team paint layer %s_acc%s" % [key, "2" if mir else ""])
				continue
			var cov := _coverage(acc, base)
			if cov < float(want_cov[key]):
				_bad.append("team paint on %s covers %.2f < %.2f" % [key, cov, float(want_cov[key])])
			if not mir:
				_log.append("%s paint %.2f" % [key, cov])


## Opaque pixels of `layer` / opaque pixels of `base` (mip 0), and the paint
## must be near-white (the tint carries the team hue).
func _coverage(layer, base) -> float:
	var li: Image = (layer.diffuse_texture if layer is CanvasTexture else layer).get_image()
	var bi: Image = (base.diffuse_texture if base is CanvasTexture else base).get_image()
	if li == null or bi == null:
		return 0.0
	li = li.duplicate()
	bi = bi.duplicate()
	li.clear_mipmaps()
	bi.clear_mipmaps()
	if li.is_compressed():
		li.decompress()
	if bi.is_compressed():
		bi.decompress()
	var n_l := 0
	var n_b := 0
	var lum := 0.0
	var sat := 0.0
	for y in range(0, li.get_height(), 3):
		for x in range(0, li.get_width(), 3):
			var c := li.get_pixel(x, y)
			if c.a > 0.5:
				n_l += 1
				lum += c.get_luminance()
				sat += c.s
			if bi.get_pixel(x, y).a > 0.5:
				n_b += 1
	if n_l > 0 and (sat / n_l > 0.12 or lum / n_l < 0.35):
		_bad.append("team paint is not near-white (lum %.2f sat %.2f)" % [lum / n_l, sat / n_l])
	return float(n_l) / maxf(1.0, float(n_b))


func _check_palette(st) -> void:
	var TC = load("res://scripts/team_colors.gd")
	var keep_mode = st.game_mode
	var keep_tc = st.team_colors
	# free-for-all: no team paint, own colours kept
	for m in [st.MODE_DM, st.MODE_RM, st.MODE_BR, st.MODE_GG]:
		st.game_mode = m
		TC.invalidate()
		if TC.team_of(1) != 0 or TC.team_of(2) != 0:
			_bad.append("mode %d is free-for-all but shows teams" % m)
		var own := Color(0.2, 0.9, 0.3)
		if TC.body_for(1, own) != own:
			_bad.append("mode %d repaints a soldier's own colour" % m)
	for m in [st.MODE_TDM, st.MODE_CTF, st.MODE_INF, st.MODE_HTF, st.MODE_PM, st.MODE_DOM]:
		st.game_mode = m
		TC.invalidate()
		if TC.team_of(1) != 1 or TC.team_of(2) != 2 or TC.team_of(1000) != 0:
			_bad.append("team mode %d: team_of wrong" % m)
	st.game_mode = st.MODE_CTF
	# team paint wins over cosmetics in team modes; FFA keeps them
	var paint: Color = TC.paint(1)
	var acc := Color(0.7, 0.8, 1.0)
	var gold := Color(1.0, 0.8, 0.28)
	for k in ["helm", "kap", "kamizelka", "klata", "ramie", "jetpack", "morda"]:
		if _G._paint_color(k, 1, paint, acc, gold) != paint:
			_bad.append("team mode: %s paint is not the team colour" % k)
	for k in ["helm", "kap", "kamizelka"]:
		if _G._paint_color(k, 0, paint, acc, gold) != gold:
			_bad.append("free-for-all: %s lost the player's paint" % k)
	if _G._paint_color("klata", 0, paint, acc, gold) != acc:
		_bad.append("free-for-all: klata panels not the body accent")
	# palettes: saturated, the two sides far apart, colour-blind = blue vs orange
	var seen := {}
	for p in ["classic", "colorblind", "contrast"]:
		st.team_colors = p
		TC.invalidate()
		var b: Color = TC.paint(1)
		var r: Color = TC.paint(2)
		seen[p] = r
		if b.s < 0.7 or r.s < 0.7:
			_bad.append("%s palette not saturated" % p)
		if absf(b.h - r.h) < 0.3 and absf(b.h - r.h) > -0.3:
			_bad.append("%s palette hues too close" % p)
		if not (b.b > b.r and r.r > r.b):
			_bad.append("%s palette: blue / red sides swapped" % p)
	var cb: Color = seen["colorblind"]
	if not (cb.g > 0.45 and cb.h > 0.06 and cb.h < 0.14):
		_bad.append("colour-blind red team is not orange (%s)" % str(cb))
	if seen["colorblind"] == seen["classic"] or seen["contrast"] == seen["classic"]:
		_bad.append("palette setting changes nothing")
	st.team_colors = "colorblind"
	TC.invalidate()
	if TC.red() != Color(0.95, 0.58, 0.1):
		_bad.append("colour-blind UI red is not orange")
	# outlines: enemies stronger than allies
	st.team_colors = "classic"
	TC.invalidate()
	TC.viewer_team = 1
	if not (TC.rim(2).a > TC.rim(1).a and TC.rim(1).a > 0.0):
		_bad.append("enemy outline not stronger than ally (%.2f vs %.2f)" % [TC.rim(2).a, TC.rim(1).a])
	TC.viewer_team = 0
	if TC.rim(0).a != 0.0:
		_bad.append("a team-less soldier has an outline")
	st.team_colors = keep_tc
	st.game_mode = keep_mode
	TC.invalidate()
	_log.append("palettes ok" if _bad.is_empty() else "palettes checked")


const FAKE_MAIN := """
extends Node2D
var player = null
"""
const FAKE_SOLDIER := """
extends Node2D
var team := 1
var dead := false
var display_name := "S"
var aim_dir := Vector2.RIGHT
"""


## Low quality fallback (team-edge material in team modes only) + markers.
func _check_low_and_markers(st) -> void:
	var TC = load("res://scripts/team_colors.gd")
	var keep_q = st.gfx_quality
	var keep_mode = st.game_mode
	var mscr := GDScript.new()
	mscr.source_code = FAKE_MAIN
	mscr.reload()
	var sscr := GDScript.new()
	sscr.source_code = FAKE_SOLDIER
	sscr.reload()
	var main := Node2D.new()
	main.set_script(mscr)
	main.name = "FakeMain"
	root.add_child(main)
	var mk := func(team: int, pos: Vector2, nm: String) -> Node2D:
		var n := Node2D.new()
		n.set_script(sscr)
		n.team = team
		n.display_name = nm
		n.position = pos
		n.add_to_group("soldier")
		main.add_child(n)
		return n
	var me: Node2D = mk.call(1, Vector2(0, 10), "Me")
	var ally: Node2D = mk.call(1, Vector2(600, 10), "Ally")
	var far_enemy: Node2D = mk.call(2, Vector2(0, 700), "FarFoe")
	var aimed: Node2D = mk.call(2, Vector2(900, 10), "Aimed")
	var near_enemy: Node2D = mk.call(2, Vector2(-150, 10), "Near")
	var cloaked: Node2D = mk.call(2, Vector2(120, 10), "Cloaked")
	cloaked.modulate.a = 0.2
	main.player = me
	st.set_gfx_quality(0)
	st.game_mode = st.MODE_CTF
	TC.invalidate()
	var atmo = load("res://scripts/gfx/atmosphere.gd").install(main, {})
	atmo._apply_rim()
	var fl = load("res://scripts/gfx/soldier_flash.gdshader")
	if not (ally.material is ShaderMaterial) or (ally.material as ShaderMaterial).shader != fl:
		_bad.append("Low + team mode: soldiers have no team-edge material")
	st.game_mode = st.MODE_DM
	TC.invalidate()
	atmo._apply_rim()
	if ally.material != null:
		_bad.append("Low + free-for-all: soldiers got a material")
	st.game_mode = st.MODE_CTF
	TC.invalidate()
	var tm = load("res://scripts/gfx/team_markers.gd").new()
	tm.main = main
	main.add_child(tm)
	var got := {}
	for m in tm.collect():
		got[str((m["node"] as Node).get("display_name"))] = m
	if not got.has("Ally") or not bool(got["Ally"]["ally"]) or not bool(got["Ally"]["name"]):
		_bad.append("ally marker / name missing")
	if got.has("Me"):
		_bad.append("marker over the local player")
	if got.has("FarFoe"):
		_bad.append("far, not-aimed enemy got a name")
	if not got.has("Aimed") or not got.has("Near"):
		_bad.append("aimed-at / close enemy has no name (%s)" % str(got.keys()))
	if got.has("Cloaked"):
		_bad.append("cloaked (Predator) enemy revealed by a marker")
	if tm.viewer_team() != 1:
		_bad.append("viewer team %d" % tm.viewer_team())
	st.game_mode = st.MODE_DM
	TC.invalidate()
	if not tm.collect().is_empty():
		_bad.append("markers in a free-for-all mode")
	_log.append("markers %d" % got.size())
	main.queue_free()
	st.set_gfx_quality(keep_q)
	st.game_mode = keep_mode
	TC.invalidate()
	TC.viewer_team = 0


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
	# #306: team-mode soldiers (team paint + outline path), cosmetics on
	out.append({"body_color": B, "team": 1, "weapon_name": "AK-74", "cosmetics": {"finish": "gold", "vest": true, "vfinish": "night"}})
	out.append({"body_color": R, "team": 2, "facing": -1.0, "aim_dir": Vector2.LEFT, "cosmetics": {"head": "kap", "finish": "night"}})
	out.append({"body_color": R, "team": 2, "dead": true})
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
		var rim_mat := ShaderMaterial.new()
		rim_mat.shader = load("res://scripts/gfx/rim_light.gdshader")
		for p in _poses():
			var n := Node2D.new()
			n.set_script(scr)
			if p.has("team"):
				n.material = rim_mat
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
		# #306: team soldiers handed their outline to the material; dead = none
		for idx in [_puppets.size() - 3, _puppets.size() - 2]:
			var rs: Color = _puppets[idx].ds._rim_sent
			if rs.a <= 0.0:
				_bad.append("team puppet %d has no team outline" % idx)
		if (_puppets[_puppets.size() - 1].ds._rim_sent as Color).a > 0.0:
			_bad.append("dead soldier kept its team outline")
		for k in ["kamizelka_acc", "kap_acc", "kap_trim", "morda_acc", "ramie_acc"]:
			if _G._hd_cache.get(k) == null:
				_bad.append("team layer %s never drawn" % k)
		_check_palette(st)
		_check_low_and_markers(st)
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
