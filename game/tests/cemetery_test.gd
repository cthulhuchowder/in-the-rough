extends SceneTree
## The Cemetery biome. In the lobby's biome list and the Mixed rotation; its holes have gravestones,
## mausoleums (big obstacles, as formations), fence runs laid along the line of play with gaps, gnarled
## trees, dead bushes, pumpkins and flickering jack-o'-lanterns; its water is the bog, with bubbles;
## crows perch near the line of play and fly off (gone in a few seconds) when a ball comes down near
## them. (50 seeds playable and deterministic, and the line-of-play corridor: procgen_test and
## course_dressing_test, which cover every biome.)
## Run: godot --headless --fixed-fps 120 --path game -s res://tests/cemetery_test.gd

const P: ProcgenParams = preload("res://data/procgen.tres")

var _failed := false


func _check(ok: bool, what: String) -> void:
	_failed = _failed or not ok
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])


func _initialize() -> void:
	await process_frame
	var biome: Biome = P.biomes.filter(func(b: Biome) -> bool: return b.name == "cemetery")[0]
	var index := P.biomes.find(biome)
	var mixed := {}
	for h in Procgen.course(0xC0FFEE, P).slice(0, P.biomes.size()):
		mixed[P.biomes[h.biome].name] = true
	_check(RoomRules.BIOMES[index + 1] == "Cemetery" and mixed.has("cemetery") and biome.water_name == "bog",
		"in the lobby's list (%s) and the Mixed rotation; its water is the bog" % RoomRules.BIOMES[index + 1])

	var seen := {}
	var fences_along := true
	var fence_count := 0
	var crows := 0
	var bubbles := 0
	var fled := true
	for s in 6:
		var d := Procgen.hole(0xCE3E + s * 977, 3 + s % 3, P, biome)
		for list in [d.trees, d.props]:
			for i in list.size() / 4:
				var kind: PropKind = (biome.trees if list == d.trees else biome.props)[list[4 * i + 2]]
				seen[kind.resource_path.get_file().get_basename()] = true
		var hole := GeneratedHole.new()
		hole.build(d, P)
		root.add_child(hole)
		for node in hole.get_children(): # fence runs lie along the route where they stand
			if node is StaticBody3D and node.get_child_count() > 0 and node.get_child(0) is CollisionShape3D:
				var box := (node.get_child(0) as CollisionShape3D).shape as BoxShape3D
				if box and box.size.x > 5.0 and box.size.z < 0.2: # (a fence: long and thin; not a mausoleum)
					fence_count += 1
					var want := hole._route_yaw(Vector2(node.position.x, node.position.z))
					fences_along = fences_along and absf(wrapf(node.rotation.y - want, -PI, PI)) < 0.01
		var life := BiomeLife.new(hole)
		hole.add_child(life)
		crows += life._crows.size()
		bubbles += life.get_children().filter(func(c: Node) -> bool: return c is CPUParticles3D).size()
		if not life._crows.is_empty(): # a ball comes down by the first crow: it caws and flies, then is gone
			var crow: Node3D = life._crows[0][0]
			var ball := Node3D.new()
			ball.add_to_group("balls")
			hole.add_child(ball)
			ball.global_position = crow.global_position + Vector3(3.0, 0.5, 0.0)
			life._process(1.0 / 60.0)
			var flying: bool = life._crows[0][2] == 1
			var from := crow.global_position
			for k in 60 * 5:
				life._process(1.0 / 60.0)
			fled = fled and flying and crow.global_position.distance_to(from) > 10.0 and not crow.visible
		hole.free()
	var want := ["gravestone", "mausoleum", "iron_fence", "gnarled_tree", "dead_bush", "pumpkin", "jack_o_lantern"]
	var all := want.all(func(k: String) -> bool: return seen.has(k))
	_check(all, "every Cemetery kind stands on its holes (%s)" % [seen.keys()])
	_check(fence_count > 10 and fences_along, "fence runs: %d over 6 holes, each laid along the line of play" % fence_count)
	_check(crows > 0 and fled, "crows: %d perched near the line of play; a ball landing by one sets it off — it flies away and is gone" % crows)
	_check(bubbles > 0, "bog bubbles: %d spots on the water" % bubbles)
	var jack: PropKind = load("res://data/props/jack_o_lantern.tres")
	var mat := Flora.material_for(jack) as ShaderMaterial
	_check(mat != null and float(mat.get_shader_parameter("flicker")) > 0.0 and float(mat.get_shader_parameter("glow")) > 0.0,
		"jack-o'-lanterns glow and flicker (glow %.1f, flicker %.2f)" % [jack.glow, jack.flicker])
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)
