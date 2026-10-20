extends Node
## Maker mode (#286): the Mario-Maker-style front of the map editor.
##
## A child of map_editor.gd (`ed`), working on the editor's `_map` (source
## form: entities in the normal map keys + a "maker" block of terrain / hazard
## / pad / prop pieces, scripts/maker/maker_build.gd). It owns:
##   * the UI on its own CanvasLayer: top bar (file / theme / map / test mode /
##     grid / undo / redo / Advanced / PLAY), the bottom palette of piece cards
##     in tabs, a minimap with zoom-to-fit, a floating selection bar (rotate /
##     flip / duplicate / delete), a context menu, the problems sheet, toasts;
##   * input: drag from the palette (ghost preview on the snapping grid) or tap
##     a card to arm it and tap the map to stamp; click / drag to select and
##     move, handles to resize, box select, keyboard shortcuts; touch: one
##     finger drags pieces or pans on empty space, two fingers pinch-zoom,
##     long press opens the context menu;
##   * the world view (drawn into the editor's canvas): theme sky, grid, the
##     compiled terrain exactly as the game gets it, hazards, props, entities;
##   * PLAY: validate -> compile -> save _playtest -> main.tscn with the player
##     spawned under the camera; main's EDIT comes back here (Net.maker_return).
## Every committed change goes through the editor's whole-map undo snapshots.

const MapIO = preload("res://scripts/map_io.gd")
const Pieces = preload("res://scripts/maker/maker_pieces.gd")
const Build = preload("res://scripts/maker/maker_build.gd")
const Themes = preload("res://scripts/maker/maker_themes.gd")
const HazardArt = preload("res://scripts/maker/hazard_art.gd")
const GameLists = preload("res://scripts/game_lists.gd")

const GRIDS := [10, 20, 40, 80]
const LONG_PRESS := 0.5
const DRAG_SLOP := 9.0
const HANDLE_PX := 10.0
const ZOOM_MIN := 0.08
const ZOOM_MAX := 2.5
const SINGLE_KEYS := ["player_spawn", "inf_flag", "htf_flag", "rambo_pos"]
const LIST_KEYS := ["bot_spawns", "dom_points", "point_spawns", "bonus_spawns", "medkits", "grenade_kits",
	"vehicle_spawns", "tank_spawns", "heli_spawns", "plane_spawns", "m2_mounts"]

var ed: Node2D = null
var active := false
var tab := "terrain"
var armed := ""
var sel: Array = []
var test_mode := 2
var box_mode := false

var _prev: Dictionary = {}
var _prev_sig := -1
var _excl: Array = []           # piece indices hidden from the preview while dragged
var _press: Dictionary = {}
var _drag := ""
var _orig: Dictionary = {}       # ref key -> original position / piece copy
var _box_a := Vector2.ZERO
var _box_b := Vector2.ZERO
var _pan_btn := 0
var _rpan_moved := false
var _rpan_from := Vector2.ZERO
var _touches: Dictionary = {}
var _pinch_d := 0.0
var _pal: Dictionary = {}        # palette press: {id, from, dragging}
var _ghost_id := ""
var _ghost_w := Vector2.INF
var _hover_w := Vector2.INF
var _last_cam := Vector3.ZERO
var _toast_t := 0.0
var _t := 0.0

# UI
var layer: CanvasLayer = null
var root: Control = null
var _top: PanelContainer = null
var _name: LineEdit = null
var _theme_ob: OptionButton = null
var _mode_ob: OptionButton = null
var _grid_btn: Button = null
var _box_btn: Button = null
var _undo_btn: Button = null
var _redo_btn: Button = null
var _palette: PanelContainer = null
var _tab_btns: Dictionary = {}
var _scroll: ScrollContainer = null
var _cards: HBoxContainer = null
var _mini: Control = null
var _mini_panel: PanelContainer = null
var _selbar: PanelContainer = null
var _selbar_btns: Dictionary = {}
var _ctx: PanelContainer = null
var _ctx_box: VBoxContainer = null
var _probs: PanelContainer = null
var _probs_list: VBoxContainer = null
var _probs_title: Label = null
var _probs_go: Button = null
var _load: PanelContainer = null
var _load_list: VBoxContainer = null
var _toast: Label = null
var _hint: Label = null
var _file_menu: MenuButton = null
var _map_menu: MenuButton = null
var _pending_after_probs := ""


# ── Lifecycle ────────────────────────────────────────────────────────────────

func setup(editor: Node2D) -> void:
	ed = editor
	test_mode = clampi(Settings.game_mode, 0, GameLists.MODE_NAMES.size() - 1)
	# The world size changes with the map: the view is clamped by _clamp_cam.
	var c: Camera2D = ed._cam
	c.limit_left = -100000
	c.limit_top = -100000
	c.limit_right = 100000
	c.limit_bottom = 100000
	_build_ui()


func set_active(on: bool) -> void:
	active = on
	if layer != null:
		layer.visible = on
	if on:
		Build.ensure_maker(ed._map)
		_sync_controls()
		_rebuild(true)
		_hint_default()
	else:
		armed = ""
		sel.clear()
		_close_popups()
	ed.queue_redraw()


func _process(delta: float) -> void:
	if not active:
		return
	_t += delta
	# Long press (touch): context menu where the finger rests.
	if not _press.is_empty() and bool(_press.get("touch", false)) and not bool(_press.get("moved", false)) and _drag == "":
		_press["t"] = float(_press.get("t", 0.0)) + delta
		if float(_press["t"]) >= LONG_PRESS:
			var sp: Vector2 = _press["s"]
			var r: Dictionary = hit(_press["w"])
			_press = {}
			if not r.is_empty() and not _has_ref(r):
				sel = [r]
			_open_context(sp)
	if _toast != null and _toast.visible:
		_toast_t -= delta
		if _toast_t <= 0.0:
			_toast.visible = false
	var cam: Camera2D = ed._cam
	var cs := Vector3(cam.position.x, cam.position.y, cam.zoom.x)
	if cs != _last_cam:
		if absf(cs.z - _last_cam.z) > 0.0001:
			ed.queue_redraw()   # entity icons keep a readable screen size
		_last_cam = cs
		if _mini != null:
			_mini.queue_redraw()
		_place_selbar()
	if _ghost_id != "" or (armed != "" and _hover_w != Vector2.INF):
		ed.queue_redraw()


# ── Map access ───────────────────────────────────────────────────────────────

func _m() -> Dictionary:
	return ed._map


func _mk() -> Dictionary:
	return Build.ensure_maker(ed._map)


func _pieces() -> Array:
	return _mk()["pieces"]


func theme() -> String:
	return str(_mk().get("theme", "grassland"))


func grid() -> int:
	return int(_mk().get("grid", 20))


func world_size() -> Vector2:
	var mk := _mk()
	return Vector2(float(mk.get("w", Build.DEFAULT_W)), float(mk.get("h", Build.DEFAULT_H)))


func preview() -> Dictionary:
	return _prev


## Recompile the preview when the map changed (cheap: a few ms).
func _rebuild(force: bool = false) -> void:
	var sig := str(_m()).hash() ^ str(_excl).hash()
	if not force and sig == _prev_sig:
		return
	_prev_sig = sig
	if _excl.is_empty():
		_prev = Build.compile(_m())
	else:
		var tmp := _m().duplicate(true)
		var pcs: Array = Build.ensure_maker(tmp)["pieces"]
		var idx := _excl.duplicate()
		idx.sort()
		idx.reverse()
		for i in idx:
			if int(i) < pcs.size():
				pcs.remove_at(int(i))
		_prev = Build.compile(tmp)
	ed.queue_redraw()
	if _mini != null:
		_mini.queue_redraw()


func commit(msg: String = "") -> void:
	ed._checkpoint()
	_excl.clear()
	_rebuild()
	_sync_undo()
	_place_selbar()
	if msg != "":
		toast(msg)


# ── Coordinates ──────────────────────────────────────────────────────────────

func to_world(screen: Vector2) -> Vector2:
	return ed.get_viewport().get_canvas_transform().affine_inverse() * screen


func to_screen(world: Vector2) -> Vector2:
	return ed.get_viewport().get_canvas_transform() * world


func zoom() -> float:
	return ed._cam.zoom.x


func snapv(p: Vector2) -> Vector2:
	var g := float(grid())
	return Vector2(round(p.x / g) * g, round(p.y / g) * g)


func _ent_size() -> float:
	return clampf(34.0 / zoom(), 44.0, 170.0)


func _clamp_cam() -> void:
	var ws := world_size()
	var c: Camera2D = ed._cam
	c.position = c.position.clamp(Vector2(-600, -600), ws + Vector2(600, 600))


func zoom_at(screen_p: Vector2, factor: float) -> void:
	var c: Camera2D = ed._cam
	var before := to_world(screen_p)
	c.zoom = (c.zoom * factor).clamp(Vector2(ZOOM_MIN, ZOOM_MIN), Vector2(ZOOM_MAX, ZOOM_MAX))
	c.force_update_scroll()
	var after := to_world(screen_p)
	c.position += before - after
	_clamp_cam()
	ed.queue_redraw()


func fit_view() -> void:
	var ws := world_size()
	var vs := ed.get_viewport().get_visible_rect().size
	var avail := Vector2(vs.x - 40.0, vs.y - _top_h() - _palette_h() - 40.0)
	var z := clampf(minf(avail.x / ws.x, avail.y / ws.y), ZOOM_MIN, ZOOM_MAX)
	var c: Camera2D = ed._cam
	c.zoom = Vector2(z, z)
	# Centre the world in the area between the bars.
	var off := (_top_h() - _palette_h()) * 0.5 / z
	c.position = ws * 0.5 - Vector2(0, off)
	ed.queue_redraw()


func _top_h() -> float:
	return 76.0 if _top == null else _top.get_global_rect().end.y + 8.0


func _palette_h() -> float:
	if _palette == null:
		return 170.0
	return ed.get_viewport().get_visible_rect().size.y - _palette.get_global_rect().position.y + 8.0


# ── Refs: everything selectable ──────────────────────────────────────────────

func _ref_key(r: Dictionary) -> String:
	return "%s:%d:%d" % [str(r.get("k", "")), int(r.get("t", 0)), int(r.get("i", 0))]


func _has_ref(r: Dictionary) -> bool:
	var k := _ref_key(r)
	for s in sel:
		if _ref_key(s) == k:
			return true
	return false


func all_refs() -> Array:
	var out: Array = []
	var m := _m()
	for i in (m.get("polys", []) as Array).size():
		out.append({"k": "polys", "i": i})
	for i in (m.get("platforms", []) as Array).size():
		out.append({"k": "platforms", "i": i})
	for i in _pieces().size():
		out.append({"k": "pc", "i": i})
	for i in (m.get("ladders", []) as Array).size():
		out.append({"k": "ladders", "i": i})
	for i in (m.get("scenery", []) as Array).size():
		out.append({"k": "scenery", "i": i})
	for k in LIST_KEYS:
		for i in (m.get(k, []) as Array).size():
			out.append({"k": k, "i": i})
	for i in (m.get("weapon_pickups", []) as Array).size():
		out.append({"k": "weapon_pickups", "i": i})
	var ts: Variant = m.get("team_spawns", {})
	if typeof(ts) == TYPE_DICTIONARY:
		for t in [1, 2]:
			for i in ((ts as Dictionary).get(t, []) as Array).size():
				out.append({"k": "team_spawns", "t": t, "i": i})
	for i in (m.get("ctf_flags", []) as Array).size():
		out.append({"k": "ctf_flags", "i": i})
	for k in SINGLE_KEYS:
		if m.has(k):
			out.append({"k": k, "i": 0})
	return out


