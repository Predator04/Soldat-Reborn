extends RefCounted
## Discord local RPC wire format (#223) — what the desktop Discord client
## speaks on its local pipe / socket. Pure data: no I/O, no scene tree, safe
## from any thread.
##
## A frame is: opcode (u32, little endian), payload length (u32, LE), then
## that many bytes of UTF-8 JSON.
##   HANDSHAKE {"v": 1, "client_id": "<application id>"}
##     -> FRAME {"cmd": "DISPATCH", "evt": "READY", "data": {"user": {...}}}
##     -> or CLOSE {"code": 4000, "message": "Invalid Client ID"} (and Discord hangs up)
##   FRAME {"cmd": "SET_ACTIVITY", "args": {"pid": <our pid>, "activity": {...} | null}, "nonce": "<n>"}
##     -> FRAME {"cmd": "SET_ACTIVITY", "nonce": "<n>", "evt": null | "ERROR", "data": {...}}
##   PING -> answer PONG with the same payload.

const OP_HANDSHAKE := 0
const OP_FRAME := 1
const OP_CLOSE := 2
const OP_PING := 3
const OP_PONG := 4

## Replies bigger than this are not Discord talking to us.
const MAX_PAYLOAD := 65536


static func encode(op: int, payload: Variant) -> PackedByteArray:
	var body := JSON.stringify(payload).to_utf8_buffer()
	var out := PackedByteArray()
	out.resize(8)
	out.encode_u32(0, op)
	out.encode_u32(4, body.size())
	out.append_array(body)
	return out


static func handshake(client_id: String) -> PackedByteArray:
	return encode(OP_HANDSHAKE, {"v": 1, "client_id": client_id})


## `activity` = {} clears the status (Discord takes a null activity for that).
static func set_activity(pid: int, activity: Dictionary, nonce: String) -> PackedByteArray:
	return encode(OP_FRAME, {
		"cmd": "SET_ACTIVITY",
		"args": {"pid": pid, "activity": activity if not activity.is_empty() else null},
		"nonce": nonce,
	})


## [op, payload_length] from an 8-byte header ([-1, 0] when malformed).
static func parse_header(h: PackedByteArray) -> Array:
	if h.size() != 8:
		return [-1, 0]
	var op := h.decode_u32(0)
	var n := h.decode_u32(4)
	if op > OP_PONG or n > MAX_PAYLOAD:
		return [-1, 0]
	return [op, n]


## Parsed JSON object of a payload ({} when it isn't one).
static func parse_payload(b: PackedByteArray) -> Dictionary:
	var v: Variant = JSON.parse_string(b.get_string_from_utf8())
	return v if v is Dictionary else {}


## Decode every whole frame at the front of `buf`: returns [frames, bytes used],
## frames = [[op, payload dict], ...]. (The test's fake Discord parses with it.)
static func split_frames(buf: PackedByteArray) -> Array:
	var frames: Array = []
	var at := 0
	while buf.size() - at >= 8:
		var hd := parse_header(buf.slice(at, at + 8))
		if int(hd[0]) < 0:
			break
		var n: int = hd[1]
		if buf.size() - at - 8 < n:
			break
		frames.append([int(hd[0]), parse_payload(buf.slice(at + 8, at + 8 + n))])
		at += 8 + n
	return [frames, at]
