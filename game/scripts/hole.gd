class_name Hole
extends Node3D
## A hole: lie and height lookup, tee, cup and the drop rule. This base is hand-placed:
## flat ground at y = 0 and surface regions under $Surfaces (later children win).
## GeneratedHole overrides the lookups with procgen data.

const FEEL: SwingFeel = preload("res://data/swing_feel.tres")
const POLE_HEIGHT := 2.5
const CUP_COLOR := Color("#ECE8DF") # off-white liner
const CUP_BOTTOM_COLOR := Color("#D9D4C8") # its bottom, a shade deeper (soft shading in the cup)
const POLE_COLOR := Color("#E2E2DE")
const FLAG_COLOR := Color("#C2614E")
const CUP_RIM_SIDES := 48 ## rim loop of the ground collider (and its lip); liner wall boxes
const CUP_LIP_STEPS := 4 ## down its quarter-round profile

@export var par: int
@export var out_of_bounds: SurfaceData ## lie outside every region
@export var wind := Vector3.ZERO ## m/s, horizontal, the way it blows (generated holes: from the seed)

## Drops walk toward this polyline (world). Defaults to tee → cup.
var centreline := PackedVector3Array()
## The ground's collider. It has a real hole at the cup: only the liner's wall and bottom collide there.
var ground: CollisionObject3D

@onready var tee: Marker3D = $Tee
@onready var cup: Marker3D = $Cup
var _regions: Array[Node] = []
var _pin: Node3D
var _pin_y := 0.0 # how far the pin is lifted out
var _hop_t := -1.0 # s into the hole-in hop; −1 when still
var _hop: CelebrationParams


func _ready() -> void:
	if has_node("Surfaces"):
		_regions = $Surfaces.get_children()
	if centreline.is_empty():
		centreline = PackedVector3Array([tee.global_position, cup.global_position])
	ground = get_node_or_null("Ground")
	_cut_flat_ground()
	_build_cup()


## Hand-placed holes stand on one flat box: swap it for a flat sheet over its top with the cup cut out.
func _cut_flat_ground() -> void:
	var holder := get_node_or_null("Ground/Shape") as CollisionShape3D
	if holder == null or not holder.shape is BoxShape3D:
		return
	var half := (holder.shape as BoxShape3D).size * 0.5
	var y := (holder.global_transform * Vector3(0, half.y, 0)).y
	var centre := holder.global_transform.origin
	var c := cup.global_position
	# A 3×3 grid of rectangles over the top, the middle one a 4 m square round the cup that becomes
	# the ring in to the rim: no long thin triangles near the cup (their inner edges kick a fast ball).
	var xs := [centre.x - half.x, c.x - 2.0, c.x + 2.0, centre.x + half.x]
	var zs := [centre.z - half.z, c.z - 2.0, c.z + 2.0, centre.z + half.z]
	var faces := PackedVector3Array()
	for i in 3:
		for j in 3:
			if i == 1 and j == 1:
				continue
			var a := Vector3(xs[i], y, zs[j])
			var b := Vector3(xs[i + 1], y, zs[j])
			var d := Vector3(xs[i], y, zs[j + 1])
			var e := Vector3(xs[i + 1], y, zs[j + 1])
			faces.append_array([a, b, d, b, e, d])
	faces.append_array(cup_ring_faces(PackedVector3Array([Vector3(xs[1], y, zs[1]), Vector3(xs[2], y, zs[1]),
		Vector3(xs[2], y, zs[2]), Vector3(xs[1], y, zs[2])]), func(_p: Vector3) -> float: return y))
	var sheet := ConcavePolygonShape3D.new()
	sheet.backface_collision = true
	sheet.set_faces(faces)
	holder.shape = sheet
	holder.global_transform = Transform3D.IDENTITY


