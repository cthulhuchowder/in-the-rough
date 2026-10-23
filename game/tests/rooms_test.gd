extends SceneTree
## Headless check of step 2.5: a dedicated server and three bot clients as separate processes.
## A hosts a room, B and C join by code, everyone readies, A starts a 2-hole round. C drops out
## mid-hole 1; the hole must still complete for A and B, then hole 2, and the scorecard each
## client ends with must equal the server's. Bots swing before every shot (streamed at 20 Hz);
## each remote golfer must draw the other's swing within one sample tick of what was sent.
## Run: godot --headless --path game -s res://tests/rooms_test.gd

const PORT := "7795"
const TIMEOUT_S := 300.0

var _pids: Array[int] = []
var _files := {}
var _started := 0.0
var _joiners_started := false
var _exe := ""
var _common: Array[String] = []

func _initialize() -> void:
	_exe = OS.get_executable_path()
	var dir := OS.get_user_data_dir()
	_files = {code = dir + "/rooms_code.txt", server = dir + "/rooms_server.json", A = dir + "/rooms_A.json", B = dir + "/rooms_B.json"}
	for path in _files.values():
		DirAccess.remove_absolute(path)

	# Real time, not --fixed-fps fast-forward: unthrottled, the server floods the unreliable channel
	# with snapshots, and a client stalled building the next hole drops swing samples at the socket.
	_common = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--"]
	_pids.append(OS.create_process(_exe, _common + ["--server", "--port", PORT, "--holes", "2",
		"--exit-when-done", "--report", _files.server]))
	OS.delay_msec(1500)
	_pids.append(OS.create_process(_exe, _common + _bot("A") + ["--create", "--expect", "3", "--code-file", _files.code,
		"--report", _files.A]))
	_started = Time.get_ticks_msec() / 1000.0

func _bot(bot_name: String) -> Array[String]:
	return ["--bot", "--name", bot_name, "--address", "127.0.0.1", "--port", PORT]

func _process(_delta: float) -> bool:
	var waited := Time.get_ticks_msec() / 1000.0 - _started
	if not _joiners_started and FileAccess.file_exists(_files.code):
		var code := FileAccess.get_file_as_string(_files.code).strip_edges()
		if code.length() == 6:
			print("  room code %s" % code)
			_pids.append(OS.create_process(_exe, _common + _bot("B") + ["--code", code, "--report", _files.B]))
			_pids.append(OS.create_process(_exe, _common + _bot("C") + ["--code", code, "--leave-after-shots", "1"]))
			_joiners_started = true
	var done: bool = FileAccess.file_exists(_files.server) and FileAccess.file_exists(_files.A) and FileAccess.file_exists(_files.B)
	if not done and waited < TIMEOUT_S:
		OS.delay_msec(200)
		return false
	for pid in _pids:
		if OS.is_process_running(pid):
			OS.kill(pid)
	if not done:
		print("  FAIL  timed out after %.0f s" % waited)
		print("FAIL")
		return true
	var reports := [_files.server, _files.A, _files.B].map(func(path): return JSON.parse_string(FileAccess.get_file_as_string(path)))
	if reports.any(func(r): return not r is Dictionary):
		if waited < TIMEOUT_S:
			OS.delay_msec(200) # a report still being written: read it again next frame
			return false
		print("  FAIL  a report never became readable JSON")
		print("FAIL")
		return true
	var server: Dictionary = reports[0]
	var a: Dictionary = reports[1]
	var b: Dictionary = reports[2]
	print("  server card: %s" % JSON.stringify(server))
	var names: Array = server.rows.map(func(r): return r.name)
	var ok := true
	ok = _check(server.pars.size() == 2, "two holes played (pars %s)" % [server.pars]) and ok
	ok = _check(names == ["A", "B"], "C left mid-round and is off the card (rows %s)" % [names]) and ok
	ok = _check(server.rows.all(func(r): return r.scores.size() == 2 and r.scores.all(func(s): return s >= 1)),
		"A and B completed both holes, including the one C left during") and ok
	var card := {pars = server.pars, rows = server.rows, rules = server.rules} # (the report adds what the coins came from)
	ok = _check(a.card == card and b.card == card, "both clients' scorecards match the server") and ok
	for pair in [[a, b], [b, a]]:
		var problem := _swing_tracks(pair[0], pair[1])
		ok = _check(problem == "", "%s sees %s's swing %s" % [pair[0].swing.name, pair[1].swing.name,
			problem if problem != "" else "within one tick"]) and ok
	for pair in [[a, b], [b, a]]: # every bot strolls once before its second shot
		var frames := int(pair[0].walk.seen.get(pair[1].swing.name, 0))
		ok = _check(int(pair[1].walk.sent) > 0 and frames > 0, "%s sees %s walk (%d samples sent, %d frames drawn walking)" % [
			pair[0].swing.name, pair[1].swing.name, int(pair[1].walk.sent), frames]) and ok
	print("  %.0f s" % waited)
	print("PASS" if ok else "FAIL")
	return true

func _check(ok: bool, what: String) -> bool:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	return ok

## Empty if `receiver` drew `sender`'s swing faithfully: every relayed sample carries the value
## that was sent, and every drawn angle lies within one sample step of the sender's angles at
## that server tick (i.e. it never lags or leads by more than one tick).
func _swing_tracks(receiver: Dictionary, sender: Dictionary) -> String:
	var sent := {}
	for s in sender.swing.sent:
		sent[int(s[0])] = float(s[1])
	var seen: Dictionary = receiver.swing.seen.get(sender.swing.name, {})
	if seen.is_empty() or seen.received.is_empty():
		return "(no samples received)"
	var timeline: Array = [] # [server tick, angle the sender sent]
	for r in seen.received:
		if not sent.has(int(r[0])) or absf(float(r[2]) - sent[int(r[0])]) > 0.001:
			return "(sample %d altered in transit)" % int(r[0])
		timeline.append([float(r[1]), sent[int(r[0])]])
	if seen.received.size() < sent.size() * 0.8:
		return "(only %d of %d samples arrived)" % [seen.received.size(), sent.size()]
	for d in seen.displayed:
		var tick := float(d[0])
		var k := timeline.size() - 1
		for i in timeline.size() - 1:
			if tick <= timeline[i + 1][0]:
				k = i
				break
		var a: Array = timeline[k]
		var b: Array = timeline[mini(k + 1, timeline.size() - 1)]
		var step: float = absf(b[1] - a[1]) + 0.001
		var low: float = minf(a[1], b[1]) - step if tick < b[0] else b[1] - 0.001
		var high: float = maxf(a[1], b[1]) + step if tick < b[0] else b[1] + 0.001
		if float(d[1]) < low or float(d[1]) > high:
			return "(drawn %.3f at tick %.0f, sender %.3f→%.3f)" % [d[1], tick, a[1], b[1]]
	if seen.displayed.is_empty():
		return "(never drawn)"
	print("  %s → %s: %d of %d samples, %d frames drawn" % [sender.swing.name, receiver.swing.name,
		seen.received.size(), sent.size(), seen.displayed.size()])
	return ""
