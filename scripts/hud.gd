extends CanvasLayer
## HUD — health, fuel, ammo, weapon, grenades, kill feed, scoreboard, round timer, winner banner.

const UITheme = preload("res://scripts/ui_theme.gd")
# Preload player.gd so we can read its GG_LADDER constant — Object.get() only
# exposes member vars, not script constants, so we go through the script class.
const PlayerScript = preload("res://scripts/player.gd")

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
var scoreboard: Control = null
var lbl_timer: Label
var lbl_score: RichTextLabel
var lbl_winner: Label
var lbl_winner_note: Label
var feed: KillFeed              # kill_feed.gd

# Death screen state
var desat_overlay: ColorRect
var post_fx: ColorRect          # post_fx.gdshader (grade / vignette / bloom / hit flash)
var _hit_fx := 0.0
var _last_hp := -1.0
var lbl_death: Label
var lbl_respawn: Label
var _death_remaining := 0.0
var rewind_on := false     # kill cam rewind playing: keep the middle of the screen clear
var _dead := false

# /command line for gestures (opened by player.gd when the "/" key is pressed).
# Reused for T (global chat) and Y (team chat) — hud_commands.gd.
var command_line: HudCommands   # hud_commands.gd
var chat_feed: ChatFeed         # chat_feed.gd
var _left_strip: Control
var _bars: Control
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
var vote_panel: VotePanel       # vote_panel.gd
# (#78) Active bonus indicator — bottom-center label showing kind + countdown.
var lbl_bonus: Label
const BonusPickup = preload("res://scripts/bonus_pickup.gd")
static var _taunts: Dictionary = {}
const WeaponMenu = preload("res://scripts/weapon_menu.gd")
const KillFeed = preload("res://scripts/kill_feed.gd")
const ChatFeed = preload("res://scripts/chat_feed.gd")
const VotePanel = preload("res://scripts/vote_panel.gd")
const NextMapPanel = preload("res://scripts/next_map_panel.gd")
const HudCommands = preload("res://scripts/hud_commands.gd")
const ObjectiveHud = preload("res://scripts/objective_hud.gd")
var objective_hud: Control = null


var radio_menu: Node = null
const GameInfo = preload("res://scripts/game_info.gd")


