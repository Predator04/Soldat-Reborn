extends Node
## Main's map world (#258 split of main.gd): the per-map world rect, sky,
## parallax, weather, terrain bodies (platforms, polygons, ladders, scenery),
## graphics layers (gfx.gd), the plain-geometry placement queries (no physics
## space needed) and the kill-line / anti-stuck watchdog.
##
## MAP_W / MAP_H / GROUND_Y / KILL_Y and the solid-geometry index stay on Main;
## bots, flags and spawns query them through Main.

const Main = preload("res://scripts/main.gd")
const MapIO = preload("res://scripts/map_io.gd")

var main: Main

# Anti-stuck watchdog (see _tick_soldier_safety).
const STUCK_CHECK_HZ := 8.0
const STUCK_GRACE := 0.35          # seconds embedded before we nudge a soldier out
var _safety_cd := 0.0
# Player-solid terrain as plain geometry ({"r": Rect2 AABB, "pts": polygon}) so
# spawn/flag placement can test the map without waiting for the physics space.
var _solid_geo: Array = []
# Collision layers for terrain classes (ported Soldat polygon types):
#   layer 1 (bit 1) — normal terrain: soldiers, bullets, pickups all collide.
#   layer 2 (bit 2) — "only bullets" polys: bullets/rockets/grenades mask it,
#                     soldiers don't, so players walk through.
#   layer 3 (bit 4) — "only players" polys: soldiers mask it, bullets don't.
const TERRAIN_LAYER_BULLETS_ONLY := 2
const TERRAIN_LAYER_PLAYERS_ONLY := 4
# Column index over _solid_geo: bots probe ground/pits several times per tick,
# and scanning ~200-3000 pieces each time cost milliseconds per frame.
const GEO_COL_W := 32.0
var _geo_cols: Array = []
# Level → z_index for ported .pms scenery. 0=back (behind terrain),
# 1=middle (in front of terrain but tree-ordered behind soldiers spawned
# later at z=0), 2=front (drawn above soldiers).
const _SCENERY_LEVEL_Z := {0: -3, 1: 0, 2: 5}
var _soft_blank: Texture2D = null
# #283: every drawn terrain polygon / platform with its classic colour data
# (points, vertex colours, texture + tile UVs)
# and the classic nodes that draw it — scripts/gfx/terrain_hd.gd redraws them
# in the cinematic look (and hides these nodes meanwhile).
var _hd_items: Array = []


func _apply_world() -> void:
	# Pull the per-map world rect (ported maps) or fall back to the built-in arena.
	var w: Dictionary = main._map.get("world", {}) if typeof(main._map.get("world", {})) == TYPE_DICTIONARY else {}
	# #236: clamp regardless of source — map_io sanitizes saved/hosted JSON, but
	# _geo_candidates sizes the collision index from these and must never see a
	# giant or negative value (host-sent custom maps, hand-edited files).
	main.MAP_W = clampf(float(w.get("w", main.DEFAULT_MAP_W)), MapIO.WORLD_MIN, MapIO.WORLD_MAX)
	main.MAP_H = clampf(float(w.get("h", main.DEFAULT_MAP_H)), MapIO.WORLD_MIN, MapIO.WORLD_MAX)
	main.GROUND_Y = clampf(float(w.get("ground_y", main.DEFAULT_GROUND_Y)), 50.0, main.MAP_H)
	var ky := float(w.get("kill_y", INF))
	main.KILL_Y = ky if (ky > 0.0 and is_finite(ky)) else INF


# Sky + parallax are built by scripts/gfx/atmosphere.gd (#270; Classic look
# uses sky.gd / parallax.gd from there).


# Per-map weather (#68). Reads _map["weather"] ("rain"/"snow" or ""). Renders as
# a CPUParticles2D anchored to the camera so a single emitter covers the visible
# region no matter how far the player travels. Skipped under Settings.lofi to
# stay consistent with the rest of the particle stack.
func _build_weather() -> void:
	var kind: String = str(main._map.get("weather", "")).strip_edges().to_lower()
	# Sound bed plays even in Lo-fi (it's the particles that cost).
	Sfx.ambience(kind)
	if not main.tree_exiting.is_connected(_stop_ambience):
		main.tree_exiting.connect(_stop_ambience)
	if kind == "" or Settings.lofi:
		return
	var host := Node2D.new()
	host.name = "Weather"
	# We update the host position each frame from the camera; script inline via
	# a lambda-driven Node2D would be awkward, so use a wrapper method below.
	main.add_child(host)
	var p := CPUParticles2D.new()
	p.name = "WeatherFX"
	# Wide emission line above the camera; particles fall/drift down into view.
	# Sized generously so a quick camera pan doesn't outrun the emitter edge.
	var view := main.get_viewport().get_visible_rect().size
	var band_w: float = maxf(view.x + 400.0, 1600.0)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(band_w * 0.5, 8.0)
	p.one_shot = false
	p.local_coords = false
	if kind == "snow":
		# Slow, drifty flakes with visible horizontal sway.
		p.amount = 220
		p.lifetime = 8.0
		p.direction = Vector2(0, 1)
		p.gravity = Vector2(0, 40)
		p.initial_velocity_min = 30.0
		p.initial_velocity_max = 60.0
		p.spread = 12.0
		p.angular_velocity_min = -25.0
		p.angular_velocity_max = 25.0
		p.scale_amount_min = 1.4
		p.scale_amount_max = 2.6
		p.color = Color(0.94, 0.96, 1.0, 0.85)
		# Sinusoidal x-sway via tangential accel gives snow its side-to-side drift.
		p.tangential_accel_min = -18.0
		p.tangential_accel_max = 18.0
	else:
		# Rain — thin fast streaks straight down.
		p.amount = 380
		p.lifetime = 1.2
		p.direction = Vector2(0.08, 1)
		p.gravity = Vector2(0, 900)
		p.initial_velocity_min = 900.0
		p.initial_velocity_max = 1100.0
		p.spread = 3.0
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.4
		p.color = Color(0.75, 0.85, 1.0, 0.55)
	p.emitting = true
	# Draw over terrain but under HUD.
	p.z_index = 90
	# Rain is a single vertical pixel-tall streak; snow uses a small circle.
	# CPUParticles2D without a texture draws a small dot — good enough for both.
	host.add_child(p)
	# Follow the camera each frame — a stub node with a script is overkill, so
	# reuse a timer + method on Main. Godot doesn't provide a per-node "process"
	# hook without a script, so we add a lightweight one inline.
	var follower := Node.new()
	follower.name = "WeatherFollow"
	follower.set_script(preload("res://scripts/weather_follow.gd"))
	follower.set("host_path", host.get_path())
	follower.set("band_w", band_w)
	host.add_child(follower)


