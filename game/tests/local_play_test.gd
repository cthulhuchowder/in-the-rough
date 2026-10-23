extends SceneTree
## Single player = a room of one with no network: the lobby's Play hosts the server inside the game
## (GameServer.local on an OfflineMultiplayerPeer), makes a room you're alone and ready in, Start
## begins the round and balls come back from that server, and leaving removes it. No connection
## errors ever show.
## Run: godot --headless --path game -s res://tests/local_play_test.gd

func _initialize() -> void:
	var net: Node = root.get_node("Net")
	var lobby: Node = load("res://lobby.tscn").instantiate()
	root.add_child(lobby)
	await process_frame
	lobby._play_local()
	var t := Time.get_ticks_msec()
	while not net.lobby.get(1, {}).get("ready", false) and Time.get_ticks_msec() - t < 5000:
		await process_frame
	var peer: MultiplayerPeer = lobby.multiplayer.multiplayer_peer
	var roomed: bool = net.local and net.lobby.size() == 1 and net.lobby.get(1, {}).get("ready", false) \
		and lobby._start.visible and not lobby._start.disabled and peer is OfflineMultiplayerPeer
	print("  %s  Play: room %s with no network (%s), players %d, ready, Start enabled %s" % ["ok  " if roomed else "FAIL", net.room_code,
		peer.get_class() if peer else "no peer", net.lobby.size(), not lobby._start.disabled])
	var status: String = lobby._status.text # (once the round runs the lobby says so; the game has left it by then)
	var began := [false]
	net.round_began.connect(func(): began[0] = true)
	var snaps := [0]
	net.snapshot_received.connect(func(_tick, _data): snaps[0] += 1)
	lobby._start.pressed.emit()
	t = Time.get_ticks_msec()
	while (not began[0] or snaps[0] < 5) and Time.get_ticks_msec() - t < 15000:
		await process_frame
	var playing: bool = began[0] and snaps[0] >= 5 and net.online()
	print("  %s  Start begins the round on the in-process server (%d snapshots)" % ["ok  " if playing else "FAIL", snaps[0]])
	net.leave()
	for i in 5:
		await process_frame
	var gone: bool = net.server == null and lobby.multiplayer.multiplayer_peer == null and status == ""
	print("  %s  leaving removes the in-process server; no status shown ('%s')" % ["ok  " if gone else "FAIL", status])
	var ok: bool = roomed and playing and gone
	print("PASS" if ok else "FAIL")
	quit(0 if ok else 1)
