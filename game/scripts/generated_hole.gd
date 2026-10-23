class_name GeneratedHole
extends Hole
## A hole built from Procgen data: terrain mesh + trimesh collider, water plane, tee, cup, and the
## biome's trees, bushes and rocks (Flora).
## Lies and heights come from the quantised masks (bilinear), so every machine agrees.

const TERRAIN_SHADER := preload("res://art/terrain.gdshader")
const TUFT_TILE := 32.0 ## m, one grass-tuft MultiMesh per square this size
const TUFT_RANGE := 90.0 ## m, tufts fade out beyond this
const TUFT_ROWS_PER_FRAME := 4 ## tuft tile rows built per frame (they finish behind the flyover)
const STREAM_BUDGET_MS := 4.0 ## ms a frame of deferred forest and prop building on clients (normal play)
const TEMPLATES := 3 ## looks per kind and size (more if its palette has more colours): batched, each instance turned and tinted
const BATCH_TILE := 96.0 ## m: one batch per square this size (so distant ones cull and fade)
const SMALL_SIZE := 1.5 ## m: props smaller than this (rocks, bushes, shells…) fade out beyond SMALL_RANGE
const SMALL_RANGE := 120.0 ## m
const TUMBLE_SPEED := 0.35 ## of the wind speed, a tumbleweed's roll (visual only)
const TUMBLE_RANGE := 40.0 ## m from home before one starts over upwind
const TUMBLE_DRAG := 2.0 ## 1/s: how fast the wind brings a tumbleweed up to its roll speed
const TUMBLE_HOP := Vector2(1.0, 2.2) ## m/s up, a hop (from where it is, hashed)
const TUMBLE_HOP_EVERY := Vector2(0.6, 1.8) ## s between hops
const TUMBLE_BOUNCE := 0.35 ## of its fall speed back up when it lands
const TUMBLE_BOUNCE_MIN := 0.6 ## m/s: landing slower than this, it just settles
const TUMBLE_CLEAR := 0.003 ## m kept between its underside and the ground (between the points sampled)

signal built ## everything deferred (tufts, the out-of-bounds forest, props) is in: the hole may be shown

var data: Procgen.HoleData
var params: ProcgenParams
var _water_y := 0.0
## Clients build the out-of-bounds forest, then the props, over the frames after _ready (the flyover
## holds for them); the server and script runs (tests, captures) build them with the rest.
var defer_forest := DisplayServer.get_name() != "headless" and not OS.get_cmdline_args().has("-s")
## ms of deferred building per frame (the flyover raises it while it holds on black).
var stream_budget_ms := STREAM_BUDGET_MS
var _forest_later := false # the forest and props are still to build (_add_deferred)
var _tufts_later := false # the grass tufts are still being built (_add_tufts)
var _tuft_rows := Vector2i.ZERO # tuft tile rows built, of all
var _deferred := Vector2i.ZERO # forest trees and props built, of all deferred
var _terrain_verts: PackedVector3Array
var _tumbleweeds := [] # [node, home] (they roll with the wind)
var _batches := {} # key → {mesh, xforms, colors, small, view}: the props' looks as MultiMeshes
var _swayers := [] # [node, rest rotation, phase]: the reef's fans, kelp and anemones (clients)
var _sway_t := 0.0


func _ready() -> void:
	super()
	_build_collision()
	if DisplayServer.get_name() != "headless":
		_add_tufts() # a coroutine: finishes over the next few frames, behind the hole flyover
		add_child(TeeProps.new(self)) # the cart and caddies at the tee (visual only)
		add_child(Scenery.new(self)) # distant mesas, fog bands in the wild (visual only)
		if data.biome.water_bubbles > 0 or data.biome.crows > 0:
			add_child(BiomeLife.new(self)) # bog bubbles, crows (visual only)
	if _forest_later:
		_add_deferred() # likewise


func _add_tree(k: int) -> void:
	var d := data
	var s := Vector3(d.tree_scale[3 * k], d.tree_scale[3 * k + 1], d.tree_scale[3 * k + 2]) / 1000.0
	_add_flora(d.biome.trees[d.trees[4 * k + 2]], d.trees, k, 2 * k, s)


## True while the forest and props are still being built (deferred, clients).
func is_building() -> bool:
	return _forest_later or _tufts_later


