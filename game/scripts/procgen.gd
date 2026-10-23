class_name Procgen
extends RefCounted
## Seeded course and hole generator, with a fixed draw order.
## Determinism contract — same 64-bit seed, same bytes on every machine:
## - integer counter-based RNG (no engine RNG, nothing unseeded);
## - floats only through + − × ÷ sqrt floor, each its own GDScript op (no sin/cos/exp, no
##   FastNoiseLite, no Curve2D baking, no fused ops);
## - distances from an exact integer distance transform; the water level is a true min;
## - every output quantised to ints/bytes.
## Never reorder the draws in hole(): that changes every hole for every seed.

const MASK32 := 0xFFFFFFFF
const TREE_STREAM := 0x7472656573 # xor'd into the hole seed for the tree RNG stream
const WIND_STREAM := 0x77696e64 # and for the wind
const PROP_STREAM := 0x70726f7073 # and for bushes and rocks
const TREE_LINE_STREAM := 0x6c696e65 # and for the rows of trees along the fairway
const TREE_SCALE_STREAM := 0x7363616c65 # and for each tree's size
const FOREST_STREAM := 0x666f72657374 # and for the out-of-bounds forest
const UNDERGROWTH_STREAM := 0x756e646572 # and for its bushes
const BIOME_STREAM := 0x62696f6d65 # xor'd into the course seed for its biomes
const RIVER_STREAM := 0x7269766572 # xor'd into the hole seed for its rivers
const PIT_STREAM := 0x70697473 # and for its pits
const FORMATION_STREAM := 0x7265656673 # and for the reef's big formations
const FENCE_STREAM := 0x66656e6365 # and for fence runs
## tan(π/k) for k = 0..16 (exact literals, no trig at run time): the step round a ring of k trees
const RING_TAN := [0.0, 0.0, 0.0, 1.7320508075688772, 1.0, 0.7265425280053609, 0.5773502691896257, 0.4815746188075286,
	0.41421356237309503, 0.36397023426620234, 0.3249196962329063, 0.2936264929383669, 0.2679491924311227,
	0.24647817284156537, 0.22824347439820978, 0.21255656167002213, 0.19891236737965800]


## The hole's wind (m/s, world xz, the way it blows) from its seed: any direction; speed 0..wind_max
## as the mean of three uniform draws, so most holes blow 2–5 m/s and still or gale-force are rare.
static func wind(seed: int, p: ProcgenParams) -> Vector2:
	var rng := Rng.new(seed ^ WIND_STREAM)
	var heading := rng.range_f(0.0, TAU)
	var speed := (rng.range_f(0.0, 1.0) + rng.range_f(0.0, 1.0) + rng.range_f(0.0, 1.0)) / 3.0 * p.wind_max
	return Vector2(cos(heading), sin(heading)) * speed


## 64-bit seed → [{number, seed, par, biome}]. Each nine draws its par pool (3/3/3) in random order.
## Biomes (`pick`, RoomRules.biome): 0 mixed — the biomes in an order shuffled from the course seed,
## one hole each in turn, so a round rotates through them; k ≥ 1 — biome k − 1 for every hole.
static func course(seed: int, p: ProcgenParams, pick := 0) -> Array[Dictionary]:
	var rng := Rng.new(seed)
	var holes: Array[Dictionary] = []
	var pool := {}
	for number in range(1, p.holes_per_course + 1):
		if (number - 1) % 9 == 0:
			pool = {3: p.par3_per_nine, 4: p.par4_per_nine, 5: p.par5_per_nine}
		var allowed: Array[int] = []
		for par: int in [3, 4, 5]:
			if pool[par] > 0:
				allowed.append(par)
		var par := allowed[rng.range_i(0, allowed.size() - 1)]
		pool[par] -= 1
		holes.append({number = number, seed = rng.u64(), par = par})
	var order: Array[int] = []
	for k in p.biomes.size():
		order.append(k)
	var shuffle := Rng.new(seed ^ BIOME_STREAM)
	for k in range(order.size() - 1, 0, -1): # Fisher–Yates
		var j := shuffle.range_i(0, k)
		var swap := order[k]
		order[k] = order[j]
		order[j] = swap
	for h in holes:
		h.biome = pick - 1 if pick >= 1 and pick <= p.biomes.size() else order[(h.number - 1) % order.size()]
	return holes