func _stop_ambience() -> void:
	Sfx.ambience("")


func _make_platform(pos: Vector2, size: Vector2, col: Color, tex_path: String = "") -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = pos
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	var vis := Polygon2D.new()
	var poly := PackedVector2Array([
		Vector2(-size.x / 2.0, -size.y / 2.0),
		Vector2(size.x / 2.0, -size.y / 2.0),
		Vector2(size.x / 2.0, size.y / 2.0),
		Vector2(-size.x / 2.0, size.y / 2.0),
	])
	vis.polygon = poly
	vis.color = col
	if tex_path != "" and ResourceLoader.exists(tex_path):
		var tex: Texture2D = load(tex_path) as Texture2D
		if tex != null:
			vis.texture = tex
			vis.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
			# #112: explicit UVs = polygon coords + half-size so the texture starts
			# at (0,0) in the top-left and tiles at 1 world-pixel per texture-pixel.
			# Polygon2D falls back to (0,0)-mapped UVs when uv is empty, which
			# stretches one tile across the whole platform — invisible on a
			# 5000-pixel-wide baseline floor. Modulate stays at pure white so the
			# tiled grass/rock reads at full contrast against the sky.
			var uvs := PackedVector2Array()
			for p in poly:
				uvs.append(p + size * 0.5)
			vis.uv = uvs
			vis.color = Color(1, 1, 1, 1)
	body.add_child(vis)
	# Bevel trim: bright lip on the walkable top edge, dark underside — reads
	# as a solid ledge instead of a flat coloured box. Skipped on the huge
	# baseline floor/walls (size > 1000) where it'd just be a hairline.
	if size.x <= 1000.0 and size.y <= 1000.0 and size.y >= 6.0:
		var hx := size.x * 0.5
		var hy := size.y * 0.5
		var lip := Line2D.new()
		lip.width = 3.0
		lip.default_color = Color(1, 1, 1, 0.28)
		lip.points = PackedVector2Array([Vector2(-hx, -hy + 1.5), Vector2(hx, -hy + 1.5)])
		body.add_child(lip)
		var under := Line2D.new()
		under.width = 3.0
		under.default_color = Color(0, 0, 0, 0.45)
		under.points = PackedVector2Array([Vector2(-hx, hy - 1.5), Vector2(hx, hy - 1.5)])
		body.add_child(under)
		var sides := Line2D.new()
		sides.width = 2.0
		sides.default_color = Color(0, 0, 0, 0.35)
		sides.closed = true
		sides.points = poly
		body.add_child(sides)
	main.add_child(body)
	return body