func _ready() -> void:
	feed = KillFeed.new()
	feed.warm_icons()
	Stats.achievement_unlocked.connect(_on_achievement)
	_locked_looks = preload("res://scripts/customization.gd").locked_list()
	Stats.level_up.connect(func(lv: int) -> void: _ach_queue.append(["RANK UP", "you reached level %d" % lv]))
	if Net.is_networked():
		Stats.record_event.call_deferred("online")
	# Post-processing pass over the world (gfx.gd quality): first child, so
	# it sits under every HUD element.
	post_fx = ColorRect.new()
	post_fx.name = "PostFX"
	post_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	post_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var _pm := ShaderMaterial.new()
	_pm.shader = preload("res://scripts/post_fx.gdshader")
	post_fx.material = _pm
	add_child(post_fx)
	apply_gfx_quality()
	# Full-screen death desaturation overlay (behind all HUD text).
	desat_overlay = ColorRect.new()
	desat_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	desat_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var _sm := ShaderMaterial.new()
	_sm.shader = preload("res://scripts/death_desat.gdshader")
	desat_overlay.material = _sm
	desat_overlay.visible = false
	add_child(desat_overlay)

	# Left-cluster backing strip — a dark translucent panel behind
	# HP/Fuel/Ammo/Weapon/Grenades so the readouts pop over bright sky/terrain.
	# Placed BEFORE the labels so they render on top.
	var left_strip := PanelContainer.new()
	left_strip.set_anchors_preset(Control.PRESET_TOP_LEFT)
	left_strip.position = Vector2(6, 6)
	left_strip.custom_minimum_size = Vector2(206, 132)
	left_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_strip.add_theme_stylebox_override("panel", UITheme.hud_strip_style())
	add_child(left_strip)
	_left_strip = left_strip

	# Top-center strip behind the mode/timer/score cluster.
	var top_strip := PanelContainer.new()
	top_strip.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top_strip.offset_left = -260
	top_strip.offset_right = 260
	top_strip.offset_top = 4
	top_strip.offset_bottom = 138  # room for the objective status line
	top_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_strip.add_theme_stylebox_override("panel", UITheme.hud_strip_style())
	add_child(top_strip)

	lbl_health = _make_label(Vector2(14, 10), UITheme.COL_HUD_HEALTH)
	lbl_fuel = _make_label(Vector2(14, 34), UITheme.COL_HUD_FUEL)
	lbl_ammo = _make_label(Vector2(14, 58), UITheme.COL_HUD_AMMO)
	lbl_weapon = _make_label(Vector2(14, 82), UITheme.COL_HUD_WEAPON)
	lbl_grenades = _make_label(Vector2(14, 106), UITheme.COL_HUD_GRENADE)
	scoreboard = Control.new()
	scoreboard.name = "Scoreboard"
	scoreboard.set_script(preload("res://scripts/scoreboard.gd"))
	scoreboard.set("hud", self)
	scoreboard.set("main", get_parent())
	add_child(scoreboard)
	var bars := Control.new()
	bars.name = "VitalsBars"
	bars.set_script(preload("res://scripts/hud_bars.gd"))
	bars.set("hud", self)
	add_child(bars)
	_bars = bars
	add_child(feed)
	lbl_map = Label.new()
	lbl_map.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_map.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl_map.offset_top = 8
	lbl_map.offset_bottom = 30
	lbl_map.add_theme_font_size_override("font_size", 15)
	lbl_map.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)
	lbl_map.add_theme_color_override("font_outline_color", UITheme.COL_SHADOW)
	lbl_map.add_theme_constant_override("outline_size", 3)
	add_child(lbl_map)
	lbl_status = Label.new()
	lbl_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_status.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl_status.offset_top = 28
	lbl_status.offset_bottom = 48
	lbl_status.add_theme_font_size_override("font_size", 12)
	lbl_status.add_theme_color_override("font_color", UITheme.COL_INFO)
	lbl_status.add_theme_color_override("font_outline_color", UITheme.COL_SHADOW)
	lbl_status.add_theme_constant_override("outline_size", 3)
	add_child(lbl_status)

	lbl_timer = Label.new()
	lbl_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_timer.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl_timer.offset_top = 50
	lbl_timer.offset_bottom = 82
	lbl_timer.add_theme_font_size_override("font_size", 24)
	lbl_timer.add_theme_color_override("font_color", UITheme.COL_ACCENT)
	lbl_timer.add_theme_color_override("font_outline_color", UITheme.COL_SHADOW)
	lbl_timer.add_theme_constant_override("outline_size", 5)
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
	lbl_winner.add_theme_color_override("font_color", UITheme.COL_ACCENT_HI)
	lbl_winner.add_theme_color_override("font_outline_color", UITheme.COL_SHADOW)
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
	command_line = HudCommands.new()
	command_line.hud = self
	add_child(command_line)

	# Chat feed — recent messages scroll bottom-up above the ammo readout.
	chat_feed = ChatFeed.new()
	add_child(chat_feed)

	radio_menu = preload("res://scripts/radio_menu.gd").new()
	add_child(radio_menu)

	# Weapon selection panel (#70) — death-triggered limbo menu: shows while the
	# player is dead, hides once they pick a weapon. See weapon_menu.gd _process.
	weapon_menu = WeaponMenu.new()
	add_child(weapon_menu)
	# First-matches controls card (H toggles).
	var hint := PanelContainer.new()
	hint.name = "ControlsHint"
	hint.set_script(preload("res://scripts/controls_hint.gd"))
	add_child(hint)
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
	var touch_ui: bool = OS.has_feature("android") or OS.has_feature("mobile") \
			or DisplayServer.is_touchscreen_available() or "--force-touch" in OS.get_cmdline_user_args()
	lbl_spectate_hint.text = tr("Tap left / right to switch view") if touch_ui \
			else tr("← / →  or  LB / RB  next target    ·    C  toggle free-cam")
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
	lbl_streak.offset_top = -150
	lbl_streak.offset_bottom = -150
	lbl_streak.add_theme_font_size_override("font_size", 32)
	lbl_streak.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl_streak.add_theme_constant_override("outline_size", 8)
	lbl_streak.modulate = Color(1, 1, 1, 0)
	lbl_streak.visible = false
	add_child(lbl_streak)

	# Vote prompt (#77) — vote_panel.gd.
	vote_panel = VotePanel.new()
	add_child(vote_panel)

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

	_build_info_labels()

	# Objective status line, announcements and off-screen markers.
	objective_hud = ObjectiveHud.new()
	objective_hud.main = get_parent()
	objective_hud.player_ref = func() -> Node2D: return player
	add_child(objective_hud)


