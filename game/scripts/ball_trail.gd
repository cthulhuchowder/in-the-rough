class_name BallTrail
extends MeshInstance3D
## A ball's trail (from launch, every club but the putter). `style` 0, the
## plain one: a thin ribbon through the ball's recent positions, facing the camera, fading out over
## FEEDBACK.trail_time. The shop's trails (ShopItem.Tab.TRAIL) emit only while the ball is in the air
## (well above its hole's ground), and each bit of them is gone within 2 s: 1 Bubble Stream, small iridescent
## bubbles that wobble and pop; 2 Duck Parade, tiny rubber ducks dropping behind it, and a little pile
## of them where it first lands, kept until the next shot; 3 Sad Smoke, grey puffs that droop and
## swell, thinner the weaker the shot. start() at launch clears the last one; feed() the ball's position
## every frame while it moves; stop() lets what is there fade. Visual only.

const FEEDBACK: FeedbackParams = preload("res://data/feedback.tres")
const STYLES := 4
const AIR := 0.3 ## m above the ground: the ball is flying (the shop's trails emit)
const LAND := 0.12 ## m: back down, landed
const LIFE := [0.0, 1.1, 1.6, 2.0] ## s, each bit of a style's trail (all within 2 s)
const EVERY := [0.0, 0.035, 0.1, 0.045] ## s between bits while flying
const PILE := 7 ## ducks in the landing pile
const DUCK := 2.0 ## × the duck mesh (6 cm): 12 cm, readable from the follow camera

var style := 0:
	set(value):
		if value == style:
			return
		style = value
		clear()
		if _view:
			_view.queue_free()
			_view = null
var hole: Hole ## the ball's hole (its ground); unset: never flying. A new hole drops the pile
var ground_y := NAN ## with no hole: a flat ground at this height (the shop's demo)
var _points := [] # [position, time] oldest first
var _running := false
var _mesh := ImmediateMesh.new()
var _bits := [] # the shop's trails: [position, velocity, born, size, spin]
var _pile := PackedVector3Array() # Duck Parade: the landing pile (world points)
var _power := 1.0
var _flew := false # flying since the launch (the next landing makes the pile)
var _next := 0.0
var _view: MultiMeshInstance3D
var _pile_hole: Hole # the hole the pile is on
static var _looks := {} # style → mesh


func _ready() -> void:
	top_level = true
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = mat


## A new shot. `power` 0..1 (Sad Smoke: thinner the weaker).
func start(at: Vector3, power := 1.0) -> void:
	_points = [[at, _now()]]
	_running = true
	_power = clampf(power, 0.0, 1.0)
	_flew = false
	_pile.clear()


## Gone at once (a putt, or the ball placed somewhere new: `keep_pile`, the Duck Parade's pile stays).
func clear(keep_pile := false) -> void:
	_points.clear()
	_bits.clear()
	if not keep_pile:
		_pile.clear()
	_running = false


func stop() -> void:
	_running = false


func feed(at: Vector3) -> void:
	if not _running:
		return
	if style == 0:
		if _points.is_empty() or at.distance_to(_points[-1][0]) > 0.02:
			_points.append([at, _now()])
		return
	var height: float = at.y - _ground(at) if hole != null or not is_nan(ground_y) else 0.0
	var now := _now()
	if height > AIR:
		if not _flew:
			_flew = true
			_next = now
		while now >= _next: # one bit every EVERY s while it flies
			_emit(at, now)
			_next += EVERY[style]
	elif _flew and height < LAND:
		_flew = false
		if style == 2 and _pile.is_empty(): # where it first lands: the pile
			_pile_hole = hole
			for k in PILE:
				var ring := 0 if k < 4 else (1 if k < 6 else 2)
				var a: float = TAU * k / [4.0, 2.0, 1.0][ring] + ring * 0.7
				var r: float = [0.09, 0.05, 0.0][ring] * DUCK
				_pile.append(Vector3(at.x + cos(a) * r, _ground(at) + (0.025 + ring * 0.045) * DUCK, at.z + sin(a) * r))


