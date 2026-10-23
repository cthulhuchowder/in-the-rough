extends SceneTree
## Shop. Online rules, through the server's own path (the in-process server, the same RPCs and
## handlers): a buy needs the coins and spends them, owning twice or an unknown item is refused,
## only owned items equip. The look: equipped colours, hat shapes rebuilt on the rig, the striped
## ball; a room's roster carries what each player wears (for everyone else's view of them). The
## fitting room offline: cards per tab, hover previews on the golfer, Buy and Equip on the local profile.
## Run: godot --headless --fixed-fps 120 --path game -s res://tests/shop_test.gd

const SPIN_STEP := 0.001

var _failed := false
var _net: Node


func _check(ok: bool, what: String) -> void:
	_failed = _failed or not ok
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])


func _initialize() -> void:
	_net = root.get_node("Net")
	var server: Node = load("res://scripts/game_server.gd").new()
	server.local = true # in process; its store is in memory under tests
	root.add_child(server)
	await process_frame
	server.store.get_profile(server.profile_key(1, "Ana")).balance = 300 # (this computer's key: single player)
	var got := [null]
	_net.shop_changed.connect(func(owned: Array, equipped: Dictionary, why: String) -> void: got[0] = [owned, equipped, why])
	var ask := func(call: Callable) -> Array:
		got[0] = null
		call.call()
		for i in 10:
			if got[0] != null:
				break
			await process_frame
		return got[0]
	var r: Array = await ask.call(func(): _net.shop_open.rpc_id(1, "Ana"))
	_check(r != null and _net.balance == 300 and r[0].is_empty(), "open: 300 coins, nothing owned")
	r = await ask.call(func(): _net.shop_buy.rpc_id(1, "Ana", "club_gold"))
	_check(r[2] == "" and _net.balance == 100 and "club_gold" in r[0], "buy the Gold set (200): owned, 100 left")
	r = await ask.call(func(): _net.shop_buy.rpc_id(1, "Ana", "hat_flat"))
	_check(r[2] == "Not enough coins" and _net.balance == 100 and not "hat_flat" in r[0], "the Flat cap (150) with 100: refused, nothing spent")
	r = await ask.call(func(): _net.shop_buy.rpc_id(1, "Ana", "club_gold"))
	_check(r[2] == "Already owned" and _net.balance == 100, "buying it twice: refused")
	r = await ask.call(func(): _net.shop_buy.rpc_id(1, "Ana", "golden_putter"))
	_check(r[2] == "No such item", "an unknown item: refused")
	r = await ask.call(func(): _net.shop_equip.rpc_id(1, "Ana", ShopItem.Tab.HAT, "hat_bucket"))
	_check(r[2] == "Not owned" and not r[1].has("hat"), "equipping an unowned hat: refused")
	r = await ask.call(func(): _net.shop_equip.rpc_id(1, "Ana", ShopItem.Tab.CLUB, "club_gold"))
	_check(r[2] == "" and r[1].get("club_set", "") == "club_gold", "equip the Gold set")

	# The look
	var gold: ShopItem = ShopCatalog.item("club_gold")
	var look := ShopCatalog.look_for(r[1])
	_check(look.club == gold.color and look.shirt == ShopCatalog.DEFAULT_LOOK.shirt, "the look: gold clubs, the rest standard")
	var rig := GolferRig.new(load("res://data/character.tres"), ShopCatalog.look_for({hat = "hat_bucket"}))
	root.add_child(rig)
	var bucket: int = rig._hat_style
	rig.look = ShopCatalog.look_for({hat = "hat_flat"})
	var flat: int = rig._hat_style
	var parts: int = rig._hat_parts.size()
	_check(bucket == 1 and flat == 2 and parts == 3 and rig._mats.hat.albedo_color == ShopCatalog.item("hat_flat").color,
		"hats: a bucket hat, then a flat cap rebuilt in its place (%d pieces)" % parts)
	var striped := Ball.view_mesh_for(ShopCatalog.look_for({ball = "ball_stripe"}))
	var colors: PackedColorArray = striped.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var accent := ShopCatalog.item("ball_stripe").accent
	_check(striped != Ball.view_mesh() and Array(colors).any(func(c: Color): return Vector3(c.r - accent.r, c.g - accent.g, c.b - accent.b).length() < 0.01) and Ball.view_mesh_for(ShopCatalog.look_for({})) == Ball.view_mesh(),
		"balls: the Tour stripe has its stripe; the standard ball is unchanged")

	# What a player wears goes round the room
	_net.create_room.rpc_id(1, "Ana")
	_net.set_ready.rpc_id(1, true)
	_net.start_round.rpc_id(1)
	for i in 10:
		await process_frame
	await process_frame
	_check(_net.players.get(1, {}).get("equipped", {}).get("club_set", "") == "club_gold", "the room's roster carries Ana's Gold set")
	_net.leave()
	await process_frame

	# The fitting room, offline
	var shop: Node = load("res://shop.tscn").instantiate()
	shop.set("player_name", "Bea")
	root.add_child(shop)
	await process_frame
	load("res://scripts/profile_store.gd").mine().balance = 120
	shop._go_offline_refresh() # (Bea's 120 coins on this computer)
	await process_frame
	var cards: int = shop._cards.get_child_count()
	shop._tabs.current_tab = ShopItem.Tab.SHIRT
	await process_frame
	shop._show_preview("shirt_mint")
	var mint := ShopCatalog.item("shirt_mint").color
	var previewed: bool = shop._rig.look.shirt == mint
	shop._show_look()
	var back: bool = shop._rig.look.shirt == ShopCatalog.DEFAULT_LOOK.shirt
	shop._buy("shirt_mint")
	shop._equip("shirt_mint")
	await process_frame
	var hats := ShopCatalog.catalog().items.filter(func(it: ShopItem) -> bool: return it.tab == ShopItem.Tab.HAT).size()
	_check(cards == 1 + hats and previewed and back, "fitting room: Standard and every item of the tab (%d hats); hovering previews the Mint polo, leaving reverts" % hats)
	_check(shop.balance == 40 and "shirt_mint" in shop.owned and shop.equipped.get("shirt", "") == "shirt_mint" and shop._rig.look.shirt == mint,
		"offline: Buy spends 80 of 120, Equip wears it (balance %d)" % shop.balance)
	# The turntable turns the whole golfer as one, head with body, on every tab's pose
	var all_ok := true
	var worst := 0.0
	for t in ShopCatalog.TAB_NAMES.size():
		shop._tabs.current_tab = t
		var turns := PackedFloat32Array()
		for k in 2:
			shop._angle = k * PI * 0.5 - SPIN_STEP
			shop._process(SPIN_STEP / shop.SPIN) # (one step on, to k quarter turns)
			var head: Node3D = shop._rig._head
			var body: Node3D = shop._rig._torso
			var hf := -head.global_basis.z
			var bf := -body.global_basis.z
			turns.append(atan2(hf.x, hf.z) - atan2(bf.x, bf.z))
		var drift := absf(wrapf(turns[1] - turns[0], -PI, PI))
		worst = maxf(worst, drift)
		all_ok = all_ok and drift < 0.02
	_check(all_ok, "turning a quarter turn, the head stays with the body on every tab (worst drift %.3f rad)" % worst)
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)
