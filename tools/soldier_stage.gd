extends SceneTree
## Dev-only soldier lineup (#280, not part of the gate): draws soldiers in
## every pose and look through the real SoldierArt.draw_soldier path, on a
## studio backdrop, at close-up and at true 1x scale, and saves PNGs so the
## same run gives before / after pairs on an older build.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --resolution 1280x720 \
##     -s tools/soldier_stage.gd -- --out=DIR [--zoom=4] [--tag=after] [--style=classic|cinematic] [--bg=dark|day|night] [--look=classic|operator] [--debug]
## --weapons (#284): every weapon in hand (4 x 4 grid, each soldier also has a
## slung weapon + belt grenade) and every weapon as a dropped pickup, saved one
## row per shot as weapons_<tag>_r<N>.png / pickups_<tag>_r<N>.png.
## --classic-weapons: Operator soldiers holding the classic weapon sprites
## (before / after pairs of the weapon art alone). --skins: cycle the weapon skins.
var _out := "."
var _tag := "shot"
var _zoom := 4.0
var _style := "cinematic"
var _bg := "dark"
var _n := 0
var _puppets: Array = []
var _debug := false
var _look := ""
var _bench := false   # --bench: 36 soldiers, print frame time
var _weapons := false # --weapons: weapon lineup (#284)
var _shots: Array = []  # [camera pos, file name] for --weapons
var _classic_weapons := false
var _skins := false
var _t0 := 0

const PUPPET_SRC := """
extends Node2D
var ds
var art
var pose := {}
func _process(_d):
	queue_redraw()
var debug := false
func _draw():
	for k in pose:
		ds.set(k, pose[k])
	art.draw_soldier(self, ds)
	if debug:
		_dbg()
func _dbg():
	var G = load("res://scripts/gostek.gd")
	var st = G._states.get(get_instance_id(), {})
	var frame = st.get("frame", PackedVector2Array())
	var flip = ds.facing < 0.0
	var i = 0
	var cols = [Color.RED, Color.YELLOW, Color.CYAN, Color.MAGENTA, Color.GREEN, Color.ORANGE, Color.WHITE]
	for spec in G.PARTS:
		var key = spec[0]
		i += 1
		if key.begins_with("<"):
			continue
		var p1 = G._joint_local(frame, spec[1], flip)
		var p2 = G._joint_local(frame, spec[2], flip)
		if not p1.is_finite() or not p2.is_finite():
			continue
		var bone = p2 - p1
		var tex = G._tex(key, flip)
		var cy = spec[4]
		if flip and tex != null:
			cy = 1.0 - cy
		if tex == null:
			tex = G._tex(key, false)
		var w = tex.get_width() / 3.0
		var h = tex.get_height() / 3.0
		var sx = 1.0
		if spec[5] > 0.0:
			sx = minf(1.5, bone.length() / spec[5])
		var c = cols[i % cols.size()]
		draw_set_transform(p1, bone.angle(), Vector2(sx, 1.0))
		draw_rect(Rect2(-spec[3] * w, -cy * h, w, h), c, false, 0.15)
		draw_line(Vector2(-spec[3] * w, -cy * h), Vector2(-spec[3] * w + 2.0, -cy * h), c, 0.4)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_string(ThemeDB.fallback_font, (p1 + p2) * 0.5 + Vector2(8 + (i % 3) * 7, -2 + (i % 4) * 1.5), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 3, c)
"""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): _out = a.substr(6)
		elif a.begins_with("--tag="): _tag = a.substr(6)
		elif a.begins_with("--zoom="): _zoom = float(a.substr(7))
		elif a.begins_with("--style="): _style = a.substr(8)
		elif a.begins_with("--bg="): _bg = a.substr(5)
		elif a == "--debug": _debug = true
		elif a.begins_with("--look="): _look = a.substr(7)
		elif a == "--bench": _bench = true
		elif a == "--weapons": _weapons = true
		elif a == "--classic-weapons": _classic_weapons = true
		elif a == "--skins": _skins = true


func _blue() -> Color:
	return Color(0.35, 0.55, 1.0)


func _red() -> Color:
	return Color(0.85, 0.3, 0.25)