## 0..1 through the deferred build (tuft rows, then forest and props), for a loading bar.
func build_progress() -> float:
	if not is_building():
		return 1.0
	var tufts := float(_tuft_rows.x) / maxf(_tuft_rows.y, 1.0) if _tufts_later else 1.0
	var forest := float(_deferred.x) / maxf(_deferred.y, 1.0) if _forest_later else 1.0
	return (tufts + forest) * 0.5


func _check_built() -> void:
	if not is_building():
		built.emit()


## The out-of-bounds forest, then the props (a coroutine), stream_budget_ms of it a frame.
func _add_deferred() -> void:
	var trees := data.trees.size() / 4
	var started := Time.get_ticks_usec()
	_deferred = Vector2i(0, trees + data.props.size() / 4 - data.forest_from)
	for k in range(data.forest_from, trees + data.props.size() / 4):
		_deferred.x = k - data.forest_from
		if (Time.get_ticks_usec() - started) / 1000.0 >= stream_budget_ms:
			await get_tree().process_frame
			if not is_inside_tree():
				return
			started = Time.get_ticks_usec()
		if k < trees:
			_add_tree(k)
		else:
			_add_prop(k - trees)
	_flush_batches()
	_forest_later = false
	_check_built()


func _add_prop(k: int) -> void:
	_add_flora(data.biome.props[data.props[4 * k + 2]], data.props, k, 2 * k + 1)


## Ground collision: the terrain's cells, except the few under the cup, which become a ring of
## triangles in to the rim, so the cup is a real hole (the liner's wall and bottom hold the ball).
func _build_collision() -> void:
	var n := data.size
	var m := data.metres_per_px
	var c := cup.position / m
	var r := (FEEL.cup_radius + 0.05) / m
	var x0 := int(floor(c.x - r))
	var x1 := int(floor(c.x + r))
	var y0 := int(floor(c.z - r))
	var y1 := int(floor(c.z + r))
	var v := _terrain_verts
	var faces := PackedVector3Array()
	faces.resize((n - 1) * (n - 1) * 6)
	var k := 0
	for y in n - 1:
		for x in n - 1:
			if x >= x0 and x <= x1 and y >= y0 and y <= y1:
				continue
			var i := y * n + x
			faces[k] = v[i]
			faces[k + 1] = v[i + 1]
			faces[k + 2] = v[i + n]
			faces[k + 3] = v[i + 1]
			faces[k + 4] = v[i + n + 1]
			faces[k + 5] = v[i + n]
			k += 6
	faces.resize(k)
	var outer := PackedVector3Array() # the cut cells' boundary, one way round
	for x in range(x0, x1 + 2):
		outer.append(v[y0 * n + x])
	for y in range(y0 + 1, y1 + 2):
		outer.append(v[y * n + x1 + 1])
	for x in range(x1, x0 - 1, -1):
		outer.append(v[(y1 + 1) * n + x])
	for y in range(y1, y0, -1):
		outer.append(v[y * n + x0])
	faces.append_array(cup_ring_faces(outer, height_at))
	var sheet := ConcavePolygonShape3D.new()
	sheet.backface_collision = true
	sheet.set_faces(faces)
	($Ground/Shape as CollisionShape3D).shape = sheet


