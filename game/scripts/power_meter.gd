class_name PowerMeter
extends Control
## Vertical power bar: a new maximum sets the bar and a hold (0.5 s at the
## values); readings between bar and maximum raise the bar; once the hold runs out, or as soon as
## the swing goes backwards, bar and maximum fall to zero over fall_time with a sine ease-out.
## At impact it shows the hit's power until the next address. Beside it, the spin bar during an
## iron or wedge flight. Flat, chunky, rounded: the project look.

var params: FeedbackParams
var bar := 0.0
var peak := 0.0
var spin := 0.0
var spin_visible := false

var _hold := 0.0
var _frozen := false
var _fall_t := -1.0 # s into a fall; −1 when not falling
var _fall_bar := 0.0
var _fall_peak := 0.0
var _fall_with_peak := false
var _back := StyleBoxFlat.new()
var _fill := StyleBoxFlat.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.bg_color = params.meter_back
	_back.border_color = params.meter_frame
	_fill.bg_color = params.meter_power


## One swing tick: power 0..1 and whether the swing angle fell this tick.
func update(power: float, falling: bool, delta: float) -> void:
	if _frozen:
		return
	_hold = maxf(0.0, _hold - params.meter_hold_decay * delta)
	if falling:
		_start_fall(true)
	elif power > params.meter_min_power:
		if power > peak:
			peak = power
			bar = power
			_hold = params.meter_hold
			_fall_t = -1.0
		elif power > bar:
			bar = power
			_fall_t = -1.0
	elif _hold <= 0.0 and bar > 0.0:
		_start_fall(false)
	if _fall_t >= 0.0:
		_fall_t += delta
		var eased := sin(minf(_fall_t / params.meter_fall_time, 1.0) * PI * 0.5)
		bar = _fall_bar * (1.0 - eased)
		if _fall_with_peak:
			peak = _fall_peak * (1.0 - eased)
		if _fall_t >= params.meter_fall_time:
			_fall_t = -1.0
	queue_redraw()


## Impact: show the hit's power and stop following the swing until release().
func on_hit(power: float) -> void:
	bar = power
	peak = maxf(peak, power)
	_fall_t = -1.0
	_frozen = true
	queue_redraw()


## Next address: the bar follows the swing again (and so decays from the last shot).
func release() -> void:
	_frozen = false
	spin_visible = false
	queue_redraw()


func _start_fall(with_peak: bool) -> void:
	if _fall_t >= 0.0 and (_fall_with_peak or not with_peak):
		return # already falling
	_fall_bar = bar
	_fall_peak = peak
	_fall_with_peak = with_peak
	_fall_t = 0.0


## The power bar on screen (the spin bar shows 1.6 bar widths left of it).
func bar_rect() -> Rect2:
	var k := size.y / 1080.0
	var bar_size := params.meter_size * k
	return Rect2(Vector2(size.x - params.meter_margin * k - bar_size.x, (size.y - bar_size.y) * 0.5), bar_size)


func _draw() -> void:
	if size.y <= 0.0:
		return # no window (headless)
	var rect := bar_rect()
	_column(rect.position, rect.size, bar, params.meter_power, peak)
	if spin_visible:
		_column(rect.position - Vector2(rect.size.x * 1.6, 0), rect.size, spin, params.meter_spin, -1.0)


func _column(origin: Vector2, bar_size: Vector2, value: float, color: Color, mark: float) -> void:
	var k := size.y / 1080.0
	var radius := int(bar_size.x * 0.35)
	_back.set_corner_radius_all(radius)
	_back.set_border_width_all(int(maxf(2.0, 3.0 * k)))
	draw_style_box(_back, Rect2(origin, bar_size))
	var inset := 5.0 * k
	var inner := Rect2(origin + Vector2(inset, inset), bar_size - Vector2(inset, inset) * 2.0)
	var fill_h := inner.size.y * clampf(value, 0.0, 1.0)
	if fill_h > 1.0:
		_fill.bg_color = color
		_fill.set_corner_radius_all(int(maxf(1.0, radius - inset)))
		draw_style_box(_fill, Rect2(Vector2(inner.position.x, inner.end.y - fill_h), Vector2(inner.size.x, fill_h)))
	if mark > 0.0:
		var y := inner.end.y - inner.size.y * clampf(mark, 0.0, 1.0)
		draw_rect(Rect2(Vector2(inner.position.x - inset * 0.5, y - 1.5 * k), Vector2(inner.size.x + inset, 3.0 * k)), params.meter_peak)
