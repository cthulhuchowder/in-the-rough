class_name Hud
extends Control
## The player's HUD, in the scorecard's look (dark see-through, muted text): top left a narrow pill
## "Shot N · Par P · D m" and right under it, in the same look at chip_size and fitting its own text, the club pill "D · 218 m"
## (short name, carry for the lie), which pulses for a caddy pick. Full-rect, ignores
## the mouse. main fills it every frame (show_state()).

const FEEDBACK: FeedbackParams = preload("res://data/feedback.tres")

var pulse_tween: Tween ## the caddy pulse while it runs

var _pill := PanelContainer.new()
var _line := Label.new()
var _chip := PanelContainer.new()
var _coin_pill := PanelContainer.new() # top right: a flat coin and the balance
var _coin_label := Label.new()
var _pop := Label.new() # "+25", rising and fading under it
var _pop_tween: Tween
var _club := Label.new()


func _ready() -> void:
	var f := FEEDBACK
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.add_theme_stylebox_override("panel", _box(f.hud_height, f.hud_padding))
	_pill.custom_minimum_size.y = f.hud_height
	_pill.position = Vector2.ONE * f.hud_margin
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pill)
	_line.add_theme_color_override("font_color", f.card_muted)
	_line.add_theme_font_size_override("font_size", f.hud_line_font)
	_line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pill.add_child(_line)
	var k := f.chip_size # the shot pill's look, a little smaller
	_chip.add_theme_stylebox_override("panel", _box(f.hud_height * k, f.hud_padding * k))
	_chip.custom_minimum_size.y = f.hud_height * k
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chip)
	_club.add_theme_color_override("font_color", f.card_muted)
	_club.add_theme_font_size_override("font_size", roundi(f.hud_line_font * k))
	_club.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_club.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_chip.add_child(_club)
	# Top right: the coin balance (hidden until the server sends it)
	_coin_pill.add_theme_stylebox_override("panel", _box(f.hud_height, f.hud_padding))
	_coin_pill.custom_minimum_size.y = f.hud_height
	_coin_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coin_pill.hide()
	add_child(_coin_pill)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_coin_pill.add_child(row)
	row.add_child(coin_icon(f.hud_height * 0.62))
	_coin_label.add_theme_color_override("font_color", f.card_text)
	_coin_label.add_theme_font_size_override("font_size", f.hud_line_font)
	_coin_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_coin_label)
	_pop.add_theme_color_override("font_color", f.coin_color)
	_pop.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	_pop.add_theme_constant_override("outline_size", 4)
	_pop.add_theme_font_size_override("font_size", f.hud_line_font + 6)
	_pop.modulate.a = 0.0
	add_child(_pop)


## This frame's values.
func show_state(shot: int, par: int, to_pin: float, club: String, carry: String, line := "") -> void:
	_line.text = line if line != "" else "Shot %d · Par %d · %d m" % [shot, par, roundi(to_pin)] # (practice says where it is)
	_club.text = "%s · %s" % [club, carry]
	# Each pill fits its text; the chip just under the shot pill, both left-aligned
	_pill.size = _pill.get_combined_minimum_size()
	_chip.size = _chip.get_combined_minimum_size()
	_chip.position = Vector2(_pill.position.x, _pill.position.y + _pill.size.y + FEEDBACK.chip_gap)
	_chip.pivot_offset = Vector2(0.0, _chip.size.y * 0.5) # the pulse swells from its left edge, staying aligned


## The coin balance, top right (negative: not known yet, hidden).
func set_coins(balance: int) -> void:
	_coin_pill.visible = balance >= 0
	if balance < 0:
		return
	_coin_label.text = str(balance)
	_coin_pill.size = _coin_pill.get_combined_minimum_size()
	_coin_pill.position = Vector2(size.x - FEEDBACK.hud_margin - _coin_pill.size.x, FEEDBACK.hud_margin)


## "+N" rising out of the coin pill and fading.
func pop_coins(amount: int) -> void:
	_pop.text = "+%d" % amount
	_pop.size = _pop.get_combined_minimum_size()
	var start := Vector2(size.x - FEEDBACK.hud_margin - _pop.size.x, FEEDBACK.hud_margin + FEEDBACK.hud_height + 4.0)
	_pop.position = start
	if _pop_tween:
		_pop_tween.kill()
	_pop.modulate.a = 1.0
	_pop_tween = create_tween()
	_pop_tween.tween_property(_pop, "position:y", start.y + 26.0, 1.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_pop_tween.parallel().tween_property(_pop, "modulate:a", 0.0, 1.4).set_delay(0.5)


func coins_bottom() -> float:
	return _coin_pill.position.y + _coin_pill.size.y if _coin_pill.visible else 0.0


## A flat coin: a gold disc, a darker inner ring, a light glint.
static func coin_icon(diameter: float) -> Control:
	var f := FEEDBACK
	var disc := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = f.coin_color
	style.border_color = f.coin_color.darkened(0.3)
	style.set_border_width_all(maxi(1, int(diameter * 0.12)))
	style.set_corner_radius_all(int(diameter * 0.5))
	disc.add_theme_stylebox_override("panel", style)
	disc.custom_minimum_size = Vector2.ONE * diameter
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return disc


## The caddy's pick: the chip swells and brightens chip_pulse_count times; a new pick restarts it.
func pulse() -> void:
	var f := FEEDBACK
	if pulse_tween:
		pulse_tween.kill()
	_chip.scale = Vector2.ONE
	_chip.modulate = Color.WHITE
	pulse_tween = create_tween()
	for i in f.chip_pulse_count:
		pulse_tween.tween_property(_chip, "scale", Vector2.ONE * f.chip_pulse_scale, f.chip_pulse_time * 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
		pulse_tween.parallel().tween_property(_chip, "modulate", Color(1.35, 1.35, 1.35), f.chip_pulse_time * 0.5)
		pulse_tween.tween_property(_chip, "scale", Vector2.ONE, f.chip_pulse_time * 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		pulse_tween.parallel().tween_property(_chip, "modulate", Color.WHITE, f.chip_pulse_time * 0.5)


func chip_scale() -> float:
	return _chip.scale.x


func panel_bottom() -> float:
	return _chip.position.y + _chip.size.y


## A pill: fully rounded ends, `padding` px left and right.
func _box(height: float, padding: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = FEEDBACK.card_panel
	box.set_corner_radius_all(int(height * 0.5))
	box.content_margin_left = padding
	box.content_margin_right = padding
	return box
