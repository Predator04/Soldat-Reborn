extends SceneTree
## Menu news line (#261) + featured-week fallback (#264) against a real local
## master (gate C "news"): the master serves news.json; the menu shows it
## under the version button; × hides that message for good and a new one
## shows again; an expired message and a missing file show nothing; with no
## news the master falls back to featured.json. Also: a reloaded menu reuses
## the cached reply instead of asking again (10-minute cap).
##   godot --headless -s tools/news_test.gd -- --menu-news --master=http://127.0.0.1:PORT \
##       --news-file=/tmp/x/news.json --featured-file=/tmp/x/featured.json

var _st := 0
var _n := 0
var _t := 0
var _m: Node
var _nw: Node
var _news_file := ""
var _feat_file := ""
var _saved_url := ""
var _saved_dismissed := ""
var _log: Array = []
const GL = preload("res://tools/gate_load.gd")
var WAIT := GL.wait_ms(8000)   # ms per step before giving up (headless frames are fast; #293: x GATE_LOAD)


func _write(path: String, s: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(s)
	f.close()


func _process(_d: float) -> bool:
	_n += 1
	var st = root.get_node_or_null("Settings")
	if st == null or _n < 3:
		return false
	match _st:
		0:
			_saved_url = st.master_url
			_saved_dismissed = st.news_dismissed
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--master="):
					st.master_url = a.substr(9)
				elif a.begins_with("--news-file="):
					_news_file = a.substr(12)
				elif a.begins_with("--featured-file="):
					_feat_file = a.substr(16)
			if _news_file == "":
				return _end(false, "no --news-file")
			st.news_dismissed = ""
			DirAccess.remove_absolute(_feat_file)
			_write(_news_file, JSON.stringify({"text": "Test news: v9 is out\u0007", "url": "https://example.com/news", "until_ms": 0}))
			change_scene_to_file("res://scenes/menu.tscn")
			_st = 1
			_t = Time.get_ticks_msec()
		1:
			_m = current_scene
			if _m == null or _m.get("_news") == null or _m.get("_menu_root") == null:
				return Time.get_ticks_msec() - _t > WAIT and _end(false, "menu never loaded")
			_nw = _m._news
			if _nw.shown_text == "":
				return Time.get_ticks_msec() - _t > WAIT and _end(false, "news never shown (fetches=%d)" % _nw.fetches)
			if _nw.shown_text != "Test news: v9 is out" or _nw.shown_url != "https://example.com/news":
				return _end(false, "wrong news: '%s' '%s'" % [_nw.shown_text, _nw.shown_url])
			if not _nw.visible:
				return false   # visibility follows on the next frame
			var vb: Control = _m._upd_btn
			if _nw.get_global_rect().position.y < vb.get_global_rect().end.y - 1.0:
				return _end(false, "news overlaps the version button")
			if _nw._x_btn.custom_minimum_size.y < 32 or _nw._text_btn.custom_minimum_size.y < 32:
				return _end(false, "hit area too small")
			_log.append("shown '%s'" % _nw.shown_text)
			# Dismiss: hidden, remembered, stays hidden for the same text.
			_nw.dismiss()
			if _nw.shown_text != "" or st.news_dismissed != "Test news: v9 is out":
				return _end(false, "dismiss: shown='%s' saved='%s'" % [_nw.shown_text, st.news_dismissed])
			_nw.fetch()
			_st = 2
			_t = Time.get_ticks_msec()
		2:
			if Time.get_ticks_msec() - _t < 1500:
				return false
			if _nw.shown_text != "":
				return _end(false, "dismissed message came back")
			if _nw.visible:
				return false
			_log.append("dismissed")
			# A new message shows again.
			_write(_news_file, JSON.stringify({"text": "Second message: tournament on Saturday", "until_ms": int(Time.get_unix_time_from_system() * 1000.0) + 3600000}))
			_nw.fetch()
			_st = 3
			_t = Time.get_ticks_msec()
		3:
			if _nw.shown_text != "Second message: tournament on Saturday" or not _nw.visible:
				return Time.get_ticks_msec() - _t > WAIT and _end(false, "new message not shown: '%s'" % _nw.shown_text)
			if _nw.shown_url != "":
				return _end(false, "url without one: %s" % _nw.shown_url)
			_log.append("new shown")
			# A menu reload uses the cached reply (no new request inside 10 min).
			var again = load("res://scripts/menu_news.gd").new()
			root.add_child(again)
			if again.fetches != 0 or again.shown_text != "Second message: tournament on Saturday":
				return _end(false, "reload: fetches=%d text='%s'" % [again.fetches, again.shown_text])
			again.queue_free()
			_log.append("cached")
			# Expired -> hidden.
			_write(_news_file, JSON.stringify({"text": "Expired message from last week", "until_ms": int(Time.get_unix_time_from_system() * 1000.0) - 60000}))
			_nw.fetch()
			_st = 4
			_t = Time.get_ticks_msec()
		4:
			if _nw.shown_text != "" or _nw.visible:
				return Time.get_ticks_msec() - _t > WAIT and _end(false, "expired still shown: '%s'" % _nw.shown_text)
			if not load("res://scripts/menu_news.gd").parse_news({"text": "x", "until_ms": 5}).is_empty():
				return _end(false, "client accepts expired")
			_log.append("expired hidden")
			# Featured week fallback (#264), then nothing at all.
			_write(_feat_file, JSON.stringify({"mode": "rm", "map": "Voland", "until": 0}))
			_nw.fetch()
			_st = 5
			_t = Time.get_ticks_msec()
		5:
			if _nw.shown_text != "This week on the official server: Rambomatch on Voland":
				return Time.get_ticks_msec() - _t > WAIT and _end(false, "featured fallback: '%s'" % _nw.shown_text)
			_log.append("featured")
			DirAccess.remove_absolute(_feat_file)
			DirAccess.remove_absolute(_news_file)
			_nw.fetch()
			_st = 6
			_t = Time.get_ticks_msec()
		6:
			if _nw.shown_text != "" or _nw.visible:
				return Time.get_ticks_msec() - _t > WAIT and _end(false, "missing file still shown: '%s'" % _nw.shown_text)
			if Time.get_ticks_msec() - _t < 1500:
				return false   # let the reply land; nothing may error
			_log.append("missing hidden")
			# Unreachable master: silent, keeps the menu working.
			st.master_url = "http://127.0.0.1:1"
			_nw.fetch()
			_st = 7
			_t = Time.get_ticks_msec()
		7:
			if Time.get_ticks_msec() - _t < 3000:
				return false
			if _nw.shown_text != "":
				return _end(false, "unreachable master showed something")
			_log.append("offline ok")
			return _end(true, "")
	return false


func _end(ok: bool, why: String) -> bool:
	var st = root.get_node_or_null("Settings")
	if st != null:
		st.master_url = _saved_url
		st.news_dismissed = _saved_dismissed
		st.save()
	print("NEWS-TEST %s %s %s" % ["ok" if ok else "FAIL", why, str(_log)])
	quit(0 if ok else 1)
	return true
