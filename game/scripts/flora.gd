class_name Flora
## Trees, bushes and rocks in the project look (flat-shaded low-poly, vertex colors, beveled
## trunks, canopies of a few overlapping faceted blobs), and their colliders. Colliders depend only
## on the kind and size, so server and clients agree; the per-instance seed only varies the look
## (blob offsets, a turn, a slight hue and brightness shift).
## Solid: a tree's trunk cylinder, a rock. Soft: foliage, an Area3D sphere ("Foliage") the ball
## passes through, heavily damped (Ball.enter_foliage); the hole plays a leaf rustle on entry.


static var _views := {} # view_mesh() cache


## The thing at the origin, standing on the ground (y = 0). `sink`: trunk below ground on slopes.
## `with_view` false: its body only (colliders, foliage), no look — the same random draws, so the same turn.
## `scale` (trees): x = height (trunk and canopy), y = canopy width (visual, across), z = trunk
## height on top of x, as Procgen's tree_scale.
static func build(kind: PropKind, size: Vector2, seed: int, sink: float, surface: SurfaceData,
		scale := Vector3.ONE, with_view := true) -> Node3D:
	size = Vector2(size.x * scale.x * scale.z, size.y * scale.x)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var leaf := _tint(kind.color, kind, rng)
	var root: Node3D
	LowPoly.dry = not with_view # (the look still runs, for its random draws — the turn after them — but makes nothing)
	match kind.shape:
		PropKind.Shape.ROCK, PropKind.Shape.MOSSY_ROCK:
			root = _solid(surface)
			var shape := SphereShape3D.new()
			shape.radius = size.y * 0.6
			_shape(root, shape, Vector3(0, size.y * 0.25, 0))
			if kind.shape == PropKind.Shape.ROCK:
				_rock(root, size.y, leaf, rng)
			else:
				_mossy_rock(root, size.y, leaf, kind.moss_color, rng)
		PropKind.Shape.CORAL_CLUSTER: # as a big tree: a solid core the ball bounces off, its branches soft
			root = _solid(surface)
			var core := CylinderShape3D.new()
			core.radius = kind.trunk_radius
			core.height = size.x * 0.5 + sink
			_shape(root, core, Vector3(0, (size.x * 0.5 - sink) * 0.5, 0))
			_foliage(root, size.y * 0.55, Vector3(0, size.x * 0.55, 0))
			_coral_cluster(root, size, leaf, rng, sink)
		PropKind.Shape.CORAL_ARCH: # solid all round: two pillars and the span over (a ball can pass under it)
			root = _solid(surface)
			var half := size.y * 0.5
			for side in [-1.0, 1.0]:
				var pillar := CylinderShape3D.new()
				pillar.radius = kind.trunk_radius
				pillar.height = size.x * 0.6 + sink
				_shape(root, pillar, Vector3(side * half * 0.95, (size.x * 0.6 - sink) * 0.5, 0))
			for k in 5: # the span, in boxes along its top
				var t := 0.2 + 0.15 * k
				var span := BoxShape3D.new()
				span.size = Vector3(size.y * 0.22, kind.trunk_radius * 1.4, kind.trunk_radius * 1.6)
				_shape(root, span, Vector3(-half * cos(PI * t), size.x * sin(PI * t) * (1.0 - 0.15 * cos(TAU * t)), 0))
				(root.get_child(-1) as Node3D).rotation.z = atan2(size.x * PI * cos(PI * t), half * PI * sin(PI * t)) # along the arch
			_coral_arch(root, size, kind.trunk_radius, leaf, rng, sink)
		PropKind.Shape.GRAVESTONE, PropKind.Shape.FENCE: # solid slabs: a box the ball bounces off
			root = _solid(surface)
			var slab := BoxShape3D.new()
			if kind.shape == PropKind.Shape.GRAVESTONE:
				slab.size = Vector3(size.y, size.x, size.y * 0.3)
				_shape(root, slab, Vector3(0, size.x * 0.5, 0))
				_gravestone(root, size, leaf, rng)
			else:
				slab.size = Vector3(size.x, size.y, 0.12)
				_shape(root, slab, Vector3(0, size.y * 0.5, 0))
				_fence(root, size, leaf, rng)
		PropKind.Shape.MAUSOLEUM: # a big solid stone house
			root = _solid(surface)
			var house := BoxShape3D.new()
			house.size = Vector3(size.y * 1.15, size.x * 0.75 + sink, size.y * 1.35)
			_shape(root, house, Vector3(0, (size.x * 0.75 - sink) * 0.5, 0))
			_mausoleum(root, size, leaf, rng, sink)
		PropKind.Shape.PUMPKIN: # a small solid gourd
			root = _solid(surface)
			var gourd := SphereShape3D.new()
			gourd.radius = size.y * 0.85
			_shape(root, gourd, Vector3(0, size.y * 0.75, 0))
			_pumpkin(root, size.y, leaf, rng, kind.glow > 0.0)
		PropKind.Shape.FERN, PropKind.Shape.DESERT_SHRUB: # soft, as a bush
			root = Node3D.new()
			_foliage(root, size.y, Vector3(0, size.y * 0.45, 0))
			if kind.shape == PropKind.Shape.FERN:
				_fern(root, size.y, leaf, rng)
			else:
				_desert_shrub(root, size.y, leaf, rng)
		PropKind.Shape.FLOWER, PropKind.Shape.MOSS: # visual only, on the ground
			root = Node3D.new()
			if kind.shape == PropKind.Shape.FLOWER:
				_flower(root, size, leaf, kind.trunk_color, rng)
			else:
				_moss(root, size.y, leaf, rng)
		PropKind.Shape.BARREL, PropKind.Shape.PRICKLY_PEAR: # solid, a ball off it bounces
			root = _solid(surface)
			var body := SphereShape3D.new()
			if kind.shape == PropKind.Shape.BARREL:
				body.radius = size.y
				_shape(root, body, Vector3(0, size.x * 0.7, 0))
				_barrel(root, size, leaf, rng)
			else:
				body.radius = size.y * 1.4
				_shape(root, body, Vector3(0, size.y * 1.6, 0))
				_prickly_pear(root, size, leaf, rng)
		PropKind.Shape.BUSH:
			root = Node3D.new()
			_foliage(root, size.y, Vector3(0, size.y * 0.45, 0))
			_bush(root, size.y, leaf, rng)
		PropKind.Shape.TUMBLEWEED: # visual only: no collider (the hole rolls it with the wind)
			root = Node3D.new()
			root.set_meta("tumbleweed", size.y)
			_tumbleweed(root, size.y, leaf, rng)
		PropKind.Shape.LOG:
			root = _solid(surface)
			var log := CylinderShape3D.new()
			log.radius = size.y
			log.height = size.x
			_shape(root, log, Vector3(0, size.y * 0.8, 0))
			(root.get_child(-1) as Node3D).rotation.z = PI * 0.5
			_log(root, size, leaf, kind.trunk_color, rng)
		PropKind.Shape.STUMP:
			root = _solid(surface)
			var stump := CylinderShape3D.new()
			stump.radius = size.y
			stump.height = size.x + sink
			_shape(root, stump, Vector3(0, (size.x - sink) * 0.5, 0))
			_stump(root, size, leaf, kind.trunk_color, sink, rng)
		PropKind.Shape.STAGHORN, PropKind.Shape.TUBE: # reef: a solid foot, the rest drawn only
			root = _solid(surface)
			var foot := CylinderShape3D.new()
			foot.radius = kind.trunk_radius if kind.shape == PropKind.Shape.STAGHORN else size.y * 0.6
			foot.height = size.x * 0.35 + sink
			_shape(root, foot, Vector3(0, (size.x * 0.35 - sink) * 0.5, 0))
			if kind.shape == PropKind.Shape.STAGHORN:
				_staghorn(root, size, kind.trunk_radius, leaf, rng, sink)
			else:
				_tubes(root, size, leaf, rng, sink)
		PropKind.Shape.BRAIN, PropKind.Shape.ANEMONE: # a solid low base
			root = _solid(surface)
			var base := CylinderShape3D.new()
			base.radius = size.y * 0.75
			base.height = (size.x if kind.shape == PropKind.Shape.BRAIN else size.y * 0.9) + sink
			_shape(root, base, Vector3(0, (base.height - 2.0 * sink) * 0.5, 0))
			if kind.shape == PropKind.Shape.BRAIN:
				_brain(root, size, leaf, rng)
			else:
				_foliage(root, size.x * 0.8, Vector3(0, size.y + size.x * 0.4, 0)) # the tentacles: soft
				_anemone(root, size, leaf, rng)
		PropKind.Shape.SEA_FAN, PropKind.Shape.KELP: # soft all through: passed through, damped, like a canopy
			root = Node3D.new()
			_foliage(root, maxf(size.y, size.x * 0.35), Vector3(0, size.x * 0.5, 0))
			if kind.shape == PropKind.Shape.SEA_FAN:
				_sea_fan(root, size, leaf, rng)
			else:
				_kelp(root, size, leaf, rng)
		PropKind.Shape.STARFISH, PropKind.Shape.SHELL: # visual only, on the sand
			root = Node3D.new()
			if kind.shape == PropKind.Shape.STARFISH:
				_starfish(root, size.y, leaf, rng)
			else:
				_shell(root, size.y, leaf, rng)
		PropKind.Shape.PALM: # a trunk the ball bounces off, its crown soft
			root = _solid(surface)
			var trunk := CylinderShape3D.new()
			trunk.radius = kind.trunk_radius
			trunk.height = size.x + sink
			_shape(root, trunk, Vector3(0, (size.x - sink) * 0.5, 0))
			var crown := _palm(root, size, kind.trunk_radius, leaf, kind.trunk_color, rng, sink)
			_foliage(root, size.y * 0.8, crown)
		PropKind.Shape.CACTUS, PropKind.Shape.BURNT_TREE, PropKind.Shape.CORAL, PropKind.Shape.MUSHROOM, PropKind.Shape.GNARLED_TREE:
			root = _solid(surface) # a trunk the ball bounces off; no foliage but the mushroom's cap
			var stem := CylinderShape3D.new()
			stem.radius = size.y * 0.25 if kind.shape == PropKind.Shape.MUSHROOM else kind.trunk_radius # (a mushroom's stem goes with its cap)
			stem.height = size.x + sink
			_shape(root, stem, Vector3(0, (size.x - sink) * 0.5, 0))
			match kind.shape:
				PropKind.Shape.CACTUS:
					_cactus(root, size, kind.trunk_radius, leaf, rng, sink)
				PropKind.Shape.BURNT_TREE:
					_burnt(root, size, kind.trunk_radius, kind.trunk_color, rng, sink)
				PropKind.Shape.GNARLED_TREE:
					_gnarled(root, size, kind.trunk_radius, kind.trunk_color, rng, sink)
				PropKind.Shape.CORAL:
					_coral(root, size, kind.trunk_radius, leaf, rng, sink)
				PropKind.Shape.MUSHROOM:
					_foliage(root, size.y * 0.9, Vector3(0, size.x + size.y * 0.2, 0))
					_mushroom(root, size, leaf, kind.trunk_color, rng, sink, kind.glow > 0.0 and rng.randf() < 0.4)
		_:
			root = _solid(surface)
			var trunk := CylinderShape3D.new()
			trunk.radius = kind.trunk_radius
			trunk.height = size.x + sink
			_shape(root, trunk, Vector3(0, (size.x - sink) * 0.5, 0))
			if kind.shape == PropKind.Shape.REDWOOD: # a conifer's body, its own look
				_foliage(root, size.y * 1.15, Vector3(0, size.x + size.y * 1.3, 0))
				_redwood(root, size, kind.trunk_radius, leaf, kind.trunk_color, rng, sink)
			else:
				LowPoly.piece(root, LowPoly.rounded_prism(6, Vector3(kind.trunk_radius * 2.0, size.x + sink + size.y * 0.4,
				kind.trunk_radius * 2.0), kind.trunk_radius * 0.35, 1, 0.65), kind.trunk_color,
				Vector3(0, (size.x - sink + size.y * 0.4) * 0.5, 0))
			match kind.shape:
				PropKind.Shape.ROUND_TREE:
					_foliage(root, size.y * 1.05, Vector3(0, size.x + size.y * 0.75, 0))
					_round_canopy(root, size, leaf, rng)
				PropKind.Shape.CONIFER:
					_foliage(root, size.y * 1.15, Vector3(0, size.x + size.y * 1.3, 0))
					_conifer(root, size, leaf)
				PropKind.Shape.BUSHY_TREE:
					_foliage(root, size.y * 1.1, Vector3(0, size.x + size.y * 0.5, 0))
					_bushy_canopy(root, size, leaf, rng)
	LowPoly.dry = false
	root.set_meta("shape", kind.shape) # (what a ball hitting it sounds like: wood or stone)
	if not with_view: # the body only (colliders, foliage): its look is drawn elsewhere (GeneratedHole's batches) or not at all (server)
		for part in root.get_children():
			if part.has_meta("flat"):
				root.remove_child(part)
				part.free()
		root.rotation.y = rng.randf() * TAU
		return root
	_merge(root, material_for(kind))
	if root.has_meta("tumbleweed"): # its look on a pivot at the ball's centre: it rolls about that, not about its foot
		var spin := Node3D.new()
		spin.name = "Spin"
		spin.position = Vector3(0, size.y, 0)
		for view in root.get_children():
			if view is MeshInstance3D:
				root.remove_child(view)
				view.position -= spin.position
				spin.add_child(view)
		root.add_child(spin)
	if scale.y != 1.0: # canopy width: the merged look only (colliders keep their round shapes)
		for view in root.get_children():
			if view is MeshInstance3D:
				view.scale = Vector3(scale.y, 1.0, scale.y)
	root.rotation.y = rng.randf() * TAU
	return root


