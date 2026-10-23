class_name Biome
extends Resource
## A hole's look, light, relief and planting: per hole from the course seed or the room's pick
## (Procgen.course). Values live in
## data/biomes/*.tres. The palette colours the ground, the sky/fog/sun set the light; relief
## reshapes the terrain (never the physics); the tree set and props are what
## Procgen scatters on the rough (same deterministic placement rules for every biome).

enum Ambient { NONE, BUBBLES, EMBERS, FIREFLIES, WISPS }
enum OobPattern { PLAIN, RIPPLES, LEAF_LITTER, ASH, MOSS }

@export var name := "" ## id (Procgen, digests)
@export var display_name := "" ## the hole card's "Mystic forest"
@export var card_color := Color.WHITE ## the biome's name on the hole card
## This biome's light on a scene: the sky gradient, fog (and the low height fog, `water_y` the ground
## it lies over), the sun's angle, colour and strength. The game per hole and the menu's backdrop.
func light(e: Environment, sun: DirectionalLight3D, water_y := 0.0) -> void:
	if e:
		e.fog_enabled = fog_density > 0.0 or fog_height_density > 0.0
		e.fog_light_color = fog_color
		e.fog_density = fog_density
		e.fog_height_density = fog_height_density # (thick low fog: the cemetery)
		e.fog_height = water_y + fog_height
		e.fog_sun_scatter = fog_sun_scatter # (the deep forest's mist brightens toward the sun)
		var sky := e.sky.sky_material as ProceduralSkyMaterial if e.sky else null
		if sky:
			sky.sky_top_color = sky_top
			sky.sky_horizon_color = sky_horizon
			sky.ground_horizon_color = ground_horizon
			sky.ground_bottom_color = ground_bottom
	if sun:
		sun.rotation_degrees = Vector3(-sun_rotation.x, sun_rotation.y, 0.0)
		sun.light_color = sun_color
		sun.light_energy = sun_energy


@export_group("Palette")
@export var fairway_color: Color ## ground: fairway (and tee) tone
@export var rough_color: Color
@export var green_color: Color
@export var sand_color: Color
@export_group("Sky and light")
@export var sky_top: Color ## sky gradient, zenith…
@export var sky_horizon: Color ## …to the horizon
@export var ground_horizon: Color ## below the horizon
@export var ground_bottom: Color
@export var fog_color: Color
@export var fog_density: float ## 0 none; a trace keeps the far edge of the map soft
@export var fog_height_density: float ## > 0: thick fog lying low on the ground (height fog), this dense
@export var fog_height: float ## m above the hole's water level where the low fog thins out
@export var sun_rotation: Vector2 ## degrees: pitch (down from level), yaw
@export var sun_color: Color
@export var sun_energy: float
@export var ambient: Ambient ## particles in the air around the camera (visual only)
@export var soundscape: SoundscapeSet ## its ambient sound: the base loop, the water's, one-shots round the player (Soundscape)
@export var sun_bloom: float ## 0..: a soft screen glow round where the sun is (no beams)
@export var sun_bloom_color := Color.WHITE
@export var fog_sun_scatter: float ## 0..1: the mist brightens and warms toward the sun
@export var caustics: float ## 0..1: rippling light on the ground (underwater)
@export_group("Water")
@export var water_name := "Water" ## the hazard's name ("Water: +1", "Lava: +1")
@export var water_color: Color
@export var water_alpha: float
@export var water_glow: float ## emission energy (lava)
@export var water_bubbles := 0 ## spots on the water where bubbles rise now and then (the bog; BiomeLife)
@export var crows := 0 ## crows perched on gravestones near the line of play, flying off when a ball lands near (BiomeLife)
@export_group("Relief")
@export var relief_amp := 1.0 ## times the terrain's height amplitude (hills, mountains); 1: as parkland
@export var relief_freq := 1.0 ## times its noise frequency: higher is more rugged
@export var rivers := 0 ## winding water channels through the rough, alongside the hole
@export var river_width: float ## m
@export var river_offset: float ## m out from the fairway's edge
@export var pits: Vector2i ## small water (lava) pits in the rough near the fairway, min..max per hole: penalty lies
@export var pit_radius: float ## m
@export_group("Trees")
@export var trees: Array[PropKind] = [] ## species, picked by weight per tree
@export var groves_per_km2: float ## of allowed rough
@export var grove_size: Vector2i ## trees tried per grove
@export var grove_radius: float ## m
@export var grove_gap: float ## m at least between grove centres, so lines of play stay open
@export var tree_line_step: float ## m along the hole between tree-line slots, each side of the fairway
@export var tree_line_offset: Vector2 ## m out from the fairway's edge, min..max
@export var tree_line_gaps: float ## 0..1 of tree-line slots left empty
@export var landmark_chance: float ## 0..1 of trees near a dogleg or the green made a landmark
@export var landmark_scale: float ## a landmark's height scale
@export var landmark_radius: float ## m from the cup, or from a dogleg's bend, that counts as near
@export var landmark_bend_deg: float ## the route bends at least this much at its junction to count as a dogleg
@export var formation_count := Vector2i.ZERO ## major formations per hole, min..max: the species of weight 0 (Procgen._formations)
@export var formation_offset: Vector2 ## m out past the fairway's edge, min..max
@export var formation_spacing: float ## m at least between them
@export var fence_offset: Vector2 ## m out past the fairway's edge, min..max: fence runs (a FENCE prop kind)
@export var fence_gaps: float ## 0..1 of fence runs left out
@export var fence_clearance := 3.0 ## m a fence keeps from fairway and water (nearer than trees: it lines the rough's edge)
@export var tee_clear_ahead: float ## m in front of the tee along its aim kept free of trees and props (0: off)
@export var tee_clear_width: float ## m either side of the aim line
@export var tee_thin_radius: float ## m round the tee where trees are thinned
@export var tee_thin_keep: float ## 0..1 of the trees kept there
@export_group("Out-of-bounds forest")
@export var forest_inset: float ## m past the OB line where the forest starts
@export var forest_density: float ## its groves per km², times the rough's groves_per_km2
@export var forest_depth: float ## m deep from there (beyond it the fog hides it; trees there would only cost draws and colliders)
@export var forest_grove_radius: float ## m: tighter than grove_radius
@export var forest_tree_scale: float ## forest trees' height, times their drawn size
@export var forest_bushes_per_km2: float ## undergrowth bushes, of the biome's bush kinds
@export_group("Props")
@export var props: Array[PropKind] = [] ## bushes, rocks: each at its own per_km2
@export var prop_min_spacing: float ## m between props, and from tree trunks
@export_group("Grass tufts")
@export var tufts_per_m2: float ## short grass on the rough (visual only, no collision)
@export var tuft_color: Color
@export_group("Wild (out of bounds)")
@export var ob_props_scale := 3.0 ## out past the OB line every prop kind stands this many times as thick as on the rough
@export var oob_color: Color ## its ground
@export var oob_pattern: OobPattern ## its ground's pattern
@export var ob_fog_bands := 0 ## low soft fog lying over the out-of-bounds forest (visual)
@export_group("Grove rings and desert")
@export var grove_rings: float ## 0..1 of groves planted as a ring (fairy rings of mushrooms)
@export var rough_ripples: float ## 0..1: wind ripples drawn over the rough (dunes)
@export var mesas := 0 ## distant flat-topped rock formations far out in the haze (visual)
@export var mesa_color: Color
@export var heat_shimmer: float ## 0..1: the air over the ground wavers now and then (screen effect)