static func hole(seed: int, par: int, p: ProcgenParams, biome: Biome = null) -> HoleData:
	var rng := Rng.new(seed)
	var n := p.grid_size
	var c := n / 2
	var long := par != 3

	# --- draws, in order ---
	var mountain_up := rng.range_f(p.mountain_up.x, p.mountain_up.y)
	var mountain_down := rng.range_f(p.mountain_down.x, p.mountain_down.y)
	var n_fw := ValueNoise.new(rng.u32(), p.fairway_width_freq, 1, 0.0, n)
	var n_bw := ValueNoise.new(rng.u32(), p.bunker_radius_freq, 1, 0.0, n)
	var n_gw := ValueNoise.new(rng.u32(), p.green_width_freq, 1, 0.0, n)
	var n_gh := ValueNoise.new(rng.u32(), p.green_break_freq, 1, 0.0, n)
	var bio: Biome = biome if biome else p.biomes[0]
	var n_world := ValueNoise.new(rng.u32(), p.world_freq * bio.relief_freq, p.world_octaves, p.world_gain, n) # (relief: same draws, reshaped)
	var depth: Vector2i = [p.depth_par3, p.depth_par4, p.depth_par5][par - 3]
	var lateral: Vector2i = [p.lateral_par3, p.lateral_par4, p.lateral_par5][par - 3]
	var margin: Vector2 = [p.junction_margin_par3, p.junction_margin_par4, p.junction_margin_par5][par - 3]
	var d := rng.range_i(depth.x, depth.y)
	var lat := rng.range_i(lateral.x, lateral.y)
	var amp := p.base_amp_long if long else p.base_amp_par3
	var max_fe := rng.range_f(amp.x, amp.y) * bio.relief_amp
	var junction_y := rng.range_f(c - d + margin.x, c + d - margin.y)
	var offset := p.cup_offset_long if long else p.cup_offset_par3
	var cup_r := rng.range_f(offset.x, offset.y)
	var cup_turn := rng.range_f(-p.cup_turn_tan_half, p.cup_turn_tan_half)
	var fairway_count := rng.range_i(p.fairway_bunkers.x, p.fairway_bunkers.y) if long else 0
	var green_count := rng.range_i(p.green_bunkers.x, p.green_bunkers.y)
	var fairway_draws := PackedFloat64Array()
	for k in fairway_count:
		fairway_draws.append(rng.range_f(p.fairway_bunker_t.x, p.fairway_bunker_t.y))
		fairway_draws.append(float(rng.range_i(0, 1) * 2 - 1))
	var green_draws := PackedFloat64Array()
	for k in green_count:
		green_draws.append(rng.range_f(-p.green_bunker_turn_tan_half, p.green_bunker_turn_tan_half))

	# --- route (px) ---
	var front_x := float(c)
	var front_y := float(c - d)
	var back_x := float(c + lat)
	var back_y := float(c + d)
	var tee := Vector2i(c, c - d - p.tee_behind_front)
	var dir := _rotate(_unit(back_x - front_x, back_y - junction_y), cup_turn)
	var cup := Vector2i(int(floor(back_x + dir.x * cup_r + 0.5)), int(floor(back_y + dir.y * cup_r + 0.5)))

	var playable := _curve(PackedFloat64Array([tee.x, tee.y - p.playable_tail, tee.x, tee.y, front_x, front_y,
		front_x, junction_y, back_x, back_y, cup.x, cup.y]), true, p)
	var cup_from_tee := sqrt(float((cup.x - tee.x) * (cup.x - tee.x) + (cup.y - tee.y) * (cup.y - tee.y)))
	var fairway: PackedFloat64Array
	if not long and cup_from_tee < p.par3_straight_fairway_below:
		fairway = _curve(PackedFloat64Array([front_x, junction_y, back_x, back_y, cup.x, cup.y]), false, p)
	else:
		fairway = _curve(PackedFloat64Array([front_x, front_y, front_x, junction_y, back_x, back_y, cup.x, cup.y]), true, p)

	# --- bunkers (px centres) ---
	var bunkers := PackedFloat64Array()
	for k in fairway_count:
		bunkers.append_array(_beside(fairway, fairway_draws[2 * k], fairway_draws[2 * k + 1] * p.fairway_bunker_offset))
	var approach := _unit(cup.x - back_x, cup.y - back_y)
	for k in green_count:
		var arc := _rotate(approach, green_draws[k])
		var start_x := cup.x + arc.x
		var start_y := cup.y + arc.y
		var push := 1.0 + p.green_width_base + p.green_width_amp * n_gw.at(start_x, start_y) \
			+ p.bunker_radius_base + p.bunker_radius_amp * n_bw.at(cup.x, cup.y)
		bunkers.append(cup.x + arc.x * push)
		bunkers.append(cup.y + arc.y * push)

	# --- fields ---
	var d_playable := _edt(_raster(playable, n), n)
	var d_fairway := _edt(_raster(fairway, n), n)
	var cup_ground := n_world.at(cup.x, cup.y) * max_fe
	var bunker_reach := p.bunker_radius_base + p.bunker_radius_amp
	var far := p.rough_falloff + p.fairway_width_base + p.fairway_width_amp
	var heights_m := PackedFloat64Array()
	heights_m.resize(n * n)
	var out := HoleData.new()
	out.seed = seed
	out.par = par
	out.size = n
	out.metres_per_px = p.metres_per_px
	out.tee = tee
	out.cup = cup
	out.route = PackedVector2Array([Vector2(tee), Vector2(front_x, front_y), Vector2(front_x, junction_y), Vector2(back_x, back_y), Vector2(cup)])
	for k in bunkers.size() / 2:
		out.bunkers.append(Vector2(bunkers[2 * k], bunkers[2 * k + 1]))
	out.fairway.resize(n * n)
	out.green.resize(n * n)
	out.rough.resize(n * n)
	out.bunker.resize(n * n)
	var lowest_playable := INF

	for y in n:
		for x in n:
			var i := y * n + x
			var fx := float(x)
			var fy := float(y)
			var dpc := sqrt(float(d_playable[i]))
			var hx := fx - cup.x
			var hy := fy - cup.y
			var dhole := sqrt(hx * hx + hy * hy)
			var f := 0.0
			var g := 0.0
			var pl := 0.0
			var r := 1.0
			var wf := 0.0
			if minf(dpc, dhole) < far:
				wf = p.fairway_width_base + p.fairway_width_amp * n_fw.at(fx, fy)
				f = _lin(sqrt(float(d_fairway[i])), wf)
				g = _lin(dhole, wf)
				pl = maxf(maxf(f, g), _lin(dpc, wf))
				r = _smooth01(_clamp01(minf(dpc - wf, dhole - wf) / p.rough_falloff))

			var b := 0.0
			var nearest := INF
			for k in bunkers.size() / 2:
				var bx := fx - bunkers[2 * k]
				var by := fy - bunkers[2 * k + 1]
				nearest = minf(nearest, sqrt(bx * bx + by * by))
			if nearest < bunker_reach:
				var wb := p.bunker_radius_base + p.bunker_radius_amp * n_bw.at(fx, fy)
				b = 1.0 - _clamp01(nearest / wb)

			var s := n_world.at(fx, fy)
			var base := s * max_fe
			var h := base
			if r < 1.0:
				var dg := maxf(dhole - wf - p.green_flatten_pad, 0.0)
				var gh := 1.0 - _smooth01(_clamp01(dg / p.green_flatten_radius))
				if gh > 0.0:
					var green_top := cup_ground + p.green_break_amp * n_gh.at(fx, fy)
					h = base + (green_top - base) * gh
				var ex := absf(fx - tee.x) - p.tee_pad_half.x
				var ey := absf(fy - tee.y) - p.tee_pad_half.y
				var mx := maxf(ex, 0.0)
				var my := maxf(ey, 0.0)
				var sd := sqrt(mx * mx + my * my) + minf(maxf(ex, ey), 0.0)
				var t := 1.0 - _clamp01(sd / p.tee_pad_falloff)
				if t > 0.0:
					var tee_h := base + (max_fe - base) * t
					h = h + (tee_h - h) * t
			var mountain := (-mountain_down + (mountain_up + mountain_down) * ((s + 1.0) * 0.5)) * bio.relief_amp
			h = h + (mountain - h) * r
			h -= p.bunker_depth_m * _clamp01(b - 0.5)

			heights_m[i] = h
			if pl > 0.5 or b > 0.0:
				lowest_playable = minf(lowest_playable, h)
			out.fairway[i] = _byte(f)
			out.green[i] = _byte(g)
			out.rough[i] = _byte(r)
			out.bunker[i] = _byte(b)

	# --- water carved below the hole's water level: the biome's rivers along the rough and its pits
	# near the fairway (penalty lies), on their own RNG streams; never under fairway, green, sand or
	# the tee pad ---
	var water_m := lowest_playable - p.water_margin
	var river_far := PackedInt32Array()
	var river_half := bio.river_width * 0.5 / p.metres_per_px
	if bio.rivers > 0:
		var river_rng := Rng.new(seed ^ RIVER_STREAM)
		var seeds := PackedByteArray()
		seeds.resize(n * n)
		for k in bio.rivers:
			var side := float(river_rng.range_i(0, 1) * 2 - 1)
			var reach := p.fairway_width_base + p.fairway_width_amp + bio.river_offset / p.metres_per_px + river_half
			var pts := PackedFloat64Array()
			for step in 13:
				var at := _beside(playable, step / 12.0, side * reach * river_rng.range_f(0.8, 1.35))
				pts.append_array(at)
			var count := pts.size() / 2 # run on past both ends, along the end directions
			var head := _unit(pts[0] - pts[2], pts[1] - pts[3])
			var tail := _unit(pts[2 * count - 2] - pts[2 * count - 4], pts[2 * count - 1] - pts[2 * count - 3])
			var river_line := PackedFloat64Array([pts[0] + head.x * n, pts[1] + head.y * n])
			river_line.append_array(pts)
			river_line.append_array(PackedFloat64Array([pts[2 * count - 2] + tail.x * n, pts[2 * count - 1] + tail.y * n]))
			var mask := _raster(_curve(river_line, true, p), n)
			for i in n * n:
				seeds[i] = maxi(seeds[i], mask[i])
		river_far = _edt(seeds, n)
	var pit_rng := Rng.new(seed ^ PIT_STREAM)
	var pit_count := pit_rng.range_i(bio.pits.x, bio.pits.y) if bio.pits.y > 0 else 0
	var pit_r := bio.pit_radius / p.metres_per_px
	var pits := PackedFloat64Array()
	for k in pit_count:
		var t := pit_rng.range_f(0.15, 0.85)
		var side := float(pit_rng.range_i(0, 1) * 2 - 1)
		pits.append_array(_beside(fairway, t, side * (p.fairway_width_base + p.fairway_width_amp + pit_r + pit_rng.range_f(1.0, 3.0))))
	if bio.rivers > 0 or pit_count > 0:
		var on_px := p.surface_threshold * 255.0
		for y in n:
			for x in n:
				var i := y * n + x
				if out.fairway[i] > on_px or out.green[i] > on_px or out.bunker[i] > 0:
					continue
				if absi(x - tee.x) <= int(p.tee_pad_half.x) + 2 and absi(y - tee.y) <= int(p.tee_pad_half.y) + 2:
					continue
				var h := heights_m[i]
				if bio.rivers > 0: # a bed below the water, banks easing back up over a width either side
					var t := sqrt(float(river_far[i])) / maxf(river_half, 0.5)
					if t < 1.0:
						h = minf(h, water_m - 1.2 * (1.0 - t * t))
					elif t < 2.0:
						h = minf(h, water_m + 0.15 + (h - water_m - 0.15) * (t - 1.0))
				for k in pit_count:
					var px := float(x) - pits[2 * k]
					var py := float(y) - pits[2 * k + 1]
					var t := sqrt(px * px + py * py) / pit_r
					if t < 1.0:
						h = minf(h, water_m - 0.7 * (1.0 - t * t))
					elif t < 1.6:
						h = minf(h, water_m + 0.1 + (h - water_m - 0.1) * (t - 1.0) / 0.6)
				heights_m[i] = h

	out.heights.resize(n * n)
	for i in n * n:
		out.heights[i] = _cm(heights_m[i])
	out.water = _cm(water_m)
	out.biome = bio
	var where := _allowed(out, p)
	out.trees = PackedInt32Array()
	if bio.formation_count.y > 0: # the reef's big formations first: groves keep out of them
		var placed := _formations(out, where[0], Rng.new(seed ^ FORMATION_STREAM), p, bio)
		out.trees = placed[0]
		where[0] = placed[1]
	out.trees = _trees(out, where[0], where[1], Rng.new(seed ^ TREE_STREAM), p, out.biome, out.trees)
	out.trees = _tree_line(out, where[0], out.trees, Rng.new(seed ^ TREE_LINE_STREAM), p, out.biome)
	var forest := _forest_spots(out, p, out.biome)
	out.forest_from = out.trees.size() / 4
	out.trees = _trees(out, forest[0], forest[1], Rng.new(seed ^ FOREST_STREAM), p, out.biome, out.trees,
		out.biome.forest_density, out.biome.forest_grove_radius, out.biome.forest_grove_radius) # groves may abut out there
	if bio.tee_clear_ahead > 0.0: # the opening shot in view
		_clear_tee(out, bio)
	_corridor(out, p) # the line of play open
	out.tree_scale = _tree_scales(out, Rng.new(seed ^ TREE_SCALE_STREAM), p, out.biome)
	out.props = _props(out, where[0], where[1], Rng.new(seed ^ PROP_STREAM), p, out.biome)
	out.props = _fence_line(out, where[0], Rng.new(seed ^ FENCE_STREAM), p, out.biome) # (only biomes with fences)
	out.undergrowth_from = out.props.size() / 4
	out.props = _undergrowth(out, forest[0], forest[1], Rng.new(seed ^ UNDERGROWTH_STREAM), p, out.biome)
	if bio.tee_clear_ahead > 0.0:
		_clear_tee(out, bio, true)
	_corridor(out, p, true)
	out.wind = wind(seed, p)
	return out




