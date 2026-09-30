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

# ── Achievements (v1.24) ─────────────────────────────────────────────────────
signal achievement_unlocked(id: String, title: String, desc: String)

var counters: Dictionary = {}     # headshots, captures, best_streak, modes_won (Array) ...
var unlocked: Dictionary = {}     # id -> unix time
var _streak := 0
var _recent_kills: Array = []     # msec of our last kills (multi-kill)

# id, title, description, how progress is read ([counter, goal])
const ACHIEVEMENTS := [
	["first_blood", "First Blood", "Get your first kill.", ["kills", 1]],
	["soldier", "Soldier", "100 kills.", ["kills", 100]],
	["veteran", "Veteran", "1,000 kills.", ["kills", 1000]],
	["sharpshooter", "Sharpshooter", "25 headshot kills.", ["headshots", 25]],
	["long_shot", "Long Shot", "25 kills with the Barrett.", ["w:Barrett", 25]],
	["rocket_man", "Rocket Man", "25 kills with the LAW or M79.", ["rockets", 25]],
	["grenadier", "Grenadier", "50 grenade kills (frag or cluster).", ["grenades", 50]],
	["blade", "Up Close", "10 knife or chainsaw kills.", ["melee", 10]],
	["roadkill", "Roadkill", "Run over 10 enemies with a buggy.", ["w:Buggy", 10]],
	["tank_ace", "Tank Ace", "25 kills with a tank (shells or treads).", ["w:Tank", 25]],
	["double", "Double Trouble", "Two kills within 3 seconds.", ["best_multi", 2]],
	["massacre", "Massacre", "Four kills within 3 seconds.", ["best_multi", 4]],
	["unstoppable", "Unstoppable", "10 kills without dying.", ["best_streak", 10]],
	["flag_runner", "Flag Runner", "Capture 10 flags.", ["captures", 10]],
	["winner", "Winner", "Win a match.", ["wins", 1]],
	["champion", "Champion", "Win 25 matches.", ["wins", 25]],
	["all_rounder", "All-Rounder", "Win a match in 5 different modes.", ["modes_won", 5]],
	["survivor", "Last One Standing", "Win a match with Survival on.", ["survival_wins", 1]],
	["marathon", "Marathon", "Play 50 matches.", ["matches_played", 50]],
	["recruit", "Recruit", "Finish Training.", ["trained", 1]],
	["online", "Plays Well With Others", "Host or join an online game.", ["online", 1]],
]


# ── Rank (v1.24): XP from kills, captures, wins and finished matches ─────────
signal level_up(level: int)
const XP_KILL := 10
const XP_HEADSHOT := 5
const XP_CAPTURE := 50
const XP_MATCH := 20
const XP_WIN := 80


func xp() -> int:
	return int(counters.get("xp", 0))


## Level from total XP: level n needs 100 * n * (n + 1) / 2 in total
## (100 for level 2, 300 for 3, 600 for 4 ...).
static func level_for(total: int) -> int:
	var n := 1
	while 100 * n * (n + 1) / 2 <= total:
		n += 1
	return n


## [xp into this level, xp this level needs]
func level_progress() -> Array:
	var lv := level_for(xp())
	var start := 100 * (lv - 1) * lv / 2
	return [xp() - start, 100 * lv]


func _add_xp(n: int) -> void:
	var before := level_for(xp())
	counters["xp"] = xp() + n
	var after := level_for(xp())
	if after > before:
		level_up.emit(after)


func counter(key: String) -> int:
	match key:
		"kills": return kills
		"wins": return wins
		"matches_played": return matches_played
		"modes_won": return (counters.get("modes_won", []) as Array).size()
	if key.begins_with("w:"):
		return int(kills_by_weapon.get(key.substr(2), 0))
	return int(counters.get(key, 0))


func achievement_progress(a: Array) -> Array:
	var goal: int = int(a[3][1])
	return [mini(counter(str(a[3][0])), goal), goal]


func _bump(key: String, n := 1) -> void:
	counters[key] = int(counters.get(key, 0)) + n


func _check_achievements() -> void:
	for a in ACHIEVEMENTS:
		var id: String = a[0]
		if unlocked.has(id):
			continue
		var pr := achievement_progress(a)
		if pr[0] >= pr[1]:
			unlocked[id] = int(Time.get_unix_time_from_system())
			_mark()
			achievement_unlocked.emit(id, str(a[1]), str(a[2]))


## One-off events from elsewhere: "trained", "online", "capture".
func record_event(kind: String) -> void:
	match kind:
		"trained", "online":
			counters[kind] = 1
		"capture":
			_bump("captures")
			_add_xp(XP_CAPTURE)
	_mark()
	_check_achievements()


