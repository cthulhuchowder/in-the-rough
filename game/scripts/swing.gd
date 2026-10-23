class_name Swing
extends Node3D
## Angle-integrating swing: reads SwingGesture each tick, measures speed of a point orbiting
## the camera, sweeps a hit box along the aim line and launches the ball on contact.

signal hit
signal spin_locked(spin: float) ## follow-through backspin decided after impact
signal whiffed ## a full swing went well past impact without touching the ball
signal ticked ## end of every physics tick, after the hitbox has moved: the visual club locks onto it

@export var feel: SwingFeel
@export var club: ClubData
@export var gesture: SwingGesture
@export var ball: Ball
@export var camera: Camera3D

var angle := 0.0
var pitch := 0.0
var power := 0.0
var peak_speed := 0.0
var path_angle := 0.0
var has_hit := false
var aim := Vector3.FORWARD ## horizontal, unit
var spin := 0.0 ## backspin 0..1, locked at first landing
var feet: Vector3 ## golfer's stance position
var shot_dir := Vector3.FORWARD ## launch direction of the last hit (the aim line)
## The swing eye at _cam_pos looking at the ball; its x is the eye's right (the eye's left is the aim
## line). The swing, mouse feeder and club pose read this, never the rendered Camera3D.
var eye_basis := Basis()
var contact_box: Vector3 ## hitbox centre where its sweep first touched the ball, on the hit tick

var spin_decided := true ## backspin is final for this shot (soft swing, landing or timeout)
var backswinging := false ## angle fell this tick: the power meter drops
var swing_started := false ## angle left stance_turn_window of address; stays set until reset()
var _whiffed := false
var _spin_time := 0.0
var _target: Vector3
var _body: Basis # x = away from target, z = toward golfer
var _cam_pos: Vector3
var _cam_right: Vector3
var _prev_angle := 0.0
var _prev_speed_point: Vector3
var _prev_box: Vector3
var _smoothed := 0.0
var _history: Array[float] = []
var _skip_tick := true

@onready var _hit_box: ShapeCast3D = $HitBox


func _ready() -> void:
	ball.first_landing.connect(lock_spin) # first reset() comes from main once a hole is loaded


func reset() -> void:
	_target = ball.global_position
	_body = Basis(-aim, Vector3.UP, (-aim).cross(Vector3.UP))
	feet = Vector3(_target.x, 0.0, _target.z) + _body.z * club.stance_dist
	feet.y = ball.course.height_at(feet)
	var head := feet + Vector3.UP * feel.camera_height - _body.z * feel.camera_forward
	_cam_pos = head + _body.z * club.camera_back # pulled back, away from the ball (_body.z is flat(ball→player))
	# Swing input, the hitbox and the club pose use only this swing eye; the rendered camera is placed
	# from it (place_view()) and never read back.
	eye_basis = Basis.looking_at(_target - _cam_pos)
	_cam_right = eye_basis.x
	place_view()

	angle = feel.address_angle
	_prev_angle = angle
	pitch = 0.0
	power = 0.0
	peak_speed = 0.0
	has_hit = false
	spin = 0.0
	spin_decided = true
	_skip_tick = true
	_whiffed = false
	backswinging = false
	swing_started = false
	# Smoothing and peak history don't carry across swings: start each swing clean.
	_smoothed = 0.0
	_history.clear()

	var size := feel.hitbox_size * club.hitbox_scale
	(_hit_box.shape as BoxShape3D).size = size
	($HitBox/Mesh.mesh as BoxMesh).size = size
	_prev_box = _box_pos()
	_hit_box.global_transform = Transform3D(_body, _prev_box)
	_hit_box.target_position = Vector3.ZERO
	_prev_speed_point = _speed_point()


func _physics_process(delta: float) -> void:
	_step(delta)
	ticked.emit()


func _step(delta: float) -> void:
	angle = clampf(angle + gesture.angle_delta, -feel.angle_limit, feel.angle_limit)
	pitch = clampf(pitch + gesture.pitch_delta, feel.pitch_min, feel.pitch_max)
	swing_started = swing_started or absf(angle - feel.address_angle) > feel.stance_turn_window
	if has_hit:
		_spin_time += delta
		if _spin_time >= feel.spin_lock_timeout:
			lock_spin()
		return

	var point := _speed_point()
	var vel := (point - _prev_speed_point) / delta
	_prev_speed_point = point
	_smoothed = lerpf(_smoothed, vel.length(), 1.0 - exp(-feel.speed_smooth_rate * delta))
	_history.push_back(_smoothed)
	while _history.size() > feel.speed_peak_window:
		_history.pop_front()
	peak_speed = _history.max()
	power = clampf(peak_speed / club.strength, 0.0, 1.0)

	var box := _box_pos()
	if _skip_tick:
		_skip_tick = false
		_prev_angle = angle
		_prev_box = box
		return

	var not_forward := angle < _prev_angle or vel.dot(-_body.x) <= 0.0
	backswinging = angle < _prev_angle
	_prev_angle = angle
	_hit_box.global_transform = Transform3D(_body, _prev_box)
	_hit_box.target_position = _body.inverse() * (box - _prev_box)
	_hit_box.force_shapecast_update()
	_prev_box = box

	if _hit_box.is_colliding() and peak_speed > 0.0 and not not_forward:
		contact_box = _hit_box.global_position.lerp(box,_hit_box.get_closest_collision_safe_fraction()) # read-only: for the visual club
		has_hit = true
		path_angle = gesture.path_delta.signed_angle_to(-_cam_right, Vector3.UP)
		shot_dir = -_cam_right
		ball.launch(-_cam_right, path_angle, power, club, _body.z)
		_spin_time = 0.0
		spin = 0.0
		# Soft swings get no spin; otherwise the follow-through decides at first landing.
		spin_decided = peak_speed < feel.spin_min_speed
		hit.emit()
	elif not _whiffed and not not_forward and peak_speed > feel.whiff_min_speed \
			and angle > impact_angle() + feel.whiff_angle:
		_whiffed = true
		whiffed.emit()


