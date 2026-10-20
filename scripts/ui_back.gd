extends RefCounted
## BACK rule: the Android system BACK button / gesture
## (NOTIFICATION_WM_GO_BACK_REQUEST; project.godot has quit_on_go_back off),
## Esc and the `ui_cancel` action all mean the same thing: close the TOP-MOST
## overlay / dialog first. Only with nothing open does a screen fall back to
## its own "leave" path (menu sub-screen -> main list, main list -> quit,
## editor -> menu, play-test -> EDIT, match -> pause menu).
##
## Each scene has exactly ONE dispatcher (menu.gd `_go_back`, map_editor.gd
## `go_back`, pause_menu.gd `go_back`, replay_player.gd) that handles both the
## notification and the key; overlays never handle BACK / Esc themselves, they
## `register()` a close callable here and the dispatcher calls `dismiss()`
## first. The notification reaches every node in the tree, so a second
## handler in the same scene would close two things at once.

const GROUP := &"ui_back"
const META := &"ui_back"


## While `c` is visible in the tree, BACK / Esc runs `on_back` (and nothing
## below it reacts). Pass a no-op for a dialog that must stay up (BACK is then
## swallowed instead of leaving the screen behind it).
static func register(c: CanvasItem, on_back: Callable) -> void:
	c.set_meta(META, on_back)
	if not c.is_in_group(GROUP):
		c.add_to_group(GROUP)


## Esc (keycode or scancode) or the `ui_cancel` action, pressed, not an echo.
static func is_back_event(ev: InputEvent) -> bool:
	if ev == null or not ev.is_pressed() or ev.is_echo():
		return false
	if ev is InputEventKey:
		var k := ev as InputEventKey
		if k.keycode == KEY_ESCAPE or k.physical_keycode == KEY_ESCAPE:
			return true
	return InputMap.has_action("ui_cancel") and ev.is_action_pressed("ui_cancel")


## Hides an open embedded popup (OptionButton / MenuButton list, any Popup or
## dialog window). Esc already closes these by itself — they take input before
## the scene — but the BACK notification goes straight to the scene.
static func close_popup(vp: Viewport) -> bool:
	if vp == null:
		return false
	var wins: Array = vp.get_embedded_subwindows()
	for i in range(wins.size() - 1, -1, -1):
		var w := wins[i] as Window
		if w == null or not w.visible:
			continue
		# Tooltips are no-focus, click-through popups: not something to close.
		if w.get_flag(Window.FLAG_NO_FOCUS) or w.get_flag(Window.FLAG_MOUSE_PASSTHROUGH):
			continue
		if w is Popup or w is AcceptDialog or w.transient:
			w.hide()
			return true
	return false


## The registered overlay drawn on top (highest canvas layer, then last in
## tree order), or null when none is showing.
static func top(tree: SceneTree) -> CanvasItem:
	var best: CanvasItem = null
	var best_layer := 0
	var nodes: Array = tree.get_nodes_in_group(GROUP)
	for i in range(nodes.size() - 1, -1, -1):
		var c := nodes[i] as CanvasItem
		if c == null or not c.is_visible_in_tree() or not c.has_meta(META):
			continue
		var cl := c.get_canvas_layer_node()
		var l := cl.layer if cl != null else 0
		if best == null or l > best_layer:
			best = c
			best_layer = l
	return best


## Closes the top popup, else the top registered overlay. True = BACK used.
static func dismiss(tree: SceneTree) -> bool:
	if tree == null:
		return false
	if close_popup(tree.root):
		return true
	var c := top(tree)
	if c == null:
		return false
	var cb = c.get_meta(META)
	if cb is Callable and (cb as Callable).is_valid():
		(cb as Callable).call()
	return true
