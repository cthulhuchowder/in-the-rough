extends SceneTree
## Auto caddy. The four rules, in order: on the green the putter; in sand the sand wedge; a hole's
## first shot may get the driver if the pin is beyond every other club's carry, otherwise never the
## driver; else the club whose carry for the lie is closest to but not less than the distance (the
## longest non-driver if none reaches). In the game: a new lie picks it even
## while the follow camera still runs after a shot (it used to be refused there; the chip pulses), and a re-address
## keeps the player's own switch.
## Run: godot --headless --fixed-fps 120 --path game -s res://tests/caddy_test.gd

var _failed := false


func _check(ok: bool, what: String) -> void:
	_failed = _failed or not ok
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])


func _initialize() -> void:
	var clubs: Array = Clubs.ALL
	var fairway: SurfaceData = load("res://data/surfaces/fairway.tres")
	var rough: SurfaceData = load("res://data/surfaces/rough.tres")
	var sand: SurfaceData = load("res://data/surfaces/sand.tres")
	var green: SurfaceData = load("res://data/surfaces/green.tres")
	var pick := func(lie: SurfaceData, d: float, first: bool) -> String: return clubs[Clubs.caddy_pick(clubs, lie, d, first)].label
	var three: float = clubs[1].carry_for(fairway) # the longest non-driver
	var seven: float = clubs[5].carry_for(fairway)
	var got := [pick.call(green, 30.0, false), pick.call(green, 300.0, true)]
	_check(got == ["P", "P"], "1. on the green: putter (%s)" % [got])
	got = [pick.call(sand, 10.0, false), pick.call(sand, 150.0, true)]
	_check(got == ["SW", "SW"], "2. in sand: sand wedge, near or far, even off the tee (%s)" % [got])
	got = [pick.call(fairway, three + 30.0, true), pick.call(fairway, three - 5.0, true), pick.call(fairway, three + 30.0, false)]
	_check(got == ["D", "3I", "3I"], "3. driver only on a first shot past every other carry (%.0f m); a short tee shot or a later long one never (%s)" % [three, got])
	got = [pick.call(fairway, seven - 1.0, false), pick.call(fairway, seven, false), pick.call(fairway, seven + 1.0, false), pick.call(rough, 20.0, false)]
	_check(got == ["7I", "7I", "6I", "SW"], "4. closest carry not under the distance (7I carries %.0f m: −1 m, exact, +1 m; 20 m from rough) (%s)" % [seven, got])

	var main: Node = load("res://main.tscn").instantiate()
	main.random_course = false
	root.add_child(main)
	for i in 5:
		await physics_frame
	main.load_hole(load("res://holes/test_hole.tscn").instantiate()) # flat, with a bunker at (−14, −210)
	for i in 10:
		await physics_frame
	var settings: Node = root.get_node("Settings")
	_check(settings.auto_caddy, "the setting is on by default")
	var tee: String = main._swing.club.label
	var d: float = Vector2(main._hole.cup.global_position.x - main._ball.global_position.x, main._hole.cup.global_position.z - main._ball.global_position.z).length()
	_check(tee == pick.call(main._ball.lie, d, true), "hole start: picked %s for %.0f m" % [tee, d])
	# A shot has settled in the bunker; the follow camera is still running (Following, has_hit)
	main._first_shot = false
	main._swing.has_hit = true
	main._set_mode(main.Mode.FOLLOWING)
	main._ball.place(main._hole.rest_point(Vector3(-14, 0, -210), 0.05))
	main._address()
	var pulsing: bool = main._hud.pulse_tween != null and main._hud.pulse_tween.is_running()
	_check(main._swing.club.label == "SW" and main.mode == main.Mode.SHOOTING and pulsing,
		"after a shot settles in sand (following still): %s, chip pulsing %s" % [main._swing.club.label, pulsing])
	main.select_club(8)
	main._address() # re-addressing the same lie keeps the player's choice
	_check(main._swing.club.label == "PW", "the player's switch stays on a re-address (%s)" % main._swing.club.label)
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)
