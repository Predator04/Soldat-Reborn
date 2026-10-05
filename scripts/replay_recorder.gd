extends Node
## Match recorder: 15 snapshots a second of every soldier (position, aim,
## pose, weapon, health), projectiles, flags and vehicles, plus kills.
## Saved to user://replays/ (gzip) at the end of each round and when you leave
## the match; the REPLAYS screen plays them back (replay_player.gd).

const MapIO = preload("res://scripts/map_io.gd")
const DIR := "user://replays/"
const HZ := 15.0
const KEEP := 20                 # newest replays kept on disk
const MIN_SECS := 15.0           # shorter matches aren't worth a file
const MAX_FRAMES := int(HZ * 60 * 20)   # 20 minutes per file

var main: Node
var frames: Array = []           # [t, soldiers, shots, flags, vehicles]
var who: Dictionary = {}         # soldier id -> {name, team, color, cos}
var events: Array = []           # [t, "kill", killer, victim, weapon]
var _ids: Dictionary = {}        # player name -> soldier id
var _next_id := 1
var _t := 0.0
var _acc := 0.0
var _started_unix := 0
var saved_paths: Array = []      # for tests


func _ready() -> void:
	_started_unix = int(Time.get_unix_time_from_system())
	main.kill.connect(func(k: String, v: String, w: String, _kt: int, _vt: int) -> void:
		events.append([snappedf(_t, 0.01), "kill", k, v, w]))


func _process(delta: float) -> void:
	_t += delta
	_acc += delta
	if _acc < 1.0 / HZ:
		return
	_acc = 0.0
	if frames.size() >= MAX_FRAMES:
		return
	frames.append(_snapshot())


# One id per player name, so a respawned body (a new node) keeps its id and
# the replay camera can keep following them.
func _sid(n: Node) -> int:
	var key := str(n.get("display_name"))
	if key == "":
		key = "#%d" % n.get_instance_id()
	if not _ids.has(key):
		_ids[key] = _next_id
		_next_id += 1
	return int(_ids[key])


func _snapshot() -> Array:
	var sol: Array = []
	for s in get_tree().get_nodes_in_group("soldier"):
		if not is_instance_valid(s) or not s.has_method("replay_state"):
			continue
		var id := _sid(s)
		var info := {"name": str(s.get("display_name")), "team": int(s.get("team")),
			"color": (s.get("color") as Color).to_html(false), "cos": (s.get("cosmetics") as Dictionary).duplicate()}
		if not who.has(id) or who[id] != info:
			who[id] = info
		var st: Array = s.replay_state()
		st.push_front(id)
		sol.append(st)
	var shots: Array = []
	for b in get_tree().get_nodes_in_group("bullet"):
		if not is_instance_valid(b):
			continue
		var kind := "r" if b.get("grav") != null and b.has_method("_explode") else "b"
		var dir: Vector2 = b.get("direction") if b.get("direction") != null else Vector2.RIGHT
		shots.append([kind, roundi(b.global_position.x), roundi(b.global_position.y), snappedf(dir.angle(), 0.05)])
	for g in get_tree().get_nodes_in_group("grenade"):
		if is_instance_valid(g):
			shots.append(["g", roundi(g.global_position.x), roundi(g.global_position.y), 0.0])
	var fl: Array = []
	for f in main.get("flags"):
		if is_instance_valid(f):
			fl.append([int(f.get_meta("team", 0)), roundi(f.global_position.x), roundi(f.global_position.y)])
	var veh: Array = []
	for v in get_tree().get_nodes_in_group("vehicle"):
		if is_instance_valid(v):
			veh.append([str(v.get("kind")), roundi(v.global_position.x), roundi(v.global_position.y), snappedf(v.global_rotation, 0.02), bool(v.get("alive"))])
	return [snappedf(_t, 0.01), sol, shots, fl, veh]


func header() -> Dictionary:
	var mi: int = int(main.get("cur_map_index"))
	var mname := "Custom"
	var map_json := ""
	if mi >= 0:
		mname = str(main.MAPS[mi].get("name", "?"))
	else:
		map_json = MapIO.map_to_json(main.get("_map"))
		mname = str(main.get("_map").get("name", "Custom"))
	var me := ""
	if main.get("player") != null and is_instance_valid(main.player):
		me = str(main.player.display_name)
	return {"v": 1, "game": str(ProjectSettings.get_setting("application/config/version", "")),
		"when": _started_unix, "map_index": mi, "map": mname, "map_json": map_json,
		"mode": int(Settings.game_mode), "secs": snappedf(_t, 0.1), "me": me, "online": Net.is_networked()}


## Write the replay so far; returns the path ("" if too short or failed).
func save() -> String:
	if _t < MIN_SECS or frames.size() < 10:
		return ""
	DirAccess.make_dir_recursive_absolute(DIR)
	var stamp := Time.get_datetime_string_from_unix_time(_started_unix).replace(":", "-").replace("T", "_")
	var path := DIR + "%s_%s.replay" % [stamp, MapIO.safe_filename(str(header().map))]
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_GZIP)
	if f == null:
		return ""
	f.store_var({"header": header(), "who": who, "events": events, "frames": frames})
	f.close()
	saved_paths.append(path)
	_prune()
	return path


static func list_files() -> Array:
	var out: Array = []
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	for fn in d.get_files():
		if fn.ends_with(".replay"):
			out.append(DIR + fn)
	out.sort()
	out.reverse()
	return out


static func load_file(path: String) -> Dictionary:
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_GZIP)
	if f == null:
		return {}
	var d = f.get_var()
	f.close()
	return d if typeof(d) == TYPE_DICTIONARY and d.has("frames") else {}


static func _prune() -> void:
	var files := list_files()
	for i in range(KEEP, files.size()):
		DirAccess.remove_absolute(files[i])
