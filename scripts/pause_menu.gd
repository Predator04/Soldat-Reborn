extends CanvasLayer
## Pause menu — ESC-triggered overlay with Resume / Settings / Exit-to-Menu / Exit-Game.
##
## Sits above the HUD and drives get_tree().paused so weapons/bots freeze while
## the menu is open. Process runs while paused (PROCESS_MODE_ALWAYS) so the
## keyboard ESC toggle and button presses still fire.

const ControlsMenu = preload("res://scripts/controls_menu.gd")
const SettingsPanel = preload("res://scripts/settings_panel.gd")
const HostAdminPanel = preload("res://scripts/host_admin_panel.gd")
const UITheme = preload("res://scripts/ui_theme.gd")
const UIBack = preload("res://scripts/ui_back.gd")
const TouchControls = preload("res://scripts/touch_controls.gd")

var _root_panel: Control
var _menu_box: VBoxContainer
var _settings_panel: Node        # SettingsPanel (glassmorphism accordion, #73)
var _controls_panel: VBoxContainer
var _host_admin_panel: Node      # HostAdminPanel (#74) — host-only match config
var _host_admin_btn: Button      # shortcut on the pause list; only visible to host/SP
var _quit_confirm: VBoxContainer
var _dim: ColorRect
var _open := false
# #93: focus seeds so arrow-key / gamepad nav lands somewhere sensible on open.
var _resume_btn: Button = null
var _quit_cancel_btn: Button = null


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS

	_root_panel = Control.new()
	_root_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root_panel.visible = false
	# Block clicks from falling through to the HUD/game underneath.
	_root_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_root_panel)

	_dim = ColorRect.new()
	_dim.color = Color(0.01, 0.015, 0.025, 0.62)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_panel.add_child(_dim)

	_build_main_menu()
	_build_settings_panel()
	_build_controls_panel()
	_build_host_admin_panel()
	_build_quit_confirm()
	# #272: UI scale + enter animations (ui_fx.gd): the dim fades, the pause
	# list rises in, sub-screens slide in from the right (instant with Reduce
	# motion). Opening / closing stays synchronous — only the look animates.
	UITheme.apply_ui_scale(_root_panel)
	UITheme.UIFx.watch(_dim, Vector2.ZERO)
	UITheme.UIFx.watch(_menu_wrapper, Vector2.DOWN)
	for p in [_settings_panel, _controls_panel, _host_admin_panel]:
		UITheme.UIFx.watch(p, Vector2.RIGHT)
	UITheme.UIFx.watch(_quit_confirm_wrapper, Vector2.DOWN)


var _menu_wrapper: PanelContainer  # framed panel that hosts _menu_box


