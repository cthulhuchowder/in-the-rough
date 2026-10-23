extends SceneTree
## The course's dressing. Underwater: every hole has its 2–4 major formations (big coral clusters and
## arches), each near a fairway edge with nothing else growing inside its footprint, and solid like a
## big tree. Deep forest: nothing in the 20 m lane in front of the tee along its aim, and the trees
## within 40 m thinned (against the same holes unthinned). Tee caddies: 1.5 m from each other and from
## the cart, the same spots every build. Oasis tumbleweeds: rolling downwind, hopping now and then, and
## never into the ground: their underside, every frame for 30 s on 3 seeds, at or above the surface the
## ball collides with (checked against the collider by rays).
## Run: godot --headless --fixed-fps 120 --path game -s res://tests/course_dressing_test.gd

const SEEDS := 12
const P: ProcgenParams = preload("res://data/procgen.tres")

var _failed := false


func _check(ok: bool, what: String) -> void:
	_failed = _failed or not ok
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])


func _biome(name: String) -> Biome:
	return P.biomes.filter(func(b: Biome) -> bool: return b.name == name)[0]


func _initialize() -> void:
	await process_frame
	# Underwater formations
	var reef := _biome("underwater")
	var counts := PackedInt32Array()
	var worst_edge := 0.0
	var intruders := 0
	for s in SEEDS:
		var d := Procgen.hole(0x5EEF00 + s * 7919, 4, P, reef)
		var m := d.metres_per_px
		var formations := 0
		for i in d.trees.size() / 4:
			var kind: PropKind = reef.trees[d.trees[4 * i + 2]]
			if kind.weight != 0.0:
				continue
			formations += 1
			var at := Vector2(d.trees[4 * i], d.trees[4 * i + 1]) / 100.0
			worst_edge = maxf(worst_edge, _to_fairway(d, at, P))
			var reach := kind.sizes[d.trees[4 * i + 3]].y * 0.6
			for j in d.trees.size() / 4:
				if j != i and at.distance_to(Vector2(d.trees[4 * j], d.trees[4 * j + 1]) / 100.0) < reach:
					intruders += 1
		counts.append(formations)
	var counts_ok := true
	for c in counts:
		counts_ok = counts_ok and c >= 2 and c <= 4
	_check(counts_ok and worst_edge < 35.0 and intruders == 0,
		"underwater: 2–4 formations a hole %s, each within %.0f m of a fairway edge, nothing inside one (%d)" % [counts, worst_edge, intruders])
	var solid := true
	for kind in reef.trees.filter(func(k: PropKind) -> bool: return k.weight == 0.0):
		var body := Flora.build(kind, kind.sizes[1], 1, 0.0, P.tree_surface, Vector3.ONE, false)
		solid = solid and body is StaticBody3D and body.find_children("*", "CollisionShape3D", true, false).size() >= 2
		body.free()
	_check(solid, "underwater: the cluster and the arch are solid bodies like big trees (colliders, a soft canopy on the cluster)")

	# Deep forest tee lane
	var forest := _biome("deep_forest")
	var open := forest.duplicate() as Biome
	open.tee_clear_ahead = 0.0
	var in_lane := 0
	var near := 0
	var near_open := 0
	for s in SEEDS:
		var seed := 0xF0E500 + s * 104729
		for pass_ in 2:
			var d := Procgen.hole(seed, 4, P, forest if pass_ == 0 else open)
			var tee := Vector2(d.tee) * d.metres_per_px
			var aim := (d.route[1] - d.route[0]).normalized()
			for i in d.trees.size() / 4:
				var at := Vector2(d.trees[4 * i], d.trees[4 * i + 1]) / 100.0 - tee
				var ahead := at.dot(aim)
				var aside := absf(at.cross(aim))
				if pass_ == 0 and ahead > -2.0 and ahead < 20.0 and aside < forest.tee_clear_width:
					in_lane += 1
				if at.length() < 40.0:
					if pass_ == 0:
						near += 1
					else:
						near_open += 1
	_check(in_lane == 0 and near_open > 0 and near < near_open * 0.6,
		"deep forest: no trees in the 20 m lane ahead of the tee; within 40 m %d trees, against %d unthinned" % [near, near_open])

	# The line of play, every biome, pars 3–5: no tree and no big prop within the corridor's half width
	# of the route (25 m wide at the tee, 15 m at the green)
	var intruding := 0
	var holes := 0
	var small_in := 0
	for biome in P.biomes:
		for s in 6:
			var d := Procgen.hole(0xC0441D0 + s * 6007 + biome.name.hash() % 997, 3 + s % 3, P, biome)
			holes += 1
			for list in [d.trees, d.props]:
				for i in list.size() / 4:
					var at := Vector2(list[4 * i], list[4 * i + 1]) / 100.0
					var r: Vector2 = _route_reach(d, at)
					var canopy: float = biome.trees[list[4 * i + 2]].sizes[list[4 * i + 3]].y * P.corridor_canopy if list == d.trees else 0.0
					if r.x >= (P.corridor_width.x + (P.corridor_width.y - P.corridor_width.x) * r.y) * 0.5 + canopy:
						continue
					var big: bool = list == d.trees
					if not big:
						var kind: PropKind = biome.props[list[4 * i + 2]]
						big = kind.shape in [PropKind.Shape.LOG, PropKind.Shape.STUMP] or kind.sizes[list[4 * i + 3]].y >= P.corridor_big_prop
					if big:
						intruding += 1
					else:
						small_in += 1
	_check(intruding == 0, "the line of play: %d holes, every biome, no tree (nor its canopy) or big prop in the 25 → 15 m corridor (%d small props there)" % [holes, small_in])

	# Tee caddies
	var spacing_ok := true
	var same := true
	var closest := INF
	for biome in P.biomes:
		for s in 3:
			var d := Procgen.hole(0xCADD1E + s * 31 + biome.name.hash() % 1000, 4, P, biome)
			var spots := []
			for build in 2:
				var hole := GeneratedHole.new()
				hole.build(d, P)
				root.add_child(hole)
				var props := TeeProps.new(hole)
				var cart: Node3D = props.get_child(0) if props.get_child_count() > 0 else null
				var stood: Array[Vector3] = []
				for c in props._caddies:
					if cart and not TeeProps.caddy_clear(c.position, stood, cart):
						spacing_ok = false
					for o in stood:
						closest = minf(closest, Vector2(c.position.x - o.x, c.position.z - o.z).length())
					stood.append(c.position)
				spots.append(stood)
				props.free()
				hole.free()
			same = same and spots[0] == spots[1]
	_check(spacing_ok and same, "tee caddies: 1.5 m from each other (closest %.2f m) and from the cart, the same every build" % closest)

	# Oasis tumbleweeds: 30 s on 3 seeds. Each frame, each ball's underside against the ground the ball
	# collides with, measured independently: 64 points over its footprint (the ball's centre is its
	# Spin pivot), the surface from the hole's own collider by physics rays at a sample of them
	for s in 3:
		var hole := GeneratedHole.new()
		hole.build(Procgen.hole(0x70BB1E + s * 7741, 4, P, _biome("oasis")), P)
		root.add_child(hole)
		await physics_frame
		await physics_frame
		if hole.wind.length() < 0.5:
			hole.wind = Vector3(3.0, 0, 1.0)
		var weeds: Array = hole._tumbleweeds
		var starts := []
		for t in weeds:
			starts.append(t[0].position)
		var space := hole.get_world_3d().direct_space_state
		var lowest := INF # the least clearance seen, m
		var ray_worst := 0.0 # ground_at() against the collider's rays
		var air := 0.0
		for frame in 1800: # 30 s at 60 frames a second
			hole._process(1.0 / 60.0)
			for k in weeds.size():
				var node: Node3D = weeds[k][0]
				var r: float = node.get_meta("tumbleweed")
				var centre := node.global_position + Vector3(0, r, 0)
				for i in 64:
					var a: float = TAU * i / 16.0 + floor(i / 16.0) * 0.3
					var d: float = r * (0.15 + 0.27 * floor(i / 16.0)) # four rings, out to 0.96 r
					var p := centre + Vector3(cos(a) * d, 0.0, sin(a) * d)
					var under_y := centre.y - sqrt(r * r - d * d)
					var g := hole.ground_at(p)
					if frame % 120 == 0 and i % 16 == 0 and k % 4 == 0: # the collider itself, now and then
						var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, p.y + 50.0, p.z), Vector3(p.x, p.y - 50.0, p.z)))
						if not hit.is_empty() and hit.collider == hole.get_node("Ground"):
							ray_worst = maxf(ray_worst, absf(hit.position.y - g))
							g = maxf(g, hit.position.y)
					lowest = minf(lowest, under_y - g)
				air = maxf(air, node.position.y - hole.ground_at(node.position))
		var downwind := 0
		for k in weeds.size(): # rolling with the wind now (a long way down they start over upwind)
			var v: Vector3 = weeds[k][2]
			if Vector2(v.x, v.z).dot(Vector2(hole.wind.x, hole.wind.z)) > 0.0:
				downwind += 1
		print("    oasis seed %d: %d tumbleweeds, min clearance %.4f m over 30 s, ground_at vs collider rays %.5f m, hops to %.2f m" % [s, weeds.size(), lowest, ray_worst, air])
		_check(weeds.size() > 0 and lowest >= 0.0 and ray_worst < 0.001 and air > 0.1 and downwind >= weeds.size() * 0.8,
			"oasis seed %d: %d tumbleweeds roll downwind (%d) and hop, their underside never below the ground (%.4f m at least)" % [s, weeds.size(), downwind, lowest])
		hole.free()
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


