class_name FlyoverParams
extends Resource
## Hole flyover tunables. Values live in data/flyover.tres.

@export var duration: float ## s for the whole flight, one ease-in-out start to finish

@export_group("Path")
@export var back: float ## m behind the tee where it starts
@export var height: float ## m above the tee it flies at, start and fairway (one altitude: no bobbing)
@export var path_spacing: float ## m between the centreline points the splines run through
@export var orbit_radius: float ## m from the pin, orbiting it at the green
@export var orbit_height: float ## m above the pin
@export var orbit_degrees: float ## how far round the pin it goes
@export var orbit_blend: float ## m from the pin where the run leaves the centreline and curves into the orbit

@export_group("View")
@export var lookahead: float ## m further along the path it looks
@export var look_height: float ## m above the tee at the point it looks at down the fairway (sets the pitch)
@export var pin_blend: float ## s over which the view turns from ahead on the fairway onto the pin, done as the orbit starts
@export var hud_fade: float ## s the HUD fades back in after

@export_group("Card")
@export var card_fade: float ## s the hole card takes to fade in and out
@export var card_margin: float ## px at 1080p from the bottom-left corner
@export var card_font: int ## px at 1080p

@export_group("Opening hold")
@export var hold_fade: float ## s the black fades out over as the flight starts
@export var hold_budget_ms: float ## ms a frame the hole may spend building while held (the screen is black)

@export var loading_pulse: Vector2 ## "Loading..." opacity, min..max of its pulse during the hold
@export var loading_pulse_time: float ## s per pulse