func _build_main_menu() -> void:
	# Wrap the pause list in a framed panel so it reads as a briefing terminal,
	# consistent with every other menu surface.
	_menu_wrapper = PanelContainer.new()
	_menu_wrapper.add_theme_stylebox_override("panel", UITheme.panel_style())
	_menu_wrapper.set_anchors_preset(Control.PRESET_CENTER, true)
	_menu_wrapper.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu_wrapper.grow_vertical = Control.GROW_DIRECTION_BOTH
	_menu_wrapper.process_mode = Node.PROCESS_MODE_ALWAYS
	_root_panel.add_child(_menu_wrapper)

	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 10)
	_menu_box.custom_minimum_size = Vector2(340, 0)
	_menu_box.process_mode = Node.PROCESS_MODE_ALWAYS
	_menu_wrapper.add_child(_menu_box)

	var title := UITheme.make_screen_title("PAUSED", 46)
	_menu_box.add_child(title)
	# Session line: map / mode, and in multiplayer where you're hosting or
	# connected (so a host can read the address out to LAN friends).
	_info_lbl = Label.new()
	_info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_lbl.add_theme_font_size_override("font_size", 13)
	_info_lbl.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)
	_menu_box.add_child(_info_lbl)

	_menu_box.add_child(UITheme.make_rule())

	_menu_box.add_child(UITheme.spacer(4))

	var resume := _make_button("RESUME", true)
	resume.pressed.connect(close)
	_menu_box.add_child(resume)
	_resume_btn = resume

	var settings := _make_button("SETTINGS")
	settings.pressed.connect(_open_settings)
	_menu_box.add_child(settings)

	# HOST SETTINGS — only visible to the host (or SP, which is functionally the
	# local host). Clients can't tweak match rules. Visibility is refreshed on
	# open() so the button appears/disappears if Net mode changes mid-session.
	_copy_code_btn = _make_button("COPY JOIN CODE")
	_copy_code_btn.tooltip_text = "Copies a message with your join code to paste to friends."
	_copy_code_btn.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(Net.share_text())
		_copy_code_btn.text = "COPIED!"
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			if is_instance_valid(_copy_code_btn):
				_copy_code_btn.text = "COPY JOIN CODE"))
	_menu_box.add_child(_copy_code_btn)

	_host_admin_btn = _make_button("HOST SETTINGS")
	_host_admin_btn.pressed.connect(_open_host_admin)
	_menu_box.add_child(_host_admin_btn)

	var to_menu := _make_button("EXIT TO MENU")
	to_menu.pressed.connect(_exit_to_menu)
	_menu_box.add_child(to_menu)

	var quit_btn := _make_button("EXIT GAME")
	quit_btn.pressed.connect(_open_quit_confirm)
	_menu_box.add_child(quit_btn)


func _build_settings_panel() -> void:
	# Reuses the glassmorphism accordion Settings screen (#73) from the main menu
	# so both routes share layout, defaults, and persistence.
	_settings_panel = SettingsPanel.new()
	_settings_panel.visible = false
	_root_panel.add_child(_settings_panel)
	_settings_panel.back_pressed.connect(_close_settings)
	_settings_panel.controls_pressed.connect(_open_controls)


func _build_controls_panel() -> void:
	_controls_panel = ControlsMenu.new()
	_controls_panel.visible = false
	_controls_panel.back_pressed.connect(_close_controls)
	_root_panel.add_child(_controls_panel)


func _build_host_admin_panel() -> void:
	_host_admin_panel = HostAdminPanel.new()
	_host_admin_panel.visible = false
	_host_admin_panel.back_pressed.connect(_close_host_admin)
	_root_panel.add_child(_host_admin_panel)


var _quit_confirm_wrapper: PanelContainer


func _build_quit_confirm() -> void:
	# Framed confirm dialog — a smaller cousin of the pause list, styled the same.
	_quit_confirm_wrapper = PanelContainer.new()
	_quit_confirm_wrapper.add_theme_stylebox_override("panel", UITheme.panel_style())
	_quit_confirm_wrapper.set_anchors_preset(Control.PRESET_CENTER, true)
	_quit_confirm_wrapper.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_quit_confirm_wrapper.grow_vertical = Control.GROW_DIRECTION_BOTH
	_quit_confirm_wrapper.visible = false
	_quit_confirm_wrapper.process_mode = Node.PROCESS_MODE_ALWAYS
	_root_panel.add_child(_quit_confirm_wrapper)

	_quit_confirm = VBoxContainer.new()
	_quit_confirm.add_theme_constant_override("separation", 10)
	_quit_confirm.custom_minimum_size = Vector2(340, 0)
	_quit_confirm.process_mode = Node.PROCESS_MODE_ALWAYS
	_quit_confirm_wrapper.add_child(_quit_confirm)

	var head := Label.new()
	head.text = "QUIT GAME?"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_head(head, 30)
	head.add_theme_color_override("font_color", UITheme.COL_ALERT)
	_quit_confirm.add_child(head)

	_quit_confirm.add_child(UITheme.make_rule())

	_quit_confirm.add_child(UITheme.spacer(4))

	var yes := _make_button("QUIT")
	yes.pressed.connect(func() -> void: get_tree().quit())
	_quit_confirm.add_child(yes)

	var no := _make_button("CANCEL", true)
	no.pressed.connect(_close_quit_confirm)
	_quit_confirm.add_child(no)
	_quit_cancel_btn = no