## The merged look of one kind at one size from one seed, unturned (a template: many instances of
## it are drawn as one MultiMesh, each turned, scaled and tinted). Cached.
static func view_mesh(kind: PropKind, size: Vector2, seed: int, sink: float) -> Mesh:
	var key := "%s|%s|%d|%.2f" % [kind.resource_path, size, seed, sink]
	if not _views.has(key):
		var node := build(kind, size, seed, sink, null)
		var mesh: Mesh = null
		for child in node.get_children():
			if child is MeshInstance3D:
				mesh = (child as MeshInstance3D).mesh
		node.free()
		_views[key] = mesh
	return _views[key]


## All of a thing's visual parts as one mesh (one draw call): they share the vertex-color material.
static func _merge(root: Node3D, material: Material = LowPoly.shared_material()) -> void:
	var parts: Array[Node3D] = []
	for child in root.get_children():
		if child.has_meta("flat"):
			parts.append(child)
	if parts.is_empty():
		return
	var view := MeshInstance3D.new()
	view.mesh = LowPoly.merge(parts)
	view.material_override = material
	for part in parts:
		root.remove_child(part)
		part.free()
	root.add_child(view)


## Kind's color (or one of its palette) with its hue and brightness nudged by up to ± hue_jitter / value_jitter.
static func _tint(c: Color, kind: PropKind, rng: RandomNumberGenerator) -> Color:
	if not kind.palette.is_empty(): # one of the biome's colours for this one
		c = kind.palette[rng.randi() % kind.palette.size()]
	var out := Color.from_hsv(fposmod(c.h + rng.randf_range(-1.0, 1.0) * kind.hue_jitter, 1.0), c.s,
		clampf(c.v + rng.randf_range(-1.0, 1.0) * kind.value_jitter, 0.0, 1.0))
	return out


static func _solid(surface: SurfaceData) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.set_meta("surface", surface) # the ball bounces off it with this restitution
	return body


static func _shape(parent: Node3D, shape: Shape3D, at: Vector3) -> void:
	var holder := CollisionShape3D.new()
	holder.shape = shape
	holder.position = at
	parent.add_child(holder)


## The soft part: an Area3D sphere the ball passes through, damped while inside.
static func _foliage(parent: Node3D, radius: float, at: Vector3) -> void:
	var area := Area3D.new()
	area.name = "Foliage"
	area.collision_layer = 0
	area.collision_mask = 4 # the ball
	area.monitorable = false
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	_shape(area, sphere, at)
	area.body_entered.connect(func(body: Node3D) -> void:
		if body.has_method("enter_foliage"):
			body.enter_foliage(1))
	area.body_exited.connect(func(body: Node3D) -> void:
		if body.has_method("enter_foliage"):
			body.enter_foliage(-1))
	parent.add_child(area)


## One faceted blob (a low sphere, squashed), its shade a touch lighter or darker.
static func _blob(parent: Node3D, radius: float, at: Vector3, color: Color, rng: RandomNumberGenerator,
		squash := 0.85) -> void:
	var view := LowPoly.piece(parent, LowPoly.sphere(radius, 7, 4), color, at,
		Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3)))
	view.scale = Vector3(1.0, squash, 1.0)


static func _round_canopy(root: Node3D, size: Vector2, leaf: Color, rng: RandomNumberGenerator) -> void:
	var r := size.y
	var top := size.x
	_blob(root, r * 0.8, Vector3(0, top + r * 0.75, 0), leaf, rng)
	for k in 3:
		var a := TAU * k / 3.0 + rng.randf_range(-0.4, 0.4)
		var out := Vector3(cos(a), 0, sin(a)) * r * rng.randf_range(0.45, 0.6)
		_blob(root, r * rng.randf_range(0.55, 0.7), out + Vector3(0, top + r * rng.randf_range(0.45, 0.7), 0),
			leaf.darkened(0.06) if k % 2 == 0 else leaf.lightened(0.04), rng)
	_blob(root, r * 0.55, Vector3(rng.randf_range(-0.2, 0.2) * r, top + r * 1.25, rng.randf_range(-0.2, 0.2) * r),
		leaf.lightened(0.07), rng)


static func _conifer(root: Node3D, size: Vector2, leaf: Color) -> void:
	var r := size.y
	var base := size.x
	for tier in 3:
		var radius: float = r * [1.0, 0.78, 0.52][tier]
		var height: float = r * [1.5, 1.3, 1.15][tier]
		var shade := leaf.darkened(0.05 * (2 - tier)).lightened(0.03 * tier)
		LowPoly.piece(root, LowPoly.cylinder(0.0, radius, height, 7), shade,
			Vector3(0, base + r * [0.65, 1.45, 2.2][tier], 0), Vector3(0, tier * 0.45, 0))


static func _bushy_canopy(root: Node3D, size: Vector2, leaf: Color, rng: RandomNumberGenerator) -> void:
	var r := size.y
	var top := size.x
	_blob(root, r * 0.65, Vector3(0, top + r * 0.7, 0), leaf.lightened(0.04), rng)
	for k in 4:
		var a := TAU * k / 4.0 + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), 0, sin(a)) * r * rng.randf_range(0.5, 0.7)
		_blob(root, r * rng.randf_range(0.5, 0.62), out + Vector3(0, top + r * rng.randf_range(0.3, 0.5), 0),
			leaf.darkened(0.05) if k % 2 == 0 else leaf, rng, 0.75)


static func _bush(root: Node3D, r: float, leaf: Color, rng: RandomNumberGenerator) -> void:
	_blob(root, r * 0.7, Vector3(0, r * 0.55, 0), leaf.lightened(0.04), rng, 0.8)
	for k in 3:
		var a := TAU * k / 3.0 + rng.randf_range(-0.5, 0.5)
		var out := Vector3(cos(a), 0, sin(a)) * r * rng.randf_range(0.4, 0.55)
		_blob(root, r * rng.randf_range(0.5, 0.62), out + Vector3(0, r * 0.4, 0), leaf.darkened(0.05) if k == 1 else leaf, rng, 0.75)


static func _rock(root: Node3D, r: float, stone: Color, rng: RandomNumberGenerator) -> void:
	var main := LowPoly.piece(root, LowPoly.sphere(r, 6, 3), stone, Vector3(0, r * 0.25, 0),
		Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4)))
	main.scale = Vector3(1.0, 0.62, rng.randf_range(0.75, 0.95))
	if rng.randf() < 0.6: # a smaller one leaning on it
		var side := Vector3(cos(rng.randf() * TAU), 0, sin(rng.randf() * TAU)) * r * 0.75
		var small := LowPoly.piece(root, LowPoly.sphere(r * 0.5, 6, 3), stone.darkened(0.06), side + Vector3(0, r * 0.12, 0),
			Vector3(rng.randf(), rng.randf() * TAU, rng.randf()))
		small.scale = Vector3(1.0, 0.7, 0.85)


