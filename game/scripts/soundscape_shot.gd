class_name SoundscapeShot
extends Resource
## A one-shot in a biome's soundscape: one of its variants, every `interval` seconds or so, somewhere
## `distance` off round the player and `height` up, in 3D.

@export var streams: Array[AudioStream] = [] ## variants, one picked at random each time
@export var interval: Vector2 ## s between plays, min..max
@export var distance: Vector2 ## m from the player, min..max
@export var height: Vector2 ## m above the ground there, min..max (a bird up in a tree, a creak in a trunk)
@export var volume_db: float
@export var pitch: Vector2 = Vector2.ONE ## pitch scale, min..max, so no two are the same