func announce_objective(kind: String, team: int, who: String) -> void:
	if objective_hud != null:
		objective_hud.announce(kind, team, who)
	# Feed line too, so there's a record of it.
	if not is_instance_valid(feed):
		return
	var txt := ""
	match kind:
		"grab": txt = "%s took the %s flag" % [who, str(_team_display_info(team)["name"]) if team != 0 else "neutral"]
		"capture": txt = "%s scored for %s" % [who, str(_team_display_info(team)["name"])]
		"dom": txt = "%s captured point %s" % [str(_team_display_info(team)["name"]), who]
		"point": txt = "%s +1 point" % who
		_: return
	feed.add_text(txt, _team_display_info(team).get("color", Color(1, 0.85, 0.35)))


func show_streak_banner(killer_name: String, title: String, killer_team: int, count: int) -> void:
	# Overwrites any in-progress banner — a rapid escalation from Double → Multi
	# should read as one crescendo, not two overlapping labels.
	if lbl_streak == null:
		return
	var info := _team_display_info(killer_team)
	var col: Color = info.get("color", Color(1.0, 0.85, 0.35))
	lbl_streak.text = "%s\n%s  ×%d" % [tr(title).to_upper(), killer_name, count]
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
	feed.add_text(tr("%s ended %s's %d-kill streak") % [ender_name, victim_name, streak_len], col)


func set_spectate_target(name: String, col: Color) -> void:
	# Called by Spectator whenever the follow target or free-cam mode changes.
	# Empty name hides the label — happens when spectator deactivates on respawn.
	if lbl_spectate == null:
		return
	if name == "":
		lbl_spectate.visible = false
		lbl_spectate_hint.visible = false
		return
	lbl_spectate.text = tr("Spectating: %s") % name
	lbl_spectate.add_theme_color_override("font_color", col)
	lbl_spectate.visible = not rewind_on
	lbl_spectate_hint.visible = not rewind_on


func set_killcam(name: String, hp: int, weapon: String, col: Color) -> void:
	if lbl_spectate == null:
		return
	var w := (" · " + tr(weapon)) if weapon != "" else ""
	lbl_spectate.text = tr("KILL CAM: %s") % name + "  ·  " + (tr("%d HP left") % maxi(0, hp)) + w
	lbl_spectate.add_theme_color_override("font_color", col)
	lbl_spectate.visible = not rewind_on
	lbl_spectate_hint.visible = not rewind_on


## Kill cam rewind start / end: hide the death text, grey overlay, spectate
## label and the help card while it plays; put them back after.
func set_rewind(on: bool) -> void:
	rewind_on = on
	var hint := get_node_or_null("ControlsHint")
	if on:
		for c in [lbl_death, lbl_respawn, desat_overlay, lbl_spectate, lbl_spectate_hint]:
			if c != null:
				c.visible = false
		if hint != null:
			hint.visible = false
	elif _dead:
		desat_overlay.visible = true
		var m := get_parent()
		if m != null and m.get("spectator") != null and is_instance_valid(m.spectator) and m.spectator.is_active():
			m.spectator._notify_hud()


## Typed line (gestures / commands / chat) — hud_commands.gd.
func open_command(prefill: String = "/") -> void:
	command_line.open_command(prefill)


func open_chat(scope: String) -> void:
	command_line.open_chat(scope)


func _close_command() -> void:
	command_line.close_command()


func _try_vote_command(raw: String) -> bool:
	return command_line.try_vote_command(raw)


func _try_host_command(raw: String) -> bool:
	return command_line.try_host_command(raw)


func _resolve_mode_arg(a: String) -> int:
	return command_line.resolve_mode_arg(a)


func _resolve_map_arg(a: String) -> int:
	return command_line.resolve_map_arg(a)


func _update_vote_ui() -> void:
	if vote_panel != null:
		vote_panel.refresh(get_parent())


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
	var hint: String = GameInfo.item_short(kind)
	lbl_bonus.text = "%s  %ds%s" % [BonusPickup.kind_label(kind), int(ceil(t)), ("  ·  " + hint) if hint != "" else ""]
	lbl_bonus.add_theme_color_override("font_color", BonusPickup.kind_color(kind))
	lbl_bonus.visible = true


# ── Mode banner + pickup toasts (v1.18) ──────────────────
var lbl_mode_banner: Label
var lbl_toast: Label
var lbl_vehicle: Label
var _banner_t := 0.0
var _toast_t := 0.0
const BANNER_HOLD := 7.0
const TOAST_HOLD := 3.5


