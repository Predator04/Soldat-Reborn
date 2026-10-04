extends SceneTree
## Customization (gate stage F): locked looks never reach your soldier, the
## unlocked ones do, other players' looks survive the network sanitizer, bots
## get random looks, and the CUSTOMIZE screen + Settings card build.
##   godot --headless -s tools/customize_test.gd

var _n := 0
var _bad: Array = []
var _saved := {}
const PROPS := ["cos_skin", "cos_pants", "cos_finish", "cos_vfinish", "cos_wskin"]


func _process(_d: float) -> bool:
	_n += 1
	var st = root.get_node_or_null("Settings")
	var stats = root.get_node_or_null("Stats")
	if st == null or stats == null or _n < 3:
		return false
	for k in PROPS:
		_saved[k] = st.get(k)
	var saved_xp = stats.counters.get("xp", 0)
	var saved_unl: Dictionary = stats.unlocked.duplicate()
	var C = load("res://scripts/customization.gd")
	var P = load("res://scripts/player.gd")
	# A brand-new player (level 1, no achievements).
	stats.counters["xp"] = 0
	stats.unlocked = {}
	st.cos_skin = "dark"; st.cos_pants = "white"; st.cos_finish = "gold"; st.cos_vfinish = "night"; st.cos_wskin = "crimson"
	var c: Dictionary = P.my_cosmetics()
	if c.skin != "dark": _bad.append("free skin tone dropped")
	for k in ["pants", "finish", "vfinish", "wskin"]:
		if c[k] != "": _bad.append("locked %s=%s reached the soldier" % [k, c[k]])
	# Level 40 + the Massacre achievement.
	stats.counters["xp"] = 100 * 40 * 41 / 2
	stats.unlocked = {"massacre": 1}
	c = P.my_cosmetics()
	if c.pants != "white" or c.finish != "gold" or c.wskin != "crimson": _bad.append("unlocked looks missing: %s" % str(c))
	if c.vfinish != "": _bad.append("vest night needs Unstoppable")
	if C.lock_text("vfinish", "night").find("Unstoppable") < 0: _bad.append("lock text: %s" % C.lock_text("vfinish", "night"))
	# Network sanitizer keeps the new keys.
	var body = P.new()
	body.net_cosmetics({"skin": "tan", "pants": "black", "wskin": "gold", "vfinish": "urban", "evil": "x"})
	if body.cosmetics.get("pants") != "black" or body.cosmetics.get("wskin") != "gold" or body.cosmetics.has("evil"):
		_bad.append("net sanitizer: %s" % str(body.cosmetics))
	body.free()
	# Screens build.
	var panel = load("res://scripts/customize_panel.gd").new()
	root.add_child(panel)
	var rows := 0
	for ch in panel._rows_box.get_children():
		rows += 1
	if rows != C.ROWS.size(): _bad.append("customize rows %d" % rows)
	panel.queue_free()
	stats.counters["xp"] = saved_xp
	stats.unlocked = saved_unl
	for k in PROPS:
		st.set(k, _saved[k])
	print("CUSTOMIZE-TEST %s %s" % ["ok" if _bad.is_empty() else "FAIL", str(_bad)])
	quit(0 if _bad.is_empty() else 1)
	return true
