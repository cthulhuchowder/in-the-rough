class_name MenuSceneParams
extends Resource
## The main menu's live scene. Values live in data/menu_scene.tres.

@export var flag_right: float ## m right of the frame's centre the flag stands (the menu sits over the centre)
@export var golfer_right: float ## m right of the flag the golfer stands
@export var cart_left: float ## m right of the flag the cart is parked (behind the golfer)
@export var caddy_lean: float ## rad the caddy leans on the cart
@export_group("Camera")
@export var orbit_radius: float ## m from the centre
@export var orbit_height: float ## m above the ground
@export var orbit_speed: float ## rad/s of the to-and-fro
@export var look_height: float ## m: the point it looks at, above the centre
@export var arc_deg: float ## the camera drifts this far either side
@export var turn_rate: float ## 1/s: how fast the golfer turns to face the camera
@export_group("Wave")
@export var wave_out: float ## m beside the shoulder
@export var wave_height: float ## m above it
@export var wave_sway: float ## m either way
@export var wave_rate: float ## Hz
@export_group("Confetti")
@export var confetti_amount: int ## pieces in the air at once
@export var confetti_lifetime: float ## s each drifts
@export var confetti_fall: float ## m/s² (gentle)
@export var confetti_box: Vector3 ## m: where pieces appear, around the golfer, high up
@export_group("Title")
@export var title_left: float ## m left of the frame's centre the title's mound stands
@export var title_back: float ## m behind the centre (away from the camera)
@export var mound_size: Vector3 ## m: the grassy mound's half-extents
@export var letter_size: float ## m a grid step of the big line's letters (a letter is 4 tall); the top line is 0.7 of it
@export var title_drop: float ## m each letter falls from as the menu opens
@export var title_bounce_time: float ## s each letter's fall and bounce
@export var title_stagger: float ## s between one letter's start and the next
@export_group("Framing")
@export var centre_screen_x: float ## of the screen's width from the left, where the scene's centre sits (the buttons have the left)
@export var push_in: float ## m the camera eases in at either end of its drift
