extends CanvasLayer
## HUD — health, fuel, ammo, weapon, grenades, kill feed, scoreboard, round timer, winner banner.

var player: Node2D
var map_name := ""
var lbl_health: Label
var lbl_fuel: Label
var lbl_ammo: Label
var lbl_weapon: Label
var lbl_grenades: Label
var lbl_map: Label
var lbl_rec: Label
var lbl_status: Label
var lbl_timer: Label
var lbl_score: RichTextLabel
var lbl_winner: Label
var lbl_winner_note: Label
var feed: VBoxContainer

# Death screen state
var desat_overlay: ColorRect
var lbl_death: Label
var lbl_respawn: Label
var _death_remaining := 0.0
var _dead := false

# /command line for gestures (opened by player.gd when the "/" key is pressed).
# Reused for T (global chat) and Y (team chat) — _line_mode tracks which.
var command_line: LineEdit
var _command_visible := false
var _line_mode := "cmd"  # "cmd" | "global" | "team"
var chat_feed: VBoxContainer
var weapon_menu: Control  # left-side Soldat weapon selection panel (#70)
var lbl_fps: Label        # top-right FPS overlay — visible only when Settings.show_fps (#73)
var lbl_spectate: Label   # "Spectating: <name>" label while dead (#75)
var lbl_spectate_hint: Label  # controls hint under the spectate label
# (#76) Kill-streak / multi-kill announcement banner. Overwrites-on-escalation:
# a Double Kill followed by a Rampage swaps the same label instead of stacking.
var lbl_streak: Label
var _streak_tween: Tween = null
const STREAK_HOLD := 2.0
# (#77) Vote prompt — centered upper-third panel with title, tally, timer.
var vote_panel: PanelContainer
var lbl_vote_title: Label
var lbl_vote_tally: Label
var lbl_vote_timer: Label
# (#78) Active bonus indicator — bottom-center label showing kind + countdown.
var lbl_bonus: Label
const BonusPickup = preload("res://scripts/bonus_pickup.gd")
static var _taunts: Dictionary = {}
const CHAT_FEED_MAX := 7
const CHAT_TTL := 10.0
const WeaponMenu = preload("res://scripts/weapon_menu.gd")

const FEED_MAX := 5
const FEED_TTL := 4.0

var _feed_entries: Array = []


