extends RefCounted
## NamePrompt — the first-launch / rename dialog, extracted from menu.gd
## (#258 batch 1). All functions take the menu node (`m`) so the dialog can
## layer over it exactly as it did inline; menu.gd keeps thin wrappers so
## every existing call site is untouched.


## A real, saved name (used in kill feed, scoreboard, multiplayer).
static func has_real_name() -> bool:
	var n := Settings.player_name.strip_edges()
	return Settings.name_set and n != "" and n != "Player"


## Name prompt. First launch: pick a name, then Training or the menu (no
## skip). Later: CHANGE NAME on the menu, or any Training / online button
## while the name is still the default, opens it with `then` run after
## saving.
static func build(m: Node, then: Callable = Callable(), changing := false) -> void:
	var root := PanelContainer.new()
	root.add_theme_stylebox_override("panel", UITheme.panel_style())
	root.set_anchors_preset(Control.PRESET_CENTER, true)
	root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.grow_vertical = Control.GROW_DIRECTION_BOTH
	m.add_child(root)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(440, 0)
	root.add_child(box)
	box.add_child(UITheme.make_screen_title("YOUR NAME" if changing else "WELCOME, SOLDIER"))
	var lbl := Label.new()
	lbl.text = "What should we call you? It shows in the kill feed, the scoreboard and online."
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.style_body(lbl)
	box.add_child(lbl)
	var edit := LineEdit.new()
	edit.max_length = 24
	edit.placeholder_text = "Type your name"
	edit.text = Settings.player_name if has_real_name() else ""
	edit.custom_minimum_size = Vector2(0, 38)
	UITheme.style_lineedit(edit)
	box.add_child(edit)
	# Optional clan tag, shown as "«TAG» Name".
	var tag_edit := LineEdit.new()
	tag_edit.max_length = 4
	tag_edit.placeholder_text = TranslationServer.translate("Clan tag (optional, up to 4 letters)")
	tag_edit.text = Settings.clan_tag
	tag_edit.custom_minimum_size = Vector2(0, 34)
	UITheme.style_lineedit(tag_edit)
	box.add_child(tag_edit)
	var hint := Label.new()
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)
	box.add_child(hint)
	var buttons: Array = []
	var first := not changing and then.is_null()
	var train: Button = null
	if first:
		train = m._make_button("START WITH TRAINING", true)
		box.add_child(train)
		buttons.append(train)
	var go: Button = m._make_button("TO THE MENU" if first else ("SAVE" if then.is_null() else "SAVE AND CONTINUE"), not first)
	box.add_child(go)
	buttons.append(go)
	var cancel: Button = null
	if not first:
		cancel = m._make_button("CANCEL")
		box.add_child(cancel)
	m._menu_root.visible = false
	var valid := func(t: String) -> bool:
		var c := t.strip_edges()
		return c != "" and c.to_lower() != "player"
	var refresh := func(t: String) -> void:
		var ok: bool = valid.call(t)
		for b in buttons:
			(b as Button).disabled = not ok
		hint.text = "" if ok else ("Pick something other than \"Player\"." if t.strip_edges().to_lower() == "player" else "Type a name to continue.")
	edit.text_changed.connect(refresh)
	refresh.call(edit.text)
	var close := func() -> void:
		root.queue_free()
		m._menu_root.visible = true
		m._refresh_name_btn()
		UITheme.safe_grab_focus_deferred(m._menu_first_focus)
	var finish := func(after: Callable) -> void:
		if not valid.call(edit.text):
			refresh.call(edit.text)
			return
		Settings.player_name = edit.text.strip_edges().left(24)
		Settings.clan_tag = Settings.clean_tag(tag_edit.text)
		Settings.name_set = true
		Settings.save()
		close.call()
		if not after.is_null():
			after.call()
	go.pressed.connect(func() -> void: finish.call(then))
	if train != null:
		train.pressed.connect(func() -> void: finish.call(m.start_training_match))
	edit.text_submitted.connect(func(_t: String) -> void: finish.call(then))
	if cancel != null:
		cancel.pressed.connect(close)
	m._name_prompt_root = root
	UITheme.safe_grab_focus_deferred(edit)


## The CHANGE NAME chip in the top-right corner of the main list.
static func refresh_btn_text(m: Node) -> void:
	var btn: Button = m._name_btn
	if btn != null:
		var t := "  %s  ·  LV %d  ·  %s  " % [Settings.display_name() if has_real_name() else TranslationServer.translate("No name yet"), Stats.level_for(Stats.xp()), TranslationServer.translate("CHANGE NAME")]
		if btn.text != t:
			btn.text = t
