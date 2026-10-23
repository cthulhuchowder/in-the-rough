class_name ScorecardView
extends PanelContainer
## The server's scorecard as one wide card in the HUD's look (dark, see-through, thin separators):
## hole numbers 1..N and the PAR row in muted text, then a row per player (avatar and name, each
## hole against par: "−1" green, "0" muted, "+1" red, "–" unplayed) and TOTAL right-aligned: strokes
## with to par in brackets.
## Every hole of the round is shown, so the card keeps one width. The same card at hole end, while
## Tab is held and at round end (there with Play again / Leave). The rules are not on it (main shows
## them top right while Tab is held).

signal play_again_pressed
signal leave_pressed

const FEEDBACK: FeedbackParams = preload("res://data/feedback.tres")

var showing := "" ## "", "hole", "full" or "summary"
var round_pars: Array = [] ## par of every hole of the round (the client's course); the card's own for those played

var _box := VBoxContainer.new()


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = FEEDBACK.card_panel
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	add_theme_stylebox_override("panel", style)
	add_child(_box)
	_box.add_theme_constant_override("separation", 0)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	hide()


static func to_par(card: Dictionary, row: Dictionary) -> int:
	var total := 0
	for i in row.scores.size():
		if row.scores[i] >= 0:
			total += int(row.scores[i]) - int(card.pars[i])
	return total


static func par_text(d: int) -> String:
	return "E" if d == 0 else "%+d" % d


func show_hole(card: Dictionary, number: int) -> void:
	_show("hole", _hole_title(card, number), card)


func show_full(card: Dictionary, number: int) -> void:
	_show("full", _hole_title(card, number), card)


func show_summary(card: Dictionary, is_host: bool, me := 0) -> void:
	var rows: Array = card.rows.duplicate()
	rows.sort_custom(func(a, b): return to_par(card, a) < to_par(card, b))
	var winner := ""
	if not rows.is_empty():
		winner = "  ·  %s wins at %s" % [rows[0].name, par_text(to_par(card, rows[0]))]
	_show("summary", "Round over" + winner, card)
	for row in card.rows: # this player's coins for the round, by category
		if row.id == me and row.get("coins", {}).get("total", 0) > 0:
			var parts: Array[String] = []
			for k in Economy.CATEGORIES:
				if int(row.coins.get(k, 0)) > 0:
					parts.append("%s %d" % [Economy.NAMES[k], int(row.coins[k])])
			_box.add_child(_gap(8))
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 8)
			line.alignment = BoxContainer.ALIGNMENT_CENTER
			line.add_child(Hud.coin_icon(18.0))
			line.add_child(_label("%d coins  ·  %s" % [int(row.coins.total), "  ·  ".join(parts)], FEEDBACK.card_text, 0.0))
			_box.add_child(line)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	_box.add_child(_gap(10))
	_box.add_child(buttons)
	var again := Button.new()
	again.text = "Play again (new course)" if is_host else "Waiting for the host to play again"
	again.disabled = not is_host
	again.focus_mode = Control.FOCUS_NONE
	again.pressed.connect(play_again_pressed.emit)
	buttons.add_child(again)
	var leave := Button.new()
	leave.text = "Leave room"
	leave.focus_mode = Control.FOCUS_NONE
	leave.pressed.connect(leave_pressed.emit)
	buttons.add_child(leave)


func close() -> void:
	showing = ""
	hide()


func _hole_title(card: Dictionary, number: int) -> String:
	var pars := _pars(card)
	return "Hole %d · Par %d" % [number, pars[number - 1]] if number >= 1 and number <= pars.size() else "Hole %d" % number


## Pars of every hole of the round: the card's for those played, the course's for the rest.
func _pars(card: Dictionary) -> Array:
	var pars: Array = card.pars.duplicate()
	var holes := int(card.get("rules", {}).get("holes", round_pars.size())) # (the course may run longer than the round)
	for i in range(pars.size(), holes):
		pars.append(round_pars[i] if i < round_pars.size() else -1)
	return pars