func _make_polygon_body(points: PackedVector2Array, col: Color, tex_path: String = "",
		uvs_norm: PackedVector2Array = PackedVector2Array(), draw_outline: bool = true,
		col_class: int = 0, vcols: PackedColorArray = PackedColorArray()) -> Node2D:
	# World-space polygon terrain. Enables hills / mountains / tunnel walls
	# without stacking dozens of small rectangles. `uvs_norm` are tile-space
	# UVs (from the .pms) that get scaled by texture size for tiled sampling.
	# col_class: 0 solid, 1 bullets only, 2 players only, 3 decorative (no body).
	if points.size() < 3:
		return null
	var body: Node2D
	if col_class == 3:
		body = Node2D.new()
	else:
		var sb := StaticBody2D.new()
		if col_class == 1:
			sb.collision_layer = TERRAIN_LAYER_BULLETS_ONLY
		elif col_class == 2:
			sb.collision_layer = TERRAIN_LAYER_PLAYERS_ONLY
		sb.collision_mask = 0
		var col_poly := CollisionPolygon2D.new()
		col_poly.polygon = points
		sb.add_child(col_poly)
		body = sb
	body.position = Vector2.ZERO
	var vis := Polygon2D.new()
	vis.polygon = points
	vis.color = col
	var textured := false
	if tex_path != "" and ResourceLoader.exists(tex_path):
		var tex: Texture2D = load(tex_path) as Texture2D
		if tex != null:
			vis.texture = tex
			vis.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
			if uvs_norm.size() == points.size():
				# Ported .pms map: tile-space UVs. Multiply by texture size so
				# Godot samples at the same density Soldat did.
				var ts := tex.get_size()
				var uv_px := PackedVector2Array()
				for uv in uvs_norm:
					uv_px.append(Vector2(uv.x * ts.x, uv.y * ts.y))
				vis.uv = uv_px
			else:
				# #112: procedural remake maps (Ascent/Towers/Pillars) don't carry
				# per-vertex UVs. Polygon2D with an empty uv array stretches ONE
				# texture across the whole polygon, so a 1000×200 hill shows a
				# single blurry pixel of grass instead of tiling. Generate UVs
				# from world-space vertex positions so the texture repeats at its
				# native size (1 world pixel = 1 texture pixel).
				var uv_px := PackedVector2Array()
				for pt in points:
					uv_px.append(pt)
				vis.uv = uv_px
			# Pure-white modulate so the tiled texture reads at full contrast
			# instead of getting washed toward the fallback terrain_color.
			vis.color = Color(1, 1, 1, 1)
			textured = true
	# Soldat's per-vertex colours carry all of a classic map's shading (dark
	# caves, sunlit ridges, tinted water). Without them every map looked flat.
	if vcols.size() == points.size():
		vis.vertex_colors = vcols
	body.add_child(vis)
	if draw_outline:
		# Subtle darkened top-edge outline so hills read against the sky at distance.
		var outline := Line2D.new()
		outline.width = 3.0
		outline.default_color = col.darkened(0.4) if not textured else Color(0, 0, 0, 0.35)
		outline.antialiased = true
		var ridge := PackedVector2Array()
		for p in points:
			ridge.append(p)
		outline.points = ridge
		body.add_child(outline)
	main.add_child(body)
	return body


func _build_gfx_world() -> void:
	if Net.is_dedicated:
		return
	main.terrain_fx = Node2D.new()
	main.terrain_fx.name = "TerrainFX"
	main.terrain_fx.set_script(preload("res://scripts/terrain_fx.gd"))
	var outlines: Array = []
	var pieces: Array = []
	var tris: Array = []
	var default_col: Color = main._map.get("terrain_color", Color(0.24, 0.28, 0.34))
	var default_tex: String = str(main._map.get("terrain_texture", ""))
	var has_coll: bool = main._map.has("collision") and typeof(main._map["collision"]) == TYPE_ARRAY and not (main._map["collision"] as Array).is_empty()
	for poly in main._map.get("polys", []):
		var pts: PackedVector2Array = poly.get("points", PackedVector2Array())
		if pts.size() < 3:
			continue
		var cc := int(poly.get("col", 0))
		var tex := str(poly.get("texture", default_tex))
		var textured := tex != "" and ResourceLoader.exists(tex)
		tris.append({"pts": pts, "tex": tex if textured else "", "uvs": poly.get("uvs", PackedVector2Array()),
			"vc": poly.get("vc", PackedColorArray()), "col": Color.WHITE if textured else (poly.get("color", default_col) as Color)})
		if not has_coll and (cc == 0 or cc == 2):
			pieces.append(pts)
	if has_coll:
		for c in main._map["collision"]:
			var ccl := int(c.get("col", 0))
			# Maker props (#286: crates, sandbags) are drawn by their sprite —
			# no grass lip / rim along them.
			if (ccl == 0 or ccl == 2) and not bool(c.get("prop", false)):
				pieces.append(c["points"])   # convex pieces: shared edges dropped
	var plat_tex: String = str(main._map.get("platform_texture", default_tex))
	for pl in main._map.get("platforms", []):
		var hs: Vector2 = (pl["s"] as Vector2) * 0.5
		var pc: Vector2 = pl["p"]
		var rect := PackedVector2Array([pc + Vector2(-hs.x, -hs.y), pc + Vector2(hs.x, -hs.y), pc + Vector2(hs.x, hs.y), pc + Vector2(-hs.x, hs.y)])
		pieces.append(rect)
		tris.append({"pts": rect, "tex": plat_tex if ResourceLoader.exists(plat_tex) else "", "uvs": PackedVector2Array(), "vc": PackedColorArray(), "col": Color(0.82, 0.8, 0.78)})
	var world_cfg: Dictionary = main._map.get("world", {}) if typeof(main._map.get("world", {})) == TYPE_DICTIONARY else {}
	if bool(world_cfg.get("floor_visible", true)):
		var fl := PackedVector2Array([Vector2(-100, main.GROUND_Y), Vector2(main.MAP_W + 100, main.GROUND_Y), Vector2(main.MAP_W + 100, main.GROUND_Y + 200), Vector2(-100, main.GROUND_Y + 200)])
		pieces.append(fl)
		var ftex := str(main._map.get("floor_texture", ""))
		tris.append({"pts": fl, "tex": ftex if ResourceLoader.exists(ftex) else "", "uvs": PackedVector2Array(), "vc": PackedColorArray(), "col": Color(0.22, 0.26, 0.32) if not ResourceLoader.exists(ftex) else Color.WHITE})
	main.terrain_fx.set("outlines", outlines)
	main.terrain_fx.set("pieces", pieces)
	main.terrain_fx.set("tris", tris)
	main.add_child(main.terrain_fx)
	if preload("res://scripts/gfx.gd").on(preload("res://scripts/gfx.gd").MEDIUM):
		main.terrain_fx.build()
	# #283: HD materials + painted edges (cinematic look, Medium+; draws
	# nothing otherwise).
	var hd: Node2D = preload("res://scripts/gfx/terrain_hd.gd").new()
	hd.name = "TerrainHD"
	hd.setup(main, _hd_items, pieces)
	main.add_child(hd)
	main.soldier_shadows = Node2D.new()
	main.soldier_shadows.name = "SoldierShadows"
	main.soldier_shadows.set_script(preload("res://scripts/soldier_shadows.gd"))
	main.add_child(main.soldier_shadows)
	# Phase B (#271): pooled combat FX (decals / back layer before any soldier,
	# so blood and debris sit behind them) + screen feel (shake, hit-stop).
	FxWorld.ensure(main)
	ScreenFeel.install(main)
	# #306: ally chevrons / names + the viewer's team for the team outlines.
	var tm: Node2D = preload("res://scripts/gfx/team_markers.gd").new()
	tm.main = main
	main.add_child(tm)
	_build_ambient_fx()