func _build_info_labels() -> void:
	lbl_mode_banner = Label.new()
	lbl_mode_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_mode_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_mode_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl_mode_banner.offset_left = 220
	lbl_mode_banner.offset_right = -220
	lbl_mode_banner.offset_top = 150
	lbl_mode_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_mode_banner.add_theme_font_size_override("font_size", 18)
	lbl_mode_banner.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	lbl_mode_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl_mode_banner.add_theme_constant_override("outline_size", 6)
	add_child(lbl_mode_banner)
	lbl_toast = Label.new()
	lbl_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_toast.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	lbl_toast.offset_left = 200
	lbl_toast.offset_right = -200
	lbl_toast.offset_top = -120
	lbl_toast.offset_bottom = -66
	lbl_toast.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	lbl_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_toast.add_theme_font_size_override("font_size", 17)
	lbl_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl_toast.add_theme_constant_override("outline_size", 6)
	lbl_toast.visible = false
	add_child(lbl_toast)
	lbl_vehicle = Label.new()
	lbl_vehicle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_vehicle.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	lbl_vehicle.offset_top = -98
	lbl_vehicle.offset_bottom = -64
	lbl_vehicle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_vehicle.add_theme_font_size_override("font_size", 18)
	lbl_vehicle.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl_vehicle.add_theme_constant_override("outline_size", 6)
	lbl_vehicle.visible = false
	add_child(lbl_vehicle)
	show_mode_banner()


# "CAPTURE THE FLAG — grab the enemy flag…" for the first seconds of a match.
func show_mode_banner() -> void:
	if lbl_mode_banner == null:
		return
	var gm: int = Settings.game_mode
	var t := "%s\n%s" % [GameInfo.mode_title(gm), GameInfo.mode_goal(gm)]
	var subs: PackedStringArray = PackedStringArray()
	for k in ["realistic", "survival", "advance"]:
		if bool(Settings.get(k)):
			subs.append(str(GameInfo.SUBMODES[k]))
	if not subs.is_empty():
		t += "\n" + "  ".join(subs)
	lbl_mode_banner.text = t
	lbl_mode_banner.modulate.a = 1.0
	lbl_mode_banner.visible = true
	_banner_t = BANNER_HOLD


# Pickup explainer: "VEST — you take half damage for 30 s."
func toast(title: String, desc: String, col: Color = Color(1, 1, 1)) -> void:
	if lbl_toast == null:
		return
	lbl_toast.text = title if desc == "" else "%s — %s" % [title, desc]
	lbl_toast.add_theme_color_override("font_color", col)
	lbl_toast.modulate.a = 1.0
	lbl_toast.visible = true
	_toast_t = TOAST_HOLD


# Buggy readout while you're in one: its health, the gun's heat, and a note
# when you're driving solo (firing slows you down).
func _tick_vehicle_label() -> void:
	if lbl_vehicle == null:
		return
	var v = player.get("mounted_m2") if is_instance_valid(player) else null
	if v == null or not is_instance_valid(v) or not v.is_in_group("vehicle"):
		lbl_vehicle.visible = false
		return
	var hp_frac: float = float(v.hp) / float(v.MAX_HP)
	var gun := "GUN OVERHEATED" if v.overheated else "GUN %d%%" % int(round(float(v.heat) * 100.0))
	if str(v.kind) == "tank":
		gun = "SHELL READY" if float(v.fire_cd) <= 0.0 else "RELOADING %.1fs" % float(v.fire_cd)
	var t := "%s  %d HP  ·  %s" % [str(v.LABEL), int(v.hp), gun]
	if v.driver() == player and v.gunner() == null:
		t += "  ·  solo: slower while firing"
	elif v.gunner() != null and v.gunner() != player and v.gunner().get("bot_id") != null:
		t += "  ·  %s on the gun" % str(v.gunner().get("display_name"))
	lbl_vehicle.text = t
	lbl_vehicle.add_theme_color_override("font_color", Color(0.95, 0.35, 0.25) if v.overheated or hp_frac < 0.3 else Color(0.95, 0.85, 0.5))
	lbl_vehicle.visible = true


func _tick_info_labels(delta: float) -> void:
	_tick_vehicle_label()
	_tick_achievements()
	if lbl_mode_banner != null and lbl_mode_banner.visible:
		_banner_t -= delta
		lbl_mode_banner.modulate.a = clampf(_banner_t, 0.0, 1.0)
		if _banner_t <= 0.0:
			lbl_mode_banner.visible = false
	if lbl_toast != null and lbl_toast.visible:
		_toast_t -= delta
		lbl_toast.modulate.a = clampf(_toast_t / 0.6, 0.0, 1.0)
		if _toast_t <= 0.0:
			lbl_toast.visible = false


func toggle_radio() -> void:
	if radio_menu == null or command_line.is_open:
		return
	radio_menu.player = player
	radio_menu.toggle()