## A charred trunk and a few bare branches angling up and out.
static func _burnt(root: Node3D, size: Vector2, r: float, bark: Color, rng: RandomNumberGenerator, sink: float) -> void:
	var h := size.x
	LowPoly.piece(root, LowPoly.rounded_prism(6, Vector3(r * 2.0, h + sink, r * 2.0), r * 0.3, 1, 0.45), bark,
		Vector3(0, (h - sink) * 0.5, 0))
	for k in 3 + int(rng.randf() < 0.5):
		var a := TAU * k / 3.5 + rng.randf_range(-0.5, 0.5)
		var at := h * rng.randf_range(0.45, 0.85)
		var reach := size.y * rng.randf_range(0.6, 1.0)
		var tilt := rng.randf_range(0.5, 0.9) # from vertical
		var dir := Vector3(cos(a) * sin(tilt), cos(tilt), sin(a) * sin(tilt))
		LowPoly.piece(root, LowPoly.cylinder(r * 0.12, r * 0.32, reach, 5), bark.lightened(0.04),
			Vector3(0, at, 0) + dir * reach * 0.5, _along(dir))


## A palm: a trunk of short segments leaning a little more each, a crown of drooping fronds and a few
## coconuts under them.
static func _palm(root: Node3D, size: Vector2, r: float, frond: Color, bark: Color, rng: RandomNumberGenerator,
		sink: float) -> Vector3:
	var lean := Vector3(cos(rng.randf() * TAU), 0.0, sin(rng.randf() * TAU)).normalized()
	var at := Vector3(0, -sink, 0)
	var segments := 6
	for k in segments:
		var dir := (Vector3.UP + lean * (0.08 + 0.07 * k)).normalized()
		var length := (size.x + (sink if k == 0 else 0.0)) / segments
		LowPoly.piece(root, LowPoly.cylinder(r * (1.0 - 0.06 * k) * 0.92, r * (1.0 - 0.06 * k), length * 1.08, 7),
			bark.lightened(0.05) if k % 2 == 0 else bark, at + dir * length * 0.5, _along(dir))
		at += dir * length
	for k in 7:
		var a := TAU * k / 7.0 + rng.randf_range(-0.2, 0.2)
		var out := Vector3(cos(a), 0.0, sin(a))
		var droop := rng.randf_range(0.65, 1.15)
		var dir := (out + Vector3.DOWN * droop).normalized()
		var leaf := LowPoly.piece(root, LowPoly.box(Vector3(size.y * 0.32, 0.06, size.y)), frond.darkened(0.06) if k % 2 == 0 else frond,
			at + dir * size.y * 0.5 + Vector3.UP * 0.1, Vector3.ZERO)
		leaf.basis = Basis.looking_at(dir, Vector3.UP)
	for k in 3:
		var a := rng.randf() * TAU
		LowPoly.piece(root, LowPoly.sphere(r * 0.45, 6, 3), bark.darkened(0.3), at + Vector3(cos(a) * r, -r * 0.6, sin(a) * r))
	return at


## Branching coral (tubes forking upward, lighter tips) or, for some seeds, a rounded brain coral
## on a short foot.
static func _coral(root: Node3D, size: Vector2, r: float, tint: Color, rng: RandomNumberGenerator, sink: float) -> void:
	var h := size.x
	if rng.randf() < 0.3:
		LowPoly.piece(root, LowPoly.cylinder(r, r * 1.2, h * 0.3 + sink, 6), tint.darkened(0.1), Vector3(0, (h * 0.3 - sink) * 0.5, 0))
		var brain := LowPoly.piece(root, LowPoly.sphere(size.y, 8, 4), tint, Vector3(0, h * 0.3 + size.y * 0.5, 0),
			Vector3(0, rng.randf() * TAU, 0))
		brain.scale = Vector3(1.0, 0.7, 1.0)
		return
	LowPoly.piece(root, LowPoly.cylinder(r * 0.8, r, h * 0.35 + sink, 6), tint.darkened(0.08), Vector3(0, (h * 0.35 - sink) * 0.5, 0))
	var foot := Vector3(0, h * 0.3, 0)
	for k in 5:
		var a := TAU * k / 5.0 + rng.randf_range(-0.4, 0.4)
		var tilt := rng.randf_range(0.15, 0.6)
		var dir := Vector3(cos(a) * sin(tilt), cos(tilt), sin(a) * sin(tilt))
		var length := h * rng.randf_range(0.55, 0.9)
		LowPoly.piece(root, LowPoly.cylinder(r * 0.35, r * 0.55, length, 6), tint, foot + dir * length * 0.5, _along(dir))
		LowPoly.piece(root, LowPoly.sphere(r * 0.45, 6, 3), tint.lightened(0.25), foot + dir * length)
		if rng.randf() < 0.5: # a fork
			var fork := (dir + Vector3(cos(a + 1.2), 0.6, sin(a + 1.2)) * 0.6).normalized()
			var at := foot + dir * length * 0.6
			LowPoly.piece(root, LowPoly.cylinder(r * 0.25, r * 0.35, length * 0.45, 5), tint.lightened(0.08),
				at + fork * length * 0.22, _along(fork))


## A loose ball of twigs: two offset low-poly shells, the inner one darker.
static func _tumbleweed(root: Node3D, r: float, dry: Color, rng: RandomNumberGenerator) -> void:
	var outer := LowPoly.piece(root, LowPoly.sphere(r, 6, 4), dry, Vector3(0, r, 0),
		Vector3(rng.randf(), rng.randf() * TAU, rng.randf()))
	outer.scale = Vector3(1.0, 0.9, 1.0)
	LowPoly.piece(root, LowPoly.sphere(r * 0.75, 5, 3), dry.darkened(0.2), Vector3(0, r, 0), Vector3(rng.randf(), rng.randf(), 0))


## A fallen log lying along x, its cut ends lighter, a moss patch on top.
static func _log(root: Node3D, size: Vector2, moss: Color, bark: Color, rng: RandomNumberGenerator) -> void:
	LowPoly.piece(root, LowPoly.rounded_prism(7, Vector3(size.y * 2.0, size.x, size.y * 2.0), size.y * 0.25, 1), bark,
		Vector3(0, size.y * 0.8, 0), Vector3(0, 0, PI * 0.5))
	for end in [-1.0, 1.0]:
		LowPoly.piece(root, LowPoly.cylinder(size.y * 0.85, size.y * 0.85, 0.06, 7), bark.lightened(0.35),
			Vector3(end * size.x * 0.5, size.y * 0.8, 0), Vector3(0, 0, PI * 0.5))
	var patch := LowPoly.piece(root, LowPoly.sphere(size.y * 0.7, 6, 3), moss, Vector3(rng.randf_range(-0.3, 0.3) * size.x, size.y * 1.55, 0))
	patch.scale = Vector3(1.6, 0.35, 1.0)
	for k in 3: # moss creeping along its top
		var along := rng.randf_range(-0.45, 0.45) * size.x
		var side := LowPoly.piece(root, LowPoly.sphere(size.y * rng.randf_range(0.5, 0.7), 6, 3), moss.lightened(0.05 * k),
			Vector3(along, size.y * 1.62, size.y * rng.randf_range(-0.25, 0.25)), Vector3(0, rng.randf_range(-0.3, 0.3), 0))
		side.scale = Vector3(2.2, 0.45, 1.15)
	if rng.randf() < 0.5:
		_toadstools(root, Vector3(rng.randf_range(-0.3, 0.3) * size.x, size.y * 1.72, 0), size.y * 0.35, size.y * 0.2, rng.randi_range(2, 4), rng)


## A stump: short and wide, the top a lighter cut ring, a little moss on the side.
static func _stump(root: Node3D, size: Vector2, moss: Color, bark: Color, sink: float, rng: RandomNumberGenerator) -> void:
	LowPoly.piece(root, LowPoly.cylinder(size.y * 0.9, size.y * 1.15, size.x + sink, 8), bark, Vector3(0, (size.x - sink) * 0.5, 0))
	LowPoly.piece(root, LowPoly.cylinder(size.y * 0.86, size.y * 0.86, 0.05, 8), bark.lightened(0.35), Vector3(0, size.x + 0.02, 0))
	var patch := LowPoly.piece(root, LowPoly.sphere(size.y * 0.5, 6, 3), moss, Vector3(size.y * 0.5, size.x * 0.6, 0))
	patch.scale = Vector3(0.5, 0.8, 1.0)
	_toadstools(root, Vector3(0, size.x + 0.04, 0), size.y * 0.6, size.y * 0.16, rng.randi_range(2, 5), rng) # mushrooms on its cut
	if rng.randf() < 0.6: # and a few at its foot
		_toadstools(root, Vector3(-size.y * 1.1, 0, 0), size.y * 0.4, size.y * 0.12, rng.randi_range(1, 3), rng)


## Euler angles turning +y onto `dir` (a branch or arm along it).
static func _along(dir: Vector3) -> Vector3:
	var axis := Vector3.UP.cross(dir)
	if axis.length() < 0.0001:
		return Vector3.ZERO
	return Basis(axis.normalized(), Vector3.UP.angle_to(dir)).get_euler()


# --- the reef (underwater) ---------------------------------------------------------------------

## Staghorn coral: a short base and tapered antler branches forking upward, tips lighter.
static func _staghorn(root: Node3D, size: Vector2, r: float, tint: Color, rng: RandomNumberGenerator, sink: float) -> void:
	var h := size.x
	LowPoly.piece(root, LowPoly.cylinder(r * 0.8, r * 1.1, h * 0.2 + sink, 6), tint.darkened(0.12), Vector3(0, (h * 0.2 - sink) * 0.5, 0))
	var foot := Vector3(0, h * 0.18, 0)
	for k in 5 + rng.randi_range(0, 2):
		var a := TAU * k / 6.0 + rng.randf_range(-0.4, 0.4)
		var tilt := rng.randf_range(0.25, 0.75)
		var dir := Vector3(cos(a) * sin(tilt), cos(tilt), sin(a) * sin(tilt))
		var length := h * rng.randf_range(0.5, 0.85)
		LowPoly.piece(root, LowPoly.cylinder(r * 0.22, r * 0.5, length, 6), tint, foot + dir * length * 0.5, _along(dir))
		for fork in 2: # two tines off each branch, thinner, angling up
			var b := a + (fork * 2 - 1) * rng.randf_range(0.5, 0.9)
			var up := (dir + Vector3(cos(b), 0.9, sin(b)) * 0.7).normalized()
			var at := foot + dir * length * rng.randf_range(0.45, 0.75)
			var tine := length * rng.randf_range(0.35, 0.5)
			LowPoly.piece(root, LowPoly.cylinder(r * 0.12, r * 0.26, tine, 5), tint.lightened(0.12), at + up * tine * 0.5, _along(up))
			LowPoly.piece(root, LowPoly.sphere(r * 0.14, 5, 3), tint.lightened(0.35), at + up * tine)
		LowPoly.piece(root, LowPoly.sphere(r * 0.24, 5, 3), tint.lightened(0.3), foot + dir * length)


