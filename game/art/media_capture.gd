extends SceneTree
## Marketing media, rendered from the game itself at 1920x1080 (needs a window: Godot's --headless
## has no renderer). Stills go to docs/media/; GIF shots write numbered frames to --frames DIR (then
## tools/make_media.sh turns them into GIFs with ffmpeg).
##   banner    the menu's title scene (docs/media/title-scene.png; the banner is cropped from it)
##   biomes    one shot per biome from behind the tee (docs/media/biome-<name>.png)
##   shop      the shop turntable in a goofy outfit (docs/media/shop-outfit.png)
##   tee       a multiplayer tee box, three golfers (docs/media/multiplayer-tee.png)
##   drive     frames: first-person driver swing, impact and ball flight
##   putt      frames: a birdie putt dropping, the celebration after it
##   flyover   frames: the flyover of a deep forest hole
##   celebrate the birdie celebration at the cup (docs/media/celebration.png)
## Run: godot --path game --resolution 1920x1080 --fixed-fps 30 -s res://art/media_capture.gd -- --shot drive --frames /tmp/drive

const COURSE := 1 ## the default course's seed
const FOREST_HOLE := 5 ## course index of the deep forest flyover (as flyover_profile.gd)
const PUTT_DISTANCE := 2.6 ## m from the cup
const GOOFY := ["hat_goose", "shirt_flamingo", "pants_plaid", "shoes_clown", "ball_disco"]

var _out := ""
var _frames := ""
var _recording := false
var _frame := 0


func _initialize() -> void:
	_out = ProjectSettings.globalize_path("res://").path_join("../docs/media").simplify_path()
	DirAccess.make_dir_recursive_absolute(_out)
	_frames = _arg("frames", "")
	if _frames != "":
		DirAccess.make_dir_recursive_absolute(_frames)
	process_frame.connect(_record)
	match _arg("shot", ""):
		"banner": await _banner()
		"biomes": await _biomes()
		"shop": await _shop()
		"tee": await _tee()
		"drive": await _drive()
		"putt": await _putt(float(_arg("speed", "6.0")))
		"flyover": await _flyover()
		"celebrate": await _celebrate()
		_: push_error("--shot banner|biomes|shop|tee|drive|putt|flyover")
	quit()


