extends RefCounted
## Team colours in one place (v1.23, #306). Settings → Video "Team colours"
## picks the palette and applies live (soldiers, rims, ally markers, vehicles,
## flags, score strip, kill feed, objective HUD all read it here):
##   classic    — clear cyan-blue vs red-orange
##   colorblind — blue vs orange (reads for the common red-green types)
##   contrast   — bright cyan vs hot red-magenta, stronger soldier outlines
## blue() / red() are the body / UI colours, paint() the saturated soldier team
## paint (Operator _acc panels, the classic helmet + vest), rim() the outline.
## Free-for-all modes (DM / RM / BR / GG) have no teams: team_of() is 0 there
## and soldiers keep their own colours.

const STYLES := ["classic", "colorblind", "contrast"]

## Team of the soldier the local player is (1 / 2, else 0): allies get a
## softer outline than enemies. Kept by team_markers.gd during a match.
static var viewer_team := 0
# Settings reads cached per frame (every soldier asks several times a frame).
static var _frame := -1
static var _style := "classic"
static var _team_mode := false
static var _zombie := false   # #314: Zombie mode — the red side is the zombies (green)


static func _refresh() -> void:
	var f := Engine.get_process_frames()
	if f == _frame:
		return
	_frame = f
	var ml := Engine.get_main_loop() as SceneTree
	var st: Node = ml.root.get_node_or_null("Settings") if ml != null else null
	if st == null:
		_style = "classic"
		_team_mode = false
		_zombie = false
		return
	var s := str(st.get("team_colors"))
	_style = s if STYLES.has(s) else "classic"
	_team_mode = bool(st.call("is_team_mode"))
	_zombie = int(st.get("game_mode")) == 11


## Settings changed this frame (the Video tab, tests): re-read at once.
static func invalidate() -> void:
	_frame = -1


static func style() -> String:
	_refresh()
	return _style


static func blue(bright := false) -> Color:
	match style():
		"colorblind":
			return Color(0.32, 0.56, 1.0) if bright else Color(0.24, 0.46, 1.0)
		"contrast":
			return Color(0.3, 0.86, 1.0) if bright else Color(0.18, 0.72, 1.0)
	return Color(0.36, 0.64, 1.0) if bright else Color(0.26, 0.52, 1.0)


static func red(bright := false) -> Color:
	if zombie_mode() and style() != "colorblind":
		# #314: zombies are a sickly green (colourblind keeps its orange).
		if style() == "contrast":
			return Color(0.62, 1.0, 0.16) if bright else Color(0.5, 0.95, 0.08)
		return Color(0.55, 0.92, 0.32) if bright else Color(0.42, 0.78, 0.22)
	match style():
		"colorblind":
			return Color(1.0, 0.68, 0.18) if bright else Color(0.95, 0.58, 0.1)
		"contrast":
			return Color(1.0, 0.3, 0.45) if bright else Color(0.95, 0.16, 0.32)
	return Color(1.0, 0.42, 0.3) if bright else Color(0.92, 0.28, 0.18)


## #314: Zombie mode (team 2 = the zombies, drawn green).
static func zombie_mode() -> bool:
	_refresh()
	return _zombie


## 1 = blue, 2 = red; anything else gets `other`.
static func for_team(t: int, bright := false, other := Color(0.6, 0.6, 0.6)) -> Color:
	if t == 1:
		return blue(bright)
	if t == 2:
		return red(bright)
	return other


## Saturated soldier team paint (#306): big panels, value-separated (the blue
## side lighter, the red side deeper) so it also reads in greyscale-ish light.
static func paint(t: int) -> Color:
	var s := style()
	if t == 1:
		match s:
			"colorblind": return Color(0.12, 0.46, 1.0)
			"contrast": return Color(0.1, 0.9, 1.0)
		return Color(0.16, 0.62, 1.0)
	if t == 2:
		if _zombie and s != "colorblind":
			return Color(0.55, 1.0, 0.12) if s == "contrast" else Color(0.36, 0.82, 0.12)
		match s:
			"colorblind": return Color(1.0, 0.6, 0.04)
			"contrast": return Color(1.0, 0.1, 0.32)
		return Color(1.0, 0.27, 0.08)
	return Color.WHITE


## Soldier outline colour; alpha = strength. Enemies of the local player get a
## stronger one than allies; with no local team (menus, replays) both medium.
static func rim(t: int) -> Color:
	if t != 1 and t != 2:
		return Color(0, 0, 0, 0)
	var c := paint(t).lerp(Color.WHITE, 0.25)
	var a := 0.7
	if viewer_team == 1 or viewer_team == 2:
		a = 0.5 if t == viewer_team else 0.9
	if style() == "contrast":
		a = minf(1.0, a * 1.3)
		c = paint(t).lerp(Color.WHITE, 0.15)
	c.a = a
	return c


## The team a soldier shows (1 / 2) — 0 in free-for-all modes or with no team.
static func team_of(team: int) -> int:
	if team != 1 and team != 2:
		return 0
	_refresh()
	return team if _team_mode else 0


## Body colour to draw a soldier with: the live team colour in team modes (so a
## palette change applies at once), else the soldier's own colour.
static func body_for(team: int, own: Color) -> Color:
	var t := team_of(team)
	return for_team(t) if t > 0 else own
