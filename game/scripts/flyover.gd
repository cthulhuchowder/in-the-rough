class_name Flyover
extends Node
## The hole flyover: first a hold on black (the first frame frozen, "Loading..." and a progress bar)
## until the hole is fully built (release(); a skip then waits for it); then from behind and above the
## tee, along the hole's centreline
## (so it follows doglegs) at one altitude above the tee (no terrain bobbing), curving
## tangent-matched into a slow half-orbit round the pin, then a cut to the shooting camera: one
## continuous spline, constant arc-length speed under one ease-in-out. The view rides its own
## spline ahead on the fairway, then holds the pin. A hole card fades in bottom-left (number, par,
## length, biome, wind). Any key skips it. Emits `finished` (skipped or not) and frees itself.

signal finished
signal hold_ended ## the opening hold is over (the flight starts, or it was skipped)

const FEEDBACK: FeedbackParams = preload("res://data/feedback.tres")

var params: FlyoverParams

var _camera: Camera3D
var _hole: Hole
var _end: Transform3D
var _eye := Curve3D.new()
var _pin: Vector3
var _orbit_from := 0.0 # offset along _eye where the orbit round the pin begins
var _look := Curve3D.new() # what it looks at: the same ground path at look height
var _orbit_time := 0.0 # s in when the eye reaches the orbit
var _t := 0.0
var _done := false
var _layer := CanvasLayer.new()
var _card := PanelContainer.new()
var _accent := "" # the biome's name on the card, in _accent_color
var _accent_color := Color.WHITE
var _black := ColorRect.new() # the opening hold's cover, fading out as the flight starts
var _loading := Label.new() # "Loading..." during the hold
var _holding := true
var _held := 0.0
## The opening hold lasts until release() (main calls it on the hole's `built`); 0..1 for the bar meanwhile.
var progress: Callable
var _released := false
## During the hold: the camera shows the flight peek s in (behind the black; the shader warm-up looks
## along the path so what the flight will see is compiled first); −1 shows its start.
var peek := -1.0
var _skip_pending := false # a skip pressed during the hold
var _bar := ColorRect.new()
var _bar_fill := ColorRect.new()


## Fly `camera` over `hole`, then cut to `end` (the shooting camera). `card`: the hole's line of
## text; `wind`: the hole's wind (m/s, world) and `along`: the hole's direction, for the card's arrow;
## `accent` (the biome) follows the text in `accent_color`.
func start(camera: Camera3D, hole: Hole, end: Transform3D, card: String, wind: Vector3, along: Vector3,
		accent := "", accent_color := Color.WHITE) -> void:
	_accent = accent
	_accent_color = accent_color
	_camera = camera
	_hole = hole
	_end = end
	_build_path()
	_build_card(card, wind, along)
	_camera.global_transform = _view(0.0)