func ref_valid(r: Dictionary) -> bool:
	var k := str(r.get("k", ""))
	var i := int(r.get("i", 0))
	var m := _m()
	match k:
		"pc": return i < _pieces().size()
		"team_spawns":
			var ts: Variant = m.get("team_spawns", {})
			return typeof(ts) == TYPE_DICTIONARY and i < ((ts as Dictionary).get(int(r.get("t", 1)), []) as Array).size()
	if k in SINGLE_KEYS:
		return m.has(k)
	return m.has(k) and i < (m[k] as Array).size()


## Palette id of a ref (its art / tips / capabilities).
func ref_id(r: Dictionary) -> String:
	var k := str(r.get("k", ""))
	var i := int(r.get("i", 0))
	match k:
		"pc": return str(_pieces()[i].get("t", ""))
		"ladders": return "ladder"
		"scenery", "polys", "platforms": return ""
		"weapon_pickups": return Pieces.entity_id_for(k, 0, 0, str(_m()["weapon_pickups"][i].get("weapon", "")))
	return Pieces.entity_id_for(k, int(r.get("t", 0)), i)


func ref_pos(r: Dictionary) -> Vector2:
	var k := str(r.get("k", ""))
	var i := int(r.get("i", 0))
	var m := _m()
	match k:
		"pc":
			var p: Dictionary = _pieces()[i]
			return Vector2(float(p["x"]), float(p["y"]))
		"team_spawns":
			return m["team_spawns"][int(r.get("t", 1))][i]
		"weapon_pickups", "scenery":
			return m[k][i].get("pos", Vector2.ZERO)
		"ladders", "platforms", "polys":
			return ed._pos_of(k, i)
	if k in SINGLE_KEYS:
		return m[k]
	return m[k][i]


func ref_set_pos(r: Dictionary, p: Vector2) -> void:
	var k := str(r.get("k", ""))
	var i := int(r.get("i", 0))
	var m := _m()
	match k:
		"pc":
			_pieces()[i]["x"] = float(p.x)
			_pieces()[i]["y"] = float(p.y)
		"team_spawns":
			m["team_spawns"][int(r.get("t", 1))][i] = p
		"weapon_pickups", "scenery":
			m[k][i]["pos"] = p
		"ladders", "platforms", "polys":
			ed._set_pos_of(k, i, p)
		_:
			if k in SINGLE_KEYS:
				m[k] = p
			else:
				m[k][i] = p


func ref_rect(r: Dictionary) -> Rect2:
	var k := str(r.get("k", ""))
	var i := int(r.get("i", 0))
	var m := _m()
	match k:
		"pc":
			var p: Dictionary = _pieces()[i]
			var d := Pieces.def(str(p.get("t", "")))
			if str(d.get("kind", "")) == "pad":
				return Build.piece_rect(p).grow_individual(4, 14, 4, 0)
			return Build.piece_rect(p)
		"ladders":
			return ed._ladder_rect(m["ladders"][i])
		"scenery":
			return _scenery_rect(m["scenery"][i])
		"platforms":
			var pl: Dictionary = m["platforms"][i]
			return Rect2((pl["p"] as Vector2) - (pl["s"] as Vector2) * 0.5, pl["s"])
		"polys":
			var pts: PackedVector2Array = m["polys"][i].get("points", PackedVector2Array())
			var rr := Rect2(pts[0] if pts.size() > 0 else Vector2.ZERO, Vector2.ZERO)
			for v in pts:
				rr = rr.expand(v)
			return rr
	var s := _ent_size()
	var pos := ref_pos(r)
	var anchor := str(Pieces.def(ref_id(r)).get("anchor", "feet"))
	if anchor == "center":
		return Rect2(pos - Vector2(s, s) * 0.5, Vector2(s, s))
	return Rect2(pos - Vector2(s * 0.5, s), Vector2(s, s))


func _scenery_rect(sc: Dictionary) -> Rect2:
	var t := Pieces.tex(str(sc.get("tex", "")))
	var sz := Vector2(40, 40)
	if t != null:
		sz = t.get_size() * float(sc.get("scale", 1.0))
	return Rect2((sc.get("pos", Vector2.ZERO) as Vector2) - sz * 0.5, sz)


## Top-most selectable thing under a world point.
func hit(w: Vector2) -> Dictionary:
	var refs := all_refs()
	for j in range(refs.size() - 1, -1, -1):
		var r: Dictionary = refs[j]
		var k := str(r["k"])
		if k == "polys":
			var pts: PackedVector2Array = _m()["polys"][int(r["i"])].get("points", PackedVector2Array())
			if pts.size() >= 3 and Geometry2D.is_point_in_polygon(w, pts):
				return r
			continue
		if k == "pc":
			var p: Dictionary = _pieces()[int(r["i"])]
			var d := Pieces.def(str(p.get("t", "")))
			if str(d.get("kind", "")) == "shape":
				var poly := Build.piece_polygon(p)
				var thin := minf(Build.piece_size(p).x, Build.piece_size(p).y) < 30.0
				if Geometry2D.is_point_in_polygon(w, poly) or (thin and ref_rect(r).grow(8.0 / zoom()).has_point(w)):
					return r
				continue
		var grow := 6.0 / zoom() if k == "pc" or k == "ladders" else 2.0 / zoom()
		if ref_rect(r).grow(grow).has_point(w):
			return r
	return {}


# ── Editing operations (also the test API) ───────────────────────────────────

## Drop palette piece `id` at world point `w` (snapped). Returns its ref.
func place(id: String, w: Vector2) -> Dictionary:
	var d := Pieces.def(id)
	if d.is_empty():
		return {}
	var kind := str(d.get("kind", ""))
	var m := _m()
	var g := snapv(w)
	var ref := {}
	match kind:
		"shape", "hazard", "prop":
			var p := Build.new_piece(id, Vector2.ZERO)
			var sz := Build.piece_size(p)
			var tl := snapv(w - sz * 0.5)
			p["x"] = float(tl.x + sz.x * 0.5)
			p["y"] = float(tl.y + sz.y * 0.5)
			_pieces().append(p)
			ref = {"k": "pc", "i": _pieces().size() - 1}
		"pad":
			var p2 := Build.new_piece(id, g - Vector2(0, float(d.get("h", 20.0)) * 0.5))
			_pieces().append(p2)
			ref = {"k": "pc", "i": _pieces().size() - 1}
		"ladder":
			var lw := float(d.get("w", 20.0))
			var lh := float(d.get("h", 240.0))
			var tl2 := snapv(w - Vector2(lw * 0.5, lh * 0.5))
			var arr: Array = m.get("ladders", [])
			arr.append({"x": tl2.x, "y": tl2.y, "w": lw, "h": lh})
			m["ladders"] = arr
			ref = {"k": "ladders", "i": arr.size() - 1}
		"scenery":
			var t := Pieces.tex(str(d.get("tex", "")))
			var sc := float(d.get("scale", 1.0))
			var hh := (t.get_size().y * sc * 0.5) if t != null else 20.0
			var arr2: Array = m.get("scenery", [])
			arr2.append({"tex": str(d.get("tex", "")), "pos": Vector2(g.x, g.y - hh), "scale": sc, "z": -2})
			m["scenery"] = arr2
			ref = {"k": "scenery", "i": arr2.size() - 1}
		"entity":
			ref = _place_entity(id, d, g)
			if ref.is_empty():
				return {}
	_settle(ref)
	sel = [ref]
	commit()
	return ref


## Things that stand on the ground (spikes, pads, props, spawns, flags,
## pickups, vehicles ...) dropped a little above a surface land on it.
func _settle(ref: Dictionary) -> void:
	var k := str(ref.get("k", ""))
	var id := ref_id(ref)
	var d := Pieces.def(id)
	var kind := str(d.get("kind", ""))
	var bottom: float
	if k == "pc":
		if not (kind in ["pad", "prop"] or (kind == "hazard" and str(d.get("hz", "")) == "spikes" and int(_pieces()[int(ref["i"])].get("r", 0)) == 0)):
			return
		bottom = ref_rect(ref).end.y if kind != "pad" else float(_pieces()[int(ref["i"])]["y"]) + float(_pieces()[int(ref["i"])]["h"]) * 0.5
	elif kind == "entity" and str(d.get("anchor", "feet")) == "feet":
		bottom = ref_pos(ref).y
	else:
		return
	var x := ref_pos(ref).x
	var solids := Build._solids(_prev)
	if Build._in_solid(solids, Vector2(x, bottom - 2.0)):
		return
	for dy in range(0, 48, 2):
		if Build._in_solid(solids, Vector2(x, bottom + float(dy) + 1.0)):
			if dy > 0:
				ref_set_pos(ref, ref_pos(ref) + Vector2(0, float(dy)))
			return


func _place_entity(id: String, d: Dictionary, g: Vector2) -> Dictionary:
	var m := _m()
	var key := str(d.get("key", ""))
	if bool(d.get("single", false)):
		m[key] = g
		return {"k": key, "i": 0}
	if key == "ctf_flags":
		var fl: Array = m.get("ctf_flags", [])
		var ws := world_size()
		while fl.size() < 2:
			fl.append(Vector2(300.0 if fl.size() == 0 else ws.x - 300.0, ws.y * 0.5))
		fl[int(d.get("slot", 0))] = g
		m["ctf_flags"] = fl
		return {"k": "ctf_flags", "i": int(d.get("slot", 0))}
	if key == "team_spawns":
		var ts: Dictionary = m.get("team_spawns", {}) if typeof(m.get("team_spawns", {})) == TYPE_DICTIONARY else {}
		var t := int(d.get("team", 1))
		var lst: Array = ts.get(t, [])
		lst.append(g)
		ts[t] = lst
		if not ts.has(1):
			ts[1] = []
		if not ts.has(2):
			ts[2] = []
		m["team_spawns"] = ts
		return {"k": "team_spawns", "t": t, "i": lst.size() - 1}
	if key == "weapon_pickups":
		var wl: Array = m.get("weapon_pickups", [])
		wl.append({"pos": g, "weapon": str(d.get("weapon", "AK-74"))})
		m["weapon_pickups"] = wl
		return {"k": key, "i": wl.size() - 1}
	var arr: Array = m.get(key, [])
	if d.has("max") and arr.size() >= int(d["max"]):
		toast(tr("That's the most %s a map can have.") % tr(str(d.get("label", ""))), true)
		return {}
	arr.append(g)
	m[key] = arr
	return {"k": key, "i": arr.size() - 1}


func delete_selection() -> void:
	if sel.is_empty():
		return
	var m := _m()
	var by_key: Dictionary = {}
	var kept_player := false
	for r in sel:
		if not ref_valid(r):
			continue
		var k := str(r["k"])
		if k == "player_spawn":
			kept_player = true
			continue
		if k in SINGLE_KEYS:
			m.erase(k)
			continue
		if k == "ctf_flags":
			m.erase("ctf_flags")   # flags come as a blue / red pair
			continue
		var bk := k + ("/%d" % int(r.get("t", 0)) if k == "team_spawns" else "")
		if not by_key.has(bk):
			by_key[bk] = []
		(by_key[bk] as Array).append(int(r["i"]))
	for bk in by_key:
		var idx: Array = by_key[bk]
		idx.sort()
		idx.reverse()
		var parts := str(bk).split("/")
		var lst: Array
		if parts[0] == "pc":
			lst = _pieces()
		elif parts[0] == "team_spawns":
			lst = m["team_spawns"][int(parts[1])]
		else:
			lst = m.get(parts[0], [])
		for i in idx:
			if int(i) < lst.size():
				lst.remove_at(int(i))
		if parts[0] in LIST_KEYS and lst.is_empty():
			m.erase(parts[0])
	sel.clear()
	commit(tr("The player start can't be deleted — drag it instead.") if kept_player else "")


