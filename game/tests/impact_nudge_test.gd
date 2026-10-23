extends SceneTree
## The impact nudge (visual only). A firm putt and a full 7-iron: on the hit tick, if the drawn face
## has reached the ball's back surface, the ball's look is drawn ahead of the face by that overlap plus
## the margin, and by impact_nudge_time it is back on the ball; the body moves exactly as it does with
## the nudge switched off (the same positions tick by tick: physics, position and what is sent untouched).
## Run: godot --headless --fixed-fps 120 --path game -s res://tests/impact_nudge_test.gd

const FEEDBACK: FeedbackParams = preload("res://data/feedback.tres")

var _failed := false


func _check(ok: bool, what: String) -> void:
	_failed = _failed or not ok
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])


func _initialize() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	main.random_course = false
	root.add_child(main)
	for i in 5:
		await physics_frame
	main.load_hole(load("res://holes/test_hole.tscn").instantiate())
	var margin := FEEDBACK.impact_nudge_margin
	for c in [main.CLUBS.size() - 1, 5]: # putter, 7 iron
		var runs := []
		for nudge in [true, false]:
			main._ball.nudge_views = nudge
			var r: Dictionary = await _swing_once(main, c, nudge)
			runs.append(r)
		main._ball.nudge_views = true
		var on: Dictionary = runs[0]
		var off: Dictionary = runs[1]
		var same: bool = on.path.size() == off.path.size()
		for k in mini(on.path.size(), off.path.size()):
			same = same and (on.path[k] as Vector3).distance_to(off.path[k]) < 1e-6
		var label: String = main.CLUBS[c].label
		if on.overlap >= 0.0:
			_check(on.ahead >= margin - 1e-4 and on.ahead < margin + 0.002 and on.settled < 1e-5 and same,
				"%s: the face %.1f mm past the ball's back on the hit tick; its look drawn %.1f mm ahead of the face, back on the ball by %.2f s (%.5f m off); the body's path the same as with no nudge" % [
					label, on.overlap * 1000.0, on.ahead * 1000.0, FEEDBACK.impact_nudge_time, on.settled])
		else:
			_check(on.offset_at_hit < 1e-6 and same, "%s: the face short of the ball's back on the hit tick (%.1f mm): no nudge" % [label, -on.overlap * 1000.0])
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


## One swing with club `c`: back, then firm through until the hit. {overlap: the drawn face past the
## ball's back on the hit tick, ahead: the look's back surface ahead of the face then, settled: the look
## off the body impact_nudge_time later, offset_at_hit, path: the body's positions for 30 ticks}.
func _swing_once(main: Node, c: int, _nudge: bool) -> Dictionary:
	var swing: Swing = main.get_node("Swing")
	var feeder: MouseSwingFeeder = main.get_node("MouseSwingFeeder")
	main.restart()
	main.select_club(c)
	for k in 12:
		await physics_frame
	var putter: bool = swing.club.model == ClubData.Model.PUTTER
	for k in 30:
		feeder.add_motion(Vector2(12 if putter else 25, 0))
		await physics_frame
	var ticks := 0
	while not swing.has_hit and ticks < 400:
		feeder.add_motion(Vector2(-30 if putter else -45, 0))
		await physics_frame
		ticks += 1
	var ball: Ball = main._ball
	var mesh: Node3D = ball.get_node("Mesh")
	var aim: Vector3 = swing.aim
	var face: Vector3 = main._fp_face()
	var overlap := (face - (swing.address_point() - aim * Ball.RADIUS)).dot(aim)
	var look_back := (mesh.global_position - aim * Ball.RADIUS - face).dot(aim)
	var offset_at_hit := (mesh.global_position - ball.global_position).length()
	var path := []
	var settled := INF
	var t := 0.0
	for k in 30:
		path.append(ball.global_position)
		feeder.add_motion(Vector2(-30, 0))
		await process_frame
		t += 1.0 / Engine.physics_ticks_per_second
		if t > FEEDBACK.impact_nudge_time + 0.02 and settled == INF:
			settled = (mesh.global_position - ball.global_position).length()
	return {overlap = overlap, ahead = look_back, settled = settled, offset_at_hit = offset_at_hit, path = path}
