class_name MenuScene
extends Node3D
## The main menu's live backdrop. A different biome each launch (its sky, fog, sun and ground
## colours, a scatter of its trees and props round the green). In the middle, the title — IN THE
## ROUGH — in chunky low-poly block letters standing on a grassy mound, a grass tuft growing from
## the R and a golf ball for the dot of the I, bouncing in when the menu opens. On the right the
## player's golfer (their look) waving beside the hole's flag, the cart and a caddy leaning on it
## just behind; the menu's buttons are a column on the left. The camera drifts slowly to and fro on
## a shallow arc. Not built headless.

const PARAMS: MenuSceneParams = preload("res://data/menu_scene.tres")
const CHARACTER: CharacterParams = preload("res://data/character.tres")
const CELEBRATION: CelebrationParams = preload("res://data/celebration.tres")
const PROCGEN: ProcgenParams = preload("res://data/procgen.tres")
const TITLE := ["IN THE", "ROUGH"] ## the title's two lines
## Block letters on a 2 × 4 grid (x 0..2, y 0..4), each a list of strokes [from, to].
const GLYPHS := {
	"I": [[Vector2(1, 0), Vector2(1, 3.1)]],
	"N": [[Vector2(0, 0), Vector2(0, 4)], [Vector2(2, 0), Vector2(2, 4)], [Vector2(0, 4), Vector2(2, 0)]],
	"T": [[Vector2(0, 4), Vector2(2, 4)], [Vector2(1, 0), Vector2(1, 4)]],
	"H": [[Vector2(0, 0), Vector2(0, 4)], [Vector2(2, 0), Vector2(2, 4)], [Vector2(0, 2), Vector2(2, 2)]],
	"E": [[Vector2(0, 0), Vector2(0, 4)], [Vector2(0, 4), Vector2(2, 4)], [Vector2(0, 2), Vector2(1.6, 2)], [Vector2(0, 0), Vector2(2, 0)]],
	"R": [[Vector2(0, 0), Vector2(0, 4)], [Vector2(0, 4), Vector2(1.5, 4)], [Vector2(1.5, 4), Vector2(2, 3.4)], [Vector2(2, 3.4), Vector2(2, 2.6)],
		[Vector2(2, 2.6), Vector2(1.5, 2)], [Vector2(1.5, 2), Vector2(0, 2)], [Vector2(1, 2), Vector2(2, 0)]],
	"O": [[Vector2(0, 0.5), Vector2(0, 3.5)], [Vector2(2, 0.5), Vector2(2, 3.5)], [Vector2(0.5, 0), Vector2(1.5, 0)], [Vector2(0.5, 4), Vector2(1.5, 4)],
		[Vector2(0, 0.5), Vector2(0.5, 0)], [Vector2(1.5, 0), Vector2(2, 0.5)], [Vector2(0, 3.5), Vector2(0.5, 4)], [Vector2(1.5, 4), Vector2(2, 3.5)]],
	"U": [[Vector2(0, 4), Vector2(0, 0.5)], [Vector2(2, 4), Vector2(2, 0.5)], [Vector2(0.5, 0), Vector2(1.5, 0)], [Vector2(0, 0.5), Vector2(0.5, 0)],
		[Vector2(1.5, 0), Vector2(2, 0.5)]],
	"G": [[Vector2(2, 3.5), Vector2(1.5, 4)], [Vector2(1.5, 4), Vector2(0.5, 4)], [Vector2(0.5, 4), Vector2(0, 3.5)], [Vector2(0, 3.5), Vector2(0, 0.5)],
		[Vector2(0, 0.5), Vector2(0.5, 0)], [Vector2(0.5, 0), Vector2(1.5, 0)], [Vector2(1.5, 0), Vector2(2, 0.5)], [Vector2(2, 0.5), Vector2(2, 2)],
		[Vector2(2, 2), Vector2(1.1, 2)]],
}

static var biome_override := -1 ## tests and captures: this biome's index instead of a random one