func duplicate_selection() -> void:
	if sel.is_empty():
		return
	var m := _m()
	var off := Vector2(maxf(float(grid()) * 2.0, 40.0), 0)
	var out: Array = []
	for r in sel:
		if not ref_valid(r):
			continue
		var k := str(r["k"])
		var i := int(r.get("i", 0))
		if k in SINGLE_KEYS or k == "ctf_flags":
			continue
		match k:
			"pc":
				var p: Dictionary = (_pieces()[i] as Dictionary).duplicate(true)
				p["x"] = float(p["x"]) + off.x
				_pieces().append(p)
				out.append({"k": "pc", "i": _pieces().size() - 1})
			"team_spawns":
				var t := int(r.get("t", 1))
				var lst: Array = m["team_spawns"][t]
				lst.append((lst[i] as Vector2) + off)
				out.append({"k": k, "t": t, "i": lst.size() - 1})
			"weapon_pickups", "scenery", "ladders", "platforms", "polys":
				var arr: Array = m[k]
				var e: Variant = arr[i]
				var copy: Variant = e.duplicate(true) if typeof(e) == TYPE_DICTIONARY else e
				arr.append(copy)
				var nr := {"k": k, "i": arr.size() - 1}
				ref_set_pos(nr, ref_pos({"k": k, "i": i}) + off)
				out.append(nr)
			_:
				var d := Pieces.def(ref_id(r))
				var arr2: Array = m[k]
				if d.has("max") and arr2.size() >= int(d["max"]):
					continue
				arr2.append((arr2[i] as Vector2) + off)
				out.append({"k": k, "i": arr2.size() - 1})
	if out.is_empty():
		return
	sel = out
	commit()


func rotate_selection() -> void:
	var n := 0
	for r in sel:
		if str(r.get("k", "")) == "pc" and ref_valid(r):
			var p: Dictionary = _pieces()[int(r["i"])]
			if Pieces.can_rotate(str(p.get("t", ""))):
				p["r"] = posmod(int(p.get("r", 0)) + 1, 4)
				n += 1
	if n > 0:
		commit()


func flip_selection() -> void:
	var n := 0
	for r in sel:
		if str(r.get("k", "")) == "pc" and ref_valid(r):
			var p: Dictionary = _pieces()[int(r["i"])]
			if Pieces.can_flip(str(p.get("t", ""))):
				p["f"] = 0 if int(p.get("f", 0)) == 1 else 1
				n += 1
	if n > 0:
		commit()


func move_selection(delta: Vector2) -> void:
	for r in sel:
		if ref_valid(r):
			ref_set_pos(r, ref_pos(r) + delta)
	commit()


func select_all() -> void:
	sel = []
	for r in all_refs():
		if str(r["k"]) != "polys" and str(r["k"]) != "platforms":
			sel.append(r)
	_place_selbar()
	ed.queue_redraw()


## Resize a piece / ladder / prop / scenery so its rect follows handle `h`
## (0..7: corners clockwise from top-left, then edges) dragged to world `w`.
func resize_ref(r: Dictionary, h: int, w: Vector2, orig: Rect2) -> void:
	var g := float(grid())
	var x0 := orig.position.x
	var y0 := orig.position.y
	var x1 := orig.end.x
	var y1 := orig.end.y
	var s := snapv(w)
	if h in [0, 6, 7]: x0 = minf(s.x, x1 - g)
	if h in [2, 3, 4]: x1 = maxf(s.x, x0 + g)
	if h in [0, 1, 2]: y0 = minf(s.y, y1 - g * 0.5)
	if h in [4, 5, 6]: y1 = maxf(s.y, y0 + g * 0.5)
	var nr := Rect2(x0, y0, x1 - x0, y1 - y0)
	var k := str(r["k"])
	var i := int(r.get("i", 0))
	match k:
		"pc":
			var p: Dictionary = _pieces()[i]
			var d := Pieces.def(str(p.get("t", "")))
			var minsz := Vector2(8, 8)
			var sz := nr.size.max(minsz)
			if str(d.get("kind", "")) == "prop":
				var aspect := float(d.get("h", 1.0)) / maxf(1.0, float(d.get("w", 1.0)))
				sz = Vector2(sz.x, sz.x * aspect)
				nr = Rect2(Vector2(nr.position.x, nr.end.y - sz.y), sz)
			if str(p.get("t", "")) == "lava":
				# The handle box includes the basin walls + floor.
				sz = Vector2(maxf(40.0, sz.x - Build.BASIN_RIM * 2.0), maxf(16.0, sz.y - Build.BASIN_H))
				nr = Rect2(nr.position + Vector2(Build.BASIN_RIM, 0), sz)
			var c := nr.position + sz * 0.5
			p["x"] = float(c.x)
			p["y"] = float(c.y)
			if int(p.get("r", 0)) % 2 == 1:
				p["w"] = float(sz.y)
				p["h"] = float(sz.x)
			else:
				p["w"] = float(sz.x)
				p["h"] = float(sz.y)
		"ladders":
			var ld: Dictionary = _m()["ladders"][i]
			ld["x"] = nr.position.x
			ld["y"] = nr.position.y
			ld["w"] = maxf(10.0, nr.size.x)
			ld["h"] = maxf(40.0, nr.size.y)
		"scenery":
			var sc: Dictionary = _m()["scenery"][i]
			var t := Pieces.tex(str(sc.get("tex", "")))
			if t != null:
				var k2 := maxf(0.05, nr.size.x / t.get_size().x)
				sc["scale"] = snappedf(k2, 0.001)
				var hh := t.get_size().y * k2
				sc["pos"] = Vector2(nr.get_center().x, orig.end.y - hh * 0.5)


func set_theme(id: String) -> void:
	_mk()["theme"] = id
	commit(tr("Theme: %s") % tr(Themes.label(id)))
	_sync_controls()


func set_world(size_idx: int, bottom: String) -> void:
	var mk := _mk()
	if size_idx >= 0:
		var s: Array = Build.SIZES[size_idx]
		mk["w"] = float(s[1])
		mk["h"] = float(s[2])
	if bottom != "":
		mk["bottom"] = bottom
	commit()
	_clamp_cam()


func cycle_grid() -> void:
	var gi := GRIDS.find(grid())
	_mk()["grid"] = GRIDS[(gi + 1) % GRIDS.size()]
	ed._checkpoint()
	_sync_controls()
	ed.queue_redraw()
	toast(tr("Grid: %d px") % grid())


func new_map() -> void:
	_close_popups()
	var th := theme()
	ed._map = Build.starter_map(th)
	sel.clear()
	_name.text = "My map"
	ed._name_edit.text = "My map"
	commit(tr("New map."))
	fit_view()


# ── Input ────────────────────────────────────────────────────────────────────

func _over_ui(screen_p: Vector2) -> bool:
	for c in [_top, _palette, _mini_panel, _selbar, _ctx, _probs, _load]:
		var ctl := c as Control
		if ctl != null and ctl.is_visible_in_tree() and ctl.get_global_rect().has_point(screen_p):
			return true
	return false


func handle_input(event: InputEvent) -> void:
	if event is InputEventKey:
		_key(event as InputEventKey)
		return
	if event is InputEventScreenTouch:
		_touch(event as InputEventScreenTouch)
		return
	if event is InputEventScreenDrag:
		_touch_drag(event as InputEventScreenDrag)
		return
	if event is InputEventMagnifyGesture:
		zoom_at((event as InputEventMagnifyGesture).position, (event as InputEventMagnifyGesture).factor)
		return
	if event is InputEventPanGesture:
		ed._cam.position += (event as InputEventPanGesture).delta * 12.0 / zoom()
		_clamp_cam()
		return
	if event is InputEventMouse and (event as InputEventMouse).device == InputEvent.DEVICE_ID_EMULATION:
		return   # touches are handled as touches
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_at(mb.position, 1.12)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_at(mb.position, 1.0 / 1.12)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_pan_btn = MOUSE_BUTTON_MIDDLE if mb.pressed else 0
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_pan_btn = MOUSE_BUTTON_RIGHT
				_rpan_moved = false
				_rpan_from = mb.position
			else:
				_pan_btn = 0
				if not _rpan_moved:
					if armed != "":
						disarm()
					else:
						var r := hit(to_world(mb.position))
						if not r.is_empty() and not _has_ref(r):
							sel = [r]
						_open_context(mb.position)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_close_popups()
				_pointer_down(mb.position, false, mb.shift_pressed)
			else:
				_pointer_up(mb.position)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_hover_w = to_world(mm.position)
		if _pan_btn != 0:
			if _pan_btn == MOUSE_BUTTON_RIGHT and mm.position.distance_to(_rpan_from) > DRAG_SLOP:
				_rpan_moved = true
			if _pan_btn == MOUSE_BUTTON_MIDDLE or _rpan_moved:
				ed._cam.position -= mm.relative / zoom()
				_clamp_cam()
			return
		if not _press.is_empty():
			_pointer_move(mm.position)


func _key(k: InputEventKey) -> void:
	if not k.pressed or k.echo and not (k.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]):
		return
	var ctrl := k.ctrl_pressed or k.meta_pressed
	if ctrl:
		match k.keycode:
			KEY_Z:
				redo() if k.shift_pressed else undo()
			KEY_Y:
				redo()
			KEY_D:
				duplicate_selection()
			KEY_A:
				select_all()
			KEY_S:
				save()
		return
	match k.keycode:
		KEY_DELETE, KEY_BACKSPACE:
			delete_selection()
		KEY_R:
			rotate_selection()
		KEY_F:
			flip_selection()
		KEY_G:
			cycle_grid()
		KEY_HOME:
			fit_view()
		KEY_F5, KEY_P:
			play()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			set_tab(Pieces.TABS[k.keycode - KEY_1])
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
			if not sel.is_empty():
				var g := float(grid())
				var dv := {KEY_LEFT: Vector2(-g, 0), KEY_RIGHT: Vector2(g, 0), KEY_UP: Vector2(0, -g), KEY_DOWN: Vector2(0, g)}
				move_selection(dv[k.keycode])
		# Esc never gets here: the editor's go_back() takes it (BACK rule) and
		# asks back_pressed() below before leaving.


func _touch(t: InputEventScreenTouch) -> void:
	if t.pressed:
		if _touches.is_empty() and _over_ui(t.position):
			return
		_touches[t.index] = t.position
		if _touches.size() == 1:
			_close_popups()
			_pointer_down(t.position, true, false)
		elif _touches.size() == 2:
			_cancel_press()
			_drag = "pinch"
			_pinch_d = _spread()
	else:
		if not _touches.has(t.index):
			return
		_touches.erase(t.index)
		if _drag == "pinch":
			if _touches.is_empty():
				_drag = ""
			return
		if _touches.is_empty():
			_pointer_up(t.position)