# Radio line in the chat feed: amber, tagged, and team-only by construction.
func post_radio(author: String, text: String) -> void:
	if not is_instance_valid(chat_feed):
		return
	chat_feed.add_radio(author, text)


func post_chat(author: String, msg: String, is_team: bool) -> void:
	if not is_instance_valid(chat_feed):
		return
	chat_feed.add_chat(author, msg, is_team)


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


func _make_label(pos: Vector2, col: Color) -> Label:
	# HUD readouts — position from top-left, tight outline for high contrast
	# over bright sky/terrain. Font size 17 matches UITheme.style_hud_label.
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", UITheme.COL_SHADOW)
	l.add_theme_constant_override("outline_size", 4)
	add_child(l)
	return l


func show_death(killer: String, weapon: String, respawn_secs: float = 2.0) -> void:
	_dead = true
	# Countdown matches the real respawn delay so the label doesn't tick to 0
	# while the player is still on the floor (INF attackers pay 5s, not 2s).
	# Pass a negative value to display the "no respawn" survival hint instead.
	_death_remaining = respawn_secs
	var me: String = str(player.display_name) if is_instance_valid(player) else Settings.display_name()
	var suicide: bool = killer != "" and killer == me
	lbl_death.text = (tr("You were killed by %s") % killer) if killer != "" and not suicide else tr("You died")
	if weapon != "" and killer != "" and not suicide:
		lbl_death.text += "  [%s]" % weapon
	lbl_death.visible = true
	lbl_respawn.visible = true
	desat_overlay.visible = true


## "BLUE 3 alive · RED 2 alive" (team modes) or "4 left" (FFA) for the
## Survival waiting screen.
func _alive_summary() -> String:
	var blue := 0
	var red := 0
	var all := 0
	for s in get_tree().get_nodes_in_group("soldier"):
		if not is_instance_valid(s) or bool(s.get("dead")):
			continue
		all += 1
		match int(s.get("team")):
			1: blue += 1
			2: red += 1
	if Settings.is_team_mode():
		return tr("BLUE %d alive  ·  RED %d alive") % [blue, red]
	return tr("%d left") % all


func _hide_death() -> void:
	_dead = false
	lbl_death.visible = false
	lbl_respawn.visible = false
	desat_overlay.visible = false


## Kill-feed weapon icon (kill_feed.gd); hud_bars.gd reads it for the vitals box.
func _kill_icon(weapon: String) -> Texture2D:
	return feed.kill_icon(weapon)


func _on_kill(killer_name: String, victim_name: String, weapon_name: String, killer_team: int, _victim_team: int) -> void:
	# Reuse the scoreboard's team palette so BLUE/RED kills read as their team
	# color instead of everyone-not-us collapsing to red.
	var info := _team_display_info(killer_team)
	var kcol: Color = info.get("color", Color(1.0, 0.45, 0.45))
	feed.add_kill(killer_name, victim_name, weapon_name, kcol)
	if is_instance_valid(player) and killer_name == str(player.display_name) and victim_name != killer_name:
		_kill_confirm(victim_name, weapon_name.ends_with("(headshot)"))


var _confirm_lbl: Label
var _confirm_tween: Tween


## Short "KILLED <name>" line under the action when *you* score a kill.
func _kill_confirm(victim: String, headshot: bool) -> void:
	if _confirm_lbl == null:
		_confirm_lbl = Label.new()
		_confirm_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		_confirm_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_confirm_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_confirm_lbl.offset_top = 150
		_confirm_lbl.offset_bottom = 150
		_confirm_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_confirm_lbl.add_theme_font_size_override("font_size", 17)
		_confirm_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_confirm_lbl.add_theme_constant_override("outline_size", 4)
		add_child(_confirm_lbl)
	_confirm_lbl.text = (tr("KILLED  %s  ·  HEADSHOT") if headshot else tr("KILLED  %s")) % victim
	_confirm_lbl.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45) if headshot else Color(1.0, 0.88, 0.55))
	_confirm_lbl.modulate.a = 1.0
	_confirm_lbl.visible = true
	if _confirm_tween != null and _confirm_tween.is_valid():
		_confirm_tween.kill()
	_confirm_tween = create_tween()
	_confirm_tween.tween_interval(1.1)
	_confirm_tween.tween_property(_confirm_lbl, "modulate:a", 0.0, 0.4)


