class_name GameServer
extends Node
## Headless authority hosting many rooms at once. Players never see its address: it lives in
## net.tres. Hosts create a room and get a short code; others join with it. Each room owns its
## seed, balls, scoring and hole progression (Room). Clients send only lobby actions and shots.
## Single player runs one inside the game itself (`local`), the same code with no network.
## Args: --port N  --holes N (default holes per round; hosts pick theirs)  --exit-when-done (after the first round ends)
##       --report PATH (that round's scorecard as JSON)

const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" # no 0/O or 1/I

var _rooms := {} ## code → Room
var _room_of := {} ## peer id → Room
var _holes := 0
var _exit_when_done := false
var _report_path := ""
var store: ProfileStore ## players' coins and stats, by player key
var _key_of := {} # peer id → the player key it gave (its profile)
var coin_share := 1.0 ## of every coin award (Economy.PARAMS.offline_share in single player)
var local := false ## single player: hosted inside the game (no network), freed when its room closes


func _ready() -> void:
	var params := Net.PARAMS
	_holes = int(Boot.arg("holes", str(params.holes_per_round)))
	_exit_when_done = Boot.flag("exit-when-done")
	_report_path = Boot.arg("report")
	# Profiles (coins, stats): single player in user://profile.json at the offline share; a dedicated
	# server in one file next to its binary (--profiles PATH to put it elsewhere)
	store = ProfileStore.offline() if local else ProfileStore.open(Boot.arg("profiles",
		OS.get_executable_path().get_base_dir().path_join("profiles.json")))
	coin_share = Economy.PARAMS.offline_share if local else 1.0
	if local: # single player, in the game's own process: no sockets, the game is peer 1 and the server
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		Net.server = self
		return
	var port := int(Boot.arg("port", str(params.port)))
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 32 * params.max_players)
	if err != OK:
		printerr("golf server: cannot listen on UDP %d: %s" % [port, error_string(err)])
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_disconnected.connect(on_leave)
	multiplayer.peer_disconnected.connect(func(id: int) -> void: _key_of.erase(id))
	(multiplayer as SceneMultiplayer).peer_packet.connect(_on_packet)
	Net.server = self
	print("golf server: UDP %d, %d holes per round, version %s" % [port, _holes, Net.version()])