var biome: Biome ## the one this launch
var _rig: GolferRig
var _caddy: GolferRig
var _camera := Camera3D.new()
var _t := 0.0
var _centre := Vector3.ZERO # what the camera frames: the menu column is left of it
var _feet := Vector3.ZERO
var _forward := Vector3.FORWARD # from the camera's middle position toward the centre
var _yaw := 0.0 # where the golfer faces (eases toward the camera)
var _look := 0.0 # the caddy's head turn, easing to _look_to
var _look_to := 0.0
var _look_next := 3.0
var _letters: Array[Node3D] = [] # the title's pieces, each bouncing in (rest position in meta "rest")


func _ready() -> void:
	var p := PARAMS
	biome = PROCGEN.biomes[biome_override if biome_override >= 0 else randi() % PROCGEN.biomes.size()]
	var preset: Node = load("res://art/presets/overcast.tscn").instantiate()
	add_child(preset)
	var env := preset.get_node("Environment") as WorldEnvironment
	env.environment = env.environment.duplicate(true) # (the preset's is shared: light only ours)
	biome.light(env.environment, preset.get_node("Sun") as DirectionalLight3D)
	var hole: Hole = load("res://holes/test_hole.tscn").instantiate()
	add_child(hole)
	_tint(hole)
	var cup := hole.cup.global_position
	var right := _forward.cross(Vector3.UP).normalized()
	_centre = cup - right * p.flag_right # the flag right of the middle
	_feet = cup + right * p.golfer_right
	_rig = GolferRig.new(CHARACTER, ShopCatalog.my_look()) # the player's look, as equipped in the shop
	add_child(_rig)
	_rig.global_position = _feet
	# Behind the golfer on the right: the cart, a caddy leaning on its side
	var cart := TeeProps._cart(biome)
	add_child(cart)
	cart.global_position = cup + right * p.cart_left + _forward * 3.6
	cart.rotation.y = -0.7
	var look: CharacterLook = ShopCatalog.DEFAULT_LOOK.duplicate()
	look.shirt = Color(0.85, 0.85, 0.82)
	look.outerwear = Color(0.36, 0.5, 0.64)
	look.hat = Color(0.36, 0.5, 0.64)
	_caddy = GolferRig.new(CHARACTER, look)
	add_child(_caddy)
	_caddy.global_position = cart.global_position + right * 0.2 + _forward * 1.1 # (its near side, toward the camera)
	_caddy.rotation.y = PI * 0.95
	_scatter(cup)
	_build_title(_centre - right * p.title_left + _forward * p.title_back)
	_camera.fov = 60.0
	add_child(_camera)
	_camera.make_current()
	add_child(_confetti())


## The test hole's patches in the biome's ground colours.
func _tint(hole: Hole) -> void:
	var by_name := {"Rough": biome.rough_color, "Fairway": biome.fairway_color, "Green": biome.green_color, "Sand": biome.sand_color,
		"Water": biome.water_color, "Out of bounds": biome.oob_color}
	for region in hole.find_children("*", "SurfaceRegion", true, false):
		var surface: SurfaceData = (region as SurfaceRegion).surface
		if by_name.has(surface.resource_name) and (region as MeshInstance3D).mesh:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = by_name[surface.resource_name]
			(region as MeshInstance3D).mesh.surface_set_material(0, mat)
	var ground := hole.get_node_or_null("Ground/Mesh") as MeshInstance3D
	if ground:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = biome.oob_color.lerp(biome.rough_color, 0.5)
		ground.material_override = mat


## A few of the biome's trees and props round the back of the green (random each launch).
func _scatter(cup: Vector3) -> void:
	var trees := biome.trees.filter(func(k: PropKind) -> bool: return k.weight > 0.0)
	for k in 14:
		var a := randf_range(-PI * 0.95, -PI * 0.05) # behind the cup (the camera is at +Z)
		var at := cup + Vector3(cos(a), 0.0, sin(a)) * randf_range(16.0, 40.0)
		var kind: PropKind = trees[randi() % trees.size()] if k % 2 == 0 and not trees.is_empty() else biome.props[randi() % biome.props.size()]
		if kind.shape in [PropKind.Shape.TUMBLEWEED, PropKind.Shape.FENCE]:
			continue
		var thing := Flora.build(kind, kind.sizes[randi() % kind.sizes.size()], randi(), 0.0, null)
		thing.position = at
		add_child(thing)


