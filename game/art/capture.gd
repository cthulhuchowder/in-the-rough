extends SceneTree
## Renders the art-direction mocks: course seed 0x1, hole 1, seen from behind the golfer on the
## tee, once per preset, to docs/art/mock-*.png at 1920x1080. Godot's --headless has no
## renderer, so this needs a (small) window; the shot itself is an offscreen 1920x1080 viewport.
## Run: godot --path game --resolution 480x270 -s res://art/capture.gd

const PRESETS := {"a": "res://art/presets/morning.tscn", "b": "res://art/presets/cartoon.tscn",
	"c": "res://art/presets/overcast.tscn"}
const SIZE := Vector2i(1920, 1080)
const SETTLE_FRAMES := 20 # shadows and fog need a few frames


func _initialize() -> void:
	_run()


func _run() -> void:
	var procgen: ProcgenParams = load("res://data/procgen.tres")
	var rules: RulesData = load("res://data/rules.tres")
	var entry: Dictionary = Procgen.course(1, procgen)[0]
	var data := Procgen.hole(entry.seed, entry.par, procgen)
	var out_dir := ProjectSettings.globalize_path("res://").path_join("../docs/art").simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	for key in PRESETS:
		var view := SubViewport.new()
		view.size = SIZE
		view.own_world_3d = true
		view.msaa_3d = Viewport.MSAA_4X
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(view)
		var art: ArtPreset = load(PRESETS[key]).instantiate()
		view.add_child(art)
		var hole := GeneratedHole.new()
		hole.build(data, procgen)
		view.add_child(hole)
		await process_frame # let the hole run _ready (tee, cup)
		ArtDresser.dress(hole, art)

		var ball := hole.rest_point(hole.tee.global_position, rules.drop_height)
		var aim := hole.cup.global_position - ball
		aim.y = 0.0
		aim = aim.normalized()
		view.add_child(ArtDresser.ball(art, ball))
		view.add_child(ArtDresser.golfer(art, ball, aim, hole.height_at(ball)))
		var side := (-aim).cross(Vector3.UP)
		var camera := Camera3D.new()
		camera.fov = 62.0
		camera.far = 3000.0
		view.add_child(camera)
		var eye := ball - aim * 6.5 + side * 2.2 + Vector3.UP * 2.6
		var look := ball + aim * 70.0
		look.y = hole.height_at(look) + 1.0
		camera.look_at_from_position(eye, look)
		camera.current = true

		for i in SETTLE_FRAMES:
			await process_frame
		var path := out_dir.path_join("mock-%s.png" % key)
		view.get_texture().get_image().save_png(path)
		print("  %s  %s" % [key, path])
		view.queue_free()
		await process_frame
	print("hole: course 0x1, hole 1, par %d, seed 0x%s" % [entry.par, String.num_uint64(entry.seed, 16)])
	quit()
