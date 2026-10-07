extends SceneTree
## Graphics quality (gate stage F): High / Medium / Low presets switch the
## terrain depth pass, grass, post FX (bloom only on High), ambient motes,
## contact shadows, light glows / smoke / casings — live, mid-match — and
## Low keeps the old Lo-fi flag in step.
##   godot --headless -s tools/gfx_test.gd

var _n := 0
var _st := 0
var _saved := []
var _bad: Array = []
var _log: Array = []
var G = null


func _process(_d: float) -> bool:
	_n += 1
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _st == 0:
		G = load("res://scripts/gfx.gd")
		_saved = [st.bot_count, st.game_mode, st.map_index, st.custom_map_path, st.gfx_quality, st.lofi]
		st.bot_count = 2
		st.game_mode = 0
		st.map_index = 19
		st.custom_map_path = ""
		st.set_gfx_quality(2)
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		_st = 1
		return false
	var m = current_scene
	if m == null or m.get("terrain_fx") == null:
		return false
	match _st:
		1:
			if _n < 40:
				return false
			# High.
			var tf = m.terrain_fx
			_log.append("high edges=%d grass=%d" % [tf.edges_built, tf.grass_blades])
			if tf.edges_built < 50:
				_bad.append("terrain edges %d" % tf.edges_built)
			if tf.grass_blades < 50:
				_bad.append("no grass on Arena2 (High)")
			if tf.get_child_count() != 1:
				_bad.append("terrain fx mesh missing")
			_post(m, true, true)
			if not m.ambient_fx.emitting:
				_bad.append("ambient motes off on High")
			if m.soldier_shadows.drawn < 1:
				_bad.append("no contact shadows")
			_log.append("shadows=%d" % m.soldier_shadows.drawn)
			var g0: int = G.live_glows
			var s0: int = G.live_smoke
			G.explosion(m, m.player.global_position + Vector2(0, 30), 90.0)
			G.casing(m, m.player.global_position, 1.0)
			if G.live_glows <= g0 or G.live_smoke <= s0 or G.live_casings < 1:
				_bad.append("explosion fx: glows %d->%d smoke %d->%d casings %d" % [g0, G.live_glows, s0, G.live_smoke, G.live_casings])
			var lights := 0
			for c in m.get_children():
				if c is PointLight2D:
					lights += 1
			if lights < 1:
				_bad.append("no real light on a High explosion")
			# Caps hold under spam.
			for i in 200:
				G.flash(m, Vector2(100, 100), Color.WHITE, 40.0, 1.0)
				G.smoke(m, Vector2(100, 100), Vector2.ZERO, 10.0, 2.0)
			if G.live_glows > G.MAX_GLOWS or G.live_smoke > G.MAX_SMOKE:
				_bad.append("caps broken: %d glows %d smoke" % [G.live_glows, G.live_smoke])
			# → Medium.
			st.set_gfx_quality(1)
			m.apply_gfx_quality()
			_st = 2
		2:
			var tf = m.terrain_fx
			if tf.get_child_count() > 1:
				return false   # old mesh still freeing
			_log.append("medium edges=%d grass=%d" % [tf.edges_built, tf.grass_blades])
			if tf.edges_built < 50 or tf.grass_blades != 0:
				_bad.append("medium terrain: edges=%d grass=%d (grass is High only)" % [tf.edges_built, tf.grass_blades])
			_post(m, true, false)
			if m.ambient_fx.emitting:
				_bad.append("ambient motes on Medium")
			if st.lofi:
				_bad.append("lofi set on Medium")
			# → Low.
			st.set_gfx_quality(0)
			m.apply_gfx_quality()
			_st = 3
			_n = 0
		3:
			if _n < 3:
				return false
			var tf = m.terrain_fx
			if tf.get_child_count() != 0:
				_bad.append("terrain fx still drawn on Low")
			_post(m, false, false)
			if not st.lofi:
				_bad.append("Low didn't turn Lo-fi on")
			var g0: int = G.live_glows
			G.explosion(m, Vector2(300, 300), 90.0)
			if G.live_glows != g0:
				_bad.append("glow spawned on Low")
			if m.soldier_shadows.drawn != 0:
				_bad.append("shadows on Low")
			# Saved + loaded.
			st.set_gfx_quality(1)
			st.save()
			var cf := ConfigFile.new()
			cf.load("user://settings.cfg")
			if int(cf.get_value("video", "gfx_quality", -1)) != 1:
				_bad.append("gfx_quality not saved")
			return _end()
	return false


func _post(m, vis: bool, bloom: bool) -> void:
	var pf = m.hud.post_fx
	if pf.visible != vis:
		_bad.append("post fx visible=%s (want %s) at q=%d" % [str(pf.visible), str(vis), int(root.get_node("Settings").gfx_quality)])
	var b := float((pf.material as ShaderMaterial).get_shader_parameter("bloom"))
	if vis and (b > 0.0) != bloom:
		_bad.append("bloom=%.2f at q=%d" % [b, int(root.get_node("Settings").gfx_quality)])


func _end() -> bool:
	var st = root.get_node("Settings")
	st.bot_count = _saved[0]; st.game_mode = _saved[1]; st.map_index = _saved[2]; st.custom_map_path = _saved[3]
	st.set_gfx_quality(_saved[4])
	st.save()
	var ok := _bad.is_empty()
	print("GFX-TEST %s %s %s" % ["ok" if ok else "FAIL", str(_bad), " ".join(_log)])
	quit(0 if ok else 1)
	return true