func _touch_drag(d: InputEventScreenDrag) -> void:
	if not _touches.has(d.index):
		return
	_touches[d.index] = d.position
	if _drag == "pinch" and _touches.size() >= 2:
		var pts: Array = _touches.values()
		var mid: Vector2 = ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5
		ed._cam.position -= d.relative / zoom() / float(_touches.size())
		var sp := _spread()
		if _pinch_d > 1.0 and sp > 1.0:
			zoom_at(mid, sp / _pinch_d)
		_pinch_d = sp
		_clamp_cam()
		return
	_pointer_move(d.position)


func _spread() -> float:
	if _touches.size() < 2:
		return 0.0
	var pts: Array = _touches.values()
	return (pts[0] as Vector2).distance_to(pts[1] as Vector2)


func _cancel_press() -> void:
	if _drag == "move" or _drag == "resize":
		for r in sel:
			var key := _ref_key(r)
			if _orig.has(key) and ref_valid(r):
				if str(r["k"]) == "pc":
					_pieces()[int(r["i"])] = (_orig[key] as Dictionary).duplicate(true)
				else:
					ref_set_pos(r, _orig[key])
		_excl.clear()
		_rebuild()
	_press = {}
	_drag = ""
	ed.queue_redraw()


func _pointer_down(sp: Vector2, touch: bool, shift: bool) -> void:
	var w := to_world(sp)
	_press = {"s": sp, "w": w, "touch": touch, "t": 0.0, "moved": false, "shift": shift}
	var h := _handle_at(sp)
	if h >= 0:
		_press["mode"] = "resize"
		_press["h"] = h
		return
	if armed != "":
		_press["mode"] = "stamp"
		return
	var r := hit(w)
	if not r.is_empty():
		_press["mode"] = "item"
		_press["ref"] = r
		if shift:
			_press["toggle"] = true
		elif not _has_ref(r):
			sel = [r]
			_place_selbar()
			ed.queue_redraw()
		return
	_press["mode"] = "empty"


func _pointer_move(sp: Vector2) -> void:
	if _press.is_empty():
		return
	var w := to_world(sp)
	if not bool(_press["moved"]):
		if sp.distance_to(_press["s"]) < DRAG_SLOP:
			return
		_press["moved"] = true
		_begin_drag()
	match _drag:
		"move":
			var dv := w - (_press["w"] as Vector2)
			var g := float(grid())
			dv = Vector2(round(dv.x / g) * g, round(dv.y / g) * g)
			for r in sel:
				var key := _ref_key(r)
				if _orig.has(key) and ref_valid(r):
					if str(r["k"]) == "pc":
						var o: Dictionary = _orig[key]
						_pieces()[int(r["i"])]["x"] = float(o["x"]) + dv.x
						_pieces()[int(r["i"])]["y"] = float(o["y"]) + dv.y
					else:
						ref_set_pos(r, (_orig[key] as Vector2) + dv)
			_place_selbar()
			ed.queue_redraw()
		"resize":
			var r2: Dictionary = sel[0]
			resize_ref(r2, int(_press["h"]), w, _orig["rect"])
			_place_selbar()
			ed.queue_redraw()
		"box":
			_box_b = w
			ed.queue_redraw()
		"pan":
			var prev: Vector2 = _press.get("last", _press["s"])
			ed._cam.position -= (sp - prev) / zoom()
			_press["last"] = sp
			_clamp_cam()


func _begin_drag() -> void:
	var mode := str(_press.get("mode", ""))
	_orig.clear()
	match mode:
		"resize":
			_drag = "resize"
			var r: Dictionary = sel[0]
			_orig["rect"] = ref_rect(r)
			if str(r["k"]) == "pc":
				_orig[_ref_key(r)] = (_pieces()[int(r["i"])] as Dictionary).duplicate(true)
				_excl = [int(r["i"])]
				_rebuild()
		"item":
			if bool(_press.get("toggle", false)):
				var r: Dictionary = _press["ref"]
				if not _has_ref(r):
					sel.append(r)
			_drag = "move"
			var ex: Array = []
			for r in sel:
				if not ref_valid(r):
					continue
				if str(r["k"]) == "pc":
					_orig[_ref_key(r)] = (_pieces()[int(r["i"])] as Dictionary).duplicate(true)
					ex.append(int(r["i"]))
				else:
					_orig[_ref_key(r)] = ref_pos(r)
			_excl = ex
			if not ex.is_empty():
				_rebuild()
		"empty":
			if bool(_press["touch"]) and not box_mode:
				_drag = "pan"
			else:
				_drag = "box"
				_box_a = _press["w"]
				_box_b = _press["w"]
		"stamp":
			_drag = "pan" if bool(_press["touch"]) else ""


func _pointer_up(sp: Vector2) -> void:
	if _press.is_empty():
		return
	var w := to_world(sp)
	var mode := str(_press.get("mode", ""))
	if not bool(_press["moved"]):
		match mode:
			"stamp":
				if armed != "" and not _over_ui(sp):
					place(armed, w)
			"item":
				var r: Dictionary = _press["ref"]
				if bool(_press.get("toggle", false)):
					if _has_ref(r):
						var k := _ref_key(r)
						for i in range(sel.size() - 1, -1, -1):
							if _ref_key(sel[i]) == k:
								sel.remove_at(i)
					else:
						sel.append(r)
				else:
					sel = [r]
			"empty":
				sel.clear()
	else:
		match _drag:
			"move", "resize":
				commit()
			"box":
				var br := Rect2(_box_a, Vector2.ZERO).expand(_box_b)
				var add: Array = sel if bool(_press.get("shift", false)) else []
				for r in all_refs():
					var k := str(r["k"])
					if k == "polys":
						continue
					if br.intersects(ref_rect(r)) and not _ref_in(add, r):
						add.append(r)
				sel = add
				if not sel.is_empty():
					toast(tr("%d selected") % sel.size())
	_press = {}
	_drag = ""
	_excl.clear()
	_place_selbar()
	ed.queue_redraw()


func _ref_in(arr: Array, r: Dictionary) -> bool:
	var k := _ref_key(r)
	for x in arr:
		if _ref_key(x) == k:
			return true
	return false


## Resize handle (0..7) of the single selected resizable thing under a screen
## point, or -1.
func _handle_at(sp: Vector2) -> int:
	if sel.size() != 1 or not ref_valid(sel[0]) or not _resizable(sel[0]):
		return -1
	var pts := _handle_points(ref_rect(sel[0]))
	var reach := HANDLE_PX * (1.8 if UITheme.is_touch() else 1.2)
	for i in pts.size():
		if to_screen(pts[i]).distance_to(sp) <= reach:
			return i
	return -1


func _resizable(r: Dictionary) -> bool:
	var k := str(r.get("k", ""))
	if k == "ladders" or k == "scenery":
		return true
	if k == "pc":
		return Pieces.can_resize(ref_id(r))
	return false


func _handle_points(rr: Rect2) -> PackedVector2Array:
	var c := rr.get_center()
	return PackedVector2Array([rr.position, Vector2(c.x, rr.position.y), Vector2(rr.end.x, rr.position.y), Vector2(rr.end.x, c.y),
		rr.end, Vector2(c.x, rr.end.y), Vector2(rr.position.x, rr.end.y), Vector2(rr.position.x, c.y)])


# ── Palette drag & stamp ─────────────────────────────────────────────────────

func arm(id: String) -> void:
	armed = id
	sel.clear()
	_refresh_cards()
	_place_selbar()
	_hint.text = tr("Tap the map to place %s · right-click / Esc to stop") % tr(str(Pieces.def(id).get("label", "")))
	ed.queue_redraw()


func disarm() -> void:
	armed = ""
	_refresh_cards()
	_hint_default()
	ed.queue_redraw()


func palette_press(id: String, gpos: Vector2) -> void:
	_pal = {"id": id, "from": gpos, "dragging": false}


func palette_motion(gpos: Vector2, rel: Vector2) -> void:
	if _pal.is_empty():
		return
	if not bool(_pal["dragging"]):
		var top := _palette.get_global_rect().position.y
		var dv := gpos - (_pal["from"] as Vector2)
		if gpos.y < top - 4.0 or (absf(dv.y) > 26.0 and absf(dv.y) > absf(dv.x)):
			_pal["dragging"] = true
			_ghost_id = str(_pal["id"])
		else:
			_scroll.scroll_horizontal -= int(rel.x)   # swipe along the strip
			return
	_ghost_w = to_world(gpos)
	ed.queue_redraw()


func palette_release(gpos: Vector2) -> void:
	if _pal.is_empty():
		return
	var id := str(_pal["id"])
	var dragging := bool(_pal["dragging"])
	var moved := gpos.distance_to(_pal["from"]) > DRAG_SLOP
	_pal = {}
	_ghost_id = ""
	_ghost_w = Vector2.INF
	if dragging:
		if not _over_ui(gpos):
			place(id, to_world(gpos))
			if armed != "":
				disarm()
	elif not moved:
		if armed == id:
			disarm()
		else:
			arm(id)
	ed.queue_redraw()


# ── Undo / redo / save / load / play ─────────────────────────────────────────

func undo() -> void:
	ed._undo_step()
	sel.clear()
	_after_restore()


func redo() -> void:
	ed._redo_step()
	sel.clear()
	_after_restore()


func _after_restore() -> void:
	Build.ensure_maker(ed._map)
	_excl.clear()
	_rebuild()
	_sync_controls()
	_sync_undo()
	_place_selbar()


func map_name() -> String:
	var n := _name.text.strip_edges() if _name != null else ""
	return n if n != "" else "My map"


## The playable map (compiled + named).
func compiled() -> Dictionary:
	var c := Build.compile(_m())
	c["name"] = map_name()
	c.erase("_mk_outlines")
	return c


func save() -> String:
	var c := compiled()
	var probs := Build.validate(c, -1)
	if Build.has_errors(probs):
		_show_problems(probs, "save")
		return ""
	_m()["name"] = map_name()
	ed._name_edit.text = map_name()
	var path := MapIO.save_to_file(map_name(), c)
	if path == "":
		toast(tr("Save failed."), true)
	else:
		toast(tr("Saved: %s") % map_name())
	return path


func load_path(path: String) -> void:
	var m := MapIO.load_from_file(path)
	if m.is_empty():
		toast(tr("Couldn't open that map."), true)
		return
	ed._map = Build.decompile(m)
	Build.ensure_maker(ed._map)
	_name.text = str(ed._map.get("name", "My map"))
	ed._name_edit.text = _name.text
	sel.clear()
	_close_popups()
	commit(tr("Opened: %s") % _name.text)
	fit_view()


## PLAY: check, compile, save the play-test copy and start a match with the
## player under the camera. EDIT in the match comes back to this exact view.
func play(force: bool = false) -> bool:
	var c := compiled()
	var probs := Build.validate(c, test_mode)
	if Build.has_errors(probs) or (not force and _has_new_warnings(probs)):
		_show_problems(probs, "play")
		if Build.has_errors(probs):
			return false
		return false
	var path := MapIO.save_to_file("_playtest", c)
	if path == "":
		toast(tr("Couldn't write the play-test map."), true)
		return false
	var vs := ed.get_viewport().get_visible_rect().size
	Net.maker_return = {
		"map": _m().duplicate(true), "undo": ed._undo.duplicate(true), "redo": ed._redo.duplicate(true),
		"cam": ed._cam.position, "zoom": ed._cam.zoom, "name": map_name(), "tab": tab,
		"mode_prev": Settings.game_mode, "test_mode": test_mode,
		"spawn": to_world(Vector2(vs.x * 0.5, (vs.y + _top_h() - _palette_h()) * 0.5)),
	}
	Settings.game_mode = test_mode
	Settings.custom_map_path = path
	Settings.save()
	Net.set_singleplayer()
	ed.get_tree().change_scene_to_file("res://scenes/main.tscn")
	return true