## Brain coral: a low faceted dome patterned in meandering grooves — the ridges
## lighter, the grooves darker (two-tone vertex colour).
static func _brain(root: Node3D, size: Vector2, tint: Color, rng: RandomNumberGenerator) -> void:
	var dome := LowPoly.sphere(size.y, 30, 14) # fine facets: the grooves read as grooves
	dome.is_hemisphere = true
	var a := LowPoly.flat_arrays(dome, tint)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var twist := rng.randf_range(2.5, 4.5)
	var phase := rng.randf() * TAU
	for k in range(0, verts.size(), 3):
		var c := (verts[k] + verts[k + 1] + verts[k + 2]).normalized()
		var meander := sin(c.x * 14.0 + sin(c.z * 7.0 + phase) * twist) + sin(c.z * 14.0 + sin(c.x * 6.0 - phase) * twist) # winding ridges
		var ridge := meander > 0.0
		for j in 3:
			pass # (no displacement: faces sharing an edge would part)
			colors[k + j] = tint.lightened(0.16) if ridge else tint.darkened(0.22)
	a[Mesh.ARRAY_VERTEX] = verts
	a[Mesh.ARRAY_COLOR] = colors
	var node := Node3D.new()
	node.set_meta("flat", a)
	node.scale = Vector3(1.0, minf(size.x / size.y, 0.52), 1.0) # a low dome
	root.add_child(node)


## Sea fan: an upright flat lattice — a short stem, ribs fanning up and out, cross-struts between
## them — in one plane, swaying gently (the hole rocks it; soft to the ball).
static func _sea_fan(root: Node3D, size: Vector2, tint: Color, rng: RandomNumberGenerator) -> void:
	var h := size.x
	var w := size.y
	var stem := h * 0.15
	LowPoly.piece(root, LowPoly.cylinder(w * 0.03, w * 0.05, stem, 5), tint.darkened(0.2), Vector3(0, stem * 0.5, 0))
	var ribs := 11
	var tips: Array[Vector3] = []
	for k in ribs:
		var f := (k / float(ribs - 1)) * 2.0 - 1.0 # −1..1 across the fan
		var tip := Vector3(f * w * 0.5, stem + h * (0.85 - 0.25 * f * f), 0)
		var base := Vector3(f * w * 0.08, stem, 0)
		var dir := (tip - base).normalized()
		LowPoly.piece(root, LowPoly.cylinder(w * 0.012, w * 0.022, base.distance_to(tip), 4), tint, (base + tip) * 0.5, _along(dir))
		tips.append(tip)
	for row in 5: # struts across the ribs: the lattice
		var t := 0.25 + 0.16 * row
		for k in ribs - 1:
			var a := Vector3(tips[k].x * t, stem + (tips[k].y - stem) * t, 0)
			var b := Vector3(tips[k + 1].x * t, stem + (tips[k + 1].y - stem) * t, 0)
			LowPoly.piece(root, LowPoly.cylinder(w * 0.01, w * 0.01, a.distance_to(b), 4), tint.lightened(0.08), (a + b) * 0.5,
				_along((b - a).normalized()))
	for tip in tips:
		LowPoly.piece(root, LowPoly.sphere(w * 0.03, 5, 3), tint.lightened(0.3), tip)
	root.set_meta("sway", 0.07 + rng.randf() * 0.04)


## Tube coral: a cluster of open tubes of varied height on a shared foot, rims lighter.
static func _tubes(root: Node3D, size: Vector2, tint: Color, rng: RandomNumberGenerator, sink: float) -> void:
	LowPoly.piece(root, LowPoly.cylinder(size.y * 0.8, size.y, size.x * 0.12 + sink, 8), tint.darkened(0.2), Vector3(0, (size.x * 0.12 - sink) * 0.5, 0))
	for k in 6 + rng.randi_range(0, 3):
		var a := rng.randf() * TAU
		var out := rng.randf_range(0.0, size.y * 0.7)
		var tall := size.x * rng.randf_range(0.45, 1.0)
		var r := size.y * rng.randf_range(0.12, 0.2)
		var at := Vector3(cos(a) * out, size.x * 0.1, sin(a) * out)
		var lean := Vector3(cos(a), 6.0, sin(a)).normalized()
		var tube := LowPoly.cylinder(r * 1.15, r, tall, 7)
		tube.cap_top = false
		LowPoly.piece(root, tube, tint, at + lean * tall * 0.5, _along(lean))
		LowPoly.piece(root, LowPoly.cylinder(r * 1.25, r * 1.25, r * 0.25, 7), tint.lightened(0.3), at + lean * tall)


## Sea anemone: a soft column and a ring of tentacles that wave on their own (each kept apart for that).
static func _anemone(root: Node3D, size: Vector2, tint: Color, rng: RandomNumberGenerator) -> void:
	var r := size.y
	LowPoly.piece(root, LowPoly.cylinder(r * 0.8, r, r * 0.9, 9), tint.darkened(0.15), Vector3(0, r * 0.45, 0))
	LowPoly.piece(root, LowPoly.cylinder(r * 0.82, r * 0.82, r * 0.08, 9), tint.lightened(0.15), Vector3(0, r * 0.92, 0))
	var tentacles := []
	for k in 14:
		var a := TAU * k / 14.0 + rng.randf_range(-0.1, 0.1)
		var ring := (r * 0.65) if k % 2 == 0 else (r * 0.38)
		var pivot := Node3D.new() # waves round its foot
		pivot.position = Vector3(cos(a) * ring, r * 0.95, sin(a) * ring)
		pivot.rotation = Vector3(sin(a) * 0.5, 0.0, -cos(a) * 0.5) # leaning out
		root.add_child(pivot)
		var length := size.x * rng.randf_range(0.7, 1.0)
		LowPoly.part(pivot, LowPoly.cylinder(r * 0.03, r * 0.09, length, 5), tint.lightened(0.25 if k % 2 == 0 else 0.1), Vector3(0, length * 0.5, 0))
		tentacles.append([pivot, pivot.rotation, rng.randf() * TAU])
	root.set_meta("tentacles", tentacles)


## Kelp: a few tall strands, each a stalk of stacked blades leaning a little each way up, swaying.
static func _kelp(root: Node3D, size: Vector2, tint: Color, rng: RandomNumberGenerator) -> void:
	for s in 3 + rng.randi_range(0, 2):
		var at := Vector3(rng.randf_range(-0.6, 0.6), 0.0, rng.randf_range(-0.6, 0.6))
		var h := size.x * rng.randf_range(0.6, 1.0)
		var segments := 7
		var drift := Vector3(rng.randf_range(-0.1, 0.1), 1.0, rng.randf_range(-0.1, 0.1)).normalized()
		for k in segments:
			var length := h / segments
			var dir := (drift + Vector3(sin(k * 1.3 + s) * 0.12, 0.0, cos(k * 1.1 + s) * 0.12)).normalized()
			LowPoly.piece(root, LowPoly.cylinder(0.02, 0.03, length * 1.05, 4), tint.darkened(0.15), at + dir * length * 0.5, _along(dir))
			# A ribbon blade off the stalk, alternating sides, lying along it (turned round the stalk)
			var round_stalk := Basis.from_euler(_along(dir)) * Basis(Vector3.UP, k * 2.4 + s)
			var out := round_stalk * Vector3(size.y * 0.55 * (1.0 if k % 2 == 0 else -1.0), 0, 0)
			LowPoly.piece(root, LowPoly.box(Vector3(size.y, length * 1.5, 0.02)), tint if k % 2 == 0 else tint.lightened(0.08),
				at + dir * length * 0.6 + out, round_stalk.get_euler())
			at += dir * length
	root.set_meta("sway", 0.05 + rng.randf() * 0.03)


## Starfish: five tapered arms round a domed middle, lying on the sand.
static func _starfish(root: Node3D, r: float, tint: Color, rng: RandomNumberGenerator) -> void:
	var turn := rng.randf() * TAU
	for k in 5:
		var a := turn + TAU * k / 5.0
		var dir := Vector3(cos(a), 0.0, sin(a))
		LowPoly.piece(root, LowPoly.prism(4, r * 0.32, r * 0.08, r, false), tint if k % 2 == 0 else tint.darkened(0.06),
			dir * r * 0.5 + Vector3(0, r * 0.06, 0), Vector3(0, -a, PI * 0.5))
	var middle := LowPoly.piece(root, LowPoly.sphere(r * 0.28, 7, 3), tint.lightened(0.1), Vector3(0, r * 0.05, 0))
	middle.scale = Vector3(1.0, 0.45, 1.0)


## A scallop shell: a ribbed fan lying on the sand, ribs alternating light and dark.
static func _shell(root: Node3D, r: float, tint: Color, rng: RandomNumberGenerator) -> void:
	var turn := rng.randf() * TAU
	for k in 7:
		var a := turn + (k - 3) * 0.24
		var dir := Vector3(cos(a), 0.0, sin(a))
		LowPoly.piece(root, LowPoly.box(Vector3(r * 0.2, r * 0.12, r)), tint.lightened(0.12) if k % 2 == 0 else tint.darkened(0.08),
			dir * r * 0.5 + Vector3(0, r * 0.06 + 0.02 * absf(k - 3) * -0.5, 0), Vector3(0, -a + PI * 0.5, 0))
	LowPoly.piece(root, LowPoly.box(Vector3(r * 0.35, r * 0.12, r * 0.2)), tint.darkened(0.1), Vector3(0, r * 0.06, 0), Vector3(0, -turn, 0))


# --- the detail pass: forests, mystic, desert ------------------------------------------------