func build(d: Procgen.HoleData, p: ProcgenParams) -> void:
	data = d
	params = p
	par = d.par
	wind = Vector3(d.wind.x, 0.0, d.wind.y)
	out_of_bounds = p.out_of_bounds
	_water_y = d.water / 100.0
	var n := d.size
	var m := d.metres_per_px

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var grass := Procgen.ValueNoise.new(d.seed ^ 0x67a55, p.grass_noise_freq, 2, 0.5, n)
	verts.resize(n * n)
	normals.resize(n * n)
	colors.resize(n * n)
	for y in n:
		for x in n:
			var i := y * n + x
			verts[i] = Vector3(x * m, _h(x, y), y * m)
			normals[i] = Vector3(_h(x - 1, y) - _h(x + 1, y), 2.0 * m, _h(x, y - 1) - _h(x, y + 1)).normalized()
			# R: low-frequency grass drift for the shader (0.5 = none); the lie itself is per fragment.
			colors[i] = Color(0.5 + grass.at(x, y) * p.grass_noise, 0.0, 0.0)
	var indices := PackedInt32Array()
	for y in n - 1:
		for x in n - 1:
			var i := y * n + x
			indices.append_array([i, i + 1, i + n, i + 1, i + n + 1, i + n])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var terrain := ShaderMaterial.new()
	terrain.shader = TERRAIN_SHADER
	var cup_at := _world(d.cup)
	terrain.set_shader_parameter("cup_xz", Vector2(cup_at.x, cup_at.z))
	terrain.set_shader_parameter("cup_radius", FEEL.cup_radius)
	for mask in ["fairway", "green", "bunker", "rough"]:
		var img := Image.create_from_data(n, n, false, Image.FORMAT_R8, d.get(mask))
		terrain.set_shader_parameter(mask + "_mask", ImageTexture.create_from_image(img))
	terrain.set_shader_parameter("grid_size", float(n))
	terrain.set_shader_parameter("metres_per_px", m)
	terrain.set_shader_parameter("surface_threshold", p.surface_threshold)
	terrain.set_shader_parameter("oob_threshold", p.oob_threshold)
	terrain.set_shader_parameter("water_y", _water_y)
	for lie in [["fairway", p.fairway], ["rough", p.rough], ["green", p.green], ["sand", p.sand],
			["water", p.water], ["oob", p.out_of_bounds]]:
		terrain.set_shader_parameter(lie[0] + "_color", (lie[1] as SurfaceData).color)
	terrain.set_shader_parameter("fairway_color", d.biome.fairway_color) # the biome's ground palette
	terrain.set_shader_parameter("rough_color", d.biome.rough_color)
	terrain.set_shader_parameter("green_color", d.biome.green_color)
	terrain.set_shader_parameter("sand_color", d.biome.sand_color)
	terrain.set_shader_parameter("water_color", d.biome.water_color)
	terrain.set_shader_parameter("caustics", d.biome.caustics)
	terrain.set_shader_parameter("rough_ripples", d.biome.rough_ripples)
	terrain.set_shader_parameter("ripple_dir", Vector2(d.wind.x, d.wind.y).normalized() if d.wind.length() > 0.1 else Vector2(1, 0))
	terrain.set_shader_parameter("oob_pattern", int(d.biome.oob_pattern))
	terrain.set_shader_parameter("oob_color", d.biome.oob_color)
	var tee_at := _world(d.tee)
	var axis := Vector2(cup_at.x - tee_at.x, cup_at.z - tee_at.z).normalized()
	terrain.set_shader_parameter("axis_origin", Vector2(tee_at.x, tee_at.z))
	terrain.set_shader_parameter("axis_dir", axis)
	terrain.set_shader_parameter("stripe_width", p.stripe_width)
	terrain.set_shader_parameter("stripe_shade", p.stripe_shade)
	terrain.set_shader_parameter("mottle_size", p.mottle_size)
	terrain.set_shader_parameter("mottle_shade", p.mottle_shade)
	terrain.set_shader_parameter("checker_size", p.checker_size)
	terrain.set_shader_parameter("checker_shade", p.checker_shade)
	mesh.surface_set_material(0, terrain)

	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var shape := CollisionShape3D.new()
	shape.name = "Shape" # its shape is built in _ready(), with the cup cut out
	_terrain_verts = verts
	var view := MeshInstance3D.new()
	view.mesh = mesh
	ground.add_child(shape)
	ground.add_child(view)
	add_child(ground)

	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4000, 4000)
	var water_mat := StandardMaterial3D.new() # the biome's water: a brine pool, lava…
	water_mat.albedo_color = Color(d.biome.water_color, d.biome.water_alpha)
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if d.biome.water_alpha < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	if d.biome.water_glow > 0.0:
		water_mat.emission_enabled = true
		water_mat.emission = d.biome.water_color
		water_mat.emission_energy_multiplier = d.biome.water_glow
	plane.material = water_mat
	water.mesh = plane
	water.position = Vector3(n * m * 0.5, _water_y, n * m * 0.5)
	add_child(water)

	var tee_marker := Marker3D.new()
	tee_marker.name = "Tee"
	tee_marker.position = _world(d.tee)
	add_child(tee_marker)
	var cup_marker := Marker3D.new()
	cup_marker.name = "Cup"
	cup_marker.position = _world(d.cup)
	add_child(cup_marker)

	for point in d.route:
		centreline.append(_world(Vector2i(point.round())))

	# The fairway-side trees now; then the out-of-bounds forest and after it the props, now or
	# streamed after _ready (defer_forest).
	var later := defer_forest
	for k in (d.forest_from if later else d.trees.size() / 4):
		_add_tree(k)
	_forest_later = later
	if not later:
		for k in d.props.size() / 4:
			_add_prop(k)
	_flush_batches() # the looks drawn so far, batched