## Backspin from how far the follow-through has gone: near impact = full, spin_full_angle = none.
func spin_now() -> float:
	return clampf(remap(angle, 0.0, feel.spin_full_angle, 1.0, 0.0), 0.0, 1.0)


## Backspin final now, from where the follow-through is (also when the player walks off mid-shot).
func lock_spin() -> void:
	if spin_decided or not has_hit:
		return
	spin_decided = true
	spin = spin_now()
	ball.backspin01 = spin
	spin_locked.emit(spin)


## Point orbiting the camera at the camera-to-ball radius, turned by the swing angle.
func _speed_point() -> Vector3:
	var axis := _cam_pos.direction_to(_target).cross(-_cam_right).normalized()
	return _cam_pos + (_target - _cam_pos).rotated(axis, angle * feel.speed_angle_gain)


## Hit box slides linearly along the aim line with angle and toward/away from the golfer with pitch.
func _box_pos() -> Vector3:
	return hitbox_position_at(angle, pitch)


## The hitbox centre at swing angle `a` and pitch `p` (world), as _box_pos().
func hitbox_position_at(a: float, p: float) -> Vector3:
	var o := club.hitbox_offset
	return (_target
		- _body.x * (a - club.hitbox_late_offset) * club.hitbox_gain.x
		- _body.z * p * club.hitbox_gain.y
		+ _body.x * o.x + Vector3.UP * o.y + _body.z * o.z)


## The swing eye (the pose's pivot): the club pose's hands swing round it.
## The eye's right (−aim).
func eye_right() -> Vector3:
	return _cam_right


func swing_eye() -> Vector3:
	return _cam_pos


## The stance frame: x = away from the target, y = up, z = toward the golfer (hitbox_offset's frame).
func body_frame() -> Basis:
	return _body


## Where the hitbox is now (world): the visible clubhead is pulled onto it around impact.
func hitbox_position() -> Vector3:
	return _box_pos()


## The hitbox as a unit cube scaled to its size, centred at `centre` (world): basis.x is the box's
## full length along body.x, so −basis.x is its forward (the aim line) and centre − basis.x / 2 its leading face.
func hitbox_box(centre: Vector3) -> Transform3D:
	return Transform3D(_body * Basis.from_scale(feel.hitbox_size * club.hitbox_scale), centre)


## Swing angle at which the hitbox reaches the ball along the aim line (from _box_pos()).
func impact_angle() -> float:
	return club.hitbox_late_offset + club.hitbox_offset.x / club.hitbox_gain.x


## Swing angle that puts the hitbox centre at `box_centre` along the aim line (inverse of _box_pos()).
func angle_at(box_centre: Vector3) -> float:
	return club.hitbox_late_offset + (club.hitbox_offset.x - (box_centre - _target).dot(_body.x)) / club.hitbox_gain.x


## Where the club soles at address: the ball's position when the swing was last reset.
func address_point() -> Vector3:
	return _target


## The rendered shooting camera: a swing eye (this club's or the driver's) moved to view_height and
## view_pullback further from the ball along player→ball, pitched view_pitch down. Its right vector
## is exactly the eye's right (same yaw, no roll), so the aim line runs across the screen as the
## swing sees it.
func place_view() -> void:
	# With view_use_driver_framing the view stands where the driver's swing eye would (its stance distance,
	# camera pull and ground height), so it is identical for every club; the swing still measures
	# from this club's own swing eye.
	var framing := Clubs.ALL[0] if feel.view_use_driver_framing else club
	var from_ball := framing.stance_dist - feel.camera_forward + framing.camera_back + feel.view_pullback
	var eye := Vector3(_target.x, 0.0, _target.z) + _body.z * from_ball
	eye.y = ball.course.height_at(Vector3(_target.x, 0.0, _target.z) + _body.z * framing.stance_dist) + feel.view_height
	var level := Basis(_cam_right, Vector3.UP, _cam_right.cross(Vector3.UP))
	camera.global_transform = Transform3D(level * Basis(Vector3.RIGHT, -feel.view_pitch), eye)
