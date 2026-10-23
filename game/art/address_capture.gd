extends SceneTree
## First-person address on the generated hole, the overlay hidden: driver, 7 iron and putter side
## by side (docs/art/address.png), then five frames of a driver swing with the swing paused so no
## shot fires (docs/art/swing_arc.png at angles 0, −0.3, −0.8, −1.5, +0.5: the head rising on the arc;
## top row first person, bottom row face-on from across the ball).
## Run: godot --path game --resolution 1920x1080 -s res://art/address_capture.gd

const CLUBS := [0, 5, 10] ## D, 7I, P
const ARC := [0.0, -0.3, -0.8, -1.5, 0.5] ## swing angle, rad

func _initialize() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	main.random_course = false # the default course, for repeatable shots
	root.add_child(main)
	main.get_node("Overlay").visible = false
	for i in 5:
		await process_frame
	var swing: Swing = main.get_node("Swing")
	var cam: Camera3D = main.get_node("Camera3D")
	var shots: Array[Image] = []
	for c in CLUBS:
		main.select_club(c)
		shots.append(await _grab())
		var at := cam.unproject_position(main.get_node("Ball").global_position) / cam.get_viewport().get_visible_rect().size
		print("  %s: ball at %.2f across, %.2f down" % [swing.club.label, at.x, at.y])
	_save(shots, "address.png")
	main.select_club(0)
	await process_frame
	swing.set_physics_process(false)
	shots.clear()
	for a in ARC:
		swing.angle = a
		main._lock_club() # the first-person club is posed on swing ticks, which are paused
		var head: Node3D = main._rig._club_model.get_node("Head")
		print("  angle %+.2f: head %.2f m above the ball" % [a, head.global_position.y - main.get_node("Ball").global_position.y])
		shots.append(await _grab())
	# Second row: face-on, from across the ball, so the head's rise is in frame
	var ball: Vector3 = main.get_node("Ball").global_position
	var to_golfer := swing.feet - ball
	to_golfer.y = 0.0
	to_golfer = to_golfer.normalized()
	var side := Camera3D.new()
	side.fov = 60.0
	main.add_child(side)
	side.look_at_from_position(ball - to_golfer * 4.5 + Vector3.UP * 1.3, ball + to_golfer * 0.5 + Vector3.UP * 1.0)
	for a in ARC:
		swing.angle = a
		main._lock_club()
		side.make_current()
		shots.append(await _grab())
	_save(shots, "swing_arc.png", ARC.size())
	quit()


func _grab() -> Image:
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	shot.resize(shot.get_width() / 2, shot.get_height() / 2, Image.INTERPOLATE_LANCZOS)
	return shot


func _save(shots: Array[Image], file: String, cols := 0) -> void:
	cols = cols if cols > 0 else shots.size()
	var w := shots[0].get_width()
	var h := shots[0].get_height()
	var sheet := Image.create(w * cols, h * ceili(shots.size() / float(cols)), false, shots[0].get_format())
	for k in shots.size():
		sheet.blit_rect(shots[k], Rect2i(Vector2i.ZERO, shots[k].get_size()), Vector2i(w * (k % cols), h * (k / cols)))
	var out := ProjectSettings.globalize_path("res://").path_join("../docs/art/" + file).simplify_path()
	sheet.save_png(out)
	print("  " + out)
