class_name Ambience
extends Node3D
## A biome's air (visual only, clients). Bubbles and embers: particles in a box round the camera,
## which follow() keeps it in. Fireflies belong to the hole's trees. The sun's bloom (sun_bloom): a soft
## screen-aligned glow round where the sun is, no beams.
## Fireflies: 20–40 by the rough's trees, each wandering slowly, bobbing and pulsing.
## Placed from the hole seed. main calls set_kind() per hole, follow() every frame, and hides the
## whole thing during the flyover.

const BOX := Vector3(70, 26, 70) ## m: particles live in this box round the camera
const FLIES := Vector2i(20, 40)

var _air := Node3D.new() # follows the camera
var _fixed := Node3D.new() # stays with the hole
var _bloom_layer := CanvasLayer.new() # the sun's bloom, over the 3D view
var _bloom_rect: ColorRect
var _bloom := 0.0
var _sun := Vector3.DOWN
var _shimmer_rect: ColorRect
var _shimmer := 0.0
var _flies: MultiMeshInstance3D
var _fly_homes := PackedVector3Array()
var _fly_phase := PackedFloat32Array()
var _t := 0.0
## Off during the flyover: nothing emits or wanders; on, the particles restart already in the air.
var running := true:
	set(value):
		if value == running:
			return
		running = value
		for child in _air.get_children():
			if child is CPUParticles3D:
				(child as CPUParticles3D).emitting = value
				if value:
					(child as CPUParticles3D).restart() # (preprocess: already in the air)
		if _flies:
			_flies.visible = value


func _ready() -> void:
	for layer in [_air, _fixed]:
		layer.top_level = true
		add_child(layer)


func set_kind(kind: Biome.Ambient, sun: Vector3, hole: Hole, bloom := 0.0, bloom_color := Color.WHITE, shimmer := 0.0) -> void:
	_build_shimmer(shimmer)
	_sun = sun
	_bloom = bloom
	_build_bloom(bloom_color)
	for layer in [_air, _fixed]:
		for child in layer.get_children():
			child.queue_free()
	_flies = null
	match kind:
		Biome.Ambient.BUBBLES:
			_air.add_child(_particles(260, Color(0.78, 0.9, 0.95, 0.55), 0.09, Vector3(0, 1.2, 0), 0.25, 9.0, false))
		Biome.Ambient.WISPS: # slow pale-blue wisps drifting low and sideways
			_air.add_child(_particles(70, Color(0.62, 0.78, 1.0, 0.28), 0.32, Vector3(0.05, 0.01, 0.03), 0.35, 14.0, true))
		Biome.Ambient.EMBERS:
			_air.add_child(_particles(220, Color(1.0, 0.5, 0.15, 1.0), 0.06, Vector3(0, 1.4, 0), 0.8, 7.0, true))
		Biome.Ambient.FIREFLIES:
			if hole is GeneratedHole:
				_fireflies(hole as GeneratedHole)


## Keep the camera's box round it, and the sun's bloom where the sun is on screen.
func follow(camera: Camera3D) -> void:
	_air.global_position = camera.global_position
	_bloom_layer.visible = visible and _bloom > 0.0
	if not _bloom_layer.visible:
		return
	var toward := -_sun.normalized() # from the camera toward the sun
	var facing := -camera.global_basis.z
	var size := camera.get_viewport().get_visible_rect().size
	var mat := _bloom_rect.material as ShaderMaterial
	var ahead := camera.global_position + toward * 1000.0
	var at := camera.unproject_position(ahead) / size if not camera.is_position_behind(ahead) else Vector2(0.5, -1.0)
	mat.set_shader_parameter("sun_uv", at)
	mat.set_shader_parameter("strength", _bloom * clampf(facing.dot(toward) * 0.5 + 0.5, 0.0, 1.0)) # most toward the sun


func _process(delta: float) -> void:
	_t += delta
	if _shimmer_rect:
		_shimmer_rect.get_parent().visible = visible and _shimmer > 0.0
		var wave := pow(maxf(0.0, sin(_t * TAU / 40.0)), 3.0) # on for a few seconds of every 40
		(_shimmer_rect.material as ShaderMaterial).set_shader_parameter("strength", _shimmer * wave)
	if _flies == null or not visible or not running:
		return
	var mm := _flies.multimesh
	for k in mm.instance_count:
		var ph := _fly_phase[k]
		var wander := Vector3(sin(_t * 0.11 + ph * 3.1) + 0.6 * sin(_t * 0.23 + ph * 7.3), 0.0,
			cos(_t * 0.09 + ph * 5.7) + 0.6 * sin(_t * 0.19 + ph * 2.9)) * 2.2
		var bob := Vector3(0, sin(_t * 0.7 + ph * 11.0) * 0.25, 0)
		mm.set_instance_transform(k, Transform3D(Basis.IDENTITY, _fly_homes[k] + wander + bob))
		var glow := pow(maxf(0.0, sin(_t * (0.9 + 0.5 * fposmod(ph, 1.0)) + ph * 13.0)), 2.0)
		mm.set_instance_color(k, Color(0.75, 1.0, 0.45, 0.15 + 0.85 * glow))