## Ground triangles (world) from a loop of points round the cup (star-shaped about it, either
## direction) in to the rim circle, whose heights come from `height`, then the lip down into the cup.
func cup_ring_faces(outer: PackedVector3Array, height: Callable) -> PackedVector3Array:
	var c := cup.global_position
	var angle := func(p: Vector3) -> float: return atan2(p.z - c.z, p.x - c.x)
	# Outer angles unwrapped to run one way round; the rim circle follows from the same start.
	var outer_a := PackedFloat64Array([angle.call(outer[0])])
	for i in range(1, outer.size()):
		outer_a.append(outer_a[i - 1] + wrapf(angle.call(outer[i]) - angle.call(outer[i - 1]), -PI, PI))
	var turn := signf(outer_a[outer_a.size() - 1] - outer_a[0])
	outer = outer.duplicate()
	outer.append(outer[0])
	outer_a.append(outer_a[0] + turn * TAU)
	var rim := PackedVector3Array()
	var rim_a := PackedFloat64Array()
	for k in CUP_RIM_SIDES + 1:
		var a: float = outer_a[0] + turn * TAU * k / CUP_RIM_SIDES
		var p := c + Vector3(cos(a), 0.0, sin(a)) * (FEEL.cup_radius + FEEL.cup_lip_radius) # the lip rounds the last bit down to the opening
		p.y = height.call(p)
		rim.append(p)
		rim_a.append(a)
	var lip := _lip_faces(rim, c)
	# Zip the two loops together by angle.
	var faces := PackedVector3Array()
	var i := 0
	var j := 0
	while i < outer.size() - 1 or j < rim.size() - 1:
		var next_outer := absf(outer_a[i + 1] - outer_a[0]) if i < outer.size() - 1 else INF
		var next_rim := absf(rim_a[j + 1] - rim_a[0]) if j < rim.size() - 1 else INF
		if next_outer <= next_rim:
			faces.append_array([outer[i], rim[j], outer[i + 1]])
			i += 1
		else:
			faces.append_array([outer[i], rim[j], rim[j + 1]])
			j += 1
	faces.append_array(lip)
	return faces


## The lip, in the same mesh as the ground so there is no edge between them for a ball to catch:
## a quarter-round of radius cup_lip_radius r from each point of the ground's rim loop (tangent to
## the ground there, cup_radius + r out) curving down to vertical at cup_radius, r lower, where the
## liner's wall goes on down.
func _lip_faces(rim: PackedVector3Array, c: Vector3) -> PackedVector3Array:
	var r := FEEL.cup_lip_radius
	var rings := []
	for j in CUP_LIP_STEPS + 1:
		var t := PI * 0.5 * j / CUP_LIP_STEPS
		var ring := PackedVector3Array()
		for p in rim:
			var out := Vector3(p.x - c.x, 0.0, p.z - c.z).normalized()
			ring.append(Vector3(c.x, p.y, c.z) + out * (FEEL.cup_radius + r - r * sin(t)) + Vector3.UP * (r * cos(t) - r))
		rings.append(ring)
	var faces := PackedVector3Array()
	for j in CUP_LIP_STEPS:
		for k in rim.size() - 1:
			faces.append_array([rings[j][k], rings[j][k + 1], rings[j + 1][k], rings[j][k + 1], rings[j + 1][k + 1], rings[j + 1][k]])
	return faces


