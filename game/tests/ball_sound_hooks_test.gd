extends SceneTree
## The ball's sound hooks fire in play, with the right sound. Each surface's landing (fairway and
## green, rough, sand; water silent) and each prop's (a tree knocks like wood, a rock and a gravestone
## clack like stone, by the shape Flora tags its collider with). A drive lands and bounces with
## sound; a soft putt drops into the cup; a quick one off-centre knocks on the lip.
## Run: godot --headless --fixed-fps 120 --path game -s res://tests/ball_sound_hooks_test.gd

const SOUNDS: SoundParams = preload("res://data/sounds.tres")

var _failed := false
var _main: Node
var _ball: Ball


func _check(ok: bool, what: String) -> void:
	_failed = _failed or not ok
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])


func _initialize() -> void:
	var s := func(name: String) -> SurfaceData: return load("res://data/surfaces/%s.tres" % name)
	var sounds := load("res://scripts/ball_sounds.gd")
	_check(sounds.sound_for(s.call("fairway"), -1) == SOUNDS.land_fairway and sounds.sound_for(s.call("green"), -1) == SOUNDS.land_fairway
		and sounds.sound_for(s.call("rough"), -1) == SOUNDS.land_rough and sounds.sound_for(s.call("sand"), -1) == SOUNDS.land_sand
		and sounds.sound_for(s.call("water"), -1) == null and sounds.sound_for(s.call("out_of_bounds"), -1) == SOUNDS.land_rough,
		"landings: fairway and green thud, rough a duller one, sand crunches, water silent")
	var shape_of := func(prop: String) -> int:
		var kind: PropKind = load("res://data/props/%s.tres" % prop)
		var body := Flora.build(kind, kind.sizes[0], 1, 0.0, s.call("rough"))
		var tagged := int(body.get_meta("shape", -1))
		body.free()
		return tagged
	var tree: int = shape_of.call("round_tree")
	var rock: int = shape_of.call("rock")
	var grave: int = shape_of.call("gravestone")
	_check(sounds.sound_for(null, tree) == SOUNDS.hit_tree and sounds.sound_for(null, rock) == SOUNDS.hit_stone and sounds.sound_for(null, grave) == SOUNDS.hit_stone,
		"props, by their tagged shape: a tree knocks like wood, a rock and a gravestone clack like stone")

	_main = load("res://main.tscn").instantiate()
	_main.random_course = false
	root.add_child(_main)
	_ball = _main.get_node("Ball")
	for i in 5:
		await physics_frame
	_main.load_hole(load("res://holes/test_hole.tscn").instantiate())
	await physics_frame
	var heard := []
	_ball.bounced.connect(func(surface: SurfaceData, speed: float, shape: int) -> void:
		if speed >= SOUNDS.land_speeds.x and sounds.sound_for(surface, shape) != null:
			heard.append("%s %.0f m/s" % [surface.resource_name, speed]))
	await _drive()
	_check(heard.size() >= 1, "a drive: %d landings and bounces with sound (first %s)" % [heard.size(), heard[0] if not heard.is_empty() else "none"])

	var drops := [0]
	var rattles := [0]
	_ball.dropped.connect(func() -> void: drops[0] += 1)
	_ball.rim_hit.connect(func(_v: float) -> void: rattles[0] += 1)
	await _putt(1.0, 0.0)
	var dropped: int = drops[0]
	for offset in [0.8, 0.95]:
		for speed in [3.0, 4.0]:
			await _putt(speed, offset)
	_check(dropped >= 1 and rattles[0] >= 1, "the cup: a soft putt drops in (%d), quick ones off-centre knock on the lip (%d)" % [dropped, rattles[0]])
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _drive() -> void:
	_main.restart()
	_main.select_club(0)
	for i in 10:
		await physics_frame
	var feeder: MouseSwingFeeder = _main.get_node("MouseSwingFeeder")
	for k in 40:
		feeder.add_motion(Vector2(20, 0))
		await physics_frame
	var k := 0
	while not _main._swing.has_hit and k < 400:
		feeder.add_motion(Vector2(-40, 0))
		await physics_frame
		k += 1
	for t in 120 * 12:
		await physics_frame
		if not _ball.in_play:
			break


## A putt along −Z from 0.4 m short of the cup, `offset` × cup radius across, arriving near `speed`.
func _putt(speed: float, offset: float) -> void:
	var hole: Hole = _main._hole
	var feel: SwingFeel = _ball.feel
	_main.restart()
	await physics_frame
	_ball.place(hole.rest_point(hole.cup.global_position + Vector3(offset * feel.cup_radius, 0.0, 0.4), Ball.RADIUS))
	await physics_frame
	var putter: ClubData = _main.CLUBS[10]
	_ball.launch(Vector3.FORWARD, 0.0, speed / (putter.strength * putter.power_mul * putter.smash), putter, Vector3.BACK)
	for t in 120 * 4:
		await physics_frame
		if not _ball.in_play:
			break
