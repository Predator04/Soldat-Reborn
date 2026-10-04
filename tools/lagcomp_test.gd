extends SceneTree
## Lag compensation (gate stage F): a remote player's bullet aimed where the
## local player WAS (lag_ms ago) hits; the same bullet without compensation
## misses; compensation never reaches back past the 200 ms cap; a wall in the
## way still blocks.
##   godot --headless -s tools/lagcomp_test.gd

var _n := 0
var _st := 0
var _old: Rect2
var _hp0 := 0.0
var _log: Array = []
var _bad: Array = []
var _saved_bots := 0
var _t := 0


func _process(_d: float) -> bool:
	_n += 1
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _st == 0:
		_saved_bots = st.bot_count
		st.bot_count = 0
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		_st = 1
		return false
	var m = current_scene
	if m == null or m.get("player") == null or not is_instance_valid(m.player):
		return false
	var p = m.player
	var now := Time.get_ticks_msec()
	match _st:
		1:
			if _t == 0:
				_t = now
			# Settled on the ground for a while, so the rewound spot is still.
			if now - _t < 1500 or not p.is_on_floor() or p.velocity.length() > 5.0:
				return false
			p.ceasefire_t = 0.0
			_old = p.hitbox_now()
			p.global_position += Vector2(-300, 0)
			_t = now
			_st = 2
		2:
			# ~100 ms (real time) after moving away: the uncompensated bullet
			# (7 dmg) passes through the empty old spot, the compensated one
			# (20 dmg, 180 ms) hits it.
			if now - _t < 100:
				return false
			p.ceasefire_t = 0.0
			_hp0 = p.health
			_shoot(m, 0, 7.0)
			_shoot(m, 180, 20.0)
			_t = now
			_st = 3
		3:
			if now - _t < 300:
				return false
			var dmg: float = _hp0 - float(p.health)
			_log.append("dmg=%.0f (want 20)" % dmg)
			if absf(dmg - 20.0) > 0.5:
				_bad.append("expected only the compensated bullet to hit, took %.0f" % dmg)
			p.health = 100.0
			_hp0 = p.health
			# Now > 200 ms after the move: even the max rewind finds the new spot.
			_shoot(m, 200, 20.0)
			_t = now
			_st = 4
		4:
			if now - _t < 300:
				return false
			_log.append("stale dmg=%.0f" % (_hp0 - p.health))
			if p.health < _hp0:
				_bad.append("rewound past the cap")
			var B = load("res://scripts/bullet.gd")
			if B.segment_rect_t(Vector2(0, 5), Vector2(20, 5), Rect2(10, 0, 4, 10)) != 0.5:
				_bad.append("segment_rect_t math")
			if B.segment_rect_t(Vector2(0, 20), Vector2(20, 20), Rect2(10, 0, 4, 10)) != -1.0:
				_bad.append("segment_rect_t miss")
			return _end()
	return false


func _shoot(m: Node, lag: int, dmg: float) -> void:
	var b = load("res://scenes/bullet.tscn").instantiate() if ResourceLoader.exists("res://scenes/bullet.tscn") else load("res://scripts/bullet.gd").new()
	var y := _old.get_center().y
	b.global_position = Vector2(_old.position.x - 24, y)
	b.direction = Vector2.RIGHT
	b.speed = 900.0
	b.damage = dmg
	b.team = 99
	b.killer_name = "Ghost"
	b.weapon_name = "AK-74"
	b.lag_ms = lag
	m.add_child(b)


func _end() -> bool:
	root.get_node("Settings").bot_count = _saved_bots
	var ok := _bad.is_empty()
	print("LAGCOMP-TEST %s %s | %s" % ["ok" if ok else "FAIL", str(_bad), " ".join(_log)])
	quit(0 if ok else 1)
	return true
