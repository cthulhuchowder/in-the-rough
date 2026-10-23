class_name MouseSwingFeeder
extends Node
## Desktop feeder: sums captured mouse motion and writes it into the SwingGesture once per tick.

@export var gesture: SwingGesture
@export var feel: SwingFeel
@export var swing: Swing ## path input is read in its eye_basis (the swing eye), never the rendered camera

var _accum := Vector2.ZERO
var _zoom := 0.0 # wheel notches since the last tick
var _settings: Node # the Settings autoload, found at run time (a test script may load this class before autoloads exist)


func _ready() -> void:
	process_physics_priority = -1 # fill the gesture before Swing reads it
	Input.use_accumulated_input = false
	_settings = get_node("/root/Settings")


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		add_motion(event.relative)


func _unhandled_input(event: InputEvent) -> void:
	# Clicks the UI didn't take (e.g. not the seed field) capture the mouse.
	if event is InputEventMouseButton and event.pressed and not gesture.blocked: # not under an open menu
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom += 1.0
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom -= 1.0


func add_motion(pixels: Vector2) -> void:
	_accum += pixels


func _physics_process(_delta: float) -> void:
	if _settings.invert_vertical:
		_accum.y = -_accum.y
	var k: float = feel.mouse_to_angle * _settings.sensitivity_for(swing.club) # per club class (settings menu)
	var swinging := 0.0 if gesture.blocked else 1.0
	gesture.angle_delta = -_accum.x * k * swinging # mouse right = backswing
	gesture.pitch_delta = -_accum.y * k * swinging
	var back := swing.eye_basis.z
	back.y = 0.0
	gesture.path_delta = swing.eye_basis.x * _accum.x + back * _accum.y
	gesture.look = _accum
	gesture.aim_held = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	gesture.zoom = _zoom
	_accum = Vector2.ZERO
	_zoom = 0.0
