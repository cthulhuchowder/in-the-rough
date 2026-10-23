extends SceneTree
## Room rules in PlayerRound (the server runs one per player): a mulligan puts the ball back where
## the last shot was played and undoes its strokes, once per allowance; a ball at rest within the
## gimme radius is holed with one more stroke; a shot clock whiff is a stroke with no movement.
## RoomRules.clean keeps only valid values.
## Run: godot --headless --path game -s res://tests/round_rules_test.gd

var _failed := false


func _initialize() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	main.random_course = false
	root.add_child(main)
	await physics_frame
	var r: PlayerRound = main._round
	var ball: Ball = main.get_node("Ball")
	var cup: Vector3 = r.hole.cup.global_position

	# Mulligan
	r.mulligans = 1
	var from := ball.global_position
	r.shot_taken()
	ball.place(from + Vector3(40, 0, 0))
	r.strokes += 1 # say it went out of bounds: a penalty stroke too
	var rests := [0]
	r.at_rest.connect(func(_p): rests[0] += 1)
	_check(r.mulligan() and r.strokes == 0 and ball.global_position.distance_to(from) < 0.01 and r.mulligans == 0 and rests[0] == 1,
		"a mulligan puts the ball back and undoes the shot's strokes, penalty included")
	r.shot_taken()
	_check(not r.mulligan() and r.strokes == 1, "none left: no second mulligan")

	# Shot clock whiff
	var at := ball.global_position
	r.whiff()
	_check(r.strokes == 2 and ball.global_position == at and rests[0] == 2 and r.score < 0,
		"a whiff costs a stroke, the ball stays and the next shot is from the same spot")

	# Gimme
	r.gimme = 1.0
	ball.place(r.hole.rest_point(cup + Vector3(0.8, 0, 0), 0.05))
	r._on_ball_stopped()
	_check(r.score == 3, "a ball at rest 0.8 m from the cup with a 1 m gimme is holed with one more stroke (score %d)" % r.score)

	# Untrusted rules
	var base := RoomRules.defaults()
	var bad := RoomRules.clean({holes = 7, shot_clock = -3, wind = 9, mulligans = 5, gimme = 0.7, biome = 9}, base)
	var good := RoomRules.clean({holes = 18, shot_clock = 60, wind = 2, mulligans = 3, gimme = 0.5, biome = 4}, base)
	_check(bad == base and good == {holes = 18, shot_clock = 60, wind = 2, mulligans = 3, gimme = 0.5, biome = 4},
		"RoomRules.clean drops out-of-range values and keeps valid ones")
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	_failed = _failed or not ok
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
