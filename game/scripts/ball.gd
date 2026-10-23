class_name Ball
extends RigidBody3D
## Golf ball: launch along the aim line pitched by loft; lift and curve until the first
## landing, drag whenever airborne; hand-written landing bounce with backspin; Jolt friction
## from the current lie for the roll.

signal first_landing ## the swing answers synchronously by writing backspin01
signal stopped
signal bounced(surface: SurfaceData, speed: float, shape: int) ## a landing or bounce (speed into it, m/s); shape: the prop's PropKind.Shape, −1 the ground (sounds: BallSounds)
signal rim_hit(speed: float) ## the ball knocks on the cup's lip
signal dropped ## into the cup

@export var feel: SwingFeel
@export var course: Hole

var carry := -1.0 ## m, horizontal launch to first landing; -1 until it lands
var in_play := false
var lie: SurfaceData
var backspin01 := 0.0
var last_position: Vector3 ## position one tick ago, for swept checks

var _club: ClubData # the club that hit this shot, not whatever is selected later
var _token := 0 # bumped by launch/halt so a stale settle timer can't report a stop
var _launch_vel := Vector3.ZERO
var _launch_pos: Vector3
var _side_spin := 0.0
var _spin_axis := Vector3.ZERO
var _prev_vel := Vector3.ZERO
var _airborne := false
var _been_airborne := false
var _landed := false
var _slow_time := 0.0
var _back := Vector3.ZERO
var _back_decay := 0.0
var _landing_dir := Vector3.ZERO # first-landing data, kept for a backspin that arrives late
var _landing_cap := 0.0
var _landing_damp := 0.0

## Server: the shooter's follow-through hasn't been reported yet.
var spin_pending := false
var _foliage := 0 # canopies and bushes the ball is inside (Flora's foliage areas)

## In the cup (captured or fallen in): holed once it settles.
var in_cup := false


const RADIUS := 0.05
const SHADES := [Color("#F0F0F0"), Color("#C2614E")] ## ball white and flag red (project palette): bold octants
const FEEDBACK: FeedbackParams = preload("res://data/feedback.tres")
const NOVELTY: NoveltyParams = preload("res://data/novelty.tres")
const REST_SPEED := 0.1 ## m/s: slower counts as at rest (the Eyeball looks round)
static var _mesh: ArrayMesh
static var _skins := {} # skin key → mesh (view_mesh_for)
var _trail: BallTrail # clients only
var _look: CharacterLook # what it wears (wear())
var nudge_views := true ## the impact nudge on (tests compare without it)
var _nudge := Vector3.ZERO # nudge_view(): the look's offset, world
var _nudge_time := 0.1
var _nudge_t := 1.0e9
var _nudge_frame := -1 # the hit tick: drawn with the whole offset, easing from the next


func _ready() -> void:
	$Mesh.mesh = view_mesh()
	add_to_group("balls") # (crows watch for them)


## The ball's look drawn `offset` from the ball itself, easing back to it over `time` s (smoothly):
## on the hit tick, ahead of a drawn club face that has reached it. Visual only: the body, its
## position, physics and what is sent are untouched.
func nudge_view(offset: Vector3, time: float) -> void:
	if not nudge_views:
		return
	_nudge = offset
	_nudge_time = maxf(time, 0.001)
	_nudge_t = 0.0
	_nudge_frame = Engine.get_physics_frames()
	_place_view()


func _place_view() -> void:
	var k := 1.0 - clampf(_nudge_t / _nudge_time, 0.0, 1.0)
	($Mesh as Node3D).position = global_basis.inverse() * (_nudge * k * k * (3.0 - 2.0 * k)) if k > 0.0 else Vector3.ZERO


## Draw this ball in a look's skin (the player's own, from the shop).
func wear(look: CharacterLook) -> void:
	_look = look
	$Mesh.mesh = view_mesh_for(look)
	if DisplayServer.get_name() != "headless":
		if _trail == null:
			_trail = BallTrail.new()
			add_child(_trail)
		_trail.style = look.trail_style if look else 0


