extends SceneTree
## Headless check of the hole generator, per biome: 50 seeds each, each playable (tee reaches the
## cup over non-hazard ground, no hazard on tee pad or cup, no sand under water), each generated
## twice with identical bytes (terrain, trees with species, variant and size, props, biome), the
## planting rules held. Courses: mixed rotates through every biome, a single pick holds for all
## holes. Prints digests to compare against another machine.
## Run: godot --headless --path game -s res://tests/procgen_test.gd

const SEEDS := 50
## Digest of the first seed's hole in each biome: update when the generator changes on purpose.
const FINGERPRINTS := {
	"parkland": "a1799cd421e57296e470bf673a9349ae034dfecc7a8a68a3e09b22c199ec3944",
	"oasis": "53b427ac0ccb7c00da0a950e121dfb840c3d55376e17f0815fc044579d599e87",
	"underwater": "2316862b7a94e17df833e0361d04bf9a6a843a7c364a91d81a3fdcd73d50accd",
	"magma": "ae9176482817e6f134a8b75296e7b2cd9b0a5bf662f235665d48e4562b34d88d",
	"mystic_forest": "cc244d9dee0c0722cf44ae44a3b59b89deec0b3a9fcc96fd1896796c8979edd8",
	"deep_forest": "7dab0ef6a9748ec81cb97944965734fef45a30662036571b8c87dd365028c360",
	"cemetery": "1b83491c159c6451faab1368a9194987d1d5e6394d3c80735efa561648363ced",
}

var _failed := false


func _initialize() -> void:
	var p: ProcgenParams = load("res://data/procgen.tres")
	var started := Time.get_ticks_msec()

	var course := Procgen.course(p.default_course_seed, p)
	_check(course == Procgen.course(p.default_course_seed, p), "course is deterministic")
	for nine in course.size() / 9:
		var count := {3: 0, 4: 0, 5: 0}
		for h in course.slice(nine * 9, nine * 9 + 9):
			count[h.par] += 1
		_check(count == {3: 3, 4: 3, 5: 3}, "nine %d has three each of par 3/4/5" % (nine + 1))
	var first: Array = course.slice(0, p.biomes.size()).map(func(h): return h.biome)
	var rotates := first.duplicate()
	rotates.sort()
	_check(rotates == range(p.biomes.size()) and course.all(func(h): return h.biome == first[(h.number - 1) % first.size()]),
		"mixed: the round rotates through every biome, in an order from the course seed (%s)" % [first.map(func(b): return p.biomes[b].name)])
	var single := Procgen.course(p.default_course_seed, p, 4)
	_check(single.all(func(h): return h.biome == 3), "one biome picked: every hole is %s" % p.biomes[3].name)
	_check(RoomRules.BIOMES.size() == p.biomes.size() + 1 and range(p.biomes.size()).all(func(k): return RoomRules.BIOMES[k + 1].to_lower().replace(" ", "_") == p.biomes[k].name),
		"the lobby's biome names match ProcgenParams.biomes")
	for biome in p.biomes:
		_biome_run(p, biome)
	print("  %d biomes × %d holes ×2 in %.1f s" % [p.biomes.size(), SEEDS, (Time.get_ticks_msec() - started) / 1000.0])
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _biome_run(p: ProcgenParams, biome: Biome) -> void:
	print("— %s —" % biome.name)
	var total_trees := 0
	var landmarks := 0
	var rough_trees := 0
	var forest_trees := 0
	var rough_km2 := 0.0
	var forest_km2 := 0.0
	var undergrowth := 0
	var water_px := 0
	var seen := {} # "t<species>/<variant>", "p<kind>/<variant>" placed somewhere
	var seeds := Procgen.Rng.new(0x5EED)
	for k in SEEDS:
		var seed := seeds.u64()
		var par := 3 + k % 3
		var a := Procgen.hole(seed, par, p, biome)
		var b := Procgen.hole(seed, par, p, biome)
		var same := a.digest() == b.digest() and a.heights == b.heights and a.bunker == b.bunker and a.trees == b.trees \
			and a.props == b.props and a.tree_scale == b.tree_scale
		var problem := _playability(a, p)
		if problem == "":
			problem = _tree_rules(a, p)
		if problem == "":
			problem = _tree_sizes(a)
		for t in a.tree_scale.size() / 3:
			landmarks += 1 if a.tree_scale[3 * t] == roundi(a.biome.landmark_scale * 1000.0) else 0
		rough_trees += a.forest_from
		forest_trees += a.trees.size() / 4 - a.forest_from
		rough_km2 += Procgen._allowed(a, p)[1].size() * a.metres_per_px * a.metres_per_px / 1e6
		forest_km2 += Procgen._forest_spots(a, p, a.biome)[1].size() * a.metres_per_px * a.metres_per_px / 1e6
		undergrowth += a.props.size() / 4 - a.undergrowth_from
		for i in a.size * a.size:
			water_px += 1 if a.heights[i] < a.water and a.rough[i] < p.oob_threshold * 255.0 else 0
		var length := Vector2(a.cup - a.tee).length() * p.metres_per_px
		total_trees += a.trees.size() / 4
		var mix := ""
		for s in a.biome.trees.size():
			var here := 0
			for t in a.trees.size() / 4:
				if a.trees[4 * t + 2] == s:
					here += 1
					seen["t%d/%d" % [s, a.trees[4 * t + 3]]] = true
			mix += "%s%d" % ["" if s == 0 else "/", here]
		for t in a.props.size() / 4:
			seen["p%d/%d" % [a.props[4 * t + 2], a.props[4 * t + 3]]] = true
		if not same or problem != "":
			print("  FAIL  seed %s  par %d  %3.0f m  %3d trees (%s by species)  %3d props  %s" % [String.num_uint64(seed, 16), par, length,
				a.trees.size() / 4, mix, a.props.size() / 4, problem if problem != "" else "not deterministic"])
		_failed = _failed or not same or problem != ""
		if k == 0:
			var want: String = FINGERPRINTS.get(biome.name, "")
			print("  digest of first seed: %s" % a.digest())
			_check(a.digest() == want, "%s: the first seed's fingerprint is the recorded one (%s)" % [biome.name, want.left(16)])

	_check(total_trees > SEEDS * 5, "%s: all %d holes playable and deterministic; trees placed (%d)" % [biome.name, SEEDS, total_trees])
	_check(landmarks > 0 and landmarks < total_trees * 0.05, "%s: a few landmark trees near doglegs and greens (%d)" % [biome.name, landmarks])
	var ratio := (forest_trees / forest_km2) / (rough_trees / rough_km2)
	_check(ratio > 2.5 and ratio < 3.5, "%s: out-of-bounds forest ~3× the rough's tree density (%.0f vs %.0f per km², %.1f×)" % [
		biome.name, forest_trees / forest_km2, rough_trees / rough_km2, ratio])
	if biome.props.any(func(kind: PropKind): return kind.shape == PropKind.Shape.BUSH): # (bare sea floor and lava fields have none)
		_check(undergrowth > SEEDS * 10, "%s: undergrowth in the forest (%d)" % [biome.name, undergrowth])
	if biome.rivers > 0 or biome.pits.y > 0:
		_check(water_px > SEEDS * 4, "%s: its rivers / pits carved in bounds (%d water px over %d holes)" % [biome.name, water_px, SEEDS])
	var every := true
	for s in biome.trees.size():
		for v in biome.trees[s].sizes.size():
			every = every and seen.has("t%d/%d" % [s, v])
	for s in biome.props.size():
		for v in biome.props[s].sizes.size():
			every = every and seen.has("p%d/%d" % [s, v])
	_check(every, "%s: every species and prop in every size variant appears (%d combinations)" % [biome.name, seen.size()])