func _ready() -> void:
	# Full-screen death desaturation overlay (behind all HUD text).
	desat_overlay = ColorRect.new()
	desat_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	desat_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var _sm := ShaderMaterial.new()
	_sm.shader = preload("res://scripts/death_desat.gdshader")
	desat_overlay.material = _sm
	desat_overlay.visible = false
	add_child(desat_overlay)

	lbl_health = _make_label(Vector2(14, 10), Color(1.0, 0.35, 0.35))
	lbl_fuel = _make_label(Vector2(14, 34), Color(0.4, 0.8, 1.0))
	lbl_ammo = _make_label(Vector2(14, 58), Color(1, 1, 1))
	lbl_weapon = _make_label(Vector2(14, 82), Color(0.9, 0.85, 0.6))
	lbl_grenades = _make_label(Vector2(14, 106), Color(0.6, 1.0, 0.6))
	feed = VBoxContainer.new()
	feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	feed.position = Vector2(-320, 10)
	feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	feed.alignment = BoxContainer.ALIGNMENT_END
	feed.add_theme_constant_override("separation", 3)
	add_child(feed)
	lbl_map = Label.new()
	lbl_map.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_map.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl_map.offset_top = 8
	lbl_map.offset_bottom = 30
	lbl_map.add_theme_font_size_override("font_size", 16)
	lbl_map.add_theme_color_override("font_color", Color(0.75, 0.78, 0.88))
	lbl_map.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	lbl_map.add_theme_constant_override("outline_size", 3)
	add_child(lbl_map)
	lbl_status = Label.new()
	lbl_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_status.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl_status.offset_top = 30
	lbl_status.offset_bottom = 52
	lbl_status.add_theme_font_size_override("font_size", 13)
	lbl_status.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	lbl_status.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	lbl_status.add_theme_constant_override("outline_size", 3)
	add_child(lbl_status)

	lbl_timer = Label.new()
	lbl_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_timer.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl_timer.offset_top = 52
	lbl_timer.offset_bottom = 82
	lbl_timer.add_theme_font_size_override("font_size", 22)
	lbl_timer.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	lbl_timer.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl_timer.add_theme_constant_override("outline_size", 4)
	add_child(lbl_timer)

	lbl_score = RichTextLabel.new()
	lbl_score.bbcode_enabled = true
	lbl_score.fit_content = true
	lbl_score.scroll_active = false
	lbl_score.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl_score.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl_score.offset_top = 82
	lbl_score.offset_bottom = 112
	lbl_score.add_theme_font_size_override("normal_font_size", 18)
	lbl_score.add_theme_font_size_override("bold_font_size", 18)
	add_child(lbl_score)

	lbl_winner = Label.new()
	lbl_winner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_winner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_winner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl_winner.add_theme_font_size_override("font_size", 64)
	lbl_winner.add_theme_color_override("font_color", Color(1.0, 0.92, 0.5))
	lbl_winner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl_winner.add_theme_constant_override("outline_size", 12)
	lbl_winner.visible = false
	add_child(lbl_winner)

	# Sub-line under the winner banner — explains why a draw happened (#37).
	lbl_winner_note = Label.new()
	lbl_winner_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_winner_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_winner_note.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl_winner_note.offset_top = 60
	lbl_winner_note.add_theme_font_size_override("font_size", 22)
	lbl_winner_note.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	lbl_winner_note.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl_winner_note.add_theme_constant_override("outline_size", 6)
	lbl_winner_note.visible = false
	add_child(lbl_winner_note)

	# Death message + respawn countdown.
	lbl_death = Label.new()
	lbl_death.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_death.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_death.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl_death.offset_top = -100
	lbl_death.offset_bottom = -100
	lbl_death.add_theme_font_size_override("font_size", 44)
	lbl_death.add_theme_color_override("font_color", Color(0.95, 0.25, 0.2))
	lbl_death.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl_death.add_theme_constant_override("outline_size", 9)
	lbl_death.visible = false
	add_child(lbl_death)

	lbl_respawn = Label.new()
	lbl_respawn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_respawn.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_respawn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl_respawn.offset_top = -40
	lbl_respawn.offset_bottom = -40
	lbl_respawn.add_theme_font_size_override("font_size", 26)
	lbl_respawn.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	lbl_respawn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl_respawn.add_theme_constant_override("outline_size", 6)
	lbl_respawn.visible = false
	add_child(lbl_respawn)

	# GIF-recording indicator — visible only while the recorder is running.
	lbl_rec = Label.new()
	lbl_rec.set_anchors_preset(Control.PRESET_TOP_LEFT)
	lbl_rec.position = Vector2(14, 132)
	lbl_rec.add_theme_font_size_override("font_size", 16)
	lbl_rec.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	lbl_rec.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl_rec.add_theme_constant_override("outline_size", 3)
	lbl_rec.visible = false
	add_child(lbl_rec)

	# /command line — hidden until the local player presses "/".
	command_line = LineEdit.new()
	command_line.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	command_line.offset_left = 12
	command_line.offset_right = -12
	command_line.offset_top = -110
	command_line.offset_bottom = -80
	command_line.placeholder_text = "/votemap N   /votekick name   /victory  /smoke  /tabac  /takeoff  /mercy  /kill  /brutalkill"
	command_line.custom_minimum_size = Vector2(0, 28)
	command_line.visible = false
	command_line.text_submitted.connect(_on_command_submitted)
	command_line.gui_input.connect(_on_command_gui_input)
	add_child(command_line)

	# Chat feed — recent messages scroll bottom-up above the ammo readout.
	chat_feed = VBoxContainer.new()
	chat_feed.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat_feed.offset_left = 14
	chat_feed.offset_top = -260
	chat_feed.offset_bottom = -140
	chat_feed.grow_vertical = Control.GROW_DIRECTION_BEGIN
	chat_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(chat_feed)

	# Weapon selection panel (#70) — death-triggered limbo menu: shows while the
	# player is dead, hides once they pick a weapon. See weapon_menu.gd _process.
	weapon_menu = WeaponMenu.new()
	add_child(weapon_menu)
	weapon_menu.player = player

	# FPS overlay (#73) — top-right corner. Hidden by default; toggle via Settings.
	lbl_fps = Label.new()
	lbl_fps.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	lbl_fps.offset_right = -14
	lbl_fps.offset_left = -140
	lbl_fps.offset_top = -2
	lbl_fps.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_fps.add_theme_font_size_override("font_size", 14)
	lbl_fps.add_theme_color_override("font_color", Color(0.65, 1.0, 0.65))
	lbl_fps.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl_fps.add_theme_constant_override("outline_size", 3)
	lbl_fps.visible = false
	add_child(lbl_fps)

	# Spectator label (#75) — top-center, above the death text so it reads while
	# the desat overlay is up. Team-colored per current target.
	lbl_spectate = Label.new()
	lbl_spectate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_spectate.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_spectate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl_spectate.offset_top = -180
	lbl_spectate.offset_bottom = -180
	lbl_spectate.add_theme_font_size_override("font_size", 26)
	lbl_spectate.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl_spectate.add_theme_constant_override("outline_size", 6)
	lbl_spectate.visible = false
	add_child(lbl_spectate)

	lbl_spectate_hint = Label.new()
	lbl_spectate_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_spectate_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_spectate_hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl_spectate_hint.offset_top = -150
	lbl_spectate_hint.offset_bottom = -150
	lbl_spectate_hint.text = "← / →  next target    ·    C  toggle free-cam"
	lbl_spectate_hint.add_theme_font_size_override("font_size", 14)
	lbl_spectate_hint.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	lbl_spectate_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl_spectate_hint.add_theme_constant_override("outline_size", 3)
	lbl_spectate_hint.visible = false
	add_child(lbl_spectate_hint)

	# Streak / multi-kill banner (#76) — big center-screen text, fades over ~2s.
	# Positioned above the map/timer strip so it reads over gameplay without
	# fighting the top bar for space. Font color set per-call to the killer's team.
	lbl_streak = Label.new()
	lbl_streak.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_streak.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_streak.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl_streak.offset_top = -260
	lbl_streak.offset_bottom = -260
	lbl_streak.add_theme_font_size_override("font_size", 42)
	lbl_streak.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl_streak.add_theme_constant_override("outline_size", 8)
	lbl_streak.modulate = Color(1, 1, 1, 0)
	lbl_streak.visible = false
	add_child(lbl_streak)

	# Vote prompt (#77) — centered near the top-third of the screen so it doesn't
	# eat the crosshair. Semi-opaque background so the tally reads over any map.
	vote_panel = PanelContainer.new()
	vote_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	vote_panel.offset_top = 140
	vote_panel.offset_bottom = 240
	vote_panel.offset_left = -260
	vote_panel.offset_right = 260
	vote_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vote_bg := StyleBoxFlat.new()
	vote_bg.bg_color = Color(0.05, 0.05, 0.09, 0.85)
	vote_bg.border_color = Color(0.95, 0.82, 0.4, 0.9)
	vote_bg.border_width_left = 2
	vote_bg.border_width_right = 2
	vote_bg.border_width_top = 2
	vote_bg.border_width_bottom = 2
	vote_bg.corner_radius_top_left = 6
	vote_bg.corner_radius_top_right = 6
	vote_bg.corner_radius_bottom_left = 6
	vote_bg.corner_radius_bottom_right = 6
	vote_bg.content_margin_left = 14
	vote_bg.content_margin_right = 14
	vote_bg.content_margin_top = 8
	vote_bg.content_margin_bottom = 8
	vote_panel.add_theme_stylebox_override("panel", vote_bg)
	vote_panel.visible = false
	add_child(vote_panel)
	var vote_col := VBoxContainer.new()
	vote_col.add_theme_constant_override("separation", 4)
	vote_panel.add_child(vote_col)
	lbl_vote_title = Label.new()
	lbl_vote_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_vote_title.add_theme_font_size_override("font_size", 18)
	lbl_vote_title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	lbl_vote_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl_vote_title.add_theme_constant_override("outline_size", 3)
	vote_col.add_child(lbl_vote_title)
	lbl_vote_tally = Label.new()
	lbl_vote_tally.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_vote_tally.add_theme_font_size_override("font_size", 16)
	lbl_vote_tally.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	lbl_vote_tally.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl_vote_tally.add_theme_constant_override("outline_size", 3)
	vote_col.add_child(lbl_vote_tally)
	lbl_vote_timer = Label.new()
	lbl_vote_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_vote_timer.add_theme_font_size_override("font_size", 13)
	lbl_vote_timer.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9))
	vote_col.add_child(lbl_vote_timer)

	# Bonus effect indicator (#78) — bottom-center over the ammo/weapon strip,
	# but shifted up enough that it doesn't overlap the standard HUD readouts.
	lbl_bonus = Label.new()
	lbl_bonus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_bonus.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	lbl_bonus.offset_top = -60
	lbl_bonus.offset_bottom = -30
	lbl_bonus.add_theme_font_size_override("font_size", 22)
	lbl_bonus.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl_bonus.add_theme_constant_override("outline_size", 6)
	lbl_bonus.visible = false
	add_child(lbl_bonus)


