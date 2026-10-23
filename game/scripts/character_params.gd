class_name CharacterParams
extends Resource
## Golfer proportions and animation tunables. Values live in data/character.tres.
## Lengths in metres, angles in radians. Sizes are full widths, heights and depths.

@export_group("Body")
@export var bevel: float ## chamfer on every edge, as a fraction of each part's smallest dimension
@export var bevel_segments: int ## facets per rounded edge
@export var leg_upper: float
@export var leg_lower: float
@export var hip_width: float ## half, between hip joints
@export var torso_length: float
@export var torso_top: Vector2 ## width, depth at the chest
@export var torso_waist: float ## taper: waist size as a fraction of the chest
@export var vest_size: Vector3 ## width, length, depth of the open-fronted vest shell
@export var shoulder_width: float ## half
@export var shoulder_roll: float ## shoulders pushed forward, for the slouch
@export var slouch: float ## upper-body forward tilt standing and walking
@export var breath_period: float ## s per breath at idle
@export var breath_depth: float ## rad the chest lifts on a breath
@export var arm_upper: float
@export var arm_lower: float
@export var limb_radius: float
@export var elbow_bend: float ## the soft bend in a relaxed arm
@export var knee_bend_idle: float
@export var hand_size: Vector3 ## rounded mitt
@export var foot_size: Vector3 ## rounded block

@export_group("Head")
@export var head_size: Vector3 ## tall faceted block, no neck; about 0.35 of total height
@export var nose_size: Vector3 ## long flat plane down the middle of the face
@export var nose_tilt: float ## its bottom juts out
@export var eye_radius: float ## big white bulging spheres, about a quarter of face width across
@export var eye_scale: Vector2 ## left, right: the left eye is the bigger one
@export var eye_spacing: float ## half
@export var eye_height: float ## fraction of head height
@export var eye_bulge: float ## fraction of the eye radius standing proud of the face
@export var pupil_radius: float
@export var mouth_size: Vector3 ## wide thin slot
@export var mouth_height: float ## fraction of head height
@export var pupil_scale: Vector2 ## left, right: slightly mismatched sizes
@export var pupil_look_left: Vector2 ## gaze offset (x right, y up), slightly different per eye
@export var pupil_look_right: Vector2
@export var cap_height: float ## rounded cap hugging the head (hat slot)
@export var cap_fit: float ## cap footprint relative to the head
@export var cap_drop: float ## how far the cap comes down over the head
@export var cap_round: float ## bevel of the cap crown, as a fraction of its height
@export var visor_size: Vector3
@export var ear_size: Vector3 ## small rounded nub: thickness, height, depth
@export var ear_back: float ## m behind the head centre

@export_group("Colors")
@export var features: Color ## pupils, mouth, shoes
@export var eye_white: Color
@export var remote_shirts: PackedColorArray ## other players, by join order, until skins exist

@export_group("Swing")
@export var address_lean: float ## spine tilt toward the ball
@export var wrist_ratio: float ## club turns this many times the arm angle
@export var shoulder_turn: float ## torso yaw per rad of swing angle
@export var hip_turn: float
@export var turn_limit: float
@export var finish_angle: float ## pose for a ball in flight on remote players
@export var stance_width: float ## half, feet apart at address
@export var knee_flex: float ## m the hips drop at address
@export var foot_splay: float ## rad each foot turns out from facing the ball at address
@export var side_bend: float ## rad the spine tilts away from the target at address, trail shoulder low
@export var grip_gap: float ## m along the shaft from the lead hand to the trail hand; under a hand's length, so they overlap
@export var address_elbow_bend: float ## rad left in the straighter elbow at address (the hips sit back to make it so)
@export var hip_back_max: float ## m the hips may sit back from the feet at address
@export var elbow_pole: Vector3 ## rig space, the lead elbow bends toward this (trail mirrors x): down and in, a narrow triangle
@export var contact_blend: float ## rad of swing angle either side of impact over which the clubhead is pulled onto the hitbox
@export var contact_clamp_speed_frac: float ## of club.strength: a swing whose peak speed is below this holds the visible head at the ball's surface instead of passing through
@export var fp_arm_length: float ## m from the swing eye to the hands at address
@export var fp_floor_soft: float ## m over which the first-person soft floor eases in (the club is lifted, never turned)
@export var fp_contact_ramp := 2.0 ## first person: fp_contact_offset's draw-back eases to a stop over this many times the angle from address to the hitbox meeting the ball, past it and back in the backswing (Main.contact_ramp; longer: a gentler curve in the head's path)
@export var fp_follow_body_rate: float ## 1/s: after the hit the (first-person, hidden) body turns toward the target this fast, the eye's right with it
@export var fp_pitch_follow_span: float ## rad of backswing over which the address pitch-follow (face on the hitbox under pitch) fades into the pitch turn about the eye
@export var club_scale: float ## club girth, grip and head size (visual), first person, third person and remote alike
@export var club_length_scale: float ## club length (the hands move to keep it soled at the ball: past ~1.1 the arms fold)
@export var fp_club_length_scale: float ## club length in first person, where no arms have to reach it
@export var club_head_scale: float ## heads on top of club_scale, so they read chunky

@export_group("Walk")
@export var stride_hz: float ## at walk_speed
@export var leg_swing: float
@export var knee_bend: float
@export var arm_swing: float
@export var bob: float ## m
@export var turn_rate: float ## 1/s, body yaw toward the walk direction
@export var shadow_alpha: float ## contact shadow under the club head at rest on the ground
@export var shadow_fade_height: float ## m: the shadow is gone once the head is this high
@export var shadow_size: float ## shadow footprint as a multiple of the head size
