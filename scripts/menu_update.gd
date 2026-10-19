extends RefCounted
## MenuUpdate — the update button, update panel and WHAT'S NEW dialog,
## extracted from menu.gd (#258 batch 1). Functions take the menu node (`m`)
## for layering over it; menu.gd keeps thin wrappers so existing call sites
## are untouched. scripts/updater.gd itself lives on the tree root so a
## download survives going into a match.

const Updater = preload("res://scripts/updater.gd")
const UITheme = preload("res://scripts/ui_theme.gd")
const UIBack = preload("res://scripts/ui_back.gd")


static func updater(tree: SceneTree) -> Node:
	var u := tree.root.get_node_or_null("Updater")
	if u == null:
		u = Updater.new()
		u.name = "Updater"
		tree.root.add_child.call_deferred(u)
	return u


static func build_button(m: Node) -> void:
	m._upd_btn = Button.new()
	# #272: a quiet chip (the primary ember fill is for the screen's main
	# action); refresh_ui lights the text when an update is waiting.
	UITheme.style_button(m._upd_btn, 15, false)
	m._upd_btn.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)
	m._upd_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	m._upd_btn.offset_top = 16
	m._upd_btn.offset_left = 16
	m._upd_btn.custom_minimum_size = Vector2(0, 38)
	m._upd_btn.visible = false
	m._upd_btn.pressed.connect(m._on_update_pressed)
	m.add_child(m._upd_btn)
	var u := updater(m.get_tree())
	u.state_changed.connect(m._refresh_update_ui)
	m._refresh_update_ui.call_deferred()
	var forced := str(OS.get_cmdline_user_args()).contains("--update-url=")
	if Settings.check_updates and DisplayServer.get_name() != "headless" and (forced or not OS.has_feature("editor")) \
			and not Net.is_dedicated and str(u.get("state")) == "idle":
		u.check.call_deferred()


static func refresh_ui(m: Node) -> void:
	var btn: Button = m._upd_btn
	if btn == null or not m.is_inside_tree():
		return
	var u := updater(m.get_tree())
	var st := str(u.get("state"))
	var ver := Updater.current_version()
	btn.disabled = false
	btn.tooltip_text = "Checks GitHub for a newer version of the game."
	btn.add_theme_color_override("font_color", UITheme.COL_ACCENT_HI if st == "available" or st == "ready" else UITheme.COL_TEXT_DIM)
	match st:
		"available":
			btn.text = "  %s v%s  " % [TranslationServer.translate("UPDATE AVAILABLE:"), str(u.get("latest"))]
		"downloading":
			btn.text = "  %s %d%%  " % [TranslationServer.translate("DOWNLOADING UPDATE"), int(float(u.get("progress")) * 100.0)]
			btn.disabled = true
		"ready":
			btn.text = "  %s v%s  " % [TranslationServer.translate("RESTART TO UPDATE TO"), str(u.get("latest"))]
		"checking":
			btn.text = "  v%s · %s  " % [ver, TranslationServer.translate("CHECKING FOR UPDATES...")]
			btn.disabled = true
		"none":
			btn.text = "  v%s · %s  " % [ver, TranslationServer.translate("UP TO DATE")]
		"failed":
			if str(u.get("latest")) != "":
				btn.text = "  UPDATE FAILED · RETRY  "
			else:
				btn.text = "  v%s · %s  " % [ver, TranslationServer.translate("CHECK FOR UPDATES")]
			btn.tooltip_text = str(u.get("error"))
		_:
			btn.text = "  v%s · %s  " % [ver, TranslationServer.translate("CHECK FOR UPDATES")]
	# Always shown: the current version, and one click to check again.
	btn.visible = true


static func on_pressed(m: Node) -> void:
	var u := updater(m.get_tree())
	var st := str(u.get("state"))
	if st == "ready":
		u.apply_and_restart()
		return
	if st == "failed" and str(u.get("latest")) != "":
		u.start()
		return
	if st in ["idle", "none", "failed"]:
		u.check()
		return
	if m._upd_panel != null:
		m._upd_panel.queue_free()
	m._upd_panel = PanelContainer.new()
	m._upd_panel.add_theme_stylebox_override("panel", UITheme.panel_style())
	m._upd_panel.set_anchors_preset(Control.PRESET_CENTER, true)
	m._upd_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	m._upd_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	m.add_child(m._upd_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(560, 0)
	m._upd_panel.add_child(box)
	box.add_child(UITheme.make_screen_title("UPDATE TO v%s" % str(u.get("latest"))))
	var sub := Label.new()
	sub.text = "You have v%s." % Updater.current_version()
	UITheme.style_body(sub)
	box.add_child(sub)
	var notes := RichTextLabel.new()
	notes.bbcode_enabled = true
	var txt := str(u.get("notes"))
	notes.text = md_to_bb(txt.left(2400)) + ("..." if txt.length() > 2400 else "")
	notes.custom_minimum_size = Vector2(540, 260)
	notes.add_theme_font_size_override("normal_font_size", 13)
	notes.add_theme_color_override("default_color", UITheme.COL_TEXT)
	box.add_child(notes)
	var how := Label.new()
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.add_theme_font_size_override("font_size", 13)
	how.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)
	how.text = "The new version downloads in the background (you can keep playing). Then press RESTART TO UPDATE: the game closes, swaps itself and starts again. Your settings, stats and maps are kept." \
			if Updater.can_self_update() else "This opens the download in your browser. Install the downloaded file to update; your settings, stats and maps are kept."
	box.add_child(how)
	var go: Button = m._make_button("UPDATE NOW" if Updater.can_self_update() else "DOWNLOAD", true)
	go.pressed.connect(func() -> void:
		m._upd_panel.queue_free()
		m._upd_panel = null
		m._menu_root.visible = true
		u.start())
	box.add_child(go)
	var later: Button = m._make_button("LATER")
	later.pressed.connect(func() -> void:
		m._upd_panel.queue_free()
		m._upd_panel = null
		m._menu_root.visible = true)
	box.add_child(later)
	UIBack.register(m._upd_panel, func() -> void: later.pressed.emit())
	m._menu_root.visible = false
	UITheme.safe_grab_focus_deferred(go)


