extends SceneTree
## The HUD's shot number. A drive is hit on the first hole: the count (strokes) goes up at once,
## but the HUD keeps "Shot 1" through the flight, the roll and the next address; it turns to
## "Shot 2" only when the club goes back on the next swing. A reset to the tee shows Shot 1 at once.
## Run: godot --headless --fixed-fps 120 --path game -s res://tests/shot_count_test.gd

var _failed := false
var _main: Node


func _check(ok: bool, what: String) -> void:
	_failed = _failed or not ok
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])


func _initialize() -> void:
	_main = load("res://main.tscn").instantiate()
	_main.random_course = false
	root.add_child(_main)
	for i in 20:
		await physics_frame
	var feeder: Node = _main.get_node("MouseSwingFeeder")
	var swing: Node = _main.get_node("Swing")
	_main.select_club(0)
	await _frames(5)
	_check(_shot() == 1, "on the tee: Shot %d" % _shot())
	for i in 40:
		feeder.add_motion(Vector2(20, 0))
		await physics_frame
	var ticks := 0
	while not swing.has_hit and ticks < 300:
		feeder.add_motion(Vector2(-110, 20.0 if ticks % 2 == 0 else -20.0))
		await physics_frame
		ticks += 1
	await _frames(30)
	_check(_main.strokes == 1 and _shot() == 1, "in flight: 1 stroke counted, the HUD still says Shot %d" % _shot())
	var t := 0
	while not _main._ready_to_hit() and t < 120 * 40:
		await physics_frame
		t += 1
	await _frames(10)
	_check(_main._ready_to_hit() and _shot() == 1, "at rest, addressing the next shot: still Shot %d" % _shot())
	for i in 40:
		feeder.add_motion(Vector2(20, 0))
		await physics_frame
		if swing.angle < swing.feel.address_angle - swing.feel.stance_turn_window:
			break
	await _frames(2)
	_check(_shot() == 2, "the club goes back on the next swing (angle %.2f): Shot %d" % [swing.angle, _shot()])
	_main.restart()
	await _frames(5)
	_check(_main.strokes == 0 and _shot() == 1, "reset to the tee: Shot %d at once" % _shot())
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## The number on the HUD's shot pill.
func _shot() -> int:
	var text: String = _main._hud._line.text
	return int(text.get_slice("·", 0).trim_prefix("Shot ").strip_edges())
