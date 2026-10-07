extends Node2D
## Soft contact shadows under soldiers and vehicles (gfx.gd Medium+): a ray
## straight down finds the ground; the blob shrinks and fades with height, so
## jumping / jetting soldiers stay anchored to the world. Drawn above the
## terrain, below the soldiers (tree order in Main).

const Gfx := preload("res://scripts/gfx.gd")
const REACH := 150.0
var drawn := 0     # tests: shadows drawn last frame
var _spots: Array = []


func _process(_d: float) -> void:
	_spots.clear()
	if not Gfx.on(Gfx.MEDIUM):
		drawn = 0
		queue_redraw()
		return
	var space := get_world_2d().direct_space_state
	var view := get_viewport().get_visible_rect()
	var cam := get_viewport().get_camera_2d()
	var center: Vector2 = cam.get_screen_center_position() if cam != null else view.size * 0.5
	var half: Vector2 = view.size / (cam.zoom if cam != null else Vector2.ONE) * 0.6
	for grp in ["soldier", "vehicle"]:
		for s in get_tree().get_nodes_in_group(grp):
			if not (s is Node2D) or not (s as CanvasItem).is_visible_in_tree():
				continue
			var p: Vector2 = (s as Node2D).global_position
			if absf(p.x - center.x) > half.x + 60.0 or absf(p.y - center.y) > half.y + 200.0:
				continue
			var veh: bool = grp == "vehicle"
			var q := PhysicsRayQueryParameters2D.create(p + Vector2(0, -4), p + Vector2(0, REACH + (30.0 if veh else 0.0)), 1)
			if s is CollisionObject2D:
				q.exclude = [(s as CollisionObject2D).get_rid()]
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				continue
			var gp: Vector2 = hit.position
			var h := clampf((gp.y - p.y) / REACH, 0.0, 1.0)
			var w := (34.0 if veh else 11.0) * (1.0 - h * 0.55)
			var a := (0.42 if veh else 0.38) * (1.0 - h)
			if s.get("dead") == true:
				a *= 0.6
			_spots.append([gp, w, a])
	drawn = _spots.size()
	queue_redraw()


func _draw() -> void:
	for sp in _spots:
		var gp: Vector2 = sp[0]
		var w: float = sp[1]
		var a: float = sp[2]
		draw_set_transform(gp + Vector2(0, -1), 0.0, Vector2(1.0, 0.28))
		draw_circle(Vector2.ZERO, w, Color(0, 0, 0, a * 0.5))
		draw_circle(Vector2.ZERO, w * 0.66, Color(0, 0, 0, a * 0.6))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