## A client's version handshake (raw packets: it works across protocol versions): answer with ours;
## a client on a different one is told (it disconnects itself) and dropped a moment later anyway.
func _on_packet(id: int, packet: PackedByteArray) -> void:
	var text := packet.get_string_from_utf8()
	if not text.begins_with(Net.VERSION_TAG):
		return
	var theirs := text.trim_prefix(Net.VERSION_TAG).left(64)
	(multiplayer as SceneMultiplayer).send_bytes((Net.VERSION_TAG + Net.version()).to_utf8_buffer(), id, MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	if theirs != Net.version():
		print("golf server: peer %d is on version %s (server %s): dropped" % [id, theirs, Net.version()])
		await get_tree().create_timer(1.0, true, false, true).timeout
		var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		if enet and enet.get_peer(id):
			enet.disconnect_peer(id)


func on_create(id: int, player_name: String) -> void:
	on_leave(id)
	var room := Room.new()
	room.code = _new_code()
	room.rules = RoomRules.defaults(_holes)
	room.course_seed = _new_seed()
	room.name = "Room_" + room.code
	add_child(room)
	_rooms[room.code] = room
	print("golf server: room %s created" % room.code)
	_enter(id, room, player_name)


func on_join(id: int, code: String, player_name: String) -> void:
	code = code.strip_edges().to_upper()
	var room: Room = _rooms.get(code)
	if room == null:
		Net.room_error.rpc_id(id, "No room with code %s" % code)
		return
	if _room_of.get(id) == room:
		return
	on_leave(id)
	_enter(id, room, player_name)


func on_leave(id: int) -> void:
	var room: Room = _room_of.get(id)
	if room == null:
		return
	_room_of.erase(id)
	room.remove_player(id)
	if room.is_empty():
		_rooms.erase(room.code)
		room.queue_free()
		print("golf server: room %s closed" % room.code)
		if local and _rooms.is_empty(): # the single player left: gone, and the game is offline again
			Net.server = null
			multiplayer.multiplayer_peer = null
			queue_free()


func on_ready(id: int, ready: bool) -> void:
	if _room_of.has(id):
		_room_of[id].set_ready(id, ready)


func on_start(id: int) -> void:
	if _room_of.has(id):
		_room_of[id].start(id, _room_of[id].course_seed)


func on_play_again(id: int) -> void:
	if _room_of.has(id):
		_room_of[id].play_again(id, _new_seed())


func on_shot(id: int, dir: Vector3, path_angle: float, power: float, club: int, spin: float) -> void:
	if _room_of.has(id):
		_room_of[id].shot(id, dir, path_angle, power, club, spin)


func on_set_rules(id: int, wanted: Variant) -> void:
	if _room_of.has(id):
		_room_of[id].set_rules(id, wanted)


func on_mulligan(id: int) -> void:
	if _room_of.has(id):
		_room_of[id].mulligan(id)


## Every connect: what the player did offline since the last one, added into their one profile here:
## coins earned (capped at sync_cap a time; untrusted, the client says what it earned), then items bought
## (each bought again here: refused if not affordable), then the looks worn (only owned ones). The
## reply is the profile as it now stands, which the client keeps. ponytail: the cap is per connect,
## so an edited profile.json can bring sync_cap each time; a server-side daily cap if that is abused.
## The key (ProfileStore.my_key) says whose profile this connection's is from now on.
func on_sync_offline(id: int, key: String, player_name: String, earned: int, bought: Array, worn: Dictionary) -> void:
	if ProfileStore.is_key(key):
		_key_of[id] = key
	var prof := store.get_profile(profile_key(id, player_name))
	prof.name = ProfileStore.clean_name(player_name) # (only for reading the file: the key is the account)
	if not local:
		earned = clampi(earned, 0, Economy.PARAMS.sync_cap)
		prof.balance = int(prof.balance) + earned
		for item_id in bought:
			ShopCatalog.buy(prof, str(item_id))
		for t in ShopCatalog.TAB_NAMES.size():
			if worn.has(ShopCatalog.tab_key(t)):
				ShopCatalog.equip(prof, t, str(worn[ShopCatalog.tab_key(t)]))
		prof.synced = true
		store.save()
		if earned > 0 or not bought.is_empty():
			print("golf server: %s brought %d offline coins, %d items" % [prof.name, earned, bought.size()])
	Net.offline_synced.rpc_id(id, int(prof.balance), prof.get("owned", []), prof.get("equipped", {}))


## The shop (online): the profile's coins, items and what is worn; buying and wearing checked here.
func on_shop_open(id: int, player_name: String) -> void:
	_shop_reply(id, player_name, "")


func on_shop_buy(id: int, player_name: String, item_id: String) -> void:
	var why := ShopCatalog.buy(store.get_profile(profile_key(id, player_name)), item_id)
	if why == "":
		store.save()
	_shop_reply(id, player_name, why)


func on_shop_equip(id: int, player_name: String, tab: int, item_id: String) -> void:
	var why := ShopCatalog.equip(store.get_profile(profile_key(id, player_name)), tab, item_id)
	if why == "":
		store.save()
	_shop_reply(id, player_name, why)


func _shop_reply(id: int, player_name: String, why: String) -> void:
	var prof := store.get_profile(profile_key(id, player_name))
	Net.shop_state.rpc_id(id, int(prof.balance), prof.get("owned", []), prof.get("equipped", {}), why)


## Whose profile peer `id`'s is: the key it gave at its sync; in single player this computer's; a
## client from before keys (no key given), its name, as then.
func profile_key(id: int, player_name: String) -> String:
	if local:
		return ProfileStore.my_key()
	return _key_of.get(id, ProfileStore.clean_name(player_name))


func on_chat(id: int, text: String) -> void:
	if _room_of.has(id):
		_room_of[id].chat(id, text)


func on_whiff(id: int) -> void:
	if _room_of.has(id):
		_room_of[id].whiff(id)


func on_flyover_done(id: int, number: int) -> void:
	if _room_of.has(id):
		_room_of[id].flyover_done(id, number)


func on_spin(id: int, value: float) -> void:
	if _room_of.has(id):
		_room_of[id].spin(id, value)


func on_swing(id: int, seq: int, angle: float, pitch: float, club: int) -> void:
	if _room_of.has(id):
		_room_of[id].swing(id, seq, angle, pitch, club)


func on_walk(id: int, seq: int, position: Vector3, yaw: float) -> void:
	if _room_of.has(id):
		_room_of[id].walk(id, seq, position, yaw)


func on_round_over(room: Room) -> void:
	print("golf server: room %s round over %s" % [room.code, JSON.stringify(room.card())])
	if _report_path != "":
		var f := FileAccess.open(_report_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(room.report()))
		f.close()
	if _exit_when_done:
		await get_tree().create_timer(1.0).timeout # let the reliable channel flush
		get_tree().quit()


func _enter(id: int, room: Room, player_name: String) -> void:
	if room.add_player(id, player_name):
		_room_of[id] = room


func _new_code() -> String:
	while true:
		var bytes := Crypto.new().generate_random_bytes(Net.PARAMS.room_code_length)
		var code := ""
		for b in bytes:
			code += CODE_ALPHABET[b % CODE_ALPHABET.length()]
		if not _rooms.has(code):
			return code
	return ""


## Course seeds are the one intentionally random input; everything after them is deterministic.
func _new_seed() -> int:
	return Crypto.new().generate_random_bytes(8).decode_s64(0)
