class_name Walker
extends CharacterBody3D
## Third-person walk: WASD relative to the camera yaw, look from the gesture, mouse wheel zoom.

@export var feel: SwingFeel
@export var gesture: SwingGesture
@export var camera: Camera3D

var _yaw := 0.0
var _pitch := 0.0
var _distance := 3.5 # camera distance now (eases toward the zoom)


func _ready() -> void:
	exit()


func enter(at: Vector3, facing: Vector3) -> void:
	global_position = at
	velocity = Vector3.ZERO
	_yaw = atan2(-facing.x, -facing.z)
	_pitch = feel.walk_pitch_start
	_distance = _zoom_target()
	show()
	set_physics_process(true)
	_place_camera()


func exit() -> void:
	hide()
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	# Mouse wheel: zoom between walk_zoom_range, eased; the distance is kept in the settings
	if gesture.zoom != 0.0:
		var settings: Node = get_node("/root/Settings") # (looked up: tests type this class)
		var want := clampf(settings.walk_zoom * pow(feel.walk_zoom_step, -gesture.zoom), feel.walk_zoom_range.x, feel.walk_zoom_range.y)
		settings.change("walk_zoom", want)
	_distance = lerpf(_distance, _zoom_target(), 1.0 - exp(-feel.walk_zoom_smooth * delta))
	_yaw -= gesture.look.x * feel.walk_look_gain
	_pitch = clampf(_pitch - gesture.look.y * feel.walk_look_gain, feel.walk_pitch_min, feel.walk_pitch_max)
	var move := Vector3(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)), 0.0,
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
	if gesture.blocked: # a menu or the chat box has the keys
		move = Vector3.ZERO
	var dir := Basis(Vector3.UP, _yaw) * move.normalized()
	velocity.x = dir.x * feel.walk_speed
	velocity.z = dir.z * feel.walk_speed
	velocity += get_gravity() * delta
	move_and_slide()
	_place_camera()


func _place_camera() -> void:
	var pivot := global_position + Vector3.UP * feel.walk_camera_height
	var offset := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch) * Vector3(0, 0, _distance)
	camera.look_at_from_position(pivot + offset, pivot)


## The camera distance the player last zoomed to (settings), or walk_camera_distance.
func _zoom_target() -> float:
	var settings: Node = get_node_or_null("/root/Settings")
	var want: float = settings.walk_zoom if settings else feel.walk_camera_distance
	return clampf(want, feel.walk_zoom_range.x, feel.walk_zoom_range.y)
