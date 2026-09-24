extends Node2D
## Spectator — follow-cam + free-cam while the local player is dead (#75).
## Owned by Main so it survives the player node's queue_free() on death.
## Left/Right cycles targets; C toggles free-cam (arrow keys pan, clamped
## to map bounds). Deactivated on respawn — the fresh player camera takes over.

var main: Node2D
var cam: Camera2D
var _target: Node2D = null
var _free_cam := false
var _active := false

const PAN_SPEED := 900.0
const MAP_W := 4800.0   # fallback only — real bounds come from main (per-map world)
const MAP_H := 2000.0


func _world_w() -> float:
	return float(main.get("MAP_W")) if main != null and main.get("MAP_W") != null else MAP_W


func _world_h() -> float:
	return float(main.get("MAP_H")) if main != null and main.get("MAP_H") != null else MAP_H


func _ready() -> void:
	cam = Camera2D.new()
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	cam.zoom = Vector2(1.0, 1.0)
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(_world_w())
	cam.limit_bottom = int(_world_h())
	cam.enabled = false
	add_child(cam)
	set_process(false)
	set_process_unhandled_input(false)


func activate(anchor: Vector2 = Vector2.ZERO) -> void:
	if _active:
		return
	_active = true
	_free_cam = false
	if anchor != Vector2.ZERO:
		global_position = anchor
	_target = _pick_nearest_target(global_position)
	if _target != null:
		global_position = _target.global_position
	cam.enabled = true
	cam.make_current()
	set_process(true)
	set_process_unhandled_input(true)
	_notify_hud()


func deactivate() -> void:
	if not _active:
		return
	_active = false
	cam.enabled = false
	_target = null
	set_process(false)
	set_process_unhandled_input(false)
	if main != null and main.get("hud") != null and main.hud.has_method("set_spectate_target"):
		main.hud.set_spectate_target("", Color(1, 1, 1))


func is_active() -> bool:
	return _active


func _process(delta: float) -> void:
	if not _active:
		return
	if _free_cam:
		var dir := Vector2.ZERO
		if Input.is_key_pressed(KEY_LEFT):
			dir.x -= 1.0
		if Input.is_key_pressed(KEY_RIGHT):
			dir.x += 1.0
		if Input.is_key_pressed(KEY_UP):
			dir.y -= 1.0
		if Input.is_key_pressed(KEY_DOWN):
			dir.y += 1.0
		if dir != Vector2.ZERO:
			var next := global_position + dir * PAN_SPEED * delta
			next.x = clampf(next.x, 0.0, _world_w())
			next.y = clampf(next.y, 0.0, _world_h())
			global_position = next
		return
	if not is_instance_valid(_target) or bool(_target.get("dead")):
		_target = _pick_nearest_target(global_position)
		_notify_hud()
	if _target != null:
		global_position = _target.global_position


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var kc: int = (event as InputEventKey).keycode
	if kc == KEY_C:
		_free_cam = not _free_cam
		_notify_hud()
		get_viewport().set_input_as_handled()
	elif not _free_cam and kc == KEY_LEFT:
		_cycle_target(-1)
		get_viewport().set_input_as_handled()
	elif not _free_cam and kc == KEY_RIGHT:
		_cycle_target(1)
		get_viewport().set_input_as_handled()


func _living_targets() -> Array:
	var arr: Array = []
	for s in get_tree().get_nodes_in_group("soldier"):
		if is_instance_valid(s) and not bool(s.get("dead")):
			arr.append(s)
	arr.sort_custom(func(a, b) -> bool: return int(a.get_instance_id()) < int(b.get_instance_id()))
	return arr


func _pick_nearest_target(origin: Vector2) -> Node2D:
	var arr := _living_targets()
	if arr.is_empty():
		return null
	var best: Node2D = arr[0]
	var best_d: float = INF
	for s in arr:
		var d: float = origin.distance_to((s as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = s
	return best


func _cycle_target(step: int) -> void:
	var arr := _living_targets()
	if arr.is_empty():
		_target = null
		_notify_hud()
		return
	var idx: int = 0
	if is_instance_valid(_target):
		var found: int = arr.find(_target)
		if found >= 0:
			idx = (found + step) % arr.size()
			if idx < 0:
				idx += arr.size()
	_target = arr[idx]
	_notify_hud()


func _notify_hud() -> void:
	if main == null or main.get("hud") == null:
		return
	if not main.hud.has_method("set_spectate_target"):
		return
	if _free_cam:
		main.hud.set_spectate_target("Free Cam  (C to follow · arrows to pan)", Color(0.85, 0.9, 1.0))
	elif is_instance_valid(_target):
		var col: Color = _target.get("color") if _target.get("color") != null else Color(1, 1, 1)
		main.hud.set_spectate_target(str(_target.get("display_name")), col)
	else:
		main.hud.set_spectate_target("No targets alive", Color(0.7, 0.7, 0.7))
