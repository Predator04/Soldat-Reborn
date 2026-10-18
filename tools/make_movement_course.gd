extends SceneTree
## Writes assets/maps/movement_course.json from scripts/movement_course.gd
## (#262). Re-run after changing the course geometry, then run
## tools/map_audit.py, tools/build_nav.py and tools/make_thumbs.py.
##   godot --headless -s tools/make_movement_course.gd


func _process(_d: float) -> bool:
	var C = load("res://scripts/movement_course.gd")
	var MapIO = load("res://scripts/map_io.gd")
	var path: String = ProjectSettings.globalize_path(C.PATH)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("MAKE-COURSE FAIL can't write %s" % path)
		quit(1)
		return true
	f.store_string(MapIO.map_to_json(C.build()) + "\n")
	f.close()
	print("MAKE-COURSE wrote %s" % path)
	quit()
	return true
