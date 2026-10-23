extends SceneTree
## Wind: the same full-power shot with no wind and with a 6 m/s crosswind on the flat test hole
## (landing shift logged; it must go downwind by a plausible amount), a putt that rolls the same
## either way (no wind on the ground), and per-hole winds from seeds: deterministic, 0..wind_max,
## mostly 2–5 m/s.
## Run: godot --headless --fixed-fps 120 --path game -s res://tests/wind_test.gd

var _main: Node
var _ball: Ball
var _failed := false


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
	var hole: Hole = _main._hole
	var feel: SwingFeel = _ball.feel
	var aim := Vector3.FORWARD
	var cross := Vector3.RIGHT # a crosswind from the left, blowing right of the aim line

	for club_index in [0, 5]:
		var club: ClubData = _main.CLUBS[club_index]
		hole.wind = Vector3.ZERO
		var still: Array = await _shot(club, aim)
		hole.wind = cross * 6.0
		var windy: Array = await _shot(club, aim)
		hole.wind = Vector3.ZERO
		var shift: float = (windy[0] - still[0]).dot(cross)
		var along: float = (windy[0] - still[0]).dot(aim)
		print("  %s, 6 m/s crosswind (wind_strength %.2f): lands %.1f m downwind, %+.1f m along (carry %.1f → %.1f m, hang %.2f s)" % [
			club.label, feel.wind_strength, shift, along, still[1], windy[1], windy[2]])
		_check(shift > 0.02 * still[1] and shift < 0.15 * still[1], "%s crosswind drift is plausible (2–15 %% of carry)" % club.label)

	# Rolling: a putt is never in the air, so wind leaves it alone
	var putter: ClubData = _main.CLUBS[10]
	var rests := []
	for w in [Vector3.ZERO, cross * 8.0]:
		hole.wind = w
		_main.restart()
		await physics_frame
		_ball.place(hole.rest_point(hole.cup.global_position + Vector3(2.0, 0.0, 3.0), Ball.RADIUS))
		await physics_frame
		_ball.launch(aim, 0.0, 0.2, putter, (-aim).cross(Vector3.UP))
		for i in 120 * 8:
			await physics_frame
			if not _ball.in_play:
				break
		rests.append(_ball.global_position)
	hole.wind = Vector3.ZERO
	print("  putt rest without / with an 8 m/s crosswind %.3f m apart" % rests[0].distance_to(rests[1]))
	_check(rests[0].distance_to(rests[1]) < 0.01, "wind does not move a rolling ball")

	# Per-hole winds from seeds
	var p: ProcgenParams = _main.procgen
	var middle := 0
	var top := 0.0
	var low := INF
	var count := 2000
	var same := true
	for s in count:
		var seed := Procgen.mix(s + 1) << 16 | s
		var w := Procgen.wind(seed, p)
		same = same and w == Procgen.wind(seed, p)
		top = maxf(top, w.length())
		low = minf(low, w.length())
		if w.length() >= 2.0 and w.length() <= 5.0:
			middle += 1
	print("  %d hole seeds: wind %.2f..%.2f m/s, %d%% between 2 and 5 m/s" % [count, low, top, 100 * middle / count])
	_check(same and low >= 0.0 and top <= p.wind_max and middle > count / 2, "seeded wind is deterministic, 0..%.0f m/s, mostly 2–5" % p.wind_max)
	var generated := Procgen.hole(_main._course[0].seed, _main._course[0].par, p)
	print("  course hole 1 wind %.1f m/s toward %.0f°" % [generated.wind.length(), rad_to_deg(atan2(generated.wind.y, generated.wind.x))])
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


## Full power along `aim`: [first landing point, carry, hang].
func _shot(club: ClubData, aim: Vector3) -> Array:
	_main.restart()
	await physics_frame
	_ball.launch(aim, 0.0, 1.0, club, (-aim).cross(Vector3.UP))
	var ticks := 0
	while _ball.carry < 0.0 and ticks < 120 * 20:
		await physics_frame
		ticks += 1
	return [_ball.global_position, _ball.carry, ticks / 120.0]


func _check(ok: bool, what: String) -> void:
	_failed = _failed or not ok
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
