class_name NoveltyParams
extends Resource
## The shop's goofy things: reactive hats (HatToy), novelty club heads (ClubModel), trails
## (BallTrail), shoes and balls (GolferRig, BallFx). Values live in data/novelty.tres.

@export_group("Hat Green")
@export var green_radius: float ## × the head's width: the disc
@export var green_ball: float ## × the disc's radius: its ball
@export var green_gain: float ## how hard the head's acceleration and tilt push the ball
@export var green_accel_max: float ## m/s², the head acceleration felt is capped at this
@export var green_friction: float ## 1/s, rolling friction
@export var green_sunk_time: float ## s the ball stays in the cup after a birdie

@export_group("Course Goose")
@export var goose_size: float ## × the head's width
@export var goose_turn: float ## rad, the most it turns its head
@export var goose_look_every: float ## s between looks (± 40 %)
@export var goose_blink_every: float ## s between blinks (± 30 %)
@export var goose_blink: float ## s an eye takes to close (and again to open)
@export var goose_honk_time: float ## s

@export_group("Power Propeller")
@export var beanie_fit: float ## × the head's width
@export var propeller_idle: float ## rad/s with no swing
@export var propeller_max: float ## rad/s at full power
@export var propeller_ease: float ## 1/s, how fast the spin follows the power
@export var sputter_time: float ## s from a whiff to a stop
@export var remote_power_rate: float ## rad/s of another player's streamed swing angle that reads as full power

@export_group("Club heads")
@export var flop_time: float ## s the fish's tail flops (or the beak hangs open) after impact
@export var flop_angle: float ## rad, at full power
@export var beak_power: float ## a drive over this power opens the rubber chicken's beak
@export var slap_volume_db: Vector2 ## Fresh Catch's wet slap, at power 0 and 1
@export var slap_pitch: Vector2
@export var squeak_volume_db: Vector2 ## Squeaky Set's squeak, at power 0 and 1
@export var squeak_pitch: Vector2

@export_group("Shoes and balls")
@export var shoe_slap_volume_db: float ## Clown Shoes, each step
@export var sparkle_speed: float ## m/s: the Disco Ball sparkles while rolling faster than this
@export var eye_turn_rate: float ## 1/s, the Eyeball turning to whoever is swinging
