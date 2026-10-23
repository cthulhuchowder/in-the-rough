extends SceneTree
## First person, the club hangs from the hands: for the driver at address and 0.3,
## 0.8 and 1.5 rad into the backswing, prints the hands', grip end's and head's screen positions.
## The grip end moves right across the screen and off it as the club goes back (behind the camera
## counts as off); the head stays within 0.6 m of the hitbox's path while it is still near the ground
## (address, −0.3 rad) — further back the hands' rise lifts it off (printed).
## Run: godot --path game --resolution 1920x1080 -s res://tests/fp_hang_test.gd

const ANGLES := [0.0, -0.3, -0.8, -1.5] # from the address angle
const NEAR_PATH := 0.6
const NEAR_UNTIL := -0.3

var _failed := false


func _initialize() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	main.random_course = false
	root.add_child(main)
	for i in 5:
		await process_frame
	var swing: Swing = main.get_node("Swing")
	var cam: Camera3D = main._camera
	var size := root.get_visible_rect().size
	main.select_club(0)
	main._readdress()
	for i in 4:
		await physics_frame
	swing.set_physics_process(false)
	var grip_x := []
	var near_ok := true
	for d in ANGLES:
		swing.angle = swing.feel.address_angle + d
		main._lock_club()
		var rig: GolferRig = main._rig
		var club: ClubData = swing.club
		var head: Node3D = rig._club_model.get_node("Head")
		var face := head.to_global(ClubModel.face_centre(club, rig.girth_scale(), rig.params.club_head_scale))
		var grip := rig._club_model.to_global(Vector3(0, club.grip_length * rig.girth_scale() * 0.4, 0))
		var hands: Vector3 = rig._club.global_position
		var path := INF
		for k in 400: # the hitbox's path over the swing
			var box := swing.hitbox_box(swing.hitbox_position_at(0.6 - k * 0.01, swing.pitch))
			path = minf(path, face.distance_to(box.origin - box.basis.x * 0.5))
		grip_x.append(INF if cam.is_position_behind(grip) else (cam.unproject_position(grip) / size).x)
		if d >= NEAR_UNTIL:
			near_ok = near_ok and path < NEAR_PATH
		print("  %+.1f rad: hands %s  grip end %s  head %s  head %.2f m from the hitbox path" % [d, _at(cam, hands, size),
			_at(cam, grip, size), _at(cam, face, size), path])
	swing.set_physics_process(true)
	var rising := true
	for i in grip_x.size() - 1:
		rising = rising and grip_x[i + 1] > grip_x[i]
	_check(rising, "the grip end moves right and off screen as the club goes back (x %s)" % [grip_x])
	_check(near_ok, "the head stays within %.1f m of the hitbox path to %.1f rad back" % [NEAR_PATH, NEAR_UNTIL])
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _at(cam: Camera3D, p: Vector3, size: Vector2) -> String:
	if cam.is_position_behind(p):
		return "(behind the camera)"
	var s := cam.unproject_position(p) / size
	return "(%.2f, %.2f)%s" % [s.x, s.y, "" if s.x >= 0.0 and s.x <= 1.0 and s.y >= 0.0 and s.y <= 1.0 else " off"]


func _check(ok: bool, what: String) -> void:
	_failed = _failed or not ok
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