## Major reef formations (biomes with formation_count): a few big coral clusters and arches — the
## biome's tree species of weight 0, which the groves never pick — set formation_offset out past the
## fairway's edge at random points of the route, formation_spacing apart, on the same allowed rough
## as trees; each one's footprint is then taken out of `allowed` so nothing else grows inside it.
## Own RNG stream. [trees, allowed].
static func _formations(d: HoleData, allowed: PackedByteArray, rng: Rng, p: ProcgenParams, biome: Biome) -> Array:
	var n := d.size
	var m := d.metres_per_px
	var on := p.surface_threshold * 255.0
	var trees := PackedInt32Array()
	var kinds: Array[int] = []
	for i in biome.trees.size():
		if biome.trees[i].weight == 0.0:
			kinds.append(i)
	if kinds.is_empty() or d.route.size() < 2:
		return [trees, allowed]
	var free := allowed.duplicate()
	var spacing_cm := _cm(biome.formation_spacing)
	for c in rng.range_i(biome.formation_count.x, biome.formation_count.y):
		for attempt in p.tree_tries * 4: # (more tries: the line of play rules out many spots by the fairway)
			var k := rng.range_i(0, d.route.size() - 2)
			var a := d.route[k]
			var b := d.route[k + 1]
			var along := (b - a).normalized()
			var normal := Vector2(-along.y, along.x)
			var at := a + (b - a) * rng.range_f(0.15, 0.85)
			var side := -1.0 if rng.range_f(0.0, 1.0) < 0.5 else 1.0
			var out := rng.range_f(biome.formation_offset.x, biome.formation_offset.y) / m
			var species: int = kinds[rng.range_i(0, kinds.size() - 1)]
			var variant := rng.range_i(0, biome.trees[species].sizes.size() - 1)
			var edge := 0.0 # px out from the route to the fairway's edge on this side
			while edge < 40.0:
				var q: Vector2 = (at + normal * side * edge).round()
				if q.x < 0 or q.y < 0 or q.x >= n or q.y >= n or d.fairway[int(q.y) * n + int(q.x)] <= on:
					break
				edge += 0.5
			var spot: Vector2 = (at + normal * side * (edge + out)) * m
			if not _spot_ok(trees, d, free, _cm(spot.x), _cm(spot.y), spacing_cm) or _in_corridor(d, p, Vector2(_cm(spot.x), _cm(spot.y)) / 100.0, biome.trees[species].sizes[variant].y * p.corridor_canopy):
				continue # (clear of the others, and of the line of play)
			trees.append_array([_cm(spot.x), _cm(spot.y), species, variant])
			var reach := (biome.trees[species].sizes[variant].y * 0.6 + p.tree_min_spacing) / m # its footprint, px
			var centre := spot / m
			for z in range(maxi(0, int(floor(centre.y - reach))), mini(n, int(floor(centre.y + reach)) + 2)):
				for x in range(maxi(0, int(floor(centre.x - reach))), mini(n, int(floor(centre.x + reach)) + 2)):
					if (x - centre.x) * (x - centre.x) + (z - centre.y) * (z - centre.y) <= reach * reach:
						free[z * n + x] = 0
			break
	return [trees, free]