# After an update (auto-updater or a new download): show this version's
# changelog section once. First-ever launch just records the version.
static func changelog_section(version: String) -> String:
	var f := FileAccess.open("res://CHANGELOG.md", FileAccess.READ)
	if f == null:
		return ""
	var txt := f.get_as_text()
	var head := "## [%s]" % version
	var i := txt.find(head)
	if i < 0:
		return ""
	var j := txt.find("\n## [", i + head.length())
	var sec := txt.substr(i, (j - i) if j > 0 else -1)
	sec = sec.substr(sec.find("\n") + 1).strip_edges()
	return md_to_bb(sec)


## Every version newer than `since`, newest first (capped), as short notes.
## Players who update across several releases see everything they missed.
static func changelog_since(since: String, current: String, max_sections: int = 6) -> String:
	var f := FileAccess.open("res://CHANGELOG.md", FileAccess.READ)
	if f == null:
		return ""
	var txt := f.get_as_text()
	var out := PackedStringArray()
	var i := txt.find("## [%s]" % current)
	while i >= 0 and out.size() < max_sections:
		var e := txt.find("]", i)
		var ver := txt.substr(i + 4, e - i - 4)
		if ver == since:
			break
		var j := txt.find("\n## [", i + 4)
		var sec := txt.substr(i, (j - i) if j > 0 else -1)
		sec = sec.substr(sec.find("\n") + 1).strip_edges()
		out.append("[b][color=#ffffff]v%s[/color][/b]\n%s" % [ver, md_to_bb(sec, true)])
		i = j + 1 if j > 0 else -1
	return "\n\n".join(out)


## Changelog markdown -> RichTextLabel bbcode (headers, bullets). `short`
## keeps just the first sentence of each bullet (the headline).
static func md_to_bb(sec: String, short: bool = false) -> String:
	var out := PackedStringArray()
	for line in sec.replace("**", "").replace("`", "").split("\n"):
		var l := line.strip_edges(false, true)
		if l.begins_with("### "):
			out.append("\n[b][color=#f5a623]%s[/color][/b]" % l.substr(4).to_upper())
		elif l.strip_edges().begins_with("- "):
			var ind := l.length() - l.strip_edges(true, false).length()
			var item := l.strip_edges().substr(2)
			if short:
				if ind > 0:
					continue  # sub-bullets are detail
				var dot := item.find(". ")
				if dot > 0 and dot < 200:
					item = item.left(dot + 1)
				elif item.length() > 200:
					item = item.left(197) + "..."
			out.append("%s• %s" % ["    ".repeat(ind / 2), item])
		else:
			out.append(l)
	return "\n".join(out).strip_edges()


static func maybe_whats_new(m: Node) -> void:
	var v := str(ProjectSettings.get_setting("application/config/version", ""))
	if Settings.last_seen_version == v:
		return
	var first := Settings.last_seen_version == ""
	var prev := Settings.last_seen_version
	Settings.last_seen_version = v
	Settings.save()
	if first:
		return
	var sec := changelog_since(prev, v)
	if sec == "":
		return
	var root := PanelContainer.new()
	root.add_theme_stylebox_override("panel", UITheme.panel_style())
	root.set_anchors_preset(Control.PRESET_CENTER, true)
	root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.grow_vertical = Control.GROW_DIRECTION_BOTH
	m.add_child(root)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(600, 0)
	root.add_child(box)
	box.add_child(UITheme.make_screen_title(TranslationServer.translate("WHAT'S NEW")))
	var notes := RichTextLabel.new()
	notes.bbcode_enabled = true
	notes.text = sec.left(4000)
	notes.scroll_active = true
	notes.custom_minimum_size = Vector2(580, 320)
	notes.add_theme_font_size_override("normal_font_size", 13)
	notes.add_theme_color_override("default_color", UITheme.COL_TEXT)
	box.add_child(notes)
	var ok: Button = m._make_button("GOT IT", true)
	ok.pressed.connect(func() -> void:
		root.queue_free()
		m._menu_root.visible = true)
	box.add_child(ok)
	UIBack.register(root, func() -> void: ok.pressed.emit())
	m._menu_root.visible = false
	UITheme.safe_grab_focus_deferred(ok)