## Trees and props: every one a real species/kind and size variant of the hole's biome, on rough
## and clear of fairway and water by tree_clearance_fairway, the green by tree_clearance_green and
## the tee pad by tree_clearance_tee (measured to the nearest point of each 4 m cell, not its centre).
func _tree_rules(d: Procgen.HoleData, p: ProcgenParams) -> String:
	var problem := _placement_rules(d, p, d.trees, d.biome.trees, "tree", d.forest_from)
	return problem if problem != "" else _placement_rules(d, p, d.props, d.biome.props, "prop", d.undergrowth_from)


## Entries from `forest_from` on are the out-of-bounds forest: out of bounds, forest_inset or more
## past the OB line. The rest: rough, with the clearances.
func _placement_rules(d: Procgen.HoleData, p: ProcgenParams, list: PackedInt32Array, kinds: Array[PropKind], what: String,
		forest_from: int) -> String:
	var n := d.size
	var m := d.metres_per_px
	var on := p.surface_threshold * 255.0
	var reach := int(ceil((maxf(p.tree_clearance_tee, maxf(p.tree_clearance_green, p.tree_clearance_fairway)) + m) / m))
	var inset := d.biome.forest_inset
	var inset_reach := int(ceil((inset + m) / m))
	for k in list.size() / 4:
		if k >= forest_from:
			var fx := list[4 * k] / 100.0
			var fz := list[4 * k + 1] / 100.0
			var fpx := int(floor(fx / m + 0.5))
			var fpz := int(floor(fz / m + 0.5))
			if d.lie_px(fpz * n + fpx, p) != p.out_of_bounds:
				return "forest %s %d on %s" % [what, k, d.lie_px(fpz * n + fpx, p).resource_name]
			for cy in range(maxi(fpz - inset_reach, 0), mini(fpz + inset_reach + 1, n)):
				for cx in range(maxi(fpx - inset_reach, 0), mini(fpx + inset_reach + 1, n)):
					if d.lie_px(cy * n + cx, p) == p.out_of_bounds:
						continue
					var nx := clampf(fx, cx * m - m * 0.5, cx * m + m * 0.5)
					var nz := clampf(fz, cy * m - m * 0.5, cy * m + m * 0.5)
					if Vector2(fx - nx, fz - nz).length() < inset:
						return "forest %s %d %.1f m past the OB line (needs %.0f m)" % [what, k, Vector2(fx - nx, fz - nz).length(), inset]
			continue
		var x := list[4 * k] / 100.0
		var z := list[4 * k + 1] / 100.0
		if list[4 * k + 2] < 0 or list[4 * k + 2] >= kinds.size() or list[4 * k + 3] < 0 \
				or list[4 * k + 3] >= kinds[list[4 * k + 2]].sizes.size():
			return "%s %d has species/variant %d/%d outside the biome" % [what, k, list[4 * k + 2], list[4 * k + 3]]
		var px := int(floor(x / m + 0.5))
		var pz := int(floor(z / m + 0.5))
		if d.lie_px(pz * n + px, p) != p.rough:
			return "%s %d on %s" % [what, k, d.lie_px(pz * n + px, p).resource_name]
		for cy in range(maxi(pz - reach, 0), mini(pz + reach + 1, n)):
			for cx in range(maxi(px - reach, 0), mini(px + reach + 1, n)):
				var i := cy * n + cx
				var tee_pad := absi(cx - d.tee.x) <= int(p.tee_pad_half.x) and absi(cy - d.tee.y) <= int(p.tee_pad_half.y)
				var nx := clampf(x, cx * m - m * 0.5, cx * m + m * 0.5)
				var nz := clampf(z, cy * m - m * 0.5, cy * m + m * 0.5)
				var gap := Vector2(x - nx, z - nz).length()
				var fence: bool = kinds[list[4 * k + 2]].shape == PropKind.Shape.FENCE # (fence runs line the rough's edge: nearer the fairway)
				for rule in [[tee_pad, p.tree_clearance_tee, "tee"], [d.green[i] > on, p.tree_clearance_green, "green"],
						[d.fairway[i] > on or d.heights[i] < d.water, d.biome.fence_clearance if fence else p.tree_clearance_fairway, "fairway/water"]]:
					if rule[0] and gap < rule[1]:
						return "%s %d %.1f m from %s (needs %.0f m)" % [what, k, gap, rule[2], rule[1]]
	return ""


