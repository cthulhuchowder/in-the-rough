extends SceneTree
## Uniform first-person framing: at address the rendered shooting camera uses the driver's framing
## (pullback, height, pitch) for every club, so the ball sits at the same normalized screen
## position (±0.02) for D, 7I, SW and P — on the tee and on a lie down the fairway.
## Run: godot --path game --resolution 1920x1080 -s res://tests/framing_test.gd

const CLUBS := [0, 5, 9, 10] # driver, 7 iron, sand wedge, putter
const TOLERANCE := 0.02

var _failed := false


func _initialize() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	main.random_course = false
	root.add_child(main)
	for i in 5:
		await process_frame
	var ball: Ball = main.get_node("Ball")
	var hole: Hole = main._hole
	var line := hole.centreline
	for lie in ["tee", "fairway"]:
		if lie == "fairway":
			var at := line[0].lerp(line[line.size() - 1], 0.45)
			ball.place(hole.rest_point(at, 0.05))
		var seen := []
		for c in CLUBS:
			main.select_club(c)
			main._readdress() # R: a fresh address with this club
			for i in 3:
				await process_frame
			var cam: Camera3D = main._camera
			var at: Vector2 = cam.unproject_position(ball.global_position) / root.get_visible_rect().size
			seen.append(at)
			print("  %-7s %-3s ball at (%.4f, %.4f)" % [lie, main._swing.club.label, at.x, at.y])
		var ok := seen.all(func(s: Vector2): return absf(s.x - seen[0].x) <= TOLERANCE and absf(s.y - seen[0].y) <= TOLERANCE)
		_check(ok, "%s: the ball at the same screen position for D, 7I, SW, P (±%.2f)" % [lie, TOLERANCE])
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	_failed = _failed or not ok
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