## The line of play kept open, every biome: no tree (nor its canopy: corridor_canopy radii of it), and
## no big prop (LOG, STUMP, or any corridor_big_prop or more across), within half the corridor's width of the route (tee → … → cup: the fairway's spline, or
## straight on a par 3), the width easing from corridor_width.x at the tee to .y at the green; small
## props may stand in it and line its edges. Position only (no RNG stream moves); keeps forest_from /
## undergrowth_from on the same groups.
static func _corridor(d: HoleData, p: ProcgenParams, props := false) -> void:
	var list := d.props if props else d.trees
	var split := d.undergrowth_from if props else d.forest_from
	var kept := PackedInt32Array()
	var kept_before := 0
	for i in list.size() / 4:
		var at := Vector2(list[4 * i], list[4 * i + 1]) / 100.0
		var big := true
		var extra := 0.0
		if props:
			var kind: PropKind = d.biome.props[list[4 * i + 2]]
			big = kind.shape in [PropKind.Shape.LOG, PropKind.Shape.STUMP] or kind.sizes[list[4 * i + 3]].y >= p.corridor_big_prop
		else: # a tree's canopy must stay out of it too, not just its trunk
			extra = d.biome.trees[list[4 * i + 2]].sizes[list[4 * i + 3]].y * p.corridor_canopy
		if big and _in_corridor(d, p, at, extra):
			continue
		kept.append_array([list[4 * i], list[4 * i + 1], list[4 * i + 2], list[4 * i + 3]])
		if i < split:
			kept_before += 1
	if props:
		d.props = kept
		d.undergrowth_from = kept_before
	else:
		d.trees = kept
		d.forest_from = kept_before


## True if `at` (m) is within the line-of-play corridor's half width of the route, plus `extra` m.
static func _in_corridor(d: HoleData, p: ProcgenParams, at: Vector2, extra := 0.0) -> bool:
	var m := d.metres_per_px
	var total := 0.0
	for k in d.route.size() - 1:
		total += (d.route[k + 1] - d.route[k]).length() * m
	var best := INF
	var along := 0.0
	var run := 0.0
	for k in d.route.size() - 1:
		var a := d.route[k] * m
		var seg := d.route[k + 1] * m - a
		var t := clampf((at - a).dot(seg) / maxf(seg.length_squared(), 1e-6), 0.0, 1.0)
		var dist := at.distance_to(a + seg * t)
		if dist < best:
			best = dist
			along = run + seg.length() * t
		run += seg.length()
	var f := along / maxf(total, 1.0)
	return best < (p.corridor_width.x + (p.corridor_width.y - p.corridor_width.x) * f) * 0.5 + extra


## The tee kept open (biomes with tee_clear_ahead): no tree within tee_clear_ahead in front of the tee
## along its aim line (tee_clear_width either side), and within tee_thin_radius of it only
## tee_thin_keep of the trees (picked by a hash of where each stands, so no RNG stream moves).
## Props in that lane go too. Keeps forest_from / undergrowth_from pointing at the same groups.
static func _clear_tee(d: HoleData, biome: Biome, props := false) -> void:
	var m := d.metres_per_px
	var tee := Vector2(d.tee) * m
	var aim := (d.route[1] - d.route[0]).normalized()
	var list := d.props if props else d.trees
	var split := d.undergrowth_from if props else d.forest_from
	var kept := PackedInt32Array()
	var kept_before := 0
	for i in list.size() / 4:
		var at := Vector2(list[4 * i], list[4 * i + 1]) / 100.0 - tee
		var ahead := at.x * aim.x + at.y * aim.y
		var aside := absf(at.x * aim.y - at.y * aim.x)
		var keep := not (ahead > -2.0 and ahead < biome.tee_clear_ahead and aside < biome.tee_clear_width)
		if keep and not props and at.x * at.x + at.y * at.y < biome.tee_thin_radius * biome.tee_thin_radius:
			keep = mix((list[4 * i] * 73856093) ^ (list[4 * i + 1] * 19349663) & MASK32) % 1000 < int(biome.tee_thin_keep * 1000.0)
		if keep:
			kept.append_array([list[4 * i], list[4 * i + 1], list[4 * i + 2], list[4 * i + 3]])
			if i < split:
				kept_before += 1
	if props:
		d.props = kept
		d.undergrowth_from = kept_before
	else:
		d.trees = kept
		d.forest_from = kept_before
## Map pixels a tree or prop may stand on: rough, at least tree_clearance_fairway from fairway and
## water, tree_clearance_green from the green and tree_clearance_tee from the tee pad.
## [allowed (1 per pixel), candidate pixel indices].
static func _allowed(d: HoleData, p: ProcgenParams) -> Array:
	var n := d.size
	var m := d.metres_per_px
	var on := p.surface_threshold * 255.0
	var fairway := PackedByteArray()
	var green := PackedByteArray()
	var tee := PackedByteArray()
	fairway.resize(n * n)
	green.resize(n * n)
	tee.resize(n * n)
	for i in n * n:
		var x := i % n
		var y := i / n
		tee[i] = int(absi(x - d.tee.x) <= int(p.tee_pad_half.x) and absi(y - d.tee.y) <= int(p.tee_pad_half.y))
		fairway[i] = int(d.fairway[i] > on or d.heights[i] < d.water)
		green[i] = int(d.green[i] > on)
	# Pixel centres are up to half a diagonal from the true edge on both ends.
	var rules := [[_edt(fairway, n), p.tree_clearance_fairway], [_edt(green, n), p.tree_clearance_green],
		[_edt(tee, n), p.tree_clearance_tee]]
	var allowed := PackedByteArray()
	allowed.resize(n * n)
	var candidates := PackedInt32Array()
	for i in n * n:
		if d.lie_px(i, p) != p.rough:
			continue
		var clear := true
		for rule in rules:
			clear = clear and sqrt(float(rule[0][i])) >= rule[1] / m + 1.4143
		if clear:
			allowed[i] = 1
			candidates.append(i)
	return [allowed, candidates]


## Index into `kinds` picked by weight from u in [0, 1).
static func _pick(kinds: Array[PropKind], u: float) -> int:
	var total := 0.0
	for k in kinds:
		total += k.weight
	var at := u * total
	for i in kinds.size():
		at -= kinds[i].weight
		if at < 0.0:
			return i
	for i in range(kinds.size() - 1, -1, -1): # (rounding: the last one that can be picked — weight 0 never is)
		if kinds[i].weight > 0.0:
			return i
	return kinds.size() - 1


## True if a tree may stand at (x_cm, z_cm): an allowed pixel, clear of the others by spacing_cm.
static func _spot_ok(trees: PackedInt32Array, d: HoleData, allowed: PackedByteArray, x_cm: int, z_cm: int,
		spacing_cm: int) -> bool:
	var n := d.size
	var m := d.metres_per_px
	var px := int(floor(x_cm / (m * 100.0) + 0.5))
	var pz := int(floor(z_cm / (m * 100.0) + 0.5))
	return px >= 0 and pz >= 0 and px < n and pz < n and allowed[pz * n + px] == 1 and not _crowded(trees, x_cm, z_cm, spacing_cm)


