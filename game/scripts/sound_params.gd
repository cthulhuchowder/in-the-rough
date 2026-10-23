class_name SoundParams
extends Resource
## Which sound each event plays, and how loud. Values (and the files: game/audio/, Kenney CC0, see
## THIRD_PARTY.md) live in data/sounds.tres: swap a file there to change a sound. The comedy sounds
## (applause, the whiff's swish, the goose, squeaks, the fish slap, crows, clown steps) are still
## PlaceholderSounds'.

@export_group("Clubs")
@export var club_driver: AudioStream
@export var club_iron: AudioStream
@export var club_wedge: AudioStream
@export var putter: AudioStream ## a soft wooden knock
@export_group("Ball")
@export var land_fairway: AudioStream ## the fairway and the green
@export var land_rough: AudioStream
@export var land_sand: AudioStream
@export var hit_tree: AudioStream ## trees, logs, stumps, fences: wood
@export var hit_stone: AudioStream ## rocks, gravestones, coral and the like
@export var cup_rattle: AudioStream ## the ball on the lip
@export var cup_drop: AudioStream ## the ball falls in
@export var land_db: Vector2 ## dB of a landing or a hit: at land_slow m/s and at land_fast and over
@export var land_speeds: Vector2 ## m/s: (slow, fast); slower than slow is silent
@export var cup_db: float
@export var rattle_gap: float ## s at least between two knocks on the lip (riding it is many contacts)
@export var ball_unit_size: float ## m: the ball's sounds are at full volume this close, fading further off
@export_group("Interface")
@export var ui_hover: AudioStream
@export var ui_click: AudioStream
@export var ui_back: AudioStream
@export var shop_buy: AudioStream
@export var shop_equip: AudioStream
@export var coin: AudioStream ## the coins for a hole (+N)
@export var chat: AudioStream
@export var scorecard: AudioStream
@export var ui_db: float ## hover, click and back
@export var shop_db: float
@export var scorecard_db: float
@export_group("Buses")
@export var sfx_bus_db: float ## the SFX bus's trim, under the settings slider
@export var clubs_bus_db: float ## the Clubs bus's (into SFX)
@export var limiter_ceiling_db: float ## Master: a hard limiter so stacked sounds never clip


## The hit sound for this club.
func club(model: ClubData.Model) -> AudioStream:
	match model:
		ClubData.Model.DRIVER:
			return club_driver
		ClubData.Model.WEDGE:
			return club_wedge
		ClubData.Model.PUTTER:
			return putter
	return club_iron
