extends Node
## GIF recorder — captures viewport frames while active and writes an animated
## GIF to user://recordings/. Uses a "reset-per-code" LZW stream which produces
## valid GIFs at a size penalty (no dictionary building), but stays in pure
## GDScript so we don't ship a native encoder.
##
## Toggle with F9. Also stops automatically after MAX_FRAMES to bound writes.
## Output frames are downsampled to keep the file <10 MB even at 10 s runs.

const MAX_FRAMES := 300              # ~15 s at 20 fps
const CAPTURE_FPS := 20.0
const DOWNSCALE_MAX_W := 480         # px — 480 wide keeps the file portable
const OUTPUT_DIR := "user://recordings/"

var _recording := false
var _t := 0.0
var _frames: Array = []              # Array[PackedByteArray] — each frame's palette-indexed pixels
var _palette: PackedByteArray = PackedByteArray()
var _color_to_idx: Dictionary = {}
var _size := Vector2i.ZERO


func is_recording() -> bool:
	return _recording


func toggle() -> void:
	if _recording:
		stop()
	else:
		start()


func start() -> void:
	if _recording:
		return
	if not DirAccess.dir_exists_absolute(OUTPUT_DIR):
		DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	_recording = true
	_t = 0.0
	_frames.clear()
	_palette = PackedByteArray()
	_color_to_idx.clear()
	_size = Vector2i.ZERO


func stop() -> void:
	if not _recording:
		return
	_recording = false
	if _frames.is_empty() or _size == Vector2i.ZERO:
		return
	var path := OUTPUT_DIR + "clip_%d.gif" % Time.get_unix_time_from_system()
	_encode_and_save(path)


func _process(delta: float) -> void:
	if not _recording:
		return
	if get_viewport() == null:
		return
	_t += delta
	var period: float = 1.0 / CAPTURE_FPS
	if _t < period:
		return
	_t = 0.0
	_capture_frame()
	if _frames.size() >= MAX_FRAMES:
		stop()


func _capture_frame() -> void:
	var vp := get_viewport()
	var img := vp.get_texture().get_image()
	if img == null:
		return
	# Downscale so files stay small. 480px wide is a good balance.
	if img.get_width() > DOWNSCALE_MAX_W:
		var new_w := DOWNSCALE_MAX_W
		var new_h := int(round(img.get_height() * (float(new_w) / float(img.get_width()))))
		img.resize(new_w, new_h, Image.INTERPOLATE_BILINEAR)
	img.convert(Image.FORMAT_RGB8)
	if _size == Vector2i.ZERO:
		_size = Vector2i(img.get_width(), img.get_height())
	# Quantize into a shared 256-color palette. First-come first-served: any color
	# beyond the 256th collapses to the nearest existing entry.
	var pixels := PackedByteArray()
	pixels.resize(_size.x * _size.y)
	var raw := img.get_data()
	for i in _size.x * _size.y:
		var r: int = raw[i * 3]
		var g: int = raw[i * 3 + 1]
		var b: int = raw[i * 3 + 2]
		# Reduce to 5-bit-per-channel so we hit 256 buckets fast.
		r = r & 0xF8
		g = g & 0xF8
		b = b & 0xF8
		var key: int = (r << 16) | (g << 8) | b
		var idx: int = int(_color_to_idx.get(key, -1))
		if idx < 0:
			if _color_to_idx.size() >= 256:
				idx = _nearest_palette_idx(r, g, b)
			else:
				idx = _color_to_idx.size()
				_color_to_idx[key] = idx
				_palette.append(r)
				_palette.append(g)
				_palette.append(b)
		pixels[i] = idx
	_frames.append(pixels)


func _nearest_palette_idx(r: int, g: int, b: int) -> int:
	var best := 0
	var best_d := 0xFFFFFFFF
	var n: int = _palette.size() / 3
	for i in n:
		var pr: int = _palette[i * 3]
		var pg: int = _palette[i * 3 + 1]
		var pb: int = _palette[i * 3 + 2]
		var dr: int = pr - r
		var dg: int = pg - g
		var db: int = pb - b
		var d: int = dr * dr + dg * dg + db * db
		if d < best_d:
			best_d = d
			best = i
	return best


