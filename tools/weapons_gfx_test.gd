extends SceneTree
## HD weapon art (#284, gate stage F).
##   godot --headless --fixed-fps 60 -s tools/weapons_gfx_test.gd
## Every weapon sprite (and both belt grenades) has an HD twin in
## assets/weapons-hd/ at exactly 3x the classic size, imported with mipmaps,
## plus a same-size normal map. With the Operator art forced on, the in-hand
## weapon, the back-slung weapon + belt grenade and the dropped pickups each
## draw the HD texture (pickups switch to mipmapped filtering); with it off
## nothing asks for one. The muzzle (muzzle_local, and the barrel end the
## in-hand draw returns) is identical in both looks for every weapon, facing
## and aim, so bullets spawn where they always did. Zero script errors (the
## gate greps the log).

const PUPPET_SRC := """
extends Node2D
var ds
var art
var G
var pose := {}
var draws := 0
var probe := false
var ends := []
func _process(_d):
	queue_redraw()
func _draw():
	ds.weapon_name = ""
	ds.back_weapon_name = ""
	ds.grenade_count = 0
	for k in pose:
		ds.set(k, pose[k])
	art.draw_soldier(self, ds)
	draws += 1
	if probe and ds.weapon_name != "":
		probe = false
		var keep: bool = G.force_operator_for_tests
		var sh: Vector2 = G.joint_pos(self, 16)
		for f in [1.0, -1.0]:
			for a in [Vector2.RIGHT, Vector2(1, -1).normalized(), Vector2.UP, Vector2(-1, 0.4).normalized(), Vector2(0.3, 1).normalized()]:
				var pair := []
				for on in [false, true]:
					G.force_operator_for_tests = on
					pair.append(art._draw_weapon_sprite(self, sh, a, f, ds.weapon_name, Color.WHITE, "bullet"))
				ends.append(pair)
		G.force_operator_for_tests = keep
"""

const AIMS := [Vector2.RIGHT, Vector2(0.7, -0.7), Vector2(0.0, -1.0), Vector2(-0.9, 0.3), Vector2(-0.5, -0.85), Vector2(0.2, 0.98)]

var _n := 0
var _bad: Array = []
var _log: Array = []
var _puppets: Array = []
var _pickups: Array = []
var _G = null
var _art = null
var _wg = null


func _paths() -> Array:
	var out: Array = _art.WEAPON_SPRITE.values()
	out.append(_G.GRENADE_BELT_FRAG)
	out.append(_G.GRENADE_BELT_CLUSTER)
	return out


func _check_assets() -> void:
	var n := 0
	for path in _paths():
		var cl: Texture2D = load(path)
		var hd: Texture2D = _wg.hd_for_path(path)
		var nm: Texture2D = _wg.normal_for_path(path)
		var base := str(path).get_file()
		if hd == null:
			_bad.append("no HD sprite for %s" % base)
			continue
		if hd.get_size() != cl.get_size() * 3:
			_bad.append("%s HD is %s, classic %s x3" % [base, str(hd.get_size()), str(cl.get_size())])
		var img := hd.get_image()
		if img != null and not img.has_mipmaps():
			_bad.append("%s HD imported without mipmaps (mipmaps/generate=true in its .import)" % base)
		if nm == null:
			_bad.append("no normal map for %s" % base)
		elif nm.get_size() != hd.get_size():
			_bad.append("%s normal map is %s, sprite %s" % [base, str(nm.get_size()), str(hd.get_size())])
		n += 1
	_log.append("assets %d" % n)


func _spawn_puppets() -> void:
	var dsc = load("res://scripts/soldier_draw_state.gd")
	var scr := GDScript.new()
	scr.source_code = PUPPET_SRC
	scr.reload()
	var i := 0
	for w in _art.WEAPON_SPRITE.keys():
		var n := Node2D.new()
		n.set_script(scr)
		n.ds = dsc.new()
		n.art = _art
		n.G = _G
		n.position = Vector2(60 * i, 0)
		root.add_child(n)
		_puppets.append(n)
		i += 1


## pose per puppet: "all" = weapon + slung weapon + grenade, "hand", "back"
func _set_poses(kind: String) -> void:
	var names: Array = _art.WEAPON_SPRITE.keys()
	for i in _puppets.size():
		var w: String = names[i]
		var facing := 1.0 if i % 2 == 0 else -1.0
		var p := {"body_color": Color(0.35, 0.55, 1.0), "facing": facing, "aim_dir": Vector2(facing, 0.0)}
		if kind != "back":
			p["weapon_name"] = w
		if kind != "hand":
			p["back_weapon_name"] = w if kind == "back" else names[(i + 3) % names.size()]
			p["grenade_count"] = 2
			p["use_cluster"] = i % 2 == 1
		_puppets[i].pose = p