## Short grass tufts on the rough, visual only (no collision): per TUFT_TILE square with any rough, tufts_per_m2
## spots from the hole seed, kept where the lie is rough; one MultiMesh per tile, faded out past
## TUFT_RANGE so only the nearby ones draw.
func _add_tufts() -> void:
	_tufts_later = true
	await _build_tufts()
	_tufts_later = false
	_check_built()


func _build_tufts() -> void:
	var biome := data.biome
	if biome.tufts_per_m2 <= 0.0:
		return
	var tuft := _tuft_mesh()
	var side := data.size * data.metres_per_px
	var tiles := int(ceil(side / TUFT_TILE))
	var per_tile := int(round(TUFT_TILE * TUFT_TILE * biome.tufts_per_m2))
	var rng := RandomNumberGenerator.new()
	rng.seed = Procgen.mix(data.seed ^ 0x74756674)
	# Rough per map pixel (nearest pixel is plenty for a visual scatter), and tiles with none skipped.
	var n := data.size
	var rough := PackedByteArray()
	rough.resize(n * n)
	for i in n * n:
		rough[i] = int(data.lie_px(i, params) == params.rough)
	var px_per_tile := int(TUFT_TILE / data.metres_per_px)
	var in_one_go := OS.get_cmdline_args().has("-s") # script runs (captures) want the whole hole at once
	for ty in tiles:
		_tuft_rows = Vector2i(ty, tiles)
		if ty % TUFT_ROWS_PER_FRAME == 0 and ty > 0 and not in_one_go and is_inside_tree():
			await get_tree().process_frame
			if not is_inside_tree():
				return
		for tx in tiles:
			var any := false
			for y in range(ty * px_per_tile, mini((ty + 1) * px_per_tile, n)):
				for x in range(tx * px_per_tile, mini((tx + 1) * px_per_tile, n)):
					any = any or rough[y * n + x] == 1
			if not any:
				continue
			var spots: Array[Transform3D] = []
			var shades := PackedColorArray()
			for i in per_tile:
				var at := Vector3((tx + rng.randf()) * TUFT_TILE, 0.0, (ty + rng.randf()) * TUFT_TILE)
				var yaw := rng.randf() * TAU
				var size := rng.randf_range(0.7, 1.3)
				var shade := rng.randf_range(-0.06, 0.06)
				var px := clampi(int(at.x / data.metres_per_px + 0.5), 0, n - 1)
				var pz := clampi(int(at.z / data.metres_per_px + 0.5), 0, n - 1)
				if rough[pz * n + px] == 0:
					continue
				at.y = height_at(at)
				spots.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), at))
				shades.append(biome.tuft_color.lightened(shade) if shade > 0.0 else biome.tuft_color.darkened(-shade))
			if spots.is_empty():
				continue
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.use_colors = true
			multi.mesh = tuft
			multi.instance_count = spots.size()
			for i in spots.size():
				multi.set_instance_transform(i, spots[i])
				multi.set_instance_color(i, shades[i])
			var view := MultiMeshInstance3D.new()
			view.multimesh = multi
			view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			view.visibility_range_end = TUFT_RANGE
			view.visibility_range_end_margin = TUFT_RANGE * 0.2
			view.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			add_child(view)