## Floating motes around the camera (High): dust in daylight, warm sparks
## at night. Follows the camera via weather_follow-style re-centering.
func _build_ambient_fx() -> void:
	var G = preload("res://scripts/gfx.gd")
	main.ambient_fx = CPUParticles2D.new()
	main.ambient_fx.name = "AmbientFX"
	main.ambient_fx.amount = 46
	main.ambient_fx.lifetime = 7.0
	main.ambient_fx.preprocess = 7.0
	main.ambient_fx.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	main.ambient_fx.emission_rect_extents = Vector2(900, 500)
	main.ambient_fx.gravity = Vector2(0, -4)
	main.ambient_fx.direction = Vector2(1, -0.2)
	main.ambient_fx.spread = 60.0
	main.ambient_fx.initial_velocity_min = 4.0
	main.ambient_fx.initial_velocity_max = 16.0
	main.ambient_fx.scale_amount_min = 1.0
	main.ambient_fx.scale_amount_max = 2.4
	main.ambient_fx.texture = G.soft_tex()
	main.ambient_fx.scale_amount_min = 0.05
	main.ambient_fx.scale_amount_max = 0.11
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	var night := _is_night_map()
	var mc := Color(1.0, 0.8, 0.45) if night else Color(1.0, 1.0, 0.95)
	ramp.colors = PackedColorArray([Color(mc, 0.0), Color(mc, 0.55 if night else 0.35), Color(mc, 0.45 if night else 0.3), Color(mc, 0.0)])
	main.ambient_fx.color_ramp = ramp
	main.ambient_fx.material = G.add_mat()
	main.ambient_fx.z_index = 70
	main.ambient_fx.local_coords = false
	main.add_child(main.ambient_fx)
	main.ambient_fx.emitting = G.on(G.HIGH)


func _is_night_map() -> bool:
	var sky_cfg: Variant = main._map.get("sky", {})
	if typeof(sky_cfg) == TYPE_DICTIONARY and (sky_cfg as Dictionary).has("top"):
		var c := main._arr_to_color((sky_cfg as Dictionary)["top"])
		return c.get_luminance() < 0.22
	return str(main._map.get("name", "")).to_lower().contains("night")


func _tick_ambient_fx() -> void:
	if main.ambient_fx == null or not main.ambient_fx.emitting:
		return
	var cam := main.get_viewport().get_camera_2d()
	if cam != null:
		main.ambient_fx.global_position = cam.get_screen_center_position()


## Settings → Graphics quality changed mid-match.
func apply_gfx_quality() -> void:
	var G = preload("res://scripts/gfx.gd")
	if main.hud != null and main.hud.has_method("apply_gfx_quality"):
		main.hud.apply_gfx_quality()
	if main.terrain_fx != null:
		for c in main.terrain_fx.get_children():
			c.queue_free()
		main.terrain_fx.set("edges_built", 0)
		main.terrain_fx.set("grass_blades", 0)
		if G.on(G.MEDIUM):
			main.terrain_fx.build()
	if main.ambient_fx != null:
		main.ambient_fx.emitting = G.on(G.HIGH)
	FxWorld.reconfigure()


