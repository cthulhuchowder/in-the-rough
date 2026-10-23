extends SceneTree
## Headless check of lobby rules: a dedicated server and two bot clients as separate processes.
## A hosts with --rules holes=3,shot_clock=5; B joins and stands idle for its first two strokes on
## every hole, so only the shot clock moves it on. The round must end in bounded time with three
## holes played, B's whiffs on the card, the rules on everyone's scorecard, and every hole's tee
## spots distinct (tee_slot_spacing apart across the tee) and the same on both clients.
## Run: godot --headless --path game -s res://tests/lobby_rules_test.gd

const PORT := "7796"
const TIMEOUT_S := 240.0
const IDLE := 2

var _pids: Array[int] = []
var _files := {}
var _started := 0.0
var _joined := false
var _exe := ""
var _common: Array[String] = []

func _initialize() -> void:
	_exe = OS.get_executable_path()
	var dir := OS.get_user_data_dir()
	_files = {code = dir + "/rules_code.txt", server = dir + "/rules_server.json", A = dir + "/rules_A.json", B = dir + "/rules_B.json"}
	for path in _files.values():
		DirAccess.remove_absolute(path)
	_common = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--"]
	_pids.append(OS.create_process(_exe, _common + ["--server", "--port", PORT, "--exit-when-done", "--report", _files.server]))
	OS.delay_msec(1500)
	_pids.append(OS.create_process(_exe, _common + _bot("A") + ["--create", "--expect", "2", "--code-file", _files.code,
		"--rules", "holes=3,shot_clock=5", "--report", _files.A]))
	_started = Time.get_ticks_msec() / 1000.0

func _bot(bot_name: String) -> Array[String]:
	return ["--bot", "--name", bot_name, "--address", "127.0.0.1", "--port", PORT]

func _process(_delta: float) -> bool:
	var waited := Time.get_ticks_msec() / 1000.0 - _started
	if not _joined and FileAccess.file_exists(_files.code):
		var code := FileAccess.get_file_as_string(_files.code).strip_edges()
		if code.length() == 6:
			_pids.append(OS.create_process(_exe, _common + _bot("B") + ["--code", code, "--idle-shots", str(IDLE),
				"--report", _files.B]))
			_joined = true
	var reports := []
	for key in ["server", "A", "B"]:
		var text := FileAccess.get_file_as_string(_files[key]) if FileAccess.file_exists(_files[key]) else ""
		reports.append(JSON.parse_string(text) if text != "" else null)
	if reports.any(func(r): return not r is Dictionary) and waited < TIMEOUT_S:
		OS.delay_msec(200)
		return false
	for pid in _pids:
		if OS.is_process_running(pid):
			OS.kill(pid)
	if reports.any(func(r): return not r is Dictionary):
		print("  FAIL  timed out after %.0f s" % waited)
		print("FAIL")
		return true
	var server: Dictionary = reports[0]
	var a: Dictionary = reports[1]
	var b: Dictionary = reports[2]
	print("  server card: %s" % JSON.stringify(server))
	var ok := true
	ok = _check(waited < TIMEOUT_S, "the round ended in bounded time (%.0f s, limit %.0f s)" % [waited, TIMEOUT_S]) and ok
	ok = _check(server.pars.size() == 3, "three holes played, as the host set (pars %s)" % [server.pars]) and ok
	ok = _check(int(server.rules.holes) == 3 and int(server.rules.shot_clock) == 5,
		"the rules travel on the scorecard (%s)" % RoomRules.describe(server.rules)) and ok
	var b_row: Dictionary = server.rows.filter(func(r): return r.name == "B")[0]
	ok = _check(b_row.scores.all(func(s): return s >= IDLE + 1),
		"B's shot clock whiffs count: every hole at least %d (scores %s)" % [IDLE + 1, b_row.scores]) and ok
	var card := {pars = server.pars, rows = server.rows, rules = server.rules} # (the report adds what the coins came from)
	ok = _check(a.card == card and b.card == card, "both clients' scorecards match the server") and ok
	var spacing: float = (load("res://data/net.tres") as NetParams).tee_slot_spacing # (autoload names aren't known to -s scripts)
	var distinct: bool = a.tees.size() == 3
	for hole in a.tees:
		for i in hole.size():
			for j in range(i + 1, hole.size()):
				var d: float = Vector2(hole[i][0] - hole[j][0], hole[i][2] - hole[j][2]).length()
				distinct = distinct and absf(d - spacing * (j - i)) < 0.1
	ok = _check(distinct, "every hole's tee spots are distinct, %.1f m apart in join order (%s)" % [spacing, a.tees]) and ok
	ok = _check(a.tees == b.tees, "both clients got the same tee spots") and ok
	print("  %.0f s" % waited)
	print("PASS" if ok else "FAIL")
	return true

func _check(ok: bool, what: String) -> bool:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	return ok
