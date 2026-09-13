extends Node
## Settings — persistent user preferences (autoload singleton "Settings").

const PATH := "user://settings.cfg"

var sfx_volume := 1.0          # 0.0 = muted, 1.0 = full
var screen_shake := true
var fullscreen := false
var map_index := 0             # which map layout the next game loads

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

# Convenience: DM / Rambo / Battle Royale are FFA (friendly-fire on), teams disable friendly damage.
func friendly_fire_on() -> bool:
	return game_mode == MODE_DM or game_mode == MODE_RM or game_mode == MODE_BR


func is_team_mode() -> bool:
	return game_mode == MODE_TDM or game_mode == MODE_CTF or game_mode == MODE_INF \
		or game_mode == MODE_HTF or game_mode == MODE_PM or game_mode == MODE_DOM


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	sfx_volume = float(cf.get_value("audio", "sfx_volume", 1.0))
	screen_shake = bool(cf.get_value("game", "screen_shake", true))
	fullscreen = bool(cf.get_value("video", "fullscreen", false))
	map_index = int(cf.get_value("game", "map_index", 0))
	game_mode = int(cf.get_value("game", "game_mode", MODE_DM))
	realistic = bool(cf.get_value("game", "realistic", false))
	survival = bool(cf.get_value("game", "survival", false))
	advance = bool(cf.get_value("game", "advance", false))


func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "sfx_volume", sfx_volume)
	cf.set_value("game", "screen_shake", screen_shake)
	cf.set_value("video", "fullscreen", fullscreen)
	cf.set_value("game", "map_index", map_index)
	cf.set_value("game", "game_mode", game_mode)
	cf.set_value("game", "realistic", realistic)
	cf.set_value("game", "survival", survival)
	cf.set_value("game", "advance", advance)
	cf.save(PATH)


func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