func _build_terrain() -> void:
	# Baseline floor + side walls always present so maps can rely on them.
	# The floor slab's TOP edge sits exactly at GROUND_Y (it used to be centred
	# on it, which put the walkable surface 100 px higher than every map, the
	# editor and map_gen assumed — sealing the built-in tunnels shut and burying
	# the bottom rows of every ported map).
	var floor_tex: String = str(main._map.get("floor_texture", ""))
	var world_cfg: Dictionary = main._map.get("world", {}) if typeof(main._map.get("world", {})) == TYPE_DICTIONARY else {}
	var floor_body := _make_platform(Vector2(main.MAP_W / 2.0, main.GROUND_Y + 100.0), Vector2(main.MAP_W + 200, 200), Color(0.22, 0.26, 0.32), floor_tex)
	_solid_geo.clear()
	_hd_items.clear()
	if bool(world_cfg.get("floor_visible", true)):
		_hd_register_platform(floor_body, Vector2(main.MAP_W / 2.0, main.GROUND_Y + 100.0), Vector2(main.MAP_W + 200, 200), Color(0.22, 0.26, 0.32), floor_tex, Color.WHITE)
	_register_solid(PackedVector2Array([Vector2(-100, main.GROUND_Y), Vector2(main.MAP_W + 100, main.GROUND_Y),
		Vector2(main.MAP_W + 100, main.GROUND_Y + 200), Vector2(-100, main.GROUND_Y + 200)]))
	if not bool(world_cfg.get("floor_visible", true)):
		# Ported maps: the floor only exists as a safety net below the kill line.
		for c in floor_body.get_children():
			if c is CanvasItem:
				(c as CanvasItem).visible = false
	# Optional polygon terrain (hills / mountains / tunnel walls). Each entry is
	# { "points": PackedVector2Array } with optional "color" and "texture".
	var default_terrain_col: Color = main._map.get("terrain_color", Color(0.24, 0.28, 0.34))
	var default_terrain_tex: String = str(main._map.get("terrain_texture", ""))
	# Ported .pms maps ship per-vertex UVs so we can suppress the sky-ridge outline
	# (which was there to give flat-color hills contrast) and let the tiled
	# texture carry the visual weight.
	var has_uvs := false
	var has_coll: bool = main._map.has("collision") and typeof(main._map["collision"]) == TYPE_ARRAY \
			and not (main._map["collision"] as Array).is_empty()
	for poly in main._map.get("polys", []):
		var pts: PackedVector2Array = poly.get("points", PackedVector2Array())
		var pc: Color = poly.get("color", default_terrain_col)
		var pt: String = str(poly.get("texture", default_terrain_tex))
		var uvs: PackedVector2Array = poly.get("uvs", PackedVector2Array())
		var draw_outline := uvs.size() != pts.size()
		if not draw_outline:
			has_uvs = true
		var vcols: PackedColorArray = poly.get("vc", PackedColorArray())
		var cc := int(poly.get("col", 0))
		# With merged collision outlines the triangles are drawn only.
		var pbody := _make_polygon_body(pts, pc, pt, uvs, draw_outline, 3 if has_coll else cc, vcols)
		if pbody != null:
			_hd_items.append({"nodes": _canvas_children(pbody), "pts": pts, "vc": vcols, "col": pc, "tex": pt, "cc": cc, "uvs": uvs})
		if not has_coll and pts.size() >= 3 and (cc == 0 or cc == 2):
			_register_solid(pts)
	# Ported maps: physics from merged, seam-free outlines (tools/pms_to_map.py
	# build_collision) so soldiers don't snag on the joins between triangles.
	if has_coll:
		for c in main._map["collision"]:
			var cpts: PackedVector2Array = c["points"]
			var ccl := int(c.get("col", 0))
			var sb := StaticBody2D.new()
			if ccl == 1:
				sb.collision_layer = TERRAIN_LAYER_BULLETS_ONLY
			elif ccl == 2:
				sb.collision_layer = TERRAIN_LAYER_PLAYERS_ONLY
			sb.collision_mask = 0
			var cp := CollisionPolygon2D.new()
			cp.polygon = cpts
			sb.add_child(cp)
			main.add_child(sb)
			if ccl == 0 or ccl == 2:
				_register_solid(cpts)
	# Legacy rectangular platforms: textured with the map's terrain (slightly
	# darkened so they read as man-made ledges) instead of a flat grey box.
	var plat_tex: String = str(main._map.get("platform_texture", default_terrain_tex))
	for pl in main._map["platforms"]:
		var pb := _make_platform(pl["p"], pl["s"], Color(0.28, 0.32, 0.4), plat_tex)
		var hs: Vector2 = (pl["s"] as Vector2) * 0.5
		var pc2: Vector2 = pl["p"]
		_register_solid(PackedVector2Array([pc2 + Vector2(-hs.x, -hs.y), pc2 + Vector2(hs.x, -hs.y),
			pc2 + Vector2(hs.x, hs.y), pc2 + Vector2(-hs.x, hs.y)]))
		for c in pb.get_children():
			if c is Polygon2D and (c as Polygon2D).texture != null:
				(c as Polygon2D).color = Color(0.82, 0.8, 0.78, 1.0)
		_hd_register_platform(pb, pl["p"], pl["s"], Color(0.28, 0.32, 0.4), plat_tex, Color(0.82, 0.8, 0.78, 1.0))
	var wall_l := _make_platform(Vector2(0, main.MAP_H / 2.0), Vector2(40, main.MAP_H * 2.0), Color(0.2, 0.23, 0.28))
	var wall_r := _make_platform(Vector2(main.MAP_W, main.MAP_H / 2.0), Vector2(40, main.MAP_H * 2.0), Color(0.2, 0.23, 0.28))
	if not bool(world_cfg.get("floor_visible", true)):
		for wb in [wall_l, wall_r]:
			for c in wb.get_children():
				if c is CanvasItem:
					(c as CanvasItem).visible = false
	else:
		_hd_register_platform(wall_l, Vector2(0, main.MAP_H / 2.0), Vector2(40, main.MAP_H * 2.0), Color(0.2, 0.23, 0.28), "", Color.WHITE)
		_hd_register_platform(wall_r, Vector2(main.MAP_W, main.MAP_H / 2.0), Vector2(40, main.MAP_H * 2.0), Color(0.2, 0.23, 0.28), "", Color.WHITE)
	# Ladders — climbable Area2D regions (see player.gd's climbing state).
	for ld in main._map.get("ladders", []):
		_make_ladder(float(ld.get("x", 0.0)), float(ld.get("y", 0.0)),
			float(ld.get("w", 20.0)), float(ld.get("h", 120.0)))
	_spawn_scenery()
	_spawn_scenery_hints()
	main._vehicles_sys._spawn_m2_mounts()
	main._bonuses._spawn_map_weapon_pickups()


