extends SceneTree
## Cup rim ride: putts arriving at 3.0 and 4.0 m/s at 0, 0.5, 0.8 and 0.95 cup radii off the centre
## line, on a generated green and the flat test hole. Logged per putt: how far it swept round the
## cup centre on the rim or spiralling down the inside of the wall (centre near the wall, above the
## bottom), and whether it then dropped or left — drop (< 180°), horseshoe (180–360°) or 360
## (≥ 360°), each ending in drop or exit. Required: at least one putt circles ≥ 270° before dropping.
## All physics: the lip, wall, gravity and the capture rule decide.
## Run: godot --headless --fixed-fps 120 --path game -s res://tests/cup_test.gd

const SPEEDS := [3.0, 4.0]
const OFFSETS := [0.0, 0.5, 0.8, 0.95] ## × cup radius off the centre line
const RUN_UP := 0.4 ## m from start to the cup centre

var _main: Node
var _ball: Ball
var _decel := 0.0 ## m/s² on this green, from a probe putt
var _best := 0.0 ## largest sweep (degrees) of a putt that dropped


func _initialize() -> void:
	_main = load("res://main.tscn").instantiate()
	_main.random_course = false # the default course, so every run plays the same holes
	root.add_child(_main)
	_ball = _main.get_node("Ball")
	_run()


func _run() -> void:
	await physics_frame
	var feel: SwingFeel = _ball.feel
	print("  cup radius %.3f m, capture below %.1f m/s, lip tube %.3f m, friction %.2f, restitution %.2f" % [
		feel.cup_radius, feel.cup_capture_speed, feel.cup_lip_radius, feel.cup_lip_friction, feel.lip_restitution])
	await _table("generated hole 1")
	_main.load_hole(load("res://holes/test_hole.tscn").instantiate())
	await physics_frame
	await _table("flat test hole")
	var ok := _best >= 270.0
	print("  %s  a putt circled %.0f° before dropping (need ≥ 270°)" % ["ok  " if ok else "FAIL", _best])
	print("PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _table(where: String) -> void:
	var feel: SwingFeel = _ball.feel
	# The green slows a putt: measure it once (well away from the cup), then launch each so it
	# reaches the rim at its speed.
	_decel = 0.0
	var probe: Dictionary = await _putt(1.5, 3.0)
	_decel = (1.5 * 1.5 - probe.at_rim * probe.at_rim) / (2.0 * (RUN_UP - feel.cup_radius))
	print("  %s (the green slows a putt at %.2f m/s²)" % [where, _decel])
	print("  speed    offset    arrives     swept round the rim   result")
	for speed in SPEEDS:
		for offset in OFFSETS:
			var r: Dictionary = await _putt(speed, offset)
			print("  %.1f m/s  %.2f R    %.2f m/s    %4.0f°                 %s" % [speed, offset, r.at_rim, r.swept, r.result])
			if r.dropped:
				_best = maxf(_best, r.swept)


## One putt along world −Z, `offset` × cup radius across it; it starts RUN_UP short of the cup.
func _putt(speed: float, offset: float) -> Dictionary:
	var hole: Hole = _main._hole
	var cup := hole.cup.global_position
	var feel: SwingFeel = _ball.feel
	_main.restart()
	await physics_frame
	var start := hole.rest_point(cup + Vector3(offset * feel.cup_radius, 0.0, RUN_UP), Ball.RADIUS)
	_ball.place(start)
	await physics_frame
	var putter: ClubData = _main.CLUBS[10]
	var launch := sqrt(speed * speed + 2.0 * _decel * (RUN_UP - feel.cup_radius))
	_ball.launch(Vector3.FORWARD, 0.0, launch / (putter.strength * putter.power_mul * putter.smash), putter, Vector3.BACK)
	var out := {at_rim = 0.0, swept = 0.0, dropped = false, result = ""}
	var last_angle := NAN
	for t in 120 * 8:
		await physics_frame
		var p := _ball.global_position
		var rel := Vector2(p.x - cup.x, p.z - cup.z)
		if out.at_rim == 0.0 and p.z < cup.z + feel.cup_radius: # crossing the rim's line
			out.at_rim = Vector2(_ball.linear_velocity.x, _ball.linear_velocity.z).length()
		# On the rim or running round the inside of the wall, above the bottom
		var on_rim := rel.length() > feel.cup_radius - 2.0 * Ball.RADIUS and rel.length() < feel.cup_radius + Ball.RADIUS \
			and p.y > cup.y - feel.cup_depth + 2.0 * Ball.RADIUS and p.y < cup.y + 0.15
		if on_rim:
			var a := atan2(rel.y, rel.x)
			if not is_nan(last_angle):
				out.swept += absf(rad_to_deg(wrapf(a - last_angle, -PI, PI)))
			last_angle = a
		else:
			last_angle = NAN
		if _ball.in_cup and not _ball.in_play:
			out.dropped = true
			break
		if not _ball.in_play:
			break
	var kind := "drop" if out.swept < 180.0 else ("horseshoe" if out.swept < 360.0 else "360")
	out.result = (kind if kind == "drop" else kind + " → drop") if out.dropped else ("exit" if kind == "drop" else kind + " → exit")
	return out
