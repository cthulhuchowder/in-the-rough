class_name BiomeLife
extends Node3D
## A biome's small life at a generated hole (visual only, clients): bubbles rising now and then out of
## its water (Biome.water_bubbles spots: the cemetery's bog), and crows (Biome.crows) perched on
## gravestones near the line of play, pecking and looking round, that caw and fly off when a ball
## lands or rolls near (any node in the "balls" group: the player's own and everyone else's). Spots
## from the hole seed.

const FLEE_RANGE := 7.0 ## m: a ball this close (and low) sets a crow off
const FLEE_TIME := 4.0 ## s it flies before it's gone

var _crows := [] # [node, wings: Array[Node3D], state 0 perched / 1 flying, t, away, next peck]
var _caw: AudioStreamWAV
var _t := 0.0


func _init(hole: GeneratedHole) -> void:
	var d := hole.data
	var b: Biome = d.biome
	var n := d.size
	var m := d.metres_per_px
	if b.water_bubbles > 0: # bog bubbles: spots on the water, picked by a hash scan of the grid
		var placed := 0
		var water_y := d.water / 100.0
		for k in n * n:
			if placed >= b.water_bubbles:
				break
			var i := Procgen.mix(d.seed ^ (k * 2654435761)) % (n * n)
			if d.heights[i] / 100.0 < water_y - 0.3:
				add_child(_bubbles(Vector3((i % n) * m, water_y, (i / n) * m), Procgen.mix(i)))
				placed += 1
	if b.crows > 0:
		_caw = PlaceholderSounds.caw()
		var perches := []
		for k in d.props.size() / 4:
			var kind: PropKind = b.props[d.props[4 * k + 2]]
			if kind.shape == PropKind.Shape.GRAVESTONE:
				var at := Vector3(d.props[4 * k] / 100.0, 0.0, d.props[4 * k + 1] / 100.0)
				if Procgen._in_corridor(d, hole.params, Vector2(at.x, at.z), 30.0): # near the line of play
					perches.append([at, kind.sizes[d.props[4 * k + 3]].x])
		for c in mini(b.crows, perches.size()):
			var pick: Array = perches[Procgen.mix(d.seed ^ (c * 7919 + 13)) % perches.size()]
			var at: Vector3 = pick[0]
			at.y = hole.height_at(at) + float(pick[1]) * 0.9 # on top of the stone
			_crows.append(_crow(at, float(Procgen.mix(c) % 628) / 100.0))


func _process(delta: float) -> void:
	_t += delta
	var balls := get_tree().get_nodes_in_group("balls")
	for c in _crows:
		var node: Node3D = c[0]
		if not node.visible:
			continue
		var wings: Array = c[1]
		if c[2] == 0: # perched: a peck or a look round now and then; a ball near: away
			if _t > c[5]:
				c[5] = _t + 1.5 + fmod(_t * 7.31, 2.5)
				node.rotation.y += 0.9 * (1.0 if fmod(_t, 2.0) < 1.0 else -1.0)
			var head: Node3D = node.get_node("Head")
			var peck := clampf(_t - (c[5] - 0.5), 0.0, 0.3)
			head.rotation.x = sin(peck / 0.3 * PI) * 0.6
			for ball in balls:
				var p: Vector3 = (ball as Node3D).global_position
				var off := Vector2(p.x - node.global_position.x, p.z - node.global_position.z)
				if (ball as Node3D).is_visible_in_tree() and off.length() < FLEE_RANGE and p.y < node.global_position.y + 2.5:
					c[2] = 1
					c[3] = 0.0
					c[4] = Vector3(-off.x, 0.0, -off.y).normalized() if off.length() > 0.01 else Vector3.FORWARD
					node.rotation.y = atan2(-c[4].x, -c[4].z) # (its beak, −Z, the way it flies: away from the ball)
					var sound := AudioStreamPlayer3D.new()
					sound.bus = &"SFX"
					sound.stream = _caw
					node.add_child(sound)
					sound.play()
					break
		else: # flying off: wings beating, climbing away, then gone
			c[3] += delta
			var away: Vector3 = c[4]
			node.global_position += (away * 6.0 + Vector3.UP * (3.5 - c[3] * 0.4)) * delta
			var beat := sin(c[3] * 28.0) * 0.9
			wings[0].rotation.z = beat
			wings[1].rotation.z = -beat
			if c[3] > FLEE_TIME:
				node.visible = false


## A crow: a black faceted body, head with a grey beak, a wedge tail and two wings on pivots.
func _crow(at: Vector3, yaw: float) -> Array:
	var bird := Node3D.new()
	bird.position = at
	bird.rotation.y = yaw
	add_child(bird)
	var black := Color(0.08, 0.08, 0.1)
	var body := LowPoly.part(bird, LowPoly.sphere(0.12, 7, 4), black, Vector3(0, 0.12, 0))
	body.scale = Vector3(0.8, 0.75, 1.35)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.22, -0.14)
	bird.add_child(head)
	LowPoly.part(head, LowPoly.sphere(0.07, 6, 3), black, Vector3.ZERO)
	LowPoly.part(head, LowPoly.cylinder(0.0, 0.025, 0.08, 4), Color(0.3, 0.3, 0.32), Vector3(0, -0.01, -0.09), Vector3(-PI * 0.5, 0, 0))
	LowPoly.part(bird, LowPoly.prism(3, 0.12, 0.02, 0.14), black, Vector3(0, 0.13, 0.2), Vector3(-0.3, 0, 0)) # the tail
	var wings: Array[Node3D] = []
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(side * 0.08, 0.16, 0)
		bird.add_child(pivot)
		var wing := LowPoly.part(pivot, LowPoly.box(Vector3(0.24, 0.015, 0.16)), black, Vector3(side * 0.12, 0, 0.02))
		wing.rotation.z = side * -0.15
		wings.append(pivot)
	for view in bird.find_children("*", "MeshInstance3D", true, false):
		(view as MeshInstance3D).material_override = LowPoly.shared_material()
	return [bird, wings, 0, 0.0, Vector3.ZERO, 1.0 + fmod(yaw * 3.7, 3.0)]


## Bubbles out of the bog at `at`: one now and then, swelling as it rises a little, then popping.
func _bubbles(at: Vector3, h: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = at
	p.amount = 3
	p.lifetime = 1.4
	p.randomness = 1.0
	p.explosiveness = 0.0
	p.speed_scale = 0.35 + float(h % 100) / 400.0 # (each spot in its own time)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.8
	p.direction = Vector3.UP
	p.spread = 5.0
	p.initial_velocity_min = 0.02
	p.initial_velocity_max = 0.06
	p.gravity = Vector3.ZERO
	var dome := SphereMesh.new()
	dome.radius = 0.09
	dome.height = 0.12
	dome.is_hemisphere = true
	dome.radial_segments = 8
	dome.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.26, 0.14)
	mat.roughness = 0.15
	mat.metallic_specular = 0.9
	dome.material = mat
	p.mesh = dome
	var grow := Curve.new() # swells, then pops
	grow.add_point(Vector2(0.0, 0.2))
	grow.add_point(Vector2(0.85, 1.0))
	grow.add_point(Vector2(0.9, 0.0))
	p.scale_amount_curve = grow
	return p