## The title on its mound: each letter a merged mesh of chunky strokes, the I's dot a golf ball, a
## tuft of grass out of the R; each piece starts high and bounces down into place, one after another.
func _build_title(at: Vector3) -> void:
	var p := PARAMS
	var mound := LowPoly.part(self, LowPoly.sphere(1.0, 14, 6), biome.fairway_color.lerp(biome.green_color, 0.5), at)
	mound.scale = Vector3(p.mound_size.x, p.mound_size.y, p.mound_size.z)
	mound.material_override = LowPoly.shared_material()
	var face := Color(0.98, 0.96, 0.9)
	var rows := [[TITLE[0], p.letter_size * 0.7, at + Vector3(0, p.mound_size.y * 0.55 + p.letter_size * 4.0 * 1.25, -0.4)],
		[TITLE[1], p.letter_size, at + Vector3(0, p.mound_size.y * 0.75, 0.2)]]
	var order := 0
	for row in rows:
		var text: String = row[0]
		var unit: float = row[1]
		var width := 0.0
		for c in text:
			width += (2.0 if c != " " else 1.0) * unit + unit * 1.3
		var x := -width * 0.5
		for c in text:
			if c == " ":
				x += unit * 2.0
				continue
			var letter := Node3D.new()
			add_child(letter)
			letter.position = (row[2] as Vector3) + Vector3(x, 0, 0)
			letter.rotation.y = 0.0
			var view := MeshInstance3D.new()
			view.mesh = _glyph(c, unit, face, Color(0.42, 0.3, 0.2))
			view.material_override = LowPoly.shared_material()
			letter.add_child(view)
			if c == "I": # the dot: a golf ball
				LowPoly.part(letter, LowPoly.sphere(unit * 0.55, 10, 6), Color(0.97, 0.97, 0.95), Vector3(unit, unit * 4.0, 0)).material_override = LowPoly.shared_material()
			if c == "R": # a grass tuft growing out of its top
				for k in 7:
					var a := TAU * k / 7.0
					var blade := LowPoly.part(letter, LowPoly.cylinder(0.0, unit * 0.12, unit * 1.1, 3), Color(0.36, 0.62, 0.3).darkened(0.1 * (k % 2)),
						Vector3(unit * 0.7 + cos(a) * unit * 0.25, unit * 4.6, sin(a) * unit * 0.12), Vector3(sin(a) * 0.4, 0, cos(a) * 0.4))
					blade.material_override = LowPoly.shared_material()
			letter.set_meta("rest", letter.position)
			letter.set_meta("delay", order * p.title_stagger)
			letter.position += Vector3.UP * p.title_drop
			_letters.append(letter)
			order += 1
			x += unit * 3.3


## One letter: its strokes as chunky bevelled bars (`unit` a grid step), a lighter face, darker sides.
static func _glyph(c: String, unit: float, face: Color, side: Color) -> ArrayMesh:
	var root := Node3D.new()
	var thick := unit * 0.9
	var depth := unit * 1.1
	for stroke in GLYPHS[c]:
		var a: Vector2 = stroke[0] * unit
		var b: Vector2 = stroke[1] * unit
		var mid := (a + b) * 0.5
		var length := a.distance_to(b) + thick
		var angle := atan2(b.y - a.y, b.x - a.x) - PI * 0.5
		LowPoly.piece(root, LowPoly.rounded_prism(4, Vector3(thick, length, depth), thick * 0.18, 1), side, Vector3(mid.x, mid.y, 0), Vector3(0, 0, angle))
		LowPoly.piece(root, LowPoly.box(Vector3(thick * 0.82, length * 0.96, depth * 0.04)), face, Vector3(mid.x, mid.y, depth * 0.5), Vector3(0, 0, angle))
	var parts: Array[Node3D] = []
	for child in root.get_children():
		parts.append(child)
	var mesh := LowPoly.merge(parts)
	root.free()
	return mesh


