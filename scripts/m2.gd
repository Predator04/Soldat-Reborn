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


func _ready() -> void:
	add_to_group("m2_gun")
	z_index = 1


func mount(pl: Node2D) -> void:
	if not is_instance_valid(pl):
		return
	if operator != null:
		return
	operator = pl
	if pl.has_method("mount_m2"):
		pl.mount_m2(self)


func dismount() -> void:
	if is_instance_valid(operator) and operator.has_method("dismount_m2"):
		operator.dismount_m2()
	operator = null


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
	# Aim = operator's mouse, clamped to a sensible turret cone.
	var mouse: Vector2 = operator.get_global_mouse_position()
	var to_mouse := mouse - global_position
	if to_mouse.length() > 1.0:
		var a := to_mouse.normalized()
		# Clamp elevation: min y (up) is -AIM_MAX_ELEV, max y (down) is +AIM_MAX_DEPRESS.
		var min_y := -AIM_MAX_ELEV
		var max_y := AIM_MAX_DEPRESS
		if a.y < min_y or a.y > max_y:
			var new_y: float = clampf(a.y, min_y, max_y)
			var new_x_sq := 1.0 - new_y * new_y
			var new_x: float = sqrt(maxf(0.0, new_x_sq)) * (1.0 if a.x >= 0.0 else -1.0)
			a = Vector2(new_x, new_y)
		aim_dir = a
		operator.set("facing", 1.0 if aim_dir.x >= 0.0 else -1.0)
	# Dismount if the operator taps a directional key.
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_SPACE) \
			or Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_D) \
			or Input.is_physical_key_pressed(KEY_S):
		dismount()
		return
	# Fire on LMB — hitscan-fast bullets with a tight cone. Skip in networked mode
	# to keep the RPC surface small; M2 is currently SP-only.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and fire_cd <= 0.0 and not Net.is_networked():
		_fire()


func _fire() -> void:
	fire_cd = RATE
	var b := _bullet_scene.instantiate()
	var muzzle := global_position + Vector2(0, -14) + aim_dir * 26.0
	b.global_position = muzzle
	b.direction = aim_dir.rotated(randf_range(-SPREAD, SPREAD))
	b.speed = SPEED
	b.damage = DAMAGE
	b.team = int(operator.get("team"))
	b.killer_name = str(operator.get("display_name"))
	b.weapon_name = "M2"
	get_parent().add_child(b)
	Sfx.shoot("Minigun")
	if operator.has_method("_shake"):
		operator._shake(1.8)


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
