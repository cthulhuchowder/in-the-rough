class_name PropKind
extends Resource
## One kind of tree or prop a biome scatters: its low-poly shape, size variants and colors.
## Values live in data/props/*.tres. Trees and bushes have soft foliage the ball can pass through
## (heavily damped); trunks and rocks are solid.

enum Shape { ROUND_TREE, CONIFER, BUSHY_TREE, BUSH, ROCK, CACTUS, BURNT_TREE, MUSHROOM, CORAL, TUMBLEWEED, LOG, STUMP, PALM,
	STAGHORN, BRAIN, SEA_FAN, TUBE, ANEMONE, KELP, STARFISH, SHELL,
	REDWOOD, FERN, FLOWER, MOSS, MOSSY_ROCK, BARREL, PRICKLY_PEAR, DESERT_SHRUB, CORAL_CLUSTER, CORAL_ARCH,
	GRAVESTONE, MAUSOLEUM, FENCE, GNARLED_TREE, PUMPKIN }
## Undergrowth: the shapes scattered through the forest as bushes are (Procgen._undergrowth).
const UNDERGROWTH := [Shape.BUSH, Shape.FERN, Shape.DESERT_SHRUB]

@export var shape: Shape
## Size variants, m: x = trunk height (trees; 0 for bushes and rocks), y = foliage / rock radius.
## Cactus: x height, y arm reach; burnt tree: x height, y branch reach; mushroom: x stem, y cap
## radius; coral: x height, y spread; tumbleweed: y radius; log: x length, y radius; stump: x
## height, y radius.
## Reef: staghorn x height, y spread; brain x height, y radius; sea fan x height, y width; tube x
## height, y cluster radius; anemone x tentacle length, y column radius; kelp x height, y blade width;
## starfish / shell y radius.
## Detail: redwood as a tree; fern / moss / desert shrub / mossy rock y radius; flower x stem, y
## head radius; barrel x height, y radius; prickly pear y pad radius.
## Reef formations (as trees): coral cluster x height, y spread; coral arch x height, y span
## (trunk_radius: its pillars' girth).
## Cemetery: gravestone x height, y width; mausoleum (as a tree, placed as a formation) x height, y
## width; fence (a run along a fairway edge, Procgen._fence_line) x length, y height; gnarled tree as a
## tree; pumpkin y radius (glow > 0: a jack-o'-lantern, carved and lit).
@export var sizes: Array[Vector2] = []
@export var trunk_radius: float ## m, at the base (trees)
@export var color: Color ## foliage, or the rock
@export var trunk_color: Color
@export var glow: float ## > 0: parts of it glow (mushroom caps on some, flower petals), this bright
@export var moss_color := Color(0.36, 0.5, 0.26) ## mossy rock: its moss
@export var flicker := 0.0 ## 0..1: its glow flickers this much (a candle in a jack-o'-lantern)
@export var hue_jitter: float ## each one's hue shifts up to ± this (0..1 of the wheel), from the hole seed
@export var value_jitter: float ## and its brightness up to ± this
@export var weight := 1.0 ## trees: how often the biome picks this species
@export var per_km2: float ## props: how many per km² of allowed rough, scattered singly
@export var palette := PackedColorArray() ## if set, each one takes one of these (from the biome's palette) before its jitter
@export var near_water: float ## props: m; if > 0 only placed within this of water (palms)
@export var cluster := Vector2i.ZERO ## props: this many more (min..max) placed round each one, a stand
@export var cluster_radius: float ## m

@export_group("Variety (trees)")
@export var height_range := Vector2.ONE ## per-tree height scale, min..max (the mean of two draws: biased to the middle)
@export var width_range := Vector2.ONE ## per-tree canopy width scale, min..max, independent of height
@export var trunk_range := Vector2.ONE ## per-tree trunk height scale on top of that: canopies sitting low or high