## Groves of grove_size trees within grove_radius of a centre, centres at least grove_gap apart so
## lines of play stay open; each tree a species of the biome and one of its size variants. Works
## only on the quantised hole data and its own RNG stream, so terrain draws are untouched.
## Per tree: x cm, z cm (from the start), species index, variant index.
## `start`: trees already placed (kept, and kept clear of); `density` times the biome's
## groves_per_km2, `grove_radius` and `grove_gap` (m, < 0: the biome's) — the out-of-bounds forest's
## denser, tighter groves.
static func _trees(d: HoleData, allowed: PackedByteArray, candidates: PackedInt32Array, rng: Rng,
		p: ProcgenParams, biome: Biome, start := PackedInt32Array(), density := 1.0, grove_radius := -1.0,
		grove_gap := -1.0) -> PackedInt32Array:
	var n := d.size
	var m := d.metres_per_px
	var trees := start.duplicate()
	if candidates.is_empty() or biome.trees.is_empty():
		return trees
	var area_km2 := float(candidates.size()) * m * m / 1000000.0
	var groves := int(floor(area_km2 * biome.groves_per_km2 * density + 0.5))
	var radius := grove_radius if grove_radius >= 0.0 else biome.grove_radius
	var gap := grove_gap if grove_gap >= 0.0 else biome.grove_gap
	var spacing_cm := _cm(p.tree_min_spacing)
	var centres := PackedVector2Array()
	for c in groves:
		var centre := Vector2.INF
		for attempt in p.tree_tries:
			var cell := candidates[rng.range_i(0, candidates.size() - 1)]
			var at := Vector2(cell % n, cell / n) * m
			var apart := true
			for other in centres:
				apart = apart and at.distance_to(other) >= gap
			if apart:
				centre = at
				break
		if centre == Vector2.INF:
			continue
		centres.append(centre)
		var count := rng.range_i(biome.grove_size.x, biome.grove_size.y)
		# A fairy ring (biomes with grove_rings, drawn only for them so others keep their draws): the
		# grove's trees stepped round a circle, rotation by tan(π/count) without trig
		if biome.grove_rings > 0.0 and rng.range_f(0.0, 1.0) < biome.grove_rings:
			var spoke := Vector2(radius * 0.7, 0.0)
			var step: float = RING_TAN[clampi(count, 3, RING_TAN.size() - 1)]
			for t in count:
				var species := _pick(biome.trees, rng.range_f(0.0, 1.0))
				var variant := rng.range_i(0, biome.trees[species].sizes.size() - 1)
				var x_cm := _cm(centre.x + spoke.x)
				var z_cm := _cm(centre.y + spoke.y)
				if _spot_ok(trees, d, allowed, x_cm, z_cm, spacing_cm):
					trees.append_array([x_cm, z_cm, species, variant])
				spoke = _rotate(spoke, step)
			continue
		for t in count:
			for attempt in p.tree_tries:
				var ox := rng.range_f(-radius, radius)
				var oz := rng.range_f(-radius, radius)
				var species := _pick(biome.trees, rng.range_f(0.0, 1.0))
				var variant := rng.range_i(0, biome.trees[species].sizes.size() - 1)
				var x_cm := _cm(centre.x + ox)
				var z_cm := _cm(centre.y + oz)
				if ox * ox + oz * oz <= radius * radius and _spot_ok(trees, d, allowed, x_cm, z_cm, spacing_cm):
					trees.append_array([x_cm, z_cm, species, variant])
					break
	return trees


## Wrought-iron fence runs (biomes with a FENCE prop kind): along each side of the route, fence_offset
## out past where the fairway ends, one run of the kind's length every so often with fence_gaps of them
## left out (gaps to play through), on dry rough (nearer the fairway than trees may stand); appended to the props. Each run is turned along
## the route by GeneratedHole (it knows which way the route goes there). Own RNG stream.
static func _fence_line(d: HoleData, allowed: PackedByteArray, rng: Rng, p: ProcgenParams, biome: Biome) -> PackedInt32Array:
	var props := d.props.duplicate()
	var kind := -1
	for k in biome.props.size():
		if biome.props[k].shape == PropKind.Shape.FENCE:
			kind = k
	if kind < 0:
		return props
	var n := d.size
	var m := d.metres_per_px
	var on := p.surface_threshold * 255.0
	var run: float = biome.props[kind].sizes[0].x
	for k in d.route.size() - 1:
		var a := d.route[k]
		var b := d.route[k + 1]
		var along := (b - a).normalized()
		var normal := Vector2(-along.y, along.x)
		var slots := int(floor(a.distance_to(b) * m / (run + 0.6)))
		for s in slots:
			var at := a + along * (s + 0.5) * (run + 0.6) / m
			for side: float in [-1.0, 1.0]:
				var gap := rng.range_f(0.0, 1.0)
				var out := rng.range_f(biome.fence_offset.x, biome.fence_offset.y) / m
				if gap < biome.fence_gaps:
					continue
				var edge := 0.0
				while edge < 40.0:
					var q: Vector2 = (at + normal * side * edge).round()
					if q.x < 0 or q.y < 0 or q.x >= n or q.y >= n or d.fairway[int(q.y) * n + int(q.x)] <= on:
						break
					edge += 0.5
				var spot: Vector2 = (at + normal * side * (edge + out)) * m
				var px := int(floor(spot.x / m + 0.5))
				var pz := int(floor(spot.y / m + 0.5))
				if px >= 0 and pz >= 0 and px < n and pz < n and d.lie_px(pz * n + px, p) == p.rough and _fence_clear(d, p, _cm(spot.x) / 100.0, _cm(spot.y) / 100.0, biome.fence_clearance):
					props.append_array([_cm(spot.x), _cm(spot.y), kind, 0]) # (on rough, closer in than trees may stand)
	return props


## True if a fence run at (x, z) m is `fairway_m` from fairway and water and the full
## tree_clearance_green / tree_clearance_tee from the green and the tee pad (each pixel's square).
static func _fence_clear(d: HoleData, p: ProcgenParams, x: float, z: float, fairway_m: float) -> bool:
	var n := d.size
	var m := d.metres_per_px
	var on := p.surface_threshold * 255.0
	var px := int(floor(x / m + 0.5))
	var pz := int(floor(z / m + 0.5))
	var reach := int(ceil(maxf(p.tree_clearance_tee, maxf(p.tree_clearance_green, fairway_m)) / m)) + 1
	for cy in range(maxi(pz - reach, 0), mini(pz + reach + 1, n)):
		for cx in range(maxi(px - reach, 0), mini(px + reach + 1, n)):
			var i := cy * n + cx
			var nx := clampf(x, cx * m - m * 0.5, cx * m + m * 0.5)
			var nz := clampf(z, cy * m - m * 0.5, cy * m + m * 0.5)
			var gap := Vector2(x - nx, z - nz).length()
			if (d.fairway[i] > on or d.heights[i] < d.water) and gap < fairway_m:
				return false
			if d.green[i] > on and gap < p.tree_clearance_green:
				return false
			if absi(cx - d.tee.x) <= int(p.tee_pad_half.x) and absi(cy - d.tee.y) <= int(p.tee_pad_half.y) and gap < p.tree_clearance_tee:
				return false
	return true