var _warned_sig := 0


func _has_new_warnings(probs: Array) -> bool:
	if probs.is_empty():
		return false
	var sig := str(probs).hash()
	if sig == _warned_sig:
		return false
	_warned_sig = sig
	return true


## Back from a PLAY session (map_editor._ready).
func restore_session(st: Dictionary) -> void:
	ed._map = (st.get("map", ed._map) as Dictionary).duplicate(true)
	Build.ensure_maker(ed._map)
	ed._undo = (st.get("undo", []) as Array).duplicate(true)
	ed._redo = (st.get("redo", []) as Array).duplicate(true)
	ed._snap_map = ed._map.duplicate(true)
	ed._snap_sig = str(ed._map).hash()
	ed._cam.position = st.get("cam", ed._cam.position)
	ed._cam.zoom = st.get("zoom", ed._cam.zoom)
	_name.text = str(st.get("name", "My map"))
	ed._name_edit.text = _name.text
	test_mode = int(st.get("test_mode", test_mode))
	if st.has("mode_prev"):
		Settings.game_mode = int(st["mode_prev"])
		Settings.save()
	set_tab(str(st.get("tab", tab)))
	_sync_controls()
	_sync_undo()
	_rebuild(true)


# ── Drawing (into the editor's canvas) ───────────────────────────────────────

func draw_world(ci: Node2D) -> void:
	var ws := world_size()
	var th := theme()
	var z := zoom()
	ci.draw_rect(Rect2(-20000, -20000, 40000 + ws.x, 40000 + ws.y), Color(0.035, 0.045, 0.06))
	var st := Themes.sky_color(th, true)
	var sb := Themes.sky_color(th, false)
	ci.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(ws.x, 0), ws, Vector2(0, ws.y)]),
		PackedColorArray([st, st, sb, sb]))
	_draw_grid(ci, ws, z)
	var wcfg := Build.world_of(_mk())
	if bool(wcfg.get("floor_visible", true)):
		var gy := float(wcfg["ground_y"])
		ci.draw_rect(Rect2(0, gy, ws.x, ws.y - gy), Color(0.2, 0.23, 0.28))
		ci.draw_line(Vector2(0, gy), Vector2(ws.x, gy), Color(0.5, 0.56, 0.64), 2.0)
	else:
		var ky := float(wcfg["kill_y"])
		ci.draw_rect(Rect2(0, ky, ws.x, ws.y - ky), Color(0.5, 0.06, 0.05, 0.18))
		var x := 0.0
		var dash := 40.0
		while x < ws.x:
			ci.draw_line(Vector2(x, ky), Vector2(minf(x + dash * 0.6, ws.x), ky), Color(1.0, 0.36, 0.3, 0.55), 2.0 / maxf(z, 0.3))
			x += dash
	draw_terrain(ci)
	_draw_hazards(ci)
	_draw_props_scenery(ci)
	for i in (_m().get("ladders", []) as Array).size():
		Pieces.draw_ladder(ci, ed._ladder_rect(_m()["ladders"][i]))
	_draw_entities(ci)
	_draw_ghosts(ci)
	_draw_selection(ci)
	if _drag == "box":
		var br := Rect2(_box_a, Vector2.ZERO).expand(_box_b)
		ci.draw_rect(br, Color(UITheme.COL_NEON, 0.08))
		ci.draw_rect(br, UITheme.COL_NEON, false, 1.5 / z)
	# World border.
	ci.draw_rect(Rect2(Vector2.ZERO, ws), Color(1, 1, 1, 0.25), false, 2.0 / z)


func _draw_grid(ci: Node2D, ws: Vector2, z: float) -> void:
	var g := float(grid())
	var step := g
	while step * z < 7.0:
		step *= 2.0
	var minor := Color(1, 1, 1, 0.045)
	var major := Color(1, 1, 1, 0.1)
	var x := 0.0
	while x <= ws.x + 0.5:
		var is_major := is_zero_approx(fmod(x, 200.0))
		ci.draw_line(Vector2(x, 0), Vector2(x, ws.y), major if is_major else minor, -1.0)
		x += step
	var y := 0.0
	while y <= ws.y + 0.5:
		var is_major2 := is_zero_approx(fmod(y, 200.0))
		ci.draw_line(Vector2(0, y), Vector2(ws.x, y), major if is_major2 else minor, -1.0)
		y += step


## The compiled terrain, exactly the polygons the game draws (textured +
## vertex colours), with a lit lip on top edges.
func draw_terrain(ci: Node2D) -> void:
	if _prev.is_empty():
		return
	var deftex := str(_prev.get("terrain_texture", ""))
	for poly in _prev.get("polys", []):
		var pts: PackedVector2Array = poly.get("points", PackedVector2Array())
		if pts.size() < 3:
			continue
		var tp := str(poly.get("texture", deftex))
		var t := Pieces.tex(tp)
		var vc: PackedColorArray = poly.get("vc", PackedColorArray())
		var cols := PackedColorArray()
		if vc.size() == pts.size():
			cols = vc
		else:
			var pc: Color = poly.get("color", _prev.get("terrain_color", Color(0.3, 0.33, 0.38)))
			cols.append(pc)
		var uvs: PackedVector2Array = poly.get("uvs", PackedVector2Array())
		if t != null and uvs.size() == pts.size():
			ci.draw_polygon(pts, cols, uvs, t)   # tile-space UVs; the editor repeats textures
		elif t != null:
			var uvw := PackedVector2Array()
			for p in pts:
				uvw.append(p / t.get_size())
			ci.draw_polygon(pts, cols if cols.size() == pts.size() else PackedColorArray([Color.WHITE]), uvw, t)
		else:
			ci.draw_polygon(pts, cols)
	var th := Themes.get_theme(theme())
	var z := zoom()
	for o in _prev.get("_mk_outlines", []):
		var pts2: PackedVector2Array = o["pts"]
		var lip: Color = (th["top"] as Color).lightened(0.3)
		if str(o.get("tint", "")) == "wood":
			lip = (th["wood"] as Color).lightened(0.25)
		elif str(o.get("tint", "")) == "glass":
			lip = Color(0.7, 0.92, 1.0, 0.8)
		var n := pts2.size()
		for i in n:
			var a: Vector2 = pts2[i]
			var b: Vector2 = pts2[(i + 1) % n]
			var e := b - a
			if e.length_squared() < 0.01:
				continue
			var nrm := Vector2(e.y, -e.x).normalized()
			if nrm.y < -0.5:
				ci.draw_line(a, b, lip, maxf(3.0, 2.5 / z))
			else:
				ci.draw_line(a, b, Color(0, 0, 0, 0.4), maxf(1.5, 1.2 / z))
	# Advanced-mode platforms (drawn by the game as plain ledges).
	for pl in _prev.get("platforms", []):
		var c: Vector2 = pl["p"]
		var s: Vector2 = pl["s"]
		if c == Build.ANCHOR_POS:
			continue
		ci.draw_rect(Rect2(c - s * 0.5, s), Color(0.42, 0.45, 0.5))
		ci.draw_line(c - s * 0.5, c + Vector2(s.x * 0.5, -s.y * 0.5), Color(1, 1, 1, 0.3), 2.0)


func _draw_hazards(ci: Node2D) -> void:
	for h in _prev.get("hazards", []):
		if str(h.get("kind", "")) == "lava":
			HazardArt.draw_lava(ci, h["rect"], _t)
		else:
			HazardArt.draw_spikes(ci, h["rect"], int(h.get("dir", 0)))
	for j in _prev.get("jump_pads", []):
		HazardArt.draw_pad(ci, j["pos"], float(j.get("power", 1150.0)) > 1400.0)
	# Pieces hidden from the preview while dragged: drawn live by _draw_ghosts.


## Advanced mode: the Maker-only things its own view doesn't know (hazards,
## pads, prop sprites).
func draw_extras(ci: Node2D) -> void:
	_draw_hazards(ci)
	var scn: Array = _prev.get("scenery", [])
	var base := int((_prev.get("maker", {}) as Dictionary).get("base_scenery", scn.size()))
	for i in range(base, scn.size()):
		var sc: Dictionary = scn[i]
		var t := Pieces.tex(str(sc.get("tex", "")))
		if t != null:
			var sz: Vector2 = t.get_size() * float(sc.get("scale", 1.0))
			ci.draw_texture_rect(t, Rect2((sc.get("pos", Vector2.ZERO) as Vector2) - sz * 0.5, sz), false)


func _draw_props_scenery(ci: Node2D) -> void:
	for sc in _prev.get("scenery", []):
		var t := Pieces.tex(str(sc.get("tex", "")))
		if t == null:
			continue
		var sz: Vector2 = t.get_size() * float(sc.get("scale", 1.0))
		ci.draw_texture_rect(t, Rect2((sc.get("pos", Vector2.ZERO) as Vector2) - sz * 0.5, sz), false, sc.get("mod", Color.WHITE))


func _draw_entities(ci: Node2D) -> void:
	var s := _ent_size()
	for r in all_refs():
		var k := str(r["k"])
		if k in ["polys", "platforms", "pc", "ladders", "scenery"]:
			continue
		var id := ref_id(r)
		var pos := ref_pos(r)
		var anchor := str(Pieces.def(id).get("anchor", "feet"))
		var foot := pos + Vector2(0, s * 0.5) if anchor == "center" else pos
		var label := ""
		if k == "dom_points":
			label = ["A", "B", "C", "D", "E"][mini(int(r["i"]), 4)]
		if anchor == "feet":
			ci.draw_set_transform(foot, 0.0, Vector2(1.0, 0.25))
			ci.draw_circle(Vector2.ZERO, s * 0.42, Color(0, 0, 0, 0.28))
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if k == "weapon_pickups":
			var pr := Rect2(foot - Vector2(s * 0.62, s * 0.86), Vector2(s * 1.24, s * 0.72))
			var st := UITheme.hud_pill_style(Pieces.GOLD, 0.62)
			st.set_corner_radius_all(int(s * 0.18))
			ci.draw_style_box(st, pr)
		Pieces.draw_entity(ci, id, foot, s, 1.0, label)


