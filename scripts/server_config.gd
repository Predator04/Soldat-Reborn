extends Node
## ServerConfig — the dedicated server's config file (#317), child "ServerConfig"
## of the Net autoload (Net.server_cfg).
##
## File: plain `key = value` lines (see server.cfg.example). `#` / `;` / `//`
## start a comment line, `[section]` headers are allowed and ignored, values may
## be quoted. Unknown keys and bad values are logged (`SERVERCFG line N: ...`)
## and skipped — the server always starts. Command-line flags given at boot win
## over the file (#264 "later flags win": the file is read first), also on a
## reload.
##
## Where it comes from: `--config <path>` / `--config=<path>`, else `server.cfg`
## beside an exported binary (the standalone server download, #320), else
## `user://server.cfg`. No file = nothing changes (the pre-#317 behaviour).
##
## How keys take effect:
##   boot   — port, register (restart to change)
##   live   — applied at once by `/reloadcfg`
##   match  — applied when the next map / match loads
## Code that reads a configurable number asks `Net.rule(key, default)` (host
## side), which returns the default unless a dedicated server's file set it.

const GameLists = preload("res://scripts/game_lists.gd")

# key -> [type, apply, help]. Types: str, int, float, bool, list, rotation,
# map, mode, register, ids. Ranges live in _check().
const KEYS := {
	# ── server
	"name": ["str", "live", "server name shown in Find Games"],
	"port": ["int", "boot", "UDP port (the query port is port + 1)"],
	"register": ["register", "boot", "list on the master server: true / false / a master URL"],
	"motd": ["str", "live", "message of the day sent to each player who joins (repeat the key for more lines)"],
	"admin_password": ["str", "live", "password for /login <password> (empty = no password login)"],
	"admins": ["ids", "live", "player ids that are admins without a password (a player sees theirs with /myid)"],
	"idle_pause": ["bool", "live", "pause the match while nobody is connected"],
	# ── rotation
	"map": ["map", "boot", "first map when there is no rotation"],
	"mode": ["mode", "match", "game mode for rotation entries that don't name one"],
	"rotation": ["rotation", "live", "map rotation: Map or Map:mode, comma separated"],
	"rotation_random": ["bool", "live", "play the rotation in random order"],
	"next_map_vote": ["bool", "live", "end-of-match vote between the next rotation map and two others"],
	# ── rules
	"time_limit": ["float", "match", "match length in minutes"],
	"score_limit_dm": ["int", "live", "Deathmatch kills to win"],
	"score_limit_tdm": ["int", "live", "Teammatch kills to win"],
	"score_limit_ctf": ["int", "live", "Capture the Flag captures to win"],
	"score_limit_inf": ["int", "live", "Infiltration points to win"],
	"score_limit_htf": ["int", "live", "Hold the Flag points (seconds held) to win"],
	"score_limit_rm": ["int", "live", "Rambomatch kills to win"],
	"score_limit_pm": ["int", "live", "Pointmatch points to win"],
	"score_limit_dom": ["int", "live", "Domination points to win"],
	"respawn_time": ["float", "live", "seconds before a dead soldier respawns"],
	"respawn_time_inf_attackers": ["float", "live", "Infiltration attackers' (red) respawn seconds"],
	"realistic": ["bool", "match", "Realistic sub-mode"],
	"survival": ["bool", "match", "Survival sub-mode"],
	"advance": ["bool", "match", "Advance sub-mode"],
	"friendly_fire": ["bool", "live", "team-mode friendly fire"],
	"bots": ["int", "live", "bot count when fill = 0 (-1 = one per spawn)"],
	"bot_skill": ["int", "live", "bot skill 1-5"],
	"fill": ["int", "live", "keep this many soldiers in the match, bots leave as players join (0 = use bots)"],
	"bonuses": ["int", "match", "power-up crate slots per map (0-3)"],
	"bonus_respawn": ["float", "live", "seconds before a taken power-up crate comes back"],
	"kits": ["bool", "match", "medikits and grenade kits on maps that have them"],
	"kit_respawn": ["float", "live", "seconds before a taken kit comes back"],
	"weapon_bans": ["list", "live", "weapons removed from the match, comma separated"],
	"vehicles": ["bool", "match", "vehicles on maps that have them"],
	"gravity": ["float", "match", "gravity modifier 0.5-2.0"],
	"jet": ["float", "match", "jet refill modifier 0.5-2.0"],
	"damage": ["float", "match", "damage modifier 0.5-2.0"],
	"speed": ["float", "match", "run speed modifier 0.5-1.5"],
	# ── votes
	"vote_map": ["bool", "live", "allow /votemap"],
	"vote_kick": ["bool", "live", "allow /votekick"],
	"vote_time": ["float", "live", "seconds a vote stays open"],
	"vote_cooldown": ["float", "live", "seconds between votes"],
}

