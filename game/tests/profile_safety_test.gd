extends SceneTree
## Coins are never lost. On a profile file of its own (ProfileStore.test_path): earn coins in single
## player, open and close the shop five times (no server: offline), "quit and relaunch" (the store
## dropped and read back from disk) — the balance never moves. A server that has not taken in our sync
## (an older protocol) sends 0 coins and nothing owned: ignored. A purchase is the one change, and it
## survives a relaunch, and a rename on the menu's chip (the coins go with the player). Each save keeps the one before as .bak; a file that will not read (cut short)
## is left exactly as it is, never saved over.
## Run: godot --headless --path game -s res://tests/profile_safety_test.gd -- --address 127.0.0.1 --port 7798

const FILE := "user://profile_safety_test.json"
const KEY := "0123456789abcdef0123456789abcdef"

var _failed := false
var _net: Node
var _ps: GDScript


func _check(ok: bool, what: String) -> void:
	_failed = _failed or not ok
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])


func _initialize() -> void:
	if not "127.0.0.1" in OS.get_cmdline_user_args():
		print("FAIL  run with -- --address 127.0.0.1 --port 7798 (never the live server)")
		quit(1)
		return
	_net = root.get_node("Net")
	_ps = load("res://scripts/profile_store.gd")
	_ps.set("test_key", KEY) # (Ana's computer; the bot plays as her too)
	root.get_node("Settings").player_name = "Ana"
	for f in [FILE, FILE + ".bak", FILE + ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	_ps.set("test_path", FILE)

	# Earn: a hole in one in single player
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
	_net.leave()
	for i in 10:
		await process_frame
	var earned := _balance()
	_check(earned > 0 and _on_disk() == earned, "earned %d in single player, saved" % earned)

	# The shop five times, offline
	var seen := []
	for k in 5:
		var shop: Node = await _open_shop()
		seen.append(shop.balance)
		shop.free()
		await process_frame
	_relaunch()
	_check(seen.all(func(b: int) -> bool: return b == earned) and _balance() == earned and _on_disk() == earned,
		"the shop opened and closed 5 times shows %s; after a relaunch %d (on disk %d)" % [seen, _balance(), _on_disk()])

	# A server that never took our sync (an older protocol): its 0 coins, nothing owned, are not kept
	_net.shop_state(0, [], {}, "")
	_net.coins({}, 0)
	_relaunch()
	_check(_balance() == earned, "a server that has not synced says 0: ignored (%d)" % _balance())

	# A purchase: the one change, and it lasts
	var shop: Node = await _open_shop()
	var item: Resource = _cheapest()
	shop._buy(item.id)
	var after: int = shop.balance
	shop.free()
	_relaunch()
	_check(after == earned - item.price and _balance() == after and item.id in _ps.mine().owned,
		"bought %s (%d): %d, the same after a relaunch" % [item.id, item.price, _balance()])
	var bak: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE + ".bak"))
	_check(bak is Dictionary and bak.has(KEY), "the save before is kept as .bak")

	# A rename on the menu's chip: the coins and items go with the player (not a fresh, empty profile)
	var lobby: Control = load("res://lobby.tscn").instantiate()
	root.add_child(lobby)
	await process_frame
	(lobby.get_node("%NameShown") as Button).pressed.emit()
	(lobby.get_node("%Name") as LineEdit).text = "Sam"
	lobby._name_done()
	var chip := int((lobby.get_node("%Coins") as Label).text)
	lobby.free()
	var renamed := []
	for k in 5:
		var s: Node = await _open_shop("Sam")
		renamed.append(s.balance)
		s.free()
		await process_frame
	_relaunch()
	var sam: Dictionary = _ps.mine()
	_check(chip == after and renamed.all(func(b: int) -> bool: return b == after) and int(sam.balance) == after and item.id in sam.owned
		and sam.name == "Sam" and _ps.offline().profiles.size() == 1 and _ps.offline().has(KEY),
		"renamed Ana → Sam: chip %d, the shop 5 times %s, after a relaunch %d with %s (the same key: the name is only what others see)" % [chip, renamed, int(sam.balance), item.id])
	root.get_node("Settings").player_name = "Ana"

	# A file cut short: not read as empty, never saved over
	var good := FileAccess.get_file_as_string(FILE)
	var f := FileAccess.open(FILE, FileAccess.WRITE)
	f.store_string(good.left(good.length() / 2))
	f.close()
	var cut := FileAccess.get_file_as_string(FILE)
	_relaunch()
	var store: RefCounted = _ps.offline()
	store.get_profile(KEY).balance = 0
	store.save()
	_check(not store.loaded and FileAccess.get_file_as_string(FILE) == cut, "a file cut short: not loaded, and left as it is (not saved over)")

	# From before keys: a profile under the player's name moves to this computer's key, all of it owed
	var old := FileAccess.open(FILE, FileAccess.WRITE)
	old.store_string(JSON.stringify({Sam = {name = "Sam", balance = 45, owned = ["club_fish"], server_balance = 0, synced = true,
		stats = {rounds = 1, holes = 27, coins_earned = 575, holes_in_one = 0, best_drive = 249.5}}}))
	old.close()
	root.get_node("Settings").player_name = "Sam"
	_relaunch()
	var moved: Dictionary = _ps.mine()
	_relaunch()
	_check(int(moved.balance) == 45 and "club_fish" in moved.owned and not moved.has("server_balance") and _ps.offline().has(KEY)
		and not _ps.offline().has("Sam") and _on_disk() == 45, "a profile from before keys (Sam, 45 coins, the Fish club) moves to the key, all of it owed to the server")

	for p in [FILE, FILE + ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _balance() -> int:
	return int(_ps.mine().balance)


func _on_disk() -> int:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
	return int(data[KEY].balance) if data is Dictionary and data.has(KEY) else -1


## Quit and relaunch, as far as the profile goes: the shared store dropped, read again from disk.
func _relaunch() -> void:
	_ps.set("_offline", null)


func _open_shop(as_name := "Ana") -> Node:
	load("res://scripts/shop_scene.gd").set("player_name", as_name)
	var shop: Node = load("res://shop.tscn").instantiate()
	root.add_child(shop)
	var t := 0.0
	while t < 8.0 and not shop.online and shop._status.text == "Connecting…":
		await create_timer(0.1).timeout
		t += 0.1
	return shop


func _cheapest() -> Resource:
	var best: Resource = null
	for it in load("res://scripts/shop_catalog.gd").catalog().items:
		if best == null or it.price < best.price:
			best = it
	return best
