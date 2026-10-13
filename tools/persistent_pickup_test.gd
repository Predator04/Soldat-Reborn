extends SceneTree
## #241/#254 verification: map-placed weapon pickups persist past the old
## 20 s life, regenerate in place after being grabbed, drop their collision
## layer while regenerating, and re-arm the thrower's drop gate on re-grant.
##   godot --headless -s tools/persistent_pickup_test.gd
## The grab happens early — a pickup asleep for ~20 s never re-evaluates a
## teleported overlap (Godot kinematic-vs-sleeping quirk; real players run
## over it while it's awake), so persistence is checked by existence after.

const TIMEOUT := 45.0

var _t := 0.0
var _phase := 0
var _bad: Array = []
var _log: Array = []
var _main = null
var _pickup = null
var _player = null


func _process(delta: float) -> bool:
	_t += delta
	if _t > TIMEOUT:
		return _end("timeout phase=%d" % _phase)
	match _phase:
		0:
			var MapIO = load("res://scripts/map_io.gd")
			var m := {"name": "qa_pp", "platforms": [], "player_spawn": Vector2(400, 1780),
				"bot_spawns": [Vector2(700, 1780)],
				"weapon_pickups": [{"pos": Vector2(500, 1780), "weapon": "AK-74"}]}
			get_root().get_node("Settings").set("custom_map_path", MapIO.save_to_file("qa_pp", m))
			get_root().get_node("Settings").set("game_mode", 0)
			get_root().get_node("Settings").set("bot_count", 0)
			get_root().get_node("Settings").set("vehicles", false)
			get_root().get_node("Net").set_singleplayer()
			change_scene_to_file("res://scenes/main.tscn")
			_phase = 1
			return false
		1:
			_main = current_scene
			if _main == null or _main.get("MAPS") == null:
				return false
			_player = _main.get("player")
			if _player == null or not is_instance_valid(_player):
				return false
			for wp in get_nodes_in_group("weapon_pickup"):
				_pickup = wp
			if _pickup == null:
				return _end("no map weapon pickup spawned")
			if not bool(_pickup.get("persistent")):
				_bad.append("host pickup not persistent")
			_log.append("found slot life=%s" % str(_pickup.get("_life")))
			_phase = 2
			_t = 0.0
			return false
		2:
			# Grab it while it's still awake from landing.
			if _t < 1.0:
				return false
			_player.global_position = (_pickup as Node2D).global_position + Vector2(0, -4)
			_player.set("velocity", Vector2(0, 40))
			_phase = 3
			_t = 0.0
			return false
		3:
			# Grabbed? The slot should be inactive + hidden + non-solid.
			if bool(_pickup.get("active")) and _t > 2.0:
				return _end("pickup not grabbed by overlapping it")
			if not bool(_pickup.get("active")):
				if _pickup.visible:
					_bad.append("regenerating slot still visible")
				if (_pickup as CollisionObject2D).collision_layer != 0:
					_bad.append("regenerating slot still solid")
				_log.append("regen started")
				_phase = 4
				_t = 0.0
			return false
		4:
			# ~8 s later it must be back, visible and solid again.
			if _t < 9.0:
				return false
			if not bool(_pickup.get("active")):
				return _end("slot did not regenerate after 8 s")
			if not _pickup.visible:
				_bad.append("regenerated slot invisible")
			if (_pickup as CollisionObject2D).collision_layer == 0:
				_bad.append("regenerated slot non-solid")
			_log.append("regen ok layer=%d" % (_pickup as CollisionObject2D).collision_layer)
			# The grabbed weapon re-armed the drop gate (#254).
			var dt = _player.get("_drop_times")
			if dt is Dictionary and dt.has("AK-74"):
				_bad.append("drop gate not cleared on re-grant")
			_phase = 5
			_t = 0.0
			return false
		5:
			# Past 20 s from spawn (old lifetime) the slot must still exist.
			if _t < 24.0:
				return false
			if not is_instance_valid(_pickup):
				return _end("map pickup despawned (old 20 s life regression)")
			if bool(_pickup.get("persistent")) == false:
				_bad.append("pickup lost persistent flag")
			_log.append("alive 24s+ after regen ok")
			return _end("")
	return false


func _end(fail: String) -> bool:
	if fail != "":
		_bad.append(fail)
	print("PPICKUP-TEST %s %s | %s" % ["ok" if _bad.is_empty() else "FAIL", str(_bad), " ".join(_log)])
	quit()
	return true