const SCORE_KEYS := {0: "score_limit_dm", 1: "score_limit_tdm", 2: "score_limit_ctf",
	3: "score_limit_inf", 4: "score_limit_htf", 5: "score_limit_rm", 6: "score_limit_pm", 7: "score_limit_dom"}
const MODE_ALIASES := {"dm": 0, "tdm": 1, "ctf": 2, "inf": 3, "htf": 4, "rm": 5, "pm": 6,
	"dom": 7, "br": 8, "gg": 9, "bomb": 10, "bd": 10}

var path := ""            # file in use ("" = none)
var values: Dictionary = {}   # key -> parsed value (only keys the file set)
var cli_keys: Dictionary = {} # keys a boot flag set: the file never overrides them
var problems := 0         # bad lines in the last load
var reloads := 0
var _rot_index := -1      # rotation entry being played (-1 = not started)
var _motd_sent: Dictionary = {}   # peer id -> true
var _admins_live: Dictionary = {} # peer id -> true (logged in this session)
var _rot_order: Array = []        # rotation_random: shuffled indices


# ── file lookup + parsing ─────────────────────────────────────────────────
static func find_path(args: Array) -> String:
	for i in args.size():
		var a: String = args[i]
		if a == "--config" and i + 1 < args.size():
			return _abs(String(args[i + 1]))
		if a.begins_with("--config="):
			return _abs(a.substr(len("--config=")))
	if OS.has_feature("template"):
		var beside := OS.get_executable_path().get_base_dir().path_join("server.cfg")
		if FileAccess.file_exists(beside):
			return beside
	if FileAccess.file_exists("user://server.cfg"):
		return "user://server.cfg"
	return ""


## A relative --config path is relative to the shell's directory (PWD) — an
## exported binary does not run from there — else to the binary's folder.
static func _abs(p: String) -> String:
	if p == "" or p.is_absolute_path() or p.begins_with("res://") or p.begins_with("user://"):
		return p
	var pwd := OS.get_environment("PWD")
	if pwd != "" and FileAccess.file_exists(pwd.path_join(p)):
		return pwd.path_join(p)
	if OS.has_feature("template"):
		var beside := OS.get_executable_path().get_base_dir().path_join(p)
		if FileAccess.file_exists(beside):
			return beside
	return p


