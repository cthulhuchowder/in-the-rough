class_name ClubWheel
extends Control
## Radial club picker (hold Q): one chunky beveled slice per club in bag order, clockwise from
## the top, each with the club's icon, code and full-power carry. Mouse motion moves a cursor
## from the centre; past the deadzone its direction highlights a slice. The caller opens it,
## feeds it look input, and reads `selected` on release.

var params: FeedbackParams
var clubs: Array[ClubData] = []
var carries := PackedStringArray() ## per club, e.g. "212 m"
var selected := -1

var _cursor := Vector2.ZERO
var _current := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()


func open(current: int) -> void:
	_current = current
	selected = current
	_cursor = Vector2.ZERO
	show()
	queue_redraw()


func close() -> void:
	hide()


## Mouse travel this tick (pixels); direction past the deadzone picks the slice.
func steer(motion: Vector2) -> void:
	if not visible or motion == Vector2.ZERO:
		return
	_cursor = (_cursor + motion).limit_length(params.wheel_outer)
	if _cursor.length() > params.wheel_deadzone:
		var step := TAU / clubs.size()
		var a := fposmod(atan2(_cursor.x, -_cursor.y), TAU) # 0 at the top, clockwise
		selected = int(round(a / step)) % clubs.size()
	queue_redraw()


func _draw() -> void:
	var k := size.y / 1080.0
	if k <= 0.0:
		return # no window (headless)
	var centre := size * 0.5
	var outer := params.wheel_outer * k
	var inner := params.wheel_inner * k
	var step := TAU / clubs.size()
	var font := ThemeDB.fallback_font
	for i in clubs.size():
		var mid := i * step
		var lit := i == selected
		var pop := Vector2(sin(mid), -cos(mid)) * (params.wheel_pop * k if lit else 0.0)
		var gap := params.wheel_gap * k
		var bevel := params.wheel_bevel * k
		# Chunky bevel: the darker rim, then the face inset inside it.
		draw_colored_polygon(_sector(centre + pop, inner, outer, mid, step, gap), params.wheel_rim)
		var face := params.wheel_highlight if lit else params.wheel_slice
		draw_colored_polygon(_sector(centre + pop, inner + bevel, outer - bevel, mid, step, gap + bevel), face)
		var spot := centre + pop + Vector2(sin(mid), -cos(mid)) * (inner + outer) * 0.5
		_icon(spot + Vector2(0, -16.0 * k), clubs[i].model, k)
		_text(font, spot + Vector2(0, 22.0 * k), clubs[i].label, int(24 * k))
		_text(font, spot + Vector2(0, 46.0 * k), carries[i], int(17 * k))
	var name := clubs[selected].label if selected >= 0 else clubs[_current].label
	_text(font, centre + Vector2(0, 10.0 * k), name, int(40 * k))


func _text(font: Font, at: Vector2, text: String, font_size: int) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, at - Vector2(width * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, params.wheel_text)


## Annulus sector centred on angle `mid` (0 = up, clockwise), `gap` px trimmed off each side.
static func _sector(centre: Vector2, r0: float, r1: float, mid: float, step: float, gap: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var segments := 6
	for s in segments + 1:
		var a := mid - step * 0.5 + gap / r1 + (step - 2.0 * gap / r1) * s / segments
		points.append(centre + Vector2(sin(a), -cos(a)) * r1)
	for s in range(segments, -1, -1):
		var a := mid - step * 0.5 + gap / r0 + (step - 2.0 * gap / r0) * s / segments
		points.append(centre + Vector2(sin(a), -cos(a)) * r0)
	return points


## Little flat club glyph: a shaft and a head shaped like the club's model.
func _icon(at: Vector2, model: ClubData.Model, k: float) -> void:
	var c := params.wheel_icon
	draw_line(at + Vector2(7, -22) * k, at + Vector2(-1, 12) * k, c, 3.0 * k)
	var head: PackedVector2Array
	match model:
		ClubData.Model.DRIVER:
			head = PackedVector2Array([Vector2(-1, 8), Vector2(-14, 10), Vector2(-17, 16), Vector2(-12, 21),
				Vector2(0, 21), Vector2(3, 15)])
		ClubData.Model.IRON:
			head = PackedVector2Array([Vector2(1, 9), Vector2(-15, 15), Vector2(-15, 20), Vector2(2, 19)])
		ClubData.Model.WEDGE:
			head = PackedVector2Array([Vector2(1, 8), Vector2(-15, 12), Vector2(-17, 20), Vector2(3, 20)])
		_:
			head = PackedVector2Array([Vector2(-1, 12), Vector2(1, 12), Vector2(1, 16), Vector2(9, 16),
				Vector2(9, 21), Vector2(-15, 21), Vector2(-15, 16), Vector2(-1, 16)])
	for i in head.size():
		head[i] = at + head[i] * k
	draw_colored_polygon(head, c)