func _draw_ghosts(ci: Node2D) -> void:
	# Pieces being dragged / resized (hidden from the compiled preview).
	for i in _excl:
		if int(i) < _pieces().size():
			_draw_piece_ghost(ci, _pieces()[int(i)], 0.75)
	# Palette drag or armed stamp under the cursor.
	var id := _ghost_id
	var at := _ghost_w
	if id == "" and armed != "" and _hover_w != Vector2.INF and _press.is_empty():
		id = armed
		at = _hover_w
	if id == "" or at == Vector2.INF:
		return
	var d := Pieces.def(id)
	var kind := str(d.get("kind", ""))
	if kind in ["shape", "hazard", "prop", "pad"]:
		var p := Build.new_piece(id, Vector2.ZERO)
		if kind == "pad":
			var foot := snapv(at)
			p["x"] = foot.x
			p["y"] = foot.y - float(p["h"]) * 0.5
		else:
			var sz := Build.piece_size(p)
			var tl := snapv(at - sz * 0.5)
			p["x"] = tl.x + sz.x * 0.5
			p["y"] = tl.y + sz.y * 0.5
		_draw_piece_ghost(ci, p, 0.6)
		ci.draw_rect(Build.piece_rect(p), Color(UITheme.COL_NEON, 0.9), false, 1.5 / zoom())
	elif kind == "ladder":
		var lw := float(d.get("w", 20.0))
		var lh := float(d.get("h", 240.0))
		var tl2 := snapv(at - Vector2(lw, lh) * 0.5)
		Pieces.draw_ladder(ci, Rect2(tl2, Vector2(lw, lh)), Color(UITheme.COL_NEON, 0.8))
	elif kind == "scenery":
		var t := Pieces.tex(str(d.get("tex", "")))
		if t != null:
			var sz2 := t.get_size() * float(d.get("scale", 1.0))
			var g := snapv(at)
			ci.draw_texture_rect(t, Rect2(Vector2(g.x - sz2.x * 0.5, g.y - sz2.y), sz2), false, Color(1, 1, 1, 0.6))
	else:
		var g2 := snapv(at)
		var s := _ent_size()
		var foot2 := g2 + Vector2(0, s * 0.5) if str(d.get("anchor", "feet")) == "center" else g2
		Pieces.draw_entity(ci, id, foot2, s, 0.65)
		ci.draw_circle(g2, 3.0 / zoom(), UITheme.COL_NEON)


func _draw_piece_ghost(ci: Node2D, p: Dictionary, alpha: float) -> void:
	var d := Pieces.def(str(p.get("t", "")))
	match str(d.get("kind", "")):
		"shape":
			Pieces.draw_shape_preview(ci, Build.piece_polygon(p), theme(), int(d.get("col", 0)), str(d.get("tint", "")), alpha)
		"hazard":
			var r := Rect2(Vector2(float(p["x"]), float(p["y"])) - Build.piece_size(p) * 0.5, Build.piece_size(p))
			if str(d.get("hz", "")) == "lava":
				Pieces.draw_shape_preview(ci, Build.lava_basin(r), theme(), 0, "", alpha)
				HazardArt.draw_lava(ci, r, _t)
			else:
				HazardArt.draw_spikes(ci, r, int(p.get("r", 0)))
		"pad":
			HazardArt.draw_pad(ci, Vector2(float(p["x"]), float(p["y"]) + float(p["h"]) * 0.5), float(d.get("power", 1150.0)) > 1400.0)
		"prop":
			Pieces.draw_sprite_fit(ci, str(d.get("tex", "")), Build.piece_rect(p), Color(1, 1, 1, alpha))


func _draw_selection(ci: Node2D) -> void:
	var z := zoom()
	for r in sel:
		if not ref_valid(r):
			continue
		var rr := ref_rect(r)
		ci.draw_rect(rr.grow(3.0 / z), Color(UITheme.COL_NEON, 0.95), false, 2.0 / z)
		if str(r["k"]) == "pc":
			var p: Dictionary = _pieces()[int(r["i"])]
			if str(Pieces.def(str(p.get("t", ""))).get("kind", "")) == "shape":
				var poly := Build.piece_polygon(p)
				var loop := PackedVector2Array(poly)
				loop.append(poly[0])
				ci.draw_polyline(loop, Color(UITheme.COL_NEON, 0.55), 1.5 / z)
	if sel.size() == 1 and ref_valid(sel[0]) and _resizable(sel[0]) and _drag != "move":
		for p in _handle_points(ref_rect(sel[0])):
			var hs := HANDLE_PX * 0.55 / z
			ci.draw_rect(Rect2(p - Vector2(hs, hs), Vector2(hs, hs) * 2.0), Color.WHITE)
			ci.draw_rect(Rect2(p - Vector2(hs, hs), Vector2(hs, hs) * 2.0), UITheme.COL_NEON, false, 1.5 / z)


# ── UI ───────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	layer = CanvasLayer.new()
	layer.name = "MakerUI"
	layer.layer = 10
	ed.add_child(layer)
	root = Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var touch := UITheme.is_touch()
	var bh := 46 if touch else 38
	# ── Top bar ──
	_top = PanelContainer.new()
	_top.name = "TopBar"
	_top.add_theme_stylebox_override("panel", _bar_style())
	_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top.offset_left = 10
	_top.offset_right = -10
	_top.offset_top = 8
	root.add_child(_top)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	_top.add_child(hb)
	_file_menu = MenuButton.new()
	_file_menu.text = tr("FILE")
	_file_menu.custom_minimum_size = Vector2(76, bh)
	UITheme.style_button(_file_menu, 16)
	var fp := _file_menu.get_popup()
	fp.add_item(tr("New map"), 0)
	fp.add_item(tr("Save"), 1)
	fp.add_item(tr("Open..."), 2)
	fp.add_separator()
	fp.add_item(tr("Exit to menu"), 3)
	fp.id_pressed.connect(_on_file)
	hb.add_child(_file_menu)
	var title := Label.new()
	title.text = tr("MAKER")
	title.add_theme_font_override("font", UITheme.font("caps"))
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", UITheme.COL_ACCENT)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(title)
	_name = LineEdit.new()
	_name.text = "My map"
	_name.placeholder_text = tr("Map name")
	_name.custom_minimum_size = Vector2(150, bh)
	_name.max_length = 40
	UITheme.style_lineedit(_name)
	_name.text_changed.connect(func(t: String) -> void: ed._name_edit.text = t)
	hb.add_child(_name)
	hb.add_child(_vsep())
	_theme_ob = OptionButton.new()
	_theme_ob.custom_minimum_size = Vector2(132, bh)
	_theme_ob.tooltip_text = tr("Theme: terrain materials, painted edges and sky.")
	for i in Themes.ORDER.size():
		_theme_ob.add_item(tr(Themes.label(Themes.ORDER[i])), i)
	_theme_ob.item_selected.connect(func(i: int) -> void: set_theme(Themes.ORDER[i]))
	UITheme.style_option_button(_theme_ob)
	hb.add_child(_theme_ob)
	_map_menu = MenuButton.new()
	_map_menu.text = tr("MAP")
	_map_menu.tooltip_text = tr("World size and what's below the map.")
	_map_menu.custom_minimum_size = Vector2(70, bh)
	UITheme.style_button(_map_menu, 16)
	var mp := _map_menu.get_popup()
	for i in Build.SIZES.size():
		var s: Array = Build.SIZES[i]
		mp.add_radio_check_item(tr("Size %s (%d x %d)") % [s[0], int(s[1]), int(s[2])], i)
	mp.add_separator()
	mp.add_radio_check_item(tr("Bottomless (falling = death)"), 10)
	mp.add_radio_check_item(tr("Solid floor"), 11)
	mp.id_pressed.connect(_on_map_menu)
	mp.about_to_popup.connect(_sync_map_menu)
	hb.add_child(_map_menu)
	_mode_ob = OptionButton.new()
	_mode_ob.custom_minimum_size = Vector2(150, bh)
	_mode_ob.tooltip_text = tr("The game mode PLAY tests.")
	for i in GameLists.MODE_NAMES.size():
		_mode_ob.add_item(tr(GameLists.MODE_NAMES[i]), i)
	_mode_ob.item_selected.connect(func(i: int) -> void: test_mode = i)
	UITheme.style_option_button(_mode_ob)
	hb.add_child(_mode_ob)
	hb.add_child(_vsep())
	_grid_btn = _small_btn("GRID 20", bh, cycle_grid, tr("Grid size (G)."))
	hb.add_child(_grid_btn)
	_undo_btn = _icon_btn("undo", bh, undo, tr("Undo (Ctrl+Z)."))
	hb.add_child(_undo_btn)
	_redo_btn = _icon_btn("redo", bh, redo, tr("Redo (Ctrl+Y)."))
	hb.add_child(_redo_btn)
	if touch:
		_box_btn = _icon_btn("select", bh, _toggle_box, tr("Drag on empty space to select an area instead of moving the view."))
		hb.add_child(_box_btn)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(spacer)
	hb.add_child(_small_btn(tr("ADVANCED"), bh, func() -> void: ed._set_maker(false), tr("The classic editor tools (free-form polygons, platforms, textures).")))
	var play_btn := Button.new()
	# "PLAY" is the replay viewer's key (= play back): translate "Play" and
	# keep the button from auto-translating the upper-cased result again.
	play_btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	play_btn.text = tr("Play").to_upper()
	play_btn.tooltip_text = tr("Test the map from where the camera is (F5).")
	play_btn.custom_minimum_size = Vector2(120, bh)
	UITheme.style_button(play_btn, 20, true)
	play_btn.pressed.connect(func() -> void: play())
	hb.add_child(play_btn)
	# ── Palette ──
	_palette = PanelContainer.new()
	_palette.name = "Palette"
	_palette.add_theme_stylebox_override("panel", _bar_style())
	_palette.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_palette.offset_left = 10
	_palette.offset_right = -10
	_palette.offset_bottom = -8
	_palette.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(_palette)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 6)
	_palette.add_child(pv)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	pv.add_child(tabs)
	for i in Pieces.TABS.size():
		var tid: String = Pieces.TABS[i]
		var tb := Button.new()
		tb.text = tr(Pieces.TAB_LABELS[tid]).to_upper()
		tb.tooltip_text = "%s (%d)" % [tr(Pieces.TAB_LABELS[tid]), i + 1]
		tb.custom_minimum_size = Vector2(0, 40 if touch else 32)
		tb.focus_mode = Control.FOCUS_NONE
		tb.pressed.connect(func() -> void: set_tab(tid))
		tabs.add_child(tb)
		_tab_btns[tid] = tb
	_hint = Label.new()
	_hint.add_theme_font_override("font", UITheme.font("semi"))
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", UITheme.COL_TEXT_MUTED)
	_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hint.clip_text = true
	_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.custom_minimum_size = Vector2(80, 0)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(_hint)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(0, (118 if touch else 104))
	pv.add_child(_scroll)
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 8)
	_scroll.add_child(_cards)
	# ── Minimap ──
	_mini_panel = PanelContainer.new()
	_mini_panel.name = "Minimap"
	_mini_panel.add_theme_stylebox_override("panel", _bar_style(6))
	_mini_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_mini_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_mini_panel.offset_right = -10
	_mini_panel.offset_top = 8 + bh + 22
	root.add_child(_mini_panel)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 4)
	_mini_panel.add_child(mv)
	_mini = MiniMap.new()
	_mini.maker = self
	_mini.custom_minimum_size = Vector2(220, 92)
	mv.add_child(_mini)
	var zh := HBoxContainer.new()
	zh.add_theme_constant_override("separation", 4)
	mv.add_child(zh)
	for spec in [["-", func() -> void: zoom_at(_screen_mid(), 1.0 / 1.25)], ["+", func() -> void: zoom_at(_screen_mid(), 1.25)],
			[tr("FIT"), fit_view]]:
		var zb := _small_btn(str(spec[0]), 30 if not touch else 40, spec[1], "")
		zb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		zh.add_child(zb)
	# ── Selection bar ──
	_selbar = PanelContainer.new()
	_selbar.name = "SelectionBar"
	_selbar.add_theme_stylebox_override("panel", _bar_style(5))
	_selbar.visible = false
	root.add_child(_selbar)
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 4)
	_selbar.add_child(sh)
	for spec in [["rotate", tr("ROTATE"), rotate_selection, "R"], ["flip", tr("FLIP"), flip_selection, "F"],
			["dup", tr("COPY"), duplicate_selection, "Ctrl+D"], ["del", tr("DELETE"), delete_selection, "Del"]]:
		var b := _small_btn(str(spec[1]), 40 if touch else 32, spec[2], "%s (%s)" % [str(spec[1]).capitalize(), spec[3]])
		sh.add_child(b)
		_selbar_btns[spec[0]] = b
	# ── Context menu ──
	_ctx = PanelContainer.new()
	_ctx.name = "ContextMenu"
	_ctx.add_theme_stylebox_override("panel", _bar_style(6))
	_ctx.visible = false
	root.add_child(_ctx)
	_ctx_box = VBoxContainer.new()
	_ctx_box.add_theme_constant_override("separation", 4)
	_ctx.add_child(_ctx_box)
	# ── Problems sheet ──
	_probs = PanelContainer.new()
	_probs.name = "Problems"
	_probs.add_theme_stylebox_override("panel", UITheme.panel_style())
	_probs.set_anchors_preset(Control.PRESET_CENTER)
	_probs.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_probs.grow_vertical = Control.GROW_DIRECTION_BOTH
	_probs.custom_minimum_size = Vector2(560, 0)
	_probs.visible = false
	root.add_child(_probs)
	var pvb := VBoxContainer.new()
	pvb.add_theme_constant_override("separation", 8)
	_probs.add_child(pvb)
	_probs_title = Label.new()
	UITheme.style_head(_probs_title, UITheme.FS_H2)
	pvb.add_child(_probs_title)
	pvb.add_child(UITheme.make_rule())
	_probs_list = VBoxContainer.new()
	_probs_list.add_theme_constant_override("separation", 4)
	pvb.add_child(_probs_list)
	var pbh := HBoxContainer.new()
	pbh.add_theme_constant_override("separation", 8)
	pbh.alignment = BoxContainer.ALIGNMENT_END
	pvb.add_child(pbh)
	pbh.add_child(_small_btn(tr("KEEP EDITING"), bh, _close_popups, ""))
	_probs_go = Button.new()
	_probs_go.text = tr("PLAY ANYWAY")
	_probs_go.custom_minimum_size = Vector2(150, bh)
	UITheme.style_button(_probs_go, 16, true)
	_probs_go.pressed.connect(func() -> void:
		_close_popups()
		if _pending_after_probs == "play":
			play(true))
	pbh.add_child(_probs_go)
	# ── Load sheet ──
	_load = PanelContainer.new()
	_load.name = "Open"
	_load.add_theme_stylebox_override("panel", UITheme.panel_style())
	_load.set_anchors_preset(Control.PRESET_CENTER)
	_load.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_load.grow_vertical = Control.GROW_DIRECTION_BOTH
	_load.custom_minimum_size = Vector2(480, 380)
	_load.visible = false
	root.add_child(_load)
	var lvb := VBoxContainer.new()
	lvb.add_theme_constant_override("separation", 8)
	_load.add_child(lvb)
	var lt := Label.new()
	lt.text = tr("OPEN A MAP")
	UITheme.style_head(lt, UITheme.FS_H2)
	lvb.add_child(lt)
	lvb.add_child(UITheme.make_rule())
	var lsc := ScrollContainer.new()
	lsc.custom_minimum_size = Vector2(0, 260)
	lsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lvb.add_child(lsc)
	_load_list = VBoxContainer.new()
	_load_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_load_list.add_theme_constant_override("separation", 4)
	lsc.add_child(_load_list)
	lvb.add_child(_small_btn(tr("CLOSE"), bh, _close_popups, ""))
	# ── Toast ──
	_toast = Label.new()
	_toast.name = "Toast"
	_toast.add_theme_stylebox_override("normal", UITheme.hud_pill_style(UITheme.COL_ACCENT, 0.8))
	_toast.add_theme_font_override("font", UITheme.font("semi"))
	_toast.add_theme_font_size_override("font_size", 15)
	_toast.add_theme_color_override("font_color", UITheme.COL_TEXT)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = 8 + bh + 30
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast)
	UITheme.apply_ui_scale(root)
	UITheme.UIFx.watch(_top, Vector2.UP)
	UITheme.UIFx.watch(_palette, Vector2.DOWN)
	UITheme.UIFx.watch(_probs, Vector2.DOWN)
	UITheme.UIFx.watch(_load, Vector2.DOWN)
	set_tab("terrain")
	_sync_controls()