## A piece whose faces alternate two tones round its axis in `stripes` bands (ribs, bark ridges).
static func _ribbed(root: Node3D, mesh: Mesh, a: Color, b: Color, stripes: int, at: Vector3, rot := Vector3.ZERO) -> Node3D:
	var node := LowPoly.piece(root, mesh, a, at, rot)
	if LowPoly.dry:
		return node
	var arrays: Array = node.get_meta("flat")
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for k in range(0, verts.size(), 3):
		var c := verts[k] + verts[k + 1] + verts[k + 2]
		var band := posmod(int(floor((atan2(c.x, c.z) / TAU + 0.5) * stripes)), 2)
		for j in 3:
			colors[k + j] = a if band == 0 else b
	arrays[Mesh.ARRAY_COLOR] = colors
	return node


## Flags a piece to glow: its vertex alpha below 1 (material_for() lights it by 1 − alpha).
static func _glowing(node: Node3D, amount := 0.5) -> void:
	if LowPoly.dry:
		return
	var arrays: Array = node.get_meta("flat")
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for k in colors.size():
		colors[k].a = 1.0 - amount
	arrays[Mesh.ARRAY_COLOR] = colors


## The look's material for a kind: the shared matte one, or for a kind that glows (PropKind.glow)
## the same matte look plus a soft emission where its vertex alpha is below 1 (a cap, petals).
static func material_for(kind: PropKind) -> Material:
	if kind.glow <= 0.0:
		return LowPoly.shared_material()
	var key := "glow|%.2f|%.2f" % [kind.glow, kind.flicker]
	if not _views.has(key):
		var s := Shader.new()
		s.code = """
shader_type spatial;
uniform float glow;
uniform float flicker;
varying float seed;
void vertex() { seed = dot(MODEL_MATRIX[3].xyz, vec3(1.7, 0.0, 2.3)); }
vec3 linear(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c)); }
void fragment() {
	vec3 c = linear(COLOR.rgb); // (vertex colours are sRGB, as the shared material reads them)
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	float f = 1.0 - flicker * (0.5 + 0.5 * sin(TIME * 11.0 + seed) * sin(TIME * 7.3 + seed * 1.9)); // a candle
	EMISSION = c * glow * (1.0 - COLOR.a) * f;
}
"""
		var mat := ShaderMaterial.new()
		mat.shader = s
		mat.set_shader_parameter("glow", kind.glow)
		mat.set_shader_parameter("flicker", kind.flicker)
		_views[key] = mat
	return _views[key]


## A mushroom: a stem curving up in a few tapering segments (some lean), a domed cap of two faceted
## hemispheres tilted to the stem's end, gills under it (a dark ring and radial fins), light spots;
## big ones with a little cluster at their foot; some (`glow`) with glowing caps. The collider stays
## upright (Flora.build): the lean is slight enough to keep the cap inside its foliage.
static func _mushroom(root: Node3D, size: Vector2, cap: Color, stem: Color, rng: RandomNumberGenerator, sink: float, glow: bool) -> void:
	var h := size.x
	var R := size.y
	var girth := R * 0.2
	var a0 := rng.randf() * TAU
	var lean := Vector3(cos(a0), 0.0, sin(a0)) * (rng.randf_range(0.15, 0.35) if rng.randf() < 0.5 else 0.05)
	var at := Vector3(0, -sink, 0)
	var dir := Vector3.UP
	var segments := 4
	LowPoly.piece(root, LowPoly.cylinder(girth * 1.15, girth * 1.5, girth * 0.6, 8), stem.darkened(0.06), Vector3(0, girth * 0.3, 0)) # the foot
	for k in segments:
		dir = (Vector3.UP + lean * (k + 1) * (k + 1) / float(segments * segments) * 2.0).normalized() # bending more toward the top
		var length := (h + (sink if k == 0 else 0.0)) / segments
		var r0 := girth * (1.15 - 0.1 * k)
		LowPoly.piece(root, LowPoly.cylinder(r0 * 0.9, r0, length * 1.08, 8), stem.darkened(0.02 * k), at + dir * length * 0.5, _along(dir))
		at += dir * length
	var frame := Basis.from_euler(_along(dir)) * Basis(Vector3.UP, rng.randf() * TAU)
	var tilt := frame.get_euler()
	var low := LowPoly.sphere(R, 10, 5)
	low.is_hemisphere = true
	var dome := LowPoly.piece(root, low, cap, at, tilt)
	dome.scale = Vector3(1.0, 0.55, 1.0)
	var high := LowPoly.sphere(R * 0.7, 9, 4)
	high.is_hemisphere = true
	var crown := LowPoly.piece(root, high, cap.lightened(0.05), at + frame * Vector3(R * 0.1, R * 0.08, -R * 0.06), tilt)
	crown.scale = Vector3(1.0, 0.62, 1.0)
	LowPoly.piece(root, LowPoly.cylinder(R * 0.97, girth * 1.05, R * 0.14, 14), cap.darkened(0.5), at - frame.y * R * 0.07, tilt) # gills
	for k in 10: # the gills' fins: dark radial blades under the rim
		LowPoly.piece(root, LowPoly.box(Vector3(R * 0.8, R * 0.1, R * 0.015)), cap.darkened(0.6),
			at + frame * Vector3(cos(TAU * k / 10.0) * R * 0.5, -R * 0.06, sin(TAU * k / 10.0) * R * 0.5),
			(frame * Basis(Vector3.UP, -TAU * k / 10.0)).get_euler())
	if glow:
		_glowing(dome)
		_glowing(crown, 0.65)
	for k in 8 + int(R * 3.0): # spots over the cap
		var a := rng.randf() * TAU
		var up := rng.randf_range(0.85, 1.35) # from the top (round the rim: the crown covers the middle)
		var out := Vector3(cos(a) * sin(up), cos(up) * 0.55, sin(a) * sin(up))
		var spot := LowPoly.piece(root, LowPoly.sphere(R * rng.randf_range(0.1, 0.16), 6, 3), cap.lightened(0.6), at + frame * (out * R * 1.03), tilt)
		spot.scale = Vector3(1.0, 0.5, 1.0)
		if glow:
			_glowing(spot, 0.8)
	if R > 1.2: # a little cluster at its foot
		for k in rng.randi_range(2, 5):
			var a := rng.randf() * TAU
			var d := girth * rng.randf_range(1.8, 3.2)
			var s := R * rng.randf_range(0.07, 0.14)
			var foot := Vector3(cos(a) * d, 0.0, sin(a) * d)
			var bend := (Vector3.UP + Vector3(cos(a), 0.0, sin(a)) * 0.3).normalized()
			LowPoly.piece(root, LowPoly.cylinder(s * 0.16, s * 0.24, s * 1.2, 6), stem, foot + bend * s * 0.6, _along(bend))
			var little := LowPoly.sphere(s, 8, 3)
			little.is_hemisphere = true
			var lit := LowPoly.piece(root, little, cap.lightened(0.08), foot + bend * s * 1.15, _along(bend))
			lit.scale = Vector3(1.0, 0.6, 1.0)
			if glow:
				_glowing(lit, 0.7)


## A fern: fronds arching out from a crown, each a midrib of short segments with a leafy blade
## along it narrowing toward the tip.
static func _fern(root: Node3D, r: float, leaf: Color, rng: RandomNumberGenerator) -> void:
	var fronds := 6 + rng.randi_range(0, 3)
	for f in fronds:
		var a := TAU * f / fronds + rng.randf_range(-0.2, 0.2)
		var out := Vector3(cos(a), 0.0, sin(a))
		var side := out.cross(Vector3.UP).normalized()
		var at := Vector3(0, 0.02, 0)
		var segments := 5
		var rise := rng.randf_range(1.8, 2.6)
		for k in segments:
			var dir := (out + Vector3.UP * (rise - 1.0 * k)).normalized() # steeply up, then over: an arch
			var length := r / segments * 1.2
			var mid := at + dir * length * 0.5
			LowPoly.piece(root, LowPoly.cylinder(r * 0.012, r * 0.02, length * 1.05, 3), leaf.darkened(0.2), mid, _along(dir))
			var tip := 1.0 - k / float(segments)
			for s in [-1.0, 1.0]: # a pair of leaflets, raised into a V
				var reach: float = r * (0.3 * tip + 0.08)
				var out_s: Vector3 = (side * s + dir.cross(side * s).normalized() * -0.35).normalized()
				var blade := LowPoly.piece(root, LowPoly.box(Vector3(reach, r * 0.01, length * 0.45)), leaf if k % 2 == 0 else leaf.lightened(0.07), mid + out_s * reach * 0.5)
				blade.basis = Basis(out_s, dir.cross(out_s).normalized(), dir).orthonormalized()
			at += dir * length


## A glowing flower: a thin stem, a leaf, a ring of petals and a lighter heart (the petals glow).
static func _flower(root: Node3D, size: Vector2, petal: Color, stem: Color, rng: RandomNumberGenerator) -> void:
	var h := size.x
	var r := size.y
	LowPoly.piece(root, LowPoly.cylinder(r * 0.05, r * 0.07, h, 4), stem, Vector3(0, h * 0.5, 0))
	var leaf := LowPoly.piece(root, LowPoly.sphere(r * 0.35, 5, 2), stem.lightened(0.1), Vector3(r * 0.2, h * 0.35, 0), Vector3(0, rng.randf() * TAU, 0.6))
	leaf.scale = Vector3(1.0, 0.15, 0.4)
	for k in 6:
		var a := TAU * k / 6.0
		var p := LowPoly.piece(root, LowPoly.sphere(r * 0.32, 5, 2), petal, Vector3(cos(a) * r * 0.36, h, sin(a) * r * 0.36), Vector3(0, -a, 0.35))
		p.scale = Vector3(1.0, 0.3, 0.6)
		_glowing(p, 0.6)
	var heart := LowPoly.piece(root, LowPoly.sphere(r * 0.16, 6, 3), petal.lightened(0.55), Vector3(0, h + r * 0.05, 0))
	_glowing(heart, 0.9)


## A mossy rock: a faceted stone with a soft cap of moss over its top and down one side.
static func _mossy_rock(root: Node3D, r: float, stone: Color, moss: Color, rng: RandomNumberGenerator) -> void:
	_rock(root, r, stone, rng)
	var cap := LowPoly.piece(root, LowPoly.sphere(r * 0.8, 8, 3), moss, Vector3(rng.randf_range(-0.1, 0.1) * r, r * 0.5, 0))
	cap.scale = Vector3(1.0, 0.3, 0.85)
	var drip := LowPoly.piece(root, LowPoly.sphere(r * 0.42, 6, 3), moss.darkened(0.08), Vector3(r * 0.5, r * 0.3, r * 0.2))
	drip.scale = Vector3(0.9, 0.45, 0.8)


