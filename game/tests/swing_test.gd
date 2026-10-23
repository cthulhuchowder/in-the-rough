extends SceneTree
## Headless check of step 2.1 + 2.2: swing hits, drive carries, wedge backspin from the
## follow-through, lies, drops, water/OB penalties, cup capture and lip-outs, pin lift, 14-stroke pickup.
## Run: godot --headless --fixed-fps 120 --path game -s res://tests/swing_test.gd

const Hazard := SurfaceData.Hazard

var _main: Node
var _hole: Hole
var _swing: Swing
var _ball: Ball
var _feeder: MouseSwingFeeder
var _failed := false


func _initialize() -> void:
	_main = load("res://main.tscn").instantiate()
	_main.random_course = false # the default course, so every run plays the same holes
	root.add_child(_main)
	_swing = _main.get_node("Swing")
	_ball = _main.get_node("Ball")
	_feeder = _main.get_node("MouseSwingFeeder")
	_run()


func _run() -> void:
	await physics_frame

	# Generated hole: ball tees up on the terrain, a drive lands and comes to rest on it, N moves on
	var generated: GeneratedHole = _main._hole
	var tee_gap := _ball.global_position.y - generated.height_at(_ball.global_position)
	_check(_main.hole_number == 1 and is_equal_approx(tee_gap, _main.rules.drop_height), "generated hole 1 tees up on terrain")
	for i in 3:
		await process_frame
	var head: Node3D = _main._rig._club_model.get_node("Head")
	var face_c := head.to_global(ClubModel.face_centre(_swing.club, _main._rig.girth_scale(), _main._rig.params.club_head_scale))
	var lie_deg := rad_to_deg(asin(_main._rig._club.global_basis.y.normalized().y))
	var address_box: Transform3D = _swing.hitbox_box(_swing.hitbox_position())
	var lead := address_box.origin - address_box.basis.x * 0.5 # (the face on the leading face at address)
	# The club on the swing arc: at address the hands are the address hands,
	# fp_arm_length from the eye along the eye→ball line tilted by hand_angle about the eye's right, plus the
	# one constant offset that puts the face on the hitbox there.
	var eye: Vector3 = _main._camera.global_position # the arc's pivot: the viewer (the rendered first-person camera)
	var hands0: Vector3 = eye + (_swing.address_point() - eye).normalized().rotated(_swing.eye_right().normalized(),
		-_swing.club.hand_angle) * _main._rig.params.fp_arm_length
	# ...turned about the ball by the club's constant address leans (fp_shaft_lean, fp_shaft_forward_lean)
	var ball_at: Vector3 = _swing.address_point()
	var aim_axis: Vector3 = Vector3(_swing.aim.x, 0.0, _swing.aim.z).normalized()
	var to_golfer: Vector3 = aim_axis.cross(Vector3.UP).normalized()
	if (_main._rig.global_position - ball_at).dot(to_golfer) < 0.0:
		to_golfer = -to_golfer
	hands0 = ball_at + Basis(to_golfer, _swing.club.fp_shaft_forward_lean) * Basis(aim_axis, _swing.club.fp_shaft_lean) * (hands0 - ball_at)
	var hands_off: float = _main._rig._club.global_position.distance_to(hands0 + _main._fp_offset)
	_check(head.global_basis.y.normalized().dot(Vector3.UP) > 0.99 and (-head.global_basis.z).normalized().dot(_swing.aim) > 0.99
		and hands_off < 0.002 and face_c.distance_to(lead) < 0.002,
		"address: head flat, face square, face centre on the hitbox's leading face, hands at the address hands + the address offset (%.4f m off; offset %.3f m)" % [hands_off, _main._fp_offset.length()])
	_check(_main._rig._body_parts.all(func(v): return not v.visible) and _main._rig._club.visible, "first person draws only the club")

	# Club switch: the rendered camera equals a fresh Shooting entry for every club, and with
	# view_use_driver_framing it is the same view for all of them; each club keeps its own swing eye
	var switch_cam: Camera3D = _main.get_node("Camera3D")
	var first_view := switch_cam.global_transform
	var stale := []
	var moved := []
	var swing_eyes := {}
	for c in _main.CLUBS.size():
		_main.select_club(c)
		for i in 2:
			await process_frame
		var switched := switch_cam.global_transform
		swing_eyes[_swing._cam_pos.snapped(Vector3.ONE * 0.001)] = true
		_main._set_mode(_main.Mode.SHOOTING)
		for i in 2:
			await process_frame
		if not switched.is_equal_approx(switch_cam.global_transform):
			stale.append(_swing.club.label)
		# Same place; same yaw up to float noise in the eye's right (the putter eye is 0.22 m from a ball at ~500 m)
		if not switched.origin.is_equal_approx(first_view.origin) or switched.basis.x.distance_to(first_view.basis.x) > 1e-3:
			moved.append(_swing.club.label)
	_check(stale.is_empty(), "club switch: rendered camera equals a fresh Shooting entry for every club %s" % [stale])
	_check(moved.is_empty() and swing_eyes.size() > 1, "uniform first-person view across all clubs %s, swing eyes still per club (%d)" % [moved, swing_eyes.size()])
	_main.select_club(0)
	await process_frame

	# The rendered camera never steers the swing: at any pullback/pitch its right is the eye's right
	# (no roll) and the hitbox and clubhead still sweep along the eye's left through impact
	var view_feel: SwingFeel = _swing.feel
	var saved := [view_feel.view_pullback, view_feel.view_pitch, view_feel.view_height]
	var eye_right := _swing.eye_basis.x
	var view_cam: Camera3D = _main.get_node("Camera3D")
	_swing.set_physics_process(false) # pose by hand: no hit
	for view in [[0.0, 0.2, 1.835], [0.35, deg_to_rad(40.0), 1.835], [1.5, 1.3, 2.4]]:
		view_feel.view_pullback = view[0]
		view_feel.view_pitch = view[1]
		view_feel.view_height = view[2]
		_swing.reset()
		var box_at_address := _swing.hitbox_position()
		_swing.angle = -0.3
		var box_dir := (box_at_address - _swing.hitbox_position()).normalized()
		_main._lock_club() # the club locks onto the hitbox on each swing tick
		var head_from: Vector3 = (_main._rig._club_model.get_node("Head") as Node3D).global_position
		_swing.angle = 0.0
		_main._lock_club()
		var swept: Vector3 = (_main._rig._club_model.get_node("Head") as Node3D).global_position - head_from
		swept.y = 0.0
		var arc := swept.normalized().dot(-_swing.eye_basis.x)
		print("  view pullback %.2f m, pitch %.0f°: camera right · eye right %.4f, roll %.4f, hitbox · eye left %.4f, head sweep · eye left %.3f" % [
			view[0], rad_to_deg(view[1]), view_cam.global_basis.x.dot(_swing.eye_basis.x), view_cam.global_basis.x.y, box_dir.dot(-_swing.eye_basis.x), arc])
		_check(_swing.eye_basis.x.is_equal_approx(eye_right) and view_cam.global_basis.x.is_equal_approx(_swing.eye_basis.x)
			and absf(view_cam.global_basis.x.y) < 1e-5 and box_dir.dot(-eye_right) > 0.9999 and arc > 0.95,
			"view at pullback %.2f m, pitch %.0f°: swing arc stays along the eye's left" % [view[0], rad_to_deg(view[1])])
	view_feel.view_pullback = saved[0]
	view_feel.view_pitch = saved[1]
	view_feel.view_height = saved[2]
	_swing.set_physics_process(true)
	_swing.reset()
	await process_frame
	await _swing_mouse(20, 110)
	_check(_swing.has_hit, "driver hits on generated hole")
	var tracked_from: Vector3 = _main.get_node("Camera3D").global_position
	for i in 72: # 0.6 s: the eased turn (yaw 10/s, pitch 6/s) has mostly caught up
		await physics_frame
	var shot_cam: Camera3D = _main.get_node("Camera3D")
	_check(_main.mode == _main.Mode.SHOOTING and shot_cam.global_position.is_equal_approx(tracked_from),
		"after impact the shooting camera stays put")
	var ahead := (_ball.global_position - shot_cam.global_position).normalized()
	print("  0.6 s after impact the camera points %.1f° off the ball" % rad_to_deg(acos(clampf((-shot_cam.global_basis.z).dot(ahead), -1.0, 1.0))))
	_check((-shot_cam.global_basis.z).dot(ahead) > cos(deg_to_rad(25.0)), "and turns to track the ball")
	for i in int(_swing.feel.follow_delay * 120.0) - 72 + 4:
		await physics_frame
	_check(_main.mode == _main.Mode.FOLLOWING, "follow camera takes over %.0f s after impact" % _swing.feel.follow_delay)
	await _wait(func(): return not _swing.has_hit)
	await process_frame
	var head_cam: Vector3 = _main.get_node("Camera3D").global_position
	_check(_main.mode == _main.Mode.SHOOTING and head_cam.distance_to(_swing.feet) < 2.5,
		"ball at rest: camera cuts back to the player at the new lie")
	var rest_gap := _ball.global_position.y - generated.height_at(_ball.global_position)
	print("  generated drive: carry %.1f m  lie %s  gap %.3f m" % [_ball.carry, _ball.lie.resource_name, rest_gap])
	_check(_ball.carry > 50.0 and absf(rest_gap) < 0.5, "drive lands and rests on generated terrain")
	_key(KEY_N, true)
	_key(KEY_N, false)
	await physics_frame
	_check(_main.hole_number == 2 and _main.strokes == 0, "N plays the next hole")

	# Trees: a ball rolled into a trunk comes back at about the rough's restitution
	var entry: Dictionary = _main._course[_main.hole_number - 1] # this hole in parkland: its round canopies (a mixed course rotates biomes)
	var treed := GeneratedHole.new()
	treed.build(Procgen.hole(entry.seed, entry.par, _main.procgen, _main.procgen.biomes[0]), _main.procgen)
	_main.load_hole(treed, _main.hole_number)
	await physics_frame
	var trunk := Vector3(treed.data.trees[0] / 100.0, 0, treed.data.trees[1] / 100.0)
	var toward := (treed.cup.global_position - trunk) * Vector3(1, 0, 1)
	toward = -toward.normalized() # roll from the cup side, away from the cup
	_ball.place(treed.rest_point(trunk - toward * 3.0, _main.rules.drop_height))
	_ball.launch(toward, 0.0, 1.0, _main.CLUBS[10], Vector3.BACK)
	var into := 0.0
	var back := 0.0
	for i in 120:
		await physics_frame
		var along := _ball.linear_velocity.dot(toward)
		if along > 0.0:
			into = along # speed on the last tick before contact
		if along < -0.05:
			back = -along
			break
	print("  tree bounce: in %.2f m/s, back %.2f m/s (rough restitution %.2f)" % [into, back, treed.params.tree_surface.restitution])
	_check(back > 0.0 and absf(back / into - treed.params.tree_surface.restitution) < 0.1, "ball bounces off a tree with rough restitution")

	# Canopies are soft: a ball flown through one above the trunk is slowed hard and keeps going
	var round_k := -1
	for k in treed.data.trees.size() / 4:
		if treed.data.biome.trees[treed.data.trees[4 * k + 2]].shape == PropKind.Shape.ROUND_TREE:
			round_k = k
			break
	var kind: PropKind = treed.data.biome.trees[treed.data.trees[4 * round_k + 2]]
	var s := treed.data.tree_scale
	var size: Vector2 = kind.sizes[treed.data.trees[4 * round_k + 3]]
	size = Vector2(size.x * s[3 * round_k] * s[3 * round_k + 2], size.y * s[3 * round_k] * 1000.0) / 1000000.0 # its own size (tree_scale)
	var stem := Vector3(treed.data.trees[4 * round_k] / 100.0, 0, treed.data.trees[4 * round_k + 1] / 100.0)
	stem.y = treed.height_at(stem)
	var heart := stem + Vector3.UP * (size.x + size.y * 0.75)
	var across := Vector3.RIGHT
	_ball.place(heart - across * (size.y + 3.0) + Vector3.UP * 0.25)
	_ball.in_play = true
	_ball.freeze = false
	_ball._launch_vel = across * 30.0
	var fastest_in := 0.0
	var out_speed := -1.0
	var was_in := false
	for i in 360: # up to 3 s: a big canopy (tree_scale) is a long way through at foliage damping
		await physics_frame
		var inside: bool = _ball._foliage > 0
		if not inside and not was_in:
			fastest_in = maxf(fastest_in, _ball.linear_velocity.length())
		if was_in and not inside:
			out_speed = _ball.linear_velocity.length()
			break
		was_in = was_in or inside
	print("  canopy (%s, radius %.1f m): in %.1f m/s, out %.1f m/s, still heading %+.2f along" % [kind.resource_path.get_file(),
		size.y, fastest_in, out_speed, _ball.linear_velocity.normalized().dot(across)])
	_check(was_in and out_speed > 0.0 and out_speed < fastest_in * 0.6 and _ball.linear_velocity.dot(across) > 0.0,
		"a ball passes through a canopy, heavily damped, not bounced")
	_ball.halt()

	_hole = load("res://holes/test_hole.tscn").instantiate()
	_main.load_hole(_hole) # rules checks use the hand-placed layout
	await physics_frame
	var rules: RulesData = _main.rules

	# Lies and drops
	for probe in [[Vector3(0, 0, -100), "Fairway"], [Vector3(35, 0, -100), "Rough"], [Vector3(0, 0, -300), "Green"],
			[Vector3(-14, 0, -210), "Sand"], [Vector3(15, 0, -170), "Water"], [Vector3(100, 0, -100), "Out of bounds"]]:
		_check(_hole.surface_at(probe[0]).resource_name == probe[1], "lie at %s is %s" % [probe[0], probe[1]])
	_check(_hole.surface_at(_hole.drop_point(Vector3(15, 0.05, -170), rules)).hazard == Hazard.NONE, "water drop is playable")

	# swing eye: head + flat(ball→player) × pull, so the putter eye sits 0.3 m further from the ball
	var feel: SwingFeel = _swing.feel
	_main.select_club(10)
	var flat: Vector3 = _swing._cam_pos - _ball.global_position
	_check(is_equal_approx(Vector2(flat.x, flat.z).length(), 0.75 - feel.camera_forward + 0.3), "putter swing eye pulled back, away from the ball")
	_main.select_club(0)

	# Aiming: RMB hold puts the camera above the ball, mouse x yaws at the aim gain, release resets
	var cam: Camera3D = _main.get_node("Camera3D")
	var aim_before := _swing.aim
	_mouse_button(MOUSE_BUTTON_RIGHT, true)
	await physics_frame
	await physics_frame
	_check(_main.mode == _main.Mode.AIMING, "RMB hold enters aiming")
	_check(cam.global_position.is_equal_approx(_ball.global_position + Vector3.UP * feel.aim_camera_height), "aim camera above ball")
	var start := _swing.aim
	_feeder.add_motion(Vector2(100, 0))
	await physics_frame
	await physics_frame
	var expected: float = feel.stance_rotate_speed * (100.0 * root.get_node("Settings").sensitivity_for(_swing.club) * feel.aim_mouse_gain) / 120.0
	_check(is_equal_approx(_swing.aim.signed_angle_to(start, Vector3.UP), expected), "mouse right yaws aim right by aim gain")
	_mouse_button(MOUSE_BUTTON_RIGHT, false)
	await physics_frame
	await physics_frame
	_check(_main.mode == _main.Mode.SHOOTING and _swing.angle == feel.address_angle, "release returns to shooting, swing reset")

	# A/D rotate at stance_rotate_speed while at rest
	start = _swing.aim
	_key(KEY_A, true)
	for i in 120:
		await physics_frame
	_key(KEY_A, false)
	_check(absf(start.signed_angle_to(_swing.aim, Vector3.UP) - feel.stance_rotate_speed) < 0.02, "A turns 0.3 rad/s left")
	_swing.aim = aim_before
	_swing.reset()

	# Walk: F toggles, W walks forward, F returns to the same stance
	_key(KEY_F, true)
	_key(KEY_F, false)
	var walker: Walker = _main.get_node("Walker")
	var from := walker.global_position
	_key(KEY_W, true)
	for i in 120:
		await physics_frame
	_key(KEY_W, false)
	var walked := walker.global_position - from
	_check(_main.mode == _main.Mode.WALKING and absf(Vector2(walked.x, walked.z).length() - feel.walk_speed) < 0.3, "F walks; W moves ~walk_speed in 1 s")
	_key(KEY_F, true)
	_key(KEY_F, false)
	await physics_frame
	_check(_main.mode == _main.Mode.SHOOTING and _swing.aim.is_equal_approx(aim_before), "F returns to shooting stance")

	# Club switching: ] and [ step; the mouse wheel and trackpad no longer change clubs; hold Q for
	# the radial wheel, steer with the mouse, release to pick, Esc to cancel; no swing while open
	_tap(KEY_BRACKETRIGHT)
	await physics_frame
	_check(_swing.club.label == "3I", "] steps to the next club")
	_tap(KEY_BRACKETLEFT)
	await physics_frame
	_check(_swing.club.label == "D", "[ steps back")
	_mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true)
	_pan(5.0)
	await physics_frame
	_check(_swing.club.label == "D", "mouse wheel and trackpad pan no longer change clubs")
	_key(KEY_Q, true)
	await physics_frame
	var pw_dir := Vector2(sin(8 * TAU / 11.0), -cos(8 * TAU / 11.0)) # slice 8 (PW), clockwise from the top
	for i in 4:
		_feeder.add_motion(pw_dir * 40.0)
		await physics_frame
	_check(_swing.angle == feel.address_angle, "swing ignores the mouse while the wheel is open")
	_key(KEY_Q, false)
	await physics_frame
	_check(_swing.club.label == "PW", "hold Q, steer toward PW, release: PW selected")
	_key(KEY_Q, true)
	await physics_frame
	_feeder.add_motion(Vector2(-160, 0))
	await physics_frame
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	_key(KEY_Q, false)
	await physics_frame
	_check(_swing.club.label == "PW" and not _main._wheel.visible, "Esc cancels the wheel without changing club")
	_main.select_club(0)
	_swing.reset()

	# Driver off the tee
	await _swing_mouse(20, 110)
	_check(_swing.has_hit, "driver hits")
	await _wait(func(): return not _swing.has_hit)
	print("  drive: power %.3f  carry %.1f m  lie %s" % [_swing.power, _ball.carry, _ball.lie.resource_name])
	_check(_main.strokes == 1, "swing counts a stroke")
	_check(_ball.carry > 100.0 and _ball.carry < 400.0, "drive carry plausible")
	_check(_ball.lie.hazard == Hazard.NONE, "drive in play")

	# Wedge: follow-through held at impact -> full backspin with the PW's own value
	_main.select_club(8)
	_check(_swing.club.label == "PW", "key 9 selects PW")
	await _swing_mouse(20, 50)
	await _wait(func(): return _ball.carry >= 0.0)
	print("  wedge: power %.3f  carry %.1f m  spin %.2f  check %.2f m/s" % [_swing.power, _ball.carry, _swing.spin, _ball._back.length()])
	_check(_swing.spin > 0.9, "short follow-through locks near-full spin")
	_check(_ball._back.length() > 0.0, "backspin applied on landing")
	await _wait(func(): return not _swing.has_hit)

	# Out of bounds: +1, dropped playable
	var before: int = _main.strokes
	_ball.launch(Vector3.RIGHT, 0.0, 0.7, _main.CLUBS[0], Vector3.BACK)
	await _wait(func(): return _main.strokes == before + 1 and not _ball.in_play)
	_check(_main.strokes == before + 1, "OB adds a stroke")
	_check(_ball.lie.hazard == Hazard.NONE, "OB drop is playable")

	# Water: +1 after the delay, back at the last safe lie (where the shot was played from)
	var safe := _hole.rest_point(Vector3(0, 0, -60), _main.rules.drop_height)
	_ball.place(safe)
	_main._round.shot_taken()
	before = _main.strokes
	_ball.place(Vector3(15, 0.05, -170)) # (the shot ends in the pond)
	_ball.launch(Vector3.FORWARD, 0.0, 0.05, _main.CLUBS[10], Vector3.BACK)
	await _wait(func(): return _main.strokes == before + 1)
	_check(_main.strokes == before + 1, "water adds a stroke")
	_check(_ball.lie.hazard == Hazard.NONE and _ball.global_position.distance_to(safe) < 0.2,
		"water puts the ball back where the shot was played from (%.2f m off)" % _ball.global_position.distance_to(safe))
	# ...and never inside a trunk or rock: one standing on that spot moves it clear of the stance
	var rock := StaticBody3D.new()
	rock.set_meta("surface", _hole.out_of_bounds)
	var rock_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.8
	rock_shape.shape = sphere
	rock.add_child(rock_shape)
	_hole.add_child(rock)
	rock.global_position = safe + Vector3(0.3, 0.4, 0)
	await physics_frame
	await physics_frame
	var cleared := _hole.clear_spot(safe, _main.rules.drop_clearance, _main.rules.drop_height)
	var gap := Vector2(cleared.x - rock.global_position.x, cleared.z - rock.global_position.z).length()
	_check(gap > _main.rules.drop_clearance + 0.8 - 0.05 and _hole.surface_at(cleared).hazard == Hazard.NONE,
		"a re-placed ball keeps %.1f m clear of a rock on its spot (moved %.1f m, %.1f m from it)" % [_main.rules.drop_clearance,
		cleared.distance_to(safe), gap])
	rock.queue_free()

	# Cup: below capture speed drops and is holed; just over meets the far lip; much faster hops the hole;
	# off-centre and fast lips out round the rim; the pin lifts out within 10 m
	var cup := _hole.cup.global_position
	var pin: Node3D = _hole._pin
	_check(pin.visible, "pin in the cup with the ball on the tee")
	var putt := func(speed: float, offset: float) -> Dictionary:
		_main.restart()
		_ball.place(cup + Vector3(offset, 0.05, 0.2)) # 7 cm short of the rim: arrives at about launch speed
		_ball.launch(Vector3.FORWARD, 0.0, speed / _main.CLUBS[10].strength, _main.CLUBS[10], Vector3.BACK)
		var out := {entry = 0.0, top = 0.0}
		for i in 120 * 8:
			var p := _ball.global_position
			if out.entry == 0.0 and Vector2(p.x - cup.x, p.z - cup.z).length() < feel.cup_radius:
				out.entry = Vector2(_ball.linear_velocity.x, _ball.linear_velocity.z).length()
			out.top = maxf(out.top, p.y - cup.y)
			if _main.score >= 0 or not _ball.in_play:
				break
			await physics_frame
		for i in 150: # the stop is reported after the settle delay
			if _main.score >= 0:
				break
			await physics_frame
		out.holed = _main.score == 0 and _main.message.begins_with("Holed")
		out.at = _ball.global_position
		print("  putt %.2f m/s, offset %.2f m: entry %.2f m/s, holed %s, rest %s" % [speed, offset, out.entry, out.holed, (out.at - cup).snapped(Vector3.ONE * 0.01)])
		return out
	var slow: Dictionary = await putt.call(1.0, 0.0)
	_check(slow.holed and absf(slow.at.y - (cup.y - feel.cup_depth + Ball.RADIUS)) < 0.01,
		"1 m/s putt drops in and is holed once it settles on the bottom")
	for i in 120:
		await process_frame
	_check(_main._celebrated.has(0) and pin.visible and pin.position.y < 0.01,
		"holed: celebrated, and the pin goes back in (hopping) once the ball is in the cup")
	_main.restart()
	_ball.place(_hole.rest_point(cup + Vector3(0.0, 0.0, 2.0), Ball.RADIUS)) # near the cup, not in it
	for i in int(120.0 * Hole.POLE_HEIGHT / feel.flag_lift_speed) + 10:
		await process_frame
	_check(not pin.visible and not _main._celebrated.has(0), "pin lifted out with the ball within %.0f m (not holed)" % feel.flag_lift_distance)
	var near_limit: Dictionary = await putt.call(feel.cup_capture_speed - 0.1, 0.0)
	_check(near_limit.holed, "just under cup_capture_speed drops in")
	var over_limit: Dictionary = await putt.call(feel.cup_capture_speed + 0.2, 0.0)
	var over_off := Vector2(over_limit.at.x - cup.x, over_limit.at.z - cup.z).length()
	_check(over_off < 1.0, "just over cup_capture_speed it meets the far lip, never a straight pass-over (rests %.2f m from the cup, holed %s)" % [
		over_off, over_limit.holed])
	var fast: Dictionary = await putt.call(6.0, 0.0)
	_check(not fast.holed and fast.top > Ball.RADIUS + 0.01 and fast.at.z < cup.z - feel.cup_radius - Ball.RADIUS,
		"6 m/s putt hops the hole and runs on past the rim")
	var lip: Dictionary = await putt.call(4.0, 0.08)
	var turned := rad_to_deg(Vector2(0, -1).angle_to(Vector2(lip.at.x - cup.x - 0.08, lip.at.z - cup.z - 0.2)))
	print("  lip-out turned the putt %.1f°" % turned)
	_check(not lip.holed and absf(turned) > 5.0, "off-centre 4 m/s putt lips out round the rim")
	_main.restart()
	for i in int(120.0 * Hole.POLE_HEIGHT / feel.flag_lift_speed) + 10:
		await process_frame
	_check(pin.visible and pin.position.y == 0.0, "pin back in the cup once the ball is away")

	# Pickup at the cap
	_main.restart()
	_main.strokes = rules.max_strokes
	_ball.launch(Vector3.FORWARD, 0.0, 0.1, _main.CLUBS[10], Vector3.BACK)
	await _wait(func(): return _main.score >= 0)
	_check(_main.score == rules.pickup_score, "cap picks up at 14")

	# A new swing starts with clean speed state
	_swing.reset()
	_check(_swing.peak_speed == 0.0 and not _swing.has_hit, "reset clears speed state")

	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _swing_mouse(back_px: float, through_px: float) -> void:
	for i in 10:
		await physics_frame
	for i in 40:
		_feeder.add_motion(Vector2(back_px, 0))
		await physics_frame
	for i in 60:
		if _swing.has_hit:
			return
		_feeder.add_motion(Vector2(-through_px, 0))
		await physics_frame


func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = down
	Input.parse_input_event(e)


func _tap(code: Key) -> void:
	_key(code, true)
	_key(code, false)


func _pan(dy: float) -> void:
	var e := InputEventPanGesture.new()
	e.delta = Vector2(0, dy)
	Input.parse_input_event(e)


func _mouse_button(button: MouseButton, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = down
	Input.parse_input_event(e)


func _wait(cond: Callable, max_ticks := 120 * 30) -> void:
	for i in max_ticks:
		if cond.call():
			return
		await physics_frame


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	_failed = _failed or not ok