func _bar_style(pad: int = 8) -> StyleBoxFlat:
	var s := UITheme.hud_strip_style()
	s.bg_color = Color(UITheme.COL_PANEL.r, UITheme.COL_PANEL.g, UITheme.COL_PANEL.b, 0.9)
	s.content_margin_left = pad + 2
	s.content_margin_right = pad + 2
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 10
	return s


func _vsep() -> Control:
	var c := ColorRect.new()
	c.color = UITheme.COL_BORDER
	c.custom_minimum_size = Vector2(1, 26)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _small_btn(text: String, h: int, cb: Callable, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, h)
	UITheme.style_button(b, 15)
	b.pressed.connect(cb)
	return b


## A square button with a vector icon (no text: fits every language).
func _icon_btn(kind: String, h: int, cb: Callable, tip: String) -> Button:
	var b := _small_btn("", h, cb, tip)
	b.custom_minimum_size = Vector2(h + 4, h)
	b.draw.connect(_draw_icon.bind(b, kind))
	return b


func _draw_icon(b: Button, kind: String) -> void:
	var col := UITheme.COL_TEXT_MUTED if b.disabled else UITheme.COL_TEXT
	if kind == "select" and box_mode:
		col = UITheme.COL_ON_ACCENT
	var c := b.size * 0.5
	var r := minf(b.size.x, b.size.y) * 0.24
	if kind == "undo" or kind == "redo":
		# An arc over the top with an arrowhead pointing down at one end.
		var o := c + Vector2(0, r * 0.3)
		b.draw_arc(o, r, PI, TAU, 16, col, 2.0, true)
		var ex := o.x - r if kind == "undo" else o.x + r
		b.draw_colored_polygon(PackedVector2Array([Vector2(ex, o.y + r * 0.62),
			Vector2(ex - r * 0.48, o.y - r * 0.02), Vector2(ex + r * 0.48, o.y - r * 0.02)]), col)
		return
	# "select": a dashed box.
	var rr := Rect2(c - Vector2(r, r * 0.8), Vector2(r * 2.0, r * 1.6))
	var dash := r * 0.36
	var x := rr.position.x
	while x < rr.end.x:
		b.draw_line(Vector2(x, rr.position.y), Vector2(minf(x + dash, rr.end.x), rr.position.y), col, 1.6)
		b.draw_line(Vector2(x, rr.end.y), Vector2(minf(x + dash, rr.end.x), rr.end.y), col, 1.6)
		x += dash * 2.0
	var y := rr.position.y
	while y < rr.end.y:
		b.draw_line(Vector2(rr.position.x, y), Vector2(rr.position.x, minf(y + dash, rr.end.y)), col, 1.6)
		b.draw_line(Vector2(rr.end.x, y), Vector2(rr.end.x, minf(y + dash, rr.end.y)), col, 1.6)
		y += dash * 2.0


func _screen_mid() -> Vector2:
	return ed.get_viewport().get_visible_rect().size * 0.5


func set_tab(t: String) -> void:
	if not (t in Pieces.TABS):
		return
	tab = t
	for k in _tab_btns:
		UITheme.style_button(_tab_btns[k], 14, k == t)
	for c in _cards.get_children():
		c.queue_free()
	var touch := UITheme.is_touch()
	for id in Pieces.ids_for_tab(t):
		var card := PieceCard.new()
		card.maker = self
		card.piece = id
		card.custom_minimum_size = Vector2(100, 116) if touch else Vector2(88, 102)
		card.tooltip_text = "%s\n%s" % [tr(str(Pieces.def(id).get("label", ""))), tr(str(Pieces.def(id).get("tip", "")))]
		_cards.add_child(card)
	_scroll.scroll_horizontal = 0


func _refresh_cards() -> void:
	for c in _cards.get_children():
		c.queue_redraw()


func _toggle_box() -> void:
	box_mode = not box_mode
	if _box_btn != null:
		UITheme.style_button(_box_btn, 15, box_mode)
		_box_btn.queue_redraw()
	toast(tr("Drag on empty space selects an area.") if box_mode else tr("Drag on empty space moves the view."))


func _sync_controls() -> void:
	if _theme_ob == null or ed == null:
		return
	_theme_ob.select(maxi(0, Themes.ORDER.find(theme())))
	_mode_ob.select(clampi(test_mode, 0, GameLists.MODE_NAMES.size() - 1))
	_grid_btn.text = tr("GRID %d") % grid()
	_refresh_cards()
	_sync_undo()


func _sync_undo() -> void:
	if _undo_btn != null:
		_undo_btn.disabled = (ed._undo as Array).is_empty() and str(ed._map).hash() == ed._snap_sig
		_redo_btn.disabled = (ed._redo as Array).is_empty()


func _sync_map_menu() -> void:
	var mp := _map_menu.get_popup()
	var ws := world_size()
	for i in Build.SIZES.size():
		var s: Array = Build.SIZES[i]
		mp.set_item_checked(mp.get_item_index(i), is_equal_approx(ws.x, float(s[1])) and is_equal_approx(ws.y, float(s[2])))
	var bottom := str(_mk().get("bottom", "void"))
	mp.set_item_checked(mp.get_item_index(10), bottom == "void")
	mp.set_item_checked(mp.get_item_index(11), bottom == "floor")


func _on_map_menu(id: int) -> void:
	if id < 10:
		set_world(id, "")
		toast(tr("World size changed."))
	else:
		set_world(-1, "void" if id == 10 else "floor")
		toast(tr("Falling off the bottom kills.") if id == 10 else tr("A solid floor runs under the whole map."))


func _on_file(id: int) -> void:
	match id:
		0: new_map()
		1: save()
		2: _open_load()
		3: ed._exit_to_menu()


func _hint_default() -> void:
	if _hint == null:
		return
	if UITheme.is_touch():
		_hint.text = tr("Drag pieces up onto the map · one finger moves the view · pinch to zoom · hold for options")
	else:
		_hint.text = tr("Drag pieces onto the map · wheel zoom · right-drag pan · R rotate · F flip · Del delete")


func toast(msg: String, alert: bool = false) -> void:
	if _toast == null:
		return
	_toast.text = msg
	_toast.add_theme_stylebox_override("normal", UITheme.hud_pill_style(UITheme.COL_ALERT if alert else UITheme.COL_ACCENT, 0.85))
	_toast.visible = true
	_toast.reset_size()
	_toast.offset_left = -_toast.size.x * 0.5
	_toast.offset_right = _toast.size.x * 0.5
	_toast_t = 2.6
	UITheme.UIFx.pop(_toast)


## BACK / Esc (map_editor.go_back): close a sheet / disarm / deselect first.
## True = handled; false = nothing left, the editor leaves.
func back_pressed() -> bool:
	if (_ctx != null and _ctx.visible) or (_probs != null and _probs.visible) or (_load != null and _load.visible):
		_close_popups()
		return true
	if armed != "":
		disarm()
		return true
	if not sel.is_empty():
		sel.clear()
		_place_selbar()
		ed.queue_redraw()
		return true
	return false


func _close_popups() -> void:
	if _ctx != null:
		_ctx.visible = false
	if _probs != null:
		_probs.visible = false
	if _load != null:
		_load.visible = false


