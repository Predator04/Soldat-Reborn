extends Node2D
## M2 stationary gun — per-map mount points. A soldier walks onto one, presses
## F to mount, aims with the mouse (clamped elevation), fires with LMB, and
## dismounts by tapping any WASD/Space direction key.
##
## Stats — Soldat weapons.ini M2: Dmg 1.8, Ammo 100, RT 366, Spd 36, Style 14.
## Translated to our units: high-DPS bullet spitter with a shallow spread cone.

const RATE := 0.055           # ~18 rps (Soldat's FI feels near-Minigun)
const DAMAGE := 18.0
const SPEED := 1450.0
const SPREAD := 0.03
const MOUNT_RADIUS := 32.0
const AIM_MAX_ELEV := 0.85    # ~48° above horizontal
const AIM_MAX_DEPRESS := 0.35 # small down-angle only (barrel below the sandbag)

var team := -1
var operator: Node2D = null
var fire_cd := 0.0
var aim_dir := Vector2.RIGHT
var _bullet_scene := preload("res://scenes/bullet.tscn")
# Stable id — Main assigns on spawn so RPCs can address a specific mount.
var m2_id: int = -1


func _ready() -> void:
	add_to_group("m2_gun")
	z_index = 1


func mount(pl: Node2D) -> void:
	if not is_instance_valid(pl):
		return
	if operator != null:
		return
	# In MP: route the mount through Main so every peer applies it as authority.
	# The local player who pressed F asks the host to arbitrate.
	if Net.is_networked():
		var peer_id: int = int(pl.get_multiplayer_authority())
		var main := get_parent()
		if main != null and main.has_method("net_m2_mount"):
			if Net.is_host():
				main.rpc("net_m2_mount", m2_id, peer_id)
			else:
				main.rpc_id(1, "net_m2_mount", m2_id, peer_id)
		return
	net_mount(pl)


func dismount() -> void:
	if Net.is_networked():
		var main := get_parent()
		if main != null and main.has_method("net_m2_dismount"):
			if Net.is_host():
				main.rpc("net_m2_dismount", m2_id)
			else:
				main.rpc_id(1, "net_m2_dismount", m2_id)
		return
	net_dismount()


func net_mount(pl: Node2D) -> void:
	if not is_instance_valid(pl) or operator != null:
		return
	operator = pl
	if pl.has_method("mount_m2"):
		pl.mount_m2(self)


func net_dismount() -> void:
	if is_instance_valid(operator) and operator.has_method("dismount_m2"):
		operator.dismount_m2()
	operator = null


func net_apply_state(new_aim: Vector2) -> void:
	# Remote peers use this to mirror the operator's turret direction.
	aim_dir = new_aim
	if is_instance_valid(operator):
		operator.set("facing", 1.0 if aim_dir.x >= 0.0 else -1.0)


func net_apply_fire(muzzle: Vector2, dir: Vector2, shooter_team: int, shooter_name: String) -> void:
	fire_cd = RATE
	var b := _bullet_scene.instantiate()
	b.global_position = muzzle
	b.direction = dir
	b.speed = SPEED
	b.damage = DAMAGE
	b.team = shooter_team
	b.killer_name = shooter_name
	b.weapon_name = "M2"
	get_parent().add_child(b)
	Sfx.shoot("Minigun")
	if is_instance_valid(operator) and operator.has_method("_shake"):
		operator._shake(1.8)


func _process(delta: float) -> void:
	fire_cd = maxf(0.0, fire_cd - delta)
	queue_redraw()
	if not is_instance_valid(operator):
		operator = null
		return
	if bool(operator.get("dead")):
		dismount()
		return
	# Snap operator to the mount seat and freeze their velocity — they're the
	# gunner, not a moving soldier while mounted.
	operator.global_position = global_position + Vector2(0, -12)
	operator.set("velocity", Vector2.ZERO)
	# In MP, only the operator's own peer reads input + drives the turret.
	# Other peers just render whatever aim_dir was last set via net_apply_state.
	var is_local_driver: bool = true
	if Net.is_networked():
		is_local_driver = int(operator.get_multiplayer_authority()) == Net.local_id()
	if not is_local_driver:
		return
	# Aim = operator's mouse, clamped to a sensible turret cone.
	var mouse: Vector2 = operator.get_global_mouse_position()
	var to_mouse := mouse - global_position
	if to_mouse.length() > 1.0:
		var a := to_mouse.normalized()
		var min_y := -AIM_MAX_ELEV
		var max_y := AIM_MAX_DEPRESS
		if a.y < min_y or a.y > max_y:
			var new_y: float = clampf(a.y, min_y, max_y)
			var new_x_sq := 1.0 - new_y * new_y
			var new_x: float = sqrt(maxf(0.0, new_x_sq)) * (1.0 if a.x >= 0.0 else -1.0)
			a = Vector2(new_x, new_y)
		aim_dir = a
		operator.set("facing", 1.0 if aim_dir.x >= 0.0 else -1.0)
	# Broadcast state so remote peers see the barrel swing.
	if Net.is_networked():
		var main := get_parent()
		if main != null and main.has_method("net_m2_state"):
			main.rpc("net_m2_state", m2_id, aim_dir)
	# Dismount if the operator taps a directional key (any movement action).
	if Input.is_action_pressed("jump") or Input.is_action_pressed("move_left") \
			or Input.is_action_pressed("move_right") or Input.is_action_pressed("crouch"):
		dismount()
		return
	# Fire on LMB — hitscan-fast bullets with a tight cone.
	if Input.is_action_pressed("fire") and fire_cd <= 0.0:
		_fire()


func _fire() -> void:
	var muzzle := global_position + Vector2(0, -14) + aim_dir * 26.0
	var dir := aim_dir.rotated(randf_range(-SPREAD, SPREAD))
	var op_team: int = int(operator.get("team"))
	var op_name: String = str(operator.get("display_name"))
	if Net.is_networked():
		var main := get_parent()
		if main != null and main.has_method("net_m2_fire"):
			main.rpc("net_m2_fire", m2_id, muzzle, dir, op_team, op_name)
		return
	# SP path: apply locally.
	net_apply_fire(muzzle, dir, op_team, op_name)


func _draw() -> void:
	# Mount + barrel drawn from the two Soldat sprites.
	var stat_tex: Texture2D = load("res://assets/weapons-gfx/m2-stat.png") as Texture2D
	var barrel_tex: Texture2D = load("res://assets/weapons-gfx/m2.png") as Texture2D
	var s_scale := 1.0 / 3.0
	if stat_tex != null:
		var ss := stat_tex.get_size() * s_scale
		draw_texture_rect(stat_tex, Rect2(Vector2(-ss.x * 0.5, -ss.y + 6.0), ss), false)
	if barrel_tex != null:
		var bs := barrel_tex.get_size() * s_scale
		var angle: float = aim_dir.angle()
		var flip_y: float = -1.0 if aim_dir.x < 0.0 else 1.0
		draw_set_transform(Vector2(0, -14), angle, Vector2(1.0, flip_y))
		draw_texture_rect(barrel_tex, Rect2(Vector2(-bs.x * 0.15, -bs.y * 0.5), bs), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Interaction hint — only visible when a soldier is close enough to mount.
	if operator == null:
		for s in get_tree().get_nodes_in_group("soldier"):
			if not is_instance_valid(s) or bool(s.get("dead")):
				continue
			if global_position.distance_to(s.global_position) < MOUNT_RADIUS + 4.0:
				draw_string(ThemeDB.fallback_font, Vector2(-16, -46), "F: MOUNT", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0.95, 0.9, 0.5))
				break
