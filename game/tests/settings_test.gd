extends SceneTree
## Settings and the Esc menu: each club class takes its own sensitivity (the feeder's swing angle
## scales with it), invert vertical flips pitch, volumes reach the audio buses, Esc opens the menu
## (swing blocked, paused offline) and closes it again; R re-addresses, the menu resets to the tee.
## Script runs ignore the saved file.
## Run: godot --headless --path game -s res://tests/settings_test.gd

var _failed := false


func _initialize() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	main.random_course = false
	root.add_child(main)
	await physics_frame
	var swing: Swing = main.get_node("Swing")
	var feeder: MouseSwingFeeder = main.get_node("MouseSwingFeeder")
	var gesture := swing.gesture
	var settings: Node = root.get_node("Settings") # autoload names aren't known when a -s script compiles
	_check(settings.sensitivity_woods == 1.0 and settings.sensitivity_irons == 1.0 and settings.sensitivity_putter == 1.0,
		"defaults (script runs ignore the saved file)")

	# Per club class
	var clubs := main.CLUBS as Array
	settings.sensitivity_woods = 0.5
	settings.sensitivity_irons = 1.5
	settings.sensitivity_putter = 2.5
	var classes := [[0, 0.5], [5, 1.5], [9, 1.5], [10, 2.5]] # driver, 7 iron, sand wedge, putter
	var all := true
	for c in classes:
		swing.club = clubs[c[0]]
		feeder.add_motion(Vector2(-10, 0))
		feeder._physics_process(1.0 / 120.0)
		var want: float = 10.0 * swing.feel.mouse_to_angle * c[1]
		all = all and absf(gesture.angle_delta - want) < 1e-6
	_check(all, "the swing angle per pixel scales with the club class's slider (woods / irons & wedges / putter)")

	# Invert vertical
	settings.invert_vertical = false
	feeder.add_motion(Vector2(0, 10))
	feeder._physics_process(1.0 / 120.0)
	var plain := gesture.pitch_delta
	settings.invert_vertical = true
	feeder.add_motion(Vector2(0, 10))
	feeder._physics_process(1.0 / 120.0)
	_check(plain != 0.0 and is_equal_approx(gesture.pitch_delta, -plain), "invert vertical flips pitch")
	settings.invert_vertical = false

	# Volumes
	settings.change("sfx_volume", 0.5)
	var sfx := AudioServer.get_bus_index(settings.SFX_BUS)
	_check(sfx > 0 and is_equal_approx(AudioServer.get_bus_volume_db(sfx), linear_to_db(0.5) + settings.SOUNDS.sfx_bus_db), "SFX volume reaches its bus (with the bus trim)")
	settings.change("sfx_volume", 1.0)

	# Shadow quality reaches the sun: cascades 1 / 2 / 4 for low / medium / high
	var sun: DirectionalLight3D = main.get_tree().get_first_node_in_group("sun")
	var modes := []
	for q in 3:
		settings.change("shadow_quality", q)
		modes.append(sun.directional_shadow_mode)
	_check(sun != null and modes == [DirectionalLight3D.SHADOW_ORTHOGONAL, DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
		DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS], "shadow quality low / medium / high sets the sun's cascades (%s)" % [modes])

	# Walk camera zoom: the wheel (gesture.zoom) sets the saved distance, clamped to walk_zoom_range
	var walker: Walker = main.get_node("Walker")
	var zooms := []
	for notch in [-5.0, 40.0, -60.0]:
		gesture.zoom = notch
		walker._physics_process(1.0 / 120.0)
		zooms.append(snappedf(settings.walk_zoom, 0.01))
	gesture.zoom = 0.0
	var range: Vector2 = main._swing.feel.walk_zoom_range
	_check(zooms[0] > 3.5 and zooms[1] == range.x and zooms[2] == range.y, "mouse wheel zooms the walk camera, %.0f–%.0f m, into the settings (%s)" % [
		range.x, range.y, zooms])
	settings.walk_zoom = 3.5

	# Esc menu
	var menu: Control = main._menu
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	await process_frame
	_check(menu.visible and gesture.blocked and paused, "Esc opens the menu: swing blocked, game paused (offline)")
	esc = esc.duplicate() # a fresh event: the engine won't take the same one twice
	Input.parse_input_event(esc)
	await process_frame
	_check(not menu.visible and not gesture.blocked and not paused, "Esc again closes it and resumes")
	# R re-addresses: swing back at address, ball and strokes untouched; Reset to tee is in the menu
	var ball: Ball = main.get_node("Ball")
	var at := ball.global_position
	var shots: int = main.strokes
	swing.angle = -1.2
	swing.pitch = 0.3
	var r := InputEventKey.new()
	r.keycode = KEY_R
	r.pressed = true
	Input.parse_input_event(r)
	await process_frame
	_check(swing.angle == swing.feel.address_angle and swing.pitch == 0.0 and ball.global_position == at and main.strokes == shots,
		"R re-addresses the swing; the ball and the stroke count stay")
	var reset: Button = null
	for b in menu.find_children("*", "Button", true, false):
		if b.text == "Reset to tee":
			reset = b
	ball.place(at + Vector3(3.0, 0.0, 0.0))
	reset.pressed.emit()
	await process_frame
	_check(reset.visible and ball.global_position.distance_to(at) < 0.01 and not menu.visible,
		"the menu's Reset to tee (offline) puts the ball back on the tee")
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	_failed = _failed or not ok
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
