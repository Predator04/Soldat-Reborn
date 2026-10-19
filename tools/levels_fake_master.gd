extends Node
## A tiny in-process stand-in for the master server's /levels API (#288) so
## tools/levels_test.gd runs in the gate's F stage with no Go binary: a
## TCPServer speaking just enough HTTP/1.1 (one request per connection,
## Connection: close). Same routes, JSON shapes and rules as levels.go
## (sorting, search incl. share codes, paging, ids=, likes once per pid,
## plays once per pid per day, filter masking via name_filter.gd); the real
## server's own rules are unit-tested in the master-server repo (go test).

const LevelThumb = preload("res://scripts/level_thumb.gd")
const NameFilter = preload("res://scripts/name_filter.gd")
const ALPHA := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

var port := 0
var levels := {}        # id -> record
var requests: Array = []   # "METHOD /path" log
var _srv := TCPServer.new()
var _conns: Array = []  # [{peer, buf, t}]
var _clock := 0


func start(p: int = 0) -> bool:
	for i in 20:
		var try := p if p > 0 else 18000 + randi() % 20000
		if _srv.listen(try, "127.0.0.1") == OK:
			port = try
			return true
	return false


func url() -> String:
	return "http://127.0.0.1:%d" % port


func _process(_d: float) -> void:
	while _srv.is_connection_available():
		_conns.append({"peer": _srv.take_connection(), "buf": PackedByteArray(), "t": Time.get_ticks_msec()})
	for c in _conns.duplicate():
		var peer: StreamPeerTCP = c["peer"]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or Time.get_ticks_msec() - int(c["t"]) > 10000:
			_conns.erase(c)
			continue
		var n := peer.get_available_bytes()
		if n > 0:
			var r: Array = peer.get_data(n)
			if int(r[0]) == OK:
				c["buf"].append_array(r[1])
		var req := _parse(c["buf"])
		if req.is_empty():
			continue
		var out: Array = _route(req)
		var body := (out[1] as String).to_utf8_buffer()
		var head := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [
			int(out[0]), "OK" if int(out[0]) == 200 else "ERR", "application/json" if int(out[0]) == 200 else "text/plain", body.size()]
		peer.put_data(head.to_utf8_buffer() + body)
		peer.disconnect_from_host()
		_conns.erase(c)


# {method, path, query: Dictionary, body: String} once the request is whole.
func _parse(buf: PackedByteArray) -> Dictionary:
	var text := buf.get_string_from_utf8()
	var he := text.find("\r\n\r\n")
	if he < 0:
		return {}
	var lines := text.substr(0, he).split("\r\n")
	var first := lines[0].split(" ")
	if first.size() < 2:
		return {}
	var clen := 0
	for l in lines:
		if l.to_lower().begins_with("content-length:"):
			clen = int(l.substr(15).strip_edges())
	var head_bytes := text.substr(0, he + 4).to_utf8_buffer().size()
	if buf.size() < head_bytes + clen:
		return {}
	var target: String = first[1]
	var path := target.get_slice("?", 0)
	var query := {}
	if target.contains("?"):
		for kv in target.get_slice("?", 1).split("&", false):
			query[kv.get_slice("=", 0)] = kv.get_slice("=", 1).replace("+", " ").uri_decode()
	var body := buf.slice(head_bytes, head_bytes + clen).get_string_from_utf8()
	requests.append("%s %s" % [first[0], path])
	return {"method": first[0], "path": path, "query": query, "body": body}


static func norm_code(s: String) -> String:
	var out := ""
	for ch in s.to_upper():
		if ch in [" ", "-", "_", "."]:
			continue
		if ch == "O":
			ch = "0"
		elif ch == "I" or ch == "L":
			ch = "1"
		if not ALPHA.contains(ch):
			return ""
		out += ch
	return out if out.length() == 12 else ""


func _view(e: Dictionary, pid: String, thumb: bool) -> Dictionary:
	var v := {}
	for k in ["id", "code", "title", "author", "modes", "theme", "plays", "likes", "downloads"]:
		v[k] = e[k]
	v["name"] = e["title"]
	v["created_ms"] = e["up"]
	v["uploaded_ms"] = e["up"]
	v["hot"] = float(e["plays"]) + 3.0 * float(e["likes"])
	if pid != "" and (e["likers"] as Dictionary).has(pid):
		v["liked"] = true
	if thumb:
		v["thumb"] = e["thumb"]
	return v


