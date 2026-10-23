extends SceneTree
## Flight: full-power, straight shots with the driver, 7 iron and pitching wedge on the flat test
## hole; carry (m), hang (s, launch to first landing) and roll (m, first landing to rest). The heavier
## ball (each club's lift cut so hang drops 10 %, bounce damping 0.1–0.7 → 0.24–0.74) took hang and roll ~10 % down from
## BEFORE; AFTER is what it must still produce.
## Run: godot --headless --fixed-fps 120 --path game -s res://tests/flight_test.gd

const CLUBS := [0, 5, 8] ## D, 7I, PW
## club index: [carry, hang, roll]
const BEFORE := {0: [225.2, 6.00, 11.9], 5: [123.8, 6.05, 7.0], 8: [95.4, 5.92, 5.7]}
const AFTER := {0: [217.8, 5.41, 10.7], 5: [118.7, 5.44, 6.3], 8: [91.2, 5.33, 5.1]}

var _main: Node
var _ball: Ball


func _initialize() -> void:
	_main = load("res://main.tscn").instantiate()
	_main.random_course = false # the default course, so every run plays the same holes
	root.add_child(_main)
	_ball = _main.get_node("Ball")
	_run()


func _run() -> void:
	await physics_frame
	_main.load_hole(load("res://holes/test_hole.tscn").instantiate())
	await physics_frame
	var failed := false
	for c in CLUBS:
		var r: Array = await _shot(c)
		var club: ClubData = _main.CLUBS[c]
		var line := "  %s: carry %.1f m  hang %.2f s  roll %.1f m" % [club.label, r[0], r[1], r[2]]
		if BEFORE.has(c):
			var b: Array = BEFORE[c]
			line += "   vs before: carry %+.1f%%  hang %+.1f%%  roll %+.1f%%" % [
				(r[0] / b[0] - 1.0) * 100.0, (r[1] / b[1] - 1.0) * 100.0, (r[2] / b[2] - 1.0) * 100.0]
		if AFTER.has(c):
			var a: Array = AFTER[c]
			var ok := absf(r[0] - a[0]) < 0.5 and absf(r[1] - a[1]) < 0.02 and absf(r[2] - a[2]) < 0.5
			failed = failed or not ok
			line = ("  ok  " if ok else "  FAIL") + line
		print(line)
	print("FAIL" if failed else "PASS")
	quit(1 if failed else 0)


func _shot(club_index: int) -> Array:
	_main.restart()
	await physics_frame
	var club: ClubData = _main.CLUBS[club_index]
	var aim := Vector3.FORWARD
	_ball.launch(aim, 0.0, 1.0, club, (-aim).cross(Vector3.UP))
	var ticks := 0
	var hang := -1.0
	var landed_at := Vector3.ZERO
	while _ball.in_play and ticks < 120 * 40:
		await physics_frame
		ticks += 1
		if hang < 0.0 and _ball.carry >= 0.0:
			hang = ticks / 120.0
			landed_at = _ball.global_position
	var rest := _ball.global_position
	return [_ball.carry, hang, Vector2(rest.x - landed_at.x, rest.z - landed_at.z).length()]
