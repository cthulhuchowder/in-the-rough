extends SceneTree
## Feel regression: fixed scripted swings must match the locked Step 2.2 feel.
## Expected values were recorded by running this same input on the Step 2.2 build.
## Run: godot --headless --fixed-fps 120 --path game -s res://tests/feel_regression_test.gd

## club index, downswing px/tick, alternating vertical px/tick, then the 2.2 results:
## hit tick (downswing ticks until contact), power, path angle (rad).
## Then the first-person club: on the hitbox at address (after that it is free).
const CASES := [
	[0, 110.0, 20.0, 8, 0.862999, 0.093591], # driver
	[5, 40.0, 10.0, 21, 0.571152, -0.119367], # 7 iron
	[10, 8.0, 4.0, 103, 0.633936, -0.206973], # putter
]

var _main: Node
var _swing: Swing
var _feeder: MouseSwingFeeder


func _initialize() -> void:
	_main = load("res://main.tscn").instantiate()
	_main.random_course = false # the default course, so every run plays the same holes
	root.add_child(_main)
	_swing = _main.get_node("Swing")
	_feeder = _main.get_node("MouseSwingFeeder")
	_run()


func _run() -> void:
	await physics_frame
	_main.load_hole(load("res://holes/test_hole.tscn").instantiate()) # flat, like the 2.2 hole
	var failed := false
	for c in CASES:
		_main.restart()
		_main.select_club(c[0])
		for i in 10:
			await physics_frame
		var address_box := _swing.hitbox_box(_swing.hitbox_position())
		var on_box := _face_centre().distance_to(address_box.origin - address_box.basis.x * 0.5) # (on the leading face at address)
		var behind := (_swing.address_point() - _face_centre()).dot(_swing.aim)
		for i in 40:
			_feeder.add_motion(Vector2(20, 0)) # backswing
			await physics_frame
		var ticks := 0
		while not _swing.has_hit and ticks < 300:
			# ±dy keeps pitch bounded while the last tick's path still has a vertical part
			_feeder.add_motion(Vector2(-c[1], c[2] if ticks % 2 == 0 else -c[2]))
			await physics_frame
			ticks += 1
		var ok: bool = _swing.has_hit and ticks == c[3] and absf(_swing.power - c[4]) < 1e-3 \
			and absf(_swing.path_angle - c[5]) < 1e-3
		failed = failed or not ok
		print("  %s  %s: tick %d (2.2: %d)  power %.4f (%.4f)  path %.3f° (%.3f°)" % ["ok  " if ok else "FAIL",
			_swing.club.label, ticks, c[3], _swing.power, c[4], rad_to_deg(_swing.path_angle), rad_to_deg(c[5])])
		# Visual club on the hitbox's leading face at address (after that nothing ties them);
		# where it is on the hit tick is printed
		var hit_box := _swing.hitbox_box(_swing.contact_box)
		var hit_off := _face_centre().distance_to(hit_box.origin - hit_box.basis.x * 0.5)
		var locked := on_box < 0.002
		failed = failed or not locked
		print("  %s  %s club: face %.4f m off its address point (the hitbox's leading face; ball centre %.3f m ahead); at the hit %.4f m off it (not asserted)" % [
			"ok  " if locked else "FAIL", _swing.club.label, on_box, behind, hit_off])
	# A/D turns the stance at address, and is ignored once the backswing has started
	_main.restart()
	var aim := _swing.aim
	await _hold_d(10)
	var turned := not _swing.aim.is_equal_approx(aim)
	for i in 10:
		_feeder.add_motion(Vector2(20, 0))
		await physics_frame
	aim = _swing.aim
	var angle := _swing.angle
	await _hold_d(10)
	var locked := _swing.aim.is_equal_approx(aim) and _swing.angle >= angle
	failed = failed or not (turned and locked)
	print("  %s  A/D: turns at address %s, ignored mid-backswing %s" % ["ok  " if turned and locked else "FAIL", turned, locked])
	print("FAIL" if failed else "PASS")
	quit(1 if failed else 0)


func _hold_d(ticks: int) -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_D
	e.pressed = true
	Input.parse_input_event(e)
	for i in ticks:
		await physics_frame
	e = e.duplicate()
	e.pressed = false
	Input.parse_input_event(e)
	await physics_frame


func _face_centre() -> Vector3:
	var head: Node3D = _main._rig._club_model.get_node("Head")
	return head.to_global(ClubModel.face_centre(_swing.club, _main._rig.girth_scale(), _main._rig.params.club_head_scale))
