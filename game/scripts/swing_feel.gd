class_name SwingFeel
extends Resource
## Shared swing and ball-flight tunables. Values live in data/swing_feel.tres.

@export_group("Input")
@export var sensitivity_range: Vector2 ## the settings menu's per-club-class sensitivity sliders, min..max (default 1)
@export var mouse_to_angle: float ## rad per pixel
@export var angle_limit: float ## rad, both directions
@export var pitch_min: float
@export var pitch_max: float
@export var address_angle: float ## rad, start of every swing
@export var stance_rotate_speed: float ## rad/s, A/D aim; also scales mouse aim
@export var stance_turn_window: float ## rad from address_angle: past it the backswing has started and A/D is ignored until reset()
@export var aim_mouse_gain: float ## aim yaw += stance_rotate_speed · (−dx · sensitivity · gain) · dt
@export var whiff_angle: float ## rad past the hitbox's impact angle with no hit: a whiff
@export var whiff_min_speed: float ## m/s peak speed for it to count as a swing at all

@export_group("Camera")
@export var camera_height: float ## m above the golfer's feet
@export var camera_forward: float ## m from the feet toward the ball
@export var view_height: float ## m: rendered shooting camera above the feet (the swing measures from the swing eye)
@export var view_pullback: float ## m further from the ball than the swing eye, along player→ball
@export var view_pitch: float ## rad down, horizon level; its yaw is always the swing eye's
@export var view_fov: float ## degrees, the first-person camera's vertical field of view
@export var view_use_driver_framing: bool ## the view uses the driver's stance distance and camera pull for every club, so it holds still on a club switch
@export var aim_camera_height: float ## m above the ball while aiming
@export var aim_side_height: float ## m above the ball, side-view clubs (putter)
@export var aim_side_back: float ## m behind the ball along the aim line, side-view clubs
@export var track_yaw_rate: float ## 1/s: after impact the camera stays put and turns after the ball
@export var track_pitch_rate: float ## 1/s
@export var follow_delay: float ## s after impact before the follow camera takes over
@export var follow_distance: float ## m behind the ball, along its travel
@export var follow_height: float ## m above it
@export var follow_lag: float ## 1/s: how fast the follow camera catches up
@export var follow_turn: float ## 1/s: how fast it swings round to the ball's new heading
@export var follow_look_rate: float ## 1/s: how fast the follow camera's look point catches the ball (exp smoothing)

@export_group("Walk")
@export var walk_speed: float ## m/s
@export var walk_look_gain: float ## rad per look unit
@export var walk_camera_distance: float ## m behind the pivot
@export var walk_camera_height: float ## m, pivot above the feet
@export var walk_zoom_range: Vector2 ## m: the mouse wheel zooms the walk camera between these
@export var walk_zoom_step: float ## distance factor per wheel notch
@export var walk_zoom_smooth: float ## 1/s: how fast the distance eases to the zoom
@export var walk_pitch_start: float
@export var walk_pitch_min: float
@export var walk_pitch_max: float

@export_group("Speed")
@export var speed_angle_gain: float ## speed point turns this many times the swing angle
@export var speed_smooth_rate: float ## 1/s
@export var speed_peak_window: int ## ticks

@export_group("Hit box")
@export var hitbox_size: Vector3 ## m, before the club's scale

@export_group("Flight")
@export var path_saturation: float ## rad of path angle for full curve
@export var curve_force_gain: float
@export var drag_coef: float ## 1/m, accel = k·v²
@export var drag_min_speed: float
@export var wind_strength: float ## 1/s: in the air the ball accelerates at wind × this (hole wind, m/s); none on the ground
@export var foliage_damping: float ## 1/s: inside a canopy or bush the ball's velocity decays at this rate

@export_group("Landing")
@export var landing_min_dot: float
@export var landing_min_approach: float
@export var impact_norm_speed: float
@export var bounce_damp_min: float
@export var bounce_damp_max: float
@export var stop_speed: float
@export var stop_time: float
@export var stop_settle_delay: float ## s at rest before the stop is reported

@export_group("Backspin")
@export var spin_min_speed: float ## peak speed below this gives no spin
@export var spin_full_angle: float ## follow-through angle at which spin reaches 0
@export var spin_lock_timeout: float ## s after impact; spin locks at first landing or this
@export var backspin_cap_frac: float ## of tangential speed
@export var backspin_decay_contact: float ## 1/s
@export var backspin_decay_air: float ## 1/s

@export_group("Cup")
@export var cup_radius: float ## m, half the cup's width: regulation 108 mm scaled to the 0.05 m ball (× 100/42.7), then 1.5× for play
@export var cup_depth: float ## m, rim to bottom
@export var cup_capture_speed: float ## m/s: centre inside the opening, moving toward the centre and slower than this: captured (falls in)
@export var cup_pull_radius: float ## × cup_radius: inside it a rolling ball below capture speed is pulled toward the centre
@export var cup_pull_accel: float ## m/s² of that pull (a real cup's slope)
@export var cup_pull_max_speed: float ## m/s: the pull only acts below this, so it never fights a ride round the rim
@export var cup_lip_radius: float ## m, tube of the torus lip round the rim
@export var cup_lip_friction: float ## the lip and the cup's liner: slick, so a ball can ride round the rim and spiral down the wall
@export var lip_restitution: float ## bounce off the lip
@export var cup_friction: float ## 1/s, rolling on the cup bottom
@export var flag_lift_distance: float ## m: the pin lifts out while the ball is this close (and drops back once it leaves)
@export var flag_lift_speed: float ## m/s