func show_streak_banner(killer_name: String, title: String, killer_team: int, count: int) -> void:
	# Overwrites any in-progress banner — a rapid escalation from Double → Multi
	# should read as one crescendo, not two overlapping labels.
	if lbl_streak == null:
		return
	var info := _team_display_info(killer_team)
	var col: Color = info.get("color", Color(1.0, 0.85, 0.35))
	lbl_streak.text = "%s\n%s  ×%d" % [title.to_upper(), killer_name, count]
	lbl_streak.add_theme_color_override("font_color", col)
	lbl_streak.visible = true
	lbl_streak.modulate = Color(col.r, col.g, col.b, 1.0)
	if _streak_tween != null and _streak_tween.is_valid():
		_streak_tween.kill()
	_streak_tween = create_tween()
	_streak_tween.tween_interval(STREAK_HOLD)
	_streak_tween.tween_property(lbl_streak, "modulate:a", 0.0, 0.6)
	_streak_tween.tween_callback(func() -> void:
		if is_instance_valid(lbl_streak):
			lbl_streak.visible = false)
	# Local sound cue — reuse the explosion sample so it thumps like Soldat's
	# original bass-drum announcer without adding an sfx table entry.
	Sfx._play_event("explode", -4.0, 0.85)


func post_streak_ended(ender_name: String, victim_name: String, streak_len: int, ender_team: int) -> void:
	# Reuses the kill-feed lane so streak enders read alongside the frag they came
	# from, at the same fade-out cadence and team color as everything else.
	if not is_instance_valid(feed):
		return
	var info := _team_display_info(ender_team)
	var col: Color = info.get("color", Color(1.0, 0.85, 0.35))
	var lbl := Label.new()
	lbl.text = "%s ended %s's %d-kill streak" % [ender_name, victim_name, streak_len]
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 3)
	feed.add_child(lbl)
	feed.move_child(lbl, 0)
	_feed_entries.push_front(lbl)
	while _feed_entries.size() > FEED_MAX:
		var old: Label = _feed_entries.pop_back()
		if is_instance_valid(old):
			old.queue_free()
	var t := Timer.new()
	t.wait_time = FEED_TTL
	t.one_shot = true
	t.autostart = true
	lbl.add_child(t)
	t.timeout.connect(func() -> void:
		_feed_entries.erase(lbl)
		if is_instance_valid(lbl):
			lbl.queue_free())


