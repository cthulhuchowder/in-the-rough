extends SceneTree
## The version handshake. A dedicated server on a different version (--fake-version) answers the
## client's hello with its own; the client disconnects and the menu's message names both versions
## ("Server is on a different version (server X, game Y)") instead of every request vanishing. The
## same build connects as before. The version carries a hash of Net's RPC set.
## Real time (separate server processes): godot --headless --path game -s res://tests/version_test.gd

const PORT_OTHER := 7798
const PORT_SAME := 7799

var _failed := false
var _pids: Array[int] = []


func _check(ok: bool, what: String) -> void:
	_failed = _failed or not ok
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])


func _initialize() -> void:
	await process_frame # (the Net autoload in the tree)
	var net: Node = root.get_node("Net")
	var exe := OS.get_executable_path()
	var common: Array[String] = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--"]
	_pids.append(OS.create_process(exe, common + ["--server", "--port", str(PORT_OTHER), "--fake-version", "9.9.9+test"]))
	_pids.append(OS.create_process(exe, common + ["--server", "--port", str(PORT_SAME)]))
	OS.delay_msec(2500)
	var mine: String = net.version()
	_check(mine.begins_with(str(ProjectSettings.get_setting("application/config/version")) + "+") and mine.length() > 7,
		"this build's version: %s (config/version + RPC-set hash)" % mine)

	var result := await _connect(net, PORT_OTHER)
	var expected: String = net.version_mismatch("9.9.9+test", mine)
	_check(result == "failed: " + expected, "a server on another version: \"%s\"" % result.trim_prefix("failed: "))
	_check(not net.is_connected_to_server(), "and the client is disconnected")

	result = await _connect(net, PORT_SAME)
	_check(result == "connected", "the same build's server: connected (%s)" % result)
	net.multiplayer.multiplayer_peer = null

	for pid in _pids:
		OS.kill(pid)
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


## "connected" or "failed: <reason>", within ten seconds.
func _connect(net: Node, port: int) -> String:
	var out := [""]
	var ok := func() -> void: out[0] = "connected"
	var bad := func(reason: String) -> void: out[0] = "failed: " + reason
	net.connected.connect(ok, CONNECT_ONE_SHOT)
	net.connection_failed.connect(bad, CONNECT_ONE_SHOT)
	net.connect_to_server("127.0.0.1", port)
	var end := Time.get_ticks_msec() + 10000
	while out[0] == "" and Time.get_ticks_msec() < end:
		await process_frame
	if net.connected.is_connected(ok):
		net.connected.disconnect(ok)
	if net.connection_failed.is_connected(bad):
		net.connection_failed.disconnect(bad)
	return out[0] if out[0] != "" else "timed out"
