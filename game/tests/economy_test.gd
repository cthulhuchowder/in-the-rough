extends SceneTree
## Coins, server-authoritative: a dedicated server and three bot clients (separate processes) play a
## 2-hole round. From the server's record of each hole (score, picked up, drive, tee shot to the pin)
## the coins are worked out here again from economy.tres's numbers — base by par, under par, hole in
## one, the room's longest drive (par 4/5) and closest to the pin (par 3) — and must equal what the
## server stored in its profiles file, the card's totals, and each client's own balance.
## Run: godot --headless --path game -s res://tests/economy_test.gd

const PORT := "7797"
const TIMEOUT_S := 300.0
const NAMES := ["A", "B", "C"]

var _pids: Array[int] = []
var _files := {}
var _started := 0.0
var _joiners := false
var _exe := ""
var _common: Array[String] = []
var _failed := false


func _check(ok: bool, what: String) -> void:
	_failed = _failed or not ok
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])


func _initialize() -> void:
	_exe = OS.get_executable_path()
	var dir := OS.get_user_data_dir()
	_files = {code = dir + "/econ_code.txt", server = dir + "/econ_server.json", profiles = dir + "/econ_profiles.json",
		A = dir + "/econ_A.json", B = dir + "/econ_B.json", C = dir + "/econ_C.json"}
	for path in _files.values():
		DirAccess.remove_absolute(path)
	_common = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--"]
	_pids.append(OS.create_process(_exe, _common + ["--server", "--port", PORT, "--holes", "2", "--exit-when-done",
		"--report", _files.server, "--profiles", _files.profiles]))
	OS.delay_msec(1500)
	_pids.append(OS.create_process(_exe, _common + _bot("A") + ["--create", "--expect", "3", "--code-file", _files.code,
		"--report", _files.A]))
	_started = Time.get_ticks_msec() / 1000.0


func _bot(bot_name: String) -> Array[String]:
	return ["--bot", "--name", bot_name, "--address", "127.0.0.1", "--port", PORT]


func _process(_delta: float) -> bool:
	var waited := Time.get_ticks_msec() / 1000.0 - _started
	if not _joiners and FileAccess.file_exists(_files.code):
		var code := FileAccess.get_file_as_string(_files.code).strip_edges()
		if code.length() == 6:
			for n in ["B", "C"]:
				_pids.append(OS.create_process(_exe, _common + _bot(n) + ["--code", code, "--report", _files[n]]))
			_joiners = true
	var done := NAMES.all(func(n): return FileAccess.file_exists(_files[n])) and FileAccess.file_exists(_files.server) \
		and FileAccess.file_exists(_files.profiles)
	if not done and waited < TIMEOUT_S:
		OS.delay_msec(200)
		return false
	OS.delay_msec(500) # (the last file finishing)
	for pid in _pids:
		if OS.is_process_running(pid):
			OS.kill(pid)
	if not done:
		print("  FAIL  timed out after %.0f s" % waited)
		print("FAIL")
		return true
	_verify()
	print("  %.0f s" % waited)
	print("FAIL" if _failed else "PASS")
	return true


func _verify() -> void:
	var p: EconomyParams = load("res://data/economy.tres")
	var server: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_files.server))
	var profiles: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_files.profiles))
	var log: Dictionary = server.holes
	var holes := int(server.pars.size())
	_check(holes == 2 and NAMES.all(func(n): return log.has(n) and log[n].size() == 2), "three players, two holes recorded (pars %s)" % [server.pars])
	var expected := {"A": 0, "B": 0, "C": 0}
	for h in holes:
		var par := int(server.pars[h])
		var longest := ""
		var best := -1.0
		var closest := ""
		var near := INF
		for n in NAMES:
			var e: Dictionary = log[n][h]
			if par >= 4 and e.drive_ok and float(e.drive) > best:
				best = float(e.drive)
				longest = n
			if par == 3 and float(e.closest) >= 0.0 and float(e.closest) < near:
				near = float(e.closest)
				closest = n
		var line := "  hole %d (par %d):" % [h + 1, par]
		for n in NAMES:
			var e: Dictionary = log[n][h]
			var score := int(e.score)
			var coins := 0
			if not e.picked_up:
				coins += [0, 0, 0, p.base_par3, p.base_par4, p.base_par5][par]
				coins += maxi(par - score, 0) * p.under_par_per_stroke
				coins += p.hole_in_one if score == 1 else 0
			coins += p.longest_drive if n == longest else 0
			coins += p.closest_to_pin if n == closest else 0
			expected[n] += coins
			_check(int(e.award.total) == coins, "hole %d: %s scored %d%s → %d coins (server %d)" % [h + 1, n, score,
				" · longest drive %.0f m" % best if n == longest else (" · closest %.1f m" % near if n == closest else ""), coins, int(e.award.total)])
	for n in NAMES:
		var mine: Array = profiles.values().filter(func(p: Dictionary) -> bool: return p.get("name", "") == n) # (kept by player key; the name is on it)
		var stored := int(mine[0].balance) if mine.size() == 1 else -1
		var row: Dictionary = server.rows.filter(func(r): return r.name == n)[0]
		var client: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_files[n]))
		_check(stored == expected[n] and int(row.coins.total) == expected[n] and int(client.balance) == expected[n],
			"%s: %d coins by the rules = stored %d = card %d = client %d" % [n, expected[n], stored, int(row.coins.total), int(client.balance)])
