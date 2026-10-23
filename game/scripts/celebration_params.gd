class_name CelebrationParams
extends Resource
## Hole-in celebration tunables. Values live in data/celebration.tres.

@export_group("Confetti")
@export var colors := PackedColorArray() ## palette colors; each piece takes one
@export var piece_size: Vector3 ## m: a small beveled rectangle
@export var amount_over_par: int ## pieces for a bogey or worse
@export var amount_par: int
@export var amount_birdie: int
@export var amount_eagle: int ## eagle or better
@export var second_pop_delay: float ## s: birdie and better pop a second time
@export var second_pop_share: float ## of the first burst's pieces
@export var launch_speed: Vector2 ## m/s up out of the hole, min..max
@export var spread_deg: float
@export var gravity: float ## m/s² (light, so they flutter)
@export var drift: float ## 1/s air drag on the pieces
@export var spin_deg: Vector2 ## °/s each piece turns, min..max
@export var lifetime: float ## s from the pop to gone; most of it lying on the green
@export var fade: float ## of the lifetime at the end over which they fade

@export_group("Ding")
@export var applause_volume_db: PackedFloat32Array ## hole-in applause, by result: over par, par, birdie, eagle or better

@export_group("Flag")
@export var flag_hop: float ## m the flagstick hops when the ball drops
@export var flag_hops: int ## bounces before it settles
@export var flag_time: float ## s

@export_group("Slow motion")
@export var slowmo_scale: float ## time scale for an eagle or better, offline
@export var slowmo_time: float ## s (real time) of slow motion on the drop
