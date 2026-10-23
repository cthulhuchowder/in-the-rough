extends SceneTree
## Step 2.1 test (f56b83b), kept runnable. Headless check: a scripted straight mouse swing hits the ball, a new swing starts clean,
## and the drive carries a plausible distance.
## Run: godot --headless --path game -s res://tests/swing21_test.gd

var _main: Node
var _swing: Swing
var _ball: Ball
var _feeder: MouseSwingFeeder
var _tick := 0
var _hit_tick := -1


func _initialize() -> void:
	_main = load("res://main.tscn").instantiate()
	_main.random_course = false # the default course, so every run plays the same holes
	root.add_child(_main)
	_swing = _main.get_node("Swing")
	_ball = _main.get_node("Ball")
	_feeder = _main.get_node("MouseSwingFeeder")
	physics_frame.connect(_on_tick)


func _on_tick() -> void:
	_tick += 1
	if _tick > 10 and _tick <= 50:
		_feeder.add_motion(Vector2(20, 0)) # backswing, 2 rad
	elif _tick > 50 and not _swing.has_hit:
		_feeder.add_motion(Vector2(-110, 0)) # downswing, ~33 rad/s
	if _swing.has_hit and _hit_tick < 0:
		_hit_tick = _tick
	if _ball.carry >= 0.0 or _tick > 120 * 30:
		_finish()


func _finish() -> void:
	physics_frame.disconnect(_on_tick)
	print("hit tick %d  power %.3f  peak %.1f m/s  path %.2f deg  carry %.1f m" % [
		_hit_tick, _swing.power, _swing.peak_speed, rad_to_deg(_swing.path_angle), _ball.carry])
	var ok := _hit_tick > 0 and _swing.power > 0.5 and absf(_swing.path_angle) < 0.01 \
		and _ball.carry > 100.0 and _ball.carry < 400.0
	_main.restart() # reset_to_tee() equivalent: ball back on the tee, full Shooting reset
	ok = ok and _swing.peak_speed == 0.0 and not _swing.has_hit
	print("PASS" if ok else "FAIL")
	quit(0 if ok else 1)