func _emit(at: Vector3, now: float) -> void:
	var h := Procgen.mix(int(now * 1000.0) ^ _bits.size() * 7919)
	var r := func(k: int) -> float: return float((h >> k) & 1023) / 1023.0 - 0.5
	var back: Vector3 = (_points[-1][0] - at).normalized() if not _points.is_empty() and _points[-1][0] != at else Vector3.ZERO
	match style:
		1: # a bubble, drifting up a little
			_bits.append([at + Vector3(r.call(0), r.call(10), r.call(20)) * 0.12, Vector3(r.call(3), 0.25 + r.call(13) * 0.2, r.call(23)) * 0.6, now,
				0.04 + (r.call(5) + 0.5) * 0.045, r.call(15) * TAU])
		2: # a duck, tossed back and falling
			_bits.append([at, back * 1.5 + Vector3(r.call(0), 0.6, r.call(20)) * 1.2, now, 1.0, r.call(10) * TAU])
		3: # a puff, sagging
			_bits.append([at + Vector3(r.call(0), r.call(10), r.call(20)) * 0.06, Vector3(r.call(3) * 0.2, -0.35, r.call(23) * 0.2), now,
				lerpf(0.05, 0.16, _power) * (0.8 + (r.call(5) + 0.5) * 0.4), r.call(15) * TAU])
	_points = [[at, now]] # (the last emitter position, for "behind")


func _process(delta: float) -> void:
	var now := _now()
	if style == 0:
		_draw_ribbon(now)
		return
	_mesh.clear_surfaces()
	var life: float = LIFE[style]
	while not _bits.is_empty() and now - _bits[0][2] > life:
		_bits.pop_front()
	if _view == null:
		_view = MultiMeshInstance3D.new()
		_view.top_level = true
		_view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = look(style)
		_view.multimesh = mm
		_view.material_override = _material(style)
		add_child(_view)
	var mm := _view.multimesh
	mm.instance_count = _bits.size() + _pile.size()
	for i in _bits.size():
		var b: Array = _bits[i]
		var age: float = now - b[2]
		var f := age / life
		match style:
			1:
				b[0] += (b[1] + Vector3(sin(age * 9.0 + b[4]), 0.0, cos(age * 7.0 + b[4])) * 0.35) * delta # wobbling
				var pop := clampf((f - 0.85) / 0.15, 0.0, 1.0) # the last moment: swells and goes
				mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * b[3] * (1.0 + pop * 0.8) * (1.0 + 0.12 * sin(age * 20.0 + b[4])) / 0.05), b[0]))
				mm.set_instance_color(i, Color(1, 1, 1, (1.0 - pop) * 0.8))
			2:
				b[1].y -= 9.8 * 0.6 * delta
				b[0] += b[1] * delta
				if hole != null or not is_nan(ground_y):
					b[0].y = maxf(b[0].y, _ground(b[0]) + 0.02)
				var shrink := 1.0 - clampf((f - 0.8) / 0.2, 0.0, 1.0)
				mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, b[4] + age * 4.0) * Basis(Vector3.RIGHT, age * 6.0) * Basis.from_scale(Vector3.ONE * shrink * DUCK), b[0]))
				mm.set_instance_color(i, Color.WHITE)
			3:
				b[1].y -= 0.25 * delta # drooping more as it goes
				b[0] += b[1] * delta
				var size: float = b[3] * (1.0 + f * 1.4)
				mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, b[4]) * Basis.from_scale(Vector3(size, size * 0.8, size) / 0.05), b[0]))
				mm.set_instance_color(i, Color(0.62, 0.62, 0.64, 0.75 * (1.0 - f) * (1.0 - f)))
	if _pile_hole != hole:
		_pile.clear()
	for k in _pile.size():
		mm.set_instance_transform(_bits.size() + k, Transform3D(Basis(Vector3.UP, k * 1.9) * Basis.from_scale(Vector3.ONE * DUCK), _pile[k]))
		mm.set_instance_color(_bits.size() + k, Color.WHITE)