## One tuft: a few thin flat blades leaning out from a point, white (the instance color tints it).
static func _tuft_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	for k in 5:
		var a := TAU * k / 5.0 + 0.3 * k
		var out := Vector3(cos(a), 0.0, sin(a))
		var across := Vector3(-out.z, 0.0, out.x) * 0.018
		var tip := out * 0.07 + Vector3.UP * (0.14 + 0.03 * (k % 2))
		verts.append_array([-across, across, tip])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var blades := ArrayMesh.new()
	blades.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mesh := LowPoly.flat(blades, Color.WHITE) # per-face normals and a white vertex color
	var mat := LowPoly.material()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED # blades seen from both sides
	mesh.surface_set_material(0, mat)
	return mesh


## Entry k of a [x cm, z cm, kind, variant] list, built by Flora on the ground; its look varies
## by the hole seed and `salt`. Foliage plays a leaf rustle where the ball comes in (clients).
func _add_flora(kind: PropKind, list: PackedInt32Array, k: int, salt: int, scale := Vector3.ONE) -> void:
	var base := Vector3(list[4 * k] / 100.0, 0.0, list[4 * k + 1] / 100.0)
	var headless := DisplayServer.get_name() == "headless"
	var moving: bool = kind.shape in [PropKind.Shape.TUMBLEWEED, PropKind.Shape.SEA_FAN, PropKind.Shape.KELP, PropKind.Shape.ANEMONE]
	var seed := Procgen.mix(data.seed ^ salt)
	var size: Vector2 = kind.sizes[list[4 * k + 3]]
	# Its body (colliders, foliage) as its own node; its look batched with others of its kind (or,
	# for the ones that move, its own; on the server none)
	var node := Flora.build(kind, size, seed, params.tree_sink, params.tree_surface, scale, moving and not headless)
	node.position = Vector3(base.x, height_at(base), base.z)
	if kind.shape == PropKind.Shape.FENCE: # a fence run lies along the line of play there
		node.rotation.y = _route_yaw(Vector2(base.x, base.z))
	if not moving and not headless:
		_batch(kind, list[4 * k + 3], seed, node, scale)
	var foliage := node.get_node_or_null("Foliage") as Area3D
	if foliage and DisplayServer.get_name() != "headless":
		foliage.body_entered.connect(func(body: Node3D) -> void: _rustle(body.global_position, kind.color))
	add_child(node)
	if node.has_meta("tumbleweed"):
		_tumbleweeds.append([node, node.position, Vector3.ZERO, float(salt % 997) / 997.0 * TUMBLE_HOP_EVERY.y]) # [node, home, velocity, s to its next hop]
	if node.has_meta("sway") or node.has_meta("tentacles"):
		_swayers.append([node, node.rotation, float(salt % 1000) * 0.0137]) # reef: fans and kelp rock, anemones wave


## One thing's look into its batch: per kind, size variant, template (one of TEMPLATES looks of it,
## by its seed) and BATCH_TILE square; turned as its body, scaled by its tree scale (approximately:
## the template is drawn at its plain size), tinted by its brightness jitter.
func _batch(kind: PropKind, variant: int, seed: int, body: Node3D, scale: Vector3) -> void:
	var templates := maxi(TEMPLATES, kind.palette.size())
	var t := seed % templates
	var tile := Vector2i(floori(body.position.x / BATCH_TILE), floori(body.position.z / BATCH_TILE))
	var key := "%s|%d|%d|%d|%d" % [kind.resource_path, variant, t, tile.x, tile.y]
	if not _batches.has(key):
		var template_seed := Procgen.mix(hash(kind.resource_path) ^ (variant * 7919 + t * 104729))
		var size: Vector2 = kind.sizes[variant]
		_batches[key] = {mesh = Flora.view_mesh(kind, size, template_seed, params.tree_sink), xforms = [], colors = [],
			small = not kind in data.biome.trees and size.y < SMALL_SIZE, view = null, kind = kind}
	var b: Dictionary = _batches[key]
	var across := scale.x * scale.y
	var up := scale.x * (1.0 + scale.z) * 0.5
	b.xforms.append(Transform3D(Basis(Vector3.UP, body.rotation.y) * Basis.from_scale(Vector3(across, up, across)), body.position))
	var shade := 1.0 + (float(Procgen.mix(seed ^ 0x5a) % 1000) / 1000.0 * 2.0 - 1.0) * kind.value_jitter * 2.0
	b.colors.append(Color(shade, shade, shade))


