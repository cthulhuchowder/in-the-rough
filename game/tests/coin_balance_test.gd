extends SceneTree
## One coin balance per player, everywhere. Ana earns coins in single player (the in-game server:
## owed to the real one), then a bot under her name earns more in an online room on a dedicated
## server (its own process). When she connects, the offline coins are added into her one profile, and
## the menu chip, the HUD's balance (Net.balance) and the shop all show the same total. A purchase in
## the shop (server-checked) updates all three. With the server down, the shop shows the same total
## and buys locally; once the server is back, it replays the buy and the balances agree again.
## Run: godot --headless --path game -s res://tests/coin_balance_test.gd -- --address 127.0.0.1 --port 7797
## (real time: a server process; the address keeps the shop off the live server when the local one is down)

const PORT := 7797
const KEY := "0123456789abcdef0123456789abcdef"

var _failed := false
var _net: Node
var _pids: Array[int] = []
var _common: Array[String] = []
var _profiles := ""
var _ps: GDScript # ProfileStore (it names the Settings autoload: loaded at run time)


func _check(ok: bool, what: String) -> void:
	_failed = _failed or not ok
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])


func _initialize() -> void:
	_net = root.get_node("Net")
	if not "127.0.0.1" in OS.get_cmdline_user_args():
		print("FAIL  run with -- --address 127.0.0.1 --port %d (never the live server)" % PORT)
		quit(1)
		return
	_ps = load("res://scripts/profile_store.gd")
	_ps.set("test_key", KEY) # (Ana's computer; the bot plays as her too)
	root.get_node("Settings").player_name = "Ana"
	var dir := OS.get_user_data_dir()
	_profiles = dir + "/coin_test_profiles.json"
	var report := dir + "/coin_test_bot.json"
	for path in [_profiles, report]:
		DirAccess.remove_absolute(path)
	_common = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--"]
	_start_server()

	# 1. Single player: a hole in one on the in-game server
	var local: Node = load("res://scripts/game_server.gd").new()
	local.local = true
	root.add_child(local)
	await process_frame
	_net.local = true
	_net.create_room.rpc_id(1, "Ana")
	_net.set_ready.rpc_id(1, true)
	_net.start_round.rpc_id(1)
	for i in 180:
		await process_frame
	var room: Node = local._room_of[1]
	room._players[1].round.score = 1
	room._award_hole()
	await process_frame
	var me: Dictionary = _ps.mine()
	var offline_earned := int(me.balance)
	_check(offline_earned > 0 and int(me.pending) == offline_earned, "single player: %d coins, owed to the server" % offline_earned)
	_net.leave()
	for i in 10:
		await process_frame

	# 2. Online: Ana (her key) plays a 1-hole round on the dedicated server; so does another player
	# also named Ana, on another computer (another key): coins go by key, not by name
	var twin_report := report.replace(".json", "_twin.json")
	DirAccess.remove_absolute(twin_report)
	var bot := OS.create_process(OS.get_executable_path(), _common + ["--bot", "--name", "Ana", "--key", KEY, "--create", "--address", "127.0.0.1",
		"--port", str(PORT), "--report", report])
	_pids.append(bot)
	_pids.append(OS.create_process(OS.get_executable_path(), _common + ["--bot", "--name", "Ana", "--key", "fedcba9876543210fedcba9876543210", "--create",
		"--address", "127.0.0.1", "--port", str(PORT), "--report", twin_report]))
	var waited := 0.0
	while not (FileAccess.file_exists(report) and FileAccess.file_exists(twin_report)) and waited < 240.0:
		await create_timer(0.5).timeout
		waited += 0.5
	var bot_report: Variant = JSON.parse_string(FileAccess.get_file_as_string(report))
	var online_balance := int(bot_report.balance) if bot_report is Dictionary else -1
	var twin: Variant = JSON.parse_string(FileAccess.get_file_as_string(twin_report))
	var twin_balance := int(twin.balance) if twin is Dictionary else -1
	_check(online_balance > 0 and twin_balance > 0, "online room: the server has %d coins for Ana, and %d for the other Ana (her own)" % [online_balance, twin_balance])

	# 3. Ana connects: her offline coins add in; chip, HUD and shop show one total
	var total := offline_earned + online_balance
	await _connect()
	me = _ps.mine()
	var lobby: Control = load("res://lobby.tscn").instantiate()
	root.add_child(lobby)
	await process_frame
	var chip := int((lobby.get_node("%Coins") as Label).text)
	var shop: Node = await _open_shop()
	_check(_net.balance == total and chip == total and shop.balance == total and shop.online and int(me.get("pending", 0)) == 0,
		"connected: server %d, HUD %d, chip %d, shop %d (expected %d = %d offline + %d online); nothing owed" % [
		_net.balance, _net.balance, chip, shop.balance, total, offline_earned, online_balance])
	var item := _cheapest()
	shop._buy(item.id)
	for i in 60:
		await process_frame
	lobby._show_profile()
	total -= item.price
	chip = int((lobby.get_node("%Coins") as Label).text)
	_check(shop.balance == total and _net.balance == total and chip == total and item.id in shop.owned,
		"bought %s (%d) online: shop %d, HUD %d, chip %d" % [item.id, item.price, shop.balance, _net.balance, chip])
	shop.free()

	# 4. The server down: the shop offline shows the same total and buys locally; reconciled on reconnect
	for pid in _pids:
		OS.kill(pid)
	_pids.clear()
	_net.multiplayer.multiplayer_peer = null
	await create_timer(0.5).timeout
	shop = await _open_shop()
	var shown_offline: int = shop.balance
	var second := _cheapest()
	shop._buy(second.id)
	total -= second.price
	lobby._show_profile()
	chip = int((lobby.get_node("%Coins") as Label).text)
	_check(not shop.online and shown_offline == total + second.price and shop.balance == total and chip == total,
		"server down: the shop shows %d, buys %s locally (%d), chip %d" % [shown_offline, second.id, shop.balance, chip])
	shop.free()
	_start_server()
	await create_timer(1.5).timeout
	await _connect()
	me = _ps.mine()
	lobby._show_profile()
	chip = int((lobby.get_node("%Coins") as Label).text)
	_check(_net.balance == total and chip == total and second.id in me.owned and me.get("pending_buys", []).is_empty(),
		"server back: it replays the buy; server %d, chip %d, nothing owed" % [_net.balance, chip])
	lobby.free()
	for pid in _pids:
		OS.kill(pid)
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _start_server() -> void:
	_pids.append(OS.create_process(OS.get_executable_path(), _common + ["--server", "--port", str(PORT), "--holes", "1", "--profiles", _profiles]))


func _connect() -> void:
	var done := [false]
	_net.offline_sync_done.connect(func() -> void: done[0] = true, CONNECT_ONE_SHOT)
	for attempt in 20:
		_net.connect_to_server("127.0.0.1", PORT)
		var t := 0.0
		while not done[0] and t < 2.0:
			await process_frame
			t += 0.016
		if done[0]:
			return
		_net.multiplayer.multiplayer_peer = null
		await create_timer(0.5).timeout


func _open_shop() -> Node:
	load("res://scripts/shop_scene.gd").set("player_name", "Ana")
	var shop: Node = load("res://shop.tscn").instantiate()
	root.add_child(shop)
	var t := 0.0
	while t < 6.0 and not shop.online and shop._status.text == "Connecting…":
		await create_timer(0.1).timeout
		t += 0.1
	return shop


## The cheapest item Ana does not own yet.
func _cheapest() -> Resource:
	var owned: Array = _ps.mine().get("owned", [])
	var best: Resource = null
	for it in load("res://scripts/shop_catalog.gd").catalog().items:
		if not it.id in owned and (best == null or it.price < best.price):
			best = it
	return best