func _ready() -> void:
	load_stats()
	# Older builds tallied "AK-74 (headshot)" separately: fold those into the
	# weapon and count them as headshots.
	for k in kills_by_weapon.keys():
		if str(k).contains("(headshot)"):
			var base := str(k).replace("(headshot)", "").strip_edges()
			var n := int(kills_by_weapon[k])
			kills_by_weapon[base] = int(kills_by_weapon.get(base, 0)) + n
			kills_by_weapon.erase(k)
			if not counters.has("headshots_seeded"):
				_bump("headshots", n)
	counters["headshots_seeded"] = 1
	if not counters.has("xp"):
		counters["xp"] = kills * XP_KILL + int(counters.get("headshots", 0)) * XP_HEADSHOT \
				+ matches_played * XP_MATCH + wins * XP_WIN
	# Category counters started in v1.24: seed them from the per-weapon tallies
	# a long-time player already has.
	for pair in [["rockets", ["LAW", "M79"]], ["grenades", ["Grenade", "Cluster"]], ["melee", ["Knife", "Chainsaw"]]]:
		if not counters.has(pair[0]):
			var n := 0
			for w in pair[1]:
				n += int(kills_by_weapon.get(w, 0))
			counters[pair[0]] = n
	# Achievements already earned by past play unlock quietly (no toast flood).
	for a in ACHIEVEMENTS:
		var pr := achievement_progress(a)
		if not unlocked.has(a[0]) and pr[0] >= pr[1]:
			unlocked[a[0]] = int(Time.get_unix_time_from_system())


# Writing the stats file on every kill / death stalled a frame (worst on
# Windows with antivirus scanning each write) — right when you land a kill.
# Changes are marked dirty and flushed a few seconds later, at match end, and
# when the game closes.
var _dirty := false
var _flush_t := 0.0
const FLUSH_DELAY := 8.0


func _mark() -> void:
	if not _dirty:
		_dirty = true
		_flush_t = FLUSH_DELAY


func _process(delta: float) -> void:
	if _dirty:
		_flush_t -= delta
		if _flush_t <= 0.0:
			save()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE or what == NOTIFICATION_APPLICATION_PAUSED:
		if _dirty:
			save()


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
	var c = cf.get_value("achievements", "counters", {})
	if c is Dictionary:
		counters = (c as Dictionary).duplicate(true)
	var u = cf.get_value("achievements", "unlocked", {})
	if u is Dictionary:
		unlocked = (u as Dictionary).duplicate(true)


func save() -> void:
	_dirty = false
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
	cf.set_value("achievements", "counters", counters)
	cf.set_value("achievements", "unlocked", unlocked)
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
	counters.clear()
	unlocked.clear()
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
	var head := weapon_name.contains("(headshot)")
	var w := weapon_name.replace("(headshot)", "").strip_edges()
	kills_by_weapon[w] = int(kills_by_weapon.get(w, 0)) + 1
	_add_xp(XP_KILL + (XP_HEADSHOT if head else 0))
	if head:
		_bump("headshots")
	if w in ["LAW", "M79"]:
		_bump("rockets")
	elif w in ["Grenade", "Cluster"]:
		_bump("grenades")
	elif w in ["Knife", "Chainsaw"]:
		_bump("melee")
	_streak += 1
	counters["best_streak"] = maxi(int(counters.get("best_streak", 0)), _streak)
	var now := Time.get_ticks_msec()
	_recent_kills = _recent_kills.filter(func(t): return now - int(t) <= 3000)
	_recent_kills.append(now)
	counters["best_multi"] = maxi(int(counters.get("best_multi", 0)), _recent_kills.size())
	_mark()
	_check_achievements()


func record_death() -> void:
	deaths += 1
	_streak = 0
	_recent_kills.clear()
	_mark()


func record_suicide() -> void:
	suicides += 1
	_streak = 0
	_mark()


func record_shot() -> void:
	shots += 1
	# Cheap batch-write: only flush every 20 shots so we don't hammer the file.
	_mark()


func record_hit() -> void:
	hits += 1
	# Flush every 5 — hits are rarer than shots.
	_mark()


func record_match_end(won: bool) -> void:
	matches_played += 1
	_add_xp(XP_MATCH + (XP_WIN if won else 0))
	if won:
		wins += 1
		var modes: Array = counters.get("modes_won", [])
		if not (Settings.game_mode in modes):
			modes.append(Settings.game_mode)
		counters["modes_won"] = modes
		if Settings.survival:
			_bump("survival_wins")
	else:
		losses += 1
	_check_achievements()
	save()
