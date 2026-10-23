extends SceneTree
## First-person contact: docs/art/contact-<club>.png for every club, address on the left, the hit
## tick of a slow push on the right; top row from the side (along the aim, vertical), bottom row face
## on from the target (toe–heel, vertical); the hitbox wireframe drawn (red), the ball, and
## the camera centred between the drawn head and the ball (only the club is drawn: first person).
## Contact is by visible gap: a clear gap at address, the head (on a lofted club its leading edge)
## just touching the ball on the hit tick (contact_alignment_test asserts within 5 mm per club).
## Run: godot --path game --resolution 1600x800 -s res://art/contact_capture.gd

const PUSH := 1.0 ## px a tick: the calibration's slow push (art/fp_contact_calibration.gd)


func _initialize() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	main.random_course = false
	root.add_child(main)
	for i in 5:
		await physics_frame
	main.load_hole(load("res://holes/test_hole.tscn").instantiate())
	main.get_node("Overlay").visible = false
	var swing: Swing = main.get_node("Swing")
	var feeder: MouseSwingFeeder = main.get_node("MouseSwingFeeder")
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL # (no perspective: the toe nearer the camera must not look ahead)
	cam.size = 0.5
	root.add_child(cam)
	for i in main.CLUBS.size():
		var club: ClubData = main.CLUBS[i]
		main.restart()
		main.select_club(i)
		main._show_hitbox = true
		for k in 12:
			await physics_frame
		var side := swing.aim.cross(Vector3.UP).normalized() # across the aim, toe side
		_aim_at(cam, main, swing, side)
		var left := await _grab()
		_aim_at(cam, main, swing, swing.aim) # face on, from the target
		var left_face := await _grab()
		var ticks := 0
		while not swing.has_hit and ticks < 1200:
			feeder.add_motion(Vector2(-PUSH, 0))
			await physics_frame
			ticks += 1
		paused = true # held on the hit tick
		_aim_at(cam, main, swing, side)
		var right := await _grab()
		_aim_at(cam, main, swing, swing.aim)
		var right_face := await _grab()
		var gap := ClubModel.head_gap(main._rig._club_model.get_node("Head"), swing.address_point())
		paused = false
		var w := left.get_width()
		var h := left.get_height()
		var both := Image.create(w * 2, h * 2, false, left.get_format())
		both.blit_rect(left, Rect2i(Vector2i.ZERO, left.get_size()), Vector2i.ZERO)
		both.blit_rect(right, Rect2i(Vector2i.ZERO, right.get_size()), Vector2i(w, 0))
		both.blit_rect(left_face, Rect2i(Vector2i.ZERO, left.get_size()), Vector2i(0, h))
		both.blit_rect(right_face, Rect2i(Vector2i.ZERO, left.get_size()), Vector2i(w, h))
		var out := ProjectSettings.globalize_path("res://").path_join("../docs/art/contact-%s.png" % club.label.to_lower()).simplify_path()
		both.save_png(out)
		print("  %s (hit tick %d, gap %+.2f mm)" % [out, ticks, gap * 1000.0])
	quit()


## The camera from `from`, on the middle of the drawn face and the ball (at address it waits well behind).
func _aim_at(cam: Camera3D, main: Node, swing: Swing, from: Vector3) -> void:
	var front: Vector3 = (main._fp_face() + swing.address_point()) * 0.5 - Vector3.UP * 0.03
	cam.look_at_from_position(front + from * 0.9 + Vector3.UP * 0.03, front)
	cam.make_current()


func _grab() -> Image:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
