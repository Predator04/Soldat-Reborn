extends SceneTree
## Dev screenshot helper (not shipped in exports — lives under tools/).
##   godot --path game -s tools/shot.gd --map=N --mode=M -- --out=/tmp/x.png [--frames=90] [--at=x,y]
## Boots main.tscn on map N, waits, optionally teleports the camera/player to
## (x,y), then saves the viewport to --out.

var _frames := 90
var _out := "user://shot.png"
var _at := Vector2.INF
var _n := 0
var _moved := false
var _at_frame := 5
var _flagdemo := false
var _flagdrop := false
var _scene := "res://scenes/main.tscn"
var _sb := false
var _nohud := false
var _gesture := ""
var _call := ""
var _menu_map := ""
var _vis := ""   # --show=NodeVar: make current_scene.<var> visible, hide _menu_root


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="):
			_frames = int(a.substr(9))
		elif a.begins_with("--at-frame="):
			_at_frame = int(a.substr(11))
		elif a.begins_with("--out="):
			_out = a.substr(6)
		elif a == "--flagdemo":
			_flagdemo = true
		elif a == "--flagdrop":
			_flagdrop = true
		elif a.begins_with("--scene="):
			_scene = a.substr(8)
		elif a.begins_with("--menu-map="):
			_menu_map = a.substr(11)
		elif a.begins_with("--call="):
			_call = a.substr(7)
		elif a.begins_with("--gesture="):
			_gesture = a.substr(10)
		elif a == "--nohud":
			_nohud = true
		elif a == "--scoreboard":
			_sb = true
		elif a.begins_with("--show="):
			_vis = a.substr(7)
		elif a.begins_with("--at="):
			var xy := a.substr(5).split(",")
			_at = Vector2(float(xy[0]), float(xy[1]))
	change_scene_to_file(_scene)


func _process(_delta: float) -> bool:
	_n += 1
	if _n == 1 and root.get_node_or_null("Settings") != null:
		# Software-rendered captures run slowly; keep the low-FPS guard from
		# flipping Lo-fi on in this machine's settings.
		root.get_node("Settings").set("lofi_auto_done", true)
	if _at != Vector2.INF and _moved and _n < _at_frame + 200 and current_scene != null:
		# The first body can be replaced (limbo pick / respawn): keep putting
		# the player back for a while.
		var p2 = current_scene.get("player")
		if p2 != null and is_instance_valid(p2) and p2.global_position.distance_to(_at) > 400.0:
			_moved = false
	if _at != Vector2.INF and not _moved and _n > _at_frame and current_scene != null:
		var p = current_scene.get("player")
		if p != null and is_instance_valid(p):
			p.global_position = _at
			var cam: Camera2D = p.get("cam")
			if cam != null:
				cam.reset_smoothing()
			_moved = true
			var fl: Array = current_scene.get("flags")
			if _flagdemo and fl.size() >= 2:
				# RED flag on the player's back (BLUE stays at its home).
				fl[1].set_meta("carrier", p)
			if _flagdrop and fl.size() >= 2:
				# RED flag lying in the field next to the player.
				fl[1].position = current_scene._settle_on_ground(_at + Vector2(90, -20))
	if _vis != "" and _n == 10 and current_scene != null:
		var mr = current_scene.get("_menu_root")
		if mr != null:
			mr.visible = false
		var panel = current_scene.get(_vis)
		if panel != null:
			panel.visible = true
	if _menu_map != "" and _n == 12 and current_scene != null and current_scene.get("_sp_map_pick") != null:
		var pk = current_scene._sp_map_pick
		for i in pk.item_count:
			if pk.get_item_text(i) == "Map: " + _menu_map:
				pk.select(i)
				current_scene._on_sp_map_selected(i)
	if _gesture != "" and _n == 14 and current_scene != null and current_scene.get("player") != null:
		current_scene.player.apply_gesture(_gesture)
	if _call != "" and _n == 14 and current_scene != null:
		# --call=method on the scene root, or --call=Child/Path:method
		var tgt: Node = current_scene
		var meth := _call
		if ":" in _call:
			tgt = current_scene.get_node_or_null(_call.get_slice(":", 0))
			meth = _call.get_slice(":", 1)
		if tgt != null and tgt.has_method(meth):
			tgt.call(meth)
	if _sb and current_scene != null and current_scene.get("hud") != null:
		var sbn = current_scene.hud.get("scoreboard")
		if sbn != null:
			sbn.peek(5.0)
	if _nohud and current_scene != null:
		var h = current_scene.get("hud")
		if h != null and is_instance_valid(h):
			h.visible = false
		var pl = current_scene.get("player")
		if pl != null and is_instance_valid(pl):
			pl.set("visible", true)
	if _n == _frames:
		var img := root.get_texture().get_image()
		img.save_png(_out)
		print("saved ", _out)
		quit()
	return false