func _place_selbar() -> void:
	if _selbar == null:
		return
	var valid: Array = []
	for r in sel:
		if ref_valid(r):
			valid.append(r)
	sel = valid
	if sel.is_empty() or _drag == "move" or _drag == "resize" or not active:
		_selbar.visible = false
		return
	var rr := ref_rect(sel[0])
	for r in sel:
		rr = rr.merge(ref_rect(r))
	var can_rot := false
	var can_flip := false
	for r in sel:
		if str(r["k"]) == "pc":
			can_rot = can_rot or Pieces.can_rotate(ref_id(r))
			can_flip = can_flip or Pieces.can_flip(ref_id(r))
	_selbar_btns["rotate"].visible = can_rot
	_selbar_btns["flip"].visible = can_flip
	_selbar.visible = true
	_selbar.reset_size()
	var a := to_screen(Vector2(rr.get_center().x, rr.position.y))
	var vs := root.size
	var p := Vector2(a.x - _selbar.size.x * 0.5, a.y - _selbar.size.y - 14.0)
	if p.y < _top_h():
		p.y = to_screen(rr.end).y + 14.0
	p.x = clampf(p.x, 8.0, vs.x - _selbar.size.x - 8.0)
	p.y = clampf(p.y, _top_h(), vs.y - _palette_h() - _selbar.size.y)
	_selbar.position = p


func _open_context(sp: Vector2) -> void:
	for c in _ctx_box.get_children():
		c.queue_free()
	var touch := UITheme.is_touch()
	var h := 42 if touch else 32
	var items: Array = []
	if not sel.is_empty():
		items.append([tr("Duplicate"), duplicate_selection])
		items.append([tr("Rotate"), rotate_selection])
		items.append([tr("Flip"), flip_selection])
		items.append([tr("Delete"), delete_selection])
	else:
		var at := to_world(sp)
		items.append([tr("Select area") if not box_mode else tr("Move the view"), _toggle_box])
		items.append([tr("Select all"), select_all])
		items.append([tr("Zoom to fit"), fit_view])
		if armed != "":
			items.append([tr("Place %s here") % tr(str(Pieces.def(armed).get("label", ""))), func() -> void: place(armed, at)])
	items.append([tr("Undo"), undo])
	for it in items:
		var cb: Callable = it[1]
		var b := _small_btn(str(it[0]), h, func() -> void:
			_ctx.visible = false
			cb.call(), "")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.x = 170
		_ctx_box.add_child(b)
	_ctx.visible = true
	_ctx.reset_size()
	var vs := root.size
	_ctx.position = Vector2(clampf(sp.x, 8.0, vs.x - _ctx.size.x - 8.0), clampf(sp.y, 8.0, vs.y - _ctx.size.y - 8.0))
	UITheme.UIFx.pop(_ctx)


func _show_problems(probs: Array, after: String) -> void:
	_pending_after_probs = after
	for c in _probs_list.get_children():
		c.queue_free()
	var errors := Build.has_errors(probs)
	_probs_title.text = tr("A FEW THINGS TO FIX FIRST") if errors else tr("BEFORE YOU PLAY")
	for p in probs.slice(0, 8):
		var row := Button.new()
		var err := str(p.get("lvl", "")) == "error"
		row.text = ("✖  " if err else "!  ") + str(p.get("msg", ""))
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.custom_minimum_size = Vector2(520, 36)
		UITheme.style_button(row, 15)
		row.add_theme_font_override("font", UITheme.font("semi"))
		row.add_theme_color_override("font_color", UITheme.COL_ALERT if err else UITheme.COL_ACCENT_HI)
		var at: Vector2 = p.get("at", Vector2.ZERO)
		row.pressed.connect(func() -> void:
			_close_popups()
			ed._cam.position = at
			_clamp_cam()
			ed.queue_redraw())
		_probs_list.add_child(row)
	if probs.size() > 8:
		_probs_list.add_child(UITheme.make_sub_label(tr("...and %d more.") % (probs.size() - 8)))
	_probs_go.visible = not errors and after == "play"
	_probs.visible = true


func _open_load() -> void:
	_close_popups()
	for c in _load_list.get_children():
		c.queue_free()
	var files := MapIO.list_files()
	var shown := 0
	for pv in files:
		var path := str(pv)
		if path.ends_with("/_playtest.json"):
			continue
		shown += 1
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lb := Label.new()
		lb.text = path.get_file().get_basename()
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.style_body(lb, 16)
		row.add_child(lb)
		row.add_child(_small_btn(tr("OPEN"), 34, func() -> void: load_path(path), ""))
		_load_list.add_child(row)
	if shown == 0:
		_load_list.add_child(UITheme.make_sub_label(tr("No saved maps yet — build one and Save.")))
	_load.visible = true


# ── Inner widgets ────────────────────────────────────────────────────────────

## One palette card: vector thumbnail + label. Press-drag up = drag the
## piece onto the map, tap = arm it for stamping, swipe sideways = scroll.
class PieceCard extends Control:
	var maker = null
	var piece := ""
	var _hover := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func() -> void:
			_hover = true
			queue_redraw())
		mouse_exited.connect(func() -> void:
			_hover = false
			queue_redraw())

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton:
			var mb := e as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					maker.palette_press(piece, get_global_mouse_position())
				else:
					maker.palette_release(get_global_mouse_position())
				accept_event()
			elif mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_DOWN or mb.button_index == MOUSE_BUTTON_WHEEL_RIGHT):
				maker._scroll.scroll_horizontal += 60
				accept_event()
			elif mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_LEFT):
				maker._scroll.scroll_horizontal -= 60
				accept_event()
		elif e is InputEventMouseMotion and ((e as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			maker.palette_motion(get_global_mouse_position(), (e as InputEventMouseMotion).relative)
			accept_event()

	func _draw() -> void:
		var armed: bool = maker.armed == piece
		var st := UITheme.card_style()
		st.set_corner_radius_all(UITheme.RADIUS_PANEL)
		if armed:
			st.border_color = UITheme.COL_ACCENT
			st.set_border_width_all(2)
			st.bg_color = Color(0.16, 0.11, 0.06, 0.95)
		elif _hover:
			st.border_color = UITheme.COL_NEON
			st.bg_color = UITheme.COL_PANEL_HI.lightened(0.06)
		draw_style_box(st, Rect2(Vector2.ZERO, size))
		var f := UITheme.font("semi")
		var lbl := tr(str(Pieces.def(piece).get("label", piece)))
		var col := UITheme.COL_ACCENT_HI if armed else (UITheme.COL_TEXT if _hover else UITheme.COL_TEXT_DIM)
		# One line at 12 px, else two lines (split at the middle-most space).
		var lines: Array = [lbl]
		var fs := 12
		if f.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x - 8 and lbl.contains(" "):
			var best := -1
			for i in lbl.length():
				if lbl[i] == " " and (best < 0 or absi(i - lbl.length() / 2) < absi(best - lbl.length() / 2)):
					best = i
			lines = [lbl.substr(0, best), lbl.substr(best + 1)]
			fs = 11
		for ln in lines:
			while f.get_string_size(str(ln), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x - 8 and fs > 8:
				fs -= 1
		var lh := fs + 2
		var thumb := Rect2(6, 6, size.x - 12, size.y - 14 - lh * lines.size() - 4)
		Pieces.draw_thumb(self, piece, thumb, maker.theme())
		for li in lines.size():
			var w := f.get_string_size(str(lines[li]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var y := size.y - 9 - float(lines.size() - 1 - li) * lh
			draw_string(f, Vector2((size.x - w) * 0.5, y), str(lines[li]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Whole-world overview: terrain silhouettes, objectives, the camera view.
## Click / drag to move the camera there.
class MiniMap extends Control:
	var maker = null

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = tr("Overview — click to jump there.")

	func _xf() -> Array:
		var ws: Vector2 = maker.world_size()
		var k: float = minf(size.x / ws.x, size.y / ws.y)
		var off := (size - ws * k) * 0.5
		return [k, off]

	func _gui_input(e: InputEvent) -> void:
		var go := false
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			go = true
		elif e is InputEventMouseMotion and ((e as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			go = true
		if go:
			var x := _xf()
			var p: Vector2 = ((e as InputEventMouse).position - (x[1] as Vector2)) / float(x[0])
			maker.ed._cam.position = p
			maker._clamp_cam()
			accept_event()

	func _draw() -> void:
		var x := _xf()
		var k: float = x[0]
		var off: Vector2 = x[1]
		var ws: Vector2 = maker.world_size()
		var th: String = maker.theme()
		var top: Color = Themes.sky_color(th, true)
		var bot: Color = Themes.sky_color(th, false)
		draw_polygon(PackedVector2Array([off, off + Vector2(ws.x * k, 0), off + ws * k, off + Vector2(0, ws.y * k)]),
			PackedColorArray([top.darkened(0.3), top.darkened(0.3), bot.darkened(0.3), bot.darkened(0.3)]))
		var pv: Dictionary = maker.preview()
		var land: Color = Themes.get_theme(th)["body"]
		for o in pv.get("_mk_outlines", []):
			var pts := PackedVector2Array()
			for p in o["pts"]:
				pts.append(off + p * k)
			if pts.size() >= 3 and not Geometry2D.triangulate_polygon(pts).is_empty():
				draw_colored_polygon(pts, land.lightened(0.15) if int(o["col"]) == 0 else Color(land, 0.7))
		if pv.get("_mk_outlines", []).is_empty():
			for poly in pv.get("polys", []):
				var pts2 := PackedVector2Array()
				for p in poly.get("points", PackedVector2Array()):
					pts2.append(off + p * k)
				if pts2.size() >= 3 and not Geometry2D.triangulate_polygon(pts2).is_empty():
					draw_colored_polygon(pts2, land)
		for h in pv.get("hazards", []):
			var r: Rect2 = h["rect"]
			draw_rect(Rect2(off + r.position * k, (r.size * k).max(Vector2(2, 2))), Color(1.0, 0.4, 0.15) if str(h.get("kind", "")) == "lava" else Color(0.85, 0.88, 0.92))
		var m: Dictionary = maker.ed._map
		var ts: Variant = m.get("team_spawns", {})
		if typeof(ts) == TYPE_DICTIONARY:
			for v in (ts as Dictionary).get(1, []):
				draw_circle(off + (v as Vector2) * k, 2.5, Pieces.BLUE)
			for v in (ts as Dictionary).get(2, []):
				draw_circle(off + (v as Vector2) * k, 2.5, Pieces.RED)
		var fl: Array = m.get("ctf_flags", [])
		for i in fl.size():
			draw_rect(Rect2(off + (fl[i] as Vector2) * k - Vector2(2, 5), Vector2(4, 6)), Pieces.BLUE if i == 0 else Pieces.RED)
		draw_circle(off + (m.get("player_spawn", Vector2.ZERO) as Vector2) * k, 2.5, Pieces.EMBER)
		# Camera view.
		var vs: Vector2 = maker.ed.get_viewport().get_visible_rect().size
		var a: Vector2 = maker.to_world(Vector2.ZERO)
		var b: Vector2 = maker.to_world(vs)
		var vr := Rect2(off + a * k, (b - a) * k).intersection(Rect2(Vector2.ZERO, size))
		draw_rect(vr, Color(UITheme.COL_NEON, 0.12))
		draw_rect(vr, UITheme.COL_NEON, false, 1.5)
		draw_rect(Rect2(off, ws * k), Color(1, 1, 1, 0.3), false, 1.0)
