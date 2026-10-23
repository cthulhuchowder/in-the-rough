extends SceneTree
## docs/art/tee-corridor.png: a deep forest par 3 from the tee at eye height, looking at the green
## down the line of play Procgen keeps open (the first such hole, from seed 0xC0441, where the corridor
## took trees out). HUD hidden.
## Run: godot --path game --resolution 1920x1080 -s res://art/tee_corridor_capture.gd

func _initialize() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	main.random_course = false
	root.add_child(main)
	for i in 5:
		await process_frame
	var p: ProcgenParams = main.procgen
	var biome: Biome = p.biomes.filter(func(b: Biome) -> bool: return b.name == "deep_forest")[0]
	var open: ProcgenParams = p.duplicate()
	open.corridor_width = Vector2.ZERO
	var seed := 0xC0441
	for k in 200: # the first par 3 the corridor changed
		if Procgen.hole(seed + k, 3, p, biome).trees.size() != Procgen.hole(seed + k, 3, open, biome).trees.size():
			seed += k
			break
	var hole := GeneratedHole.new()
	hole.build(Procgen.hole(seed, 3, p, biome), p)
	main.load_hole(hole)
	await process_frame
	main.get_node("Overlay").visible = false
	var tee: Vector3 = hole.tee.global_position
	var cup: Vector3 = hole.cup.global_position
	var camera := Camera3D.new()
	camera.fov = 60.0
	camera.far = 3000.0
	main.add_child(camera)
	camera.look_at_from_position(tee + Vector3.UP * 1.7, cup + Vector3.UP * 1.0)
	for i in 90:
		camera.make_current()
		await process_frame
	await RenderingServer.frame_post_draw
	var out := ProjectSettings.globalize_path("res://").path_join("../docs/art/tee-corridor.png").simplify_path()
	root.get_texture().get_image().save_png(out)
	print("  %s (seed 0x%x, %.0f m)" % [out, seed, tee.distance_to(cup)])
	quit()
