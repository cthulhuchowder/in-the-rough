extends SceneTree
## The shop's goofy items behave. Hats: Hat Green's ball rolls when the head moves and drops into
## the mini cup on a birdie (not on a par); Course Goose turns its head, blinks, and honks (beak
## open) on a bogey; Power Propeller spins up with power and sputters to a stop on a whiff, staying
## stopped until the next swing. Club heads: every Fresh Catch and Squeaky Set head has its flat face on
## the standard face plane (nothing of its body in front of it, the face reaching the face centre) and
## its tail or beak; an impact flops the tail, a big drive opens the beak. Trails: nothing while
## rolling, bits while flying, every bit gone within 2 s, the Duck Parade's pile where it lands kept
## until the next shot (and through the ball being placed at rest). Another player: their trail and hat
## as they wear them, reacting to their result and whiff.
## Run: godot --headless --fixed-fps 120 --path game -s res://tests/novelty_test.gd

const CHARACTER: CharacterParams = preload("res://data/character.tres")
const P: NoveltyParams = preload("res://data/novelty.tres")
const DT := 1.0 / 120.0

var _failed := false


func _check(ok: bool, what: String) -> void:
	_failed = _failed or not ok
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])


func _rig(item_id: String) -> GolferRig:
	var it := ShopCatalog.item(item_id)
	var rig := GolferRig.new(CHARACTER, ShopCatalog.look_for({ShopCatalog.tab_key(it.tab): item_id}))
	root.add_child(rig)
	rig.pose_idle()
	return rig


func _run(node: Node, seconds: float, each := Callable()) -> void:
	var t := 0.0
	while t < seconds:
		if each.is_valid():
			each.call(t)
		node._process(DT)
		t += DT