func _arg(key: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--" + key)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback


## Every rendered frame while recording, numbered from 0.
func _record() -> void:
	if not _recording or _frames == "":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(_frames.path_join("%04d.jpg" % _frame), 0.95)
	_frame += 1


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _still(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _out.path_join(name)
	root.get_texture().get_image().save_png(path)
	print("  ", path)


func _biome(name: String) -> Biome:
	var p: ProcgenParams = load("res://data/procgen.tres")
	return p.biomes.filter(func(b: Biome) -> bool: return b.name == name)[0]


func _main() -> Node:
	var main: Node = load("res://main.tscn").instantiate()
	main.random_course = false
	root.add_child(main)
	await _wait(10)
	return main


func _hole_in(main: Node, index: int, biome: Biome) -> GeneratedHole:
	var entry: Dictionary = Procgen.course(COURSE, main.procgen)[index]
	var hole := GeneratedHole.new()
	hole.build(Procgen.hole(entry.seed, entry.par, main.procgen, biome), main.procgen)
	main.load_hole(hole, index + 1)
	await _wait(2)
	return hole


func _banner() -> void:
	var p: MenuSceneParams = load("res://data/menu_scene.tres")
	p.centre_screen_x = 0.5 # (no button column: the title in the middle)
	var procgen: ProcgenParams = load("res://data/procgen.tres")
	MenuScene.biome_override = procgen.biomes.find(_biome(_arg("biome", "parkland")))
	var scene := MenuScene.new()
	root.add_child(scene)
	await _wait(int(_arg("wait", "150")))
	await _still("title-scene.png")


func _biomes() -> void:
	var main := await _main()
	var camera := Camera3D.new()
	camera.fov = 60.0
	camera.far = 3000.0
	main.add_child(camera)
	var procgen: ProcgenParams = main.procgen
	for biome: Biome in procgen.biomes:
		if _arg("only", "") not in ["", biome.name]:
			continue
		main.set_process(true)
		var hole := await _hole_in(main, int(_arg("hole", "0")), biome)
		await _wait(10)
		main.set_process(false) # (frozen, the player's first-person club hidden: a view, not a stance)
		main._rig.visible = false
		main.get_node("Overlay").visible = false
		var tee: Vector3 = hole.tee.global_position
		var aim := ((hole.cup.global_position - tee) * Vector3(1, 0, 1)).normalized()
		var side := aim.cross(Vector3.UP)
		var eye := tee - aim * 7.0 - side * 3.0 + Vector3.UP * 3.2 # (the caddies stand off to the right)
		var look := tee + aim * 90.0
		look.y = hole.height_at(look) + 4.0
		for i in int(_arg("settle", "90")): # tufts, shadows, fog and the air's particles settle
			camera.look_at_from_position(eye, look)
			camera.make_current()
			main.get_node("Overlay").visible = false
			await process_frame
		await _still("biome-%s.png" % biome.name.replace("_", "-"))


func _shop() -> void:
	var shop: Node3D = load("res://shop.tscn").instantiate()
	root.add_child(shop)
	await _wait(5)
	shop._ui.visible = false
	var wearing := {}
	for id: String in GOOFY:
		wearing[id] = id
	shop.equipped = wearing
	shop._show_look()
	shop._camera.fov = 40.0
	shop._camera.look_at_from_position(Vector3(0.6, 1.5, 5.2), Vector3(0.6, 0.95, 0.0))
	shop._angle = PI - 0.45 # three-quarters on, facing the camera, when the shot is taken
	await _wait(int(_arg("wait", "40")))
	await _still("shop-outfit.png")


func _tee() -> void:
	var main := await _main()
	var hole := await _hole_in(main, 0, _biome("parkland"))
	await _wait(10)
	main.set_process(false) # (frozen: our own golfers stand in for the player's first-person one)
	main.set_physics_process(false)
	main._rig.visible = false
	main.get_node("Overlay").visible = false
	var ball: Vector3 = main._ball.global_position
	var tee: Vector3 = hole.tee.global_position
	var aim := ((hole.cup.global_position - tee) * Vector3(1, 0, 1)).normalized()
	var side := (-aim).cross(Vector3.UP)
	var character: CharacterParams = load("res://data/character.tres")
	var looks := [["hat_propeller", "shirt_mint", "pants_khaki", "shoes_bunny"], ["hat_green", "shirt_navy", "pants_knickers", "shoes_brogue"],
		["hat_goose", "shirt_flamingo", "pants_plaid", "shoes_clown"]]
	var rigs: Array[GolferRig] = []
	for k in 3:
		var wearing := {}
		for id: String in looks[k]:
			wearing[id] = id
		var rig := GolferRig.new(character, ShopCatalog.look_for(wearing))
		main.add_child(rig)
		rigs.append(rig)
	var feet := ball + side * rigs[0].club.stance_dist
	feet.y = hole.height_at(feet)
	var camera := Camera3D.new()
	camera.fov = 50.0
	main.add_child(camera)
	for i in 60:
		rigs[0].address(feet, aim, ball)
		rigs[0].pose_swing(float(_arg("angle", "-1.4")), 0.0)
		for k in [1, 2]: # waiting their turn, behind and to the side, watching
			var at: Vector3 = feet - aim * (2.2 + k * 0.8) - side * (0.6 + k * 1.3)
			at.y = hole.height_at(at)
			var to := (feet - at) * Vector3(1, 0, 1)
			rigs[k].transform = Transform3D(Basis(Vector3.UP, atan2(to.x, to.z) + PI), at)
			rigs[k].pose_idle()
		var eye := feet + aim * 4.0 - side * 5.5 + Vector3.UP * 1.5
		camera.look_at_from_position(eye, feet - aim * 1.6 - side * 1.2 + Vector3.UP * 0.9)
		camera.make_current()
		await process_frame
	await _still("multiplayer-tee.png")


func _drive() -> void:
	var main := await _main()
	await _hole_in(main, 0, _biome("parkland"))
	main.select_club(0)
	var feeder: MouseSwingFeeder = main.get_node("MouseSwingFeeder")
	var swing: Swing = main.get_node("Swing")
	await _wait(20)
	_recording = true
	await _wait(18) # at address
	for i in 72: # a slow backswing
		feeder.add_motion(Vector2(11, 0))
		await physics_frame
	for i in 24: # a beat at the top
		await physics_frame
	var ticks := 0
	while not swing.has_hit and ticks < 300:
		feeder.add_motion(Vector2(-110, 20.0 if ticks % 2 == 0 else -20.0))
		await physics_frame
		ticks += 1
	print("  drive: power %.2f" % swing.power)
	await _wait(int(_arg("after", "180"))) # the flight
	_recording = false


func _putt(speed: float) -> void:
	var main := await _main()
	var hole := await _hole_in(main, 0, _biome("parkland"))
	var cup: Vector3 = hole.cup.global_position
	var back := ((hole.tee.global_position - cup) * Vector3(1, 0, 1)).normalized()
	var at := cup + back * PUTT_DISTANCE
	at.y = hole.height_at(at)
	main._first_shot = false
	main._round.start(hole, at)
	main.strokes = 2 # this putt is the third on a par 4: a birdie
	await _wait(5)
	main.select_club(10)
	var feeder: MouseSwingFeeder = main.get_node("MouseSwingFeeder")
	var swing: Swing = main.get_node("Swing")
	await _wait(20)
	_recording = true
	await _wait(12)
	for i in 50:
		feeder.add_motion(Vector2(4, 0))
		await physics_frame
	for i in 12:
		await physics_frame
	var ticks := 0
	while not swing.has_hit and ticks < 600:
		feeder.add_motion(Vector2(-speed, 1.0 if ticks % 2 == 0 else -1.0))
		await physics_frame
		ticks += 1
	var t := 0
	while main.score < 0 and t < 600: # until it drops (or ten seconds)
		await process_frame
		t += 1
	print("  putt at %.1f px/tick: power %.3f, %s (score %d, %d strokes)" % [speed, swing.power, "HOLED" if main.score >= 0 else "missed", main.score, main.strokes])
	await _wait(int(_arg("after", "100"))) # the celebration
	_recording = false


func _flyover() -> void:
	var main := await _main()
	var p: ProcgenParams = main.procgen
	var entry: Dictionary = Procgen.course(COURSE, p)[FOREST_HOLE]
	var biome := _biome("deep_forest")
	var hole := GeneratedHole.new()
	hole.build(Procgen.hole(entry.seed, entry.par, p, biome), p)
	main.get_node("Overlay").visible = false
	var fly := Flyover.new() # as _begin_flyover (script runs skip it), with the hole already built
	main._flyover = fly
	main._swap_hole(hole, FOREST_HOLE + 1)
	main.restart()
	fly.params = main.FLYOVER
	main.add_child(fly)
	main._warm_up(fly)
	var done := [false]
	fly.finished.connect(func() -> void: done[0] = true)
	fly.finished.connect(main._flyover_done)
	var along := (hole.cup.global_position - hole.tee.global_position) * Vector3(1, 0, 1)
	fly.start(main._camera, hole, main._camera.global_transform, main._hole_card(), hole.wind, along, biome.display_name, biome.card_color)
	while fly._holding and not done[0]:
		await process_frame
	_recording = true
	while not done[0]:
		await process_frame
	await _wait(15)
	_recording = false


## The birdie celebration (Main._celebrate: the confetti and its second pop, the flag's hop), seen
## from beside the cup with the golfer who holed it standing back on the green.
func _celebrate() -> void:
	var main := await _main()
	var hole := await _hole_in(main, 0, _biome("parkland"))
	var cup: Vector3 = hole.cup.global_position
	var back := ((hole.tee.global_position - cup) * Vector3(1, 0, 1)).normalized()
	var side := back.cross(Vector3.UP)
	await _wait(10)
	main.set_process(false)
	main._rig.visible = false
	main.get_node("Overlay").visible = false
	var rig := GolferRig.new(load("res://data/character.tres"), ShopCatalog.look_for({a = "hat_green", b = "shirt_flamingo", c = "pants_white", d = "shoes_white"}))
	main.add_child(rig)
	var feet := cup + back * 2.8 + side * 0.6
	feet.y = hole.height_at(feet)
	var camera := Camera3D.new()
	camera.fov = 55.0
	main.add_child(camera)
	var eye := cup - back * 3.2 + side * 2.6 + Vector3.UP * 1.3
	main._celebrate(cup, -1)
	for i in int(_arg("wait", "22")):
		var to := (cup - feet) * Vector3(1, 0, 1)
		rig.transform = Transform3D(Basis(Vector3.UP, atan2(-to.x, -to.z)), feet)
		rig.pose_wave(float(i) / 30.0, 0.38, 0.62, 0.14, 1.4) # (arms up: the menu's wave)
		camera.look_at_from_position(eye, cup + back * 1.2 + Vector3.UP * 0.8)
		camera.make_current()
		await process_frame
	await _still("celebration.png")
