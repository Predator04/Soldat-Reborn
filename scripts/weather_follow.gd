extends Node
## Small helper for #68 — keeps the weather CPUParticles2D anchored just above
## the active camera. Rides the same Node2D as the emitter; each frame we shove
## the parent Node2D to (cam_x, cam_top_y - band). Doing it here (rather than
## adding a script to the emitter itself) lets the emitter stay a plain node
## whose properties are set from main.gd without a specialized class.

var host_path: NodePath = NodePath("")
var band_w: float = 1600.0


func _process(_delta: float) -> void:
	var host := get_node_or_null(host_path) as Node2D
	if host == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var cam := vp.get_camera_2d()
	if cam == null:
		return
	var view := vp.get_visible_rect().size
	var cam_center := cam.get_screen_center_position()
	# Emit from a band just above the top of the visible viewport so particles
	# fall into view naturally instead of popping into existence mid-screen.
	host.global_position = Vector2(cam_center.x, cam_center.y - view.y * 0.5 - 30.0)