func _route(q: Dictionary) -> Array:
	var qs: Dictionary = q["query"]
	var pid := str(qs.get("pid", ""))
	match [q["method"], q["path"]]:
		["GET", "/levels"]:
			var out: Array = []
			var ids: Array = str(qs.get("ids", "")).split(",", false)
			if not ids.is_empty():
				for id in ids:
					if levels.has(id):
						out.append(_view(levels[id], pid, true))
				return [200, JSON.stringify({"levels": out, "page": 0, "per": 48, "total": out.size(), "more": false})]
			var term := str(qs.get("q", "")).strip_edges().to_lower()
			var code := norm_code(term)
			for e in levels.values():
				if term == "" or (code != "" and norm_code(e["code"]) == code) or (str(e["title"]) + "\n" + str(e["author"])).to_lower().contains(term):
					out.append(_view(e, pid, true))
			var by := str(qs.get("sort", "hot"))
			var key: String = {"hot": "hot", "plays": "plays", "likes": "likes"}.get(by, "uploaded_ms")
			out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				if float(a[key]) != float(b[key]):
					return float(a[key]) > float(b[key])
				return int(a["uploaded_ms"]) > int(b["uploaded_ms"]))
			var per := clampi(int(qs.get("per", "24")), 1, 48)
			var page := maxi(0, int(qs.get("page", "0")))
			var total := out.size()
			out = out.slice(page * per, page * per + per)
			return [200, JSON.stringify({"levels": out, "page": page, "per": per, "total": total, "more": (page + 1) * per < total})]
		["GET", "/levels/get"]:
			var id := str(qs.get("id", ""))
			if id == "":
				var c := norm_code(str(qs.get("code", "")))
				for e in levels.values():
					if c != "" and norm_code(e["code"]) == c:
						id = e["id"]
			if not levels.has(id):
				return [404, "no level with that id or code"]
			levels[id]["downloads"] += 1
			return [200, '{"level":%s,"map":%s}' % [JSON.stringify(_view(levels[id], pid, true)), levels[id]["map"]]]
		["POST", "/levels/upload"]:
			var d = JSON.parse_string(q["body"])
			if not (d is Dictionary) or not (d.get("map") is Dictionary):
				return [400, "bad json"]
			var m: Dictionary = d["map"]
			var ground := (m.get("platforms", []) as Array).size() + (m.get("polys", []) as Array).size() if m.get("polys") is Array else (m.get("platforms", []) as Array).size()
			if ground < 1:
				return [400, "map needs at least one platform"]
			var title := NameFilter.mask(str(d.get("title", d.get("name", "Untitled"))).strip_edges().left(32))
			m["name"] = title
			var body := JSON.stringify(m)
			var id := body.sha256_text().left(16)
			if levels.has(id):
				return [200, JSON.stringify({"ok": true, "id": id, "existing": true, "code": levels[id]["code"], "title": title, "name": title})]
			var h := ("code:" + id).sha256_buffer()
			var code := ""
			for i in 12:
				if i == 4 or i == 8:
					code += "-"
				code += ALPHA[h[i] & 31]
			_clock += 1
			levels[id] = {"id": id, "code": code, "title": title, "author": NameFilter.mask(str(d.get("author", "")).left(24)),
				"modes": LevelThumb.mode_hints(m), "theme": str(d.get("theme", "")), "plays": 0, "likes": 0, "downloads": 0,
				"up": int(Time.get_unix_time_from_system() * 1000.0) + _clock, "thumb": LevelThumb.from_map(m), "map": body,
				"likers": {}, "played": {}}
			return [200, JSON.stringify({"ok": true, "id": id, "code": code, "title": title, "name": title, "modes": levels[id]["modes"]})]
		["POST", "/levels/like"]:
			var d = JSON.parse_string(q["body"])
			if not (d is Dictionary) or not levels.has(str(d.get("id", ""))):
				return [404, "no such level"]
			var e: Dictionary = levels[str(d["id"])]
			var p := str(d.get("pid", ""))
			if bool(d.get("like", true)):
				e["likers"][p] = true
			else:
				e["likers"].erase(p)
			e["likes"] = (e["likers"] as Dictionary).size()
			return [200, JSON.stringify({"ok": true, "id": e["id"], "likes": e["likes"], "liked": (e["likers"] as Dictionary).has(p)})]
		["POST", "/levels/play"]:
			var d = JSON.parse_string(q["body"])
			if not (d is Dictionary) or not levels.has(str(d.get("id", ""))):
				return [404, "no such level"]
			var e: Dictionary = levels[str(d["id"])]
			var key := "%s@%d" % [str(d.get("pid", "")), int(Time.get_unix_time_from_system() / 86400.0)]
			var counted := not (e["played"] as Dictionary).has(key)
			if counted:
				e["played"][key] = true
				e["plays"] += 1
			return [200, JSON.stringify({"ok": true, "id": e["id"], "plays": e["plays"], "counted": counted})]
	return [404, "not found"]