func _poses() -> Array:
	var B := _blue()
	var R := _red()
	var aim := Vector2.RIGHT
	return [
		{"body_color": B, "weapon_name": "AK-74", "grenade_count": 2, "back_weapon_name": "USSOCOM"},
		{"body_color": B, "weapon_name": "MP5", "vel": Vector2(215, 0)},
		{"body_color": R, "weapon_name": "Minimi", "facing": -1.0, "aim_dir": Vector2.LEFT, "vel": Vector2(-215, 0)},
		{"body_color": R, "weapon_name": "Barrett", "facing": -1.0, "aim_dir": Vector2(-0.94, -0.34), "crouching": true},
		{"body_color": B, "weapon_name": "LAW", "jet_on": true, "on_floor": false, "vel": Vector2(80, -200), "aim_dir": Vector2(0.8, -0.6)},
		{"body_color": R, "weapon_name": "Spas-12", "facing": -1.0, "aim_dir": Vector2.LEFT, "health": 35.0,
			"cosmetics": {"head": "kap", "vest": true, "vfinish": "night", "pants": "black", "chain": "gold", "cigar": true}},
		{"body_color": B, "weapon_name": "Deagles", "cosmetics": {"head": "hair2", "skin": "brown", "pants": "desert", "dogtag": true, "finish": "desert"}},
		{"body_color": R, "weapon_name": "Flamethrower", "prone": true, "facing": -1.0, "aim_dir": Vector2.LEFT},
		{"body_color": B, "weapon_name": "Minigun", "dead": true},
	]


func _process(_d: float) -> bool:
	_n += 1
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _n == 2:
		_build(st)
		return false
	if _weapons:
		return _weapon_shots()
	if _bench:
		if _n == 60:
			_t0 = Time.get_ticks_usec()
		if _n == 360:
			print("SSTAGE bench look=%s %.2f ms/frame" % [_look, float(Time.get_ticks_usec() - _t0) / 300000.0])
			quit(0)
		return false
	if _n == 40:
		root.get_texture().get_image().save_png("%s/soldiers_%s.png" % [_out, _tag])
		print("SSTAGE saved soldiers_%s" % _tag)
	if _n == 41:
		# True 1x scale (what a 1280x720 screen shows), centred.
		var cam: Camera2D = root.get_node("Stage/Cam")
		cam.zoom = Vector2.ONE * 1.0
	if _n == 60:
		var img := root.get_texture().get_image()
		img = img.get_region(Rect2i(390, 280, 500, 160))
		img.resize(img.get_width() * 2, img.get_height() * 2, Image.INTERPOLATE_NEAREST)
		img.save_png("%s/soldiers1x_%s.png" % [_out, _tag])
		print("SSTAGE saved soldiers1x_%s" % _tag)
		quit(0)
	return false


func _build(st) -> void:
	if st.get("visual_style") != null:
		st.visual_style = _style
	if _look != "":
		st.soldier_look = _look
	var stage := Node2D.new()
	stage.name = "Stage"
	root.add_child(stage)
	var bg := ColorRect.new()
	bg.size = Vector2(4000, 2000)
	bg.position = Vector2(-2000, -1000)
	var top := Color(0.13, 0.15, 0.19)
	var bot := Color(0.05, 0.06, 0.08)
	if _bg == "day":
		top = Color(0.55, 0.68, 0.8); bot = Color(0.78, 0.74, 0.62)
	elif _bg == "night":
		top = Color(0.03, 0.04, 0.09); bot = Color(0.08, 0.07, 0.1)
	var g := Gradient.new()
	g.set_color(0, top)
	g.set_color(1, bot)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.size = bg.size
	tr.position = bg.position
	stage.add_child(tr)
	var floor_line := Line2D.new()
	floor_line.points = PackedVector2Array([Vector2(-2000, 20.5), Vector2(2000, 20.5)])
	floor_line.width = 1.0
	floor_line.default_color = Color(0.4, 0.42, 0.45, 0.6) if _bg != "day" else Color(0.3, 0.26, 0.2)
	stage.add_child(floor_line)
	var art = load("res://scripts/soldier_art.gd")
	var dsc = load("res://scripts/soldier_draw_state.gd")
	var scr := GDScript.new()
	scr.source_code = PUPPET_SRC
	scr.reload()
	var rim = null
	if _style == "cinematic":
		rim = ShaderMaterial.new()
		rim.shader = load("res://scripts/gfx/rim_light.gdshader")
		rim.set_shader_parameter("rim_strength", 0.5)
	if _weapons:
		_build_weapons(stage, scr, art, dsc, rim)
		var wcam := Camera2D.new()
		wcam.name = "Cam"
		wcam.zoom = Vector2.ONE * _zoom
		stage.add_child(wcam)
		wcam.make_current()
		return
	var poses := _poses()
	if _debug:
		poses = [poses[0], poses[2]]
	if _bench:
		var many := []
		for k in 4:
			many.append_array(poses)
		poses = many
	var gap := 34.0 if not _debug else 60.0
	for i in poses.size():
		var p := Node2D.new()
		p.set_script(scr)
		p.ds = dsc.new()
		p.art = art
		p.pose = poses[i]
		p.debug = _debug
		p.position = Vector2((i - (poses.size() - 1) * 0.5) * gap, 0)
		if rim != null:
			p.material = rim
		p.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		p.add_to_group("soldier_stage")
		stage.add_child(p)
		_puppets.append(p)
	var cam := Camera2D.new()
	cam.name = "Cam"
	cam.zoom = Vector2.ONE * _zoom
	cam.position = Vector2(0, -6)
	stage.add_child(cam)
	cam.make_current()