func _draw_ribbon(now: float) -> void:
	while not _points.is_empty() and now - _points[0][1] > FEEDBACK.trail_time:
		_points.pop_front()
	_mesh.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	if _points.size() < 2 or cam == null:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in _points.size():
		var p: Vector3 = _points[i][0]
		var along: Vector3 = (_points[mini(i + 1, _points.size() - 1)][0] - _points[maxi(i - 1, 0)][0])
		var side := along.cross(cam.global_position - p).normalized() * FEEDBACK.trail_width * 0.5
		var color := FEEDBACK.trail_color
		color.a *= 1.0 - clampf((now - _points[i][1]) / FEEDBACK.trail_time, 0.0, 1.0)
		_mesh.surface_set_color(color)
		_mesh.surface_add_vertex(p + side)
		_mesh.surface_set_color(color)
		_mesh.surface_add_vertex(p - side)
	_mesh.surface_end()


## One bit of a style's trail (bubbles and puffs at radius 0.05, scaled per bit; a duck 6 cm long).
static func look(which: int) -> Mesh:
	if _looks.has(which):
		return _looks[which]
	var root := Node3D.new()
	match which:
		1:
			LowPoly.piece(root, LowPoly.sphere(0.05, 8, 5), Color.WHITE, Vector3.ZERO)
		2: # a rubber duck
			var body := LowPoly.piece(root, LowPoly.sphere(0.025, 7, 4), Color(0.98, 0.84, 0.2), Vector3(0, 0.02, 0))
			body.scale = Vector3(1.0, 0.75, 1.25)
			LowPoly.piece(root, LowPoly.sphere(0.014, 6, 3), Color(0.98, 0.86, 0.24), Vector3(0, 0.045, -0.02))
			LowPoly.piece(root, LowPoly.box(Vector3(0.012, 0.005, 0.012)), Color(0.95, 0.5, 0.15), Vector3(0, 0.043, -0.035))
			LowPoly.piece(root, LowPoly.box(Vector3.ONE * 0.004), Color(0.1, 0.1, 0.12), Vector3(0.008, 0.05, -0.028))
			LowPoly.piece(root, LowPoly.box(Vector3.ONE * 0.004), Color(0.1, 0.1, 0.12), Vector3(-0.008, 0.05, -0.028))
			LowPoly.piece(root, LowPoly.cylinder(0.0, 0.01, 0.014, 4), Color(0.98, 0.84, 0.2), Vector3(0, 0.032, 0.03), Vector3(-1.0, 0, 0))
		3:
			LowPoly.piece(root, LowPoly.sphere(0.05, 7, 4), Color.WHITE, Vector3.ZERO)
	var parts: Array[Node3D] = []
	for child in root.get_children():
		parts.append(child)
	_looks[which] = LowPoly.merge(parts)
	root.free()
	return _looks[which]


## Its material: ducks matte vertex colour; puffs soft see-through grey; bubbles see-through, their rim
## shifting through the rainbow with the view angle and time (iridescent).
static func _material(which: int) -> Material:
	if which == 2:
		return LowPoly.shared_material()
	if which == 3:
		var smoke := LowPoly.material()
		smoke.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		return smoke
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode unshaded, blend_mix, cull_back, shadows_disabled;
void fragment() {
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	vec3 hue = 0.5 + 0.5 * cos(6.2832 * (rim * 1.3 + TIME * 0.4 + vec3(0.0, 0.33, 0.67)));
	ALBEDO = mix(vec3(0.85, 0.95, 1.0), hue, 0.7);
	ALPHA = COLOR.a * (0.25 + 0.75 * rim * rim);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = s
	return mat


func _ground(at: Vector3) -> float:
	return hole.height_at(at) if hole != null else ground_y


static func _now() -> float:
	return Time.get_ticks_usec() / 1000000.0
