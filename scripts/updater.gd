extends Node
## Auto-updater. Asks GitHub for the latest release; if it's newer than this
## build, the menu shows an UPDATE button.
##   Windows: downloads SoldatReborn.exe next to the running exe (as .new),
##   checks its size, then a tiny batch file waits for the game to close,
##   swaps the files and starts the new version.
##   Android: an app can't replace itself, so it opens the .apk download in
##   the browser (tap the download to install).
## `--update-url=<url>` points it at another releases/latest JSON (tests).

signal state_changed

const LATEST_URL := "https://api.github.com/repos/Predator04/Soldat-Reborn/releases/latest"
const PAGE_URL := "https://github.com/Predator04/Soldat-Reborn/releases/latest"

var state := "idle"      # idle | checking | none | available | downloading | ready | failed
var latest := ""         # "1.22.0"
var notes := ""
var error := ""
var progress := 0.0
var _asset_url := ""
var _asset_size := 0
var _page := PAGE_URL
var _http: HTTPRequest
var _dl: HTTPRequest
var _new_path := ""
var _url := LATEST_URL


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--update-url="):
			_url = a.substr(13)
	_http = HTTPRequest.new()
	_http.timeout = 15
	_http.request_completed.connect(_on_latest)
	add_child(_http)


static func parse_version(v: String) -> Array:
	var out: Array = []
	for p in v.strip_edges().trim_prefix("v").split("."):
		out.append(int(p) if p.is_valid_int() else 0)
	while out.size() < 3:
		out.append(0)
	return out


static func is_newer(remote: String, local: String) -> bool:
	var r := parse_version(remote)
	var l := parse_version(local)
	for i in 3:
		if r[i] != l[i]:
			return r[i] > l[i]
	return false


static func current_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## Can this build swap its own exe? (exported Windows build, not the editor)
static func can_self_update() -> bool:
	return OS.get_name() == "Windows" and not OS.has_feature("editor")


func check() -> void:
	if state == "checking" or state == "downloading":
		return
	state = "checking"
	state_changed.emit()
	if _http.request(_url, PackedStringArray(["Accept: application/vnd.github+json", "User-Agent: SoldatReborn"])) != OK:
		_fail("couldn't reach GitHub")


func _on_latest(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("update check failed (%d/%d)" % [result, code])
		return
	var d = JSON.parse_string(body.get_string_from_utf8())
	if not (d is Dictionary) or not d.has("tag_name"):
		_fail("unexpected reply from GitHub")
		return
	latest = str(d["tag_name"]).trim_prefix("v")
	notes = str(d.get("body", ""))
	_page = str(d.get("html_url", PAGE_URL))
	var want := "SoldatReborn.apk" if OS.get_name() == "Android" else "SoldatReborn.exe"
	_asset_url = ""
	for a in d.get("assets", []):
		if a is Dictionary and str(a.get("name", "")) == want:
			_asset_url = str(a.get("browser_download_url", ""))
			_asset_size = int(a.get("size", 0))
	state = "available" if is_newer(latest, current_version()) else "none"
	state_changed.emit()


## Start the update: download + swap on Windows, browser download elsewhere.
func start() -> void:
	if state != "available" and state != "failed":
		return
	if not can_self_update() or _asset_url == "":
		OS.shell_open(_asset_url if _asset_url != "" else _page)
		return
	_new_path = OS.get_executable_path().get_base_dir().path_join("SoldatReborn.update.exe")
	download_to(_new_path)


func download_to(path: String) -> void:
	_new_path = path
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	_dl = HTTPRequest.new()
	_dl.download_file = path
	_dl.use_threads = true
	_dl.request_completed.connect(_on_downloaded)
	add_child(_dl)
	if _dl.request(_asset_url, PackedStringArray(["User-Agent: SoldatReborn"])) != OK:
		_fail("download didn't start")
		return
	state = "downloading"
	progress = 0.0
	state_changed.emit()


func _process(_d: float) -> void:
	if state == "downloading" and _dl != null and _asset_size > 0:
		var p := clampf(float(_dl.get_downloaded_bytes()) / float(_asset_size), 0.0, 1.0)
		if absf(p - progress) > 0.005:
			progress = p
			state_changed.emit()


func _on_downloaded(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	_dl.queue_free()
	_dl = null
	var got := 0
	if FileAccess.file_exists(_new_path):
		var f := FileAccess.open(_new_path, FileAccess.READ)
		if f != null:
			got = f.get_length()
			f.close()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or got <= 0 or (_asset_size > 0 and got != _asset_size):
		DirAccess.remove_absolute(_new_path)
		_fail("download incomplete (%d of %d bytes)" % [got, _asset_size])
		return
	state = "ready"
	state_changed.emit()


## Batch file that waits for this process to exit, swaps the exe in, restarts.
static func swap_script(exe: String, new_exe: String, pid: int) -> String:
	var old := exe.get_basename() + ".previous.exe"
	var w := func(p: String) -> String: return p.replace("/", "\\")
	return "\r\n".join(PackedStringArray([
		"@echo off",
		":wait",
		"tasklist /FI \"PID eq %d\" 2>NUL | find \"%d\" >NUL && (ping -n 2 127.0.0.1 >NUL & goto wait)" % [pid, pid],
		"del /f /q \"%s\" >NUL 2>&1" % w.call(old),
		"move /y \"%s\" \"%s\" >NUL" % [w.call(exe), w.call(old)],
		"move /y \"%s\" \"%s\" >NUL || (move /y \"%s\" \"%s\" >NUL & goto done)" % [w.call(new_exe), w.call(exe), w.call(old), w.call(exe)],
		":done",
		"start \"\" \"%s\"" % w.call(exe),
		"del \"%~f0\"",
	])) + "\r\n"


## Windows: hand over to the batch file and quit.
func apply_and_restart() -> void:
	if state != "ready" or not can_self_update():
		return
	var exe := OS.get_executable_path()
	var bat := exe.get_base_dir().path_join("soldat_update.bat")
	var f := FileAccess.open(bat, FileAccess.WRITE)
	if f == null:
		_fail("can't write next to the game (folder is read-only?)")
		return
	f.store_string(swap_script(exe, _new_path, OS.get_process_id()))
	f.close()
	OS.create_process("cmd.exe", ["/c", bat.replace("/", "\\")])
	get_tree().quit()


func _fail(msg: String) -> void:
	error = msg
	state = "failed"
	state_changed.emit()