## Moss: a few soft flat cushions on the forest floor.
static func _moss(root: Node3D, r: float, moss: Color, rng: RandomNumberGenerator) -> void:
	for k in 3 + rng.randi_range(0, 2):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, r * 0.7)
		var c := LowPoly.piece(root, LowPoly.sphere(r * rng.randf_range(0.35, 0.6), 7, 3), moss if k % 2 == 0 else moss.lightened(0.07),
			Vector3(cos(a) * d, 0.0, sin(a) * d), Vector3(0, rng.randf() * TAU, 0))
		c.scale = Vector3(1.0, 0.16, 0.8)


## A big forest tree: root flares round its foot, a tall trunk with bark ridges (two-tone facets)
## bare low down, then tiers of short branches each ending in dense foliage clumps, a crown, and
## now and then a broken stub. Stands in a conifer's footprint (the same collider and foliage).
static func _redwood(root: Node3D, size: Vector2, r: float, leaf: Color, bark: Color, rng: RandomNumberGenerator, sink: float) -> void:
	var h := size.x
	var R := size.y
	var top := h + R * 2.6
	_ribbed(root, LowPoly.cylinder(r * 0.55, r, top + sink, 12), bark, bark.darkened(0.14), 12, Vector3(0, (top - sink) * 0.5, 0))
	for k in 6: # root flares
		var a := TAU * k / 6.0 + rng.randf_range(-0.2, 0.2)
		var flare := LowPoly.piece(root, LowPoly.prism(3, r * 1.0, r * 0.15, r * 1.5), bark.darkened(0.06),
			Vector3(cos(a), 0.0, sin(a)) * r * 0.85 + Vector3(0, r * 0.5 - sink * 0.5, 0), Vector3(0, -a - PI * 0.5, 0))
		flare.scale = Vector3(1.0, 1.0, 0.5)
	var tiers := 5
	for t in tiers:
		var f := t / float(tiers - 1)
		var y := h * 0.55 + (top - R * 0.6 - h * 0.55) * f
		var reach := R * (1.25 - 0.65 * f)
		var branches := 4 + (t + 1) % 2
		for b in branches:
			var a := TAU * b / branches + t * 0.9 + rng.randf_range(-0.3, 0.3)
			var out := Vector3(cos(a), -0.12, sin(a)).normalized()
			var foot := Vector3(0, y, 0) + Vector3(cos(a), 0, sin(a)) * r * (1.0 - 0.4 * f) * 0.7
			if rng.randf() < 0.1: # a broken branch: a short stub, no foliage
				LowPoly.piece(root, LowPoly.cylinder(r * 0.07, r * 0.13, reach * 0.3, 5), bark.darkened(0.12), foot + out * reach * 0.15, _along(out))
				continue
			LowPoly.piece(root, LowPoly.cylinder(r * 0.05, r * 0.11, reach, 5), bark.darkened(0.1), foot + out * reach * 0.5, _along(out))
			for c in 2: # a dense clump at the end and one along it
				var at := foot + out * reach * (0.95 if c == 0 else 0.55) + Vector3(0, R * 0.1, 0)
				var clump := LowPoly.piece(root, LowPoly.sphere(R * (0.48 if c == 0 else 0.36) * (1.0 - 0.3 * f), 6, 3),
					(leaf.darkened(0.04 * (tiers - t)) if c == 0 else leaf.lightened(0.05)), at, Vector3(rng.randf(), rng.randf() * TAU, 0))
				clump.scale = Vector3(1.0, 0.55, 1.0)
	var crown := LowPoly.piece(root, LowPoly.cylinder(0.0, R * 0.6, R * 1.4, 7), leaf.lightened(0.04), Vector3(0, top, 0))
	crown.rotation.y = rng.randf()


## A saguaro: a ribbed column (two-tone facets), one to three arms at varied heights that run out
## and bend upward, light spine dots along the ribs, and sometimes flowers on top.
static func _cactus(root: Node3D, size: Vector2, r: float, green: Color, rng: RandomNumberGenerator, sink: float) -> void:
	var h := size.x
	var dark := green.darkened(0.14)
	_ribbed(root, LowPoly.rounded_prism(8, Vector3(r * 2.0, h + sink, r * 2.0), r * 0.6, 2, 0.85), green, dark, 8, Vector3(0, (h - sink) * 0.5, 0))
	_spines(root, Vector3(0, -sink, 0), Vector3.UP, h + sink, r, 8, rng)
	var arms := 1 + int(rng.randf() < 0.6) + int(rng.randf() < 0.3)
	var turn := rng.randf() * TAU
	for k in arms:
		var a := turn + TAU * k / arms + rng.randf_range(-0.4, 0.4)
		var side := Vector3(cos(a), 0, sin(a))
		var at := h * rng.randf_range(0.3, 0.65)
		var reach := size.y * rng.randf_range(0.55, 0.95)
		var arm_r := r * rng.randf_range(0.55, 0.7)
		var out := (side + Vector3.UP * 0.25).normalized()
		_ribbed(root, LowPoly.rounded_prism(8, Vector3(arm_r * 2.0, reach, arm_r * 2.0), arm_r * 0.5, 1), green.darkened(0.04), dark, 8,
			Vector3(0, at, 0) + out * reach * 0.5, _along(out))
		var elbow := Vector3(0, at, 0) + out * reach
		var mid := (side * 0.15 + Vector3.UP).normalized()
		LowPoly.piece(root, LowPoly.sphere(arm_r, 8, 4), green.darkened(0.04), elbow)
		var up := minf(h - at, h * rng.randf_range(0.2, 0.45)) + arm_r
		_ribbed(root, LowPoly.rounded_prism(8, Vector3(arm_r * 2.0, up, arm_r * 2.0), arm_r * 0.6, 2, 0.85), green.lightened(0.03), dark, 8,
			elbow + mid * up * 0.5, _along(mid))
		_spines(root, elbow, mid, up, arm_r, 6, rng)
	if rng.randf() < 0.35:
		_crown_flowers(root, Vector3(0, h + r * 0.3, 0), r * 0.9, rng)


## Spine dots up a column along its ribs: tiny pale cubes, a few per rib.
static func _spines(root: Node3D, from: Vector3, dir: Vector3, length: float, r: float, ribs: int, rng: RandomNumberGenerator) -> void:
	var frame := Basis.from_euler(_along(dir))
	for k in ribs:
		var a := TAU * (k + 0.5) / ribs
		for j in 3:
			var y := length * (0.2 + 0.28 * j + rng.randf_range(-0.05, 0.05))
			LowPoly.piece(root, LowPoly.box(Vector3.ONE * r * 0.1), Color(0.96, 0.92, 0.78),
				from + frame * Vector3(sin(a) * r * 1.02, y, cos(a) * r * 1.02))


## A barrel cactus: a squat ribbed dome, spine dots along its ribs, often a ring of flowers on top.
static func _barrel(root: Node3D, size: Vector2, green: Color, rng: RandomNumberGenerator) -> void:
	var r := size.y
	var squash := size.x / r
	var body := _ribbed(root, LowPoly.sphere(r, 12, 6), green, green.darkened(0.14), 12, Vector3(0, r * squash * 0.7, 0))
	body.scale = Vector3(1.0, squash, 1.0)
	for k in 12:
		var a := TAU * (k + 0.5) / 12.0
		for j in 2:
			var up := 0.5 + 0.55 * j
			LowPoly.piece(root, LowPoly.box(Vector3.ONE * r * 0.07), Color(0.96, 0.92, 0.78),
				Vector3(sin(a) * sin(up) * r * 1.03, r * squash * (0.7 + cos(up) * 1.03), cos(a) * sin(up) * r * 1.03))
	if rng.randf() < 0.65:
		_crown_flowers(root, Vector3(0, r * squash * 1.68, 0), r * 0.45, rng)


## A prickly pear: flat oval pads stacked edge on edge, each turned its own way, spined, a few fruit.
static func _prickly_pear(root: Node3D, size: Vector2, green: Color, rng: RandomNumberGenerator) -> void:
	var pad := size.y
	var pads := [Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(0, pad * 0.9, 0))]
	for k in 3 + rng.randi_range(0, 3):
		var parent: Transform3D = pads[rng.randi_range(0, pads.size() - 1)]
		var tip := parent * Vector3(rng.randf_range(-0.7, 0.7) * pad, pad * 0.8, 0)
		var turn := parent.basis * Basis(Vector3.FORWARD, rng.randf_range(-1.1, 1.1)) * Basis(Vector3.UP, rng.randf_range(-0.8, 0.8))
		pads.append(Transform3D(turn, tip + turn.y * pad * 0.8))
	for k in pads.size():
		var xf: Transform3D = pads[k]
		var view := LowPoly.piece(root, LowPoly.sphere(pad, 8, 4), green if k % 2 == 0 else green.lightened(0.06), xf.origin, xf.basis.get_euler())
		view.scale = Vector3(0.72, 1.0, 0.2)
		for s in 5:
			var face := -1.0 if s % 2 == 0 else 1.0
			LowPoly.piece(root, LowPoly.box(Vector3.ONE * pad * 0.07), Color(0.96, 0.92, 0.78),
				xf * Vector3(rng.randf_range(-0.45, 0.45) * pad, rng.randf_range(-0.6, 0.6) * pad, face * pad * 0.19))
	for k in rng.randi_range(0, 3): # fruit on the rims of the last pads
		var top: Transform3D = pads[pads.size() - 1 - k % pads.size()]
		LowPoly.piece(root, LowPoly.sphere(pad * 0.17, 6, 3), Color(0.78, 0.2, 0.36), top * Vector3(rng.randf_range(-0.4, 0.4) * pad, pad * 0.95, 0))


