extends RefCounted
## Shared soldier renderer.
## Body is assembled from real gostek-gfx PNGs via Gostek.draw_body.
## Weapon is the real weapons-gfx sprite. Muzzle flash + HP bars still draw
## procedurally on top. Jet flame stays procedural for now.

const HP_BAR_Y := -21.0
const OP_GUN_SCALE := 0.78   # #281: in-hand / slung guns on the Operator soldier

const WEAPON_SPRITE := {
	"Deagles":      "res://assets/weapons-gfx/deserteagle.png",
	"MP5":          "res://assets/weapons-gfx/mp5.png",
	"AK-74":        "res://assets/weapons-gfx/ak74.png",
	"Steyr AUG":    "res://assets/weapons-gfx/steyraug.png",
	"Spas-12":      "res://assets/weapons-gfx/spas12.png",
	"Ruger 77":     "res://assets/weapons-gfx/ruger77.png",
	"M79":          "res://assets/weapons-gfx/m79.png",
	"Barrett":      "res://assets/weapons-gfx/barretm82.png",
	"Minimi":       "res://assets/weapons-gfx/m249.png",
	"Minigun":      "res://assets/weapons-gfx/minigun.png",
	"USSOCOM":      "res://assets/weapons-gfx/colt1911.png",
	"Knife":        "res://assets/weapons-gfx/knife.png",
	"Chainsaw":     "res://assets/weapons-gfx/chainsaw.png",
	"LAW":          "res://assets/weapons-gfx/law.png",
	"Flamethrower": "res://assets/weapons-gfx/flamer.png",
	"Rambo Bow":    "res://assets/weapons-gfx/bow.png",
}

# Grip pivot (cx, cy) per weapon — matches Soldat's GostekGraphics.inc values.
const WEAPON_PIVOT := {
	"Deagles":   [0.10, 0.80],
	"MP5":       [0.15, 0.60],
	"AK-74":     [0.15, 0.50],
	"Steyr AUG": [0.20, 0.50],
	"Spas-12":   [0.10, 0.60],
	"Ruger 77":  [0.10, 0.60],
	"M79":       [0.10, 0.60],
	"Barrett":   [0.15, 0.50],
	"Minimi":    [0.15, 0.50],
	"Minigun":   [0.05, 0.50],
	"USSOCOM":      [0.20, 0.70],
	"Knife":        [-0.10, 0.50],
	"Chainsaw":     [0.10, 0.50],
	"LAW":          [0.10, 0.60],
	"Flamethrower": [0.10, 0.55],
	"Rambo Bow":    [0.20, 0.50],
}

static var _tex_cache: Dictionary = {}
static var _atmo_script: Script = null


## scripts/gfx/atmosphere.gd, loaded on first use (soldier_art is preloaded by
## scripts that -s tests compile before the class cache is ready).
static func _atmo() -> Script:
	if _atmo_script == null:
		_atmo_script = load("res://scripts/gfx/atmosphere.gd")
	return _atmo_script

const Gostek = preload("res://scripts/gostek.gd")
const WeaponGfx = preload("res://scripts/weapon_gfx.gd")   # #284 HD weapon sprites


