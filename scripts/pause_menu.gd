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
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_panel.add_child(_dim)

	_build_main_menu()
	_build_settings_panel()
	_build_controls_panel()
	_build_host_admin_panel()
	_build_quit_confirm()


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

	var title := UITheme.make_screen_title("PAUSED", 44)
	_menu_box.add_child(title)

	var rule := ColorRect.new()
	rule.color = UITheme.COL_ACCENT_DIM
	rule.custom_minimum_size = Vector2(0, 1)
	_menu_box.add_child(rule)

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
	head.add_theme_font_size_override("font_size", 26)
	head.add_theme_color_override("font_color", UITheme.COL_ALERT)
	head.add_theme_color_override("font_outline_color", UITheme.COL_SHADOW)
	head.add_theme_constant_override("outline_size", 6)
	_quit_confirm.add_child(head)

	var rule := ColorRect.new()
	rule.color = UITheme.COL_ACCENT_DIM
	rule.custom_minimum_size = Vector2(0, 1)
	_quit_confirm.add_child(rule)

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
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			# Don't hijack ESC while the HUD's chat / command LineEdit is focused —
			# the LineEdit uses ESC to close itself.
			if not _open:
				var focused := get_viewport().gui_get_focus_owner()
				if focused != null and focused is LineEdit:
					return
			if _open:
				# ESC in a sub-panel steps back to the main pause list.
				# Controls capture handles its own ESC (to cancel a rebind) —
				# only back out once nothing is being captured, otherwise the
				# user would lose their rebind session on the first ESC.
				if _controls_panel.visible:
					if _controls_panel._capturing_action != "":
						_controls_panel._abort_capture()
					else:
						_close_controls()
					get_viewport().set_input_as_handled()
					return
				if _settings_panel.visible:
					_close_settings()
					get_viewport().set_input_as_handled()
					return
				if _host_admin_panel.visible:
					_close_host_admin()
					get_viewport().set_input_as_handled()
					return
				if _quit_confirm_wrapper.visible:
					_close_quit_confirm()
					get_viewport().set_input_as_handled()
					return
				close()
			else:
				open()
			get_viewport().set_input_as_handled()


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
	# Host admin button only makes sense on host or SP. Clients get nothing.
	if _host_admin_btn != null:
		_host_admin_btn.visible = not Net.is_client()
	# Free the OS cursor so mouse buttons work reliably on the pause menu.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = true
	# #93: focus resume so arrow-key nav works before a mouse click.
	UITheme.safe_grab_focus_deferred(_resume_btn)


func close() -> void:
	if not _open:
		return
	_open = false
	_root_panel.visible = false
	get_tree().paused = false


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
	Net.leave()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


