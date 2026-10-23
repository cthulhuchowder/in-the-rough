extends SceneTree
## First-person club, no seams: the head (face centre) sampled every 0.01 rad of swing angle from
## −1.5 to +0.5 for D, 7I, SW and P, at pitches −0.5 to +0.8 (the soft floor included); its second
## difference never exceeds MAX_SECOND_DIFF, so nothing
## jumps or kinks anywhere on the one continuous arc (address and impact included).
## Run: godot --headless --fixed-fps 120 --path game -s res://tests/fp_jerk_test.gd

const STEP := 0.01
const FROM := -1.5
const TO := 0.5
const MAX_SECOND_DIFF := 0.003 ## m: the arc's own curvature is under 1 mm at this step
const PITCHES := [-0.5, 0.0, 0.4, 0.8] ## rad: the sweep is repeated at each

var _failed := false


func _initialize() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	main.random_course = false
	root.add_child(main)
	for i in 5:
		await physics_frame
	var swing: Swing = main.get_node("Swing")
	for c in [0, 5, 9, 10]: # driver, 7 iron, sand wedge, putter
		main.restart()
		main.select_club(c)
		for i in 10:
			await physics_frame
		swing.set_physics_process(false)
		for pitch in PITCHES:
			swing.pitch = pitch
			var points := []
			var steps := roundi((TO - FROM) / STEP)
			for k in steps + 1:
				swing.angle = FROM + k * STEP
				main._lock_club()
				points.append(main._fp_face())
			var worst := 0.0
			var worst_at := 0.0
			for k in range(1, points.size() - 1):
				var d: float = (points[k + 1] - 2.0 * points[k] + points[k - 1]).length()
				if d > worst:
					worst = d
					worst_at = FROM + k * STEP
			_check(worst <= MAX_SECOND_DIFF, "%s pitch %+.1f: head second difference at most %.5f m (at %.2f rad; bound %.3f m)" % [
				swing.club.label, pitch, worst, worst_at, MAX_SECOND_DIFF])
		# From a fresh address with pitch, back through the address pitch-follow's fade
		main.restart()
		main.select_club(c)
		for i in 10:
			await physics_frame
		swing.set_physics_process(false)
		swing.pitch = 0.15
		var back := []
		for k in 101:
			swing.angle = swing.feel.address_angle - k * STEP
			main._lock_club()
			back.append(main._fp_face())
		var worst_back := 0.0
		for k in range(1, back.size() - 1):
			worst_back = maxf(worst_back, (back[k + 1] - 2.0 * back[k] + back[k - 1]).length())
		_check(worst_back <= MAX_SECOND_DIFF, "%s pitch +0.15 from address back 1 rad (the pitch-follow fading): second difference at most %.5f m" % [
			swing.club.label, worst_back])
		swing.pitch = 0.0
		swing.set_physics_process(true)
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	_failed = _failed or not ok
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
