class_name TeeProps
extends Node3D
## Set dressing at a generated hole's tee (visual only, clients; no colliders): a low-poly golf
## cart parked beside the tee, its body tinted by the biome, and 2–3 caddies (the golfer rig in
## their own colours) standing near it facing the tee, idling with a slight sway and an occasional
## look round. Out to one side of the tee past where the players' tee slots spread; the side, spots
## and colours from the hole seed.

const CHARACTER: CharacterParams = preload("res://data/character.tres")
const LOOK: CharacterLook = preload("res://data/characters/default_look.tres")
const CART_OUT := Vector2(12.0, 15.0) ## m sideways from the tee centre (players stand within ±7 m)
const CADDY_OUT := Vector2(9.0, 11.0)
const CADDY_GAP := 1.5 ## m at least between caddies, and from the cart's body
const CART_HALF := Vector2(0.7, 1.25) ## m, the cart's footprint half-size (across, along)
const CADDY_TRIES := 12 ## spots tried per caddy (seeded draws, so the same ones every time)
const SHIRTS := [Color(0.85, 0.85, 0.82), Color(0.36, 0.5, 0.64), Color(0.74, 0.62, 0.36), Color(0.46, 0.58, 0.42), Color(0.62, 0.38, 0.4)]
const PANTS := [Color(0.3, 0.32, 0.36), Color(0.68, 0.62, 0.5), Color(0.22, 0.26, 0.3)]

var _caddies: Array[GolferRig] = []
var _phase := PackedFloat32Array()
var _look_at := PackedFloat32Array() # s until each next looks round
var _look_to := PackedFloat32Array() # the head yaw each is easing to
var _look_now := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _t := 0.0


func _init(hole: GeneratedHole) -> void:
	var d := hole.data
	_rng.seed = Procgen.mix(d.seed ^ 0x636172)
	var tee := hole.tee.position
	var axis := ((hole.cup.position - tee) * Vector3(1, 0, 1)).normalized()
	var right := axis.cross(Vector3.UP)
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	var water := hole.params.water
	if hole.surface_at(tee + right * side * CART_OUT.y) == water:
		side = -side # the other side, if this one is wet
	var cart_at := tee + right * side * _rng.randf_range(CART_OUT.x, CART_OUT.y) - axis * _rng.randf_range(1.0, 4.0)
	if hole.surface_at(cart_at) == water:
		return
	cart_at.y = hole.height_at(cart_at)
	var cart := _cart(d.biome)
	cart.position = cart_at
	cart.basis = Basis.looking_at(axis, Vector3.UP).rotated(Vector3.UP, _rng.randf_range(-0.15, 0.15))
	add_child(cart)
	var stood: Array[Vector3] = []
	for k in _rng.randi_range(2, 3):
		var at := Vector3.INF
		for attempt in CADDY_TRIES: # clear of the others and of the cart by CADDY_GAP
			var spot := tee + right * side * _rng.randf_range(CADDY_OUT.x, CADDY_OUT.y) + axis * (_rng.randf_range(-3.0, 3.0) - 1.0)
			if hole.surface_at(spot) != water and caddy_clear(spot, stood, cart):
				at = spot
				break
		if at == Vector3.INF:
			continue
		stood.append(at)
		at.y = hole.height_at(at)
		var look: CharacterLook = LOOK.duplicate()
		look.shirt = SHIRTS[_rng.randi_range(0, SHIRTS.size() - 1)]
		look.outerwear = look.shirt.darkened(0.15)
		look.pants = PANTS[_rng.randi_range(0, PANTS.size() - 1)]
		look.hat = SHIRTS[_rng.randi_range(0, SHIRTS.size() - 1)].lightened(0.1)
		var rig := GolferRig.new(CHARACTER, look)
		add_child(rig)
		rig.position = at
		var face := tee + axis * 4.0 - at # toward the tee
		rig.rotation.y = atan2(face.x, face.z) + PI + _rng.randf_range(-0.4, 0.4) # (the rig faces −Z)
		rig.pose_idle()
		_caddies.append(rig)
		_phase.append(_rng.randf() * TAU)
		_look_at.append(_rng.randf_range(1.0, 6.0))
		_look_to.append(0.0)
		_look_now.append(0.0)