func _process(delta: float) -> void:
	if _nudge_t < _nudge_time and Engine.get_physics_frames() != _nudge_frame:
		_nudge_t += delta
		_place_view()
	if not freeze:
		spin($Mesh, linear_velocity, delta)
	animate($Mesh, _look, Vector3.ZERO if freeze else linear_velocity, delta)
	if _trail:
		_trail.hole = course
		if in_play and visible:
			_trail.feed(global_position)
		else:
			_trail.stop()


## Faceted ball in two bold tones, alternating octants (two bands × four slices) so its spin reads
## at a glance. Shared.
static func view_mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	_mesh = _skin(func(c: Vector3) -> Color:
		var band := int(floor((asin(c.y) / PI + 0.5) * 2.0))
		var slice := int(floor((atan2(c.x, c.z) / TAU + 0.5) * 4.0))
		return SHADES[(band + slice) % 2])
	return _mesh


## The ball in a look's skin (the shop): its own two tones in octants, or one tone with a stripe
## round the middle; the standard ball when the look's ball_color is unset (alpha 0). Cached per skin.
static func view_mesh_for(look: CharacterLook) -> ArrayMesh:
	if look == null or look.ball_color.a == 0.0:
		return view_mesh()
	var key := "%s|%s|%d" % [look.ball_color.to_html(), look.ball_accent.to_html(), look.ball_style]
	if not _skins.has(key):
		var main := look.ball_color
		var accent := look.ball_accent
		if look.ball_style >= 2:
			_skins[key] = _novelty_skin(look)
		elif look.ball_style == 1:
			_skins[key] = _skin(func(c: Vector3) -> Color: return accent if absf(c.y) < 0.3 else main) # (the rings either side of the equator)
		else:
			_skins[key] = _skin(func(c: Vector3) -> Color:
				var band := int(floor((asin(c.y) / PI + 0.5) * 2.0))
				var slice := int(floor((atan2(c.x, c.z) / TAU + 0.5) * 4.0))
				return main if (band + slice) % 2 == 0 else main.darkened(0.25))
	return _skins[key]


## A faceted ball, each face the colour `shade` gives its centre direction; `sides` × `rings` facets,
## its material (null: the matte one), `bump` moving its vertices (lumps; normals follow).
static func _skin(shade_of: Callable, sides := 12, rings := 7, material: Material = null, bump := Callable()) -> ArrayMesh:
	var source := LowPoly.flat(LowPoly.sphere(RADIUS, sides, rings), Color.WHITE) # 7 inner rings: a vertex ring on the equator
	var arrays := source.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors := PackedColorArray()
	for k in range(0, verts.size(), 3):
		var c := (verts[k] + verts[k + 1] + verts[k + 2]).normalized()
		var shade: Color = shade_of.call(c)
		colors.append_array([shade, shade, shade])
		if bump.is_valid():
			for j in 3:
				verts[k + j] = bump.call(verts[k + j])
			var n := (verts[k + 2] - verts[k]).cross(verts[k + 1] - verts[k]).normalized()
			for j in 3:
				normals[k + j] = n
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material if material else LowPoly.material())
	return mesh


## Turn a ball mesh by its angular velocity: rolling at `velocity` it is ω = up × v / r; in the air
## (|v.y| ≥ 1) the same rate backwards, as backspin. The body itself never rotates (lock_rotation).
## The drawn rate is capped at ball_spin_max so the octants never strobe backwards.
static func spin(mesh: Node3D, velocity: Vector3, delta: float) -> void:
	var w := Vector3.UP.cross(velocity) / RADIUS
	if absf(velocity.y) >= 1.0:
		w = -w
	w = w.limit_length(FEEDBACK.ball_spin_max)
	if w.length() > 0.01:
		mesh.basis = Basis(w.normalized(), w.length() * delta) * mesh.basis
		mesh.basis = mesh.basis.orthonormalized()


## Backspin decided after launch. Before the first landing it is used there as usual; if it
## arrives after (a network round trip late), the missed check velocity is added now.
func set_backspin(spin: float) -> void:
	spin_pending = false
	backspin01 = spin
	if _landed and in_play:
		_back = (_landing_dir * _club.backspin * spin).limit_length(_landing_cap)
		linear_velocity += _back * _back_decay * (1.0 - _landing_damp)