func _canvas_children(n: Node) -> Array:
	# Visuals only (never the collision shapes, which are Node2Ds too).
	var out: Array = []
	for c in n.get_children():
		if c is Polygon2D or c is Line2D:
			out.append(c)
	return out


## #283: a rectangle body made by _make_platform, for terrain_hd.gd. `mod` is
## the node colour the classic path multiplies a texture with.
func _hd_register_platform(body: Node, pos: Vector2, size: Vector2, col: Color, tex: String, mod: Color) -> void:
	var h := size * 0.5
	_hd_items.append({"nodes": _canvas_children(body), "cc": 0, "col": col, "tex": tex, "mod": mod,
		"vc": PackedColorArray(), "pts": PackedVector2Array([pos + Vector2(-h.x, -h.y), pos + Vector2(h.x, -h.y),
		pos + Vector2(h.x, h.y), pos + Vector2(-h.x, h.y)])})


func _register_solid(pts: PackedVector2Array) -> void:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	_solid_geo.append({"r": r, "pts": pts})
	_geo_cols.clear()  # rebuild the column index lazily


func _geo_candidates(x: float) -> PackedInt32Array:
	if _geo_cols.is_empty():
		var n := int(ceil((main.MAP_W + 400.0) / GEO_COL_W)) + 1
		# #236: hard cap — the index is sized from map data, never trust it alone.
		n = mini(n, 8192)
		_geo_cols.resize(n)
		for i in n:
			_geo_cols[i] = PackedInt32Array()
		for gi in _solid_geo.size():
			var rr: Rect2 = _solid_geo[gi]["r"]
			var c0 := clampi(int((rr.position.x + 200.0) / GEO_COL_W), 0, n - 1)
			var c1 := clampi(int((rr.end.x + 200.0) / GEO_COL_W), 0, n - 1)
			for c in range(c0, c1 + 1):
				# Packed arrays are value types: append to a local and store it
				# back (appending through the cast silently edited a copy).
				var col: PackedInt32Array = _geo_cols[c]
				col.append(gi)
				_geo_cols[c] = col
	return _geo_cols[clampi(int((x + 200.0) / GEO_COL_W), 0, _geo_cols.size() - 1)]


func _point_in_solid(p: Vector2) -> bool:
	if p.x <= 20.0 or p.x >= main.MAP_W - 20.0:
		return true  # inside a side wall
	for gi in _geo_candidates(p.x):
		var g: Dictionary = _solid_geo[gi]
		var r: Rect2 = g["r"]
		if p.x < r.position.x or p.x > r.end.x or p.y < r.position.y or p.y > r.end.y:
			continue
		if Geometry2D.is_point_in_polygon(p, g["pts"]):
			return true
	return false


func _spot_is_clear(feet: Vector2) -> bool:
	# Sample a soldier's standing box (14×24, feet-anchored) — edges + middle.
	for off in [Vector2(-6, -2), Vector2(6, -2), Vector2(0, -12), Vector2(-6, -22), Vector2(6, -22), Vector2(0, -23)]:
		if _point_in_solid(feet + off):
			return false
	return true


func _geom_ground_y(x: float, from_y: float) -> float:
	# Highest solid surface at column x at or below from_y (INF if none).
	var best := INF
	for gi in _geo_candidates(x):
		var g: Dictionary = _solid_geo[gi]
		var r: Rect2 = g["r"]
		if x < r.position.x or x > r.end.x or r.end.y < from_y:
			continue
		var pts: PackedVector2Array = g["pts"]
		var n := pts.size()
		for i in n:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % n]
			if (a.x <= x and b.x >= x) or (b.x <= x and a.x >= x):
				var y: float
				if absf(b.x - a.x) < 0.001:
					y = minf(a.y, b.y)
				else:
					y = lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))
				if y >= from_y and y < best:
					best = y
	return best


func _settle_on_ground(pos: Vector2) -> Vector2:
	# Drop a map object (flag base, capture point) straight down onto the first
	# surface. If it starts buried, first lift it out (up to 400 px).
	var p := pos
	var lift := 0.0
	while _point_in_solid(p + Vector2(0, -2)) and lift < 1200.0:
		p.y -= 4.0
		lift += 4.0
	var gy := _geom_ground_y(p.x, p.y - 2.0)
	if gy == INF or gy > main.KILL_Y:
		return pos
	return Vector2(p.x, gy)


func _find_free_spot_near(feet: Vector2, max_r: float = 240.0) -> Vector2:
	# Nearest spot (upward first, then outward rings) where a standing soldier fits.
	if _spot_is_clear(feet):
		return feet
	var step := 6.0
	var r := step
	while r <= max_r:
		for off in [Vector2(0, -r), Vector2(-r, -r * 0.5), Vector2(r, -r * 0.5), Vector2(-r, 0),
				Vector2(r, 0), Vector2(0, r), Vector2(-r, -r), Vector2(r, -r)]:
			var c: Vector2 = feet + off
			if c.x < 30.0 or c.x > main.MAP_W - 30.0:
				continue
			if _spot_is_clear(c):
				return c
		r += step
	return feet


func _tick_soldier_safety(delta: float) -> void:
	# Runs on every peer for the soldiers THIS peer is authoritative over
	# (own player on clients; everyone incl. bots on host / single-player).
	# 1) Fell off a ported map (below the kill line) → dies, like Soldat.
	# 2) Somehow embedded in terrain for > STUCK_GRACE s (explosion shove,
	#    stance change under a low ceiling, spawning into a moved prop…) →
	#    nudged to the nearest free spot so nobody is ever trapped.
	_safety_cd -= delta
	if _safety_cd > 0.0:
		return
	var dt := 1.0 / STUCK_CHECK_HZ
	_safety_cd = dt
	var space := main.get_world_2d().direct_space_state
	# Dropped weapons / the Rambo bow that fall off a ported map would sit on
	# the hidden safety floor forever. Host (or SP) cleans them up; the bow
	# goes back to its spawn so Rambomatch can continue.
	if main.KILL_Y != INF and (not Net.is_networked() or Net.is_host()):
		for wp in main.get_tree().get_nodes_in_group("weapon_pickup"):
			if not is_instance_valid(wp) or (wp as Node2D).global_position.y <= main.KILL_Y:
				continue
			if wp.has_meta("rambo_spawn"):
				var ground_y: float = float(main._map.get("ctf_ground_y", main.GROUND_Y))
				(wp as Node2D).global_position = main._map.get("rambo_pos", Vector2(main.MAP_W * 0.5, ground_y - 40.0))
				if wp is RigidBody2D:
					(wp as RigidBody2D).linear_velocity = Vector2.ZERO
			else:
				wp.queue_free()
	for s in main.get_tree().get_nodes_in_group("soldier"):
		if not is_instance_valid(s) or bool(s.get("dead")) or not (s is CharacterBody2D):
			continue
		if main.multiplayer.multiplayer_peer != null and not s.is_multiplayer_authority():
			continue
		var body := s as CharacterBody2D
		if body.global_position.y > main.KILL_Y:
			if s.has_method("take_damage"):
				s.set("ceasefire_t", 0.0)
				s.take_damage(9999.0, str(s.get("display_name")), "Fell", int(s.get("team")))
				main.safety_stats["fell"] = int(main.safety_stats["fell"]) + 1
				if OS.get_cmdline_user_args().has("--log-falls"):
					print("[fell] %s from x=%d goal=%s" % [s.get("display_name"), int(body.global_position.x), str(s.get("_goal_label"))])
			continue
		if s.get("mounted_m2") != null or bool(s.get("climbing")):
			main._stuck_time.erase(s.get_instance_id())
			continue
		var cs: CollisionShape2D = null
		for c in body.get_children():
			if c is CollisionShape2D:
				cs = c
				break
		if cs == null or cs.shape == null:
			continue
		var q := PhysicsShapeQueryParameters2D.new()
		q.shape = cs.shape
		q.transform = cs.global_transform
		q.collision_mask = body.collision_mask
		q.collide_with_bodies = true
		q.collide_with_areas = false
		q.exclude = [body.get_rid()]
		q.margin = -1.5  # ignore resting contact — only real overlap counts
		var embedded := false
		for hit in space.intersect_shape(q, 4):
			if hit.get("collider") is StaticBody2D:
				embedded = true
				break
		var id := s.get_instance_id()
		if not embedded:
			main._stuck_time.erase(id)
			continue
		main._stuck_time[id] = float(main._stuck_time.get(id, 0.0)) + dt
		if float(main._stuck_time[id]) >= STUCK_GRACE:
			main._stuck_time.erase(id)
			var to := _find_free_spot_near(body.global_position)
			if to != body.global_position:
				if OS.is_debug_build():
					print("[anti-stuck] freed %s at %s -> %s" % [s.get("display_name"), body.global_position, to])
				body.global_position = to
				body.velocity = Vector2.ZERO
				main.safety_stats["unstuck"] = int(main.safety_stats["unstuck"]) + 1


func _make_ladder(x: float, y: float, w: float, h: float) -> Area2D:
	# Ladder = non-collidable Area2D on the "ladder" group. player.gd polls
	# get_overlapping_areas() each physics frame to detect climb availability.
	# `center_x` is stashed on the area for the player's x-snap while climbing.
	var area := Area2D.new()
	area.add_to_group("ladder")
	area.position = Vector2(x + w * 0.5, y + h * 0.5)
	area.set_meta("center_x", area.position.x)
	area.set_meta("top_y", y)
	area.set_meta("bottom_y", y + h)
	area.set_meta("half_w", w * 0.5)
	area.set_meta("half_h", h * 0.5)
	# Only detect Area2D overlaps against the player's own ladder-probe Area2D
	# so soldiers don't drag physics bodies into the area's contact list.
	area.monitorable = true
	area.monitoring = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(w, h)
	shape.shape = rect
	area.add_child(shape)
	# Cheap _draw-style visual: two vertical rails + rungs every ~20px.
	var vis := _LadderVisual.new()
	vis.width = w
	vis.height = h
	area.add_child(vis)
	main.add_child(area)
	return area


