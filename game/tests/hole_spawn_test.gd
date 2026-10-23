extends SceneTree
## New-hole spawn: the game's bot plays hole 1 of a single-player room (in-process server); the
## moment hole 2 spawns the player is in Shooting at their own tee with the shooting camera there,
## never where the follow camera left it: the server sends the hole before the score reset, and the
## flyover takes its end pose from the camera right then.
## Run: godot --headless --fixed-fps 60 --path game -s res://tests/hole_spawn_test.gd

func _initialize() -> void:
	var net: Node = root.get_node("Net")
	var lobby: Node = load("res://lobby.tscn").instantiate()
	root.add_child(lobby)
	current_scene = lobby
	await process_frame
	lobby._play_local()
	var t := Time.get_ticks_msec()
	while not net.lobby.get(1, {}).get("ready", false) and Time.get_ticks_msec() - t < 5000:
		await process_frame
	net.set_rules.rpc_id(1, {holes = 3})
	net.bot = true # the game's test bot plays the shots
	var seen := []
	var probe := func(number: int, _rests: Dictionary) -> void:
		if number == 2:
			var main: Node = current_scene
			var ball: Vector3 = main._ball.global_position
			seen.append([main.mode, main._camera.global_position.distance_to(ball), ball.distance_to(main._hole.tee.global_position),
				main._camera.global_transform.is_equal_approx(main._swing.camera.global_transform)])
	lobby._start.pressed.emit()
	t = Time.get_ticks_msec()
	var hooked := false
	while seen.is_empty() and Time.get_ticks_msec() - t < 150000:
		await process_frame
		if not hooked and current_scene and current_scene.name == "Main":
			hooked = true # connected after main: runs right after its spawn, where the flyover takes its end pose
			net.hole_started.connect(probe)
	var ok := false
	if seen.is_empty():
		print("  FAIL  hole 2 never spawned")
	else:
		var s: Array = seen[0]
		ok = s[0] == 0 and s[1] < 6.0 and s[2] < 6.0 # Mode.SHOOTING; camera by the ball; ball on the tee
		print("  %s  hole 2 spawn: mode %d (Shooting 0), camera %.2f m from the ball, ball %.2f m from the tee" % [
			"ok  " if ok else "FAIL", s[0], s[1], s[2]])
	# Single player's coins: the offline share of every award, the balance from the in-process server
	var econ: EconomyParams = load("res://data/economy.tres")
	var row: Dictionary = net.card.rows[0] if not net.card.is_empty() else {}
	var par := int(net.card.pars[0]) if not net.card.is_empty() else 4
	var full: int = [0, 0, 0, econ.base_par3, econ.base_par4, econ.base_par5][par]
	var coins_ok: bool = not row.is_empty() and int(row.coins.base) == int(floor(full * econ.offline_share)) and net.balance == int(row.coins.total)
	print("  %s  single player earns %.0f %%: hole 1 base %d of %d, balance %d" % ["ok  " if coins_ok else "FAIL",
		econ.offline_share * 100.0, int(row.get("coins", {}).get("base", -1)), full, net.balance])
	ok = ok and coins_ok
	net.leave()
	print("PASS" if ok else "FAIL")
	quit(0 if ok else 1)
