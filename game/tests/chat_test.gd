extends SceneTree
## Room chat. A multiplayer room on the in-process server (the same Room/Net code, no sockets):
## Enter opens the box and the swing gets no input; Esc cancels (the Esc menu stays shut); Enter
## sends; the server relays "Name: text" to the room, cleaned (control characters out, trimmed to
## chat_max_length, at most one line per chat_min_interval); the log keeps chat_lines and each fades
## after chat_life. Single player has no chat.
## Run: godot --headless --fixed-fps 120 --path game -s res://tests/chat_test.gd

const FEEDBACK: FeedbackParams = preload("res://data/feedback.tres")

var _failed := false
var _net: Node


func _check(ok: bool, what: String) -> void:
	_failed = _failed or not ok
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])


func _initialize() -> void:
	_net = root.get_node("Net")
	var server: Node = load("res://scripts/game_server.gd").new() # (loaded: autoload names do not resolve in a -s script)
	server.local = true # in-process; Net.local stays false: a multiplayer room
	root.add_child(server)
	await process_frame # (its _ready, which takes the Net.server role, runs on the next frame)
	_net.create_room.rpc_id(1, "Ana")
	_net.set_ready.rpc_id(1, true)
	var began := [false]
	_net.round_began.connect(func(): began[0] = true)
	_net.start_round.rpc_id(1)
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _wait(1.0)
	var chat: Node = main._chat
	_check(chat != null and began[0], "a multiplayer room has chat")
	if chat == null:
		_done()
		return
	var gesture: SwingGesture = main._swing.gesture
	_key(KEY_ENTER)
	await _wait(0.1)
	var opened: bool = chat.is_open() and gesture.blocked
	_key(KEY_ESCAPE)
	await _wait(0.1)
	_check(opened and not chat.is_open() and not gesture.blocked and not main._menu.visible,
		"Enter opens the box and blocks the swing; Esc cancels (swing back, Esc menu shut)")

	var got := []
	_net.chat_received.connect(func(n: String, t: String): got.append("%s: %s" % [n, t]))
	_key(KEY_ENTER)
	await _wait(0.1)
	chat._edit.text = "nice\u0007 shot"
	chat._edit.text_submitted.emit(chat._edit.text) # Enter in the box
	await _wait(0.1)
	_check(got == ["Ana: nice shot"] and not chat.is_open() and chat._log.get_child_count() == 1,
		"Enter sends: relayed as %s, control character dropped, box closed" % [got])
	_net.send_chat.rpc_id(1, "too fast") # inside chat_min_interval of the last
	await _wait(0.1)
	_check(got.size() == 1, "a line sooner than %.1f s after the last is dropped" % _net.PARAMS.chat_min_interval)
	_rate_reset(server)
	_net.send_chat.rpc_id(1, "x".repeat(500))
	await _wait(0.1)
	_check(got.size() == 2 and got[1].length() == "Ana: ".length() + _net.PARAMS.chat_max_length, "a long line is trimmed to %d characters" % _net.PARAMS.chat_max_length)
	for i in 6:
		_rate_reset(server)
		_net.send_chat.rpc_id(1, "line %d" % i)
	await _wait(0.1)
	var lines: Array = chat._log.get_children().map(func(l): return l.text)
	_check(lines.size() == FEEDBACK.chat_lines and lines[-1] == "Ana: line 5", "the log keeps the last %d lines (%s … %s)" % [FEEDBACK.chat_lines, lines[0], lines[-1]])
	await _wait(FEEDBACK.chat_life + FEEDBACK.chat_fade + 0.5)
	_check(chat._log.get_child_count() == 0, "each line fades out %.0f s after it came" % FEEDBACK.chat_life)
	_net.leave()
	main.queue_free()
	await _wait(0.2)

	# Single player: no chat
	var lobby: Node = load("res://lobby.tscn").instantiate()
	root.add_child(lobby)
	await _wait(0.1)
	lobby._play_local()
	await _wait(0.2)
	_net.start_round.rpc_id(1)
	var solo: Node = load("res://main.tscn").instantiate()
	root.add_child(solo)
	await _wait(0.5)
	_check(_net.local and solo._chat == null, "single player has no chat")
	_net.leave()
	_done()


func _done() -> void:
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	var up := e.duplicate()
	up.pressed = false
	Input.parse_input_event(up)


## Game seconds, counted in frames (fixed 120 fps).
func _wait(seconds: float) -> void:
	for i in roundi(seconds * 120.0):
		await process_frame


## As if chat_min_interval had passed (the rate limit runs on the wall clock; unthrottled frames
## would let game time — the log's fades — run far ahead of it).
func _rate_reset(server: Node) -> void:
	for room in server._rooms.values():
		for id in room._players:
			room._players[id].erase("chat_at")
