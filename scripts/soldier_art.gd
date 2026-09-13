extends RefCounted
## Shared soldier renderer.
## Body is assembled from real gostek-gfx PNGs via Gostek.draw_body.
## Weapon is the real weapons-gfx sprite. Muzzle flash + HP bars still draw
## procedurally on top. Jet flame stays procedural for now.

const HP_BAR_Y := -50.0

const WEAPON_SPRITE := {
	"Deagles": "res://assets/weapons-gfx/deserteagle.png",
	"AK-74": "res://assets/weapons-gfx/ak74.png",
	"MP5": "res://assets/weapons-gfx/mp5.png",
	"Spas-12": "res://assets/weapons-gfx/spas12.png",
	"LAW": "res://assets/weapons-gfx/law.png",
}

static var _tex_cache: Dictionary = {}

const Gostek = preload("res://scripts/gostek.gd")


static func draw_soldier(
	node: CanvasItem,
	body_color: Color,
	facing: float,
	aim_dir: Vector2,
	vel: Vector2,
	jet_on: bool,
	dead: bool,
	weapon_color: Color,
	weapon_kind: String,
	muzzle_t: float,
	health: float,
	fuel: float,
	show_fuel: bool,
	weapon_name: String = "",
	on_floor: bool = true,
	reloading: bool = false,
) -> void:
	if jet_on and not dead:
		_draw_jet_flame(node, facing)

	# Jetpack — sits behind the torso on the opposite side of `facing`.
	var pack_col := body_color.darkened(0.25) if not dead else body_color.darkened(0.6)
	var pack_x := -facing * 8.0
	node.draw_rect(Rect2(pack_x - 3.0, -22.0, 6.0, 15.0), pack_col)
	node.draw_rect(Rect2(pack_x - 4.0, -22.0, 8.0, 3.0), pack_col.darkened(0.2))

	# Real body sprites, driven by .poa keyframes.
	var gs := {
		"facing": facing,
		"aim_dir": aim_dir,
		"velocity": vel,
		"on_floor": on_floor,
		"jet_on": jet_on,
		"reloading": reloading,
		"dead": dead,
	}
	Gostek.draw_body(node, gs, body_color)

	# Weapon sprite along aim_dir, mounted at the animated right wrist
	# (skeleton joint 16). Fall back to a fixed shoulder point if the
	# skeleton hasn't produced a valid position yet.
	var shoulder: Vector2 = Gostek.joint_pos(node, 16)
	if not Gostek.has_frame(node):
		shoulder = Vector2(facing * 3.0, -19.0)
	var barrel_end: Vector2 = _draw_weapon_sprite(node, shoulder, aim_dir, facing, weapon_name, weapon_color, weapon_kind)

	# Muzzle flash on top of the sprite.
	if muzzle_t > 0.0:
		var flash_pos: Vector2 = barrel_end + aim_dir * 3.0
		var m := muzzle_t
		node.draw_circle(flash_pos, 3.0 + m * 30.0, Color(1.0, 0.45, 0.15, m * 0.35))
		node.draw_circle(flash_pos, 2.4 + m * 22.0, Color(1.0, 0.8, 0.35, m * 0.6))
		node.draw_circle(flash_pos, 1.6 + m * 14.0, Color(1.0, 1.0, 0.7, m * 0.85))

	# HP + optional fuel bar.
	node.draw_rect(Rect2(-16.0, HP_BAR_Y, 32.0, 4.0), Color(0.0, 0.0, 0.0, 0.55))
	node.draw_rect(Rect2(-16.0, HP_BAR_Y, 32.0 * clampf(health / 100.0, 0.0, 1.0), 4.0), Color(0.9, 0.2, 0.2))
	if show_fuel:
		node.draw_rect(Rect2(-16.0, HP_BAR_Y + 5.0, 32.0, 3.0), Color(0.0, 0.0, 0.0, 0.55))
		node.draw_rect(Rect2(-16.0, HP_BAR_Y + 5.0, 32.0 * clampf(fuel / 100.0, 0.0, 1.0), 3.0), Color(0.3, 0.7, 1.0))


# Returns the barrel-tip position in the node's local space so callers can
# put the muzzle flash there.
static func _draw_weapon_sprite(
	node: CanvasItem,
	shoulder: Vector2,
	aim_dir: Vector2,
	facing: float,
	weapon_name: String,
	fallback_color: Color,
	weapon_kind: String
) -> Vector2:
	var tex := _weapon_texture(weapon_name)
	if tex == null:
		var line_len := 22.0 if weapon_kind != "rocket" else 18.0
		var line_thick := 6.5 if weapon_kind == "rocket" else 3.4
		var end: Vector2 = shoulder + aim_dir * line_len
		node.draw_line(shoulder, end, fallback_color, line_thick)
		return end

	var size := tex.get_size()
	# Grip pivot sits ~20% in from the left edge of the sprite.
	var grip_offset := size.x * 0.2
	var barrel_len := size.x - grip_offset
	var angle := aim_dir.angle()
	# Base the vertical flip on soldier facing, not aim.x — avoids "popping" flips
	# as the aim wobbles across x=0 (straight up/down).
	var flip_y := -1.0 if facing < 0.0 else 1.0

	node.draw_set_transform(shoulder, angle, Vector2(1.0, flip_y))
	node.draw_texture_rect(tex, Rect2(Vector2(-grip_offset, -size.y * 0.5), size), false)
	node.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	return shoulder + aim_dir * barrel_len


static func _weapon_texture(weapon_name: String) -> Texture2D:
	if not WEAPON_SPRITE.has(weapon_name):
		return null
	if _tex_cache.has(weapon_name):
		return _tex_cache[weapon_name]
	var path: String = WEAPON_SPRITE[weapon_name]
	var tex := load(path) as Texture2D if ResourceLoader.exists(path) else null
	_tex_cache[weapon_name] = tex
	return tex


static func _draw_jet_flame(node: CanvasItem, facing: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	var origin: Vector2 = Vector2(-facing * 8.0, 3.0)
	var length := 22.0 + sin(t * 26.0) * 4.5
	var wobble := cos(t * 18.0) * 1.2
	var w0 := 5.0 + wobble
	var w1 := 3.4 + wobble * 0.7
	var w2 := 1.9

	node.draw_polygon(
		PackedVector2Array([
			origin + Vector2(-w0, 0.0),
			origin + Vector2(w0, 0.0),
			origin + Vector2(wobble * 0.5, length),
		]),
		PackedColorArray([
			Color(1.0, 0.35, 0.10, 0.55),
			Color(1.0, 0.35, 0.10, 0.55),
			Color(1.0, 0.25, 0.05, 0.0),
		])
	)
	node.draw_polygon(
		PackedVector2Array([
			origin + Vector2(-w1, 0.0),
			origin + Vector2(w1, 0.0),
			origin + Vector2(wobble * 0.3, length * 0.78),
		]),
		PackedColorArray([
			Color(1.0, 0.72, 0.28, 0.75),
			Color(1.0, 0.72, 0.28, 0.75),
			Color(1.0, 0.72, 0.28, 0.0),
		])
	)
	node.draw_polygon(
		PackedVector2Array([
			origin + Vector2(-w2, 0.0),
			origin + Vector2(w2, 0.0),
			origin + Vector2(0.0, length * 0.55),
		]),
		PackedColorArray([
			Color(1.0, 1.0, 0.85, 0.95),
			Color(1.0, 1.0, 0.85, 0.95),
			Color(1.0, 1.0, 0.85, 0.0),
		])
	)