func _input(event: InputEvent) -> void:
	# Record-GIF hotkey (default F9, rebindable via controls_map). Kept on the HUD
	# rather than the player so it still works from the death screen and menus.
	if event.is_action_pressed("record_gif"):
		GifRecorder.toggle()
	if _next_map_key(event):
		return
	# Vote hotkeys (#77) — F1/F2 rebindable. Only meaningful while a vote is
	# active. Ignored while the command line is open so a "yes" typed as text
	# doesn't accidentally cast when the user hits F1.
	if command_line.is_open:
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


var _locked_looks: Array = []
var unlock_toasts := 0   # for tests
var _looks_t := 0.0


# New customization unlocked this match (level up / achievement): say so.
func _check_new_looks(delta: float) -> void:
	_looks_t -= delta
	if _looks_t > 0.0:
		return
	_looks_t = 1.5
	var C = preload("res://scripts/customization.gd")
	var now: Array = C.locked_list()
	var names: Array = []
	for item in _locked_looks:
		if not now.has(item):
			var parts := String(item).split(":")
			names.append(C.item_name(parts[0], parts[1]))
	if not names.is_empty():
		# Through the achievement queue so it never hides a RANK UP or an
		# achievement that fired at the same moment.
		_ach_queue.append([tr("UNLOCKED"), ", ".join(names) + "  ·  " + tr("main menu > CUSTOMIZE"), true])
		unlock_toasts += 1
	_locked_looks = now


## Graphics preset changed (or HUD built): post FX on/off, bloom on High.
func apply_gfx_quality() -> void:
	if post_fx == null:
		return
	var G = preload("res://scripts/gfx.gd")
	post_fx.visible = G.on(G.MEDIUM)
	var sm := post_fx.material as ShaderMaterial
	sm.set_shader_parameter("bloom", 0.85 if G.on(G.HIGH) else 0.0)
	sm.set_shader_parameter("vignette", 0.34 if UITheme.is_touch() == false else 0.22)


## Red edge + colour split when the local player takes damage.
func _tick_hit_fx(delta: float) -> void:
	if post_fx == null or not post_fx.visible:
		return
	var hp := -1.0
	if is_instance_valid(player) and not bool(player.get("dead")):
		hp = float(player.get("health"))
	if hp >= 0.0 and _last_hp >= 0.0 and hp < _last_hp - 0.5:
		_hit_fx = clampf(_hit_fx + (_last_hp - hp) / 45.0, 0.0, 1.0)
	_last_hp = hp
	if _hit_fx > 0.0:
		_hit_fx = maxf(0.0, _hit_fx - delta * 2.4)
	(post_fx.material as ShaderMaterial).set_shader_parameter("hit", _hit_fx)


