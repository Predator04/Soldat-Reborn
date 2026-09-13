extends Node
## Settings — persistent user preferences (autoload singleton "Settings").

const PATH := "user://settings.cfg"
const ControlsMap = preload("res://scripts/controls_map.gd")

var sfx_volume := 1.0          # 0.0 = muted, 1.0 = full
var screen_shake := true
var fullscreen := false
var map_index := 0             # which map layout the next game loads
var custom_map_path := ""      # if non-empty, main.gd loads this JSON map (issue #31)
var lofi := false              # low-end mode: no particles, no gib meshes, no glow

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

# Convenience: DM / Rambo / Battle Royale are FFA (friendly-fire on), teams disable friendly damage.
func friendly_fire_on() -> bool:
	return game_mode == MODE_DM or game_mode == MODE_RM or game_mode == MODE_BR


func is_team_mode() -> bool:
	return game_mode == MODE_TDM or game_mode == MODE_CTF or game_mode == MODE_INF \
		or game_mode == MODE_HTF or game_mode == MODE_PM or game_mode == MODE_DOM


func _ready() -> void:
	load_settings()
	# Apply persisted key rebinds over the InputMap defaults baked into project.godot.
	ControlsMap.load_and_apply()


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	sfx_volume = float(cf.get_value("audio", "sfx_volume", 1.0))
	screen_shake = bool(cf.get_value("game", "screen_shake", true))
	fullscreen = bool(cf.get_value("video", "fullscreen", false))
	map_index = int(cf.get_value("game", "map_index", 0))
	custom_map_path = str(cf.get_value("game", "custom_map_path", ""))
	game_mode = int(cf.get_value("game", "game_mode", MODE_DM))
	realistic = bool(cf.get_value("game", "realistic", false))
	survival = bool(cf.get_value("game", "survival", false))
	advance = bool(cf.get_value("game", "advance", false))
	lofi = bool(cf.get_value("video", "lofi", false))
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


func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "sfx_volume", sfx_volume)
	cf.set_value("game", "screen_shake", screen_shake)
	cf.set_value("video", "fullscreen", fullscreen)
	cf.set_value("game", "map_index", map_index)
	cf.set_value("game", "custom_map_path", custom_map_path)
	cf.set_value("game", "game_mode", game_mode)
	cf.set_value("game", "realistic", realistic)
	cf.set_value("game", "survival", survival)
	cf.set_value("game", "advance", advance)
	cf.set_value("video", "lofi", lofi)
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
	cf.save(PATH)


func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