## A loose row of trees along each side of the fairway: every tree_line_step along the hole's
## route, tree_line_offset out from where the fairway actually ends on that side, tree_line_gaps of
## the slots left empty. Own RNG stream; the same allowed rough and spacing as the groves.
static func _tree_line(d: HoleData, allowed: PackedByteArray, trees: PackedInt32Array, rng: Rng,
		p: ProcgenParams, biome: Biome) -> PackedInt32Array:
	var n := d.size
	var m := d.metres_per_px
	var on := p.surface_threshold * 255.0
	var spacing_cm := _cm(p.tree_min_spacing)
	var step := biome.tree_line_step / m
	for k in d.route.size() - 1:
		var a := d.route[k]
		var b := d.route[k + 1]
		var along := (b - a).normalized()
		var normal := Vector2(-along.y, along.x)
		var slots := int(floor(a.distance_to(b) / step))
		for s in slots:
			var at := a + along * (s + 0.5) * step
			for side: float in [-1.0, 1.0]:
				var gap := rng.range_f(0.0, 1.0)
				var out := rng.range_f(biome.tree_line_offset.x, biome.tree_line_offset.y) / m
				var shift := rng.range_f(-0.5, 0.5) * step
				var species := _pick(biome.trees, rng.range_f(0.0, 1.0))
				var variant := rng.range_i(0, biome.trees[species].sizes.size() - 1)
				if gap < biome.tree_line_gaps:
					continue
				var edge := 0.0 # px out from the route to the fairway's edge on this side
				while edge < 40.0:
					var q: Vector2 = (at + normal * side * edge).round()
					if q.x < 0 or q.y < 0 or q.x >= n or q.y >= n or d.fairway[int(q.y) * n + int(q.x)] <= on:
						break
					edge += 0.5
				var spot: Vector2 = (at + normal * side * (edge + out) + along * shift) * m
				if _spot_ok(trees, d, allowed, _cm(spot.x), _cm(spot.y), spacing_cm):
					trees.append_array([_cm(spot.x), _cm(spot.y), species, variant])
	return trees


## Each tree's size, after placement (own RNG stream, so positions are untouched): height from its
## species' height_range as the mean of two draws (biased to the middle), canopy width and trunk
## height drawn independently; a tree within landmark_radius of the cup or of a dogleg's bend is a
## landmark (landmark_scale tall) at landmark_chance. Per tree: height, width, trunk, per mille.
static func _tree_scales(d: HoleData, rng: Rng, p: ProcgenParams, biome: Biome) -> PackedInt32Array:
	var m := d.metres_per_px
	var near: Array[Vector2] = [Vector2(d.cup) * m]
	var r := d.route
	if r.size() >= 4:
		var a := (r[2] - r[1]).normalized()
		var b := (r[3] - r[2]).normalized()
		if a.dot(b) < cos(deg_to_rad(biome.landmark_bend_deg)):
			near.append(r[2] * m)
	var out := PackedInt32Array()
	for t in d.trees.size() / 4:
		var kind: PropKind = biome.trees[d.trees[4 * t + 2]]
		var at := Vector2(d.trees[4 * t], d.trees[4 * t + 1]) / 100.0
		var h := lerpf(kind.height_range.x, kind.height_range.y, (rng.range_f(0.0, 1.0) + rng.range_f(0.0, 1.0)) * 0.5)
		var w := lerpf(kind.width_range.x, kind.width_range.y, rng.range_f(0.0, 1.0))
		var trunk := lerpf(kind.trunk_range.x, kind.trunk_range.y, rng.range_f(0.0, 1.0))
		var landmark := rng.range_f(0.0, 1.0) < biome.landmark_chance
		if landmark and near.any(func(c: Vector2): return at.distance_to(c) <= biome.landmark_radius):
			h = biome.landmark_scale
			trunk = 1.0
		elif d.lie_px(_px_of(d, at), p) == p.out_of_bounds:
			h *= biome.forest_tree_scale # the forest's trees stand taller
		out.append_array([roundi(h * 1000.0), roundi(w * 1000.0), roundi(trunk * 1000.0)])
	return out


## Map pixel index under a point (m from the start).
static func _px_of(d: HoleData, at: Vector2) -> int:
	var px := clampi(int(floor(at.x / d.metres_per_px + 0.5)), 0, d.size - 1)
	var pz := clampi(int(floor(at.y / d.metres_per_px + 0.5)), 0, d.size - 1)
	return pz * d.size + px


## The out-of-bounds forest's ground: out-of-bounds pixels from forest_inset to forest_inset +
## forest_depth past the OB line (further out, in the fog, it would only cost draw calls and colliders).
## [allowed (1 per pixel), candidate pixel indices], as _allowed.
static func _forest_spots(d: HoleData, p: ProcgenParams, biome: Biome) -> Array:
	var n := d.size
	var inside := PackedByteArray() # in play: not out of bounds
	inside.resize(n * n)
	for i in n * n:
		inside[i] = int(d.lie_px(i, p) != p.out_of_bounds)
	var from_line := _edt(inside, n)
	var allowed := PackedByteArray()
	allowed.resize(n * n)
	var candidates := PackedInt32Array()
	for i in n * n:
		var past := sqrt(float(from_line[i])) * d.metres_per_px # m past the OB line
		if inside[i] == 0 and past >= biome.forest_inset + 1.4143 * d.metres_per_px and past <= biome.forest_inset + biome.forest_depth:
			allowed[i] = 1
			candidates.append(i)
	return [allowed, candidates]


## Undergrowth: the biome's bush kinds scattered through the forest at forest_bushes_per_km2, clear
## of other props and of trunks by prop_min_spacing. Own RNG stream; appended to the props.
static func _undergrowth(d: HoleData, allowed: PackedByteArray, candidates: PackedInt32Array, rng: Rng,
		p: ProcgenParams, biome: Biome) -> PackedInt32Array:
	var n := d.size
	var m := d.metres_per_px
	var props := d.props.duplicate()
	var bushes: Array[int] = []
	for k in biome.props.size():
		if biome.props[k].shape in PropKind.UNDERGROWTH:
			bushes.append(k)
	var spacing_cm := _cm(biome.prop_min_spacing)
	var area_km2 := float(candidates.size()) * m * m / 1000000.0
	# Every prop kind out there too, ob_props_scale times its rough density: the wild beyond the line
	if biome.ob_props_scale > 0.0 and not candidates.is_empty():
		for kind in biome.props.size():
			if biome.props[kind].near_water > 0.0:
				continue # (palms keep to the water's edge)
			for k in int(floor(area_km2 * biome.props[kind].per_km2 * biome.ob_props_scale + 0.5)):
				for attempt in p.tree_tries:
					var cell := candidates[rng.range_i(0, candidates.size() - 1)]
					var x_cm := _cm((float(cell % n) + rng.range_f(-0.5, 0.5)) * m)
					var z_cm := _cm((float(cell / n) + rng.range_f(-0.5, 0.5)) * m)
					var variant := rng.range_i(0, biome.props[kind].sizes.size() - 1)
					var px := int(floor(x_cm / (m * 100.0) + 0.5))
					var pz := int(floor(z_cm / (m * 100.0) + 0.5))
					if px < 0 or pz < 0 or px >= n or pz >= n or allowed[pz * n + px] == 0:
						continue
					if _crowded(props, x_cm, z_cm, spacing_cm) or _crowded(d.trees, x_cm, z_cm, spacing_cm):
						continue
					props.append_array([x_cm, z_cm, kind, variant])
					break
	if candidates.is_empty() or bushes.is_empty():
		return props
	for b in int(floor(area_km2 * biome.forest_bushes_per_km2 + 0.5)):
		for attempt in p.tree_tries:
			var cell := candidates[rng.range_i(0, candidates.size() - 1)]
			var x_cm := _cm((float(cell % n) + rng.range_f(-0.5, 0.5)) * m)
			var z_cm := _cm((float(cell / n) + rng.range_f(-0.5, 0.5)) * m)
			var kind := bushes[rng.range_i(0, bushes.size() - 1)]
			var variant := rng.range_i(0, biome.props[kind].sizes.size() - 1)
			var px := int(floor(x_cm / (m * 100.0) + 0.5))
			var pz := int(floor(z_cm / (m * 100.0) + 0.5))
			if px < 0 or pz < 0 or px >= n or pz >= n or allowed[pz * n + px] == 0:
				continue
			if _crowded(props, x_cm, z_cm, spacing_cm) or _crowded(d.trees, x_cm, z_cm, spacing_cm):
				continue
			props.append_array([x_cm, z_cm, kind, variant])
			break
	return props


