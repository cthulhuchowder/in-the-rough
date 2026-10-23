class_name RulesData
extends Resource
## Stroke play rules. Values live in data/rules.tres.

@export var max_strokes: int ## at rest with this many strokes, the hole is picked up
@export var pickup_score: int
@export var penalty_strokes: int ## water and out of bounds
@export var water_delay: float ## s before the drop
@export var drop_step: float ## m per step toward the tee-to-cup line
@export var drop_push: float ## m further toward the line once playable
@export var drop_height: float ## m, ball centre above the ground when placed
@export var drop_clearance: float ## m round a re-placed ball kept free of trunks and rocks: the ball and the widest stance (driver 1.3 m)
@export var ground_band: float ## ball centre below this height counts as on the ground
@export var wind_strong_scale: float ## room rule "wind strong": times the hole's generated wind
