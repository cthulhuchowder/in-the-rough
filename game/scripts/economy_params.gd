class_name EconomyParams
extends Resource
## Coin rules (Economy). Values live in data/economy.tres.

@export var base_par3: int ## coins for holing a par 3
@export var base_par4: int
@export var base_par5: int
@export var under_par_per_stroke: int ## a birdie earns this once, an eagle twice…
@export var hole_in_one: int
@export var longest_drive: int ## the room's longest first shot on a par 4 or 5 (not into a hazard)
@export var closest_to_pin: int ## the room's closest par-3 tee shot that stays on the green
@export var offline_share: float ## single player (no server of its own) earns this share of each
@export var sync_cap: int ## the most offline coins taken over on a name's first online login
