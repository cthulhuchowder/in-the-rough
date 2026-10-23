class_name SoundscapeParams
extends Resource
## The biome soundscapes' shared numbers (Soundscape). Values in data/soundscape.tres.

@export var unit_size: float ## m: a one-shot is at its own volume this close, fading further off
@export var max_distance: float ## m: past this, silent
@export var water_reach: float ## m: the water loop is searched for within this of the player
@export var water_unit_size: float ## m
@export var water_search_every: float ## s between looks for the nearest water
@export var duck_db: float ## the Ambience bus, under a hole-in celebration
@export var duck_in: float ## s to duck
@export var duck_out: float ## s back up, after the celebration's sound
@export var fade_in: float ## s the bed fades up on a new hole
