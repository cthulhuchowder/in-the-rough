class_name ArtPreset
extends Node3D
## A look for one scene: its children carry the sky, ambient and fog (WorldEnvironment) and the
## sun (DirectionalLight3D); these exports are the vertex-color palette. Look-development only:
## the game does not use presets yet.

@export_group("Ground")
@export var fairway: Color
@export var rough: Color
@export var green: Color
@export var sand: Color
@export var water: Color
@export var out_of_bounds: Color
@export var tee: Color
@export var water_alpha: float
@export var face_jitter: float ## ± brightness per terrain face, for the low-poly facet look

@export_group("Trees")
@export var trunk: Color
@export var canopy: Color
@export var canopy_alt: Color

@export_group("Golfer")
@export var shirt: Color
@export var pants: Color
@export var skin: Color
@export var cap: Color
@export var club: Color

@export_group("Pin")
@export var flag: Color
@export var pole: Color
@export var cup: Color
@export var ball: Color