func _process(delta: float) -> void:
	_tick_hit_fx(delta)
	_check_new_looks(delta)
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
	_tick_info_labels(delta)
	# The round-end banner owns the middle of the screen; the death lines
	# printed over "BLUE WINS" / the MVP line (Survival especially).
	var winner_up: bool = lbl_winner != null and lbl_winner.visible
	if _dead:
		lbl_death.visible = not winner_up and not rewind_on
		lbl_respawn.visible = not winner_up and not rewind_on
		desat_overlay.visible = not rewind_on
	if _dead:
		if _death_remaining < 0.0:
			# Survival: no respawn until the round resets. The desaturated overlay
			# stays up until show_death is called again (or _hide_death fires).
			lbl_respawn.text = tr("Waiting for next round") + "  ·  " + _alive_summary()
		else:
			_death_remaining -= delta
			lbl_respawn.text = tr("Respawning in %d") % maxi(0, int(ceil(_death_remaining)))
			if _death_remaining <= 0.0:
				_hide_death()
	# Prefix the mode (full name) so users know which rules are live.
	var mode_str: String = GameInfo.mode_title(Settings.game_mode).capitalize() + " · "
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
			mode_str = "Battle Royale · zone %dm · " % int(z.get("radius", 0.0) / 10.0)
	lbl_map.text = mode_str + map_name
	lbl_status.text = Net.status.get_slice("\n", 0) if Net.is_networked() else ""
	_update_match_ui()
	# No body (dead / spectating): hide the empty vitals box; the limbo
	# weapon menu takes that corner.
	var has_body: bool = is_instance_valid(player)
	if _left_strip != null:
		_left_strip.visible = has_body
	if _bars != null:
		_bars.visible = has_body
	if not has_body:
		# Blank the per-player readouts so we don't display last-frame HP/Fuel/Ammo
		# for a body that no longer exists (spectator, mid-respawn, disconnect).
		lbl_health.text = ""
		lbl_fuel.text = ""
		lbl_weapon.text = ""
		lbl_ammo.text = ""
		lbl_grenades.text = ""
		return
	# Defensive: bail if weapon_index or the array shape drifted mid-frame.
	var wi: int = int(player.weapon_index)
	if wi < 0 or wi >= player.weapons.size() or wi >= player.ammo.size():
		return
	lbl_health.text = "HP %d" % int(player.health)
	lbl_fuel.text = "JET %d" % int(player.fuel)
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
	lbl_ammo.text = "%d / %d" % [mag, int(w["mag"])] + (("  · " + tr("RELOADING")) if player.reloading else "")
	lbl_weapon.text = str(w["name"])
	# Gun Game: overwrite the weapon label with the ladder rung so players see
	# their race progress at a glance. Knife rung nudges them to close the deal.
	if Settings.game_mode == Settings.MODE_GG:
		var lvl: int = int(player.get("gg_level"))
		# GG_LADDER is a script const on player.gd, not a member var — Object.get()
		# returns null for constants, so read the array through the script class
		# (bug slipped in with aed7530's Gun Game HUD path).
		var ladder: Array = PlayerScript.GG_LADDER
		if ladder != null and ladder.size() > 0:
			if lvl > ladder.size() - 1:
				lbl_weapon.text = "Gun Game — Golden Knife · kill to win"
			else:
				var idx: int = clampi(lvl, 0, ladder.size() - 1)
				var wname: String = str((ladder[idx] as Dictionary).get("name", ""))
				var suffix: String = "  · Knife kill to win" if lvl >= ladder.size() - 1 else ""
				lbl_weapon.text = "Gun Game — %s (%d/%d)%s" % [wname, lvl + 1, ladder.size(), suffix]
	var gtype := "CLUSTER" if bool(player.get("use_cluster")) else "FRAG"
	lbl_grenades.text = tr("GRENADES %d  [%s]") % [player.grenades, gtype]


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
	if Settings.game_mode == Settings.MODE_GG:
		# #91: GG scoreboard — per-soldier rung + kills instead of team scores.
		# Reads _gg_levels + _gg_kills off main (host authoritative, mirrored
		# to clients via net_match_state).
		_render_gg_scoreboard(main)
	else:
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
		if Settings.is_team_mode():
			# Always both sides — in Survival a wiped-out team (no living
			# soldiers, no points yet) used to vanish from the strip.
			ordered = [1, 2]
		if not Settings.is_team_mode():
			# FFA (bots fight each other too): leaderboard — best first, top 4,
			# and the local player's line always shown.
			ordered.sort_custom(func(a, b) -> bool: return int(scores.get(a, 0)) > int(scores.get(b, 0)) \
					or (int(scores.get(a, 0)) == int(scores.get(b, 0)) and int(a) < int(b)))
			var mine: int = int(player.team) if is_instance_valid(player) else -999
			var top: Array = ordered.slice(0, 4)
			if mine != -999 and ordered.has(mine) and not top.has(mine):
				top.append(mine)
			ordered = top
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
		lbl_winner.text = tr("%s WINS") % info["name"]
		lbl_winner.add_theme_color_override("font_color", info["color"])
		lbl_winner.visible = true
	elif not active and winner < 0:
		lbl_winner.text = tr("DRAW")
		lbl_winner.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		lbl_winner.visible = true
	else:
		lbl_winner.visible = false
	_update_next_map(main, active)
	if lbl_winner_note != null:
		# MVP: best kills + 3x captures this round (from the scoreboard stats).
		var mvp := ""
		var best := -9999
		var ps: Dictionary = main.get("player_stats") if main.get("player_stats") != null else {}
		for n in ps.keys():
			var st: Dictionary = ps[n]
			var sc: int = int(st.get("k", 0)) + 3 * int(st.get("c", 0))
			if sc > best:
				best = sc
				mvp = "MVP: %s  (%d kills%s)" % [str(n), int(st.get("k", 0)), (", %d caps" % int(st.get("c", 0))) if int(st.get("c", 0)) > 0 else ""]
		var full := note
		if lbl_winner.visible and mvp != "" and best > 0:
			full = (note + "   ·   " if note != "" else "") + mvp
		lbl_winner_note.text = full
		lbl_winner_note.visible = lbl_winner.visible and full != ""


# ── End-of-round map vote (winner screen) — next_map_panel.gd ──
var next_map_panel: NextMapPanel = null


func _update_next_map(main: Node, active: bool) -> void:
	var choices: Array = main.get("next_map_choices") if main.get("next_map_choices") != null else []
	var show: bool = not active and not choices.is_empty()
	if not show:
		if next_map_panel != null:
			next_map_panel.visible = false
		return
	if next_map_panel == null:
		next_map_panel = NextMapPanel.new()
		add_child(next_map_panel)
	next_map_panel.refresh(main)


