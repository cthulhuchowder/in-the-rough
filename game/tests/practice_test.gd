extends SceneTree
## Practice: the menu's Practice opens the range (ball on the tee mat, no scoring); a drive pops up
## its landing distance; R re-tees; G goes to the putting green with the ball at the chosen cup's
## distance; a putt that drops goes back to that distance (still no score kept); C picks the next cup
## (the real cup moves there); Esc leaves for the menu.
## Run: godot --headless --fixed-fps 120 --path game -s res://tests/practice_test.gd

var _failed := false
var _main: Node


func _check(ok: bool, what: String) -> void:
	_failed = _failed or not ok
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])


func _initialize() -> void:
	PracticeRange.requested = true
	_main = load("res://main.tscn").instantiate()
	root.add_child(_main)
	for i in 10:
		await physics_frame
	var practice: PracticeRange = _main._practice
	var ball: Ball = _main._ball
	var tee: Vector3 = _main._hole.tee.global_position
	var green_dir := (Vector3(PracticeRange.GREEN.x, 0, PracticeRange.GREEN.y) - tee) * Vector3(1, 0, 1)
	_check(_main._swing.aim.is_equal_approx(Vector3.BACK) and _main._swing.aim.dot(green_dir.normalized()) < 0.3,
		"on the range: facing down it toward the boards (aim %s), the green off to the side" % _main._swing.aim)
	_check(practice != null and ball.global_position.distance_to(tee) < 0.3 and _main.mode == _main.Mode.SHOOTING,
		"Practice opens on the range, the ball on the tee mat")

	# A drive: the landing distance pops up
	practice._shot_from = ball.global_position
	ball.launch(Vector3.BACK, 0.0, 0.8, _main.CLUBS[0], Vector3.LEFT) # +Z: down the range
	_main._round.shot_taken()
	await _until(func(): return practice._popup.text != "", 2000) # (at rest after the settle delay)
	await _frames(5)
	var popped: String = practice._popup.text
	_check(popped.begins_with("Carry") and practice._popup.modulate.a > 0.5, "a drive pops up its distance ('%s')" % popped)
	_key(KEY_R)
	await _frames(5)
	_check(ball.global_position.distance_to(tee) < 0.3 and _main.strokes == 0, "R re-tees (strokes %d)" % _main.strokes)

	# The green: the ball at the first cup's distance; a holed putt goes back there
	_key(KEY_G)
	await _frames(5)
	var cup: Vector3 = _main._hole.cup.global_position
	var want: float = PracticeRange.CUPS[0][1]
	var d := Vector2(cup.x - ball.global_position.x, cup.z - ball.global_position.z).length()
	var to_cup := ((cup - ball.global_position) * Vector3(1, 0, 1)).normalized()
	_check(practice.on_green and absf(d - want) < 0.3 and _main._swing.aim.dot(to_cup) > 0.99, "G: the putting green, %.1f m from cup 1 (set %.1f m), facing the cup" % [d, want])
	var toward := (cup - ball.global_position) * Vector3(1, 0, 1)
	ball.place(_main._hole.rest_point(cup - toward.normalized() * 0.25, 0.05))
	ball.launch(toward.normalized(), 0.0, 0.03, _main.CLUBS[10], toward.normalized().cross(Vector3.UP)) # a short putt in
	await _until(func(): return _main._round.score >= 0, 400)
	await _frames(240)
	var back := Vector2(cup.x - ball.global_position.x, cup.z - ball.global_position.z).length()
	_check(absf(back - want) < 0.3 and _main._round.score < 0, "a holed putt goes back to %.1f m, no score kept (%.1f m)" % [want, back])

	# C: the next cup is the real one now
	_key(KEY_C)
	await _frames(10)
	var cup2: Vector3 = _main._hole.cup.global_position
	var want2: float = PracticeRange.CUPS[1][1]
	var d2 := Vector2(cup2.x - ball.global_position.x, cup2.z - ball.global_position.z).length()
	_check(practice.cup_index == 1 and cup2.distance_to(cup) > 3.0 and absf(d2 - want2) < 0.3, "C: cup 2, %.1f m away (set %.1f m)" % [d2, want2])
	_key(KEY_ESCAPE)
	await _frames(3)
	_check(not PracticeRange.requested, "Esc leaves for the menu")
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	var up := e.duplicate()
	up.pressed = false
	Input.parse_input_event(up)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _until(done: Callable, frames: int) -> void:
	for i in frames:
		if done.call():
			return
		await physics_frame
