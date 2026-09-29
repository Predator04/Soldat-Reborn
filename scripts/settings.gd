extends Node
## Settings — persistent user preferences (autoload singleton "Settings").

const PATH := "user://settings.cfg"
const ControlsMap = preload("res://scripts/controls_map.gd")

var sfx_volume := 1.0          # 0.0 = muted, 1.0 = full
var music_volume := 0.55       # 0.0..1.0 — separate from sfx so a quiet music track doesn't kill weapon SFX
var music_muted := false
# Screen shake is now a 0.0..1.0 intensity multiplier applied to _shake calls;
# `screen_shake > 0` preserves the old "shake on" semantics for legacy readers.
var screen_shake := true
var screen_shake_intensity := 1.0
var fullscreen := false
var map_index := 0             # which map layout the next game loads
var custom_map_path := ""      # if non-empty, main.gd loads this JSON map (issue #31)
var lofi_auto_done := false    # the low-FPS guard already switched Lo-fi on once
var lofi := false              # low-end mode: no particles, no gib meshes, no glow
var mouse_sensitivity := 1.0   # 0.25..3.0 — scales incoming mouse motion via Input.set_custom_mouse_cursor + relative event scale
# Android on-screen touch layout (issue #116 / #117). Default is the standard
# dual-stick scheme: LEFT half = movement joystick, RIGHT half = aim + fire.
# Toggling swap flips to LEFT = aim, RIGHT = move (the pre-#117 layout).
var touch_swap := false
# Per-button custom positions for the six edge buttons (#117). Keyed by the
# action name (e.g. "jet", "grenade"); value is the button CENTER position as a
# Vector2. Empty dict = use built-in default anchor layout. Populated from the
# in-game "Customize touch layout" editor (touch_controls.gd), reset by the
# "Reset touch layout" action.
var touch_btn_pos: Dictionary = {}
var show_fps := false          # overlay FPS counter on the HUD
var pause_on_focus_loss := true  # open the pause menu when the window / app loses focus
var check_updates := true      # look for a newer release on GitHub at startup
var colorblind := false        # red team drawn orange (blue / orange)
var last_seen_version := ""    # "what's new" shows once per new version
var vehicles := true   # buggies on maps with room (host decides in multiplayer)
var vsync := true
var max_fps := 0                # 0 = unlimited (VSync still caps it)
var damage_numbers := true     # floating damage numbers when you land a hit
var help_seen := 0             # matches that auto-showed the controls card
var bot_chatter := true        # bots trash-talk in chat now and then
var spawn_primary := 2         # limbo weapon menu pick (AK-74)
var spawn_secondary := 0       # (USSOCOM)
var camera_lead := true        # view slides toward where you aim (Soldat style)
var blood_intensity := 1.0     # 0.0..1.5 — visual gore multiplier (particles + gib count in gostek/gibs)

# Cosmetics — the local player's persistent character look.
# Values match filenames in assets/gostek-gfx/:
#   head:       "helm" | "kap" | "hair1" | "hair2" | "hair3" | "hair4" | "none"
#   chain:      "none" | "silver" | "gold"
#   vest:       bool (kamizelka on/off)
#   cigar:      bool (cygaro on/off)
#   dreadlocks: bool (dred tuft overlay on top of hair, issue #60)
#   dogtag:     bool (metal dogtag hanging over torso, issue #60)
var cos_head := "helm"
var cos_vest := true
var cos_chain := "none"
var cos_cigar := false
var cos_dreadlocks := false
var cos_dogtag := false

# Game mode: 0 = Deathmatch, 1 = Teammatch, 2 = CTF, 3 = Infiltration,
# 4 = Hold the Flag, 5 = Rambomatch, 6 = Pointmatch, 7 = Domination,
# 8 = Battle Royale. Sub-modes (Realistic / Survival / Advance) overlay on
# the base mode via separate flags below.
const MODE_DM := 0
const MODE_TDM := 1
const MODE_CTF := 2
const MODE_INF := 3
const MODE_HTF := 4
const MODE_RM := 5
const MODE_PM := 6
const MODE_DOM := 7
const MODE_BR := 8
const MODE_GG := 9
var game_mode := MODE_DM

