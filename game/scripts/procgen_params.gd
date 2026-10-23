class_name ProcgenParams
extends Resource
## Hole generator tunables. Values live in data/procgen.tres.
## Distances are in map pixels unless marked m. Ranges are Vector2(min, max).

@export var default_course_seed: int
@export var holes_per_course: int
@export var par3_per_nine: int
@export var par4_per_nine: int
@export var par5_per_nine: int

@export_group("Grid")
@export var grid_size: int
@export var metres_per_px: float

@export_group("Layout")
@export var depth_par3: Vector2i ## half the front→back length
@export var depth_par4: Vector2i
@export var depth_par5: Vector2i
@export var lateral_par3: Vector2i ## dogleg: green sideways offset
@export var lateral_par4: Vector2i
@export var lateral_par5: Vector2i
@export var tee_behind_front: int
@export var playable_tail: int ## corridor behind the tee
@export var junction_margin_par3: Vector2 ## junction y ∈ [c−d+x, c+d−y]
@export var junction_margin_par4: Vector2
@export var junction_margin_par5: Vector2
@export var cup_offset_par3: Vector2
@export var cup_offset_long: Vector2
@export var cup_turn_tan_half: float ## tan(max cup turn / 2); turn drawn as a rational rotation, no trig
@export var par3_straight_fairway_below: float
@export var curve_tension: float
@export var curve_steps: int ## Bézier samples per segment

@export_group("Widths")
@export var fairway_width_base: float
@export var fairway_width_amp: float
@export var fairway_width_freq: float
@export var bunker_radius_base: float
@export var bunker_radius_amp: float
@export var bunker_radius_freq: float
@export var green_width_base: float
@export var green_width_amp: float
@export var green_width_freq: float
@export var rough_falloff: float
@export var oob_threshold: float
@export var surface_threshold: float

@export_group("Bunkers")
@export var fairway_bunkers: Vector2i
@export var green_bunkers: Vector2i
@export var fairway_bunker_t: Vector2
@export var fairway_bunker_offset: float
@export var green_bunker_turn_tan_half: float ## tan(max arc / 2)
@export var bunker_depth_m: float ## sand sunk by this × (B − 0.5)

@export_group("Height")
@export var base_amp_par3: Vector2 ## m
@export var base_amp_long: Vector2 ## m
@export var world_freq: float
@export var world_octaves: int
@export var world_gain: float
@export var mountain_up: Vector2 ## m
@export var mountain_down: Vector2 ## m
@export var green_break_amp: float ## m
@export var green_break_freq: float
@export var green_flatten_pad: float
@export var green_flatten_radius: float ## polynomial falloff standing in for exp(−d²/50)
@export var tee_pad_half: Vector2
@export var tee_pad_falloff: float
@export var water_margin: float ## m below the lowest playable or sand pixel

@export_group("Trees")
@export var tree_min_spacing: float ## m between trunks
@export var tree_clearance_fairway: float ## m from fairway and water: trees line the fairway edges
@export var tree_clearance_green: float ## m from the green
@export var corridor_width := Vector2(25.0, 15.0) ## m: the line of play kept free of trees and big props, wide at the tee .. at the green (Procgen._corridor)
@export var corridor_canopy := 1.3 ## trees keep this many canopy radii (their size's y) further out than the corridor's edge, so no branch hangs into it
@export var corridor_big_prop := 0.9 ## m: props this wide or more (and logs, stumps) keep out of it; smaller ones may stand in it
@export var tree_clearance_tee: float ## m from the tee pad
@export var tree_tries: int ## placement attempts per tree
@export var tree_sink: float ## m of trunk below the ground, so slopes never expose its base
@export var tree_surface: SurfaceData ## restitution the ball bounces off trunks and rocks with
@export var biomes: Array[Biome] = [] ## a course picks one from its seed; species, props and palette live there

@export_group("Surfaces")
@export var fairway: SurfaceData
@export var rough: SurfaceData
@export var green: SurfaceData
@export var sand: SurfaceData
@export var water: SurfaceData
@export var out_of_bounds: SurfaceData
@export var grass_noise: float ## how far grass colors drift lighter or darker (visual only)
@export var grass_noise_freq: float ## cycles per pixel of the grass variation
@export var stripe_width: float ## m, fairway mower stripes, alternating light/dark across the hole axis (visual only)
@export var stripe_shade: float ## lighter / darker by this
@export var mottle_size: float ## m, rough mottling blob scale (visual only)
@export var mottle_shade: float ## per tone step (three flat tones)
@export var checker_size: float ## m, green checker squares (visual only)
@export var checker_shade: float

@export_group("Wind")
@export var wind_max: float ## m/s, the strongest a hole can blow