## One spline, tangent-continuous throughout: behind the tee → the centreline at tee height +
## height (Catmull-Rom handles) → leaving it orbit_blend m short of the pin on a blend segment
## that meets the orbit circle at its tangent point, heading matched both ends → a half-orbit
## round the pin (exact circular Bezier arcs). The look-at spline follows the same ground path at
## look height.
func _build_path() -> void:
	var p := params
	var line := _hole_points()
	var tee := line[0]
	var altitude := _hole.height_at(tee) + p.height
	var look_y := _hole.height_at(tee) + p.look_height
	_pin = _hole.cup.global_position
	var first := ((line[1] - tee) * Vector3(1, 0, 1)).normalized()
	var run := PackedVector3Array([Vector3(tee.x, altitude, tee.z) - first * p.back])
	for at in line:
		if _flat(at - _pin).length() < p.orbit_blend:
			break # the blend segment takes over
		run.append(Vector3(at.x, altitude, at.z))
	# Where the run leaves the centreline, and the tangent point on the orbit circle seen from there
	var leave := run[run.size() - 1]
	var out := _flat(leave - _pin)
	var d := maxf(out.length(), p.orbit_radius * 1.05)
	var r := p.orbit_radius
	var heading := _flat(leave - run[maxi(run.size() - 2, 0)]).normalized()
	var spread := acos(r / d) # angle at the pin between `leave` and either tangent point
	var away := atan2(out.z, out.x)
	var side := 1.0 if _flat(_on_circle(away + spread, r) - out).normalized().dot(heading) \
		>= _flat(_on_circle(away - spread, r) - out).normalized().dot(heading) else -1.0
	var a0 := away + side * spread # the tangent point
	var turn := signf(Vector3(-sin(a0), 0, cos(a0)).dot(_on_circle(a0, r) - out)) # on round the pin the way it came in
	var arcs := 4
	var step := deg_to_rad(p.orbit_degrees) / arcs * turn
	var hold := 4.0 / 3.0 * tan(absf(step) / 4.0) * r # circular arc handle length
	# The run: Catmull-Rom handles, flat (constant altitude), the last one aimed along the blend
	var entry := _pin + _on_circle(a0, r) + Vector3.UP * p.orbit_height
	for i in run.size():
		var next := run[i + 1] if i + 1 < run.size() else entry
		var tangent := _flat(next - run[maxi(i - 1, 0)]) / 6.0 # Catmull-Rom as Bezier handles
		_eye.add_point(run[i], -tangent, tangent)
	# The orbit: handles along the circle's tangent, so it meets the blend heading-matched
	var blend_hold := _flat(entry - leave).length() / 3.0
	for i in arcs + 1:
		var a := a0 + step * i
		var at := _pin + _on_circle(a, r) + Vector3.UP * p.orbit_height
		var along := Vector3(-sin(a), 0, cos(a)) * turn
		_eye.add_point(at, -along * (blend_hold if i == 0 else hold), along * hold)
	_eye.bake_interval = 0.5
	_orbit_from = _eye.get_closest_offset(entry)
	# Look-at: the same ground path at look height, its own smoothed spline
	var look := PackedVector3Array()
	var length := _eye.get_baked_length()
	var at_s := 0.0
	while at_s < length:
		var e := _eye.sample_baked(at_s, true)
		look.append(Vector3(e.x, look_y, e.z))
		at_s += p.path_spacing
	for i in look.size():
		var tangent := (look[mini(i + 1, look.size() - 1)] - look[maxi(i - 1, 0)]) / 6.0
		_look.add_point(look[i], -tangent, tangent)
	_look.bake_interval = 0.5
	# When (s) the eye reaches the orbit, through the ease: the look settles on the pin by then
	var lo := 0.0
	var hi := 1.0
	for i in 30:
		var mid := (lo + hi) * 0.5
		if smoothstep(0.0, 1.0, mid) * length < _orbit_from:
			lo = mid
		else:
			hi = mid
	_orbit_time = lo * p.duration


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


func _on_circle(a: float, r: float) -> Vector3:
	return Vector3(cos(a), 0, sin(a)) * r


## The centreline, tee to cup, resampled every path_spacing m (uneven samples kink the spline).
func _hole_points() -> PackedVector3Array:
	var line := _hole.centreline
	var points := PackedVector3Array([line[0]])
	var carry := 0.0
	for i in line.size() - 1:
		var a := line[i]
		var span := a.distance_to(line[i + 1])
		var d := params.path_spacing - carry
		while d <= span:
			points.append(a.lerp(line[i + 1], d / span))
			d += params.path_spacing
		carry = span - (d - params.path_spacing)
	return points


func _process(delta: float) -> void:
	if _done:
		return
	if _holding: # on black, the first frame frozen, until the hole is built (release)
		_held += delta
		_loading.modulate.a = lerpf(params.loading_pulse.x, params.loading_pulse.y, 0.5 + 0.5 * sin(TAU * _held / params.loading_pulse_time))
		_camera.global_transform = _view(peek if peek >= 0.0 else 0.0)
		_card.modulate.a = 1.0 # drawn in full under the black (see _build_card) so its text and pipelines are ready before the flight
		if progress.is_valid():
			_bar_fill.size.x = _bar.size.x * clampf(progress.call(), 0.0, 1.0)
		if _released:
			_end_hold()
			if _skip_pending:
				_finish()
		return
	_t += delta
	if _t >= params.duration:
		_finish()
		return
	_camera.global_transform = _view(_t)
	_card.modulate.a = clampf(minf(_t, params.duration - _t) / params.card_fade, 0.0, 1.0)
	_black.modulate.a = 1.0 - clampf(_t / params.hold_fade, 0.0, 1.0)


func _end_hold() -> void:
	if _holding:
		_holding = false
		_loading.hide()
		_bar.hide()
		_layer.move_child(_card, -1) # back over the black (it waited under it)
		_card.modulate.a = 0.0
		hold_ended.emit()


## The hole is fully built: the black may lift (the hold ends on this, never on a timer).
func release() -> void:
	_released = true


func _input(event: InputEvent) -> void:
	if not _done and event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled() # the skip press does nothing else
		if _holding:
			_skip_pending = true # skipped while still building: cut to the shot once it is built
		else:
			_finish()