## A desert shrub: a tangle of thin grey-brown twigs from one foot, small dusty leaf tufts at their ends.
static func _desert_shrub(root: Node3D, r: float, leaf: Color, rng: RandomNumberGenerator) -> void:
	var twig := Color(0.46, 0.38, 0.31)
	for k in 12:
		var a := rng.randf() * TAU
		var tilt := rng.randf_range(0.3, 1.1)
		var dir := Vector3(cos(a) * sin(tilt), cos(tilt), sin(a) * sin(tilt))
		var length := r * rng.randf_range(0.7, 1.2)
		LowPoly.piece(root, LowPoly.cylinder(r * 0.015, r * 0.04, length, 4), twig, dir * length * 0.5, _along(dir))
		var tuft := LowPoly.piece(root, LowPoly.sphere(r * rng.randf_range(0.12, 0.2), 5, 3), leaf if k % 2 == 0 else leaf.darkened(0.1), dir * length)
		tuft.scale = Vector3(1.0, 0.7, 1.0)


## A ring of small flowers (a cactus's crown).
static func _crown_flowers(root: Node3D, at: Vector3, r: float, rng: RandomNumberGenerator) -> void:
	var tone: Color = [Color(0.95, 0.45, 0.6), Color(0.98, 0.82, 0.3), Color(0.95, 0.6, 0.35)][rng.randi_range(0, 2)]
	for k in 5:
		var a := TAU * k / 5.0 + rng.randf()
		var petal := LowPoly.piece(root, LowPoly.sphere(r * 0.35, 5, 2), tone, at + Vector3(cos(a) * r * 0.45, r * 0.1, sin(a) * r * 0.45))
		petal.scale = Vector3(1.0, 0.5, 1.0)
	LowPoly.piece(root, LowPoly.sphere(r * 0.22, 5, 3), tone.lightened(0.45), at + Vector3(0, r * 0.22, 0))


## Little mushrooms in a group (on a stump's top, along a log): `n` of them round `at`.
static func _toadstools(root: Node3D, at: Vector3, spread: float, s: float, n: int, rng: RandomNumberGenerator) -> void:
	var cap: Color = [Color(0.82, 0.5, 0.3), Color(0.9, 0.78, 0.6), Color(0.7, 0.32, 0.25)][rng.randi_range(0, 2)]
	for k in n:
		var a := rng.randf() * TAU
		var foot := at + Vector3(cos(a), 0.0, sin(a)) * spread * rng.randf_range(0.2, 1.0)
		var size := s * rng.randf_range(0.6, 1.2)
		LowPoly.piece(root, LowPoly.cylinder(size * 0.18, size * 0.24, size * 1.1, 5), Color(0.92, 0.88, 0.8), foot + Vector3(0, size * 0.55, 0))
		var dome := LowPoly.sphere(size, 7, 3)
		dome.is_hemisphere = true
		var c := LowPoly.piece(root, dome, cap, foot + Vector3(0, size * 1.05, 0), Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2)))
		c.scale = Vector3(1.0, 0.6, 1.0)


# --- the reef's major formations ------------------------------------------------------------------

## A big coral formation: staghorn, brain, fan and tube corals 3–5× their reef size crowded on one
## rocky foot, the tallest in the middle. Built from the reef's own pieces, each sub-coral moved
## out round the foot.
static func _coral_cluster(root: Node3D, size: Vector2, tint: Color, rng: RandomNumberGenerator, sink: float) -> void:
	var h := size.x
	var R := size.y
	var foot := LowPoly.piece(root, LowPoly.sphere(R * 0.45, 9, 4), tint.darkened(0.35), Vector3(0, -sink * 0.5, 0))
	foot.scale = Vector3(1.0, 0.35 + sink / maxf(R, 0.01), 1.0)
	var count := 4 + rng.randi_range(0, 2)
	for k in count:
		var sub := Node3D.new()
		var a := TAU * k / count + rng.randf_range(-0.3, 0.3)
		var d := 0.0 if k == 0 else R * rng.randf_range(0.25, 0.5)
		var s := (1.0 if k == 0 else rng.randf_range(0.55, 0.8))
		var shade := Color.from_hsv(fposmod(tint.h + rng.randf_range(-0.08, 0.08), 1.0), tint.s, clampf(tint.v + rng.randf_range(-0.1, 0.1), 0.0, 1.0))
		match (k + rng.randi_range(0, 3)) % 4:
			0:
				_staghorn(sub, Vector2(h, R * 0.6) * s, R * 0.06 * s, shade, rng, 0.0)
			1:
				_brain(sub, Vector2(h * 0.35, R * 0.4) * s, shade, rng)
			2:
				_sea_fan(sub, Vector2(h * 0.9, R * 0.55) * s, shade, rng)
			_:
				_tubes(sub, Vector2(h * 0.6, R * 0.3) * s, shade, rng, 0.0)
		var place := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(cos(a) * d, R * 0.05, sin(a) * d))
		for piece in sub.get_children():
			sub.remove_child(piece)
			piece.transform = place * piece.transform
			root.add_child(piece)
		sub.free()


## A coral arch: two lumpy pillars `size.y` apart joined by a span bending over at `size.x` high,
## crusted with bumps and with sprigs of staghorn along the top; a ball can fly through it.
static func _coral_arch(root: Node3D, size: Vector2, r: float, tint: Color, rng: RandomNumberGenerator, sink: float) -> void:
	var h := size.x
	var half := size.y * 0.5
	var steps := 14
	var prev := Vector3(-half, -sink, 0)
	for k in range(1, steps + 1):
		var t := float(k) / steps # along the arch: up the left pillar, over, down the right
		var x := -half * cos(PI * t)
		var y := h * sin(PI * t) * (1.0 - 0.15 * cos(TAU * t))
		var at := Vector3(x, y if k < steps else -sink, 0)
		var thick := r * (1.25 - 0.45 * sin(PI * t)) # thicker at the feet
		var dir := (at - prev).normalized()
		var shade := tint.darkened(0.18) if k % 2 == 0 else tint
		LowPoly.piece(root, LowPoly.cylinder(thick * 0.92, thick, prev.distance_to(at) * 1.12, 7), shade, (prev + at) * 0.5, _along(dir))
		for b in 2: # crusty bumps
			var bump := LowPoly.piece(root, LowPoly.sphere(thick * rng.randf_range(0.35, 0.6), 6, 3), tint.lightened(0.1) if b == 0 else tint.darkened(0.3),
				(prev + at) * 0.5 + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.3, 0.3), (1.0 if b == 0 else -1.0)) * thick * 0.8)
			bump.scale = Vector3(1.0, 0.7, 1.0)
		if t > 0.3 and t < 0.75 and k % 2 == 1: # sprigs on top of the span
			var sprig := Node3D.new()
			_staghorn(sprig, Vector2(h * 0.18, h * 0.12), thick * 0.12, tint.lightened(0.2), rng, 0.0)
			var place := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), at + Vector3(0, thick * 0.7, 0))
			for piece in sprig.get_children():
				sprig.remove_child(piece)
				piece.transform = place * piece.transform
				root.add_child(piece)
			sprig.free()
		prev = at
	for side in [-1.0, 1.0]: # rubble round each foot
		for k in 3:
			var rubble := LowPoly.piece(root, LowPoly.sphere(r * rng.randf_range(0.4, 0.7), 6, 3), tint.darkened(0.35),
				Vector3(side * half + rng.randf_range(-1.0, 1.0) * r * 1.4, 0.0, rng.randf_range(-1.0, 1.0) * r * 1.4))
			rubble.scale = Vector3(1.0, 0.55, 1.0)


# --- the cemetery -------------------------------------------------------------------------------

## A gravestone `size.x` tall and `size.y` wide, one of four by its seed: a rounded-top slab, a cross,
## a leaning slab, or a cracked one with its broken corner lying at its foot. Stone grey, mossy at the
## foot, an engraved panel.
static func _gravestone(root: Node3D, size: Vector2, stone: Color, rng: RandomNumberGenerator) -> void:
	var h := size.x
	var w := size.y
	var t := w * 0.22 # thickness
	var dark := stone.darkened(0.25)
	LowPoly.piece(root, LowPoly.box(Vector3(w * 1.15, h * 0.08, t * 1.6)), stone.darkened(0.1), Vector3(0, h * 0.04, 0)) # the plinth
	var style := rng.randi_range(0, 3)
	var lean := Vector3(rng.randf_range(-0.06, 0.06), 0, rng.randf_range(-0.04, 0.04))
	if style == 2: # leaning well over
		lean = Vector3(rng.randf_range(0.18, 0.32) * (1.0 if rng.randf() < 0.5 else -1.0), 0, rng.randf_range(-0.1, 0.1))
	var frame := Basis.from_euler(lean)
	var at := func(p: Vector3) -> Vector3: return frame * p + Vector3(0, h * 0.08, 0)
	match style:
		1: # a cross
			LowPoly.piece(root, LowPoly.box(Vector3(w * 0.28, h * 0.92, t)), stone, at.call(Vector3(0, h * 0.46, 0)), lean)
			LowPoly.piece(root, LowPoly.box(Vector3(w * 0.9, w * 0.26, t)), stone, at.call(Vector3(0, h * 0.68, 0)), lean)
		_: # a slab with a rounded top (cracked: its upper corner broken off and lying beside it)
			var body := h * 0.72
			LowPoly.piece(root, LowPoly.box(Vector3(w, body, t)), stone, at.call(Vector3(0, body * 0.5, 0)), lean)
			var top := LowPoly.piece(root, LowPoly.cylinder(w * 0.5, w * 0.5, t, 10), stone.lightened(0.04), at.call(Vector3(0, body, 0)),
				(frame * Basis(Vector3.RIGHT, PI * 0.5)).get_euler())
			if style == 3: # cracked: a dark seam and the broken corner on the ground
				top.scale = Vector3(0.6, 1.0, 1.0)
				LowPoly.piece(root, LowPoly.box(Vector3(w * 0.7, h * 0.02, t * 1.05)), dark, at.call(Vector3(w * 0.1, body * 0.7, 0)), lean + Vector3(0, 0, 0.5))
				LowPoly.piece(root, LowPoly.box(Vector3(w * 0.4, w * 0.3, t)), stone, Vector3(w * 0.75, w * 0.12, t * 0.8), Vector3(0.3, rng.randf() * TAU, 1.2))
			LowPoly.piece(root, LowPoly.box(Vector3(w * 0.6, body * 0.35, t * 0.1)), dark, at.call(Vector3(0, body * 0.62, -t * 0.5))) # the engraved panel
	var moss := LowPoly.piece(root, LowPoly.sphere(w * 0.35, 6, 3), Color(0.3, 0.38, 0.28), Vector3(rng.randf_range(-0.3, 0.3) * w, h * 0.06, -t * 0.7))
	moss.scale = Vector3(1.3, 0.35, 0.6)