## Paint one soldier on `node` (its own _draw()). `st` carries the pose,
## weapon and HUD bits — see soldier_draw_state.gd.
static func draw_soldier(node: CanvasItem, st: SoldierDrawState) -> void:
	var body_color: Color = st.body_color
	var facing: float = st.facing
	var aim_dir: Vector2 = st.aim_dir
	var dead: bool = st.dead
	var muzzle_t: float = st.muzzle_t
	var health: float = st.health
	var cosmetics: Dictionary = st.cosmetics
	# Phase B (#271): squash-and-stretch / recoil (SoldierFeel) — a transform
	# about the feet applied to the drawn sprite only.
	var xf := Transform2D(st.fx_rot, st.fx_scale, 0.0, st.fx_offset)
	var has_xf := not xf.is_equal_approx(Transform2D.IDENTITY)
	if has_xf:
		node.draw_set_transform_matrix(xf)
	var op := Gostek.operator_on()
	var jet_col: Color = Gostek.Custom.JET_COLORS.get(str(cosmetics.get("jet", "")), Color(1.0, 0.35, 0.10))
	if st.jet_on and not dead and not op:
		_draw_jet_flame(node, facing, jet_col)

	# Jetpack — sits behind the torso on the opposite side of `facing`.
	# (#280 Operator: a sprite on the back line, drawn by gostek.gd.)
	if not op:
		var pack_col := body_color.darkened(0.25) if not dead else body_color.darkened(0.6)
		var pack_x := -facing * 3.3
		node.draw_rect(Rect2(pack_x - 1.25, -9.0, 2.5, 6.25), pack_col)
		node.draw_rect(Rect2(pack_x - 1.7, -9.0, 3.3, 1.25), pack_col.darkened(0.2))
	elif st.jet_on and not dead:
		var nz: Array = Gostek.jet_nozzle(node)
		if not nz.is_empty():
			_draw_jet_flame(node, facing, jet_col, nz[0], nz[1], xf)
			# #282: the burn lights the soldier and the ground below (pooled light).
			_atmo().light_keep(node.get_instance_id() * 8 + 5, node.to_global(nz[0] + (nz[1] as Vector2) * 6.0), jet_col, 75.0, 0.85)
	if op and st.on_floor and not st.prone and not dead:
		# #282: soft contact shadow under the boots grounds the soldier.
		node.draw_set_transform(Vector2(0.0, 6.4), 0.0, Vector2(1.0, 0.24))
		node.draw_circle(Vector2.ZERO, 6.5, Color(0, 0, 0, 0.16))
		node.draw_circle(Vector2.ZERO, 4.2, Color(0, 0, 0, 0.18))
		if has_xf:
			node.draw_set_transform_matrix(xf)
		else:
			node.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Real body sprites, driven by .poa keyframes.
	var gs := {
		"facing": facing,
		"aim_dir": aim_dir,
		"velocity": st.vel,
		"on_floor": st.on_floor,
		"jet_on": st.jet_on,
		"reloading": st.reloading,
		"dead": dead,
		"crouching": st.crouching,
		"prone": st.prone,
		"melee_swing": st.melee_swing,
		"gesture_anim": st.gesture_anim,
		"rolling": st.rolling,
		"cosmetics": cosmetics,
		"health": health,
		"back_weapon": st.back_weapon_name,
		"grenades": st.grenade_count,
		"use_cluster": st.use_cluster,
	}
	if has_xf:
		gs["xf"] = xf
	Gostek.draw_body(node, gs, body_color)

	# Weapon sprite along aim_dir, mounted at the animated right wrist
	# (skeleton joint 16). Fall back to a fixed shoulder point if the
	# skeleton hasn't produced a valid position yet.
	var shoulder: Vector2 = Gostek.joint_pos(node, 16)
	if not Gostek.has_frame(node):
		shoulder = Vector2(facing * 1.2, -8.0)
	var wskin: Color = Gostek.Custom.WEAPON_SKINS.get(str(cosmetics.get("wskin", "")), Color.WHITE)
	if dead:
		wskin = wskin.darkened(0.4)
	# Recoil: the gun kicks back along the aim for the muzzle flash's life.
	if muzzle_t > 0.0 and not dead:
		shoulder -= aim_dir * muzzle_t * 22.0
	shoulder -= aim_dir * st.fx_kick * 2.0
	var barrel_end: Vector2 = _draw_weapon_sprite(node, shoulder, aim_dir, facing, st.weapon_name, st.weapon_color, st.weapon_kind, wskin, xf if has_xf else Transform2D.IDENTITY)

	# Muzzle flash on top of the sprite (bigger/brighter so shots clearly read as muzzle fire).
	if muzzle_t > 0.0:
		var flash_pos: Vector2 = barrel_end + aim_dir * 2.0
		var m := muzzle_t
		node.draw_circle(flash_pos, 2.5 + m * 18.0, Color(1.0, 0.45, 0.15, m * 0.5))
		node.draw_circle(flash_pos, 1.8 + m * 13.0, Color(1.0, 0.8, 0.35, m * 0.72))
		node.draw_circle(flash_pos, 1.2 + m * 8.0, Color(1.0, 1.0, 0.7, m * 0.95))
	if has_xf:
		node.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# HP + optional fuel bar.
	if st.show_hp:
		node.draw_rect(Rect2(-6.5, HP_BAR_Y, 13.0, 2.0), Color(0.0, 0.0, 0.0, 0.55))
		node.draw_rect(Rect2(-6.5, HP_BAR_Y, 13.0 * clampf(health / 100.0, 0.0, 1.0), 2.0), Color(0.9, 0.2, 0.2))
	if st.show_fuel:
		node.draw_rect(Rect2(-6.5, HP_BAR_Y + 2.0, 13.0, 1.5), Color(0.0, 0.0, 0.0, 0.55))
		node.draw_rect(Rect2(-6.5, HP_BAR_Y + 2.0, 13.0 * clampf(st.fuel / 100.0, 0.0, 1.0), 1.5), Color(0.3, 0.7, 1.0))

	# "You" indicator arrow above the head — only over the LOCAL player (the one
	# actually playing), never over remote players or bots.
	if st.is_local and not dead:
		var arrow_col := body_color.lightened(0.25)
		node.draw_polygon(PackedVector2Array([
			Vector2(-7.0, -44.0),
			Vector2(7.0, -44.0),
			Vector2(0.0, -33.0),
		]), PackedColorArray([arrow_col, arrow_col, arrow_col]))

	# Ceasefire (spawn protection) — soft pulsing cyan aura ring so it reads
	# immediately as "invulnerable" to shooters.
	if st.ceasefire and not dead:
		var pulse: float = 0.35 + 0.25 * sin(Time.get_ticks_msec() * 0.012)
		node.draw_arc(Vector2(0, -8.0), 20.0, 0.0, TAU, 32, Color(0.4, 0.85, 1.0, pulse), 1.6)
		node.draw_arc(Vector2(0, -8.0), 24.0, 0.0, TAU, 32, Color(0.4, 0.85, 1.0, pulse * 0.55), 1.0)


