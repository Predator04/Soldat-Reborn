extends RefCounted
## Shared soldier renderer.
## Body is assembled from real gostek-gfx PNGs via Gostek.draw_body.
## Weapon is the real weapons-gfx sprite. Muzzle flash + HP bars still draw
## procedurally on top. Jet flame stays procedural for now.

const HP_BAR_Y := -21.0

const WEAPON_SPRITE := {
	"Deagles": "res://assets/weapons-gfx/deserteagle.png",
	"AK-74": "res://assets/weapons-gfx/ak74.png",
	"MP5": "res://assets/weapons-gfx/mp5.png",
	"Spas-12": "res://assets/weapons-gfx/spas12.png",
	"LAW": "res://assets/weapons-gfx/law.png",
}

# Grip pivot (cx, cy) per weapon — matches Soldat's GostekGraphics.inc values.
const WEAPON_PIVOT := {
	"Deagles": [0.10, 0.80],
	"AK-74":   [0.15, 0.50],
	"MP5":     [0.15, 0.60],
	"Spas-12": [0.10, 0.60],
	"LAW":     [0.10, 0.60],
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
	var pack_x := -facing * 3.3
	node.draw_rect(Rect2(pack_x - 1.25, -9.0, 2.5, 6.25), pack_col)
	node.draw_rect(Rect2(pack_x - 1.7, -9.0, 3.3, 1.25), pack_col.darkened(0.2))

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
		shoulder = Vector2(facing * 1.2, -8.0)
	var barrel_end: Vector2 = _draw_weapon_sprite(node, shoulder, aim_dir, facing, weapon_name, weapon_color, weapon_kind)

	# Muzzle flash on top of the sprite.
	if muzzle_t > 0.0:
		var flash_pos: Vector2 = barrel_end + aim_dir * 1.2
		var m := muzzle_t
		node.draw_circle(flash_pos, 1.25 + m * 12.5, Color(1.0, 0.45, 0.15, m * 0.35))
		node.draw_circle(flash_pos, 1.0 + m * 9.2, Color(1.0, 0.8, 0.35, m * 0.6))
		node.draw_circle(flash_pos, 0.67 + m * 5.8, Color(1.0, 1.0, 0.7, m * 0.85))

	# HP + optional fuel bar.
	node.draw_rect(Rect2(-6.5, HP_BAR_Y, 13.0, 2.0), Color(0.0, 0.0, 0.0, 0.55))
	node.draw_rect(Rect2(-6.5, HP_BAR_Y, 13.0 * clampf(health / 100.0, 0.0, 1.0), 2.0), Color(0.9, 0.2, 0.2))
	if show_fuel:
		node.draw_rect(Rect2(-6.5, HP_BAR_Y + 2.0, 13.0, 1.5), Color(0.0, 0.0, 0.0, 0.55))
		node.draw_rect(Rect2(-6.5, HP_BAR_Y + 2.0, 13.0 * clampf(fuel / 100.0, 0.0, 1.0), 1.5), Color(0.3, 0.7, 1.0))

	# Team indicator arrow above the head (Soldat-style), colored by body/team color.
	if not dead:
		var arrow_col := body_color.lightened(0.25)
		node.draw_polygon(PackedVector2Array([
			Vector2(-4.0, -40.0),
			Vector2(4.0, -40.0),
			Vector2(0.0, -33.0),
		]), PackedColorArray([arrow_col, arrow_col, arrow_col]))


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
	# Grip pivot matches Soldat's per-weapon cx/cy (GostekGraphics.inc).
	var pivot: Array = WEAPON_PIVOT.get(weapon_name, [0.15, 0.5])
	var grip_offset := size.x * float(pivot[0])
	var cy_offset := size.y * float(pivot[1])
	var barrel_len := size.x - grip_offset
	var angle := aim_dir.angle()
	# Base the vertical flip on soldier facing, not aim.x — avoids "popping" flips
	# as the aim wobbles across x=0 (straight up/down).
	var flip_y := -1.0 if facing < 0.0 else 1.0

	node.draw_set_transform(shoulder, angle, Vector2(1.0, flip_y))
	node.draw_texture_rect(tex, Rect2(Vector2(-grip_offset, -cy_offset), size), false)
	node.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	return shoulder + aim_dir * barrel_len


# Muzzle (barrel-tip) position in the node's LOCAL space. Used by both the
# muzzle flash and the bullet spawn so shots originate from the gun itself.
static func muzzle_local(node: CanvasItem, aim_dir: Vector2, facing: float, weapon_name: String) -> Vector2:
	var shoulder: Vector2 = Gostek.joint_pos(node, 16)
	if not Gostek.has_frame(node):
		shoulder = Vector2(facing * 1.2, -8.0)
	var tex := _weapon_texture(weapon_name)
	if tex == null:
		return shoulder + aim_dir * 22.0
	var size := tex.get_size()
	var pivot: Array = WEAPON_PIVOT.get(weapon_name, [0.15, 0.5])
	var barrel_len := size.x * (1.0 - float(pivot[0]))
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
	var origin: Vector2 = Vector2(-facing * 3.3, 1.2)
	var length := 9.0 + sin(t * 26.0) * 1.9
	var wobble := cos(t * 18.0) * 0.5
	var w0 := 2.0 + wobble
	var w1 := 1.4 + wobble * 0.7
	var w2 := 0.8

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