## Parse the text of a config file. Returns {values, problems: [String]}.
## Pure: no side effects, so tests can feed it strings.
static func parse(text: String) -> Dictionary:
	var out: Dictionary = {}
	var bad: Array = []
	var n := 0
	for raw in text.split("\n"):
		n += 1
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#") or line.begins_with(";") or line.begins_with("//"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			continue
		var eq := line.find("=")
		if eq <= 0:
			bad.append("line %d: not a 'key = value' line: %s" % [n, line.left(60)])
			continue
		var key := line.left(eq).strip_edges().to_lower()
		var val := line.substr(eq + 1).strip_edges()
		if val.length() >= 2 and ((val.begins_with("\"") and val.ends_with("\"")) or (val.begins_with("'") and val.ends_with("'"))):
			val = val.substr(1, val.length() - 2)
		if not KEYS.has(key):
			bad.append("line %d: unknown key '%s', ignored" % [n, key])
			continue
		var r: Array = _convert(key, val)
		if not bool(r[0]):
			bad.append("line %d: bad value for %s: '%s' (%s), keeping the default" % [n, key, val.left(60), str(r[1])])
			continue
		if key == "motd":
			var lines: Array = (out.get("motd", []) as Array).duplicate()
			if str(r[1]) != "":
				lines.append(str(r[1]))
			out["motd"] = lines
		else:
			out[key] = r[1]
	return {"values": out, "problems": bad}


## [ok, value_or_reason]
static func _convert(key: String, v: String) -> Array:
	var t: String = KEYS[key][0]
	match t:
		"str":
			return [true, v.left(200)]
		"int":
			if not v.is_valid_int():
				return [false, "expected a whole number"]
			return _check(key, int(v))
		"float":
			if not v.is_valid_float():
				return [false, "expected a number"]
			return _check(key, float(v))
		"bool":
			var l := v.to_lower()
			if l in ["1", "true", "yes", "on"]:
				return [true, true]
			if l in ["0", "false", "no", "off"]:
				return [true, false]
			return [false, "expected true or false"]
		"list":
			var arr: Array = []
			for w in v.split(",", false):
				var nm := w.strip_edges()
				var hit := ""
				for cand in GameLists.WEAPON_NAMES:
					if String(cand).to_lower() == nm.to_lower():
						hit = String(cand)
				if nm == "":
					continue
				if hit == "":
					return [false, "unknown weapon '%s'" % nm]
				if not arr.has(hit):
					arr.append(hit)
			return [true, arr]
		"ids":
			var ids: Array = []
			for w in v.split(",", false):
				var id := w.strip_edges().to_lower()
				if id == "":
					continue
				if id.length() < 12 or not id.is_valid_hex_number():
					return [false, "a player id is at least 12 hex digits (see /myid)"]
				ids.append(id)
			return [true, ids]
		"map":
			var mi := map_index(v)
			return [true, mi] if mi >= 0 else [false, "unknown map"]
		"mode":
			var mo := mode_index(v)
			return [true, mo] if mo >= 0 else [false, "unknown mode"]
		"register":
			var l2 := v.to_lower()
			if l2 in ["0", "false", "no", "off", ""]:
				return [true, ""]
			if l2 in ["1", "true", "yes", "on"]:
				return [true, "default"]
			if v.begins_with("http://") or v.begins_with("https://"):
				return [true, v]
			return [false, "expected true, false or an http(s) URL"]
		"rotation":
			var rot: Array = []
			for e in v.split(",", false):
				var ent := e.strip_edges()
				if ent == "":
					continue
				var parts := ent.split(":", false)
				var mi2 := map_index(parts[0].strip_edges())
				if mi2 < 0:
					return [false, "unknown map '%s'" % parts[0]]
				var mo2 := -1
				if parts.size() > 1:
					mo2 = mode_index(parts[1].strip_edges())
					if mo2 < 0:
						return [false, "unknown mode '%s'" % parts[1]]
				rot.append([mi2, mo2])
			if rot.is_empty():
				return [false, "no maps listed"]
			return [true, rot]
	return [false, "?"]


static func _check(key: String, v) -> Array:
	var lim := {"port": [1, 65535], "time_limit": [0.5, 120.0], "respawn_time": [0.0, 60.0],
		"respawn_time_inf_attackers": [0.0, 60.0], "bots": [-1, 16], "bot_skill": [1, 5],
		"fill": [0, 16], "bonuses": [0, 3], "bonus_respawn": [1.0, 600.0], "kit_respawn": [1.0, 600.0],
		"gravity": [0.5, 2.0], "jet": [0.5, 2.0], "damage": [0.5, 2.0], "speed": [0.5, 1.5],
		"vote_time": [5.0, 300.0], "vote_cooldown": [0.0, 3600.0]}
	if key.begins_with("score_limit_"):
		lim[key] = [1, 100000]
	if lim.has(key):
		var r: Array = lim[key]
		if v < r[0] or v > r[1]:
			return [false, "must be %s..%s" % [str(r[0]), str(r[1])]]
	return [true, v]