# Returns the barrel-tip position in the node's local space so callers can
# put the muzzle flash there.
static func _draw_weapon_sprite(
	node: CanvasItem,
	shoulder: Vector2,
	aim_dir: Vector2,
	facing: float,
	weapon_name: String,
	fallback_color: Color,
	weapon_kind: String,
	skin: Color = Color.WHITE,
	xf: Transform2D = Transform2D.IDENTITY
) -> Vector2:
	var tex := _weapon_texture(weapon_name)
	if tex == null:
		var line_len := 22.0 if weapon_kind != "rocket" else 18.0
		var line_thick := 6.5 if weapon_kind == "rocket" else 3.4
		var end: Vector2 = shoulder + aim_dir * line_len
		node.draw_line(shoulder, end, fallback_color, line_thick)
		return end

	var size := tex.get_size() * Gostek.SPRITE_SCALE
	# Grip pivot matches Soldat's per-weapon cx/cy (GostekGraphics.inc).
	var pivot: Array = WEAPON_PIVOT.get(weapon_name, [0.15, 0.5])
	var grip_offset := size.x * float(pivot[0])
	var cy_offset := size.y * float(pivot[1])
	var barrel_len := size.x - grip_offset
	var angle := aim_dir.angle()
	# Base the vertical flip on soldier facing, not aim.x — avoids "popping" flips
	# as the aim wobbles across x=0 (straight up/down).
	var flip_y := -1.0 if facing < 0.0 else 1.0

	# #284: Operator look draws the 3x HD sprite into the same classic rect
	# (size / pivot / barrel_len above all come from the classic texture).
	var draw_tex := tex
	var gs := 1.0
	if Gostek.operator_on():
		var hd := WeaponGfx.hd_for_path(str(WEAPON_SPRITE[weapon_name]))
		if hd != null:
			draw_tex = hd
		# #281: guns sized for the chibi gostek dwarf the Operator soldier; draw
		# them smaller about the grip. Visual only: muzzle_local() (bullet spawn)
		# keeps the classic barrel length, so play is the same in both looks.
		gs = OP_GUN_SCALE
	var plain := xf == Transform2D.IDENTITY
	if plain:
		node.draw_set_transform(shoulder, angle, Vector2(gs, flip_y * gs))
	else:
		node.draw_set_transform_matrix(xf * Transform2D(angle, Vector2(gs, flip_y * gs), 0.0, shoulder))
	node.draw_texture_rect(draw_tex, Rect2(Vector2(-grip_offset, -cy_offset), size), false, skin)
	if plain:
		node.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		node.draw_set_transform_matrix(xf)

	return shoulder + aim_dir * barrel_len * gs


