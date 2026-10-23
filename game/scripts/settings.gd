extends Node
## Player settings (autoload "Settings"): mouse sensitivity per club class, volumes, invert
## vertical, debug HUD, the last room rules hosted with, shadow quality, walk zoom, auto caddy. Applied the moment they change and saved
## to user://settings.json.
## When the game runs a script (tests, art captures) the saved file is ignored: defaults only,
## so a player's own settings never change what a test measures.

const PATH := "user://settings.json"
const SFX_BUS := "SFX"
const CLUBS_BUS := "Clubs" ## club hits (their own bus), into SFX
const AMBIENCE_BUS := "Ambience" ## the biome soundscapes (Soundscape), into Master; its own slider
const SOUNDS: SoundParams = preload("res://data/sounds.tres") ## the buses' trims and the limiter

var sensitivity_woods := 1.0 ## driver and woods
var sensitivity_irons := 1.0 ## irons and wedges
var sensitivity_putter := 1.0
var master_volume := 1.0 ## 0..1
var sfx_volume := 1.0 ## 0..1
var ambience_volume := 1.0 ## 0..1: the biome soundscapes
var invert_vertical := false
var show_debug := false ## F3
var room_rules := {} ## the rules this player last hosted with (RoomRules), offered again next time
var shadow_quality := 2 ## 0 low, 1 medium, 2 high: the sun's shadow map size and cascades
var walk_zoom := 3.5 ## m: the walk camera's distance, as last zoomed with the mouse wheel
var auto_caddy := true ## a club is picked for each new lie (distance to the pin against each club's carry)
var player_name := "" ## the name on the menu's profile chip ("": Player)

const KEYS := ["sensitivity_woods", "sensitivity_irons", "sensitivity_putter", "master_volume", "sfx_volume",
	"invert_vertical", "show_debug", "room_rules", "shadow_quality", "walk_zoom", "auto_caddy", "player_name", "ambience_volume"]


func _ready() -> void:
	if not _running_script():
		var text := FileAccess.get_file_as_string(PATH)
		var saved: Variant = JSON.parse_string(text) if text != "" else null
		if saved is Dictionary:
			for key in KEYS:
				if saved.has(key):
					set(key, type_convert(saved[key], typeof(get(key))))
	apply()


## The swing's mouse sensitivity for `club`: its class's slider.
func sensitivity_for(club: ClubData) -> float:
	match club.model:
		ClubData.Model.DRIVER:
			return sensitivity_woods
		ClubData.Model.PUTTER:
			return sensitivity_putter
		_:
			return sensitivity_irons


## Set one setting, apply it and save.
func change(key: String, value: Variant) -> void:
	set(key, value)
	apply()
	save()


## Per shadow_quality: [shadow map px, DirectionalLight3D shadow mode (cascades: 1 / 2 / 4 — the engine
## has no 3)].
const SHADOW_LEVELS := [[1024, DirectionalLight3D.SHADOW_ORTHOGONAL], [2048, DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS],
	[4096, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS]]


func apply() -> void:
	apply_shadows()
	if AudioServer.get_bus_index(SFX_BUS) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, SFX_BUS)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	if AudioServer.get_bus_index(CLUBS_BUS) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, CLUBS_BUS)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, SFX_BUS)
	if AudioServer.get_bus_index(AMBIENCE_BUS) < 0:
		AudioServer.add_bus()
		var at := AudioServer.bus_count - 1
		AudioServer.set_bus_name(at, AMBIENCE_BUS)
		AudioServer.set_bus_send(at, "Master")
		AudioServer.add_bus_effect(at, AudioEffectAmplify.new()) # (Soundscape.duck turns it down under a celebration)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(AMBIENCE_BUS), linear_to_db(maxf(ambience_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(SFX_BUS), linear_to_db(maxf(sfx_volume, 0.0001)) + SOUNDS.sfx_bus_db)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(CLUBS_BUS), SOUNDS.clubs_bus_db)
	if AudioServer.get_bus_effect_count(0) == 0: # Master: a limiter, so stacked sounds never clip
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db = SOUNDS.limiter_ceiling_db
		AudioServer.add_bus_effect(0, limiter)


## The Ambience bus's duck (an amplifier Soundscape tweens); null before apply().
func ambience_duck() -> AudioEffectAmplify:
	var at := AudioServer.get_bus_index(AMBIENCE_BUS)
	return AudioServer.get_bus_effect(at, 0) as AudioEffectAmplify if at >= 0 and AudioServer.get_bus_effect_count(at) > 0 else null


## The sun (group "sun") and the shadow atlas at shadow_quality. Main calls it again once a scene's
## sun is in the tree.
func apply_shadows() -> void:
	var level: Array = SHADOW_LEVELS[clampi(shadow_quality, 0, SHADOW_LEVELS.size() - 1)]
	RenderingServer.directional_shadow_atlas_set_size(level[0], true)
	if is_inside_tree():
		for sun in get_tree().get_nodes_in_group("sun"):
			(sun as DirectionalLight3D).directional_shadow_mode = level[1]


func save() -> void:
	if _running_script():
		return
	var out := {}
	for key in KEYS:
		out[key] = get(key)
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(out, "\t"))


static func _running_script() -> bool:
	var args := OS.get_cmdline_args()
	return args.has("-s") or args.has("--script")
