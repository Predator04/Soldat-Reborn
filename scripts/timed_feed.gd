extends VBoxContainer
## A HUD text lane whose lines expire on their own: the kill feed (newest on
## top, kill_feed.gd) and the chat feed (newest at the bottom, chat_feed.gd)
## share this. Each line carries a one-shot Timer parented to the line, so the
## timer dies with the line instead of orphan-firing after it's gone.

var max_lines := 5
var line_ttl := 4.0
## true: new lines go on top and the oldest (bottom) ones are dropped past
## max_lines. false: new lines are appended and the top child is removed.
var newest_first := true
var _entries: Array = []   # newest_first lanes only: newest → oldest


func push_line(line: Control) -> void:
	add_child(line)
	if newest_first:
		move_child(line, 0)
		_entries.push_front(line)
		while _entries.size() > max_lines:
			var old: Control = _entries.pop_back()
			if is_instance_valid(old):
				old.queue_free()
	else:
		while get_child_count() > max_lines:
			var old := get_child(0)
			remove_child(old)
			old.queue_free()
	# #272: lines fade in, and fade out over their last 0.4 s.
	if not preload("res://scripts/ui_fx.gd").reduce_motion() and line.is_inside_tree():
		line.modulate.a = 0.0
		var tw := line.create_tween()
		tw.tween_property(line, "modulate:a", 1.0, 0.15)
		tw.tween_interval(maxf(0.0, line_ttl - 0.55))
		tw.tween_property(line, "modulate:a", 0.0, 0.4)
	var t := Timer.new()
	t.wait_time = line_ttl
	t.one_shot = true
	t.autostart = true
	line.add_child(t)
	t.timeout.connect(func() -> void:
		_entries.erase(line)
		if is_instance_valid(line):
			line.queue_free())