static func map_index(v: String) -> int:
	if v.is_valid_int():
		var i := int(v)
		return i if i >= 0 and i < GameLists.MAP_NAMES.size() else -1
	var needle := v.strip_edges().to_lower()
	for p in ["ctf_", "inf_", "dm_", "htf_"]:
		if needle.begins_with(p):
			needle = needle.substr(p.length())
	for i in GameLists.MAP_NAMES.size():
		if String(GameLists.MAP_NAMES[i]).to_lower() == needle:
			return i
	return -1


static func mode_index(v: String) -> int:
	if v.is_valid_int():
		var i := int(v)
		return i if i >= 0 and i < GameLists.MODE_NAMES.size() else -1
	var needle := v.strip_edges().to_lower()
	for i in GameLists.MODE_NAMES.size():
		if String(GameLists.MODE_NAMES[i]).to_lower() == needle:
			return i
	return int(MODE_ALIASES.get(needle, -1))


# ── loading ───────────────────────────────────────────────────────────────
## Read + parse `p`. Logs every problem. Returns false when the file can't be
## read (values stay as they were).
func load_file(p: String, quiet: bool = false) -> bool:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		_log("SERVERCFG cannot read %s (%s), using defaults" % [p, error_string(FileAccess.get_open_error())], quiet)
		return false
	var res := parse(f.get_as_text())
	f.close()
	path = p
	values = res["values"]
	problems = (res["problems"] as Array).size()
	for msg in res["problems"]:
		_log("SERVERCFG " + str(msg), quiet)
	_log("SERVERCFG loaded %s: %d settings, %d problems" % [ProjectSettings.globalize_path(p), values.size(), problems], quiet)
	return true


var _held: Array = []   # boot log lines held until after "Dedicated server starting"


func _log(line: String, hold: bool) -> void:
	if hold:
		_held.append(line)
	else:
		print(line)


func flush_log() -> void:
	for line in _held:
		print(line)
	_held.clear()


func has(key: String) -> bool:
	return values.has(key) and not cli_keys.has(key)


func get_value(key: String, def = null):
	return values[key] if has(key) else def


## Boot: the values a dedicated launch needs before the CLI loop runs over
## them. `boot` = {port, map_index, mode_index, register_url, fill}; returns it
## updated. Settings-backed keys are applied to Settings / MatchConfig here.
func apply_boot(boot: Dictionary) -> Dictionary:
	if values.is_empty():
		return boot
	if has("port"):
		boot.port = int(values.port)
	if has("register"):
		boot.register_url = Settings.master_url if str(values.register) == "default" else str(values.register)
	if has("fill"):
		boot.fill = int(values.fill)
	if has("mode"):
		boot.mode_index = int(values.mode)
	if has("map"):
		boot.map_index = int(values.map)
	var rot: Array = values.get("rotation", [])
	if not rot.is_empty():
		_rot_index = 0
		if bool(values.get("rotation_random", false)):
			_shuffle_rotation()
		var e: Array = rot[_rot_entry(0)]
		boot.map_index = int(e[0])
		if int(e[1]) >= 0:
			boot.mode_index = int(e[1])
	_apply_settings(true)
	return boot


