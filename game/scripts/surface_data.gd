class_name SurfaceData
extends Resource
## One lie. Values live in data/surfaces/*.tres; resource_name is the display name.

enum Hazard { NONE, WATER, OUT_OF_BOUNDS }

@export var friction: float ## Jolt μ while rolling
@export var restitution: float ## normal bounce on landing
@export var hazard: Hazard
@export var color: Color
