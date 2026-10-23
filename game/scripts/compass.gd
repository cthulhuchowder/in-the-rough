class_name Compass
extends Control
## Hole compass: a thin horizontal dial at the top centre of the HUD, centred on the current aim.
## Markers sit at their bearing from the ball (pin, tee); one past the dial's span is pinned to its
## edge as an arrow. The pin's distance shows under its marker.
## Wind has a badge left of the dial: an arrow the way it blows relative to the aim, and its speed.
## Flat, chunky, rounded: the project look.

var params: FeedbackParams
## [{bearing: rad (+ = right of aim), color: Color, shape: "flag", "tee" or "wind", label: String}]
var markers: Array[Dictionary] = []

var _back := StyleBoxFlat.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.bg_color = params.meter_back
	_back.border_color = params.meter_frame


## Bearing (rad, + = to the right) of `to` from `from` relative to the `aim` heading, on the ground.
static func bearing(aim: Vector3, from: Vector3, to: Vector3) -> float:
	var d := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var a := Vector3(aim.x, 0.0, aim.z)
	if d.length() < 0.001 or a.length() < 0.001:
		return 0.0
	return -a.signed_angle_to(d, Vector3.UP) # signed_angle_to is + counter-clockwise from above: left


func _draw() -> void:
	var k := size.y / 1080.0
	if k <= 0.0:
		return # no window (headless)
	var dial := params.compass_size * k
	var rect := Rect2(Vector2((size.x - dial.x) * 0.5, params.compass_margin * k), dial)
	_back.set_corner_radius_all(int(dial.y * 0.5))
	_back.set_border_width_all(int(maxf(2.0, 2.0 * k)))
	draw_style_box(_back, rect)
	var half := deg_to_rad(params.compass_span_deg) * 0.5
	var mid := rect.get_center()
	var per_rad := (dial.x * 0.5 - dial.y * 0.5) / half
	# Ticks every 15°, longer every 45°, and the aim notch in the middle.
	for deg in range(-int(params.compass_span_deg / 2.0) / 15 * 15, int(params.compass_span_deg / 2.0) + 1, 15):
		var x := mid.x + deg_to_rad(deg) * per_rad
		var h := dial.y * (0.5 if deg % 45 == 0 else 0.28)
		draw_rect(Rect2(Vector2(x - 1.0 * k, mid.y - h * 0.5), Vector2(2.0 * k, h)), params.compass_tick)
	draw_colored_polygon(PackedVector2Array([Vector2(mid.x - 6 * k, rect.end.y + 7 * k), Vector2(mid.x + 6 * k, rect.end.y + 7 * k),
		Vector2(mid.x, rect.end.y)]), params.compass_tick)
	var font := get_theme_default_font()
	var font_size := int(params.compass_font * k)
	for m in markers:
		var b: float = m.bearing
		if m.shape == "wind": # its own badge left of the dial: an arrow the way it blows (up = along the aim)
			var at := Vector2(rect.position.x - dial.y * 1.4, mid.y)
			draw_circle(at, dial.y * 0.85, params.meter_back)
			draw_arc(at, dial.y * 0.85, 0.0, TAU, 24, params.meter_frame, maxf(2.0, 2.0 * k))
			var d := Vector2(sin(b), -cos(b)) * dial.y * 0.6
			var side := Vector2(-d.y, d.x) * 0.45
			draw_line(at - d, at + d * 0.3, m.color, maxf(2.0, 3.0 * k))
			draw_colored_polygon(PackedVector2Array([at + d, at + d * 0.2 + side, at + d * 0.2 - side]), m.color)
			_label(font, font_size, at.x, rect.end.y + 9 * k + font_size, m.get("label", ""), m.color, k)
			continue
		var x := mid.x + clampf(b, -half, half) * per_rad
		var c: Color = m.color
		if absf(b) > half: # off the dial: an arrow at its edge, pointing the way to turn
			var s := signf(b)
			var tip := Vector2(rect.position.x if s < 0.0 else rect.end.x, mid.y) + Vector2(s * 4.0 * k, 0)
			draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-s * 10 * k, -7 * k), tip + Vector2(-s * 10 * k, 7 * k)]), c)
			x = tip.x - s * 18.0 * k
		elif m.shape == "flag": # pole and pennant
			draw_rect(Rect2(Vector2(x - 1.5 * k, mid.y - dial.y * 0.42), Vector2(3.0 * k, dial.y * 0.84)), params.compass_tick)
			draw_colored_polygon(PackedVector2Array([Vector2(x + 1.5 * k, mid.y - dial.y * 0.42), Vector2(x + 12 * k, mid.y - dial.y * 0.22),
				Vector2(x + 1.5 * k, mid.y - dial.y * 0.02)]), c)
		else: # tee: a small square
			draw_rect(Rect2(Vector2(x - 5 * k, mid.y - 5 * k), Vector2(10 * k, 10 * k)), c)
		_label(font, font_size, x, rect.end.y + 9 * k + font_size, m.get("label", ""), c, k)


## Outlined text centred on x.
func _label(font: Font, font_size: int, x: float, y: float, text: String, color: Color, k: float) -> void:
	if text == "":
		return
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
	draw_string_outline(font, Vector2(x - w * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, int(4 * k), params.meter_frame)
	draw_string(font, Vector2(x - w * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