func set_spectate_target(name: String, col: Color) -> void:
	# Called by Spectator whenever the follow target or free-cam mode changes.
	# Empty name hides the label — happens when spectator deactivates on respawn.
	if lbl_spectate == null:
		return
	if name == "":
		lbl_spectate.visible = false
		lbl_spectate_hint.visible = false
		return
	lbl_spectate.text = "Spectating: %s" % name
	lbl_spectate.add_theme_color_override("font_color", col)
	lbl_spectate.visible = true
	lbl_spectate_hint.visible = true


func open_command(prefill: String = "/") -> void:
	_open_line("cmd", prefill, "/votemap N   /votekick name   /victory  /smoke  /mercy  /kill")


func open_chat(scope: String) -> void:
	if scope == "team":
		_open_line("team", "", "[TEAM] Y — say to your team")
	else:
		_open_line("global", "", "[GLOBAL] T — say to everyone")


func _open_line(mode: String, prefill: String, placeholder: String) -> void:
	if not is_instance_valid(player) or bool(player.get("dead")):
		return
	if _command_visible:
		return
	_command_visible = true
	_line_mode = mode
	command_line.text = prefill
	command_line.placeholder_text = placeholder
	command_line.visible = true
	command_line.grab_focus()
	command_line.caret_column = command_line.text.length()
	player.set("input_locked", true)


func _close_command() -> void:
	_command_visible = false
	command_line.visible = false
	command_line.text = ""
	command_line.release_focus()
	if is_instance_valid(player):
		player.set("input_locked", false)


