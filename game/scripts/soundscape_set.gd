class_name SoundscapeSet
extends Resource
## One biome's ambient bed (Soundscape): a looping base layer, a loop at the nearest water hazard,
## and one-shots now and then around the player. Files in game/audio/ambience/<biome>/ (rendered by
## art/soundscape_render.gd; a recording can replace any one by name). Values in
## data/soundscapes/<biome>.tres.

@export var base: AudioStream ## loops all the time, everywhere (not positional)
@export var base_db: float
@export var water: AudioStream ## loops at the nearest water (lava, bog…), heard as you come near it
@export var water_db: float
@export var shots: Array[SoundscapeShot] = []