## The camera `t` s in: one ease-in-out over the path, sampled at constant arc-length speed
## underneath; looking at the look spline `lookahead` further on, turning onto the pin over
## pin_blend s up to the orbit, then holding it.
func _view(t: float) -> Transform3D:
	var p := params
	var length := _eye.get_baked_length()
	var s := smoothstep(0.0, 1.0, t / p.duration) * length
	var eye := _eye.sample_baked(s, true)
	var ahead := _look.sample_baked(minf((s + p.lookahead) / length, 1.0) * _look.get_baked_length(), true)
	var target := ahead.lerp(_pin, smoothstep(_orbit_time - p.pin_blend, _orbit_time, t))
	return Transform3D(Basis.looking_at(target - eye), eye)


func _finish() -> void:
	if _done:
		return
	_done = true
	_end_hold()
	_camera.global_transform = _end # a cut, not a blend
	_layer.queue_free()
	finished.emit()
	queue_free()


## Bottom-left: the hole's line of text and a small arrow the way the wind blows (up = toward the green).
func _build_card(text: String, wind: Vector3, along: Vector3) -> void:
	_layer.layer = 5
	add_child(_layer)
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_black) # under the card
	# "Loading..." over the black while the hole finishes building, in the hole card's look
	var k0 := DisplayServer.window_get_size().y / 1080.0 if DisplayServer.get_name() != "headless" else 1.0
	_loading.text = "Loading..."
	_loading.add_theme_font_size_override("font_size", int(params.card_font * 1.3 * k0))
	_loading.add_theme_color_override("font_color", FEEDBACK.meter_peak)
	_loading.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_loading.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_loading.grow_vertical = Control.GROW_DIRECTION_BOTH
	_loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_layer.add_child(_loading)
	# A thin progress bar under it, filled by the hole's build stages (progress)
	_bar.color = Color(FEEDBACK.meter_peak, 0.18)
	_bar.size = Vector2(params.card_font * 9.0 * k0, maxf(3.0 * k0, 2.0))
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.set_anchors_preset(Control.PRESET_CENTER)
	_bar.position = -_bar.size * 0.5 + Vector2(0, params.card_font * 1.3 * k0)
	_bar_fill.color = Color(FEEDBACK.meter_peak, 0.75)
	_bar_fill.size = Vector2(0.0, _bar.size.y)
	_bar.add_child(_bar_fill)
	_layer.add_child(_bar)
	var k := DisplayServer.window_get_size().y / 1080.0 if DisplayServer.get_name() != "headless" else 1.0
	var back := StyleBoxFlat.new()
	back.bg_color = FEEDBACK.meter_back
	back.border_color = FEEDBACK.meter_frame
	back.set_border_width_all(3)
	back.set_corner_radius_all(12)
	back.set_content_margin_all(int(14 * k))
	_card.add_theme_stylebox_override("panel", back)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(14 * k))
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", int(params.card_font * k))
	label.add_theme_color_override("font_color", FEEDBACK.meter_peak)
	row.add_child(label)
	if _accent != "": # the biome, in its colour
		var biome := Label.new()
		biome.text = "· " + _accent
		biome.add_theme_font_size_override("font_size", int(params.card_font * k))
		biome.add_theme_color_override("font_color", _accent_color)
		row.add_child(biome)
	var arrow := WindArrow.new()
	arrow.bearing = Compass.bearing(along, Vector3.ZERO, wind)
	arrow.speed = Vector2(wind.x, wind.z).length()
	arrow.color = FEEDBACK.compass_wind
	arrow.custom_minimum_size = Vector2(params.card_font * 4.2, params.card_font * 1.3) * k
	row.add_child(arrow)
	_card.add_child(row)
	_card.modulate.a = 0.0
	_layer.add_child(_card)
	_card.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, int(params.card_margin * k))
	_layer.move_child(_card, 0) # under the black while holding: drawn there in full, unseen (warm-up)


## A small arrow (up = along the hole) and the wind speed beside it.
class WindArrow:
	extends Control
	var bearing := 0.0
	var speed := 0.0
	var color := Color.WHITE

	func _draw() -> void:
		var r := size.y * 0.42
		var at := Vector2(r + 2.0, size.y * 0.5)
		var d := Vector2(sin(bearing), -cos(bearing)) * r
		var side := Vector2(-d.y, d.x) * 0.45
		if speed > 0.05:
			draw_line(at - d, at + d * 0.3, color, maxf(2.0, r * 0.18))
			draw_colored_polygon(PackedVector2Array([at + d, at + d * 0.2 + side, at + d * 0.2 - side]), color)
		var font := get_theme_default_font()
		var text := "%.1f m/s" % speed if speed > 0.05 else "calm"
		draw_string(font, Vector2(at.x + r + 8.0, size.y * 0.5 + r * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			int(size.y * 0.55), color)