# Sub-mode overlays — toggle-able flags applied on top of the base mode.
var realistic := false   # no jet, no HUD ammo, head-shot 1HK (issue #19)
var survival := false    # no respawn until round end (issue #20)
var advance := false     # weapon unlock ladder (issue #21)

# Modifiers (#24) — scale the base rules without changing the game mode.
# 1.0 = stock Soldat. Menu clamps the visible range; code should treat these as
# untrusted floats and use them at their scale sites (see player.gd / grenade.gd).
var mod_gravity := 1.0        # 0.5–2.0. Applied to player + grenade gravity.
var mod_jet := 1.0            # 0.5–2.0. Scales jet regen (higher = faster refill).
var mod_damage := 1.0         # 0.5–2.0. Multiplies outgoing bullet / rocket / melee damage.
var mod_speed := 1.0          # 0.5–1.5. Player horizontal cap and accel.

# Bots (#67). bot_count -1 = "use every map spawn" (previous behavior); 0-8 caps
# the number spawned. bot_skill 1-5 scales aim precision + reaction — see bot.gd.
var bot_count := -1
var bot_skill := 3

# Multiplayer lobby / master server (#33). server_name is what a dedicated host
# advertises to the master; master_url is the "Browse Servers" list endpoint.
var server_name := "Soldat Server"
var last_join_ip := "127.0.0.1"   # Join panel remembers the last address
var last_join_port := 7777
var host_public := false        # listen host registers with the master server
var upnp := true                # host asks the router to open its ports (UPnP)
var player_name := "Player"
var name_set := false
var training := false          # runtime only: the Training match is running
var training_saved: Dictionary = {}   # the match settings Training replaced          # first-launch name prompt answered
var master_url := ""

# Convenience: DM / Rambo / Battle Royale / Gun Game are FFA (friendly-fire on), teams disable friendly damage.
func friendly_fire_on() -> bool:
	return game_mode == MODE_DM or game_mode == MODE_RM or game_mode == MODE_BR or game_mode == MODE_GG


func is_team_mode() -> bool:
	return game_mode == MODE_TDM or game_mode == MODE_CTF or game_mode == MODE_INF \
		or game_mode == MODE_HTF or game_mode == MODE_PM or game_mode == MODE_DOM


