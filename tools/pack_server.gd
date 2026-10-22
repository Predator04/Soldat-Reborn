extends SceneTree
## Pack a staged server folder into the release archive (#320). Runs in Godot
## so the owner's Windows release (Git Bash: no zip, sometimes no Python)
## and Linux build the same bytes.
##   godot --headless -s tools/pack_server.gd -- --src=DIR --out=FILE.zip|FILE.tar.gz [--root=NAME]
## Every file under DIR goes in as NAME/<relative path> (NAME defaults to the
## folder name). .tar.gz keeps the exec bit on the binary and *.sh / *.py
## (mode 0755, the rest 0644); .zip is for Windows. Prints PACK-OK <file> <bytes>.

const EXEC_EXT := ["sh", "py", "x86_64"]


func _init() -> void:
	var src := ""
	var out := ""
	var root := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--src="):
			src = a.substr(6)
		elif a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--root="):
			root = a.substr(7)
	if src == "" or out == "":
		printerr("usage: -- --src=DIR --out=FILE.zip|FILE.tar.gz [--root=NAME]")
		quit(2)
		return
	src = src.simplify_path()
	if root == "":
		root = src.get_file()
	var files: Array = []
	_walk(src, "", files)
	files.sort()
	if files.is_empty():
		printerr("PACK-FAIL nothing under %s" % src)
		quit(1)
		return
	var ok := false
	if out.ends_with(".zip"):
		ok = _zip(src, files, root, out)
	elif out.ends_with(".tar.gz") or out.ends_with(".tgz"):
		ok = _targz(src, files, root, out)
	else:
		printerr("PACK-FAIL unknown archive type: %s" % out)
	if not ok:
		quit(1)
		return
	var f := FileAccess.open(out, FileAccess.READ)
	print("PACK-OK %s %d files %d bytes" % [out, files.size(), f.get_length() if f != null else -1])
	quit(0)


func _walk(base: String, rel: String, out: Array) -> void:
	var d := DirAccess.open(base.path_join(rel) if rel != "" else base)
	if d == null:
		return
	d.include_hidden = false
	for fn in d.get_files():
		out.append(rel.path_join(fn) if rel != "" else fn)
	for dn in d.get_directories():
		_walk(base, rel.path_join(dn) if rel != "" else dn, out)


func _zip(src: String, files: Array, root: String, out: String) -> bool:
	var z := ZIPPacker.new()
	if z.open(out) != OK:
		printerr("PACK-FAIL cannot write %s" % out)
		return false
	for rel in files:
		var data := FileAccess.get_file_as_bytes(src.path_join(rel))
		z.start_file(root.path_join(rel))
		z.write_file(data)
		z.close_file()
	z.close()
	return true


func _is_exec(rel: String) -> bool:
	var ext := rel.get_extension().to_lower()
	return ext in EXEC_EXT or (ext == "" and rel.get_file().begins_with("TracerfallServer"))


## ustar: 512-byte header per file, data padded to 512, two zero blocks at the
## end; then gzip the lot.
func _targz(src: String, files: Array, root: String, out: String) -> bool:
	var tar := PackedByteArray()
	var mtime := int(Time.get_unix_time_from_system())
	for rel in files:
		var data := FileAccess.get_file_as_bytes(src.path_join(rel))
		var name: String = root.path_join(rel)
		var prefix := ""
		if name.to_utf8_buffer().size() > 99:
			var cut := name.rfind("/", 154)
			prefix = name.left(cut)
			name = name.substr(cut + 1)
		var h := PackedByteArray()
		h.resize(512)
		_put(h, 0, name, 100)
		_put(h, 100, "%07o" % (493 if _is_exec(rel) else 420), 8)   # 0755 / 0644
		_put(h, 108, "%07o" % 0, 8)
		_put(h, 116, "%07o" % 0, 8)
		_put(h, 124, "%011o" % data.size(), 12)
		_put(h, 136, "%011o" % mtime, 12)
		for i in 8:
			h[148 + i] = 32   # checksum field counts as spaces
		h[156] = 48           # '0' regular file
		_put(h, 257, "ustar", 6)
		_put(h, 263, "00", 2)
		_put(h, 265, "root", 32)
		_put(h, 297, "root", 32)
		_put(h, 345, prefix, 155)
		var sum := 0
		for b in h:
			sum += b
		_put(h, 148, "%06o" % sum, 7)
		h[155] = 32
		tar.append_array(h)
		tar.append_array(data)
		var pad := (512 - data.size() % 512) % 512
		if pad > 0:
			var z := PackedByteArray()
			z.resize(pad)
			tar.append_array(z)
	var end := PackedByteArray()
	end.resize(1024)
	tar.append_array(end)
	var gz := tar.compress(FileAccess.COMPRESSION_GZIP)
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		printerr("PACK-FAIL cannot write %s" % out)
		return false
	f.store_buffer(gz)
	f.close()
	return true


func _put(h: PackedByteArray, at: int, s: String, n: int) -> void:
	var b := s.to_utf8_buffer()
	for i in mini(b.size(), n):
		h[at + i] = b[i]