const WEAPON_GAP := Vector2(44, 62)


func _weapon_poses() -> Array:
	var names: Array = load("res://scripts/soldier_art.gd").WEAPON_SPRITE.keys()
	var skins: Array = [""] + load("res://scripts/customization.gd").WEAPON_SKINS.keys()
	var out := []
	for i in names.size():
		out.append({"body_color": _blue() if i % 2 == 0 else _red(), "weapon_name": names[i],
			"back_weapon_name": names[(i + 5) % names.size()], "grenade_count": 2, "use_cluster": i % 4 >= 2,
			"cosmetics": {"wskin": skins[i % skins.size()] if _skins else ""}})
	return out


func _weapon_shots() -> bool:
	# one shot every 10 frames once everything has settled
	var k := (_n - 40) / 10
	if _n >= 40 and (_n - 40) % 10 == 0 and k <= _shots.size():
		if k > 0:
			var img := root.get_texture().get_image()
			img.save_png("%s/%s" % [_out, _shots[k - 1][1]])
			print("SSTAGE saved %s" % _shots[k - 1][1])
		if k == _shots.size():
			quit(0)
			return false
		var cam: Camera2D = root.get_node("Stage/Cam")
		cam.position = _shots[k][0]
	return false


func _build_weapons(stage: Node2D, scr: GDScript, art, dsc, rim) -> void:
	if _classic_weapons:
		# a cached null makes WeaponGfx fall back to the classic sprite
		var wg = load("res://scripts/weapon_gfx.gd")
		for path in art.WEAPON_SPRITE.values():
			wg._cache[path] = null
		var G = load("res://scripts/gostek.gd")
		wg._cache[G.GRENADE_BELT_FRAG] = null
		wg._cache[G.GRENADE_BELT_CLUSTER] = null
	var poses := _weapon_poses()
	for i in poses.size():
		var p := Node2D.new()
		p.set_script(scr)
		p.ds = dsc.new()
		p.art = art
		p.pose = poses[i]
		p.position = Vector2((i % 4 - 1.5) * WEAPON_GAP.x, int(i / 4) * WEAPON_GAP.y)
		if rim != null:
			p.material = rim
		p.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		stage.add_child(p)
		_puppets.append(p)
	var rows := int(ceil(poses.size() / 4.0))
	for r in rows:
		_shots.append([Vector2(0, r * WEAPON_GAP.y - 6), "weapons_%s_r%d.png" % [_tag, r]])
	# dropped pickups: frozen props, same 4-wide grid further down
	var pk := load("res://scripts/weapon_pickup.gd")
	var y0 := rows * WEAPON_GAP.y + 400.0
	for i in poses.size():
		var b := RigidBody2D.new()
		b.set_script(pk)
		b.weapon_name = poses[i]["weapon_name"]
		b.persistent = true
		b.freeze = true
		b.gravity_scale = 0.0
		b.position = Vector2((i % 4 - 1.5) * WEAPON_GAP.x, y0 + int(i / 4) * 40.0)
		stage.add_child(b)
		for c in b.get_children():
			if c is CanvasItem:
				c.visible = false   # name tags would cover the close-up
	for r in rows:
		_shots.append([Vector2(0, y0 + r * 40.0), "pickups_%s_r%d.png" % [_tag, r]])
