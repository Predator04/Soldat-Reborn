extends SceneTree
## Labels / explanations check (gate stage F).
##   godot --headless --fixed-fps 60 -s tools/label_test.gd
## Every mode, weapon and pickup has player-facing text; the win numbers in
## that text match main.gd; a match opens with the mode banner; crates carry a
## name tag; picking up a power-up / kit explains it on the HUD.

const GI = preload("res://scripts/game_info.gd")

var _t := 0.0
var _phase := 0
var _bad: Array = []


func _check_static() -> void:
	var menu_modes: Array = (load("res://scripts/menu.gd") as GDScript).get_script_constant_map()["MODE_NAMES"]
	if GI.MODES.size() != menu_modes.size():
		_bad.append("mode count %d vs menu %d" % [GI.MODES.size(), menu_modes.size()])
	var M: Dictionary = (load("res://scripts/main.gd") as GDScript).get_script_constant_map()
	var wants := {0: M.SCORE_TO_WIN, 1: M.SCORE_TO_WIN, 2: M.CTF_SCORE_TO_WIN, 3: M.INF_SCORE_TO_WIN,
		4: M.HTF_SCORE_TO_WIN, 6: M.PM_SCORE_TO_WIN, 7: M.DOM_SCORE_TO_WIN}
	for i in wants:
		if not GI.mode_goal(i).contains(str(wants[i])):
			_bad.append("mode %d text lacks %s" % [i, str(wants[i])])
	var B: Dictionary = (load("res://scripts/bonus_pickup.gd") as GDScript).get_script_constant_map()
	for k in B.KINDS + B.KIT_KINDS:
		if GI.item_desc(k) == "":
			_bad.append("no text for item " + k)
	var P = current_scene.get("player")
	for w in P.weapons + P.secondary:
		if GI.weapon_desc(str(w["name"])) == "":
			_bad.append("no text for weapon " + str(w["name"]))


func _process(d: float) -> bool:
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _phase == 0:
		st.set("custom_map_path", ""); st.set("map_index", 5); st.set("game_mode", 2); st.set("bot_count", 0)
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		_phase = 1
		return false
	var m = current_scene
	if m == null or m.get("MAPS") == null or m.get("hud") == null:
		return false
	_t += d
	var p = m.get("player")
	if _t < 1.0 or p == null or not is_instance_valid(p):
		return false
	var hud = m.hud
	if _phase == 1:
		_check_static()
		if not (hud.lbl_mode_banner.visible and str(hud.lbl_mode_banner.text).contains("CAPTURE THE FLAG")):
			_bad.append("no mode banner")
		var tagged := 0
		var boxes := 0
		for n in m.get_children():
			if n is Area2D and n.get("bonus_kind") != null:
				boxes += 1
				if n.get_node_or_null("ItemLabel") != null:
					tagged += 1
		if boxes == 0 or tagged != boxes:
			_bad.append("crate tags %d/%d" % [tagged, boxes])
		p.apply_bonus("vest", 5.0)
		_phase = 2
		return false
	if _phase == 2:
		if not (hud.lbl_toast.visible and str(hud.lbl_toast.text).contains("half damage")):
			_bad.append("no vest toast: '%s'" % str(hud.lbl_toast.text))
		p.set("health", 40.0)
		p.call("_apply_kit_local", "medkit")
		if not str(hud.lbl_toast.text).contains("MEDIKIT"):
			_bad.append("no medikit toast")
		print("LABEL-TEST %s %s" % ["ok" if _bad.is_empty() else "FAIL", str(_bad)])
		quit()
		return true
	return false
