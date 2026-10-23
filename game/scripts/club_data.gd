class_name ClubData
extends Resource
## One club. Values live in data/clubs/*.tres.

@export var label: String ## HUD code: D, 3I, PW, P...
@export var display_name: String ## spelled out: "7 iron" (the caddy's flash)
@export var strength: float ## m/s of speed point for full power; also launch speed scale
@export var loft_deg: float
@export var smash: float ## launch speed multiplier
@export var power_mul: float ## second launch speed multiplier
@export var curve_mul: float
@export var backspin: float ## m/s of check on first landing at full spin
@export var lift: float ## accel = lift·v² until first landing
@export var stance_dist: float ## m, ball to feet
@export var camera_back: float ## m, shooting camera = head + flat(ball→player) × this (pulled back, away from the ball)
@export var aim_side_view: bool ## aim camera sits behind the ball low (putter)
@export var hitbox_gain: Vector2 ## m per rad: x = along aim line by angle, y = depth by pitch
@export var hitbox_late_offset: float ## rad
@export var hitbox_offset: Vector3 ## body frame: x = body right, y = up, z = toward golfer
@export var hitbox_scale: Vector3
@export var hand_angle: float ## rad: first person, the address hands tilt off the eye→ball line about the eye's right
@export var fp_contact_offset: float ## m: first person, how far the club is drawn back along the aim by the hit tick so the visible gap between the drawn head (on a lofted head its leading edge) and the ball closes on exactly that tick; none at address (the face on the hitbox there), eased in with the swing angle (Main.contact_ramp; the hitbox is unchanged). art/fp_contact_calibration.gd measures it per club (ClubModel.head_gap)
@export var fp_shaft_lean: float ## rad: first person, the address shaft turned about the aim line (through the ball) before the arc
@export var fp_shaft_forward_lean: float ## rad: and about the axis toward the golfer (leans the grip toward or away from the target); art/fp_lean_calibration.gd fits both
@export_group("Carry")
@export var carry_fairway: float ## m: full-power straight carry from the fairway (art/carry_calibration.gd measures it)
@export var carry_rough: float ## m: from the rough
@export var carry_sand: float ## m: from sand

@export_group("Model")
@export var model: Model ## head shape
@export var shaft_length: float ## m, grip end to sole
@export var grip_length: float ## m
@export var head_size: Vector3 ## m: toe length, height, depth (face to back)
@export var lie_deg: float ## shaft angle from the ground at address (the head soles flat)

enum Model { DRIVER, IRON, WEDGE, PUTTER }


## Full-power straight carry from this lie (measured: art/carry_calibration.gd); fairway for any
## other lie (tee, green, fringe).
func carry_for(lie: SurfaceData) -> float:
	var kind := lie_kind(lie)
	return carry_rough if kind == "rough" else (carry_sand if kind == "sand" else carry_fairway)


## "fairway", "rough", "sand", "green"…: the lie's surface file (data/surfaces/*.tres), "" for none.
static func lie_kind(lie: SurfaceData) -> String:
	return lie.resource_path.get_file().get_basename() if lie else ""
