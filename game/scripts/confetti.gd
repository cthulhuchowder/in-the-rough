class_name Confetti
## Hole-in confetti: a one-shot burst of small beveled flat-shaded chips in the celebration palette,
## shot up out of the cup, falling with drag and spin, coming to rest on the green (a height-field
## collider over it) and fading at the end of their lifetime. Client-side only.


## `amount` pieces from `at` (world). Frees itself when done.
static func pop(parent: Node, at: Vector3, amount: int, p: CelebrationParams) -> void:
	var burst := GPUParticles3D.new()
	burst.amount = maxi(amount, 1)
	burst.lifetime = p.lifetime
	burst.one_shot = true
	burst.explosiveness = 0.95
	burst.local_coords = false
	burst.visibility_aabb = AABB(Vector3(-12, -2, -12), Vector3(24, 14, 24))
	var motion := ParticleProcessMaterial.new()
	motion.direction = Vector3.UP
	motion.spread = p.spread_deg
	motion.initial_velocity_min = p.launch_speed.x
	motion.initial_velocity_max = p.launch_speed.y
	motion.gravity = Vector3(0, -p.gravity, 0)
	motion.damping_min = p.drift
	motion.damping_max = p.drift * 1.6
	motion.particle_flag_rotate_y = true
	motion.angular_velocity_min = p.spin_deg.x
	motion.angular_velocity_max = p.spin_deg.y
	motion.angle_min = 0.0
	motion.angle_max = 360.0
	motion.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	motion.collision_bounce = 0.05
	motion.collision_friction = 1.0 # land and stay put
	motion.color_initial_ramp = _palette(p.colors)
	motion.color_ramp = _fade(p.fade)
	burst.process_material = motion
	burst.draw_pass_1 = _chip(p.piece_size)
	var ground := GPUParticlesCollisionHeightField3D.new() # the green under the burst
	ground.size = Vector3(20, 8, 20)
	ground.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_256
	parent.add_child(ground)
	parent.add_child(burst)
	ground.global_position = at
	burst.global_position = at
	burst.emitting = true
	burst.finished.connect(func() -> void:
		burst.queue_free()
		ground.queue_free())


## A flat chip with beveled edges; white vertex color, so the particle color shows.
static func _chip(size: Vector3) -> Mesh:
	var mesh := LowPoly.flat(LowPoly.rounded_prism(4, Vector3(size.x, size.y, size.z), size.y * 0.45, 1), Color.WHITE)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	mesh.surface_set_material(0, mat)
	return mesh


## Each piece one of the colors (constant steps, no blending between them).
static func _palette(colors: PackedColorArray) -> GradientTexture1D:
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	g.offsets = PackedFloat32Array()
	g.colors = PackedColorArray()
	for i in colors.size():
		g.add_point(float(i) / colors.size(), colors[i])
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex


## Opaque, then fading out over the last `share` of the lifetime.
static func _fade(share: float) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0 - share, 1.0])
	g.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex
