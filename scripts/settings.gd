extends Node
## Settings — persistent user preferences (autoload singleton "Settings").

const PATH := "user://settings.cfg"

var sfx_volume := 1.0          # 0.0 = muted, 1.0 = full
var screen_shake := true
var fullscreen := false
var map_index := 0             # which map layout the next game loads

# Game mode: 0 = Deathmatch (default), 1 = Teammatch, 2 = CTF.
const MODE_DM := 0
const MODE_TDM := 1
const MODE_CTF := 2
var game_mode := MODE_DM

# Convenience: DM is FFA (friendly-fire on), teams disable friendly damage.
func friendly_fire_on() -> bool:
	return game_mode == MODE_DM


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


func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "sfx_volume", sfx_volume)
	cf.set_value("game", "screen_shake", screen_shake)
	cf.set_value("video", "fullscreen", fullscreen)
	cf.set_value("game", "map_index", map_index)
	cf.set_value("game", "game_mode", game_mode)
	cf.save(PATH)


func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
