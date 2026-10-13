extends Node
## Auto-updater. Asks GitHub for the latest release; if it's newer than this
## build, the menu shows an UPDATE button.
##   Windows: downloads SoldatReborn.exe next to the running exe (as .new),
##   then verifies its RSA signature over sha256 (#237) before a tiny batch
##   file waits for the game to close, swaps the files and starts the new
##   version. A release without a SoldatReborn.exe.sig asset, an asset on a
##   non-GitHub host, or a byte that doesn't match the signature is refused.
##   Android: an app can't replace itself, so it opens the .apk download in
##   the browser (tap the download to install) — the apk carries its own
##   keystore signature.
## `--update-url=<url>` points it at another releases/latest JSON (tests);
## `--update-pubkey=<path>` swaps the verification key (tests only).
## Key pair lives outside the repo in ../keys (see keys/UPDATE_SIGNING.md);
## the matching private key signs build/SoldatReborn.exe during release.

signal state_changed

const LATEST_URL := "https://api.github.com/repos/Predator04/Soldat-Reborn/releases/latest"
const PAGE_URL := "https://github.com/Predator04/Soldat-Reborn/releases/latest"

## Public half of the release signing key (#237). A new pair means shipping a
## manually-installed release first — see keys/UPDATE_SIGNING.md.
const PUB_PEM := """-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAscvPuu44Aq8WO/ZGNbhG
+vY3J21L2mGgPIQqZ1Bzzu7jFzQs8LupzrUjSg2qW5DfSuv5xVCSrrMhWgOhlDs0
NqWK3A8wMqP3NHRi0Ez87TrKy0D3YJFsFAUlfLZXSNo7aosSjo78hZlrTEpByFdH
4ycErA2F/G6x+n9gBe485b++6SuLPi5k8+HUAzg+nk26lH57xyr7GvxP1rNWB19I
Oxx/Tmm9bpg157HE6HFHo2V5azg/CRVyNfMXyLFIURYF2zVHnKiRr6ihf632ik5n
6kjUiuDc6cBda/HK9hKvN9CQlgrIy6gSxvREIt5g2p1gqPKe+fCmE9jtWUFZp+SO
fQIDAQAB
-----END PUBLIC KEY-----
"""

var state := "idle"      # idle | checking | none | available | downloading | ready | failed
var latest := ""         # "1.22.0"
var notes := ""
var error := ""
var progress := 0.0
var _asset_url := ""
var _asset_size := 0
var _sig_url := ""
var _page := PAGE_URL
var _http: HTTPRequest
var _dl: HTTPRequest
var _sig: HTTPRequest
var _new_path := ""
var _url := LATEST_URL
var _pub_pem := ""       # non-empty = test override via --update-pubkey
var last_sig := PackedByteArray()  # last verified signature (tests/debugging)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--update-url="):
			_url = a.substr(13)
		elif a.begins_with("--update-pubkey="):
			var pk := a.substr(16)
			if FileAccess.file_exists(pk):
				_pub_pem = FileAccess.get_file_as_string(pk)
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


## #237: release assets must come from GitHub over TLS. Plain HTTP is only
## ever acceptable for the gate's local fake server (host must be exactly
## localhost / 127.0.0.1 — #254: a prefix check let "localhost.evil.com" in).
static func asset_url_ok(u: String) -> bool:
	if u.begins_with("https://"):
		var host := u.substr(8).get_slice("/", 0).to_lower()
		return host == "github.com" or host.ends_with(".github.com")
	if u.begins_with("http://"):
		var lhost := u.substr(7).get_slice("/", 0).to_lower().split(":")[0]
		return lhost == "localhost" or lhost == "127.0.0.1"
	return false


func pubkey_pem() -> String:
	return _pub_pem if _pub_pem != "" else PUB_PEM


## Verify an RSA signature over sha256(file). `sig` is the raw signature bytes
## (256 for our RSA-2048 key). CryptoKey in Godot 4.7 only loads from a path,
## so the PEM is parked in a temp file first.
static func verify_signature(file_path: String, sig: PackedByteArray, pem: String) -> bool:
	if sig.is_empty() or pem.is_empty():
		return false
	var tmp := OS.get_user_data_dir().path_join("_update_pub.pem")
	var wf := FileAccess.open(tmp, FileAccess.WRITE)
	if wf == null:
		return false
	wf.store_string(pem)
	wf.close()
	var key := CryptoKey.new()
	if key.load(tmp, true) != OK:
		push_error("update pubkey rejected")
		return false
	var digest_hex: String = FileAccess.get_sha256(file_path)
	if digest_hex.length() != 64:
		return false
	var db := PackedByteArray()
	for i in range(0, 64, 2):
		db.append(digest_hex.substr(i, 2).hex_to_int())
	return Crypto.new().verify(HashingContext.HASH_SHA256, db, sig, key) == true


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
	_asset_size = 0
	_sig_url = ""
	for a in d.get("assets", []):
		if a is Dictionary:
			var nm := str(a.get("name", ""))
			if nm == want:
				_asset_url = str(a.get("browser_download_url", ""))
				_asset_size = int(a.get("size", 0))
			elif nm == want + ".sig":
				_sig_url = str(a.get("browser_download_url", ""))
	state = "available" if is_newer(latest, current_version()) else "none"
	# #237: refuse Windows updates we can't prove genuine — wrong host, no
	# signature asset, or no size to check against all mean fail closed.
	if state == "available" and can_self_update():
		if _asset_size <= 0 or not asset_url_ok(_asset_url) or not asset_url_ok(_sig_url):
			_fail("update is not properly signed — refusing to install")
			return
	state_changed.emit()


## Start the update: download + verify + swap on Windows, browser download elsewhere.
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
	if _dl != null:
		_dl.queue_free()
	_dl = HTTPRequest.new()
	_dl.download_file = path
	_dl.use_threads = true
	_dl.request_completed.connect(_on_downloaded)
	add_child(_dl)
	if _dl.request(_asset_url, PackedStringArray(["User-Agent: SoldatReborn"])) != OK:
		_dl.queue_free()
		_dl = null
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
	# #237: size is mandatory now — a release without it can't be checked.
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or got <= 0 or _asset_size <= 0 or got != _asset_size:
		DirAccess.remove_absolute(_new_path)
		_fail("download incomplete (%d of %d bytes)" % [got, _asset_size])
		return
	_fetch_signature()


## Pull the small .sig asset into memory, then verify the downloaded file
## against it before offering to run (#237).
func _fetch_signature() -> void:
	if _sig != null:
		_sig.queue_free()
	_sig = HTTPRequest.new()
	_sig.timeout = 20
	_sig.request_completed.connect(_on_sig_downloaded)
	add_child(_sig)
	var url := _sig_url if _sig_url != "" else _asset_url + ".sig"
	if not url.begins_with("http") or _sig.request(url, PackedStringArray(["User-Agent: SoldatReborn"])) != OK:
		_sig.queue_free()
		_sig = null
		DirAccess.remove_absolute(_new_path)
		_fail("couldn't fetch the update signature")
		return
	state = "downloading"
	state_changed.emit()


func _on_sig_downloaded(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_sig.queue_free()
	_sig = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.is_empty() or body.size() > 1024:
		DirAccess.remove_absolute(_new_path)
		_fail("update signature unavailable — refusing to install")
		return
	last_sig = body
	if not verify_signature(_new_path, body, pubkey_pem()):
		DirAccess.remove_absolute(_new_path)
		_fail("update failed its signature check — refusing to install")
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