func _next_map_key(event: InputEvent) -> bool:
	if next_map_panel == null:
		return false
	return next_map_panel.handle_key(event)


func _render_gg_scoreboard(main: Node) -> void:
	# #91: GG-specific scoreboard. Each row is "NAME  RUNG X/16  Y kills".
	# Highest rung first, kills break ties. Colors come from the soldier body
	# so BLUE/RED/YOU still read at a glance.
	var gg_levels: Dictionary = main.get("_gg_levels") if main.get("_gg_levels") != null else {}
	var gg_kills: Dictionary = main.get("_gg_kills") if main.get("_gg_kills") != null else {}
	var rungs_total: int = PlayerScript.GG_LADDER.size() if PlayerScript.GG_LADDER != null else 16
	var rows: Array = []
	for soldier in get_tree().get_nodes_in_group("soldier"):
		if not is_instance_valid(soldier):
			continue
		var nm: String = str(soldier.get("display_name"))
		if nm == "":
			continue
		var lvl: int = int(gg_levels.get(nm, 0))
		var kills: int = int(gg_kills.get(nm, 0))
		var col: Color = soldier.color if soldier.get("color") != null else Color(0.85, 0.85, 0.85)
		rows.append({"name": nm, "lvl": lvl, "kills": kills, "col": col})
	rows.sort_custom(func(a, b) -> bool:
		if a["lvl"] != b["lvl"]:
			return a["lvl"] > b["lvl"]
		return a["kills"] > b["kills"])
	if rows.is_empty():
		lbl_score.text = "[center]Gun Game[/center]"
		return
	var parts: PackedStringArray = PackedStringArray()
	for row in rows:
		var col_hex: String = (row["col"] as Color).to_html(false)
		parts.append("[color=#%s][b]%s[/b] R%d/%d · %dk[/color]" % [col_hex, row["name"], int(row["lvl"]) + 1, rungs_total, row["kills"]])
	lbl_score.text = "[center]" + "   ·   ".join(parts) + "[/center]"


func _team_display_info(team_id: int) -> Dictionary:
	if not Net.is_networked():
		# INF: fixed defender / attacker labels.
		if Settings.game_mode == Settings.MODE_INF:
			if team_id == 1:
				return {"name": "DEFENDERS", "color": Color(0.4, 0.6, 1.0)}
			if team_id == 2:
				return {"name": "ATTACKERS", "color": preload("res://scripts/team_colors.gd").red(true)}
		# Team modes generally: fixed BLUE/RED colors + labels.
		if Settings.game_mode != Settings.MODE_DM and Settings.game_mode != Settings.MODE_RM:
			if team_id == 1:
				return {"name": "BLUE", "color": Color(0.4, 0.6, 1.0)}
			if team_id == 2:
				return {"name": "RED", "color": preload("res://scripts/team_colors.gd").red(true)}
		if team_id == 0:
			return {"name": "YOU", "color": Color(0.35, 0.85, 0.5)}
		# FFA bots: each is its own team — label with the bot's name/colour.
		for s in get_tree().get_nodes_in_group("soldier"):
			if is_instance_valid(s) and int(s.team) == team_id:
				return {"name": str(s.display_name).to_upper(), "color": s.color}
		return {"name": "BOT %d" % (team_id - 999 if team_id >= 1000 else team_id), "color": Color(0.9, 0.35, 0.3)}
	# MP: reuse the soldier's own color + display_name for their team.
	for s in get_tree().get_nodes_in_group("soldier"):
		if not is_instance_valid(s):
			continue
		if int(s.team) == team_id:
			return {"name": str(s.display_name).to_upper(), "color": s.color}
	# Fallback for teams whose only soldier already left / died mid-round.
	return {"name": "P%d" % team_id, "color": Color(0.7, 0.7, 0.75)}



var _ach_queue: Array = []


# Achievements queue up so two at once (or a pickup toast) don't hide one.
func _on_achievement(_id: String, title: String, desc: String) -> void:
	_ach_queue.append([title, desc])


func _tick_achievements() -> void:
	if _ach_queue.is_empty() or (lbl_toast != null and lbl_toast.visible):
		return
	var a: Array = _ach_queue.pop_front()
	var head := str(a[0]).to_upper()
	if a.size() > 2:
		toast(head, str(a[1]), Color(1.0, 0.85, 0.4))
	else:
		toast(head if head == "RANK UP" else "ACHIEVEMENT: %s" % head, str(a[1]), Color(1.0, 0.82, 0.3))
	Sfx.objective("point")