func _initialize() -> void:
	await process_frame # (in the tree: the toys read global transforms)
	# Every hat sits on the head and covers its top (rays up and out from the head's top 4 cm all meet it)
	var hats_ok := true
	var bare_note := ""
	for style in 6:
		var look: CharacterLook = ShopCatalog.DEFAULT_LOOK.duplicate()
		look.hat_style = style
		var wearer := GolferRig.new(CHARACTER, look)
		root.add_child(wearer)
		wearer.pose_idle()
		var r: Dictionary = HatCheck.report(wearer)
		hats_ok = hats_ok and r.checked > 10 and r.bare == 0
		bare_note += " %d:%d/%d" % [style, r.bare, r.checked]
		wearer.free()
	_check(hats_ok, "every hat style covers the head's top (style: bare/checked%s)" % bare_note)
	var beanie := HatToy.new(HatToy.Kind.PROPELLER, Vector3.ZERO, CHARACTER.head_size.x)
	root.add_child(beanie)
	var crown_top := -INF
	for part in beanie.get_children():
		if part is MeshInstance3D and part.get_parent() == beanie:
			var box: AABB = part.transform * (part as MeshInstance3D).mesh.get_aabb()
			if box.size.x > CHARACTER.head_size.x: # the crown and its band (not the stalk)
				crown_top = maxf(crown_top, box.end.y)
	var blades := INF
	for part in beanie._prop.get_children():
		blades = minf(blades, (beanie._prop.transform * part.transform * (part as MeshInstance3D).mesh.get_aabb()).position.y)
	_check(blades > crown_top + 0.01, "Power Propeller: the propeller turns clear above the crown (%.3f over it), on its stalk" % (blades - crown_top))
	beanie.free()

	# Hat Green
	var green_rig := _rig("hat_green")
	var green := green_rig.hat_toy
	var start := green._ball.position
	_run(green, 0.6, func(t: float) -> void: green_rig.position.x = 0.4 * sin(t * 9.0))
	_check(green._ball.position.distance_to(start) > 0.01, "Hat Green: its ball rolls when the head moves (%.3f m)" % green._ball.position.distance_to(start))
	green.react(0)
	_run(green, 0.5)
	var sunk_par: bool = green._sunk >= 0.0
	green.react(-1)
	_run(green, 0.6)
	var cup := Vector2(green._ball.position.x, green._ball.position.z).distance_to(green._cup)
	_check(not sunk_par and green._sunk > 0.0 and cup < 0.01 and green._ball.position.y < green._radius * (0.14 + P.green_ball) - 0.005,
		"Hat Green: a par leaves it; a birdie drops it into the mini cup (%.3f m off, %.3f low)" % [cup, green._radius * (0.14 + P.green_ball) - green._ball.position.y])

	# Course Goose
	var goose := _rig("hat_goose").hat_toy
	var seen := [0.0, 1.0, 0.0] # (lambdas capture by value: the most turned, the most closed eye, the widest beak)
	_run(goose, 8.0, func(_t: float) -> void:
		seen[0] = maxf(seen[0], absf(goose._head.rotation.y))
		seen[1] = minf(seen[1], goose._eyes[0].scale.y))
	goose.react(0)
	var quiet: bool = goose._honk < 0.0
	goose.react(1)
	_run(goose, P.goose_honk_time + 0.1, func(_t: float) -> void: seen[2] = maxf(seen[2], goose._jaw.rotation.x))
	_check(seen[0] > 0.1 and seen[1] < 0.5, "Course Goose: turns its head (%.2f rad) and blinks (eyes to %.2f) on its own" % [seen[0], seen[1]])
	_check(quiet and seen[2] > 0.3 and goose._honk < 0.0, "Course Goose: nothing on a par; a bogey honks, beak open %.2f rad, then it settles" % seen[2])

	# Power Propeller
	var prop := _rig("hat_propeller").hat_toy
	prop.power = 1.0
	_run(prop, 1.5)
	var full: float = prop._spin
	prop.power = 0.0
	prop.whiffed()
	_run(prop, P.sputter_time * 0.5)
	var mid: float = prop._spin
	_run(prop, P.sputter_time * 0.5 + 0.5)
	var stopped: float = prop._spin
	prop.power = 0.6
	_run(prop, 1.0)
	_check(full > P.propeller_max * 0.9 and mid > full * 0.1 and mid < full * 0.8 and stopped == 0.0 and prop._spin > P.propeller_max * 0.4,
		"Power Propeller: full power %.0f rad/s, a whiff sputters (%.0f) to a stop (%.0f), the next swing spins it again (%.0f)" % [full, mid, stopped, prop._spin])

	# Club heads on the standard face plane
	var worst_front := 0.0
	var worst_reach := 0.0
	var flops := true
	for style in [1, 2]:
		for club: ClubData in Clubs.ALL:
			var mat := LowPoly.material()
			var model := ClubModel.build(club, CHARACTER.bevel, CHARACTER.bevel_segments, mat, mat, mat, CHARACTER.club_scale, CHARACTER.club_head_scale, 1.0, style)
			root.add_child(model)
			var frame: Node3D = model.get_node("Head/Novelty")
			var face: MeshInstance3D = frame.get_child(0)
			var verts: PackedVector3Array = face.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var nearest := INF
			var centre := ClubModel.face_centre(club, CHARACTER.club_scale, CHARACTER.club_head_scale)
			var c := frame.basis.inverse() * centre # the face centre in the unlofted frame (on z = 0)
			for v in verts:
				worst_front = maxf(worst_front, -v.z) # in front of the face plane
				if absf(v.z) < 1e-5:
					nearest = minf(nearest, Vector2(v.x - c.x, v.y - c.y).length())
			worst_reach = maxf(worst_reach, nearest)
			flops = flops and frame.get_node_or_null("Tail" if style == 1 else "Beak") != null
			model.queue_free()
	_check(worst_front < 1e-5 and worst_reach < 0.03 and flops,
		"club heads: every novelty face on the standard plane (%.6f m in front at most), reaching the face centre (%.3f m), tail or beak there" % [worst_front, worst_reach])
	var fish := _rig("club_fish")
	fish.set_club(Clubs.ALL[6])
	fish.club_impact(1.0)
	var flop := [0.0]
	_run(fish, P.flop_time * 0.5, func(_t: float) -> void: flop[0] = maxf(flop[0], absf(fish._club_model.get_node("Head/Novelty/Tail").rotation.y)))
	var chicken := _rig("club_squeaky")
	chicken.set_club(Clubs.ALL[0])
	chicken.club_impact(0.95)
	_run(chicken, 0.1)
	var open: float = absf(chicken._club_model.get_node("Head/Novelty/Beak").rotation.z)
	chicken.club_impact(0.5)
	_run(chicken, 0.1)
	var shut: float = absf(chicken._club_model.get_node("Head/Novelty/Beak").rotation.z)
	_check(flop[0] > 0.3 and open > 0.5 and shut == 0.0, "impact: the fish's tail flops (%.2f rad); a 95%% drive opens the beak (%.2f), a 50%% one not" % [flop[0], open])

	# Trails: flight only, gone within 2 s, the duck pile
	var all_ok := true
	for style in [1, 2, 3]:
		var trail := BallTrail.new()
		trail.style = style
		trail.ground_y = 0.0
		root.add_child(trail)
		trail.start(Vector3.ZERO, 0.8)
		for k in 60: # rolling: nothing
			trail.feed(Vector3(k * 0.02, 0.05, 0))
		var rolled: int = trail._bits.size()
		var t0 := Time.get_ticks_usec()
		while Time.get_ticks_usec() - t0 < 600000: # flying 0.6 s
			trail.feed(Vector3(2.0, 3.0, 0))
			trail._process(DT)
			OS.delay_msec(5)
		var flew: int = trail._bits.size()
		trail.feed(Vector3(4.0, 0.05, 0)) # landed
		var piled: int = trail._pile.size()
		OS.delay_msec(2050)
		trail._process(DT)
		var left: int = trail._bits.size()
		trail.clear(true) # the ball placed at rest
		var kept: int = trail._pile.size()
		trail.start(Vector3.ZERO)
		var ok := rolled == 0 and flew > 3 and left == 0 and (piled == BallTrail.PILE and kept == BallTrail.PILE if style == 2 else piled == 0) and trail._pile.is_empty()
		print("    trail %d: rolling %d, flying %d, after 2 s %d, pile %d (kept %d)" % [style, rolled, flew, left, piled, kept])
		all_ok = all_ok and ok
		trail.queue_free()
	_check(all_ok, "trails: nothing rolling, bits flying, all gone within 2 s; the duck pile where it lands, kept at rest, gone on the next shot")

	# Another player wearing them
	var net := root.get_node("Net")
	net.players[7] = {name = "Cy", strokes = 0, score = -1, message = "", mulligans = 0,
		equipped = {"hat": "hat_goose", "trail": "trail_ducks", "ball": "ball_eyeball", "club_set": "club_squeaky"}}
	var puppets: Node3D = load("res://scripts/ball_puppets.gd").new() # (at run time: it names the Net autoload)
	puppets.character = CHARACTER
	puppets.look = ShopCatalog.DEFAULT_LOOK
	root.add_child(puppets)
	var view: Node3D = puppets._view(7)
	var their_look: CharacterLook = puppets.look_of(7)
	var cy := GolferRig.new(CHARACTER, their_look)
	puppets._rigs[7] = cy
	puppets.add_child(cy)
	puppets.react(7, 2)
	var honking: bool = cy.hat_toy != null and cy.hat_toy._honk >= 0.0
	_check((view.get_child(2) as BallTrail).style == 2 and their_look.ball_style == 4 and their_look.club_style == 2 and honking,
		"another player: their Duck Parade trail, Eyeball and Squeaky Set as they wear them; their goose honks at their double bogey")
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)