func launch(aim: Vector3, path_angle: float, power: float, club: ClubData, golfer_side: Vector3) -> void:
	_club = club
	var dir := aim.normalized().rotated(Vector3.UP.cross(aim).normalized(), -deg_to_rad(club.loft_deg))
	_launch_vel = dir * clampf(power, 0.0, 1.0) * club.strength * club.power_mul * club.smash
	var sat := feel.path_saturation
	_side_spin = clampf(remap(path_angle, -sat, sat, -1.0, 1.0), -1.0, 1.0) * club.curve_mul * power
	_spin_axis = _launch_vel.normalized().cross(golfer_side).normalized()
	_launch_pos = global_position
	carry = -1.0
	backspin01 = 0.0
	spin_pending = false
	_back = Vector3.ZERO
	_back_decay = 0.0
	_prev_vel = _launch_vel
	_airborne = false
	_been_airborne = false
	_landed = false
	_slow_time = 0.0
	_token += 1
	_leave_cup()
	in_play = true
	freeze = false
	if _trail: # the trail from launch, every club but the putter
		if club.model != ClubData.Model.PUTTER:
			_trail.start(global_position, power)
		else:
			_trail.clear()


func halt() -> void:
	_token += 1
	_leave_cup()
	in_play = false
	freeze = true
	linear_velocity = Vector3.ZERO


## A foliage area the ball entered (+1) or left (−1).
func enter_foliage(change: int) -> void:
	_foliage = maxi(0, _foliage + change)


func _leave_cup() -> void:
	in_cup = false


func place(pos: Vector3) -> void:
	if _trail:
		_trail.clear(true) # placed somewhere new: the last shot's trail goes (a Duck Parade pile stays till the next shot)
	halt()
	global_position = pos
	last_position = pos
	lie = course.surface_at(pos)
	physics_material_override.friction = lie.friction


func _physics_process(_delta: float) -> void:
	last_position = global_position
	if in_play:
		lie = course.surface_at(global_position)
		# On the rim the ground is the cup's lip: slippery and a little bouncy, so a ball can ride it.
		var rim := in_cup or _on_rim(global_position) # the lip, and the cup's slick liner
		physics_material_override.friction = feel.cup_lip_friction if rim else lie.friction
		physics_material_override.bounce = feel.lip_restitution if rim else 0.0


## Within a ball's radius of the lip (cup_radius .. cup_radius + cup_lip_radius), at ground level.
func _on_rim(p: Vector3) -> bool:
	var c := course.cup.global_position
	var d := Vector2(p.x - c.x, p.z - c.z).length()
	return d > feel.cup_radius - RADIUS and d < feel.cup_radius + feel.cup_lip_radius + RADIUS and absf(p.y - c.y) < RADIUS * 2.0


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not in_play:
		return
	if _launch_vel != Vector3.ZERO:
		state.linear_velocity = _launch_vel
		_launch_vel = Vector3.ZERO
	var dt := state.step
	var v := state.linear_velocity
	if in_cup:
		v = _cup_step(state, v, dt)
	var was_airborne := _airborne
	_airborne = state.get_contact_count() == 0
	_been_airborne = _been_airborne or _airborne

	for i in state.get_contact_count():
		var n := state.get_contact_local_normal(i)
		var approach := maxf(-_prev_vel.dot(n), 0.0)
		# Obstacles (trees) carry their own surface and bounce the ball even while it rolls.
		var hit_obj := state.get_contact_collider_object(i)
		if (hit_obj != null and hit_obj.has_meta("cup")) or _on_rim(state.transform.origin):
			if approach >= feel.landing_min_approach:
				rim_hit.emit(approach)
			continue # the cup's lip, wall and bottom: the physics engine's contact alone
		var obstacle := hit_obj != null and hit_obj.has_meta("surface")
		var surface: SurfaceData = hit_obj.get_meta("surface") if obstacle else lie
		if (obstacle or (_been_airborne and was_airborne)) and _prev_vel.dot(n) < feel.landing_min_dot and approach >= feel.landing_min_approach:
			var v_n := n * _prev_vel.dot(n)
			var v_t := _prev_vel - v_n
			var head_on := clampf(-_prev_vel.normalized().dot(n), 0.0, 1.0)
			var damp := lerpf(feel.bounce_damp_min, feel.bounce_damp_max, clampf(v_n.length() / feel.impact_norm_speed, 0.0, 1.0) * head_on)
			if not _landed and _been_airborne:
				_landed = true
				var flat := state.transform.origin - _launch_pos
				carry = Vector2(flat.x, flat.z).length()
				first_landing.emit()
				_landing_dir = Vector3(-_prev_vel.x, 0.0, -_prev_vel.z).normalized()
				_landing_cap = feel.backspin_cap_frac * v_t.length()
				_landing_damp = damp
				_back = (_landing_dir * _club.backspin * backspin01).limit_length(_landing_cap)
				_back_decay = 1.0
			bounced.emit(surface, approach, int(hit_obj.get_meta("shape", -1)) if obstacle else -1)
			v =-v_n * surface.restitution + (v_t + _back * _back_decay) * (1.0 - damp)
		_back_decay *= exp(-feel.backspin_decay_contact * dt)

	var speed := v.length()
	if _airborne:
		if not _landed:
			v += Vector3.UP * speed * speed * _club.lift * dt
			# Axis is normalized, so curve never fades before landing.
			v += _spin_axis.cross(v) * _side_spin * feel.curve_force_gain * dt
		else:
			_back_decay *= exp(-feel.backspin_decay_air * dt)
		if speed > feel.drag_min_speed:
			v -= v.normalized() * speed * speed * feel.drag_coef * dt
		v += course.wind * feel.wind_strength * dt # a steady push while in the air, none on the ground

	if _foliage > 0: # inside a canopy or bush: leaves soak up its speed
		v *= exp(-feel.foliage_damping * dt)
	v = _cup_rim(state, v)
	state.linear_velocity = _stop_check(v, speed, dt)
	_prev_vel = state.linear_velocity