func _particles(amount: int, color: Color, size: float, rise: Vector3, wander: float, life: float,
		glow: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.preprocess = life # already in the air
	p.local_coords = false # they stay put as the camera moves through them
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = BOX * 0.5
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = wander
	p.gravity = rise
	p.damping_min = 0.2
	p.damping_max = 0.6
	p.mesh = _dot(size, color, glow)
	var fade := Gradient.new() # in and out over each life
	fade.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	p.color_ramp = fade
	return p


func _dot(size: float, color: Color, glow: bool) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = size
	mesh.height = size * 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mesh.material = mat
	return mesh


## Fireflies by the rough's trees (not the out-of-bounds forest), each with a home a few metres from
## one, 0.6–2.4 m up; the count and homes from the hole seed.
func _fireflies(hole: GeneratedHole) -> void:
	var d := hole.data
	var trees := d.forest_from
	if trees == 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = Procgen.mix(d.seed ^ 0x666c79)
	var count := rng.randi_range(FLIES.x, FLIES.y)
	_fly_homes.clear()
	_fly_phase.clear()
	for k in count:
		var t := rng.randi_range(0, trees - 1)
		var a := rng.randf() * TAU
		var r := rng.randf_range(2.0, 6.0)
		var at := Vector3(d.trees[4 * t] / 100.0 + cos(a) * r, 0.0, d.trees[4 * t + 1] / 100.0 + sin(a) * r)
		at.y = hole.height_at(at) + rng.randf_range(0.6, 2.4)
		_fly_homes.append(hole.to_global(at))
		_fly_phase.append(rng.randf() * 100.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _dot(0.1, Color.WHITE, true)
	mm.instance_count = count
	_flies = MultiMeshInstance3D.new()
	_flies.multimesh = mm
	_flies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fixed.add_child(_flies)
	_process(0.0)




## The sun's bloom: a soft warm glow over the screen round where the sun is (screen-aligned, no
## beams), strength `bloom` (Biome.sun_bloom), fading as the view turns away from it.
func _build_bloom(color: Color) -> void:
	if _bloom_rect == null:
		_bloom_layer.layer = -1 # under the HUD
		add_child(_bloom_layer)
		_bloom_rect = ColorRect.new()
		_bloom_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_bloom_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		var s := Shader.new()
		s.code = """
shader_type canvas_item;
render_mode blend_add;
uniform vec2 sun_uv;
uniform float strength;
uniform vec4 tint : source_color;
void fragment() {
	vec2 d = (UV - sun_uv) * vec2(1.6, 1.0);
	float glow = exp(-dot(d, d) * 2.2) * 0.75 + exp(-dot(d, d) * 0.45) * 0.25; // a soft core and a wide haze
	COLOR = vec4(tint.rgb * glow * strength, 1.0);
}
"""
		mat.shader = s
		_bloom_rect.material = mat
		_bloom_layer.add_child(_bloom_rect)
	(_bloom_rect.material as ShaderMaterial).set_shader_parameter("tint", color)


## Heat shimmer (Biome.heat_shimmer): now and then the air over the far ground wavers — a screen
## wobble in a band round the middle of the view, easing in and out over a slow cycle.
func _build_shimmer(amount: float) -> void:
	if _shimmer_rect == null:
		var layer := CanvasLayer.new()
		layer.layer = -1
		add_child(layer)
		_shimmer_rect = ColorRect.new()
		_shimmer_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_shimmer_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		var s := Shader.new()
		s.code = """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float strength;
void fragment() {
	float band = smoothstep(0.35, 0.52, SCREEN_UV.y) * (1.0 - smoothstep(0.52, 0.78, SCREEN_UV.y));
	float wave = sin(SCREEN_UV.y * 140.0 + TIME * 5.0) * 0.6 + sin(SCREEN_UV.x * 60.0 - TIME * 3.0) * 0.4;
	vec2 at = SCREEN_UV + vec2(wave * 0.0016, wave * 0.0008) * band * strength;
	COLOR = texture(screen, at);
}
"""
		mat.shader = s
		_shimmer_rect.material = mat
		layer.add_child(_shimmer_rect)
	_shimmer = amount
	_shimmer_rect.get_parent().visible = amount > 0.0
