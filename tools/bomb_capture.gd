extends SceneTree
## Dev capture for Bomb Defusal (#304; not shipped): each Bomb Defusal featured
## level in a bot match, framed on the planted bomb with the HUD up ->
## docs/screenshots/bomb-<slug>.jpg (and a PNG in --out).
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --resolution 1280x720 \
##       --fixed-fps 60 -s tools/bomb_capture.gd -- [--only=slug] [--out=DIR] --no-perf-guard
## The local player is parked beside the bomb (out of the bots' way: no
## physics, out of group "soldier") so its camera frames the site.

var _out := "user://bomb_shots"
var _only := ""
var _levels := ["downtown", "dust_yard", "whiteout"]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): _out = a.substr(6)
		elif a.begins_with("--only="): _only = a.substr(7)
	DirAccess.make_dir_recursive_absolute(_out)
	_run()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	await _frames(2)
	while root.get_node_or_null("Settings") == null:
		await process_frame
	var st = root.get_node("Settings")
	for slug in _levels:
		if _only != "" and slug != _only:
			continue
		st.game_mode = 10
		st.bot_count = 8
		st.custom_map_path = load("res://scripts/featured_levels.gd").local_copy(slug)
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		var n := 0
		while n < 600 and (current_scene == null or current_scene.get("_bomb") == null or current_scene.get("player") == null):
			n += 1
			await process_frame
		var m = current_scene
		var p = m.player
		p.remove_from_group("soldier")
		p.set_physics_process(false)
		p.global_position = Vector2(-600, -600)
		var b = m._bomb
		# Warm up without drawing (stale frames are cheap) until a plant.
		RenderingServer.render_loop_enabled = false
		n = 0
		while b.bomb_state != "planted" and n < 60 * 240:
			n += 1
			await process_frame
		RenderingServer.render_loop_enabled = true
		if b.bomb_state != "planted":
			print("BOMB-CAPTURE %s: no plant" % slug)
			continue
		# Frame the site: stand the (inert) player a little to one side of the bomb.
		var site: Rect2 = b.site_rect(str(b.planted_site))
		var side := -1.0 if b.bomb_pos.x > site.get_center().x else 1.0
		var spot: Vector2 = b._ground_spot(b.bomb_pos + Vector2(side * 140.0, -80.0))
		p.global_position = spot if spot != Vector2.INF else b.bomb_pos + Vector2(side * 140.0, 0)
		p.add_to_group("soldier_hidden")
		p.visible = false
		await _frames(150)
		var img: Image = root.get_texture().get_image()
		img.save_png(_out.path_join("bomb-%s.png" % slug))
		var jpg := ProjectSettings.globalize_path("res://docs/screenshots/bomb-%s.jpg" % slug.replace("_", "-"))
		img.save_jpg(jpg, 0.86)
		print("BOMB-CAPTURE %s -> %s (fuse %.0f)" % [slug, jpg, float(b.fuse_t)])
	quit(0)