## Too slow for stop_time: stop and, after the settle delay, report it.
func _stop_check(v: Vector3, speed: float, dt: float) -> Vector3:
	_slow_time = _slow_time + dt if speed < feel.stop_speed else 0.0
	if _slow_time < feel.stop_time:
		return v
	in_play = false
	set_deferred("freeze", true)
	_settle.call_deferred(_token)
	return Vector3.ZERO


## The cup. The ground has a real hole whose edge is a rounded lip (part of the ground mesh, so no
## edge to catch; on it the ball is slippery and bouncy, cup_lip_friction and lip_restitution); the
## liner's wall and bottom are real colliders below it. A ball is captured (counts as in the cup and
## no longer pulled) when its centre is inside the opening, it is moving toward the centre and slower
## than cup_capture_speed; nothing else changes — it keeps its velocity and gravity, the lip and the
## wall take it down. Otherwise it is plain physics too: a faster
## ball crosses the opening with nothing under it, meets the lip and rides it (a glancing one can
## circle the hole) until it drops, is captured once slow enough, or leaves. A ball that ends up
## below the ground inside the opening is in the cup whatever the way in. Rolling within
## cup_pull_radius radii below cup_pull_max_speed, it is pulled toward the centre (a cup's slope).
func _cup_rim(state: PhysicsDirectBodyState3D, v: Vector3) -> Vector3:
	var c := course.cup.global_position
	var p := state.transform.origin
	var rel := Vector2(p.x - c.x, p.z - c.z)
	var d := rel.length()
	var flat := Vector2(v.x, v.z)
	if not in_cup and d < feel.cup_radius:
		var toward := flat.dot(-rel) > 0.0
		var below := p.y < c.y - RADIUS
		if below or (toward and flat.length() < feel.cup_capture_speed and p.y - c.y < RADIUS * 2.0):
			in_cup = true
			dropped.emit()
	elif in_cup and d > feel.cup_radius + RADIUS and p.y > c.y: # climbed back out over the lip
		_leave_cup()
	if not in_cup and not _airborne and d > 0.0 and d < feel.cup_radius * feel.cup_pull_radius \
			and flat.length() < feel.cup_pull_max_speed:
		v += Vector3(-rel.x, 0.0, -rel.y) / d * feel.cup_pull_accel * state.step
	return v


## In the cup: rolling on the bottom slows at cup_friction.
func _cup_step(state: PhysicsDirectBodyState3D, v: Vector3, dt: float) -> Vector3:
	var bottom := course.cup.global_position.y - feel.cup_depth + RADIUS
	if state.transform.origin.y <= bottom + 0.01:
		var damp := exp(-feel.cup_friction * dt)
		v.x *= damp
		v.z *= damp
	return v