func _process(delta: float) -> void:
	_t += delta
	var p := PARAMS
	for letter in _letters: # the bounce-in: a fall, then two smaller hops, settling
		var t: float = (_t - float(letter.get_meta("delay"))) / p.title_bounce_time
		var rest: Vector3 = letter.get_meta("rest")
		letter.position = rest + Vector3.UP * p.title_drop * (1.0 - _bounce(clampf(t, 0.0, 1.0))) if t < 1.0 else rest
	_rig.pose_wave(_t, p.wave_out, p.wave_height, p.wave_sway, p.wave_rate)
	# The caddy: leaning on the cart, swaying a little, now and then looking round
	_look_next -= delta
	if _look_next <= 0.0:
		_look_to = 0.0 if absf(_look_to) > 0.01 else randf_range(-0.8, 0.8)
		_look_next = randf_range(2.5, 6.0)
	_look = lerpf(_look, _look_to, 1.0 - exp(-2.0 * delta))
	_caddy.pose_idle_look(_look, sin(_t * 0.7) * 0.03)
	_caddy.rotation.z = p.caddy_lean # the weight on the cart (to his left, now it is on his right of frame)
	# The camera to and fro on its arc round the centre, easing in a little at each end, then turned
	# so the centre sits at centre_screen_x of the width (the button column has the left)
	var swing := sin(_t * p.orbit_speed) * deg_to_rad(p.arc_deg)
	var back := (-_forward).rotated(Vector3.UP, swing)
	var radius := p.orbit_radius - p.push_in * absf(sin(_t * p.orbit_speed))
	var eye := _centre + back * radius + Vector3.UP * p.orbit_height
	_camera.look_at_from_position(eye, _centre + Vector3.UP * p.look_height)
	var view := get_viewport().get_visible_rect().size
	var half := atan(tan(deg_to_rad(_camera.fov) * 0.5) * view.x / maxf(view.y, 1.0)) # half the horizontal view
	_camera.rotate_object_local(Vector3.UP, atan((2.0 * p.centre_screen_x - 1.0) * tan(half)))
	# The golfer turns (slowly) to wave at the camera
	var to_camera := (eye - _feet) * Vector3(1, 0, 1)
	_yaw = lerp_angle(_yaw, atan2(to_camera.x, to_camera.z), 1.0 - exp(-p.turn_rate * delta))
	_rig.rotation.y = _yaw + PI # (the rig faces −Z)


## Ease-out bounce 0..1: a fall to 1, then two hops of a quarter and a sixteenth back up.
static func _bounce(t: float) -> float:
	if t < 0.5:
		return (t / 0.5) * (t / 0.5)
	if t < 0.8:
		var u := (t - 0.65) / 0.15
		return 1.0 - 0.25 * (1.0 - u * u)
	var v := (t - 0.9) / 0.1
	return 1.0 - 0.0625 * (1.0 - v * v)


## Confetti drifting down slowly, always some in the air (the celebration's pieces and palette).
func _confetti() -> CPUParticles3D:
	var p := PARAMS
	var c := CELEBRATION
	var bits := CPUParticles3D.new()
	bits.mesh = Confetti._chip(c.piece_size)
	bits.amount = p.confetti_amount
	bits.lifetime = p.confetti_lifetime
	bits.preprocess = p.confetti_lifetime # already in the air when the menu opens
	bits.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	bits.emission_box_extents = p.confetti_box * 0.5
	bits.position = _centre + Vector3.UP * 4.5
	bits.direction = Vector3.DOWN
	bits.spread = 30.0
	bits.initial_velocity_min = 0.05
	bits.initial_velocity_max = 0.3
	bits.gravity = Vector3(0.0, -p.confetti_fall, 0.0)
	bits.damping_min = 0.2
	bits.damping_max = 0.4
	bits.angular_velocity_min = -180.0
	bits.angular_velocity_max = 180.0
	bits.particle_flag_rotate_y = true
	bits.color_initial_ramp = Confetti._palette(c.colors).gradient
	bits.color_ramp = Confetti._fade(0.2).gradient
	return bits
