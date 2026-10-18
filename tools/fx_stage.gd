extends SceneTree
## Dev-only staged FX capture (not part of the gate): a scripted fight in
## front of the camera — explosion, gibbings, minigun spray, blood — saved at
## fixed delays, for tuning Phase B effects in a real render.
##   xvfb-run godot --rendering-driver opengl3 --resolution 1280x720 -s tools/fx_stage.gd -- --out=DIR [--map=8] [--zoom=2] [--style=cinematic|classic]
var _out := "."
var _map := 8
var _zoom := 2.0
var _style := "cinematic"
var _n := 0
var _t := -1
var _G = null
var _cam: Camera2D = null
const SHOTS := [4, 10, 24, 33, 40, 50, 100, 260]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): _out = a.substr(6)
		elif a.begins_with("--map="): _map = int(a.substr(6))
		elif a.begins_with("--zoom="): _zoom = float(a.substr(7))
		elif a.begins_with("--style="): _style = a.substr(8)


func _process(_d: float) -> bool:
	_n += 1
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _n == 2:
		_G = load("res://scripts/gfx.gd")
		st.bot_count = 3
		st.game_mode = 0
		st.map_index = _map
		st.custom_map_path = ""
		st.name_set = true
		st.visual_style = _style
		st.set_gfx_quality(2)
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		return false
	var m = current_scene
	if m == null or m.get("player") == null or not is_instance_valid(m.player):
		return false
	if _n < 200:
		return false
	var p: Vector2 = m.player.global_position
	if _cam == null:
		m.player.ceasefire_t = 9999.0
		_cam = Camera2D.new()
		_cam.zoom = Vector2(_zoom, _zoom)
		m.add_child(_cam)
		_cam.global_position = p + Vector2(90, -30)
		_cam.make_current()
		_t = 0
	_t += 1
	if _t == 1:
		# Real deaths through the game's own path (works on older builds too, so
		# the same staging renders a before / after pair): bots are moved in
		# front of the camera and killed — one by a blast, two by bullets.
		_G.explosion(m, p + Vector2(170, -10), 100.0)
		var i := 0
		for b in get_nodes_in_group("soldier"):
			if b == m.player or b.get("loadout") == null or bool(b.get("dead")) or i >= 3:
				continue
			b.global_position = p + Vector2(70 + i * 24, -2)
			b.set("ceasefire_t", 0.0)
			b.take_damage(999.0, "QA", "LAW" if i == 1 else "AK-74", 0)
			i += 1
	if _t <= 120 and _t % 3 == 0:
		var dir := Vector2.RIGHT.rotated(sin(_t * 0.2) * 0.12)
		if Callable(_G, "muzzle").get_argument_count() >= 4:
			_G.muzzle(m, p + Vector2(12, -12), false, dir)
		else:
			_G.muzzle(m, p + Vector2(12, -12), false)
		_G.casing(m, p + Vector2(2, -10), 1.0)
		var FX = load("res://scripts/impact_fx.gd")
		FX.spawn(m, p + Vector2(250, -14) + dir * 30.0, -dir, "wall")
		if _t % 9 == 0:
			FX.spawn(m, p + Vector2(60, -14), -dir, "blood")
	if _t == 30 and m.get_node_or_null("ScreenFeel") != null:
		# Hit-stop + multi-kill slow-mo look (presentation only).
		var SF = load("res://scripts/gfx/screen_feel.gd")
		var f = m.get_node("ScreenFeel")
		SF.local_kill("LAW")
		SF.local_kill("AK-74")
		print("FX-STAGE hit-stops=%d slow-mos=%d" % [f.hitstops, f.slowmos])
	if _t == 32 and m.get_node_or_null("ScreenFeel") != null:
		print("FX-STAGE held frames captured=%d" % m.get_node("ScreenFeel").captured)
	if _t in SHOTS:
		root.get_texture().get_image().save_png("%s/s%03d.png" % [_out, _t])
		if _t == SHOTS[-1]:
			quit()
			return true
	return false