func _cache_has_all(paths: Array, what: String) -> void:
	var miss := []
	for p in paths:
		if _wg._cache.get(p) == null:
			miss.append(str(p).get_file())
	if not miss.is_empty():
		_bad.append("%s never drew the HD sprite of %s" % [what, ", ".join(miss)])


func _check_muzzles() -> void:
	var cnt := 0
	for i in _puppets.size():
		var p: Node2D = _puppets[i]
		var w: String = p.pose.get("weapon_name", "")
		for f in [1.0, -1.0]:
			for a in AIMS:
				var aim: Vector2 = (a as Vector2).normalized()
				_G.force_operator_for_tests = false
				var m0: Vector2 = _art.muzzle_local(p, aim, f, w)
				_G.force_operator_for_tests = true
				var m1: Vector2 = _art.muzzle_local(p, aim, f, w)
				if m0 != m1:
					_bad.append("%s muzzle moved %s -> %s (facing %d aim %s)" % [w, str(m0), str(m1), int(f), str(aim)])
				cnt += 1
		if p.ends.is_empty():
			_bad.append("%s barrel-end probe never ran" % w)
		for pair in p.ends:
			if pair[0] != pair[1]:
				_bad.append("%s barrel end moved %s -> %s" % [w, str(pair[0]), str(pair[1])])
			cnt += 1
	_G.force_operator_for_tests = true
	_log.append("muzzles %d identical" % cnt)


func _process(_d: float) -> bool:
	_n += 1
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	match _n:
		2:
			_G = load("res://scripts/gostek.gd")
			_art = load("res://scripts/soldier_art.gd")
			_wg = load("res://scripts/weapon_gfx.gd")
			_check_assets()
			# classic look: no one asks for an HD weapon
			_G.force_operator_for_tests = false
			if _G.operator_on():
				_bad.append("operator_on() true in a headless run")
			_wg._cache.clear()
			_spawn_puppets()
			_set_poses("all")
		20:
			if not _wg._cache.is_empty():
				_bad.append("classic look looked up HD sprites: %s" % str(_wg._cache.keys()))
			_G.force_operator_for_tests = true
			_wg._cache.clear()
			_set_poses("hand")
		30:
			for p in _puppets:
				p.probe = true
		40:
			_cache_has_all(_art.WEAPON_SPRITE.values(), "in-hand weapon")
			_check_muzzles()
			_wg._cache.clear()
			_set_poses("back")
		60:
			_cache_has_all(_art.WEAPON_SPRITE.values() + [_G.GRENADE_BELT_FRAG, _G.GRENADE_BELT_CLUSTER], "back weapon / belt grenade")
			for p in _puppets:
				if p.texture_filter != CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
					_bad.append("soldier node not on mipmapped filtering")
					break
				p.pose = {"body_color": Color(0.85, 0.3, 0.25)}
			_wg._cache.clear()
			var pk = load("res://scripts/weapon_pickup.gd")
			var i := 0
			for w in _art.WEAPON_SPRITE.keys():
				var b := RigidBody2D.new()
				b.set_script(pk)
				b.weapon_name = w
				b.persistent = true
				b.freeze = true
				b.gravity_scale = 0.0
				b.position = Vector2(60 * i, 300)
				root.add_child(b)
				_pickups.append(b)
				i += 1
		80:
			_cache_has_all(_art.WEAPON_SPRITE.values(), "weapon pickup")
			for b in _pickups:
				if b.texture_filter != CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
					_bad.append("pickup %s not on mipmapped filtering" % b.weapon_name)
			for p in _puppets:
				if int(p.draws) < 30:
					_bad.append("puppet drew only %d times" % int(p.draws))
					break
			_G.force_operator_for_tests = false
			_log.append("drawn in hand / back / pickup x%d" % _puppets.size())
			var ok := _bad.is_empty()
			print("WEAPONS-ART-TEST %s %s%s" % ["ok" if ok else "FAIL", " | ".join(_log), "" if ok else " | " + "; ".join(_bad)])
			quit(0 if ok else 1)
	return false
