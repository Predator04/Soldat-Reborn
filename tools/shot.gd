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
var _flagdemo := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="):
			_frames = int(a.substr(9))
		elif a.begins_with("--out="):
			_out = a.substr(6)
		elif a == "--flagdemo":
			_flagdemo = true
		elif a.begins_with("--at="):
			var xy := a.substr(5).split(",")
			_at = Vector2(float(xy[0]), float(xy[1]))
	change_scene_to_file("res://scenes/main.tscn")


func _process(_delta: float) -> bool:
	_n += 1
	if _at != Vector2.INF and not _moved and _n > 5 and current_scene != null:
		var p = current_scene.get("player")
		if p != null and is_instance_valid(p):
			p.global_position = _at
			var cam: Camera2D = p.get("cam")
			if cam != null:
				cam.reset_smoothing()
			_moved = true
			if _flagdemo:
				# Put the RED flag on the player's back and drop the BLUE one
				# next to them so all three flag looks are in one frame.
				var fl: Array = current_scene.get("flags")
				if fl.size() >= 2:
					fl[1].set_meta("carrier", p)
					fl[0].position = _at + Vector2(-90, 0)
	if _n == _frames:
		var img := root.get_texture().get_image()
		img.save_png(_out)
		print("saved ", _out)
		quit()
	return false