## Settings / MatchConfig values. `live` = the keys /reloadcfg applies at once
## (boot + reload only, so an admin's /bots or /ff lasts past a map change);
## `match_keys` = the per-map ones (boot + every match start).
func _apply_settings(live: bool, match_keys: bool = true) -> void:
	if live:
		_apply_live()
	if not match_keys:
		return
	if has("realistic"):
		Settings.realistic = bool(values.realistic)
	if has("survival"):
		Settings.survival_pref = bool(values.survival)
	if has("advance"):
		Settings.advance_pref = bool(values.advance)
	if has("vehicles"):
		Settings.vehicles = bool(values.vehicles)
	for k in ["gravity", "jet", "damage", "speed"]:
		if has(k):
			Settings.set("mod_" + k, float(values[k]))


func _apply_live() -> void:
	if has("name"):
		Settings.server_name = str(values.name).strip_edges().left(48)
	if has("weapon_bans"):
		Settings.weapon_bans = (values.weapon_bans as Array).duplicate()
	if has("friendly_fire"):
		MatchConfig.host_friendly_fire = bool(values.friendly_fire)
	if has("bots"):
		Settings.bot_count = int(values.bots)
	if has("bot_skill"):
		Settings.bot_skill = int(values.bot_skill)
	if has("fill"):
		Net.fill_target = int(values.fill)
	if has("idle_pause"):
		Net._idle_enabled = bool(values.idle_pause) and not ("--no-idle" in (OS.get_cmdline_args() + OS.get_cmdline_user_args()))


## A dedicated match (main.tscn) starts loading (first thing in main._ready):
## match-time keys take effect.
func on_match_start(main: Node) -> void:
	if not Net.is_dedicated or values.is_empty():
		return
	_apply_settings(false)
	if has("time_limit") and main.get("round_time") != null:
		var secs := float(values.time_limit) * 60.0
		main.set("round_time", secs)
		main.set("time_left", secs)
	print("SERVERCFG match rules: realistic=%s survival=%s advance=%s time=%ds respawn=%.1fs bots=%d fill=%d ff=%s bans=%d" % [
		str(Settings.realistic), str(Settings.survival_pref), str(Settings.advance_pref),
		int(main.get("round_time")) if main.get("round_time") != null else -1, float(rule("respawn_time", 2.0)),
		int(Settings.bot_count), int(Net.fill_target), str(MatchConfig.host_friendly_fire), (Settings.weapon_bans as Array).size()])


## `/reloadcfg`: read the file again and apply what can change live. Returns a
## short report for the admin.
func reload(main: Node) -> String:
	if path == "":
		return "No config file in use (start the server with --config <file>)."
	var before := values.duplicate(true)
	if not load_file(path):
		return "Could not read %s; nothing changed." % path.get_file()
	reloads += 1
	_apply_settings(true, false)
	var later: Array = []
	var restart: Array = []
	for k in values.keys():
		if cli_keys.has(k) or (before.has(k) and str(before[k]) == str(values[k])):
			continue
		match str(KEYS[k][1]):
			"match":
				later.append(k)
			"boot":
				restart.append(k)
	# Rotation: keep the current position inside the new list.
	var rot: Array = values.get("rotation", [])
	if rot.is_empty():
		_rot_index = -1
	else:
		_rot_index = clampi(_rot_index, 0, rot.size() - 1)
		if bool(values.get("rotation_random", false)) and _rot_order.size() != rot.size():
			_shuffle_rotation()
	if main != null and is_instance_valid(main):
		if main.has_method("_reconcile_bots"):
			main._reconcile_bots()
	MatchConfig.host_broadcast()
	var msg := "Config reloaded (%d settings, %d problems)." % [values.size(), problems]
	if not later.is_empty():
		msg += " Next map: %s." % ", ".join(PackedStringArray(later))
	if not restart.is_empty():
		msg += " Needs a restart: %s." % ", ".join(PackedStringArray(restart))
	print("SERVERCFG reload #%d: %s" % [reloads, msg])
	return msg


# ── rules lookup ──────────────────────────────────────────────────────────
func rule(key: String, def):
	if not has(key):
		return def
	var v = values[key]
	if typeof(def) == TYPE_INT:
		return int(v)
	if typeof(def) == TYPE_FLOAT:
		return float(v)
	return v