func _on_command_submitted(text: String) -> void:
	var t := text.strip_edges()
	if is_instance_valid(player) and t != "":
		if _line_mode == "cmd" and t.begins_with("/") and _try_vote_command(t):
			_close_command()
			return
		if _line_mode == "cmd":
			if t.begins_with("/") and player.has_method("apply_gesture"):
				player.apply_gesture(t)
			elif player.has_method("send_chat"):
				player.send_chat("global", t)
		elif _line_mode == "team" and player.has_method("send_chat"):
			player.send_chat("team", t)
		elif player.has_method("send_chat"):
			player.send_chat("global", t)
	_close_command()


# Vote chat commands (#77): /votemap <n|name>, /votekick <peer|name>,
# /votecancel (host only). Returns true if the text was a vote command so the
# caller skips the gesture / chat path.
func _try_vote_command(raw: String) -> bool:
	var lower := raw.to_lower()
	var main := get_parent()
	if main == null:
		return false
	if lower == "/votemap" or lower.begins_with("/votemap "):
		var arg := raw.substr("/votemap".length()).strip_edges()
		if arg == "":
			post_chat("VOTE", "Usage: /votemap <index-or-name>", false)
			return true
		if main.has_method("request_vote"):
			main.request_vote("votemap", arg)
		return true
	if lower == "/votekick" or lower.begins_with("/votekick "):
		var arg := raw.substr("/votekick".length()).strip_edges()
		if arg == "":
			post_chat("VOTE", "Usage: /votekick <peer-id-or-name>", false)
			return true
		if main.has_method("request_vote"):
			main.request_vote("votekick", arg)
		return true
	if lower == "/votecancel":
		if main.has_method("cancel_vote"):
			main.cancel_vote()
		return true
	return false


func _update_vote_ui() -> void:
	if vote_panel == null:
		return
	var main := get_parent()
	if main == null or main.get("vote_active") == null:
		vote_panel.visible = false
		return
	var active: bool = bool(main.get("vote_active"))
	if not active:
		vote_panel.visible = false
		return
	var kind: String = str(main.get("vote_kind"))
	var target: String = str(main.get("vote_target_str"))
	var yes_ct: int = int(main.get("vote_yes"))
	var no_ct: int = int(main.get("vote_no"))
	var tl: float = float(main.get("vote_time_left"))
	var starter: String = str(main.get("vote_starter"))
	var verb: String = "change map to" if kind == "votemap" else "kick"
	lbl_vote_title.text = "Vote (%s): %s %s?" % [starter, verb, target]
	lbl_vote_tally.text = "[F1] Yes %d    ·    [F2] No %d" % [yes_ct, no_ct]
	lbl_vote_timer.text = "%ds" % int(ceil(tl))
	vote_panel.visible = true


func _update_bonus_ui() -> void:
	if lbl_bonus == null:
		return
	if not is_instance_valid(player) or player.get("bonus_kind") == null:
		lbl_bonus.visible = false
		return
	var kind: String = str(player.get("bonus_kind"))
	if kind == "":
		lbl_bonus.visible = false
		return
	var t: float = float(player.get("bonus_t"))
	lbl_bonus.text = "%s  %ds" % [BonusPickup.kind_label(kind), int(ceil(t))]
	lbl_bonus.add_theme_color_override("font_color", BonusPickup.kind_color(kind))
	lbl_bonus.visible = true


func post_chat(author: String, msg: String, is_team: bool) -> void:
	if not is_instance_valid(chat_feed):
		return
	var lbl := Label.new()
	lbl.text = ("(TEAM) %s: %s" % [author, msg]) if is_team else ("%s: %s" % [author, msg])
	var col := Color(0.6, 0.95, 1.0) if is_team else Color(0.95, 0.95, 0.95)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 3)
	chat_feed.add_child(lbl)
	while chat_feed.get_child_count() > CHAT_FEED_MAX:
		var old := chat_feed.get_child(0)
		chat_feed.remove_child(old)
		old.queue_free()
	var t := Timer.new()
	t.wait_time = CHAT_TTL
	t.one_shot = true
	t.autostart = true
	lbl.add_child(t)
	t.timeout.connect(func() -> void:
		if is_instance_valid(lbl):
			lbl.queue_free())


func get_taunt(key: String) -> String:
	_load_taunts()
	return String(_taunts.get(key.to_lower(), ""))


