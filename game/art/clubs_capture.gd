extends SceneTree
## Club lineup in the project look (overcast preset, default look's club color): the top half
## shows every club full length on its sole; the bottom half the same clubs close up at three-
## quarters, so head shapes and face lofts read. Writes docs/art/clubs.png at 1920x1080
## (offscreen viewports; needs a small window, as capture.gd).
## Run: godot --path game --resolution 480x270 -s res://art/clubs_capture.gd

const SIZE := Vector2i(1920, 1080)


func _initialize() -> void:
	_run()


func _run() -> void:
	var half := Vector2i(SIZE.x, SIZE.y / 2)
	var full := _stage(half, 0.27, 0.0, Vector3(0.0, 0.62, 4.1), Vector3(0, 0.5, 0), 24.0)
	var heads := _stage(half, 0.24, PI * 0.86, Vector3(0.3, 0.3, 1.1), Vector3(0, 0.04, 0), 60.0)
	for i in 20:
		await process_frame
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	for panel in [[full, 0], [heads, half.y]]:
		var shot: Image = panel[0].get_texture().get_image()
		shot.convert(Image.FORMAT_RGBA8)
		image.blit_rect(shot, Rect2i(Vector2i.ZERO, half), Vector2i(0, panel[1]))
	var out := ProjectSettings.globalize_path("res://").path_join("../docs/art/clubs.png").simplify_path()
	image.save_png(out)
	print("  " + out)
	quit()


## One row of every club in its own offscreen world, labelled, seen from `eye`.
func _stage(size: Vector2i, spacing: float, yaw: float, eye: Vector3, target: Vector3, fov: float) -> SubViewport:
	var character: CharacterParams = load("res://data/character.tres")
	var look: CharacterLook = load("res://data/characters/default_look.tres")
	var view := SubViewport.new()
	view.size = size
	view.own_world_3d = true
	view.msaa_3d = Viewport.MSAA_4X
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	view.add_child(load("res://art/presets/overcast.tscn").instantiate())
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = LowPoly.flat(plane, (load("res://data/surfaces/fairway.tres") as SurfaceData).color)
	ground.material_override = LowPoly.material()
	view.add_child(ground)
	var club_mat := LowPoly.material()
	club_mat.albedo_color = look.club
	var grip_mat := LowPoly.material()
	grip_mat.albedo_color = character.features
	var count := Clubs.ALL.size()
	for i in count:
		var club := Clubs.ALL[i]
		var model := ClubModel.build(club, character.bevel, character.bevel_segments, club_mat, grip_mat, null,
			character.club_scale, character.club_head_scale, character.club_length_scale)
		# Soled at the club's lie, as at address: the shaft leans, the head sits flat.
		var lie := deg_to_rad(club.lie_deg)
		var reach := ClubModel.hands_to_sole(club, character.club_length_scale)
		var pivot := Node3D.new()
		pivot.position = Vector3((i - (count - 1) * 0.5) * spacing, 0, 0)
		pivot.rotation.y = yaw
		view.add_child(pivot)
		model.position = Vector3(-reach * cos(lie), reach * sin(lie) + ClubModel.SOLE_DROP, 0)
		model.rotation.z = PI * 0.5 - lie
		model.get_node("Head").rotation.z = lie - PI * 0.5
		pivot.add_child(model)
		var model_x := pivot.position.x
		var label := Label3D.new()
		label.text = club.label
		label.font_size = 48
		label.pixel_size = 0.0012 * spacing / 0.24
		label.modulate = Color(0.18, 0.18, 0.18)
		label.outline_size = 0
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(model_x, 0.06 * spacing / 0.24, 0.14 * spacing / 0.24 + 0.04)
		view.add_child(label)
	var camera := Camera3D.new()
	camera.fov = fov
	view.add_child(camera)
	camera.look_at_from_position(eye, target)
	camera.current = true
	return view
