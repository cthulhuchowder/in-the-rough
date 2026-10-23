extends SceneTree
## The shop's goofy items rendered: docs/art/shop-wear.png (golfers in each new hat, shirt, pair of
## trousers and shoes), shop-shoes.png (the Clown Shoes and Bunny Slippers close up), shop-clubs.png (driver, 7 iron and putter in the standard, Fresh Catch and
## Squeaky Set heads, from the face side), shop-balls.png (Meatball, Disco Ball, Eyeball) and shop-trails.png
## (the three trails mid-flight).
## Run: godot --path game --resolution 1920x1080 -s res://art/novelty_capture.gd

const CHARACTER: CharacterParams = preload("res://data/character.tres")
const WEAR := ["hat_green", "hat_goose", "hat_propeller", "shirt_flamingo", "pants_plaid", "pants_knickers", "shoes_clown", "shoes_bunny"]


func _initialize() -> void:
	var stage := _stage()
	for k in WEAR.size():
		var rig := GolferRig.new(CHARACTER, ShopCatalog.look_for({ShopCatalog.tab_key(ShopCatalog.item(WEAR[k]).tab): WEAR[k]}))
		stage.add_child(rig)
		rig.transform = Transform3D(Basis(Vector3.UP, PI - 0.45), Vector3((k - 3.5) * 1.05, 0, 0)) # (facing the camera, a little aside)
		rig.pose_idle()
	_shoot(stage, Vector3(0, 1.3, 7.4), Vector3(0, 0.85, 0), 40.0, "shop-wear.png")
	await _save_when_drawn(stage, "shop-wear.png")

	stage = _stage() # the novelty shoes close up: each pair from the front three-quarters and from the side
	for k in 4:
		var rig := GolferRig.new(CHARACTER, ShopCatalog.look_for({shoes = "shoes_clown" if k < 2 else "shoes_bunny"}))
		stage.add_child(rig)
		rig.transform = Transform3D(Basis(Vector3.UP, PI - 0.6 if k % 2 == 0 else PI * 0.5), Vector3((k - 1.5) * 0.75, 0, 0))
		rig.pose_idle()
	_shoot(stage, Vector3(0, 0.5, 1.9), Vector3(0, 0.1, 0), 30.0, "shop-shoes.png")
	await _save_when_drawn(stage, "shop-shoes.png")

	stage = _stage()
	var clubs := [Clubs.ALL[0], Clubs.ALL[6], Clubs.ALL[Clubs.ALL.size() - 1]]
	for style in 3:
		for k in clubs.size():
			var mat := LowPoly.material()
			mat.albedo_color = Color(0.75, 0.77, 0.8)
			var model := ClubModel.build(clubs[k], CHARACTER.bevel, CHARACTER.bevel_segments, mat, mat, mat, CHARACTER.club_scale,
				CHARACTER.club_head_scale, 1.0, style)
			stage.add_child(model)
			var head: Node3D = model.get_node("Head")
			model.position = Vector3((k - 1) * 0.42, 0.35 + (1 - style) * 0.22, 0) - head.position # the head at its slot
	_shoot(stage, Vector3(0.35, 0.5, -1.2), Vector3(0.0, 0.35, 0), 45.0, "shop-clubs.png") # (face on, from the target side)
	await _save_when_drawn(stage, "shop-clubs.png")

	stage = _stage()
	for k in 3:
		var view := MeshInstance3D.new()
		view.mesh = Ball.view_mesh_for(ShopCatalog.look_for({"ball": ["ball_meatball", "ball_disco", "ball_eyeball"][k]}))
		view.position = Vector3((k - 1) * 0.16, 0.06, 0)
		if k == 2:
			view.rotation.y = PI * 0.85 # its pupil toward the camera, a little aside
		stage.add_child(view)
	_shoot(stage, Vector3(0, 0.16, 0.5), Vector3(0, 0.05, 0), 40.0, "shop-balls.png")
	await _save_when_drawn(stage, "shop-balls.png")

	stage = _stage()
	var trails := []
	for k in 3:
		var trail := BallTrail.new()
		trail.style = k + 1
		trail.ground_y = 0.0
		stage.add_child(trail)
		trails.append(trail)
	for k in 3:
		trails[k].start(Vector3(-6, 0.05, -k * 3.0), 0.9 if k < 2 else 0.35)
	var fly := 0.0
	while fly < 1.5: # a second and a half of flight, each one across the frame
		fly += 1.0 / 60.0
		for k in 3:
			var at := Vector3(-6 + fly * 7.0, 0.05 + 6.0 * fly - 3.4 * fly * fly, -k * 3.0)
			trails[k].feed(at)
		await create_timer(1.0 / 60.0).timeout # (real time: the trails emit and fade on the clock)
	_shoot(stage, Vector3(-0.5, 2.2, 7.5), Vector3(-0.5, 1.6, -3.0), 50.0, "shop-trails.png")
	await _save_when_drawn(stage, "shop-trails.png", 1)
	quit()


func _stage() -> Node3D:
	for child in root.get_children():
		child.queue_free()
	var stage := Node3D.new()
	root.add_child(stage)
	stage.add_child(load("res://art/presets/overcast.tscn").instantiate())
	var lawn := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	lawn.mesh = LowPoly.flat(plane, Color(0.42, 0.56, 0.36))
	lawn.material_override = LowPoly.material()
	stage.add_child(lawn)
	return stage


func _shoot(stage: Node3D, eye: Vector3, at: Vector3, fov: float, _file: String) -> void:
	var cam := Camera3D.new()
	cam.fov = fov
	stage.add_child(cam)
	cam.look_at_from_position(eye, at)
	cam.make_current()


func _save_when_drawn(_stage_node: Node3D, file: String, frames := 12) -> void:
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	var out := ProjectSettings.globalize_path("res://").path_join("../docs/art/" + file).simplify_path()
	root.get_texture().get_image().save_png(out)
	print("  " + out)