func _load_taunts() -> void:
	if not _taunts.is_empty():
		return
	var path := "res://taunts.txt"
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			while not f.eof_reached():
				var line := f.get_line().strip_edges()
				if line == "" or line.begins_with("#"):
					continue
				var sp := line.find(" ")
				if sp > 0:
					var key := line.substr(0, sp).to_lower()
					var msg := line.substr(sp + 1)
					_taunts[key] = msg
	if _taunts.is_empty():
		var defaults := {
			"a": "Attack!", "b": "Get back!", "c": "Cover me!",
			"d": "Defend the flag!", "e": "Enemy spotted!", "f": "Grab the flag!",
			"g": "Good shot!", "h": "Hello!", "i": "Need ammo!",
			"j": "Jump!", "k": "Nice kill!", "l": "Let's move!",
			"m": "Medic!", "n": "No!", "o": "Okay!", "p": "Push up!",
			"q": "Quiet!", "r": "Ready!", "s": "Sorry!", "t": "Thanks!",
			"u": "Understood!", "v": "Victory!", "w": "Watch out!",
			"x": "GG!", "y": "Yes!", "z": "Regroup!",
			"0": "Move out!", "1": "One!", "2": "Two!",
			"3": "Three!", "4": "Four!", "5": "Five!",
			"6": "Six!", "7": "Seven!", "8": "Eight!", "9": "Nine!",
		}
		for k in defaults:
			_taunts[k] = defaults[k]


func _on_command_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_close_command()