func _ready() -> void:
	load_settings()
	# #115: create joy-only actions (aim_*, pause) + gamepad defaults FIRST, then
	# apply saved rebinds over them. The old order skipped saved aim_*/pause
	# binds (actions didn't exist yet) and re-added removed pad defaults.
	ControlsMap.install_defaults()
	ControlsMap.load_and_apply()


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	sfx_volume = float(cf.get_value("audio", "sfx_volume", 1.0))
	music_volume = clampf(float(cf.get_value("audio", "music_volume", 0.55)), 0.0, 1.0)
	music_muted = bool(cf.get_value("audio", "music_muted", false))
	screen_shake_intensity = clampf(float(cf.get_value("game", "screen_shake_intensity", 1.0)), 0.0, 2.0)
	# Derive the legacy boolean from the intensity slider so callers reading
	# either see consistent state. A migration path from configs that only wrote
	# `screen_shake` (pre-intensity) still respects the old value if intensity
	# was defaulted.
	if not cf.has_section_key("game", "screen_shake_intensity"):
		screen_shake = bool(cf.get_value("game", "screen_shake", true))
		screen_shake_intensity = 1.0 if screen_shake else 0.0
	else:
		screen_shake = screen_shake_intensity > 0.01
	fullscreen = bool(cf.get_value("video", "fullscreen", false))
	map_index = int(cf.get_value("game", "map_index", 0))
	custom_map_path = str(cf.get_value("game", "custom_map_path", ""))
	game_mode = clampi(int(cf.get_value("game", "game_mode", MODE_DM)), MODE_DM, MODE_GG)
	map_index = maxi(0, map_index)  # upper bound checked by main against the map list
	realistic = bool(cf.get_value("game", "realistic", false))
	survival = bool(cf.get_value("game", "survival", false))
	advance = bool(cf.get_value("game", "advance", false))
	lofi = bool(cf.get_value("video", "lofi", false))
	lofi_auto_done = bool(cf.get_value("video", "lofi_auto_done", false))
	mouse_sensitivity = clampf(float(cf.get_value("controls", "mouse_sensitivity", 1.0)), 0.25, 3.0)
	touch_swap = bool(cf.get_value("controls", "touch_swap", false))
	# touch_btn_pos: legacy configs won't have it; default is an empty dict.
	# Also normalise entries so an old array-style [x, y] load still resolves to
	# Vector2 downstream.
	var raw_pos: Variant = cf.get_value("controls", "touch_btn_pos", {})
	touch_btn_pos = {}
	if raw_pos is Dictionary:
		for k in raw_pos.keys():
			var v: Variant = raw_pos[k]
			if v is Vector2:
				touch_btn_pos[str(k)] = v
			elif v is Array and v.size() >= 2:
				touch_btn_pos[str(k)] = Vector2(float(v[0]), float(v[1]))
	show_fps = bool(cf.get_value("video", "show_fps", false))
	damage_numbers = bool(cf.get_value("video", "damage_numbers", true))
	vsync = bool(cf.get_value("video", "vsync", true))
	max_fps = clampi(int(cf.get_value("video", "max_fps", 0)), 0, 360)
	pause_on_focus_loss = bool(cf.get_value("game", "pause_on_focus_loss", true))
	check_updates = bool(cf.get_value("game", "check_updates", true))
	colorblind = bool(cf.get_value("video", "colorblind", false))
	last_seen_version = str(cf.get_value("game", "last_seen_version", ""))
	vehicles = bool(cf.get_value("game", "vehicles", true))
	bot_chatter = bool(cf.get_value("game", "bot_chatter", true))
	camera_lead = bool(cf.get_value("controls", "camera_lead", true))
	help_seen = int(cf.get_value("game", "help_seen", 0))
	spawn_primary = clampi(int(cf.get_value("loadout", "primary", 2)), 0, 9)
	spawn_secondary = clampi(int(cf.get_value("loadout", "secondary", 0)), 0, 3)
	blood_intensity = clampf(float(cf.get_value("game", "blood_intensity", 1.0)), 0.0, 1.5)
	cos_head = str(cf.get_value("cosmetics", "head", "helm"))
	cos_vest = bool(cf.get_value("cosmetics", "vest", true))
	cos_chain = str(cf.get_value("cosmetics", "chain", "none"))
	cos_cigar = bool(cf.get_value("cosmetics", "cigar", false))
	cos_dreadlocks = bool(cf.get_value("cosmetics", "dreadlocks", false))
	cos_dogtag = bool(cf.get_value("cosmetics", "dogtag", false))
	mod_gravity = clampf(float(cf.get_value("mods", "gravity", 1.0)), 0.5, 2.0)
	mod_jet = clampf(float(cf.get_value("mods", "jet", 1.0)), 0.5, 2.0)
	mod_damage = clampf(float(cf.get_value("mods", "damage", 1.0)), 0.5, 2.0)
	mod_speed = clampf(float(cf.get_value("mods", "speed", 1.0)), 0.5, 1.5)
	bot_count = clampi(int(cf.get_value("bots", "count", -1)), -1, 8)
	bot_skill = clampi(int(cf.get_value("bots", "skill", 3)), 1, 5)
	server_name = str(cf.get_value("net", "server_name", "Soldat Server"))
	last_join_ip = str(cf.get_value("net", "last_join_ip", "127.0.0.1"))
	host_public = bool(cf.get_value("net", "host_public", false))
	upnp = bool(cf.get_value("net", "upnp", true))
	last_join_port = clampi(int(cf.get_value("net", "last_join_port", 7777)), 1, 65535)
	player_name = str(cf.get_value("net", "player_name", "Player"))
	# Players from before the prompt existed who already picked a name keep it.
	name_set = bool(cf.get_value("net", "name_set", player_name != "Player"))
	master_url = str(cf.get_value("net", "master_url", ""))


