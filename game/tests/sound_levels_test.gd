extends SceneTree
## Every event's sound is there, and none clips. Each one (data/sounds.tres) is played as the game
## plays it at its loudest (a club at full power, a landing at land_speeds' top, the UI at theirs) on
## its bus, one at a time, then the club hit, a hard landing, the coin and the scorecard all at once;
## the Master bus's output (every sample, captured after the buses' trims and the limiter) stays
## under 0 dBFS. Then each biome's ambience bed, everything in it at once, on the Ambience bus.
## Windowed (a real audio device): godot --path game -s res://tests/sound_levels_test.gd

const SOUNDS: SoundParams = preload("res://data/sounds.tres")
const FEEDBACK: FeedbackParams = preload("res://data/feedback.tres")

var _failed := false
var _capture := AudioEffectCapture.new() # on Master, after the limiter: what actually goes out


func _check(ok: bool, what: String) -> void:
	_failed = _failed or not ok
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])


func _initialize() -> void:
	root.get_node("Settings").apply()
	_capture.buffer_length = 2.0
	AudioServer.add_bus_effect(0, _capture)
	for i in 30: # (the audio device up before the first sound)
		await process_frame
	var clubs := Settings.CLUBS_BUS
	var sfx := Settings.SFX_BUS
	var top := FEEDBACK.hit_volume_db.y
	var events := [["club: driver", SOUNDS.club_driver, top, FEEDBACK.driver_hit_pitch.y, clubs], ["club: irons", SOUNDS.club_iron, top, FEEDBACK.hit_pitch.y, clubs],
		["club: wedges", SOUNDS.club_wedge, top, FEEDBACK.hit_pitch.y, clubs], ["putter", SOUNDS.putter, top, FEEDBACK.hit_pitch.y, clubs],
		["land: fairway, green", SOUNDS.land_fairway, SOUNDS.land_db.y, 1.0, sfx], ["land: rough", SOUNDS.land_rough, SOUNDS.land_db.y, 1.0, sfx],
		["land: sand", SOUNDS.land_sand, SOUNDS.land_db.y, 1.0, sfx], ["hit: tree", SOUNDS.hit_tree, SOUNDS.land_db.y, 1.0, sfx],
		["hit: stone", SOUNDS.hit_stone, SOUNDS.land_db.y, 1.0, sfx], ["cup: rattle", SOUNDS.cup_rattle, SOUNDS.cup_db, 1.0, sfx],
		["cup: drop", SOUNDS.cup_drop, SOUNDS.cup_db, 1.0, sfx], ["menu: hover", SOUNDS.ui_hover, SOUNDS.ui_db, 1.0, sfx],
		["menu: click", SOUNDS.ui_click, SOUNDS.ui_db, 1.0, sfx], ["menu: back", SOUNDS.ui_back, SOUNDS.ui_db, 1.0, sfx],
		["shop: buy", SOUNDS.shop_buy, SOUNDS.shop_db, 1.0, sfx], ["shop: equip", SOUNDS.shop_equip, SOUNDS.shop_db, 1.0, sfx],
		["coins +N", SOUNDS.coin, FEEDBACK.coin_clink_db, 1.0, sfx], ["chat", SOUNDS.chat, FEEDBACK.chat_blip_db, 1.0, sfx],
		["scorecard", SOUNDS.scorecard, SOUNDS.scorecard_db, 1.0, sfx]]
	_check(events.all(func(e: Array) -> bool: return e[1] != null), "every event has its sound (%d)" % events.size())
	var loudest := -INF
	var quiet := INF
	for e in events:
		var peak := -INF
		peak = await _peak([e])
		loudest = maxf(loudest, peak)
		quiet = minf(quiet, peak)
		print("        %-22s peak %6.1f dBFS" % [e[0], peak])
	var together := await _peak([events[0], events[4], events[16], events[18]])
	_check(quiet > -40.0, "every one audible: the quietest at its loudest setting %.1f dBFS" % quiet)
	_check(loudest < 0.0 and together < 0.0, "nothing clips: the loudest alone %.1f dBFS, the hit, a landing, the coins and the scorecard at once %.1f dBFS" % [loudest, together])
	# Each biome's bed on the Ambience bus: its base, its water and every one-shot at once (as loud as it gets)
	var beds := []
	for name in ["parkland", "oasis", "underwater", "magma", "mystic_forest", "deep_forest", "cemetery"]:
		var set: Resource = load("res://data/biomes/%s.tres" % name).soundscape
		var all := [[name, set.base, set.base_db, 1.0, "Ambience"], [name, set.water, set.water_db, 1.0, "Ambience"]]
		for shot in set.shots:
			all.append([name, shot.streams[0], shot.volume_db, 1.0, "Ambience"])
		var peak := -INF
		peak = await _peak(all)
		beds.append(peak)
		print("        ambience: %-14s peak %6.1f dBFS (everything at once)" % [name, peak])
	_check(beds.all(func(p: float) -> bool: return p > -40.0 and p < 0.0), "ambience: every biome's bed audible and never clipping, all of it at once (%.1f..%.1f dBFS)" % [beds.min(), beds.max()])
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


## The Master bus's peak (dBFS, either channel) while these [name, stream, db, pitch, bus] play together.
func _peak(events: Array) -> float:
	var players := []
	for e in events:
		var p := AudioStreamPlayer.new()
		p.stream = e[1]
		p.volume_db = e[2]
		p.pitch_scale = e[3]
		p.bus = e[4]
		root.add_child(p)
		players.append(p)
	_capture.clear_buffer()
	for p in players:
		p.play()
	var peak := 0.0
	var t := 0.0
	while t < 1.0: # (every output sample the Master bus made, after its limiter: whatever the frame rate)
		await create_timer(0.1).timeout
		t += 0.1
		for frame in _capture.get_buffer(_capture.get_frames_available()):
			peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	for p in players:
		p.queue_free()
	await create_timer(0.2).timeout
	return linear_to_db(peak) if peak > 0.0 else -200.0
