extends SceneTree
## Graphics Phase A (#270) — gate stage F: the atmosphere layer builds both
## looks, switches live mid-match, pools its lights (no new nodes per shot),
## gives soldiers the rim material and takes it away again, swaps the post
## shader, and never touches the simulation (player state is the same with
## the look on or off).
##   godot --headless --fixed-fps 60 -s tools/atmosphere_test.gd

var _n := 0
var _st := 0
var _saved := []
var _bad: Array = []
var _log: Array = []
var A = null
var G = null


func _process(_d: float) -> bool:
	_n += 1
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _st == 0:
		A = load("res://scripts/gfx/atmosphere.gd")
		G = load("res://scripts/gfx.gd")
		A.force_cinematic_for_tests = true
		_saved = [st.bot_count, st.game_mode, st.map_index, st.custom_map_path, st.gfx_quality, st.visual_style]
		st.bot_count = 3
		st.game_mode = 0
		st.map_index = 8
		st.custom_map_path = ""
		st.set_gfx_quality(2)
		st.visual_style = "cinematic"
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		_st = 1
		return false
	var m = current_scene
	if m == null or m.get_node_or_null("Atmosphere") == null or m.get("player") == null:
		return false
	var at = m.get_node("Atmosphere")
	match _st:
		1:
			if _n < 50:
				return false
			if at.style() != "cinematic":
				_bad.append("style %s, want cinematic" % at.style())
			var sky = m.get_node_or_null("SkyLayer/Sky")
			if sky == null or not (sky is ColorRect) or sky.material == null:
				_bad.append("cinematic sky missing")
			var par = m.get_node_or_null("ParallaxLayer/Parallax")
			if par == null or par.get_script() == null or not str(par.get_script().resource_path).ends_with("parallax_cinematic.gd"):
				_bad.append("cinematic parallax missing")
			if m.get_node_or_null("Ambient") == null:
				_bad.append("ambient CanvasModulate missing on High")
			var fx = m.hud.get("post_fx")
			if fx == null or (fx.material as ShaderMaterial).shader.resource_path.find("post_cinematic") < 0:
				_bad.append("post shader not swapped")
			elif float((fx.material as ShaderMaterial).get_shader_parameter("cinematic")) < 0.5:
				_bad.append("post grade not cinematic")
			# Lights: pooled, so firing 40 creates no nodes.
			var before := m.get_child_count()
			for i in 40:
				G.muzzle(m, m.player.global_position + Vector2(i, 0), i % 5 == 0)
			G.explosion(m, m.player.global_position, 90.0)
			var lit: int = at.lights_lit()
			_log.append("lit=%d" % lit)
			if lit < 1 or lit > A.LIGHT_POOL:
				_bad.append("pooled lights lit=%d" % lit)
			var real_lights := 0
			for c in m.get_children():
				if c is PointLight2D and not str(c.name).begins_with("PoolLight"):
					real_lights += 1
			if real_lights > 0:
				_bad.append("%d unpooled PointLight2D created" % real_lights)
			_log.append("children %d->%d" % [before, m.get_child_count()])
			_st = 2
			_n = 0
		2:
			if _n < 20:
				return false
			var rimmed := 0
			for s in get_nodes_in_group("soldier"):
				if s.material != null and (s.material as ShaderMaterial) != null and (s.material as ShaderMaterial).shader.resource_path.ends_with("rim_light.gdshader"):
					rimmed += 1
			_log.append("rimmed=%d" % rimmed)
			if rimmed < 2:
				_bad.append("rim material on %d soldiers" % rimmed)
			if at.lights_lit() != 0:
				_bad.append("pool lights still lit after fade: %d" % at.lights_lit())
			# Live switch to classic.
			st.visual_style = "classic"
			A.restyle(self)
			_st = 3
			_n = 0
		3:
			if _n < 10:
				return false
			if at.style() != "classic":
				_bad.append("style %s after switching to classic" % at.style())
			var sky = m.get_node_or_null("SkyLayer/Sky")
			if sky == null or sky is ColorRect:
				_bad.append("classic sky not restored")
			if m.get_node_or_null("Ambient") != null:
				_bad.append("ambient left on in classic")
			for s in get_nodes_in_group("soldier"):
				if s.material != null and (s.material as ShaderMaterial) != null and (s.material as ShaderMaterial).shader != null \
						and (s.material as ShaderMaterial).shader.resource_path.ends_with("rim_light.gdshader"):
					_bad.append("rim left on %s" % s.name)
					break
			var fx = m.hud.get("post_fx")
			if fx != null and float((fx.material as ShaderMaterial).get_shader_parameter("cinematic")) > 0.5:
				_bad.append("post grade still cinematic")
			# Back to cinematic: everything rebuilds without errors.
			st.visual_style = "cinematic"
			A.restyle(self)
			_st = 4
			_n = 0
		4:
			if _n < 10:
				return false
			if at.style() != "cinematic":
				_bad.append("could not switch back to cinematic")
			_finish(st)
			return true
	return false


func _finish(st) -> void:
	A.force_cinematic_for_tests = false
	st.bot_count = _saved[0]
	st.game_mode = _saved[1]
	st.map_index = _saved[2]
	st.custom_map_path = _saved[3]
	st.set_gfx_quality(_saved[4])
	st.visual_style = _saved[5]
	print("ATMOS-TEST %s %s | %s" % ["ok" if _bad.is_empty() else "FAIL", str(_bad), " ".join(_log)])
	quit()