## Bushes and rocks scattered singly over the allowed rough, each kind at its own per_km2, clear of
## each other and of tree trunks by prop_min_spacing. Own RNG stream. Same layout as trees.
static func _props(d: HoleData, allowed: PackedByteArray, candidates: PackedInt32Array, rng: Rng,
		p: ProcgenParams, biome: Biome) -> PackedInt32Array:
	var n := d.size
	var m := d.metres_per_px
	var props := PackedInt32Array()
	if candidates.is_empty():
		return props
	var area_km2 := float(candidates.size()) * m * m / 1000000.0
	var spacing_cm := _cm(biome.prop_min_spacing)
	var water_far := PackedInt32Array() # px² to the nearest water, for kinds that keep near it (palms)
	for kind in biome.props.size():
		var kind_data: PropKind = biome.props[kind]
		if kind_data.near_water > 0.0 and water_far.is_empty():
			var wet := PackedByteArray()
			wet.resize(n * n)
			for i in n * n:
				wet[i] = 1 if d.heights[i] < d.water else 0
			water_far = _edt(wet, n)
		var near_px := kind_data.near_water / m
		for k in int(floor(area_km2 * kind_data.per_km2 + 0.5)):
			for attempt in p.tree_tries:
				var cell := candidates[rng.range_i(0, candidates.size() - 1)]
				var x_cm := _cm((float(cell % n) + rng.range_f(-0.5, 0.5)) * m)
				var z_cm := _cm((float(cell / n) + rng.range_f(-0.5, 0.5)) * m)
				var variant := rng.range_i(0, kind_data.sizes.size() - 1)
				var px := int(floor(x_cm / (m * 100.0) + 0.5))
				var pz := int(floor(z_cm / (m * 100.0) + 0.5))
				if px < 0 or pz < 0 or px >= n or pz >= n or allowed[pz * n + px] == 0:
					continue
				if near_px > 0.0 and float(water_far[pz * n + px]) > near_px * near_px:
					continue
				if _crowded(props, x_cm, z_cm, spacing_cm) or _crowded(d.trees, x_cm, z_cm, spacing_cm):
					continue
				props.append_array([x_cm, z_cm, kind, variant])
				# A cluster: a few more of it close by (palms in a stand)
				for more in rng.range_i(kind_data.cluster.x, kind_data.cluster.y) if kind_data.cluster.y > 0 else 0:
					var cx := x_cm + _cm(rng.range_f(-kind_data.cluster_radius, kind_data.cluster_radius))
					var cz := z_cm + _cm(rng.range_f(-kind_data.cluster_radius, kind_data.cluster_radius))
					var cv := rng.range_i(0, kind_data.sizes.size() - 1)
					var qx := int(floor(cx / (m * 100.0) + 0.5))
					var qz := int(floor(cz / (m * 100.0) + 0.5))
					if qx < 0 or qz < 0 or qx >= n or qz >= n or allowed[qz * n + qx] == 0:
						continue
					if _crowded(props, cx, cz, spacing_cm) or _crowded(d.trees, cx, cz, spacing_cm):
						continue
					props.append_array([cx, cz, kind, cv])
				break
	return props

## True if any entry of a [x cm, z cm, ·, ·] list stands within spacing_cm of (x_cm, z_cm).
static func _crowded(list: PackedInt32Array, x_cm: int, z_cm: int, spacing_cm: int) -> bool:
	for k in list.size() / 4:
		var dx := list[4 * k] - x_cm
		var dz := list[4 * k + 1] - z_cm
		if dx * dx + dz * dz < spacing_cm * spacing_cm:
			return true
	return false

## Everything the game reads from a generated hole. Heights in cm, masks 0..255, points in px.
class HoleData:
	var seed: int
	var par: int
	var size: int
	var metres_per_px: float
	var tee: Vector2i
	var cup: Vector2i
	var route: PackedVector2Array ## tee, front, junction, back, cup
	var bunkers := PackedVector2Array()
	var heights := PackedInt32Array()
	var water: int
	var fairway := PackedByteArray()
	var green := PackedByteArray()
	var rough := PackedByteArray()
	var bunker := PackedByteArray()
	var trees := PackedInt32Array() ## per tree: x cm, z cm, species (index in biome.trees), variant (index in its sizes)
	var tree_scale := PackedInt32Array() ## per tree: height, canopy width, trunk scale, per mille
	var forest_from := 0 ## trees from this index on are the out-of-bounds forest
	var undergrowth_from := 0 ## props from this index on are its undergrowth
	var props := PackedInt32Array() ## per bush or rock: x cm, z cm, kind (index in biome.props), variant
	var biome: Biome
	var wind: Vector2 ## m/s, world xz, the way it blows

	## Lie at one map pixel, same priority as the ball's lookup.
	func lie_px(i: int, p: ProcgenParams) -> SurfaceData:
		if heights[i] < water:
			return p.water
		if rough[i] > p.oob_threshold * 255.0:
			return p.out_of_bounds
		var on := p.surface_threshold * 255.0
		if bunker[i] > on:
			return p.sand
		if green[i] > on:
			return p.green
		if fairway[i] > on:
			return p.fairway
		return p.rough

	## SHA-256 of every quantised output; compare across machines.
	func digest() -> String:
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(PackedInt64Array([seed, par, size, tee.x, tee.y, cup.x, cup.y, water]).to_byte_array())
		ctx.update(heights.to_byte_array())
		for mask in [fairway, green, rough, bunker]:
			ctx.update(mask)
		ctx.update(trees.to_byte_array())
		ctx.update(tree_scale.to_byte_array())
		ctx.update(props.to_byte_array())
		ctx.update(biome.name.to_utf8_buffer())
		return ctx.finish().hex_encode()


## Counter-based RNG: output k = hash(seed_lo, seed_hi, k). Integer only.
class Rng:
	var _lo: int
	var _hi: int
	var _count := 0

	func _init(seed: int) -> void:
		_lo = seed & Procgen.MASK32
		_hi = (seed >> 32) & Procgen.MASK32

	func u32() -> int:
		_count += 1
		return Procgen.mix(_lo ^ Procgen.mix(_hi ^ Procgen.mix(_count & Procgen.MASK32)))

	func u64() -> int:
		var high := u32()
		return (high << 32) | u32()

	func range_i(from: int, to: int) -> int:
		return from + u32() % (to - from + 1)

	func range_f(from: float, to: float) -> float:
		return from + float(u32()) / 4294967296.0 * (to - from)