## Empty string if playable, otherwise what's wrong.
func _playability(d: Procgen.HoleData, p: ProcgenParams) -> String:
	var n := d.size
	var tee_i := d.tee.y * n + d.tee.x
	var cup_i := d.cup.y * n + d.cup.x
	if d.lie_px(cup_i, p) != p.green:
		return "cup lie is %s" % d.lie_px(cup_i, p).resource_name
	for y in range(d.tee.y - int(p.tee_pad_half.y), d.tee.y + int(p.tee_pad_half.y) + 1):
		for x in range(d.tee.x - int(p.tee_pad_half.x), d.tee.x + int(p.tee_pad_half.x) + 1):
			var lie := d.lie_px(y * n + x, p)
			if lie.hazard != SurfaceData.Hazard.NONE or lie == p.sand:
				return "tee pad has %s" % lie.resource_name
	for i in n * n:
		if d.bunker[i] > p.surface_threshold * 255.0 and d.heights[i] < d.water:
			return "sand under water at %d,%d" % [i % n, i / n]
	# Flood fill from the tee over ground the ball can rest on.
	var seen := PackedByteArray()
	seen.resize(n * n)
	var queue := PackedInt32Array([tee_i])
	seen[tee_i] = 1
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		if i == cup_i:
			return ""
		for j in [i - 1, i + 1, i - n, i + n]:
			if j < 0 or j >= n * n or seen[j] or absi(j % n - i % n) > 1:
				continue
			seen[j] = 1
			if d.lie_px(j, p).hazard == SurfaceData.Hazard.NONE:
				queue.append(j)
	return "cup not reachable from tee"


## Empty if every tree has a size (height, width, trunk in its species' ranges — heights times
## forest_tree_scale in the forest — or a landmark).
func _tree_sizes(d: Procgen.HoleData) -> String:
	if d.tree_scale.size() != d.trees.size() / 4 * 3:
		return "tree sizes missing"
	for t in d.trees.size() / 4:
		var kind: PropKind = d.biome.trees[d.trees[4 * t + 2]]
		var s := Vector3(d.tree_scale[3 * t], d.tree_scale[3 * t + 1], d.tree_scale[3 * t + 2]) / 1000.0
		var landmark := d.tree_scale[3 * t] == roundi(d.biome.landmark_scale * 1000.0)
		var tall := d.biome.forest_tree_scale if t >= d.forest_from else 1.0 # the forest's trees stand taller
		var h_ok := landmark or (s.x >= kind.height_range.x * tall - 0.001 and s.x <= kind.height_range.y * tall + 0.001)
		var w_ok := s.y >= kind.width_range.x - 0.001 and s.y <= kind.width_range.y + 0.001
		var t_ok := landmark or (s.z >= kind.trunk_range.x - 0.001 and s.z <= kind.trunk_range.y + 0.001)
		if not (h_ok and w_ok and t_ok):
			return "tree %d size %s outside its species' ranges" % [t, s]
	return ""


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	_failed = _failed or not ok