func _encode_and_save(path: String) -> void:
	# Round palette size up to a power of two (min 4). GIF requires this.
	var n_colors: int = maxi(4, _palette.size() / 3)
	var pot := 1
	while pot < n_colors:
		pot *= 2
	# Pad palette to `pot * 3` bytes.
	while _palette.size() < pot * 3:
		_palette.append(0)
	var gct_bits: int = 0
	var p := pot
	while p > 1:
		p >>= 1
		gct_bits += 1
	gct_bits -= 1  # GIF encodes "size of GCT" as (log2 - 1)

	var out := PackedByteArray()
	_write_bytes(out, [0x47, 0x49, 0x46, 0x38, 0x39, 0x61])  # GIF89a
	_write_u16(out, _size.x)
	_write_u16(out, _size.y)
	# Packed byte: 1000 <gct_bits>, color res 7, sort 0, size gct_bits
	out.append(0x80 | (0x07 << 4) | (gct_bits & 0x07))
	out.append(0)      # Bg color index
	out.append(0)      # Pixel aspect ratio
	out.append_array(_palette.slice(0, pot * 3))

	# NETSCAPE 2.0 loop extension so the GIF loops forever.
	_write_bytes(out, [0x21, 0xFF, 0x0B])
	out.append_array("NETSCAPE2.0".to_ascii_buffer())
	_write_bytes(out, [0x03, 0x01, 0x00, 0x00, 0x00])

	var delay_cs: int = int(round(100.0 / CAPTURE_FPS))
	var lzw_min_code: int = maxi(2, gct_bits + 1)
	for frame_pixels in _frames:
		# Graphics Control Extension — sets frame delay + no transparency.
		_write_bytes(out, [0x21, 0xF9, 0x04, 0x00])
		_write_u16(out, delay_cs)
		out.append(0)
		out.append(0)
		# Image Descriptor
		out.append(0x2C)
		_write_u16(out, 0)
		_write_u16(out, 0)
		_write_u16(out, _size.x)
		_write_u16(out, _size.y)
		out.append(0)   # local color table off
		# LZW-compressed image data (using clear-code-only stream — bloated but valid).
		out.append(lzw_min_code)
		_encode_frame_lzw(out, frame_pixels, lzw_min_code)
	out.append(0x3B)  # Trailer

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("gif_recorder: could not open %s for write" % path)
		return
	f.store_buffer(out)
	f.close()


# Writes a simplified LZW stream. We never build up dictionary entries on the
# encoder side, but the decoder still expands its dict by one per code it reads.
# To keep the code width fixed at (min_code + 1), we periodically re-emit the
# CLEAR code so the decoder resets its dict before it would need to widen.
func _encode_frame_lzw(out: PackedByteArray, pixels: PackedByteArray, min_code: int) -> void:
	var clear_code: int = 1 << min_code
	var end_code: int = clear_code + 1
	var code_size: int = min_code + 1
	var max_code_this_size: int = (1 << code_size) - 1
	var next_code: int = end_code + 1

	var bit_buf: int = 0
	var bit_count: int = 0
	var sub := PackedByteArray()

	var push_code := func(code: int) -> void:
		bit_buf |= code << bit_count
		bit_count += code_size
		while bit_count >= 8:
			sub.append(bit_buf & 0xFF)
			bit_buf >>= 8
			bit_count -= 8
			if sub.size() >= 255:
				out.append(255)
				out.append_array(sub)
				sub = PackedByteArray()

	push_code.call(clear_code)
	for px in pixels:
		# If the decoder is one code away from having to widen its code size,
		# emit a CLEAR so its dict + code_size both reset back to (min+1).
		if next_code >= max_code_this_size:
			push_code.call(clear_code)
			next_code = end_code + 1
		push_code.call(int(px))
		next_code += 1
	push_code.call(end_code)
	# Flush trailing bits.
	if bit_count > 0:
		sub.append(bit_buf & 0xFF)
	if sub.size() > 0:
		out.append(sub.size())
		out.append_array(sub)
	out.append(0)  # block terminator


func _write_u16(out: PackedByteArray, v: int) -> void:
	out.append(v & 0xFF)
	out.append((v >> 8) & 0xFF)


func _write_bytes(out: PackedByteArray, arr: Array) -> void:
	for b in arr:
		out.append(int(b))
