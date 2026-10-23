extends SceneTree
## Character turnaround: the golfer in the project look (overcast preset), idle from the front,
## three-quarter and side, then at address and at the top of the backswing. Writes
## docs/art/character.png at 1920x1080 (offscreen viewport; needs a small window, as capture.gd).
## Run: godot --path game --resolution 480x270 -s res://art/character_capture.gd

const SIZE := Vector2i(1920, 1080)


func _initialize() -> void:
	_run()


func _run() -> void:
	var params: CharacterParams = load("res://data/character.tres")
	var look: CharacterLook = load("res://data/characters/default_look.tres")
	var view := SubViewport.new()
	view.size = SIZE
	view.own_world_3d = true
	view.msaa_3d = Viewport.MSAA_4X
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	view.add_child(load("res://art/presets/overcast.tscn").instantiate())
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = LowPoly.flat(plane, (load("res://data/surfaces/green.tres") as SurfaceData).color)
	ground.material_override = LowPoly.material()
	view.add_child(ground)

	# Idle: facing the camera (+Z), three-quarter, side.
	for i in 3:
		var rig := GolferRig.new(params, look)
		view.add_child(rig)
		rig.position = Vector3(-3.6 + i * 1.6, 0, 0)
		rig.rotation.y = PI + [0.0, PI * 0.25, PI * 0.5][i]
		rig.pose_idle()
	await process_frame # posing reads world transforms: the rigs must be in the tree
	# Address and top of backswing, side-on so the swing plane reads (target to screen right).
	var check := ""
	for i in 2:
		var rig := GolferRig.new(params, look)
		view.add_child(rig)
		await process_frame
		var feet := Vector3(1.4 + i * 2.0, 0, 0.3)
		var aim := Vector3.RIGHT
		var ball := feet + (-aim).cross(Vector3.UP) * -1.3 + Vector3.UP * 0.05
		rig.address(feet, aim, ball)
		rig.pose_swing(-0.075, 0.0)
		var hands_at_address := rig._club.global_position
		var angle := -0.075 if i == 0 else -2.0
		rig.pose_swing(angle, 0.0)
		if i == 1:
			var moved := (rig._club.global_position - hands_at_address).dot(aim)
			check = "backswing moves hands %s the target (%.2f m along aim)" % ["away from" if moved < 0.0 else "TOWARD", moved]
		var marker := MeshInstance3D.new()
		marker.mesh = LowPoly.flat(LowPoly.sphere(0.05, 8, 5), Color.WHITE)
		marker.material_override = LowPoly.material()
		marker.position = ball
		view.add_child(marker)

	var camera := Camera3D.new()
	camera.fov = 32.0
	view.add_child(camera)
	camera.look_at_from_position(Vector3(0.2, 1.4, 13.5), Vector3(0.2, 0.95, 0))
	camera.current = true
	for i in 20:
		await process_frame
	var out := ProjectSettings.globalize_path("res://").path_join("../docs/art/character.png").simplify_path()
	view.get_texture().get_image().save_png(out)
	print("  %s\n  %s" % [out, check])
	quit()