func _make_label(pos: Vector2, col: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	add_child(l)
	return l


func show_death(killer: String, weapon: String, respawn_secs: float = 2.0) -> void:
	_dead = true
	# Countdown matches the real respawn delay so the label doesn't tick to 0
	# while the player is still on the floor (INF attackers pay 5s, not 2s).
	# Pass a negative value to display the "no respawn" survival hint instead.
	_death_remaining = respawn_secs
	lbl_death.text = ("You were killed by %s" % killer) if killer != "" else "You died"
	if weapon != "" and killer != "":
		lbl_death.text += "  [%s]" % weapon
	lbl_death.visible = true
	lbl_respawn.visible = true
	desat_overlay.visible = true


func _hide_death() -> void:
	_dead = false
	lbl_death.visible = false
	lbl_respawn.visible = false
	desat_overlay.visible = false


func _on_kill(killer_name: String, victim_name: String, weapon_name: String, killer_team: int, _victim_team: int) -> void:
	# Reuse the scoreboard's team palette so BLUE/RED kills read as their team
	# color instead of everyone-not-us collapsing to red.
	var info := _team_display_info(killer_team)
	var kcol: Color = info.get("color", Color(1.0, 0.45, 0.45))
	var lbl := Label.new()
	lbl.text = "%s  [%s]  %s" % [killer_name, weapon_name, victim_name]
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", kcol)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 3)
	feed.add_child(lbl)
	feed.move_child(lbl, 0)
	_feed_entries.push_front(lbl)
	while _feed_entries.size() > FEED_MAX:
		var old: Label = _feed_entries.pop_back()
		if is_instance_valid(old):
			old.queue_free()
	# Timer parented to the label so it dies with the label instead of orphan-firing 4s later.
	var t := Timer.new()
	t.wait_time = FEED_TTL
	t.one_shot = true
	t.autostart = true
	lbl.add_child(t)
	t.timeout.connect(func() -> void:
		_feed_entries.erase(lbl)
		if is_instance_valid(lbl):
			lbl.queue_free())


func _input(event: InputEvent) -> void:
	# Record-GIF hotkey (default F9, rebindable via controls_map). Kept on the HUD
	# rather than the player so it still works from the death screen and menus.
	if event.is_action_pressed("record_gif"):
		GifRecorder.toggle()
	# Vote hotkeys (#77) — F1/F2 rebindable. Only meaningful while a vote is
	# active. Ignored while the command line is open so a "yes" typed as text
	# doesn't accidentally cast when the user hits F1.
	if _command_visible:
		return
	var main := get_parent()
	if main == null or not bool(main.get("vote_active")):
		return
	if event.is_action_pressed("vote_yes") and main.has_method("cast_vote"):
		main.cast_vote(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("vote_no") and main.has_method("cast_vote"):
		main.cast_vote(false)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	# GIF indicator — mirrors the recorder's live state.
	if lbl_rec != null:
		if GifRecorder.is_recording():
			lbl_rec.text = "● REC (F9 stop)"
			lbl_rec.visible = true
		else:
			lbl_rec.visible = false
	# FPS overlay — cheap ~5x/sec refresh (Engine.get_frames_per_second is a
	# rolling avg, so per-frame updates would jitter without changing the value).
	if lbl_fps != null:
		lbl_fps.visible = Settings.show_fps
		if Settings.show_fps:
			lbl_fps.text = "%d FPS" % int(round(Engine.get_frames_per_second()))
	_update_vote_ui()
	_update_bonus_ui()
	if _dead:
		if _death_remaining < 0.0:
			# Survival: no respawn until the round resets. The desaturated overlay
			# stays up until show_death is called again (or _hide_death fires).
			lbl_respawn.text = "Waiting for next round..."
		else:
			_death_remaining -= delta
			lbl_respawn.text = "Respawning in %d" % maxi(0, int(ceil(_death_remaining)))
			if _death_remaining <= 0.0:
				_hide_death()
	# Prefix the mode so users know which rules are live.
	var mode_str: String = ""
	match Settings.game_mode:
		Settings.MODE_TDM: mode_str = "TDM · "
		Settings.MODE_CTF: mode_str = "CTF · "
		Settings.MODE_INF: mode_str = "INF · "
		Settings.MODE_HTF: mode_str = "HTF · "
		Settings.MODE_RM:  mode_str = "RM · "
		Settings.MODE_PM:  mode_str = "PM · "
		Settings.MODE_DOM: mode_str = "DOM · "
		Settings.MODE_BR:  mode_str = "BR · "
		Settings.MODE_GG:  mode_str = "GG · "
	# Sub-modes append to the tag so players notice.
	var tags: PackedStringArray = PackedStringArray()
	if Settings.realistic:
		tags.append("REAL")
	if Settings.survival:
		tags.append("SURV")
	if Settings.advance:
		tags.append("ADV")
	if tags.size() > 0:
		mode_str = mode_str + "[" + "/".join(tags) + "] "
	# Battle Royale: pin the zone radius to the mode string so shrink pace is legible.
	if Settings.game_mode == Settings.MODE_BR:
		var main2 := get_parent()
		if main2 != null and main2.has_method("br_zone"):
			var z: Dictionary = main2.br_zone()
			mode_str = "BR · zone %dm · " % int(z.get("radius", 0.0) / 10.0)
	lbl_map.text = mode_str + map_name
	lbl_status.text = Net.status if Net.is_networked() else ""
	_update_match_ui()
	if not is_instance_valid(player):
		return
	# Defensive: bail if weapon_index or the array shape drifted mid-frame.
	var wi: int = int(player.weapon_index)
	if wi < 0 or wi >= player.weapons.size() or wi >= player.ammo.size():
		return
	lbl_health.text = "HP  %d" % int(player.health)
	lbl_fuel.text = "FUEL %d%%" % int(player.fuel)
	# When the secondary slot is active (Q pressed), show its name/ammo instead of the primary's.
	var use_sec: bool = bool(player.get("using_secondary"))
	var w: Dictionary
	var mag: int
	if use_sec:
		var si: int = int(player.secondary_index)
		if si < 0 or si >= player.secondary.size() or si >= player.secondary_ammo.size():
			return
		w = player.secondary[si]
		mag = player.secondary_ammo[si]
	else:
		w = player.weapons[wi]
		mag = player.ammo[wi]
	# Realistic ruleset hides the magazine readout — pilots go by weapon feel.
	lbl_ammo.visible = not Settings.realistic
	lbl_fuel.visible = not Settings.realistic
	lbl_ammo.text = "%d / %d" % [mag, int(w["mag"])] + ("  · RELOADING" if player.reloading else "")
	lbl_weapon.text = str(w["name"])
	# Gun Game: overwrite the weapon label with the ladder rung so players see
	# their race progress at a glance. Knife rung nudges them to close the deal.
	if Settings.game_mode == Settings.MODE_GG:
		var lvl: int = int(player.get("gg_level"))
		var ladder: Array = player.get("GG_LADDER")
		if ladder != null and ladder.size() > 0:
			if lvl > ladder.size() - 1:
				lbl_weapon.text = "Gun Game — Golden Knife · kill to win"
			else:
				var idx: int = clampi(lvl, 0, ladder.size() - 1)
				var wname: String = str((ladder[idx] as Dictionary).get("name", ""))
				var suffix: String = "  · Knife kill to win" if lvl >= ladder.size() - 1 else ""
				lbl_weapon.text = "Gun Game — %s (%d/%d)%s" % [wname, lvl + 1, ladder.size(), suffix]
	var gtype := "CLUSTER" if bool(player.get("use_cluster")) else "FRAG"
	lbl_grenades.text = "GRENADES %d  [%s]" % [player.grenades, gtype]


func _update_match_ui() -> void:
	var main := get_parent()
	if main == null or main.get("scores") == null:
		return
	# Bail if this scene isn't a Main yet (e.g., returning to menu mid-frame).
	if main.get("time_left") == null or main.get("round_active") == null or main.get("winner_team") == null:
		return
	var tl: float = main.time_left
	var active: bool = main.round_active
	var winner: int = main.winner_team
	var scores: Dictionary = main.scores
	# Timer MM:SS
	var s := int(maxf(0.0, tl))
	lbl_timer.text = "%d:%02d" % [s / 60, s % 60]
	# Scoreboard (team_id → "name score" with color), sorted by team_id for stability.
	var entries: Array = []
	# ensure all teams currently on the field appear, even at 0-0
	for soldier in get_tree().get_nodes_in_group("soldier"):
		if not is_instance_valid(soldier):
			continue
		var t: int = int(soldier.team)
		if not scores.has(t):
			entries.append(t)
	for k in scores.keys():
		entries.append(int(k))
	var seen: Dictionary = {}
	var ordered: Array = []
	for e in entries:
		if seen.has(e):
			continue
		seen[e] = true
		ordered.append(e)
	ordered.sort()
	var parts: PackedStringArray = PackedStringArray()
	for team in ordered:
		var info := _team_display_info(team)
		var col: Color = info["color"]
		var col_hex: String = col.to_html(false)
		var pts: int = int(scores.get(team, 0))
		parts.append("[color=#%s][b]%s[/b] %d[/color]" % [col_hex, info["name"], pts])
	lbl_score.text = "[center]" + "   ·   ".join(parts) + "[/center]"
	# Winner banner
	var note: String = str(main.get("winner_note")) if main.get("winner_note") != null else ""
	if not active and winner >= 0:
		var info := _team_display_info(winner)
		lbl_winner.text = "%s WINS" % info["name"]
		lbl_winner.add_theme_color_override("font_color", info["color"])
		lbl_winner.visible = true
	elif not active and winner < 0:
		lbl_winner.text = "DRAW"
		lbl_winner.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		lbl_winner.visible = true
	else:
		lbl_winner.visible = false
	if lbl_winner_note != null:
		lbl_winner_note.text = note
		lbl_winner_note.visible = lbl_winner.visible and note != ""


func _team_display_info(team_id: int) -> Dictionary:
	if not Net.is_networked():
		# INF: fixed defender / attacker labels.
		if Settings.game_mode == Settings.MODE_INF:
			if team_id == 1:
				return {"name": "DEFENDERS", "color": Color(0.4, 0.6, 1.0)}
			if team_id == 2:
				return {"name": "ATTACKERS", "color": Color(0.95, 0.35, 0.3)}
		# Team modes generally: fixed BLUE/RED colors + labels.
		if Settings.game_mode != Settings.MODE_DM and Settings.game_mode != Settings.MODE_RM:
			if team_id == 1:
				return {"name": "BLUE", "color": Color(0.4, 0.6, 1.0)}
			if team_id == 2:
				return {"name": "RED", "color": Color(0.95, 0.35, 0.3)}
		if team_id == 0:
			return {"name": "YOU", "color": Color(0.35, 0.85, 0.5)}
		# Distinguish multiple bot teams by id; the common single-team case still reads as "BOTS".
		var nm := "BOTS" if team_id == 99 else "BOT %d" % team_id
		return {"name": nm, "color": Color(0.9, 0.35, 0.3)}
	# MP: reuse the soldier's own color + display_name for their team.
	for s in get_tree().get_nodes_in_group("soldier"):
		if not is_instance_valid(s):
			continue
		if int(s.team) == team_id:
			return {"name": str(s.display_name).to_upper(), "color": s.color}
	# Fallback for teams whose only soldier already left / died mid-round.
	return {"name": "P%d" % team_id, "color": Color(0.7, 0.7, 0.75)}