## Every batch as a MultiMeshInstance3D (made on first use, refilled as it grows); small props fade
## out by SMALL_RANGE.
func _flush_batches() -> void:
	for key in _batches:
		var b: Dictionary = _batches[key]
		if b.mesh == null or b.xforms.is_empty():
			continue
		if b.view == null:
			var view := MultiMeshInstance3D.new()
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = b.mesh
			view.multimesh = mm
			view.material_override = Flora.material_for(b.kind)
			if b.small:
				view.visibility_range_end = SMALL_RANGE
				view.visibility_range_end_margin = SMALL_RANGE * 0.2
				view.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			add_child(view)
			b.view = view
		var multi: MultiMesh = (b.view as MultiMeshInstance3D).multimesh
		if multi.instance_count == b.xforms.size():
			continue
		multi.instance_count = b.xforms.size()
		for i in b.xforms.size():
			multi.set_instance_transform(i, b.xforms[i])
			multi.set_instance_color(i, b.colors[i])


## One of each kind of thing this hole draws — every drawable under it (batched props, tufts,
## fog bands, mesas, water, the cup and flag, the tee's cart and caddies…), one per node type and
## material — for the loading screen to draw once out of sight (Main's shader warm-up).
func warmup_samples() -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	var seen := {}
	for node in find_children("*", "GeometryInstance3D", true, false):
		var g := node as GeometryInstance3D
		var mesh: Mesh = null
		if g is MeshInstance3D:
			mesh = (g as MeshInstance3D).mesh
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh:
			mesh = (g as MultiMeshInstance3D).multimesh.mesh
		var surface: Material = mesh.surface_get_material(0) if mesh and mesh.get_surface_count() > 0 else null
		var key := "%s|%d|%d" % [g.get_class(), g.material_override.get_instance_id() if g.material_override else 0,
			surface.get_instance_id() if surface else 0]
		if not seen.has(key):
			seen[key] = true
			out.append(g)
	return out


## The reef sways and the tumbleweeds roll (visual only).
func _process(delta: float) -> void:
	_sway_t += delta
	_process_tumbleweeds(delta)
	for s in _swayers: # the reef in the current: slow rocking, tentacles each in their own time
		var node: Node3D = s[0]
		var rest: Vector3 = s[1]
		var ph: float = s[2]
		if node.has_meta("sway"):
			var amp: float = node.get_meta("sway")
			node.rotation = rest + Vector3(sin(_sway_t * 0.55 + ph) * amp, 0.0, sin(_sway_t * 0.41 + ph * 1.7) * amp * 0.7)
		if node.has_meta("tentacles"):
			for t in node.get_meta("tentacles"):
				var pivot: Node3D = t[0]
				var base: Vector3 = t[1]
				pivot.rotation = base + Vector3(sin(_sway_t * 1.3 + t[2]) * 0.25, 0.0, cos(_sway_t * 1.1 + t[2]) * 0.25)


## Tumbleweeds, physics-lite, every frame: the wind drags each toward TUMBLE_SPEED of it along the
## ground, gravity pulls it down, and every frame its ball's underside is kept on or above the ground
## the ball collides with (ground_at(): the collider's own triangles, not the bilinear height_at())
## at its centre and two rings round it; on the ground it rolls about its centre (its "Spin" pivot),
## now and then hops, landing on that same surface, and bounces a little. One that has gone
## TUMBLE_RANGE from home, or reached the terrain's edge, starts again upwind (on the ground there).
func _process_tumbleweeds(delta: float) -> void:
	if _tumbleweeds.is_empty() or wind.length() < 0.1:
		return
	var drift := wind * TUMBLE_SPEED
	for t in _tumbleweeds:
		var node: Node3D = t[0]
		var home: Vector3 = t[1]
		var v: Vector3 = t[2]
		var r: float = node.get_meta("tumbleweed")
		var flat := Vector3(v.x, 0.0, v.z)
		flat += (drift - flat) * (1.0 - exp(-TUMBLE_DRAG * delta))
		v = Vector3(flat.x, v.y - 9.8 * delta, flat.z)
		var at := node.position + v * delta
		var edge := (data.size - 1) * data.metres_per_px - r # (the terrain ends there)
		if Vector2(at.x - home.x, at.z - home.z).length() > TUMBLE_RANGE or at.x < r or at.z < r or at.x > edge or at.z > edge:
			at = home - drift.normalized() * TUMBLE_RANGE
			at = Vector3(clampf(at.x, r, edge), at.y, clampf(at.z, r, edge))
			at.y = _ground_under(at, r)
			v = Vector3(drift.x, 0.0, drift.z)
		var ground := _ground_under(at, r)
		t[3] -= delta
		if at.y <= ground: # on (or into) the ground: up onto it
			at.y = ground
			if v.y < -TUMBLE_BOUNCE_MIN:
				v.y = -v.y * TUMBLE_BOUNCE # a little bounce
			else:
				v.y = 0.0
			if t[3] <= 0.0: # a hop now and then
				var h := float(Procgen.mix(int(at.x * 1000.0) ^ int(at.z * 1000.0)) % 1000) / 1000.0
				v.y = lerpf(TUMBLE_HOP.x, TUMBLE_HOP.y, h)
				t[3] = lerpf(TUMBLE_HOP_EVERY.x, TUMBLE_HOP_EVERY.y, 1.0 - h)
		node.position = at
		t[2] = v
		var step := Vector2(v.x, v.z).length() * delta
		var spin := node.get_node_or_null("Spin") as Node3D
		if step > 0.0 and spin:
			spin.rotate(Vector3(v.x, 0.0, v.z).normalized().cross(Vector3.UP), -step / r)