func _make_button(text: String, primary: bool = false) -> Button:
	var b := UITheme.make_button(text, primary, 300, 44)
	b.process_mode = Node.PROCESS_MODE_ALWAYS
	return b


func _pad(px: int) -> Control:
	return UITheme.spacer(px)


func _input(event: InputEvent) -> void:
	# ESC (keyboard) or Start (gamepad) — both bind to the `pause` action (#115).
	# Falls back to a bare KEY_ESCAPE check (UIBack.is_back_event: keycode or
	# scancode, or ui_cancel) so a user who somehow unbound `pause` in the
	# Controls menu still has a way to open the pause overlay; keycode too:
	# remote-play / streaming / automation tools often send virtual keys
	# without a scancode, which the physical binding misses.
	var is_back := UIBack.is_back_event(event)
	var is_pause := InputMap.has_action("pause") and event.is_action_pressed("pause")
	if not is_back and not is_pause:
		return
	# Don't hijack while the HUD's chat / command LineEdit is focused —
	# the LineEdit uses ESC to close itself.
	if not _open:
		var focused := get_viewport().gui_get_focus_owner()
		if focused != null and focused is LineEdit:
			return
	get_viewport().set_input_as_handled()
	# Esc is BACK (same as the Android button); Start / a rebound pause key
	# toggles the overlay as before.
	if is_back or _open:
		go_back()
	else:
		open()


## BACK / Esc in a match (scripts/ui_back.gd rule), top-most first: an open
## popup list, a pause sub-panel (Controls mid-rebind cancels the capture
## first, so the rebind session isn't lost), the quit confirm, the pause list
## itself (= resume); with the overlay closed: the touch-layout editor, the
## chat / command line, the radio menu, then a Maker play-test goes back to
## EDIT (like the pause menu's exit) and any other match opens the pause menu.
func go_back() -> void:
	if UIBack.dismiss(get_tree()):
		return
	if _open:
		if _controls_panel.visible:
			if _controls_panel._capturing_action != "":
				_controls_panel._abort_capture()
			else:
				_close_controls()
		elif _settings_panel.visible:
			_close_settings()
		elif _host_admin_panel.visible:
			_close_host_admin()
		elif _quit_confirm_wrapper.visible:
			_close_quit_confirm()
		else:
			close()
		return
	if TouchControls.edit_mode:
		TouchControls.edit_mode = false
		Settings.save()
		return
	var hud = get_parent().get("hud") if get_parent() != null else null
	if hud != null and is_instance_valid(hud):
		var cl = hud.get("command_line")
		if cl != null and bool(cl.get("is_open")):
			cl.call("close_command")
			return
		var rm = hud.get("radio_menu")
		if rm != null and is_instance_valid(rm) and (rm as CanvasItem).visible:
			rm.call("close")
			return
	if not Net.maker_return.is_empty() and get_parent() != null and get_parent().has_method("maker_edit"):
		_exit_to_menu()
		return
	open()


var _info_lbl: Label
var _copy_code_btn: Button = null