## True if a caddy may stand at `spot`: CADDY_GAP from every caddy already placed and from the cart's
## footprint (its body as a box, on the ground plane).
static func caddy_clear(spot: Vector3, others: Array[Vector3], cart: Node3D) -> bool:
	for o in others:
		if Vector2(spot.x - o.x, spot.z - o.z).length() < CADDY_GAP:
			return false
	var local := cart.transform.affine_inverse() * spot
	var out := Vector2(maxf(absf(local.x) - CART_HALF.x, 0.0), maxf(absf(local.z) - CART_HALF.y, 0.0))
	return out.length() >= CADDY_GAP


## Idle: a slow sway each; now and then one turns its head somewhere, holds, and turns back.
func _process(delta: float) -> void:
	_t += delta
	for k in _caddies.size():
		_look_at[k] -= delta
		if _look_at[k] <= 0.0:
			_look_to[k] = 0.0 if absf(_look_to[k]) > 0.01 else _rng.randf_range(-0.9, 0.9)
			_look_at[k] = _rng.randf_range(2.0, 6.0)
		_look_now[k] = lerpf(_look_now[k], _look_to[k], 1.0 - exp(-2.5 * delta))
		_caddies[k].pose_idle_look(_look_now[k], sin(_t * 0.8 + _phase[k]) * 0.035)


## A two-seat golf cart along −Z: body and hood in the biome-tinted colour, a roof on four posts,
## dark seats, wheels and bumpers. One mesh.
static func _cart(biome: Biome) -> Node3D:
	var root := Node3D.new()
	var body := biome.card_color.lerp(Color(0.92, 0.92, 0.88), 0.55)
	var dark := Color(0.17, 0.17, 0.18)
	var seat := Color(0.3, 0.27, 0.25)
	LowPoly.piece(root, LowPoly.rounded_prism(4, Vector3(1.25, 0.45, 2.3), 0.12, 1), body, Vector3(0, 0.55, 0))
	LowPoly.piece(root, LowPoly.rounded_prism(4, Vector3(1.2, 0.35, 0.7), 0.1, 1), body.lightened(0.06), Vector3(0, 0.9, -0.85))
	LowPoly.piece(root, LowPoly.box(Vector3(1.1, 0.18, 0.75)), seat, Vector3(0, 0.88, 0.25))
	LowPoly.piece(root, LowPoly.box(Vector3(1.1, 0.6, 0.12)), seat, Vector3(0, 1.15, 0.62))
	LowPoly.piece(root, LowPoly.box(Vector3(0.6, 0.5, 0.45)), dark, Vector3(0, 1.0, 1.05)) # the bag well
	for corner in [Vector2(-0.55, -0.55), Vector2(0.55, -0.55), Vector2(-0.55, 0.75), Vector2(0.55, 0.75)]:
		LowPoly.piece(root, LowPoly.cylinder(0.03, 0.03, 1.15, 5), dark, Vector3(corner.x, 1.5, corner.y))
	LowPoly.piece(root, LowPoly.rounded_prism(4, Vector3(1.35, 0.07, 1.75), 0.03, 1), body.lightened(0.1), Vector3(0, 2.08, 0.1))
	for wheel in [Vector2(-0.6, -0.8), Vector2(0.6, -0.8), Vector2(-0.6, 0.8), Vector2(0.6, 0.8)]:
		LowPoly.piece(root, LowPoly.cylinder(0.27, 0.27, 0.2, 10), dark, Vector3(wheel.x, 0.27, wheel.y), Vector3(0, 0, PI * 0.5))
	for end in [-1.2, 1.2]:
		LowPoly.piece(root, LowPoly.box(Vector3(1.25, 0.1, 0.08)), dark, Vector3(0, 0.38, end))
	Flora._merge(root)
	return root