## Liner and bottom (the terrain shader cuts the opening above them), pin and flag. The liner's
## wall (a ring of thin boxes just outside cup_radius, up to where the ground's lip turns vertical)
## and bottom, with the lip, are the cup's only colliders.
func _build_cup() -> void:
	var body := StaticBody3D.new()
	body.name = "Liner"
	body.set_meta("cup", true) # the ball leaves contacts with the cup to the physics engine
	var slick := PhysicsMaterial.new() # a ball that drops in fast runs round the wall as it falls
	slick.friction = FEEL.cup_lip_friction
	body.physics_material_override = slick
	cup.add_child(body)
	var wall_top := -FEEL.cup_lip_radius # the lip tube's centre height: it rounds over the wall's top
	var bottom := CollisionShape3D.new()
	var disc := CylinderShape3D.new()
	disc.radius = FEEL.cup_radius + 0.03
	disc.height = 0.05
	bottom.shape = disc
	bottom.position.y = -FEEL.cup_depth - disc.height * 0.5
	body.add_child(bottom)
	for k in CUP_RIM_SIDES:
		var wall := CollisionShape3D.new()
		var slab := BoxShape3D.new()
		slab.size = Vector3(2.0 * (FEEL.cup_radius + 0.03) * tan(PI / CUP_RIM_SIDES) + 0.01, FEEL.cup_depth + wall_top, 0.05)
		wall.shape = slab
		var a := TAU * k / CUP_RIM_SIDES
		wall.basis = Basis(Vector3.UP, -a + PI * 0.5) # face the centre
		wall.position = Vector3(cos(a), 0.0, sin(a)) * (FEEL.cup_radius + 0.025) + Vector3.UP * (wall_top - FEEL.cup_depth) * 0.5
		body.add_child(wall)
	var liner := LowPoly.cylinder(FEEL.cup_radius, FEEL.cup_radius, FEEL.cup_depth, 16)
	liner.cap_top = false
	liner.cap_bottom = false
	var view := LowPoly.part(cup, liner, CUP_COLOR, Vector3(0, -FEEL.cup_depth * 0.5, 0))
	(view.material_override as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED # seen from inside
	var floor_disc: CylinderMesh = LowPoly.cylinder(FEEL.cup_radius, FEEL.cup_radius, 0.002, 16)
	LowPoly.part(cup, floor_disc, CUP_BOTTOM_COLOR, Vector3(0, -FEEL.cup_depth + 0.001, 0))
	_pin = Node3D.new()
	cup.add_child(_pin)
	LowPoly.part(_pin, LowPoly.cylinder(0.015, 0.015, POLE_HEIGHT, 6), POLE_COLOR, Vector3(0, POLE_HEIGHT * 0.5 - FEEL.cup_depth, 0))
	var flag := PrismMesh.new()
	flag.size = Vector3(0.36, 0.5, 0.01) # base along the pole, point out
	LowPoly.part(_pin, flag, FLAG_COLOR, Vector3(0.25, POLE_HEIGHT - FEEL.cup_depth - 0.2, 0), Vector3(0, 0, -PI * 0.5))


## The pin lifts out of the cup while `ball` is within flag_lift_distance, and drops back after.
## `keep_in`: the ball is holed, so the pin goes back in (and stays) whatever the distance.
func lift_flag(ball: Vector3, delta: float, keep_in := false) -> void:
	var near := Vector2(ball.x - cup.global_position.x, ball.z - cup.global_position.z).length() < FEEL.flag_lift_distance
	_pin_y = move_toward(_pin_y, POLE_HEIGHT if near and not keep_in else 0.0, FEEL.flag_lift_speed * delta)
	var hop := 0.0
	if _hop_t >= 0.0: # a few damped hops after a hole-in
		_hop_t += delta
		var k := _hop_t / _hop.flag_time
		hop = _hop.flag_hop * absf(sin(PI * _hop.flag_hops * k)) * (1.0 - k) if k < 1.0 else 0.0
		if k >= 1.0:
			_hop_t = -1.0
	_pin.position.y = _pin_y + hop
	_pin.visible = _pin_y < POLE_HEIGHT


## The flagstick hops for a hole-in (Main's celebration), per `p`.
func bounce_flag(p: CelebrationParams) -> void:
	_hop = p
	_hop_t = 0.0


func surface_at(p: Vector3) -> SurfaceData:
	for i in range(_regions.size() - 1, -1, -1):
		if _regions[i].contains(p):
			return _regions[i].surface
	return out_of_bounds


func height_at(_p: Vector3) -> float:
	return 0.0


## Where a ball is put back after a penalty: `p` if the golfer can stand there — no solid prop
## (trunk, rock, log) within `clearance` of it, ground to head height (which covers the stance), on a
## dry, in-bounds lie — else the nearest such spot on rings of 1 m steps out to 12 m (fixed order, so
## server and clients agree), else `p`. Returns a rest point `lift` above the ground.
func clear_spot(p: Vector3, clearance: float, lift: float) -> Vector3:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	for ring in 13:
		var tries := 1 if ring == 0 else 12
		for k in tries:
			var a := TAU * k / tries
			var at := rest_point(p + Vector3(cos(a), 0.0, sin(a)) * float(ring), lift)
			var lie := surface_at(at)
			if lie.hazard != SurfaceData.Hazard.NONE:
				continue
			if space and _blocked(space, at, clearance):
				continue
			return at
	return rest_point(p, lift)


func _blocked(space: PhysicsDirectSpaceState3D, at: Vector3, clearance: float) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var column := CylinderShape3D.new() # the golfer's space: `clearance` round, from just off the ground to head height
	column.radius = clearance
	column.height = 2.0
	query.shape = column
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * 1.1) # (its foot 0.1 m up, clear of the ground itself)
	for hit in space.intersect_shape(query, 16):
		if hit.collider and (hit.collider as Object).has_meta("surface"): # Flora's solid things
			return true
	return false


func rest_point(p: Vector3, lift: float) -> Vector3:
	return Vector3(p.x, height_at(p) + lift, p.z)


## Step toward the centreline until the lie is playable, then push further along.
func drop_point(p: Vector3, rules: RulesData) -> Vector3:
	var flat := Vector3(p.x, 0.0, p.z)
	var line := flat
	var best := INF
	for k in centreline.size() - 1:
		var a := Vector3(centreline[k].x, 0.0, centreline[k].z)
		var b := Vector3(centreline[k + 1].x, 0.0, centreline[k + 1].z)
		var c := Geometry3D.get_closest_point_to_segment(flat, a, b)
		if c.distance_to(flat) < best:
			best = c.distance_to(flat)
			line = c
	var q := flat
	while surface_at(rest_point(q, rules.drop_height)).hazard != SurfaceData.Hazard.NONE and q.distance_to(line) > rules.drop_step:
		q = q.move_toward(line, rules.drop_step)
	return rest_point(q.move_toward(line, rules.drop_push), rules.drop_height)
