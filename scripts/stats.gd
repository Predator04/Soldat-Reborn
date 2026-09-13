extends Node
## Stats — persistent per-profile match tallies. Autoload singleton "Stats".
## Tracks kills / deaths / shots / hits / wins / losses / matches to a file
## next to Settings.save's config. Deliberately local-only — ranked would
## need a server (see issue #33 which we've documented, not built).

const PATH := "user://stats.cfg"

var kills := 0
var deaths := 0
var suicides := 0
var shots := 0        # counts primary + secondary trigger pulls
var hits := 0         # increment when our bullet damages an enemy
var wins := 0
var losses := 0
var matches_played := 0
# Per-weapon kill tallies — weapon name (String) -> int kills.
var kills_by_weapon: Dictionary = {}


func _ready() -> void:
	load_stats()


func load_stats() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	kills = int(cf.get_value("totals", "kills", 0))
	deaths = int(cf.get_value("totals", "deaths", 0))
	suicides = int(cf.get_value("totals", "suicides", 0))
	shots = int(cf.get_value("totals", "shots", 0))
	hits = int(cf.get_value("totals", "hits", 0))
	wins = int(cf.get_value("totals", "wins", 0))
	losses = int(cf.get_value("totals", "losses", 0))
	matches_played = int(cf.get_value("totals", "matches_played", 0))
	var raw = cf.get_value("weapons", "kills", {})
	if raw is Dictionary:
		kills_by_weapon = (raw as Dictionary).duplicate(true)


func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("totals", "kills", kills)
	cf.set_value("totals", "deaths", deaths)
	cf.set_value("totals", "suicides", suicides)
	cf.set_value("totals", "shots", shots)
	cf.set_value("totals", "hits", hits)
	cf.set_value("totals", "wins", wins)
	cf.set_value("totals", "losses", losses)
	cf.set_value("totals", "matches_played", matches_played)
	cf.set_value("weapons", "kills", kills_by_weapon)
	cf.save(PATH)


func reset() -> void:
	kills = 0
	deaths = 0
	suicides = 0
	shots = 0
	hits = 0
	wins = 0
	losses = 0
	matches_played = 0
	kills_by_weapon.clear()
	save()


func accuracy() -> float:
	if shots <= 0:
		return 0.0
	return float(hits) / float(shots)


func kd() -> float:
	if deaths <= 0:
		return float(kills)
	return float(kills) / float(deaths)


func record_kill(weapon_name: String) -> void:
	kills += 1
	kills_by_weapon[weapon_name] = int(kills_by_weapon.get(weapon_name, 0)) + 1
	save()


func record_death() -> void:
	deaths += 1
	save()


func record_suicide() -> void:
	suicides += 1
	save()


func record_shot() -> void:
	shots += 1
	# Cheap batch-write: only flush every 20 shots so we don't hammer the file.
	if shots % 20 == 0:
		save()


func record_hit() -> void:
	hits += 1
	# Flush every 5 — hits are rarer than shots.
	if hits % 5 == 0:
		save()


func record_match_end(won: bool) -> void:
	matches_played += 1
	if won:
		wins += 1
	else:
		losses += 1
	save()
