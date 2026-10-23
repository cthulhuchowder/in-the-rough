extends SceneTree
## Biome ambience. Every biome has its set (data/soundscapes/): a base loop, a water loop and at least
## two kinds of one-shot, each file in game/audio/ambience/<biome>/; the loops run on seamlessly (the
## end into the start). In the game a generated hole's biome bed plays on the Ambience bus; one-shots
## turn up round the listener in 3D at their distances; the water loop sits on a real water hazard
## near the listener (and stops away from it); a celebration ducks the bus and it comes back; the
## Ambience slider sets the bus.
## Windowed (clients only build it): godot --path game -s res://tests/soundscape_test.gd

const BIOMES := ["parkland", "oasis", "underwater", "magma", "mystic_forest", "deep_forest", "cemetery"]

var _failed := false


func _check(ok: bool, what: String) -> void:
	_failed = _failed or not ok
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])


func _initialize() -> void:
	for name in BIOMES:
		var biome: Resource = load("res://data/biomes/%s.tres" % name)
		var set: SoundscapeSet = biome.soundscape
		var files := []
		var in_folder := true
		for s in ([set.base, set.water] if set else []):
			files.append(s)
		if set:
			for shot in set.shots:
				files.append_array(shot.streams)
		for f in files:
			in_folder = in_folder and f != null and (f as Resource).resource_path.begins_with("res://audio/ambience/%s/" % name)
		var seams := []
		for loop in ([set.base, set.water] if set else []):
			seams.append(_seam(loop.resource_path))
		_check(set != null and set.base != null and set.water != null and set.shots.size() >= 2 and in_folder and seams.all(func(s: float) -> bool: return s <= 1.0),
			"%s: a base loop, a water loop, %d kinds of one-shot (%d files) in audio/ambience/%s/, loops seamless (worst jump %.3f)" % [
			name, set.shots.size() if set else 0, files.size(), name, seams.max() if not seams.is_empty() else -1.0])

	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	var scape: Node3D = main._soundscape
	var hole: Hole = main._hole
	_check(scape != null and scape.bed != null and scape.bed == (hole as GeneratedHole).data.biome.soundscape and scape._base.playing and scape._base.bus == "Ambience",
		"in the game: the hole's biome bed (%s) plays on the Ambience bus" % ((hole as GeneratedHole).data.biome.name if hole is GeneratedHole else "?"))
	var listener := Node3D.new()
	root.add_child(listener)
	listener.global_position = hole.tee.global_position
	scape.follow(listener)
	var heard := []
	for t in 600: # a minute of shots, in 0.1 s steps
		scape._process(0.1)
		for c in scape.get_children():
			if c is AudioStreamPlayer3D and c != scape._water and not c.has_meta("seen"):
				c.set_meta("seen", true)
				heard.append(c.global_position.distance_to(listener.global_position))
	var reach := 0.0
	for shot in scape.bed.shots:
		reach = maxf(reach, shot.distance.y + shot.height.y + 5.0)
	_check(heard.size() >= 5 and heard.all(func(d: float) -> bool: return d > 2.0 and d < reach),
		"one-shots round the listener in a minute: %d, %.0f–%.0f m off" % [heard.size(), heard.min() if heard.size() else 0.0, heard.max() if heard.size() else 0.0])
	var wet := _a_water_point(hole)
	var number := 1
	while wet == Vector3.INF and number < 9: # a hole with water on it
		number += 1
		main.play_hole(number)
		for i in 20:
			await process_frame
		hole = main._hole
		scape.play(scape.bed, hole)
		wet = _a_water_point(hole)
	var dry: Vector3 = scape.nearest_water(hole, hole.tee.global_position)
	if wet != Vector3.INF:
		listener.global_position = wet + Vector3(6, 0, 0)
		scape.follow(listener)
		scape._search = 0.0
		scape._process(0.01)
		var at: Vector3 = scape._water.global_position
		_check(scape._water.playing and hole.surface_at(at).hazard == SurfaceData.Hazard.WATER and at.distance_to(listener.global_position) < 15.0,
			"near water: its loop plays on the water, %.1f m from the listener" % at.distance_to(listener.global_position))
	else:
		print("        (no water on this hole: the water loop's placement not checked; at the tee nearest water %s)" % dry)
	scape.duck(0.3)
	await create_timer(0.5).timeout
	var low: float = root.get_node("Settings").ambience_duck().volume_db
	await create_timer(2.2).timeout
	var back: float = root.get_node("Settings").ambience_duck().volume_db
	_check(low < -10.0 and absf(back) < 0.5, "a celebration ducks the Ambience bus (%.1f dB) and it comes back (%.1f dB)" % [low, back])
	root.get_node("Settings").ambience_volume = 0.5
	root.get_node("Settings").apply()
	var bus_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Ambience"))
	_check(absf(bus_db - linear_to_db(0.5)) < 0.1 and "ambience_volume" in root.get_node("Settings").get("KEYS"), "the Ambience slider sets the bus (50%% = %.1f dB), saved with the settings" % bus_db)
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


## The loop seam: the step from the last sample back to the first, against the file's own steps
## between neighbouring samples (its 99th percentile): ≤ 1 is no bigger than the sound itself makes.
func _seam(path: String) -> float:
	var wav := AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(path))
	var d := wav.data
	var steps := PackedFloat32Array()
	for i in range(2, d.size(), 2):
		steps.append(absf(d.decode_s16(i) - d.decode_s16(i - 2)))
	steps.sort()
	return absf(d.decode_s16(d.size() - 2) - d.decode_s16(0)) / maxf(steps[int(steps.size() * 0.99)], 1.0)


## Some point of water hazard on the hole (a coarse search over its ground), or INF.
func _a_water_point(hole: Hole) -> Vector3:
	var c := hole.cup.global_position
	var t := hole.tee.global_position
	for k in 400:
		var u := float(k) / 400.0
		var along := t.lerp(c, u)
		for side: float in [-40.0, -25.0, -12.0, 12.0, 25.0, 40.0]:
			var p := along + (c - t).cross(Vector3.UP).normalized() * side
			p.y = hole.height_at(p)
			if hole.surface_at(p).hazard == SurfaceData.Hazard.WATER:
				return p
	return Vector3.INF
