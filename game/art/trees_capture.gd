extends SceneTree
## Parkland renders: docs/art/trees.png (every tree species in each size variant, then bushes and
## rocks, on a flat lawn under the project look) and docs/art/hole-parkland.png (hole 1 of the
## default course from the tee).
## Run: godot --path game --resolution 1920x1080 -s res://art/trees_capture.gd

const BIOME: Biome = preload("res://data/biomes/parkland.tres")
const PROCGEN: ProcgenParams = preload("res://data/procgen.tres")


func _initialize() -> void:
	# Lineup
	var stage := Node3D.new()
	root.add_child(stage)
	stage.add_child(load("res://art/presets/overcast.tscn").instantiate())
	var lawn := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	lawn.mesh = LowPoly.flat(plane, BIOME.rough_color)
	lawn.material_override = LowPoly.material()
	stage.add_child(lawn)
	var x := 0.0
	var kinds: Array[PropKind] = BIOME.trees + BIOME.props
	for kind in kinds:
		for v in kind.sizes.size():
			var size := kind.sizes[v]
			var gap := maxf(size.y * 2.2, 1.6)
			x += gap * 0.5
			var thing := Flora.build(kind, size, 0x7EE5 + int(x * 10.0), 0.0, PROCGEN.tree_surface)
			thing.position = Vector3(x, 0, 0)
			stage.add_child(thing)
			x += gap * 0.5 + 0.6
	var cam := Camera3D.new()
	cam.fov = 32.0
	stage.add_child(cam)
	var fit := x * 0.56 / (tan(deg_to_rad(cam.fov * 0.5)) * 16.0 / 9.0) # the whole row across the frame
	cam.look_at_from_position(Vector3(x * 0.5, 4.5, fit), Vector3(x * 0.5, 2.4, 0))
	cam.make_current()
	_save(await _grab(), "trees.png")
	stage.queue_free()
	await process_frame

	# Hole 1 from the tee
	var main: Node = load("res://main.tscn").instantiate()
	main.random_course = false # the default course, so the render is repeatable
	root.add_child(main)
	main.get_node("Overlay").visible = false
	for i in 5:
		await process_frame
	var hole: Hole = main._hole
	var tee := hole.tee.global_position
	var ahead := (hole.centreline[1] - tee) * Vector3(1, 0, 1)
	ahead = ahead.normalized()
	var eye := tee + ahead * 4.0 # just in front of the tee, so the ball and club are behind the camera
	eye.y = hole.height_at(eye) + 2.6
	var view := Camera3D.new()
	view.fov = 55.0
	main.add_child(view)
	view.look_at_from_position(eye, tee + ahead * 120.0 + Vector3.UP * (hole.height_at(tee + ahead * 120.0) - tee.y))
	view.make_current()
	_save(await _grab(), "hole-parkland.png")
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
