extends SceneTree
## Player name (gate stage F): Training / online buttons ask for a name first
## (no empty name, no "Player"), and CHANGE NAME on the menu renames.
##   godot --headless -s tools/name_test.gd

var _n := 0
var _st := 0
var _bad: Array = []
var _log: Array = []
var _ran := false
var _saved := []


func _find(n: Node, cls: String) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c.is_class(cls):
			out.append(c)
		out.append_array(_find(c, cls))
	return out


func _process(_d: float) -> bool:
	_n += 1
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _st == 0:
		_saved = [st.player_name, st.name_set]
		st.player_name = "Player"
		st.name_set = false
		change_scene_to_file("res://scenes/menu.tscn")
		_st = 1
		return false
	var m = current_scene
	if m == null or m.get("_menu_root") == null or _n < 10:
		return false
	if _st == 1:
		m._with_name(func() -> void: _ran = true)
		var pr: Control = m._name_prompt_root
		if pr == null:
			return _end("no name prompt before an action")
		var edit: LineEdit = _find(pr, "LineEdit")[0]
		var btns: Array = _find(pr, "Button").filter(func(b): return not (b as Button).flat and (b as Button).text != "CANCEL")
		for b in btns:
			if not b.disabled:
				_bad.append("'%s' enabled with no name" % b.text)
		edit.text = "player"
		edit.text_changed.emit("player")
		for b in btns:
			if not b.disabled:
				_bad.append("'%s' enabled for 'player'" % b.text)
		edit.text_submitted.emit("player")
		if _ran:
			_bad.append("action ran without a name")
		edit.text = "  Ace  "
		edit.text_changed.emit(edit.text)
		(btns[0] as Button).pressed.emit()
		_log.append("named=%s ran=%s" % [st.player_name, str(_ran)])
		if st.player_name != "Ace" or not _ran or not st.name_set:
			_bad.append("save/continue failed")
		# Change it from the menu.
		m._build_name_prompt(Callable(), true)
		var e2: LineEdit = _find(m._name_prompt_root, "LineEdit")[0]
		if e2.text != "Ace":
			_bad.append("change prompt not prefilled")
		e2.text = "Bee"
		e2.text_changed.emit("Bee")
		e2.text_submitted.emit("Bee")
		m._refresh_name_btn()
		_log.append("renamed=%s btn='%s'" % [st.player_name, m._name_btn.text])
		if st.player_name != "Bee" or not str(m._name_btn.text).contains("Bee"):
			_bad.append("rename failed")
		# A named player goes straight through.
		_ran = false
		m._with_name(func() -> void: _ran = true)
		if not _ran:
			_bad.append("named player was asked again")
		return _end("")
	return false


func _end(fail: String) -> bool:
	if fail != "":
		_bad.append(fail)
	var st = root.get_node("Settings")
	st.player_name = _saved[0]
	st.name_set = _saved[1]
	st.save()
	print("NAME-TEST %s %s | %s" % ["ok" if _bad.is_empty() else "FAIL", str(_bad), " ".join(_log)])
	quit()
	return true