# Muzzle (barrel-tip) position in the node's LOCAL space. Used by both the
# muzzle flash and the bullet spawn so shots originate from the gun itself.
static func muzzle_local(node: CanvasItem, aim_dir: Vector2, facing: float, weapon_name: String) -> Vector2:
	var shoulder: Vector2 = Gostek.joint_pos(node, 16)
	if not Gostek.has_frame(node):
		shoulder = Vector2(facing * 1.2, -8.0)
	var tex := _weapon_texture(weapon_name)
	if tex == null:
		return shoulder + aim_dir * 22.0
	var size := tex.get_size() * Gostek.SPRITE_SCALE
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


static func _draw_jet_flame(node: CanvasItem, facing: float, base: Color = Color(1.0, 0.35, 0.10), at := Vector2.INF, down := Vector2.DOWN, base_xf := Transform2D.IDENTITY) -> void:
	var outer := Color(base.r, base.g, base.b, 0.55)
	var mid := base.lerp(Color(1, 1, 0.8), 0.45)
	mid.a = 0.75
	var t := Time.get_ticks_msec() * 0.001
	var origin: Vector2 = Vector2(-facing * 3.3, 1.2) if not at.is_finite() else at
	# #280: the flame leaves the nozzle along the back line; draw it in a frame
	# where +y is that direction.
	var rot := Vector2.DOWN.angle_to(down) if at.is_finite() else 0.0
	if rot != 0.0:
		node.draw_set_transform_matrix(base_xf * Transform2D(rot, origin))
		origin = Vector2.ZERO
	var length := 9.0 + sin(t * 26.0) * 1.9
	var wobble := cos(t * 18.0) * 0.5
	var w0 := 2.0 + wobble
	var w1 := 1.4 + wobble * 0.7
	var w2 := 0.8
	# Phase B (#271): a faint neon bloom around the nozzle (embers + heat
	# shimmer come from fx_world.gd).
	var bloom_r := 3.6 + sin(t * 31.0) * 0.6
	for k in 3:
		node.draw_circle(origin + Vector2(0.0, 2.5), bloom_r * (1.0 - k * 0.28), Color(base.r, base.g, base.b, 0.06))

	node.draw_polygon(
		PackedVector2Array([
			origin + Vector2(-w0, 0.0),
			origin + Vector2(w0, 0.0),
			origin + Vector2(wobble * 0.5, length),
		]),
		PackedColorArray([
			outer,
			outer,
			Color(base.r, base.g * 0.7, base.b * 0.5, 0.0),
		])
	)
	node.draw_polygon(
		PackedVector2Array([
			origin + Vector2(-w1, 0.0),
			origin + Vector2(w1, 0.0),
			origin + Vector2(wobble * 0.3, length * 0.78),
		]),
		PackedColorArray([
			mid,
			mid,
			Color(mid.r, mid.g, mid.b, 0.0),
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
	if rot != 0.0:
		node.draw_set_transform_matrix(base_xf)