func _spawn_scenery() -> void:
	# Non-collidable decorative sprites (trees / rocks / etc.). Each entry is
	# { "tex": res_path, "pos": Vector2, optional "scale": float, "mod": Color }.
	var items: Array = main._map.get("scenery", [])
	if items.is_empty():
		return
	for it in items:
		var path: String = str(it.get("tex", ""))
		if path == "" or not ResourceLoader.exists(path):
			continue
		var tex: Texture2D = load(path) as Texture2D
		if tex == null:
			continue
		var s := Sprite2D.new()
		s.texture = tex
		s.position = it.get("pos", Vector2.ZERO)
		s.scale = Vector2.ONE * float(it.get("scale", 1.0))
		s.modulate = it.get("mod", Color(1, 1, 1, 1))
		s.z_index = int(it.get("z", -2))
		main.add_child(s)


func _spawn_scenery_hints() -> void:
	# Ported .pms maps carry a `_scenery_hints` array holding the original
	# prop list: sprite name + world pos/scale/rot/alpha/level. Resolves each
	# name to res://assets/scenery/<stem>.png.
	var items: Array = main._map.get("_scenery_hints", [])
	if items.is_empty():
		return
	# Sprites need to grow with the map's port-time scale so they stay in
	# proportion to terrain (both scaled together during .pms → JSON).
	var map_scale := float((main._map.get("_source", {}) as Dictionary).get("scale", 1.0))
	for it in items:
		var raw_name: String = str(it.get("name", ""))
		if raw_name == "":
			continue
		var stem := raw_name.get_basename().to_lower()
		var path := "res://assets/scenery/%s.png" % stem
		if not ResourceLoader.exists(path):
			continue
		var tex: Texture2D = load(path) as Texture2D
		if stem == "blank":
			# Soldat maps tint "blank" squares to fake light and shadow; drawn
			# as hard-edged boxes they read as glitchy white/black rectangles.
			# Feather the edges so they blend like a glow / shade.
			tex = _soft_blank_tex()
		if tex == null:
			continue
		var pos_arr = it.get("pos", [0, 0])
		var pos := Vector2(float(pos_arr[0]), float(pos_arr[1]))
		var sc := float(it.get("scale", 1.0))
		var sc_y := float(it.get("scale_y", sc))
		var rot := float(it.get("rot", 0.0))
		var alpha := int(it.get("alpha", 255))
		var level := int(it.get("level", 1))
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false  # Soldat anchors props by top-left corner.
		s.position = pos
		# Soldat sizes a prop as its stored Width×Height (original sprite
		# size) × ScaleX/Y — not by the texture's pixel size. Our PNGs are
		# frequently HD, so normalise by the texture size when w/h are known.
		var tsz := tex.get_size()
		var fit := Vector2.ONE
		if it.has("w") and it.has("h") and tsz.x > 0.0 and tsz.y > 0.0:
			fit = Vector2(maxf(1.0, float(it["w"])) / tsz.x, maxf(1.0, float(it["h"])) / tsz.y)
		s.scale = Vector2(sc, sc_y) * map_scale * fit
		# Soldat renders props with -Rotation (MapGraphics.pas) in the same
		# y-down space Godot uses, so the sign flips here.
		s.rotation = -rot
		var tint := Color.WHITE
		if it.has("color"):
			tint = Color.html(str(it["color"]))
		s.modulate = Color(tint.r, tint.g, tint.b, clamp(alpha / 255.0, 0.0, 1.0))
		s.z_index = int(_SCENERY_LEVEL_Z.get(level, 0))
		main.add_child(s)


func _soft_blank_tex() -> Texture2D:
	if _soft_blank == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0)])
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.width = 92
		gt.height = 92
		gt.fill = GradientTexture2D.FILL_SQUARE
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		_soft_blank = gt
	return _soft_blank


class _LadderVisual extends Node2D:
	var width: float = 20.0
	var height: float = 120.0

	func _draw() -> void:
		var col := Color(0.72, 0.55, 0.28, 0.95)
		var inset: float = clampf(width * 0.15, 2.0, 6.0)
		var lx := -width * 0.5 + inset
		var rx :=  width * 0.5 - inset
		var ty := -height * 0.5
		var by :=  height * 0.5
		# Faint fill so the ladder reads even against dark terrain.
		draw_rect(Rect2(Vector2(-width * 0.5, ty), Vector2(width, height)),
			Color(0.35, 0.24, 0.12, 0.28))
		draw_line(Vector2(lx, ty), Vector2(lx, by), col, 2.0)
		draw_line(Vector2(rx, ty), Vector2(rx, by), col, 2.0)
		var step := 20.0
		var y := ty + step * 0.5
		while y < by:
			draw_line(Vector2(lx, y), Vector2(rx, y), col, 1.5)
			y += step