func score_limit(mode: int, def: int) -> int:
	return int(rule(str(SCORE_KEYS.get(mode, "")), def)) if SCORE_KEYS.has(mode) else def


# ── rotation ──────────────────────────────────────────────────────────────
func has_rotation() -> bool:
	return Net.is_dedicated and not (values.get("rotation", []) as Array).is_empty()


func _shuffle_rotation() -> void:
	var rot: Array = values.get("rotation", [])
	_rot_order = range(rot.size())
	_rot_order.shuffle()


func _rot_entry(i: int) -> int:
	var rot: Array = values.get("rotation", [])
	if rot.is_empty():
		return -1
	i = posmod(i, rot.size())
	if bool(values.get("rotation_random", false)) and _rot_order.size() == rot.size():
		return int(_rot_order[i])
	return i


## The next rotation entry as [map_index, mode_index] (mode = the current one
## when the entry names none and no `mode` key is set).
func peek_next(cur_mode: int) -> Array:
	var rot: Array = values.get("rotation", [])
	var e: Array = rot[_rot_entry(_rot_index + 1)]
	var mo: int = int(e[1])
	if mo < 0:
		mo = int(values.get("mode", cur_mode))
	return [int(e[0]), mo]


func advance_rotation() -> void:
	var rot: Array = values.get("rotation", [])
	if rot.is_empty():
		return
	_rot_index += 1
	if _rot_index >= rot.size():
		_rot_index = 0
		if bool(values.get("rotation_random", false)):
			_shuffle_rotation()


## Other maps for the end-of-match vote: rotation maps first, then any.
func vote_extras(exclude: Array, n: int, map_count: int) -> Array:
	var out: Array = []
	var pool: Array = []
	for e in values.get("rotation", []):
		if not exclude.has(int(e[0])) and not pool.has(int(e[0])) and int(e[0]) < map_count:
			pool.append(int(e[0]))
	pool.shuffle()
	for m in pool:
		if out.size() < n:
			out.append(m)
	if out.size() < n:
		var rest: Array = []
		for i in map_count:
			if not exclude.has(i) and not out.has(i):
				rest.append(i)
		rest.shuffle()
		for m in rest:
			if out.size() < n:
				out.append(m)
	return out


# ── players: MOTD, admins ─────────────────────────────────────────────────
func motd_lines() -> Array:
	return values.get("motd", []) if has("motd") else []


func on_peer_ready(main: Node, pid: int) -> void:
	if _motd_sent.has(pid):
		return
	_motd_sent[pid] = true
	for line in motd_lines():
		tell(main, pid, str(line))


func on_peer_left(pid: int) -> void:
	_motd_sent.erase(pid)
	_admins_live.erase(pid)


func is_admin(pid: int) -> bool:
	if _admins_live.has(pid):
		return true
	var id := str(Net.peer_profiles.get(pid, ""))
	if id == "":
		return false
	for a in values.get("admins", []):
		if id.begins_with(str(a)):
			return true
	return false


## /login <password>. Returns the reply text.
func login(pid: int, pw: String) -> String:
	var want := str(values.get("admin_password", ""))
	if want == "":
		return "Password login is off on this server."
	if pw != want:
		print("SERVERCFG admin login failed (peer %d)" % pid)
		return "Wrong admin password."
	_admins_live[pid] = true
	print("SERVERCFG admin login (peer %d)" % pid)
	return "You are now an admin on this server."


## One chat line to one player (host -> client).
static func tell(main: Node, pid: int, text: String) -> void:
	if main == null or not is_instance_valid(main) or main.multiplayer.multiplayer_peer == null:
		return
	if not main.multiplayer.get_peers().has(pid):
		return
	main.rpc_id(pid, "net_chat", "SERVER", text.left(200), "global", -1)
