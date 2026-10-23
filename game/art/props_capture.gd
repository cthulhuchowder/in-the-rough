extends SceneTree
## Close-ups of a biome's flora: docs/art/props-<biome>.png, its trees (a middle size each, three
## looks) on top and its props (every size) below, on its own rough under the project look.
## Run: godot --path game --resolution 1920x1080 -s res://art/props_capture.gd -- mystic_forest deep_forest oasis

const PROCGEN: ProcgenParams = preload("res://data/procgen.tres")


func _initialize() -> void:
	for name in OS.get_cmdline_user_args():
		var biome: Biome = load("res://data/biomes/%s.tres" % name)
		for row in [biome.trees, biome.props]:
			var stage := Node3D.new()
			root.add_child(stage)
			stage.add_child(load("res://art/presets/overcast.tscn").instantiate())
			var lawn := MeshInstance3D.new()
			var plane := PlaneMesh.new()
			plane.size = Vector2(400, 400)
			lawn.mesh = LowPoly.flat(plane, biome.rough_color)
			lawn.material_override = LowPoly.material()
			stage.add_child(lawn)
			var x := 0.0
			var tall := 0.0
			for kind: PropKind in row:
				var variants: Array = [kind.sizes.size() / 2, kind.sizes.size() / 2, kind.sizes.size() / 2] if row == biome.trees else range(kind.sizes.size())
				for i in variants.size():
					var size: Vector2 = kind.sizes[variants[i]]
					var gap := maxf(size.y * 2.4, 1.0)
					x += gap * 0.5
					var thing := Flora.build(kind, size, 0x7EE5 + int(x * 10.0) + i * 977, 0.0, PROCGEN.tree_surface)
					thing.position = Vector3(x, 0, 0)
					stage.add_child(thing)
					tall = maxf(tall, size.x + size.y * 2.0)
					x += gap * 0.5 + 0.3
			var cam := Camera3D.new()
			cam.fov = 32.0
			stage.add_child(cam)
			var fit := maxf(x * 0.56 / (tan(deg_to_rad(cam.fov * 0.5)) * 16.0 / 9.0), tall * 1.6)
			cam.look_at_from_position(Vector3(x * 0.5, tall * 0.7 + 0.4, fit), Vector3(x * 0.5, tall * 0.4, 0))
			cam.make_current()
			_save(await _grab(), "props-%s-%s.png" % [name, "trees" if row == biome.trees else "props"])
			stage.queue_free()
			await process_frame
	quit()


func _grab() -> Image:
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _save(shot: Image, file: String) -> void:
	var out := ProjectSettings.globalize_path("res://").path_join("../docs/art/" + file).simplify_path()
	shot.save_png(out)
	print("  " + out)
