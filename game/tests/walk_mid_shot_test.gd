extends SceneTree
## Walking while the ball is out. After a shot, F takes the third-person walk (in the air, and
## again while rolling) and the ball flies and rolls on as it would have: it comes to rest on the
## same spot as the same shot watched through. F while it still moves goes back to the follow
## camera; once it has stopped, the walk stays until F, which takes the stance at the ball.
## Run: godot --headless --fixed-fps 120 --path game -s res://tests/walk_mid_shot_test.gd

var _failed := false
var _main: Node


func _check(ok: bool, what: String) -> void:
	_failed = _failed or not ok
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])


func _initialize() -> void:
	_main = load("res://main.tscn").instantiate()
	_main.random_course = false
	root.add_child(_main)
	for i in 5:
		await physics_frame
	_main.load_hole(load("res://holes/test_hole.tscn").instantiate())
	var walking: int = _main.Mode.WALKING
	var following: int = _main.Mode.FOLLOWING
	var shooting: int = _main.Mode.SHOOTING

	# The shot watched through: where it rests
	var watched := await _shoot_and_rest()

	# The same shot, walking off once the ball is rolling (its spin is set by the first landing)
	await _shoot()
	while _main._ball.carry < 0.0: # (in the air)
		await physics_frame
	for i in 10:
		await physics_frame
	_f()
	var walk_mode: int = _main.mode
	var from: Vector3 = _main._ball.global_position
	for i in 30:
		await physics_frame
	var rolled: float = _main._ball.global_position.distance_to(from)
	_check(walk_mode == walking and rolled > 0.05, "F while it rolls: walking, the ball rolls on (%.2f m in 0.25 s)" % rolled)
	_f()
	_check(_main.mode == following, "F again while it still moves: the follow camera")
	_f()
	var rests := [0]
	_main._round.at_rest.connect(func(_at: Vector3) -> void: rests[0] += 1)
	var t := 0
	while rests[0] == 0 and t < 120 * 30:
		await physics_frame
		t += 1
	await physics_frame
	var rest: Vector3 = _main._ball.global_position
	_check(_main.mode == walking and _main._rested_while_walking and rest.distance_to(watched) < 0.01,
		"it stops while walking: still walking, at rest %.3f m from the watched shot's spot" % rest.distance_to(watched))
	_f()
	await physics_frame
	_check(_main.mode == shooting and _main._swing.address_point().distance_to(rest) < 0.3 and not _main._swing.has_hit,
		"F then: the stance at the ball")

	# In the air: F walks, the ball flies on
	_main.restart()
	for i in 10:
		await physics_frame
	await _shoot()
	for i in 20:
		await physics_frame
	var flying: bool = _main._ball.carry < 0.0
	var high: float = _main._ball.global_position.y
	_f()
	for i in 30:
		await physics_frame
	_check(flying and _main.mode == walking and _main._swing.spin_decided and _main._ball.global_position.y != high,
		"F in the air: walking, the spin set, the ball flies on")
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _f() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_F
	ev.pressed = true
	_main._unhandled_input(ev)


## A full driver swing from the tee: back, then through until it hits, and a little follow-through.
func _shoot() -> void:
	_main.restart()
	_main.select_club(0)
	for i in 10:
		await physics_frame
	var feeder: MouseSwingFeeder = _main.get_node("MouseSwingFeeder")
	for k in 40:
		feeder.add_motion(Vector2(20, 0))
		await physics_frame
	var k := 0
	while not _main._swing.has_hit and k < 400:
		feeder.add_motion(Vector2(-40, 0))
		await physics_frame
		k += 1
	for i in 4:
		feeder.add_motion(Vector2(-40, 0))
		await physics_frame


func _shoot_and_rest() -> Vector3:
	await _shoot()
	var rests := [0]
	var c := func(_at: Vector3) -> void: rests[0] += 1
	_main._round.at_rest.connect(c)
	var t := 0
	while rests[0] == 0 and t < 120 * 30:
		await physics_frame
		t += 1
	_main._round.at_rest.disconnect(c)
	await physics_frame
	return _main._ball.global_position
