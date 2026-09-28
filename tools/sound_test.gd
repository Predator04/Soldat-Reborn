extends SceneTree
## Sound wiring check (gate stage F).
##   godot --headless --fixed-fps 60 -s tools/sound_test.gd
## Runs a bot deathmatch and makes sure every family of world sound fires:
## gunfire, footsteps, jumps/landings, ricochets, deaths, the rain bed, and that every
## requested sample actually exists on disk.

const FAMILIES := {
	"gunfire": ["-fire", "dist-gun", "flamer", "knife", "chainsaw", "law-start"],
	"footsteps": ["step", "crouch-move"],
	"jump/land": ["jump", "fall", "roll"],
	"ricochet": ["ric"],
	"death": ["playerdeath", "death"],
	"weather": ["sfx_rain"],
}

var _t := 0.0
var _phase := 0


func _process(d: float) -> bool:
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _phase == 0:
		st.set("custom_map_path", ""); st.set("map_index", 5); st.set("game_mode", 0)  # 5 = Aftermath (rain)
		st.set("bot_count", 7); st.set("bot_skill", 2)
		st.set("sfx_volume", 0.8)
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		_phase = 1
		return false
	var m = current_scene
	if m == null or m.get("MAPS") == null:
		return false
	_t += d
	var sfx = root.get_node("Sfx")
	var counts: Dictionary = sfx.get("play_counts")
	var have := {}
	for fam in FAMILIES:
		for k in counts:
			for pat in FAMILIES[fam]:
				if str(k).begins_with(pat) or str(k).ends_with(pat):
					have[fam] = int(have.get(fam, 0)) + int(counts[k])
	if have.size() == FAMILIES.size() or _t > 75.0:
		var missing: Array = []
		for k in counts:
			if not ResourceLoader.exists("res://assets/sfx/%s.wav" % k):
				missing.append(k)
		var parts: Array = []
		for fam in FAMILIES:
			parts.append("%s=%d" % [fam, int(have.get(fam, 0))])
		var ok: bool = have.size() == FAMILIES.size() and missing.is_empty()
		print("SOUND-TEST %s %s t=%.0fs missing=%s" % ["ok" if ok else "FAIL", " ".join(parts), _t, str(missing)])
		quit()
		return true
	return false
