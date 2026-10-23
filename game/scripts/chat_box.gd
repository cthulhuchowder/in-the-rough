class_name ChatBox
extends Control
## Room chat, bottom left: open() shows a small text box (Enter sends through the server to the
## room, Esc cancels); lines arrive as "Name: text" in a log of the last chat_lines, each fading out
## chat_life s after it came, with a short blip. While the box is open the swing gets no input
## (gesture.blocked) and main skips its held keys. Multiplayer rooms only (main never builds it for
## single player).

const FEEDBACK: FeedbackParams = preload("res://data/feedback.tres")

var gesture: SwingGesture
var _sound := AudioStreamPlayer.new() # its own: never cuts a hit sound

var _log := VBoxContainer.new()
var _edit := LineEdit.new()
var _blip: AudioStream = preload("res://data/sounds.tres").chat
var _blocked_before := false


func _ready() -> void:
	var f := FEEDBACK
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.add_theme_constant_override("separation", 2)
	add_child(_log)
	_edit.custom_minimum_size = Vector2(f.chat_width, 0)
	_edit.max_length = Net.PARAMS.chat_max_length
	_edit.placeholder_text = "Say something…"
	_edit.add_theme_font_size_override("font_size", f.chat_font)
	var box := StyleBoxFlat.new()
	box.bg_color = f.card_panel
	box.set_corner_radius_all(6)
	box.set_content_margin_all(6)
	_edit.add_theme_stylebox_override("normal", box)
	_edit.add_theme_stylebox_override("focus", box)
	_edit.add_theme_color_override("font_color", f.card_text)
	_edit.focus_next = NodePath(".") # Tab stays in the box
	_edit.focus_previous = NodePath(".")
	_edit.hide()
	_edit.text_submitted.connect(_send)
	add_child(_edit)
	_sound.bus = Settings.SFX_BUS
	add_child(_sound)
	Net.chat_received.connect(add_line)


func is_open() -> bool:
	return _edit.visible


func open() -> void:
	if is_open():
		return
	_blocked_before = gesture.blocked
	gesture.blocked = true # no swing while typing
	_edit.text = ""
	_edit.show()
	_edit.grab_focus()
	_layout()


func close() -> void:
	if not is_open():
		return
	_edit.release_focus()
	_edit.hide()
	gesture.blocked = _blocked_before
	_layout()


## Esc cancels before anything else sees it (the Esc menu, the club wheel).
func _input(event: InputEvent) -> void:
	if is_open() and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


func _send(text: String) -> void:
	if text.strip_edges() != "":
		Net.send_chat.rpc_id(1, text)
	close()


func add_line(player_name: String, text: String) -> void:
	var f := FEEDBACK
	var line := Label.new()
	line.text = "%s: %s" % [player_name, text]
	line.add_theme_font_size_override("font_size", f.chat_font)
	line.add_theme_color_override("font_color", f.card_text)
	line.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	line.add_theme_constant_override("outline_size", 4)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size.x = f.chat_width
	_log.add_child(line)
	while _log.get_child_count() > f.chat_lines:
		var old := _log.get_child(0)
		_log.remove_child(old)
		old.queue_free()
	var fade := line.create_tween()
	fade.tween_interval(f.chat_life)
	fade.tween_property(line, "modulate:a", 0.0, f.chat_fade)
	fade.tween_callback(func() -> void:
		if is_instance_valid(line) and line.get_parent() == _log:
			_log.remove_child(line)
			line.queue_free()
			_layout())
	if DisplayServer.get_name() != "headless":
		_sound.stream = _blip
		_sound.volume_db = f.chat_blip_db
		_sound.play()
	_layout()


## Bottom left: the box at the bottom, the log just above it.
func _layout() -> void:
	var f := FEEDBACK
	var k := size.y / 1080.0 if size.y > 0.0 else 1.0
	var bottom := size.y - f.chat_margin * k
	_edit.size = _edit.get_combined_minimum_size()
	_edit.position = Vector2(f.chat_margin * k, bottom - _edit.size.y)
	_log.size = _log.get_combined_minimum_size()
	_log.position = Vector2(f.chat_margin * k, bottom - _edit.size.y - 6.0 - _log.size.y)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()
