extends SceneTree
## The equipped ball skin stays on. Single player (the in-process server, as Play does) with the
## Meatball equipped: three shots, the first into water (a penalty: the ball comes back to a drop), then
## two more. Every frame of every shot — while the local prediction shows, once the server's copy of
## the ball takes over in flight, at rest, after the penalty's drop — the ball drawn is the Meatball.
## Run: godot --headless --path game -s res://tests/ball_skin_test.gd

var _failed := false


func _check(ok: bool, what: String) -> void:
	_failed = _failed or not ok
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])


func _initialize() -> void:
	OS.set_environment("GOLF_TEST_EQUIP", "ball_meatball") # (ShopCatalog.my_look: this run's player wears it)
	var skin := Ball.view_mesh_for(ShopCatalog.look_for({"ball": "ball_meatball"}))
	var net: Node = root.get_node("Net")
	var lobby: Node = load("res://lobby.tscn").instantiate()
	root.add_child(lobby)
	await process_frame
	lobby._play_local()
	var t := Time.get_ticks_msec()
	while not net.lobby.get(1, {}).get("ready", false) and Time.get_ticks_msec() - t < 5000:
		await process_frame
	net.set_rules.rpc_id(1, {"biome": 2, "holes": 1}) # oasis: its river and lakes
	await create_timer(0.3).timeout
	lobby._start.pressed.emit()
	var main: Node = null
	t = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < 30000:
		await process_frame
		main = current_scene if current_scene and current_scene.has_method("_bot_shot") else null
		if main and main._hole is GeneratedHole and not main._hole.is_building() and main._flyover == null and main.mode == 0:
			break
	if main == null:
		_check(false, "the round began and the golfer is at the ball")
		quit(1)
		return
	for i in 60:
		await process_frame
	var water := _water_spot(main)
	_check(water != Vector3.INF, "the hole has water in reach (%s)" % [water])
	var frames := 0
	var bad := 0
	var shown_server := 0
	var penalty := false
	for shot in 3:
		var strokes_before: int = main.strokes
		if shot == 0 and water != Vector3.INF:
			var to: Vector3 = water - main._ball.global_position
			to.y = 0.0
			var power := clampf(to.length() / 230.0, 0.2, 1.0)
			main._ball.launch(to.normalized(), 0.0, power, main.CLUBS[0], (-to.normalized()).cross(Vector3.UP))
			main._send_shot(to.normalized(), 0.0, power, 0, 0.0)
		else:
			main._bot_shot()
		t = Time.get_ticks_msec()
		await process_frame
		while (main._awaiting_rest or main.mode != 0) and Time.get_ticks_msec() - t < 40000:
			await process_frame
			frames += 1
			var own: MeshInstance3D = main._ball.get_node("Mesh")
			if main._ball.visible and own.mesh != skin:
				bad += 1
			var views: Dictionary = main._puppets._views
			if views.has(net.my_id) and main._puppets.own_visible:
				shown_server += 1
				if (views[net.my_id].get_child(0) as MeshInstance3D).mesh != skin:
					bad += 1
		for i in 30:
			await process_frame
		var own: MeshInstance3D = main._ball.get_node("Mesh")
		bad += int(own.mesh != skin)
		if shot == 0:
			penalty = main.strokes - strokes_before >= 2 or str(net.players.get(net.my_id, {}).get("message", "")).contains("Water")
		print("    shot %d: strokes %d → %d, %s" % [shot + 1, strokes_before, main.strokes, net.players.get(net.my_id, {}).get("message", "")])
	_check(penalty, "the first shot found the water: a penalty and a drop")
	_check(bad == 0 and shown_server > 0, "the Meatball in every frame of three shots (%d frames, %d of them the server's ball in flight; %d wrong)" % [frames, shown_server, bad])
	net.leave()
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


## The nearest water 30–220 m from the ball, a few metres in from its edge, or INF.
func _water_spot(main: Node) -> Vector3:
	var hole: GeneratedHole = main._hole
	var from: Vector3 = main._ball.global_position
	for r in range(30, 221, 3):
		for k in 120:
			var a := TAU * k / 120.0
			var out := Vector3(cos(a), 0.0, sin(a))
			var p := from + out * r
			p.y = hole.height_at(p) # (water is where the ground lies under its level)
			var q := p + out * 6.0
			q.y = hole.height_at(q)
			if hole.surface_at(p) == hole.params.water and hole.surface_at(q) == hole.params.water:
				return q
	return Vector3.INF