## Value noise on an integer-hashed lattice, smoothstep-interpolated, FBM-normalised to [−1, 1].
class ValueNoise:
	var _freqs := PackedFloat64Array()
	var _amps := PackedFloat64Array()
	var _widths := PackedInt32Array()
	var _lattices: Array[PackedFloat64Array] = []
	var _amp_sum := 0.0

	func _init(seed: int, freq: float, octaves: int, gain: float, extent: int) -> void:
		var f := freq
		var a := 1.0
		for o in octaves:
			var w := int(floor(float(extent) * f)) + 2
			var lat := PackedFloat64Array()
			lat.resize(w * w)
			for j in w:
				for i in w:
					var h := Procgen.mix(seed ^ Procgen.mix((i + Procgen.mix((j + Procgen.mix(o)) & Procgen.MASK32)) & Procgen.MASK32))
					lat[j * w + i] = float(h) / 4294967295.0 * 2.0 - 1.0
			_freqs.append(f)
			_amps.append(a)
			_widths.append(w)
			_lattices.append(lat)
			_amp_sum += a
			f *= 2.0
			a *= gain

	func at(x: float, y: float) -> float:
		var total := 0.0
		for o in _freqs.size():
			var fx := x * _freqs[o]
			var fy := y * _freqs[o]
			var ix := int(floor(fx))
			var iy := int(floor(fy))
			var tx := fx - ix
			var ty := fy - iy
			tx = tx * tx * (3.0 - 2.0 * tx)
			ty = ty * ty * (3.0 - 2.0 * ty)
			var w := _widths[o]
			var lat := _lattices[o]
			var k := iy * w + ix
			var top := lat[k] + (lat[k + 1] - lat[k]) * tx
			var bottom := lat[k + w] + (lat[k + w + 1] - lat[k + w]) * tx
			total += (top + (bottom - top) * ty) * _amps[o]
		return total / _amp_sum


## murmur3 fmix32 on a value in [0, 2^32).
static func mix(h: int) -> int:
	h ^= h >> 16
	h = _mul32(h, 0x85EBCA6B)
	h ^= h >> 13
	h = _mul32(h, 0xC2B2AE35)
	h ^= h >> 16
	return h


## 32-bit wrapping multiply without overflowing int64.
static func _mul32(a: int, b: int) -> int:
	return (a * (b & 0xFFFF) + (((a * (b >> 16)) & 0xFFFF) << 16)) & MASK32


static func _unit(x: float, y: float) -> Vector2:
	var l := sqrt(x * x + y * y)
	return Vector2(x / l, y / l)


## Rotate by the angle whose half-angle tangent is t: cos = (1−t²)/(1+t²), sin = 2t/(1+t²).
static func _rotate(v: Vector2, t: float) -> Vector2:
	var den := 1.0 + t * t
	var co := (1.0 - t * t) / den
	var si := 2.0 * t / den
	return Vector2(v.x * co - v.y * si, v.x * si + v.y * co)


## Catmull-Rom-style Bézier through xy pairs (handles = tension × neighbour difference), sampled.
static func _curve(pts: PackedFloat64Array, smooth: bool, p: ProcgenParams) -> PackedFloat64Array:
	var m := pts.size() / 2
	var out := PackedFloat64Array()
	for k in m - 1:
		var x0 := pts[2 * k]
		var y0 := pts[2 * k + 1]
		var x3 := pts[2 * k + 2]
		var y3 := pts[2 * k + 3]
		var x1 := x0
		var y1 := y0
		var x2 := x3
		var y2 := y3
		if smooth:
			var a0 := maxi(k - 1, 0)
			var a1 := mini(k + 1, m - 1)
			var b0 := k
			var b1 := mini(k + 2, m - 1)
			x1 = x0 + p.curve_tension * (pts[2 * a1] - pts[2 * a0])
			y1 = y0 + p.curve_tension * (pts[2 * a1 + 1] - pts[2 * a0 + 1])
			x2 = x3 - p.curve_tension * (pts[2 * b1] - pts[2 * b0])
			y2 = y3 - p.curve_tension * (pts[2 * b1 + 1] - pts[2 * b0 + 1])
		for s in p.curve_steps:
			var t := float(s) / float(p.curve_steps)
			var u := 1.0 - t
			var w0 := u * u * u
			var w1 := 3.0 * u * u * t
			var w2 := 3.0 * u * t * t
			var w3 := t * t * t
			out.append(w0 * x0 + w1 * x1 + w2 * x2 + w3 * x3)
			out.append(w0 * y0 + w1 * y1 + w2 * y2 + w3 * y3)
	out.append(pts[2 * m - 2])
	out.append(pts[2 * m - 1])
	return out


## Point at fraction t of the polyline's length, pushed sideways by `side` px along its normal.
static func _beside(line: PackedFloat64Array, t: float, side: float) -> PackedFloat64Array:
	var m := line.size() / 2
	var cum := PackedFloat64Array([0.0])
	for k in range(1, m):
		var dx := line[2 * k] - line[2 * k - 2]
		var dy := line[2 * k + 1] - line[2 * k - 1]
		cum.append(cum[k - 1] + sqrt(dx * dx + dy * dy))
	var target := t * cum[m - 1]
	var k := 0
	while k < m - 1 and cum[k] < target:
		k += 1
	var a := maxi(k - 1, 0)
	var b := mini(k + 1, m - 1)
	var tangent := _unit(line[2 * b] - line[2 * a], line[2 * b + 1] - line[2 * a + 1])
	return PackedFloat64Array([line[2 * k] - tangent.y * side, line[2 * k + 1] + tangent.x * side])


static func _raster(line: PackedFloat64Array, n: int) -> PackedByteArray:
	var seeds := PackedByteArray()
	seeds.resize(n * n)
	for k in line.size() / 2:
		var x := clampi(int(floor(line[2 * k] + 0.5)), 0, n - 1)
		var y := clampi(int(floor(line[2 * k + 1] + 0.5)), 0, n - 1)
		seeds[y * n + x] = 1
	return seeds


## Exact squared Euclidean distance to the nearest seed pixel (Meijster et al.), integers only.
static func _edt(seeds: PackedByteArray, n: int) -> PackedInt32Array:
	var inf := n * 2
	var g := PackedInt32Array()
	g.resize(n * n)
	for x in n:
		var run := inf
		for y in n:
			run = 0 if seeds[y * n + x] != 0 else mini(run + 1, inf)
			g[y * n + x] = run
		for y in range(n - 2, -1, -1):
			if g[(y + 1) * n + x] < g[y * n + x]:
				g[y * n + x] = g[(y + 1) * n + x] + 1
	var out := PackedInt32Array()
	out.resize(n * n)
	var s := PackedInt32Array()
	var t := PackedInt32Array()
	s.resize(n)
	t.resize(n)
	for y in n:
		var row := y * n
		var q := 0
		s[0] = 0
		t[0] = 0
		for u in range(1, n):
			var gu := g[row + u]
			while q >= 0:
				var gs := g[row + s[q]]
				if (t[q] - s[q]) * (t[q] - s[q]) + gs * gs <= (t[q] - u) * (t[q] - u) + gu * gu:
					break
				q -= 1
			if q < 0:
				q = 0
				s[0] = u
			else:
				var gs := g[row + s[q]]
				var num := u * u - s[q] * s[q] + gu * gu - gs * gs
				var den := 2 * (u - s[q])
				var w := 1 + (num / den if num >= 0 else -((-num + den - 1) / den)) # floor division
				if w < n:
					q += 1
					s[q] = u
					t[q] = w
		for u in range(n - 1, -1, -1):
			var gs := g[row + s[q]]
			out[row + u] = (u - s[q]) * (u - s[q]) + gs * gs
			if u == t[q]:
				q -= 1
	return out


static func _lin(d: float, w: float) -> float:
	return 1.0 - _clamp01((d - w) / w)


static func _clamp01(v: float) -> float:
	return minf(maxf(v, 0.0), 1.0)


static func _smooth01(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


static func _byte(v: float) -> int:
	return int(floor(_clamp01(v) * 255.0 + 0.5))


static func _cm(m: float) -> int:
	return int(floor(m * 100.0 + 0.5))
