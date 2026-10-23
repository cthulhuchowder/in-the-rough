class_name Soundscape
extends Node3D
## The biome's ambient bed round the player (clients only), on the Ambience bus: its base loop, its
## one-shots each on its own random timer at a random spot round the listener (3D, fading with
## distance), and its water loop at the nearest water hazard (searched round the listener now and
## then; silent when none is near). Ducks under a hole-in celebration. The sets per biome in
## data/soundscapes/, shared numbers in data/soundscape.tres.

const PARAMS: SoundscapeParams = preload("res://data/soundscape.tres")
const DIRECTIONS := 24 ## the water search: this many bearings round the listener…
const RINGS := [3.0, 6.0, 10.0, 16.0, 24.0, 34.0, 45.0] ## …at these distances (m, within water_reach)

var bed: SoundscapeSet
var _hole: Hole
var _listener := Vector3.ZERO
var _base := AudioStreamPlayer.new()
var _water := AudioStreamPlayer3D.new()
var _timers: Array[float] = [] # s until each shot plays next
var _search := 0.0
var _duck: Tween


func _ready() -> void:
	_base.bus = Settings.AMBIENCE_BUS
	add_child(_base)
	_water.bus = Settings.AMBIENCE_BUS
	_water.unit_size = PARAMS.water_unit_size
	_water.max_distance = PARAMS.water_reach * 1.5
	add_child(_water)


## A new hole: this biome's bed (the same bed carries on without a restart), on `hole`.
func play(next: SoundscapeSet, hole: Hole) -> void:
	_hole = hole
	_search = 0.0
	if next == bed:
		return
	bed = next
	_base.stop()
	_water.stop()
	_timers.clear()
	if bed == null:
		return
	for shot in bed.shots:
		_timers.append(randf_range(shot.interval.x * 0.3, shot.interval.y)) # (the first ones soon, not all at once)
	if bed.base:
		_base.stream = _looping(bed.base)
		_base.volume_db = -60.0
		_base.play()
		create_tween().tween_property(_base, "volume_db", bed.base_db, PARAMS.fade_in)
	if bed.water:
		_water.stream = _looping(bed.water)
		_water.volume_db = bed.water_db


## Where the listener (the camera) is this frame.
func follow(listener: Node3D) -> void:
	_listener = listener.global_position


func _process(delta: float) -> void:
	if bed == null or _hole == null:
		return
	for k in bed.shots.size():
		_timers[k] -= delta
		if _timers[k] <= 0.0:
			var shot: SoundscapeShot = bed.shots[k]
			_timers[k] = randf_range(shot.interval.x, shot.interval.y)
			_one_shot(shot)
	_search -= delta
	if _search <= 0.0 and bed.water:
		_search = PARAMS.water_search_every
		var near := nearest_water(_hole, _listener)
		if near == Vector3.INF:
			_water.stop()
		else:
			_water.global_position = near
			if not _water.playing:
				_water.play()


func _one_shot(shot: SoundscapeShot) -> void:
	if shot.streams.is_empty():
		return
	var a := randf() * TAU
	var at := _listener + Vector3(cos(a), 0.0, sin(a)) * randf_range(shot.distance.x, shot.distance.y)
	at.y = _hole.height_at(at) + randf_range(shot.height.x, shot.height.y)
	var player := AudioStreamPlayer3D.new()
	player.bus = Settings.AMBIENCE_BUS
	player.stream = shot.streams[randi() % shot.streams.size()]
	player.volume_db = shot.volume_db
	player.pitch_scale = randf_range(shot.pitch.x, shot.pitch.y)
	player.unit_size = PARAMS.unit_size
	player.max_distance = PARAMS.max_distance
	add_child(player)
	player.global_position = at
	player.finished.connect(player.queue_free)
	player.play()


## The nearest water-hazard ground (water, lava, bog…) to `from` within water_reach, sampled on rings
## of bearings; INF when there is none.
static func nearest_water(hole: Hole, from: Vector3) -> Vector3:
	for r: float in RINGS:
		if r > PARAMS.water_reach:
			break
		var best := Vector3.INF
		for k in DIRECTIONS:
			var a := TAU * k / DIRECTIONS
			var p := from + Vector3(cos(a), 0.0, sin(a)) * r
			p.y = hole.height_at(p)
			var surface := hole.surface_at(p)
			if surface and surface.hazard == SurfaceData.Hazard.WATER and from.distance_to(p) < from.distance_to(best):
				best = p
		if best != Vector3.INF:
			return best # (the first ring with water in it is the nearest, to a ring's width)
	return Vector3.INF


## The Ambience bus ducks under a celebration for `seconds`, then comes back up.
func duck(seconds: float) -> void:
	var amp := Settings.ambience_duck()
	if amp == null:
		return
	if _duck:
		_duck.kill()
	_duck = create_tween()
	_duck.tween_property(amp, "volume_db", PARAMS.duck_db, PARAMS.duck_in)
	_duck.tween_interval(seconds)
	_duck.tween_property(amp, "volume_db", 0.0, PARAMS.duck_out)


## The same stream, looping end to end (the base_ and water_ files are rendered to loop seamlessly).
static func _looping(stream: AudioStream) -> AudioStream:
	if stream is AudioStreamWAV:
		var wav := (stream as AudioStreamWAV).duplicate() as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
		return wav
	return stream
