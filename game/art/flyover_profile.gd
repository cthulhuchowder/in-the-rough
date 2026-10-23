extends SceneTree
## Flyover frame-time profile: for three holes (parkland, deep forest, mystic forest) the real
## flyover — the hole streamed in behind the black hold as in the game, then the flight — with vsync
## off; each frame's time, phase, draw calls, objects drawn, pipeline (shader) compiles and node
## count. Prints the worst frames per hole and a summary line.
## Run: godot --path game --resolution 1920x1080 -s res://art/flyover_profile.gd

const HOLES := [[0, "parkland"], [5, "deep_forest"], [4, "mystic_forest"]] ## [course index, biome]
const WORST := 6


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var main: Node = load("res://main.tscn").instantiate()
	main.random_course = false
	root.add_child(main)
	for i in 10:
		await process_frame
	var p: ProcgenParams = main.procgen
	var course := Procgen.course(1, p)
	var summary := []
	for h in HOLES:
		var entry: Dictionary = course[h[0]]
		var biome: Biome = p.biomes.filter(func(b): return b.name == h[1])[0]
		if OS.get_environment("PROFILE_NO_TUFTS") != "":
			biome = biome.duplicate()
			biome.tufts_per_m2 = 0.0
		if OS.get_environment("PROFILE_NO_RIVER") != "":
			biome = biome.duplicate()
			biome.rivers = 0
		var hole := GeneratedHole.new()
		hole.defer_forest = true # stream in as on a client
		hole.build(Procgen.hole(entry.seed, entry.par, p, biome), p)
		main.get_node("Overlay").visible = false # as _begin_flyover: no HUD over the flyover (it fades back in after)
		var fly := Flyover.new()
		main._flyover = fly # (set before the address, so the caddy's pulse waits for it, as in the game)
		main._swap_hole(hole, 1)
		main.restart()
		fly.params = main.FLYOVER
		main.add_child(fly)
		if hole.is_building():
			fly.progress = hole.build_progress
			hole.built.connect(main._warm_up.bind(fly), CONNECT_ONE_SHOT) # (as the game: shader warm-up, then the lift)
			hole.stream_budget_ms = main.FLYOVER.hold_budget_ms
			fly.hold_ended.connect(func() -> void: hole.stream_budget_ms = GeneratedHole.STREAM_BUDGET_MS)
		else:
			main._warm_up(fly)
		var along := (hole.cup.global_position - hole.tee.global_position) * Vector3(1, 0, 1)
		var done := [false]
		fly.finished.connect(func() -> void: done[0] = true)
		fly.finished.connect(main._flyover_done)
		fly.start(main._camera, hole, main._camera.global_transform, main._hole_card(), hole.wind, along, biome.display_name, biome.card_color)
		var frames := []
		var last := Time.get_ticks_usec()
		var compiles_before := _compiles()
		while not done[0] and frames.size() < 12000:
			await process_frame
			if done[0] or not is_instance_valid(fly):
				break
			var now := Time.get_ticks_usec()
			var c := _compiles()
			frames.append({ms = (now - last) / 1000.0, phase = "hold" if fly._holding else "flight %.1fs" % fly._t,
				draws = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
				objects = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
				compiles = c - compiles_before, nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))})
			if c != compiles_before:
				print("    compiles at %s: canvas %d mesh %d surface %d draw %d specialization %d" % [fly._t, Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_CANVAS), Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH), Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE), Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW), Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION)])
			compiles_before = c
			last = now
		var flight := frames.filter(func(f): return f.phase != "hold")
		var sorted := flight.duplicate()
		sorted.sort_custom(func(a, b): return a.ms > b.ms)
		var total := 0.0
		for f in flight:
			total += f.ms
		var compiled := 0
		for f in flight:
			compiled += f.compiles
		print("— %s (seed 0x%s): %d hold frames, %d flight frames, mean %.1f ms, worst %.1f ms, %d pipeline compiles in flight, %d nodes" % [
			h[1], String.num_uint64(entry.seed, 16), frames.size() - flight.size(), flight.size(), total / maxf(flight.size(), 1),
			sorted[0].ms if not sorted.is_empty() else 0.0, compiled, flight[-1].nodes if not flight.is_empty() else 0])
		for f in sorted.slice(0, WORST):
			print("    %6.1f ms  %-12s draws %5d  objects %5d  compiles %d" % [f.ms, f.phase, f.draws, f.objects, f.compiles])
		var p99: float = sorted[int(sorted.size() * 0.01)].ms if not sorted.is_empty() else 0.0
		var slow := flight.filter(func(fr): return fr.ms > 4.0).size()
		summary.append("%s worst %.1f ms p99 %.1f ms, %d frames > 4 ms, %d compiles" % [h[1], sorted[0].ms if not sorted.is_empty() else 0.0, p99, slow, compiled])
		for i in 30:
			await process_frame
	print("SUMMARY ", " | ".join(summary))
	quit()


func _compiles() -> int:
	var n := 0
	for m in [Performance.PIPELINE_COMPILATIONS_CANVAS, Performance.PIPELINE_COMPILATIONS_MESH, Performance.PIPELINE_COMPILATIONS_SURFACE,
			Performance.PIPELINE_COMPILATIONS_DRAW, Performance.PIPELINE_COMPILATIONS_SPECIALIZATION]:
		n += int(Performance.get_monitor(m))
	return n
