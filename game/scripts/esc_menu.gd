class_name EscMenu
extends Control
## Esc: the pause/settings overlay, in the project look (the power meter's flat, rounded panel).
## Resume, Reset to tee (offline), Settings, Leave round, Quit; offline the course seed (selectable,
## to play it again) and the game pauses; online the round runs on and the swing is blocked while
## it's open.
## Settings apply the moment they change (autoload Settings saves them).

const FEEDBACK: FeedbackParams = preload("res://data/feedback.tres")

const SOUNDS: SoundParams = preload("res://data/sounds.tres")
var main: Node ## Main: its gesture, club wheel, seed field and leave (null: the menu's settings page alone)

var _panel := PanelContainer.new()
var _home := VBoxContainer.new()
var _settings := VBoxContainer.new()
var _seed := LineEdit.new()
var _debug := CheckBox.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # works while the game is paused
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = theme_of()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_panel)
	var both := VBoxContainer.new()
	both.add_child(_home)
	both.add_child(_settings)
	_panel.add_child(both)
	_build_home()
	_build_settings()
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		return
	if main == null: # the menu's settings: Esc closes them
		if visible:
			visible = false
			get_viewport().set_input_as_handled()
		return
	if main._wheel.visible:
		return # the club wheel takes Esc first
	if visible and _settings.visible:
		_show_settings(false)
	else:
		open(not visible)
	get_viewport().set_input_as_handled()


func open(show: bool) -> void:
	visible = show
	_show_settings(false)
	main._swing.gesture.blocked = show
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if show else Input.MOUSE_MODE_CAPTURED
	if not Net.online() or Net.local: # (single player's server is in this tree: it pauses too)
		get_tree().paused = show
	_seed.text = main._seed_field.text
	_seed.visible = not Net.online()
	_debug.set_pressed_no_signal(Settings.show_debug)


## The main menu's Settings: this overlay's settings page on its own (Back closes it).
func show_settings_only() -> void:
	visible = true
	_show_settings(true)


func _show_settings(show: bool) -> void:
	_home.visible = not show
	_settings.visible = show


func _build_home() -> void:
	_home.add_theme_constant_override("separation", 10)
	_home.add_child(_title("Paused"))
	var hint := Label.new()
	hint.text = "Course seed (F3 seed field plays it again):"
	_home.add_child(hint)
	_seed.editable = false # still selectable, to copy
	_seed.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seed.custom_minimum_size.x = 280
	_home.add_child(_seed)
	for item in [["Resume", func(): open(false)], ["Reset to tee", _reset_to_tee], ["Settings", func(): _show_settings(true)],
			["Leave round", _leave_round], ["Quit", func(): get_tree().quit()]]:
		var button := Button.new()
		button.text = item[0]
		button.custom_minimum_size = Vector2(280, 44)
		button.pressed.connect(item[1])
		_home.add_child(button)
		if item[0] == "Reset to tee":
			button.visible = not Net.online() # online the server owns the ball
	hint.visible = not Net.online()


func _build_settings() -> void:
	_settings.add_theme_constant_override("separation", 8)
	_settings.add_child(_title("Settings"))
	var range: Vector2 = (main._swing.feel if main else (load("res://data/swing_feel.tres") as SwingFeel)).sensitivity_range
	for row in [["Sensitivity: driver & woods", "sensitivity_woods"], ["Sensitivity: irons & wedges", "sensitivity_irons"],
			["Sensitivity: putter", "sensitivity_putter"]]:
		_slider(row[0], row[1], range.x, range.y, 0.05, "%.2f")
	_slider("Master volume", "master_volume", 0.0, 1.0, 0.01, "%.0f%%", 100.0)
	_slider("Sound effects", "sfx_volume", 0.0, 1.0, 0.01, "%.0f%%", 100.0)
	_slider("Ambience", "ambience_volume", 0.0, 1.0, 0.01, "%.0f%%", 100.0)
	var invert := CheckBox.new()
	invert.text = "Invert vertical"
	invert.button_pressed = Settings.invert_vertical
	invert.toggled.connect(func(on: bool): Settings.change("invert_vertical", on))
	_settings.add_child(invert)
	var caddy := CheckBox.new()
	caddy.text = "Auto caddy (picks a club for each new lie)"
	caddy.button_pressed = Settings.auto_caddy
	caddy.toggled.connect(func(on: bool): Settings.change("auto_caddy", on))
	_settings.add_child(caddy)
	var shadows := HBoxContainer.new()
	var shadows_label := Label.new()
	shadows_label.text = "Shadow quality"
	shadows_label.custom_minimum_size.x = 250
	shadows.add_child(shadows_label)
	var pick := OptionButton.new()
	for level in ["Low", "Medium", "High"]:
		pick.add_item(level)
	pick.select(Settings.shadow_quality)
	pick.item_selected.connect(func(i: int): Settings.change("shadow_quality", i))
	shadows.add_child(pick)
	_settings.add_child(shadows)
	_debug.text = "Show debug (F3)"
	_debug.toggled.connect(func(on: bool): Settings.change("show_debug", on))
	_settings.add_child(_debug)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(280, 44)
	back.pressed.connect(func():
		_back_sound()
		if main == null:
			visible = false # (the menu's settings: back to the menu)
		else:
			_show_settings(false))
	_settings.add_child(back)