func _show(kind: String, title: String, card: Dictionary) -> void:
	showing = kind
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	var f := FEEDBACK
	var heading := _label(title, f.card_text, 0.0, HORIZONTAL_ALIGNMENT_CENTER)
	heading.add_theme_font_size_override("font_size", 22)
	_box.add_child(heading)
	_box.add_child(_gap(8))
	var pars := _pars(card)
	var header := _row()
	header.add_child(_label("HOLE", f.card_muted, f.card_name_width))
	for i in pars.size():
		header.add_child(_label(str(i + 1), f.card_muted, f.card_cell.x, HORIZONTAL_ALIGNMENT_CENTER))
	header.add_child(_label("TOTAL", f.card_muted, f.card_total_width, HORIZONTAL_ALIGNMENT_RIGHT))
	_box.add_child(_line())
	var par_row := _row()
	par_row.add_child(_label("PAR", f.card_muted, f.card_name_width))
	var par_sum := 0
	for p in pars:
		par_row.add_child(_label(str(p) if p > 0 else "–", f.card_muted, f.card_cell.x, HORIZONTAL_ALIGNMENT_CENTER))
		par_sum += maxi(int(p), 0)
	par_row.add_child(_label(str(par_sum), f.card_muted, f.card_total_width, HORIZONTAL_ALIGNMENT_RIGHT))
	for row in card.rows:
		_box.add_child(_line())
		var line := _row()
		line.add_child(_player(row))
		var strokes := 0
		for i in pars.size():
			var s: int = row.scores[i] if i < row.scores.size() else -1
			strokes += maxi(s, 0)
			var played: bool = s >= 0 and i < card.pars.size()
			var rel: int = s - int(card.pars[i]) if played else 0 # per hole: against par, "−1" "0" "+1"
			var shown := ("0" if rel == 0 else ("+%d" % rel if rel > 0 else "−%d" % -rel)) if played else "–"
			line.add_child(_label(shown, f.card_muted if not played or rel == 0 else _ink(rel), f.card_cell.x, HORIZONTAL_ALIGNMENT_CENTER))
		var total := to_par(card, row)
		line.add_child(_label("%d (%s)" % [strokes, par_text(total)], _ink(total), f.card_total_width, HORIZONTAL_ALIGNMENT_RIGHT))
	show()


## Score colour against par: under green, over red, level plain.
func _ink(to_par_d: int) -> Color:
	return FEEDBACK.card_text if to_par_d == 0 else (FEEDBACK.card_good if to_par_d < 0 else FEEDBACK.card_bad)


func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.custom_minimum_size.y = FEEDBACK.card_cell.y
	_box.add_child(row)
	return row


## A thin separator between rows.
func _line() -> ColorRect:
	var line := ColorRect.new()
	line.color = FEEDBACK.card_line
	line.custom_minimum_size.y = 1
	return line


func _gap(height: float) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size.y = height
	return gap


func _label(text: String, ink: Color, width: float, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size.x = width
	label.clip_text = width > 0.0
	label.add_theme_color_override("font_color", ink)
	return label


## A player's avatar (no pictures yet): a disc in a colour of their own (from their id), their initial.
static func avatar(player_name: String, id: int, diameter: float) -> PanelContainer:
	var disc := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color.from_hsv(fmod(float(id) * 0.618034, 1.0), 0.4, 0.7)
	style.set_corner_radius_all(int(diameter * 0.5))
	disc.add_theme_stylebox_override("panel", style)
	disc.custom_minimum_size = Vector2.ONE * diameter
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var initial := Label.new()
	initial.text = player_name.left(1).to_upper()
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.add_theme_color_override("font_color", Color.WHITE)
	initial.add_theme_font_size_override("font_size", int(diameter * 0.6))
	disc.add_child(initial)
	return disc


## Avatar and the name.
func _player(row: Dictionary) -> HBoxContainer:
	var f := FEEDBACK
	var cell := HBoxContainer.new()
	cell.add_theme_constant_override("separation", 8)
	cell.custom_minimum_size.x = f.card_name_width
	cell.add_child(avatar(row.name, row.get("id", 0), f.card_avatar))
	var name := _label(row.name, f.card_text, f.card_name_width - f.card_avatar - 8.0)
	cell.add_child(name)
	return cell