## Yaw that lays a node's +X along the route at its nearest segment to `at` (m): a fence run's way.
func _route_yaw(at: Vector2) -> float:
	var m := data.metres_per_px
	var best := INF
	var dir := Vector2.RIGHT
	for k in data.route.size() - 1:
		var a := data.route[k] * m
		var seg := data.route[k + 1] * m - a
		var t := clampf((at - a).dot(seg) / maxf(seg.length_squared(), 1e-6), 0.0, 1.0)
		var dist := at.distance_to(a + seg * t)
		if dist < best:
			best = dist
			dir = seg.normalized()
	return atan2(-dir.y, dir.x) # Basis(UP, θ) takes +X to (cos θ, 0, −sin θ)


## The ground under a ball of radius `r` may sit (its foot's height) at `at` and stay out of the
## ground the ball collides with: a ball resting on the collider's own triangles (the mesh's cells, each
## split along the same diagonal) under its footprint — on a face, an edge or a vertex, whichever holds
## it highest. Exact, so no crease between sample points can poke into it.
func _ground_under(at: Vector3, r: float) -> float:
	var n := data.size
	var m := data.metres_per_px
	var c := Vector2(at.x, at.z)
	var top := -INF # the lowest the ball's centre may be
	for y in range(maxi(0, int(floor((c.y - r) / m))), mini(n - 1, int(floor((c.y + r) / m)) + 1)):
		for x in range(maxi(0, int(floor((c.x - r) / m))), mini(n - 1, int(floor((c.x + r) / m)) + 1)):
			var a := _world(Vector2i(x, y))
			var b := _world(Vector2i(x + 1, y))
			var d := _world(Vector2i(x, y + 1))
			var e := _world(Vector2i(x + 1, y + 1))
			for tri in [[a, b, d], [b, e, d]]:
				top = maxf(top, _sphere_on_triangle(c, r, tri[0], tri[1], tri[2]))
	if top == -INF:
		return ground_at(at) + TUMBLE_CLEAR
	return top - r + TUMBLE_CLEAR


