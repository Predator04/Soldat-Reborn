extends RefCounted
## How the game reaches the desktop Discord client (#223), in pure GDScript —
## no native library to build, sign or ship, nothing in the export presets.
## Every transport is used from discord_presence.gd's worker thread ONLY (the
## Windows reads block), never from the main thread.
##
## A transport (duck-typed; the test injects its own) has:
##   open() -> bool                 find + connect to a running Discord
##   write(bytes) -> bool
##   read_exact(n, timeout_ms) -> PackedByteArray   (shorter / empty = failed)
##   close()
##   describe() -> String           what it is connected to (logs)


## The platform's transport, or null where Discord has no desktop client we talk to.
static func for_platform() -> RefCounted:
	match OS.get_name():
		"Windows":
			return WindowsPipe.new()
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			return UnixSocket.new()
	return null


## Windows: Discord serves the named pipes \\.\pipe\discord-ipc-0 … -9.
## FileAccess can open them, but only spelled \\?\pipe\…: Godot's path
## clean-up (String.simplify_path) drops the "." segment of \\.\pipe\…,
## leaving a UNC path. FileAccess.open(READ_WRITE) = CreateFile(GENERIC_READ |
## GENERIC_WRITE, OPEN_EXISTING) through the C runtime; reads block until
## Discord answers, which is why this only ever runs on the worker thread.
class WindowsPipe:
	extends RefCounted
	var _f: FileAccess = null
	var _path := ""

	static func pipe_paths() -> PackedStringArray:
		var out := PackedStringArray()
		for i in 10:
			out.append("\\\\?\\pipe\\discord-ipc-%d" % i)
		return out

	func open() -> bool:
		close()
		for p in pipe_paths():
			var f := FileAccess.open(p, FileAccess.READ_WRITE)
			if f != null:
				_f = f
				_path = p
				return true
		return false

	func write(b: PackedByteArray) -> bool:
		if _f == null:
			return false
		var ok := _f.store_buffer(b)
		_f.flush()
		return ok and _f.get_error() == OK

	func read_exact(n: int, _timeout_ms: int) -> PackedByteArray:
		if _f == null or n <= 0:
			return PackedByteArray()
		return _f.get_buffer(n)

	func close() -> void:
		if _f != null:
			_f.close()
		_f = null

	func describe() -> String:
		return _path


## Linux / BSD: a Unix domain socket discord-ipc-0 … -9 in $XDG_RUNTIME_DIR
## (or the temp dir; Flatpak / Snap Discord nest it one level down).
## StreamPeerUDS (Godot 4.5+) is non-blocking, so reads poll with a timeout.
## Made through ClassDB (never named in code), so this file also compiles on
## a platform / build without the class.
class UnixSocket:
	extends RefCounted
	const ST_CONNECTING := 1   # StreamPeerSocket.Status
	const ST_CONNECTED := 2
	var dirs_override: PackedStringArray = PackedStringArray()   # tests
	# Socket files left behind by a Discord that quit or crashed: path ->
	# mtime of the failed try. Skipped until Discord makes a new one (a
	# failed connect is an engine error line, so don't repeat it every retry).
	static var _stale: Dictionary = {}
	var _s: Object = null
	var _path := ""

	func candidate_dirs() -> PackedStringArray:
		if not dirs_override.is_empty():
			return dirs_override
		var out := PackedStringArray()
		for k in ["XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP"]:
			var d := OS.get_environment(k).strip_edges()
			if d != "" and not out.has(d):
				out.append(d)
		if not out.has("/tmp"):
			out.append("/tmp")
		var base := PackedStringArray(out)
		for d in base:
			for sub in ["app/com.discordapp.Discord", "snap.discord", "app/com.discordapp.DiscordCanary", "app/dev.vencord.Vesktop"]:
				out.append(d.path_join(sub))
		return out

	func open() -> bool:
		close()
		for d in candidate_dirs():
			if not DirAccess.dir_exists_absolute(d):
				continue
			# Only knock on sockets that exist (a failed connect is an engine
			# error line in the log; Discord not running is the normal case).
			var names := DirAccess.get_files_at(d)
			for i in 10:
				var nm := "discord-ipc-%d" % i
				if not names.has(nm):
					continue
				var sp := d.path_join(nm)
				var mt := FileAccess.get_modified_time(sp)
				if _stale.get(sp, -1) == mt:
					continue
				if not ClassDB.can_instantiate("StreamPeerUDS"):
					return false
				var s: Object = ClassDB.instantiate("StreamPeerUDS")
				if int(s.call("connect_to_host", sp)) != OK:
					_stale[sp] = mt
					continue
				var t0 := Time.get_ticks_msec()
				while int(s.call("get_status")) == ST_CONNECTING and Time.get_ticks_msec() - t0 < 500:
					s.call("poll")
					OS.delay_msec(2)
				if int(s.call("get_status")) == ST_CONNECTED:
					_stale.erase(sp)
					_s = s
					_path = sp
					return true
				_stale[sp] = mt
				s.call("disconnect_from_host")
		return false

	func write(b: PackedByteArray) -> bool:
		if _s == null:
			return false
		_s.call("poll")
		if int(_s.call("get_status")) != ST_CONNECTED:
			return false
		return int(_s.call("put_data", b)) == OK

	func read_exact(n: int, timeout_ms: int) -> PackedByteArray:
		var out := PackedByteArray()
		if _s == null or n <= 0:
			return out
		var t0 := Time.get_ticks_msec()
		while out.size() < n:
			_s.call("poll")
			if int(_s.call("get_status")) != ST_CONNECTED:
				break
			var avail := int(_s.call("get_available_bytes"))
			if avail > 0:
				var r: Array = _s.call("get_partial_data", mini(avail, n - out.size()))
				if int(r[0]) != OK:
					break
				out.append_array(r[1])
				continue
			if Time.get_ticks_msec() - t0 > timeout_ms:
				break
			OS.delay_msec(3)
		return out

	func close() -> void:
		if _s != null:
			_s.call("disconnect_from_host")
		_s = null

	func describe() -> String:
		return _path