func _settle(token: int) -> void:
	await get_tree().create_timer(feel.stop_settle_delay, false, true).timeout
	if token == _token:
		stopped.emit()



# --- the shop's novelty balls (look.ball_style 2–4) -------------------------------------------------

## Meatball: lumpy and brown with darker seared bits and specks of herb. Disco Ball: small mirror tiles,
## each its own shade of silver, shiny. Eyeball: white with a blue iris and a black pupil looking
## along −Z (Ball.animate turns it). The collider is the same sphere for all.
static func _novelty_skin(look: CharacterLook) -> ArrayMesh:
	match look.ball_style:
		2:
			return _skin(func(c: Vector3) -> Color:
				var h := _hash3(c * 9.0)
				if h > 0.9:
					return Color(0.3, 0.42, 0.18) # herbs
				return look.ball_color.darkened(0.35) if h > 0.6 else look.ball_color.lightened(0.08 * h),
				12, 7, null, func(p: Vector3) -> Vector3: return p * (1.0 + (_hash3(p.normalized() * 5.0) - 0.5) * 0.22))
		3:
			var mirror := LowPoly.material()
			mirror.metallic = 0.85
			mirror.roughness = 0.18
			mirror.metallic_specular = 0.9
			return _skin(func(c: Vector3) -> Color: return look.ball_color * (0.55 + 0.5 * _hash3(c * 40.0)), 18, 11, mirror)
		_:
			return _skin(func(c: Vector3) -> Color:
				var ahead := -c.z # (the pupil looks along −Z)
				if ahead > 0.93:
					return Color(0.05, 0.05, 0.06)
				if ahead > 0.74:
					return Color(0.25, 0.5, 0.85) if _hash3(c * 30.0) > 0.25 else Color(0.18, 0.38, 0.7)
				if ahead < 0.5 and _hash3(c * 23.0) > 0.93:
					return Color(0.85, 0.3, 0.3) # a vein
				return look.ball_color, 16, 9)


## 0..1 from a point (integer hash of it, quantised to 1/1000).
static func _hash3(p: Vector3) -> float:
	return float(Procgen.mix((int(p.x * 1000.0) * 73856093) ^ (int(p.y * 1000.0) * 19349663) ^ (int(p.z * 1000.0) * 83492791) & Procgen.MASK32) % 10007) / 10006.0


## Whoever is swinging now (Main and BallPuppets set it each frame: a golfer's head), for the Eyeball.
static var eye_target := Vector3.INF


## A novelty ball's behaviour on its drawn mesh, every frame after spin(): the Disco Ball sparkles
## while rolling; the Eyeball, at rest, turns its pupil to face whoever is swinging.
static func animate(mesh: Node3D, look: CharacterLook, velocity: Vector3, delta: float) -> void:
	if look == null:
		return
	if look.ball_style == 3:
		var sparkles := mesh.get_node_or_null("Sparkles") as CPUParticles3D
		if sparkles == null:
			sparkles = _sparkles()
			mesh.add_child(sparkles)
		var flat := Vector2(velocity.x, velocity.z).length()
		sparkles.emitting = flat > NOVELTY.sparkle_speed and absf(velocity.y) < 1.0
		sparkles.global_basis = Basis() # (not spinning with the ball)
	elif look.ball_style == 4 and velocity.length() < REST_SPEED and eye_target != Vector3.INF:
		var to := eye_target - mesh.global_position
		if to.length() > 0.2 and absf(to.normalized().y) < 0.97:
			var want := Basis.looking_at(to.normalized()) # its −Z, the pupil, toward them
			var now := mesh.global_basis.orthonormalized()
			mesh.global_basis = now.slerp(want, 1.0 - exp(-NOVELTY.eye_turn_rate * delta)).scaled(mesh.global_basis.get_scale())


static func _sparkles() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Sparkles"
	p.amount = 14
	p.lifetime = 0.45
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = RADIUS * 1.1
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.6
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var star := QuadMesh.new()
	star.size = Vector2.ONE * 0.018
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1.0, 0.98, 0.85)
	star.material = mat
	p.mesh = star
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	return p