## The lowest centre height for a ball of radius `r` above (c.x, c.y) to stay out of triangle p q s:
## on its face (the touch point, under the centre along the normal, inside it), on an edge or on a
## corner — the highest of those that apply; −INF where the triangle is out of reach.
static func _sphere_on_triangle(c: Vector2, r: float, p: Vector3, q: Vector3, s: Vector3) -> float:
	var best := -INF
	var nrm := (q - p).cross(s - p).normalized()
	if nrm.y < 0.0:
		nrm = -nrm
	if nrm.y > 0.01: # the face: the centre r out along the normal from the touch point
		var touch := c - Vector2(nrm.x, nrm.z) * r
		if Geometry2D.point_is_inside_triangle(touch, Vector2(p.x, p.z), Vector2(q.x, q.z), Vector2(s.x, s.z)):
			var plane_y := p.y - ((touch.x - p.x) * nrm.x + (touch.y - p.z) * nrm.z) / nrm.y
			best = maxf(best, plane_y + r * nrm.y)
	for edge in [[p, q], [q, s], [s, p]]: # edges and corners
		var e0: Vector3 = edge[0]
		var e1: Vector3 = edge[1]
		# Along the edge (u 0..1) the ball's centre must clear y(u) + √(r² − plan distance²): its maximum
		# where the derivative is 0 — u = b/a + dy·√((r² − h²) / (a (a + dy²))), h the edge's plan
		# distance from the centre — or an end
		var dir := Vector2(e1.x - e0.x, e1.z - e0.z)
		var w := c - Vector2(e0.x, e0.z)
		var a := maxf(dir.length_squared(), 1e-12)
		var b := w.dot(dir)
		var dy := e1.y - e0.y
		var h2 := w.length_squared() - b * b / a
		var us := [0.0, 1.0]
		if h2 < r * r:
			us.append(clampf(b / a + dy * sqrt((r * r - h2) / (a * (a + dy * dy))), 0.0, 1.0))
		for u: float in us:
			var pt := e0.lerp(e1, u)
			var dd := (c - Vector2(pt.x, pt.z)).length_squared()
			if dd < r * r:
				best = maxf(best, pt.y + sqrt(r * r - dd))
	return best


## Height of the ground the ball collides with at `p` (x, z): the terrain mesh and collider's own
## triangle there — each cell split along the same diagonal — not the bilinear height_at().
func ground_at(p: Vector3) -> float:
	var n := data.size
	var m := data.metres_per_px
	var u := clampf(p.x / m, 0.0, n - 1.001)
	var w := clampf(p.z / m, 0.0, n - 1.001)
	var x := int(u)
	var y := int(w)
	var tx := u - x
	var ty := w - y
	if tx + ty <= 1.0: # (x, y), (x+1, y), (x, y+1)
		return _h(x, y) + (_h(x + 1, y) - _h(x, y)) * tx + (_h(x, y + 1) - _h(x, y)) * ty
	return _h(x + 1, y + 1) + (_h(x, y + 1) - _h(x + 1, y + 1)) * (1.0 - tx) + (_h(x + 1, y) - _h(x + 1, y + 1)) * (1.0 - ty)


## A short burst of leaf flecks at `at`, in the foliage's color.
func _rustle(at: Vector3, color: Color) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 14
	p.lifetime = 0.9
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.5
	p.gravity = Vector3(0, -3.0, 0)
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	var fleck := BoxMesh.new()
	fleck.size = Vector3(0.06, 0.01, 0.04)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color.lightened(0.1)
	fleck.material = mat
	p.mesh = fleck
	add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)

func surface_at(p: Vector3) -> SurfaceData:
	if p.y < _water_y:
		return params.water
	if _sample(data.rough, p) > params.oob_threshold * 255.0:
		return out_of_bounds
	var on := params.surface_threshold * 255.0
	if _sample(data.bunker, p) > on:
		return params.sand
	if _sample(data.green, p) > on:
		return params.green
	if _sample(data.fairway, p) > on:
		return params.fairway
	return params.rough


func height_at(p: Vector3) -> float:
	return _sample(data.heights, p) / 100.0


func _h(x: int, y: int) -> float:
	var n := data.size
	return data.heights[clampi(y, 0, n - 1) * n + clampi(x, 0, n - 1)] / 100.0


func _world(px: Vector2i) -> Vector3:
	return Vector3(px.x * data.metres_per_px, _h(px.x, px.y), px.y * data.metres_per_px)


## Bilinear sample of a per-pixel array (bytes or cm) at a world position.
func _sample(grid: Variant, p: Vector3) -> float:
	var n := data.size
	var u := clampf(p.x / data.metres_per_px, 0.0, n - 1.001)
	var v := clampf(p.z / data.metres_per_px, 0.0, n - 1.001)
	var x := int(u)
	var y := int(v)
	var tx := u - x
	var ty := v - y
	var i := y * n + x
	var top := lerpf(grid[i], grid[i + 1], tx)
	var bottom := lerpf(grid[i + n], grid[i + n + 1], tx)
	return lerpf(top, bottom, ty)
