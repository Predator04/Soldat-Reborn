extends RefCounted
## Shared procedural soldier renderer (head/torso/arms/legs/weapon + jet flame + muzzle flash).
## Preloaded from player.gd and bot.gd (not a class_name — reload-time resolution flakes across scene changes).

const HP_BAR_Y := -50.0


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
	show_fuel: bool
) -> void:
	var col := body_color if not dead else body_color.darkened(0.4)
	var pants_col := col.darkened(0.45)
	var skin_col := Color(0.94, 0.78, 0.62) if not dead else Color(0.55, 0.5, 0.5)
	var shoe_col := Color(0.10, 0.11, 0.14)
	var pack_col := col.darkened(0.25)
	var visor_col := Color(0.10, 0.14, 0.22) if not dead else Color(0.25, 0.15, 0.15)

	if jet_on and not dead:
		_draw_jet_flame(node, facing)

	# Jetpack — sits behind the torso on the opposite side of `facing`.
	var pack_x := -facing * 8.0
	node.draw_rect(Rect2(pack_x - 3.0, -22.0, 6.0, 15.0), pack_col)
	node.draw_rect(Rect2(pack_x - 4.0, -22.0, 8.0, 3.0), pack_col.darkened(0.2))

	# Legs — cycle when moving on the ground; stand straight in air.
	var move_amt := clampf(absf(vel.x) / 400.0, 0.0, 1.0)
	var t := Time.get_ticks_msec() * 0.001
	var swing := 0.0
	if move_amt > 0.05:
		swing = sin(t * 14.0) * 4.5 * move_amt
	var lf: Vector2 = Vector2(-3.0 + swing, 9.0)
	var rf: Vector2 = Vector2(3.0 - swing, 9.0)
	node.draw_line(Vector2(-3.0, -2.0), lf, pants_col, 5.0)
	node.draw_line(Vector2(3.0, -2.0), rf, pants_col, 5.0)
	# shoes point in the facing direction
	node.draw_line(lf, lf + Vector2(facing * 3.5, 1.0), shoe_col, 4.0)
	node.draw_line(rf, rf + Vector2(facing * 3.5, 1.0), shoe_col, 4.0)

	# Torso — rounded polygon, slight darkening at the belt.
	var torso := PackedVector2Array([
		Vector2(-8.0, -22.0),
		Vector2(8.0, -22.0),
		Vector2(9.0, -8.0),
		Vector2(6.0, -2.0),
		Vector2(-6.0, -2.0),
		Vector2(-9.0, -8.0),
	])
	var torso_cols := PackedColorArray([
		col.lightened(0.05),
		col.lightened(0.05),
		col,
		col.darkened(0.12),
		col.darkened(0.12),
		col,
	])
	node.draw_polygon(torso, torso_cols)

	# Head — circle with a helmet cap and a visor stripe.
	var head_pos: Vector2 = Vector2(facing * 1.5, -29.0)
	node.draw_circle(head_pos, 6.5, skin_col)
	node.draw_polygon(
		PackedVector2Array([
			head_pos + Vector2(-6.5, -0.5),
			head_pos + Vector2(6.5, -0.5),
			head_pos + Vector2(6.0, -6.0),
			head_pos + Vector2(-6.0, -6.0),
		]),
		PackedColorArray([col.darkened(0.2), col.darkened(0.2), col.darkened(0.3), col.darkened(0.3)])
	)
	node.draw_line(head_pos + Vector2(-5.0, -1.0), head_pos + Vector2(5.0, -1.0), visor_col, 2.6)

	# Weapon — line in aim_dir, thicker/stumpier for rockets, drawn behind the flash.
	var shoulder: Vector2 = Vector2(facing * 3.0, -19.0)
	var grip: Vector2 = shoulder + aim_dir * 5.0
	var barrel_len := 22.0 if weapon_kind != "rocket" else 18.0
	var barrel_thick := 6.5 if weapon_kind == "rocket" else 3.4
	var barrel_end: Vector2 = shoulder + aim_dir * barrel_len
	node.draw_line(grip, barrel_end, weapon_color, barrel_thick)
	if weapon_kind == "rocket":
		# tube muzzle ring
		node.draw_circle(barrel_end, 3.6, weapon_color.darkened(0.25))
	# stock
	node.draw_line(shoulder, grip - aim_dir * 2.0, weapon_color.darkened(0.35), barrel_thick * 0.7)
	# front arm reaches for the grip
	node.draw_line(shoulder, grip, col.lightened(0.1), 4.0)
	# back arm dangles a bit toward the pack
	var back_hand: Vector2 = Vector2(-facing * 6.0, -10.0)
	node.draw_line(Vector2(-facing * 2.0, -18.0), back_hand, col.lightened(0.05), 3.5)

	# Muzzle flash — layered additive-ish glow (three concentric halos)
	if muzzle_t > 0.0:
		var flash_pos: Vector2 = barrel_end + aim_dir * 3.0
		var m := muzzle_t
		node.draw_circle(flash_pos, 3.0 + m * 30.0, Color(1.0, 0.45, 0.15, m * 0.35))
		node.draw_circle(flash_pos, 2.4 + m * 22.0, Color(1.0, 0.8, 0.35, m * 0.6))
		node.draw_circle(flash_pos, 1.6 + m * 14.0, Color(1.0, 1.0, 0.7, m * 0.85))

	# HP + optional fuel bar (kept above the head).
	node.draw_rect(Rect2(-16.0, HP_BAR_Y, 32.0, 4.0), Color(0.0, 0.0, 0.0, 0.55))
	node.draw_rect(Rect2(-16.0, HP_BAR_Y, 32.0 * clampf(health / 100.0, 0.0, 1.0), 4.0), Color(0.9, 0.2, 0.2))
	if show_fuel:
		node.draw_rect(Rect2(-16.0, HP_BAR_Y + 5.0, 32.0, 3.0), Color(0.0, 0.0, 0.0, 0.55))
		node.draw_rect(Rect2(-16.0, HP_BAR_Y + 5.0, 32.0 * clampf(fuel / 100.0, 0.0, 1.0), 3.0), Color(0.3, 0.7, 1.0))


static func _draw_jet_flame(node: CanvasItem, facing: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	# Origin is behind the pack.
	var origin: Vector2 = Vector2(-facing * 8.0, 3.0)
	var length := 22.0 + sin(t * 26.0) * 4.5
	var wobble := cos(t * 18.0) * 1.2
	var w0 := 5.0 + wobble
	var w1 := 3.4 + wobble * 0.7
	var w2 := 1.9

	# Outer red-orange cone (transparent tip)
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
	# Mid orange cone
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
	# Inner yellow-white core
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
