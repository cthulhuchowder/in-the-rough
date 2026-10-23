extends SceneTree
## Renders docs/art/biome-<name>.png: the same hole (course seed 0x1's first long hole) generated in
## each biome and loaded into the game scene (its sky, fog, sun, water, props and air), seen from
## above and behind the tee down the hole, HUD hidden.
## Run: godot --path game --resolution 1920x1080 -s res://art/biome_capture.gd

const SETTLE_FRAMES := 90 # tufts, shadows, fog and the air's particles


func _initialize() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	main.random_course = false
	root.add_child(main)
	for i in 5:
		await process_frame
	var procgen: ProcgenParams = main.procgen
	var entry: Dictionary = {}
	for h in Procgen.course(1, procgen):
		if h.par == 4:
			entry = h
			break
	var out_dir := ProjectSettings.globalize_path("res://").path_join("../docs/art").simplify_path()
	main.get_node("Overlay").visible = false
	var camera := Camera3D.new()
	camera.fov = 62.0
	camera.far = 3000.0
	main.add_child(camera)
	for biome: Biome in procgen.biomes:
		var hole := GeneratedHole.new()
		hole.build(Procgen.hole(entry.seed, entry.par, procgen, biome), procgen)
		main.load_hole(hole)
		await process_frame
		main.get_node("Overlay").visible = false
		var tee: Vector3 = hole.tee.global_position
		var cup: Vector3 = hole.cup.global_position
		var aim := ((cup - tee) * Vector3(1, 0, 1)).normalized()
		var side := aim.cross(Vector3.UP)
		var eye := tee - aim * 28.0 + side * 9.0 + Vector3.UP * 16.0
		var look := tee + aim * 150.0
		look.y = hole.height_at(look)
		camera.look_at_from_position(eye, look)
		camera.make_current()
		for i in SETTLE_FRAMES:
			camera.make_current()
			await process_frame
		await RenderingServer.frame_post_draw
		var path := out_dir.path_join("biome-%s.png" % biome.name.replace("_", "-"))
		root.get_texture().get_image().save_png(path)
		print("  %s  %s" % [biome.name, path])
	print("hole: course 0x1, first par 4, seed 0x%s" % String.num_uint64(entry.seed, 16))
	quit()