func open() -> void:
	if _open:
		return
	_open = true
	_menu_wrapper.visible = true
	_settings_panel.visible = false
	_controls_panel.visible = false
	_host_admin_panel.visible = false
	_quit_confirm_wrapper.visible = false
	_root_panel.visible = true
	if _info_lbl != null:
		var main := get_parent()
		var mp: Dictionary = main.get("_map") if main != null and main.get("_map") != null else {}
		var gm: int = Settings.game_mode
		var mode_name: String = str(Net.MODE_NAMES[gm]) if gm >= 0 and gm < Net.MODE_NAMES.size() else "?"
		var txt := "%s · %s" % [str(mp.get("name", "?")), mode_name]
		txt += "\n" + preload("res://scripts/game_info.gd").mode_goal(gm)
		txt += "\n" + preload("res://scripts/game_info.gd").TITLE + " v%s" % str(ProjectSettings.get_setting("application/config/version", "?"))
		if Net.is_networked():
			txt += "\n" + Net.status
			if Net.is_host():
				txt += "  ·  %d player(s) connected" % multiplayer.get_peers().size()
		_info_lbl.text = txt
	# Host admin button only makes sense on host or SP. Clients get nothing.
	if _host_admin_btn != null:
		_host_admin_btn.visible = not Net.is_client()
	if _copy_code_btn != null:
		_copy_code_btn.visible = Net.is_host() and Net.share_text() != ""
	# Free the OS cursor so mouse buttons work reliably on the pause menu.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_set_frozen(true)
	# #93: focus resume so arrow-key nav works before a mouse click.
	UITheme.safe_grab_focus_deferred(_resume_btn)


func close() -> void:
	if not _open:
		return
	_open = false
	_root_panel.visible = false
	_set_frozen(false)


# Single-player freezes the whole tree. In multiplayer the match keeps running
# for everyone else (pausing the host's tree used to freeze every client; a
# paused client stopped applying snapshots), so only our own input is locked.
func _set_frozen(on: bool) -> void:
	if Net.is_networked():
		var m := get_parent()
		var p: Variant = m.get("player") if m != null else null
		if p != null and is_instance_valid(p):
			(p as Node).set("input_locked", on)
		get_tree().paused = false
	else:
		get_tree().paused = on


# Android back button / gesture = Esc (go_back) instead of quitting the app
# (quit_on_go_back is off in project.godot).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if is_inside_tree():
			# Deferred: the notification walks the tree; EDIT changes scenes.
			go_back.call_deferred()
	# Alt-tab / phone home button / incoming call: open the pause menu so a
	# single-player match doesn't keep running (and you don't come back dead).
	# In multiplayer it only stops your own input, same as pressing Esc.
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if not _open and not Net.is_dedicated and DisplayServer.get_name() != "headless" \
				and Settings.pause_on_focus_loss:
			open()


func _open_settings() -> void:
	_menu_wrapper.visible = false
	_settings_panel.visible = true


func _close_settings() -> void:
	_settings_panel.visible = false
	_menu_wrapper.visible = true
	UITheme.safe_grab_focus_deferred(_resume_btn)


func _open_host_admin() -> void:
	_menu_wrapper.visible = false
	_host_admin_panel.visible = true


func _close_host_admin() -> void:
	_host_admin_panel.visible = false
	_menu_wrapper.visible = true
	UITheme.safe_grab_focus_deferred(_resume_btn)


func _open_controls() -> void:
	_settings_panel.visible = false
	_controls_panel.visible = true


func _close_controls() -> void:
	_controls_panel.visible = false
	_settings_panel.visible = true


func _open_quit_confirm() -> void:
	_menu_wrapper.visible = false
	_quit_confirm_wrapper.visible = true
	UITheme.safe_grab_focus_deferred(_quit_cancel_btn)


func _close_quit_confirm() -> void:
	_quit_confirm_wrapper.visible = false
	_menu_wrapper.visible = true
	UITheme.safe_grab_focus_deferred(_resume_btn)


func _exit_to_menu() -> void:
	# Unpause first so the next scene doesn't inherit a paused tree, and drop any
	# active network peer since the main menu is single-scene / lobby.
	get_tree().paused = false
	# Maker PLAY session (#286): Quit goes back to the editor, not the menu.
	var m := get_tree().current_scene
	if not Net.maker_return.is_empty() and m != null and m.has_method("maker_edit"):
		m.maker_edit()
		return
	Net.leave()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