## (m from `at` to the route, how far along it that nearest point is: 0 at the tee .. 1 at the cup).
func _route_reach(d, at: Vector2) -> Vector2:
	var m: float = d.metres_per_px
	var total := 0.0
	for k in d.route.size() - 1:
		total += (d.route[k + 1] - d.route[k]).length() * m
	var best := INF
	var along := 0.0
	var run := 0.0
	for k in d.route.size() - 1:
		var a: Vector2 = d.route[k] * m
		var b: Vector2 = d.route[k + 1] * m
		var t := clampf((at - a).dot(b - a) / maxf((b - a).length_squared(), 1e-6), 0.0, 1.0)
		var dist := at.distance_to(a.lerp(b, t))
		if dist < best:
			best = dist
			along = run + a.distance_to(b) * t
		run += a.distance_to(b)
	return Vector2(best, along / maxf(total, 1.0))


## m from `at` to the nearest fairway pixel.
func _to_fairway(d, at: Vector2, p: ProcgenParams) -> float:
	var n: int = d.size
	var m: float = d.metres_per_px
	var on := p.surface_threshold * 255.0
	var best := INF
	var c := at / m
	for z in range(maxi(0, int(c.y) - 60), mini(n, int(c.y) + 61)):
		for x in range(maxi(0, int(c.x) - 60), mini(n, int(c.x) + 61)):
			if d.fairway[z * n + x] > on:
				best = minf(best, Vector2(x - c.x, z - c.y).length() * m)
	return best