## A mausoleum: a stone house on steps, two columns either side of a dark door under a pediment, a
## stepped roof with an urn or cross on top; `size.x` tall, `size.y` wide (and deep).
static func _mausoleum(root: Node3D, size: Vector2, stone: Color, rng: RandomNumberGenerator, sink: float) -> void:
	var h := size.x
	var w := size.y
	var d := w * 1.2
	var dark := stone.darkened(0.3)
	LowPoly.piece(root, LowPoly.box(Vector3(w * 1.3, h * 0.08 + sink, d * 1.25)), stone.darkened(0.12), Vector3(0, (h * 0.08 - sink) * 0.5, 0)) # the steps
	LowPoly.piece(root, LowPoly.box(Vector3(w * 1.15, h * 0.05, d * 1.12)), stone.darkened(0.06), Vector3(0, h * 0.105, 0))
	var wall := h * 0.58
	LowPoly.piece(root, LowPoly.box(Vector3(w, wall, d)), stone, Vector3(0, h * 0.13 + wall * 0.5, 0))
	LowPoly.piece(root, LowPoly.box(Vector3(w * 0.36, wall * 0.62, d * 0.05)), Color(0.08, 0.08, 0.1), Vector3(0, h * 0.13 + wall * 0.31, -d * 0.5)) # the door
	for side in [-1.0, 1.0]:
		LowPoly.piece(root, LowPoly.cylinder(w * 0.07, w * 0.08, wall, 8), stone.lightened(0.06), Vector3(side * w * 0.32, h * 0.13 + wall * 0.5, -d * 0.56))
	var eave := h * 0.13 + wall
	LowPoly.piece(root, LowPoly.box(Vector3(w * 1.1, h * 0.06, d * 1.14)), stone.lightened(0.04), Vector3(0, eave + h * 0.03, 0))
	for side in [-1.0, 1.0]: # a pitched roof: two slabs meeting at the ridge, the gables front and back
		LowPoly.piece(root, LowPoly.box(Vector3(w * 0.62, h * 0.05, d * 1.16)), stone.darkened(0.08), Vector3(side * w * 0.26, eave + h * 0.06 + w * 0.17, 0), Vector3(0, 0, -side * 0.6))
	for end in [-1.0, 1.0]:
		var gable := LowPoly.piece(root, LowPoly.cylinder(0.0, w * 0.5, w * 0.34, 3), stone.lightened(0.02), Vector3(0, eave + h * 0.06 + w * 0.12, end * d * 0.52), Vector3(0, PI * 0.5 * 0.0, 0))
		gable.scale = Vector3(1.0, 1.0, 0.08)
	LowPoly.piece(root, LowPoly.box(Vector3(w * 0.5, h * 0.02, d * 0.02)), dark, Vector3(0, eave - h * 0.04, -d * 0.51)) # a name lintel
	var top := eave + h * 0.06 + w * 0.36
	if rng.randf() < 0.5: # an urn
		LowPoly.piece(root, LowPoly.cylinder(w * 0.05, w * 0.09, h * 0.08, 8), stone, Vector3(0, top + h * 0.04, 0))
		LowPoly.piece(root, LowPoly.sphere(w * 0.09, 8, 4), stone, Vector3(0, top + h * 0.11, 0))
	else: # a cross
		LowPoly.piece(root, LowPoly.box(Vector3(w * 0.05, h * 0.2, w * 0.05)), stone, Vector3(0, top + h * 0.1, 0))
		LowPoly.piece(root, LowPoly.box(Vector3(w * 0.14, w * 0.05, w * 0.05)), stone, Vector3(0, top + h * 0.15, 0))
	for k in 4: # ivy creeping up the corners
		var c := Vector3((-1.0 if k % 2 == 0 else 1.0) * w * 0.5, h * 0.25, (-1.0 if k < 2 else 1.0) * d * 0.5)
		var ivy := LowPoly.piece(root, LowPoly.sphere(w * 0.16, 6, 3), Color(0.24, 0.32, 0.24), c)
		ivy.scale = Vector3(0.7, 2.2, 0.7)


## A run of wrought-iron fence along x, `size.x` long and `size.y` high: two rails between stone-capped
## posts at its ends, spiked pickets every 0.14 m, a few bent or missing.
static func _fence(root: Node3D, size: Vector2, iron: Color, rng: RandomNumberGenerator) -> void:
	var l := size.x
	var h := size.y
	for side in [-0.5, 0.5]: # the posts
		LowPoly.piece(root, LowPoly.box(Vector3(0.22, h * 1.15, 0.22)), Color(0.42, 0.42, 0.44), Vector3(side * l, h * 0.575, 0))
		LowPoly.piece(root, LowPoly.box(Vector3(0.28, 0.08, 0.28)), Color(0.5, 0.5, 0.52), Vector3(side * l, h * 1.19, 0))
	for y in [0.22, 0.82]: # the rails
		LowPoly.piece(root, LowPoly.box(Vector3(l, 0.035, 0.035)), iron, Vector3(0, h * y, 0))
	var count := int(l / 0.14)
	for k in range(1, count):
		if rng.randf() < 0.06:
			continue # one gone
		var x := -l * 0.5 + k * l / count
		var bend := rng.randf_range(-0.25, 0.25) if rng.randf() < 0.1 else 0.0
		LowPoly.piece(root, LowPoly.box(Vector3(0.022, h * 0.95, 0.022)), iron, Vector3(x, h * 0.475, 0), Vector3(0, 0, bend))
		LowPoly.piece(root, LowPoly.cylinder(0.0, 0.03, 0.09, 4), iron, Vector3(x - sin(bend) * h * 0.95, h * 0.98, 0), Vector3(0, 0, bend)) # its spike


## A gnarled dead tree: a twisted trunk of short leaning segments, tapering, splitting into a few
## crooked bare branches that fork again into twigs; dark grey-brown.
static func _gnarled(root: Node3D, size: Vector2, r: float, bark: Color, rng: RandomNumberGenerator, sink: float) -> void:
	var h := size.x
	var at := Vector3(0, -sink, 0)
	var dir := Vector3.UP
	var segments := 6
	for k in segments:
		dir = (dir + Vector3(rng.randf_range(-0.35, 0.35), 0.0, rng.randf_range(-0.35, 0.35))).normalized()
		dir = (dir + Vector3.UP * 0.6).normalized() # (it still grows up)
		var length := (h + (sink if k == 0 else 0.0)) / segments
		var r0 := r * (1.0 - 0.11 * k)
		LowPoly.piece(root, LowPoly.cylinder(r0 * 0.88, r0, length * 1.1, 6), bark.darkened(0.03 * (k % 2)), at + dir * length * 0.5, _along(dir))
		if k == 1 or k == 3: # a knot
			LowPoly.piece(root, LowPoly.sphere(r0 * 0.55, 5, 3), bark.darkened(0.12), at + dir * length * 0.6 + Vector3(r0 * 0.7, 0, 0))
		at += dir * length
	for b in 4 + rng.randi_range(0, 2): # branches from the upper trunk and the crown
		var a := TAU * b / 5.0 + rng.randf_range(-0.4, 0.4)
		var from := at - dir * h * rng.randf_range(0.0, 0.35)
		var out := (Vector3(cos(a), rng.randf_range(0.2, 0.9), sin(a))).normalized()
		_crooked(root, from, out, size.y * rng.randf_range(0.55, 0.9), r * 0.4, bark, rng, 2)


## A crooked branch: a few bending segments, forking `depth` more times into thinner ones.
static func _crooked(root: Node3D, from: Vector3, dir: Vector3, length: float, r: float, bark: Color, rng: RandomNumberGenerator, depth: int) -> void:
	var at := from
	for k in 3:
		dir = (dir + Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.2, 0.35), rng.randf_range(-0.4, 0.4))).normalized()
		var step := length / 3.0
		LowPoly.piece(root, LowPoly.cylinder(r * (0.75 - 0.2 * k) * 0.8, r * (0.75 - 0.2 * k), step * 1.1, 5), bark, at + dir * step * 0.5, _along(dir))
		at += dir * step
		if depth > 0 and k == 1:
			_crooked(root, at, (dir + Vector3(rng.randf_range(-1, 1), 0.3, rng.randf_range(-1, 1))).normalized(), length * 0.55, r * 0.55, bark, rng, depth - 1)


## A pumpkin: a squat ribbed orange gourd with a twisted stem; a jack-o'-lantern (`carved`) has a
## glowing face cut in it (eyes, nose, a toothy grin: its pieces flagged to glow, see material_for()).
static func _pumpkin(root: Node3D, r: float, skin: Color, rng: RandomNumberGenerator, carved: bool) -> void:
	var body := _ribbed(root, LowPoly.sphere(r, 12, 6), skin, skin.darkened(0.16), 12, Vector3(0, r * 0.78, 0), Vector3(0, rng.randf() * TAU, 0))
	body.scale = Vector3(1.0, 0.78, 1.0)
	LowPoly.piece(root, LowPoly.cylinder(r * 0.06, r * 0.11, r * 0.35, 5), Color(0.32, 0.38, 0.18), Vector3(r * 0.03, r * 1.5, 0), Vector3(0.25, 0, 0.2))
	if not carved:
		return
	var glow := Color(1.0, 0.62, 0.18)
	var face := -r * 0.97 # the front (−Z)
	for side in [-1.0, 1.0]: # eyes
		var eye := LowPoly.piece(root, LowPoly.prism(3, r * 0.26, r * 0.26, r * 0.06), glow, Vector3(side * r * 0.32, r * 0.95, face), Vector3(PI * 0.5, 0, 0))
		_glowing(eye, 0.95)
	var nose := LowPoly.piece(root, LowPoly.prism(3, r * 0.15, r * 0.15, r * 0.06), glow, Vector3(0, r * 0.72, face), Vector3(PI * 0.5, 0, 0))
	_glowing(nose, 0.95)
	for k in 5: # the grin, teeth between
		var mouth := LowPoly.piece(root, LowPoly.box(Vector3(r * 0.15, r * (0.1 if k % 2 == 0 else 0.16), r * 0.05)), glow,
			Vector3((k - 2) * r * 0.16, r * (0.5 + 0.03 * absf(k - 2)), face * (1.0 - 0.06 * absf(k - 2))))
		_glowing(mouth, 0.95)
