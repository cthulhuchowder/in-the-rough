extends SceneTree
## Loading hold: the flyover's black "Loading..." hold lifts only on the hole's `built` signal (never
## a timer), and a skip pressed during the hold waits for it: the hole is never shown half built.
## The progress bar climbs to 1. The hole's deferred build is forced on (script runs build at once).
## Run: godot --headless --fixed-fps 120 --path game -s res://tests/loading_hold_test.gd

var _failed := false


func _check(ok: bool, what: String) -> void:
	_failed = _failed or not ok
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])


func _initialize() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	main.random_course = false
	root.add_child(main)
	for i in 5:
		await process_frame
	var p: ProcgenParams = main.procgen
	var hole := GeneratedHole.new()
	hole.defer_forest = true # stream the out-of-bounds forest and props in over frames, as clients do
	var entry: Dictionary = Procgen.course(1, p)[0]
	hole.build(Procgen.hole(entry.seed, entry.par, p, p.biomes[5]), p) # deep forest: plenty to stream
	main.load_hole(hole)
	hole.stream_budget_ms = 0.3 # slow it down so the hold is long
	var fly := Flyover.new()
	fly.params = main.FLYOVER
	main.add_child(fly)
	fly.progress = hole.build_progress
	hole.built.connect(fly.release, CONNECT_ONE_SHOT)
	var done := [false, false] # finished, and whether the hole was still building then
	fly.finished.connect(func() -> void:
		done[0] = true
		done[1] = hole.is_building())
	var built_at := [-1]
	hole.built.connect(func() -> void: built_at[0] = Engine.get_process_frames())
	fly.start(main._camera, hole, main._camera.global_transform, "Hole 1", hole.wind, Vector3.FORWARD)
	await process_frame
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	Input.parse_input_event(key) # skip, while still building
	var frames := 0
	var progress := PackedFloat32Array()
	var early := false
	while not done[0] and frames < 6000:
		await process_frame
		frames += 1
		progress.append(hole.build_progress())
		early = early or (done[0] and done[1])
	var climbs := progress.size() > 2 and progress[0] < 0.9 and progress[-1] == 1.0
	for i in range(1, progress.size()):
		climbs = climbs and progress[i] >= progress[i - 1] - 0.0001
	_check(frames > 3 and built_at[0] > 0, "the hole streamed in over %d frames behind the black" % frames)
	_check(done[0] and not done[1] and not early, "skipped during the hold: cut to the shot only once the hole was built")
	_check(climbs, "the progress bar climbed to 1 (from %.2f)" % (progress[0] if progress.size() > 0 else -1.0))
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)