func save() -> void:
	# Training swaps in its own match settings; never write those to disk.
	if training and not training_saved.is_empty():
		var live := {}
		for k in training_saved.keys():
			live[k] = get(k)
			set(k, training_saved[k])
		training = false
		save()
		training = true
		for k in live.keys():
			set(k, live[k])
		return
	# Read-modify-write: keep sections other code owns (controls bindings,
	# anything a newer build added) instead of truncating the file.
	var cf := ConfigFile.new()
	cf.load(PATH)
	cf.set_value("audio", "sfx_volume", sfx_volume)
	cf.set_value("audio", "music_volume", music_volume)
	cf.set_value("audio", "music_muted", music_muted)
	cf.set_value("game", "screen_shake", screen_shake)
	cf.set_value("game", "screen_shake_intensity", screen_shake_intensity)
	cf.set_value("video", "fullscreen", fullscreen)
	cf.set_value("game", "map_index", map_index)
	cf.set_value("game", "custom_map_path", custom_map_path)
	cf.set_value("game", "game_mode", game_mode)
	cf.set_value("game", "realistic", realistic)
	cf.set_value("game", "survival", survival)
	cf.set_value("game", "advance", advance)
	cf.set_value("video", "lofi", lofi)
	cf.set_value("video", "lofi_auto_done", lofi_auto_done)
	cf.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cf.set_value("controls", "touch_swap", touch_swap)
	cf.set_value("controls", "touch_btn_pos", touch_btn_pos)
	cf.set_value("video", "show_fps", show_fps)
	cf.set_value("video", "damage_numbers", damage_numbers)
	cf.set_value("video", "vsync", vsync)
	cf.set_value("video", "max_fps", max_fps)
	cf.set_value("game", "pause_on_focus_loss", pause_on_focus_loss)
	cf.set_value("game", "check_updates", check_updates)
	cf.set_value("video", "colorblind", colorblind)
	cf.set_value("game", "last_seen_version", last_seen_version)
	cf.set_value("game", "vehicles", vehicles)
	cf.set_value("game", "bot_chatter", bot_chatter)
	cf.set_value("controls", "camera_lead", camera_lead)
	cf.set_value("game", "help_seen", help_seen)
	cf.set_value("loadout", "primary", spawn_primary)
	cf.set_value("loadout", "secondary", spawn_secondary)
	cf.set_value("game", "blood_intensity", blood_intensity)
	cf.set_value("cosmetics", "head", cos_head)
	cf.set_value("cosmetics", "vest", cos_vest)
	cf.set_value("cosmetics", "chain", cos_chain)
	cf.set_value("cosmetics", "cigar", cos_cigar)
	cf.set_value("cosmetics", "dreadlocks", cos_dreadlocks)
	cf.set_value("cosmetics", "dogtag", cos_dogtag)
	cf.set_value("mods", "gravity", mod_gravity)
	cf.set_value("mods", "jet", mod_jet)
	cf.set_value("mods", "damage", mod_damage)
	cf.set_value("mods", "speed", mod_speed)
	cf.set_value("bots", "count", bot_count)
	cf.set_value("bots", "skill", bot_skill)
	cf.set_value("net", "server_name", server_name)
	cf.set_value("net", "last_join_ip", last_join_ip)
	cf.set_value("net", "host_public", host_public)
	cf.set_value("net", "upnp", upnp)
	cf.set_value("net", "last_join_port", last_join_port)
	cf.set_value("net", "player_name", player_name)
	cf.set_value("net", "name_set", name_set)
	cf.set_value("net", "master_url", master_url)
	cf.save(PATH)


func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# Below ~960x540 the menus and HUD overlap; don't let the window shrink past it.
	if not (OS.has_feature("android") or OS.has_feature("mobile")):
		DisplayServer.window_set_min_size(Vector2i(960, 540))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = max_fps
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
