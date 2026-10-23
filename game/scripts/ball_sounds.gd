class_name BallSounds
extends Node3D
## The player's own ball's sounds, riding on it: each landing and bounce by what it meets (the
## fairway and green a thud, the rough a duller one, sand a soft crunch, water silent; a tree or log
## knocks like wood, a rock or gravestone clacks like stone), louder the harder it comes down; the
## cup's lip rattling and the drop in. Files and volumes in data/sounds.tres. Never on the server.

const SOUNDS: SoundParams = preload("res://data/sounds.tres")
const STONE := [PropKind.Shape.ROCK, PropKind.Shape.MOSSY_ROCK, PropKind.Shape.GRAVESTONE, PropKind.Shape.MAUSOLEUM,
	PropKind.Shape.BRAIN, PropKind.Shape.STAGHORN, PropKind.Shape.CORAL, PropKind.Shape.CORAL_CLUSTER, PropKind.Shape.CORAL_ARCH,
	PropKind.Shape.TUBE, PropKind.Shape.SHELL, PropKind.Shape.STARFISH] ## props that clack; the rest knock like wood

var _land := AudioStreamPlayer3D.new()
var _cup := AudioStreamPlayer3D.new()
var _rattled_at := -INF # s: the last knock on the lip


func _init(ball: Ball) -> void:
	for player in [_land, _cup]:
		player.bus = Settings.SFX_BUS
		player.unit_size = SOUNDS.ball_unit_size
		add_child(player)
	ball.bounced.connect(_on_bounce)
	ball.rim_hit.connect(_on_rim)
	ball.dropped.connect(func() -> void: _play(_cup, SOUNDS.cup_drop, SOUNDS.cup_db))


## A knock on the lip, no closer than rattle_gap to the last (riding it is a contact every tick).
func _on_rim(_speed: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _rattled_at >= SOUNDS.rattle_gap:
		_rattled_at = now
		_play(_cup, SOUNDS.cup_rattle, SOUNDS.cup_db)


func _on_bounce(surface: SurfaceData, speed: float, shape: int) -> void:
	if speed < SOUNDS.land_speeds.x:
		return
	var stream := sound_for(surface, shape)
	if stream:
		var t := inverse_lerp(SOUNDS.land_speeds.x, SOUNDS.land_speeds.y, minf(speed, SOUNDS.land_speeds.y))
		_play(_land, stream, lerpf(SOUNDS.land_db.x, SOUNDS.land_db.y, t))


## What a bounce off this sounds like: a prop by its shape (−1: the ground), the ground by its
## surface (null: water, silent).
static func sound_for(surface: SurfaceData, shape: int) -> AudioStream:
	if shape >= 0:
		return SOUNDS.hit_stone if shape in STONE else SOUNDS.hit_tree
	if surface == null or surface.hazard == SurfaceData.Hazard.WATER:
		return null
	var name := surface.resource_name.to_lower()
	if "sand" in name:
		return SOUNDS.land_sand
	if "fairway" in name or "green" in name:
		return SOUNDS.land_fairway
	return SOUNDS.land_rough


func _play(player: AudioStreamPlayer3D, stream: AudioStream, db: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	player.stream = stream
	player.volume_db = db
	player.play()
