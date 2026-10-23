extends SceneTree
## First-person club and pitch: pitch turns the whole swing-arc pose about the eye's right, positive (mouse up)
## lifting it. At −0.8 rad from address the head's height rises with pitch from −0.5 to +0.8 rad and
## never goes below the ground; and at every sampled (angle, pitch) the grip end is nearer the eye
## than the head (the club points from the player out to the arc), for D, 7I, SW and P.
## Run: godot --headless --fixed-fps 120 --path game -s res://tests/fp_pitch_test.gd

const PITCHES := [-0.5, -0.25, 0.0, 0.2, 0.4, 0.6, 0.8]
const ANGLES := [0.0, -0.3, -0.8, -1.5, 0.3] # from address

var _failed := false


func _initialize() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	main.random_course = false
	root.add_child(main)
	for i in 5:
		await physics_frame
	var swing: Swing = main.get_node("Swing")
	for c in [0, 5, 9, 10]:
		main.restart()
		main.select_club(c)
		for i in 10:
			await physics_frame
		swing.set_physics_process(false)
		var eye: Vector3 = main._camera.global_position
		var rig: GolferRig = main._rig
		var heights := []
		var above := true
		for p in PITCHES:
			swing.angle = swing.feel.address_angle - 0.8
			swing.pitch = p
			main._lock_club()
			var face: Vector3 = main._fp_face()
			var over: float = face.y - main._hole.height_at(face)
			heights.append(over)
			above = above and over >= 0.0
		var rising := true
		for i in heights.size() - 1:
			rising = rising and heights[i + 1] > heights[i]
		_check(rising and above, "%s at −0.8 rad: head over the ground rises with pitch, never below it (%s m)" % [swing.club.label,
			heights.map(func(h): return snappedf(h, 0.01))])
		var nearer := true
		var worst := ""
		for a in ANGLES:
			for p in PITCHES:
				swing.angle = swing.feel.address_angle + a
				swing.pitch = p
				main._lock_club()
				var grip := rig._club_model.to_global(Vector3(0, swing.club.grip_length * rig.girth_scale() * 0.4, 0))
				if grip.distance_to(eye) >= main._fp_face().distance_to(eye):
					nearer = false
					worst = "angle %+.1f pitch %+.2f" % [a, p]
		swing.pitch = 0.0
		swing.set_physics_process(true)
		_check(nearer, "%s: the grip end nearer the eye than the head at every sampled angle and pitch%s" % [swing.club.label,
			"" if nearer else " (not at %s)" % worst])
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	_failed = _failed or not ok
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