## A labelled slider bound to one setting; its value shown as `format` of value × `shown`.
func _slider(label: String, key: String, from: float, to: float, step: float, format: String, shown := 1.0) -> void:
	var row := HBoxContainer.new()
	var name := Label.new()
	name.text = label
	name.custom_minimum_size.x = 250
	row.add_child(name)
	var slider := HSlider.new()
	slider.min_value = from
	slider.max_value = to
	slider.step = step
	slider.value = Settings.get(key)
	slider.custom_minimum_size = Vector2(220, 28)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var value := Label.new()
	value.custom_minimum_size.x = 60
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.text = format % (slider.value * shown)
	row.add_child(value)
	slider.value_changed.connect(func(v: float) -> void:
		value.text = format % (v * shown)
		Settings.change(key, v))
	_settings.add_child(row)


func _title(text: String) -> Label:
	var title := Label.new()
	title.text = text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	return title


## Offline: the hole starts over from the tee (R only re-addresses).
func _reset_to_tee() -> void:
	open(false)
	main.restart()


func _leave_round() -> void:
	get_tree().paused = false
	main._swing.gesture.blocked = false
	if Net.online():
		main._leave()
	else:
		get_tree().change_scene_to_file("res://lobby.tscn")


## Flat, rounded, in the HUD palette (FeedbackParams' meter colors).
static func theme_of() -> Theme:
	var p: FeedbackParams = FEEDBACK
	var t := Theme.new()
	var panel := _box(p.meter_back, p.meter_frame, 12, 22)
	t.set_stylebox("panel", "PanelContainer", panel)
	for state in [["normal", p.meter_back.lightened(0.12)], ["hover", p.meter_back.lightened(0.24)],
			["pressed", p.meter_power], ["focus", p.meter_back.lightened(0.24)]]:
		t.set_stylebox(state[0], "Button", _box(state[1], p.meter_frame, 10, 8))
	# Check rows (Invert vertical, Auto caddy, Show debug): boxed like the other rows in every state;
	# hover lightens a little; checked shows only by its tick; focus is the outline, drawn over the rest
	var row := p.meter_back.lightened(0.12)
	var row_hover := p.meter_back.lightened(0.2)
	for state in [["normal", row], ["pressed", row], ["hover", row_hover], ["hover_pressed", row_hover], ["disabled", row]]:
		t.set_stylebox(state[0], "CheckBox", _box(state[1], p.meter_frame, 10, 8))
	t.set_stylebox("focus", "CheckBox", _box(Color.TRANSPARENT, p.meter_frame, 10, 8))
	for state in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(state, "CheckBox", p.meter_peak)
	t.set_color("font_color", "Button", p.meter_peak)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_color", "Label", p.meter_peak)
	t.set_color("font_color", "CheckBox", p.meter_peak)
	t.set_font_size("font_size", "Button", 20)
	t.set_font_size("font_size", "Label", 18)
	t.set_font_size("font_size", "CheckBox", 18)
	return t


static func _box(fill: Color, frame: Color, radius: int, margin: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = frame
	box.set_border_width_all(3)
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(margin)
	return box


## Back: the soft back blip (data/sounds.tres), on its own player.
func _back_sound() -> void:
	var player := AudioStreamPlayer.new()
	player.bus = Settings.SFX_BUS
	player.stream = SOUNDS.ui_back
	player.volume_db = SOUNDS.ui_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
