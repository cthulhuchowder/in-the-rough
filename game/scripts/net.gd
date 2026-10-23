extends Node
## Autoload "Net": every network message, so client and server share one RPC table.
## Channel 0 is reliable and ordered (lobby, shots, rests, scores, holes). Channel 1 carries
## ball snapshots unreliable and newest-wins, so a lost packet never stalls the stream
## The server address is net.tres's, never shown to players.
## Every RPC is call_local and sent with rpc_id, never broadcast: single player hosts the server in
## the game itself (GameServer.local, peer 1), so its messages to peer 1 run in place.

signal connected ## to the server; a room comes next
signal connection_failed(reason: String)

## The version handshake: raw packets, not RPCs, so it still works when the two builds' RPC sets
## differ (then Godot drops every Net RPC between them, silently).
const VERSION_TAG := "ITR-VERSION:"
signal room_failed(reason: String)
signal lobby_changed
signal round_began
signal hole_started(number: int, rests: Dictionary)
signal ball_at_rest(id: int, position: Vector3)
signal player_changed(id: int)
signal snapshot_received(tick: int, data: PackedInt32Array)
signal swing_received(id: int, seq: int, tick: int, angle: float, pitch: float, club: int)
signal walk_received(id: int, seq: int, tick: int, position: Vector3, yaw: float)
signal card_changed
signal hole_completed
signal round_ended
signal coins_received(awarded: Dictionary) ## this player's coins for a hole (Economy categories, total); balance is set
signal offline_sync_done
signal shop_changed(owned: Array, equipped: Dictionary, why: String) ## the server's answer to a shop request
signal chat_received(player_name: String, text: String) ## a room member said something (relayed by the server)
signal whiff_received(id: int) ## another player whiffed (their reactive hat answers)

const PARAMS: NetParams = preload("res://data/net.tres")
enum RoomState { LOBBY, PLAYING, ROUND_OVER } ## mirrors Room.State

var server: Node ## set on the server; client messages are handed to it
var balance := -1 ## this player's coins (from the server); -1 until it says
var my_id := 0 ## set while in a started round
var room_code := ""
var host_id := 0
var room_state := RoomState.LOBBY
var lobby := {} ## peer id → {name, ready}
var course_seed := 0
var hole_number := 0
var rests := {} ## peer id → ball rest position at round / hole start
var players := {} ## peer id → {name, strokes, score, message, mulligans}
var card := {} ## {pars, rows: [{id, name, scores}]}, -1 = not played
var bot := false
var local := false ## this room is a single player's, on a server inside this game (no network)
var clock_live := false ## the own shot clock runs (this client's own flyover of the hole is over)
var rules := {} ## the room's custom rules (RoomRules), from the server
var clock_ends := 0.0 ## s (ticks clock) the own shot clock runs out; 0 = none running
var report_path := ""


func online() -> bool:
	return my_id != 0


func is_host() -> bool:
	return host_id != 0 and host_id == multiplayer.get_unique_id()


func is_connected_to_server() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer is ENetMultiplayerPeer and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Connects once (to net.tres's server, or `to_address`:`to_port`); emits connected (now or when the
## handshake finishes) or connection_failed.
func connect_to_server(to_address := "", to_port := 0) -> void:
	if is_connected_to_server():
		connected.emit()
		return
	var address := to_address if to_address != "" else Boot.arg("address", PARAMS.default_address)
	var port := to_port if to_port > 0 else int(Boot.arg("port", str(PARAMS.port)))
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		connection_failed.emit("Could not start networking: %s" % error_string(err))
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_check_version, CONNECT_ONE_SHOT)
	multiplayer.connection_failed.connect(func():
		multiplayer.multiplayer_peer = null
		connection_failed.emit("Can't reach the game server"), CONNECT_ONE_SHOT)
	multiplayer.server_disconnected.connect(func():
		_clear_room()
		multiplayer.multiplayer_peer = null
		connection_failed.emit("Lost connection to the game server"), CONNECT_ONE_SHOT)


## Connected: first the versions are compared (our version to the server, its back). The same: on
## as before. Different, or no answer within version_timeout (a server from before the handshake):
## disconnect and say so, rather than every request after it vanishing.
func _check_version() -> void:
	var scene := multiplayer as SceneMultiplayer
	var answered := [false]
	var on_packet := func(from: int, packet: PackedByteArray) -> void:
		var text := packet.get_string_from_utf8()
		if from != 1 or answered[0] or not text.begins_with(VERSION_TAG):
			return
		answered[0] = true
		_version_answer(text.trim_prefix(VERSION_TAG))
	scene.peer_packet.connect(on_packet)
	scene.send_bytes((VERSION_TAG + version()).to_utf8_buffer(), 1, MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	await get_tree().create_timer(PARAMS.version_timeout, true, false, true).timeout
	scene.peer_packet.disconnect(on_packet)
	if not answered[0] and is_connected_to_server():
		_version_answer("older")


func _version_answer(server_version: String) -> void:
	if server_version != version():
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
		connection_failed.emit(version_mismatch(server_version, version()))
		return
	_synced = false
	_send_offline() # (first: the server knows whose coins these are, and adds in what is owed, before any room or shop request)
	connected.emit()


## What the menu says when the server and this game differ.
static func version_mismatch(server_version: String, game_version: String) -> String:
	return "Server is on a different version (server %s, game %s)" % [server_version, game_version]


## This build's network version: the game's config/version and a hash of Net's RPC set (each RPC's
## name, mode, channel and argument count), so any protocol change shows even under the same version
## number. --fake-version VALUE stands in for it (tests).
func version() -> String:
	var fake := Boot.arg("fake-version")
	if fake != "":
		return fake
	var rpcs: Dictionary = get_script().get_rpc_config()
	var args := {}
	for m in get_script().get_script_method_list():
		args[m.name] = m.args.size()
	var names := rpcs.keys().map(func(n: StringName) -> String: return str(n)) # (StringNames sort by address, not by name)
	names.sort()
	var signature := ""
	for n in names:
		signature += "%s/%s/%d;" % [n, JSON.stringify(rpcs[StringName(n)], "", true), args.get(StringName(n), -1)]
	return "%s+%s" % [ProjectSettings.get_setting("application/config/version", "?"), signature.md5_text().substr(0, 6)]


func leave() -> void:
	if (local or is_connected_to_server()) and room_code != "":
		leave_room.rpc_id(1) # (single player: the in-process server closes the room and goes)
	_clear_room()


func _clear_room() -> void:
	my_id = 0
	local = false
	room_code = ""
	host_id = 0
	lobby = {}
	players = {}
	card = {}
	rules = {}
	clock_ends = 0.0
	room_state = RoomState.LOBBY


# --- client → server ---------------------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func create_room(player_name: String) -> void:
	if server:
		server.on_create(multiplayer.get_remote_sender_id(), player_name)


@rpc("any_peer", "call_local", "reliable")
func join_room(code: String, player_name: String) -> void:
	if server:
		server.on_join(multiplayer.get_remote_sender_id(), code, player_name)


@rpc("any_peer", "call_local", "reliable")
func leave_room() -> void:
	if server:
		server.on_leave(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_local", "reliable")
func set_ready(ready: bool) -> void:
	if server:
		server.on_ready(multiplayer.get_remote_sender_id(), ready)


@rpc("any_peer", "call_local", "reliable")
func start_round() -> void:
	if server:
		server.on_start(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_local", "reliable")
func play_again() -> void:
	if server:
		server.on_play_again(multiplayer.get_remote_sender_id())


## spin < 0 means "decided later" (follow-through at landing); shot_spin carries it.
@rpc("any_peer", "call_local", "reliable")
func shot(dir: Vector3, path_angle: float, power: float, club: int, spin: float) -> void:
	if server:
		server.on_shot(multiplayer.get_remote_sender_id(), dir, path_angle, power, club, spin)


## Own swing (and the club in hand) while in Shooting, swing_send_hz, newest-wins like snapshots.
@rpc("any_peer", "call_local", "unreliable", 1)
func swing_state(seq: int, angle: float, pitch: float, club: int) -> void:
	if server:
		server.on_swing(multiplayer.get_remote_sender_id(), seq, angle, pitch, club)


## Own golfer while walking: where it stands and which way it faces, walk_send_hz, newest-wins.
@rpc("any_peer", "call_local", "unreliable", 1)
func walk_state(seq: int, position: Vector3, yaw: float) -> void:
	if server:
		server.on_walk(multiplayer.get_remote_sender_id(), seq, position, yaw)


## Host, in the lobby or between rounds: the room's custom rules (RoomRules); the server cleans them.
@rpc("any_peer", "call_local", "reliable")
func set_rules(wanted: Dictionary) -> void:
	if server:
		server.on_set_rules(multiplayer.get_remote_sender_id(), wanted)


## Retake the last shot (if a mulligan is left and the ball is at rest).
@rpc("any_peer", "call_local", "reliable")
func mulligan() -> void:
	if server:
		server.on_mulligan(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_local", "reliable")
func shot_spin(spin: float) -> void:
	if server:
		server.on_spin(multiplayer.get_remote_sender_id(), spin)


@rpc("any_peer", "call_local", "reliable")
func sync_offline(key: String, player_name: String, earned: int, bought: Array, worn: Dictionary) -> void:
	if server:
		server.on_sync_offline(multiplayer.get_remote_sender_id(), key, player_name, earned, bought, worn)


var _sent_offline := [0, []] # what the last sync_offline carried (taken off what is owed when answered)
var _synced := false # this connection's server has answered our sync: only then is its word on our profile kept


## The real (dedicated) server's word on this player's profile counts only once it has taken in what
## we owed (offline_synced on this connection): a server that has not (an older protocol, no answer
## yet) can never overwrite this computer's balance with its own.
func _trusted_server() -> bool:
	return is_connected_to_server() and _synced


## What this player owes the server from offline play (ProfileStore.offline()), sent on every connect.
## A profile from before the one balance (no server_balance: its coins and items were this computer's
## alone) brings them all, once: its balance plus what its items cost, and the items, bought again there.
func _send_offline() -> void:
	var me := ProfileStore.mine()
	var earned := int(me.get("pending", 0))
	var bought: Array = me.get("pending_buys", []).duplicate()
	if not me.has("server_balance"):
		bought = me.get("owned", []).duplicate()
		earned = int(me.balance)
		for item_id in bought:
			earned += ShopCatalog.item(str(item_id)).price if ShopCatalog.item(str(item_id)) else 0
	_sent_offline = [earned, bought]
	sync_offline.rpc_id(1, ProfileStore.my_key(), ProfileStore.my_name(), earned, bought, me.get("equipped", {}) if me.get("equip_dirty", false) else {})


@rpc("any_peer", "call_local", "reliable")
func shop_open(player_name: String) -> void:
	if server:
		server.on_shop_open(multiplayer.get_remote_sender_id(), player_name)


@rpc("any_peer", "call_local", "reliable")
func shop_buy(player_name: String, item_id: String) -> void:
	if server:
		server.on_shop_buy(multiplayer.get_remote_sender_id(), player_name, item_id)


@rpc("any_peer", "call_local", "reliable")
func shop_equip(player_name: String, tab: int, item_id: String) -> void:
	if server:
		server.on_shop_equip(multiplayer.get_remote_sender_id(), player_name, tab, item_id)


@rpc("any_peer", "call_local", "reliable")
func send_chat(text: String) -> void:
	if server:
		server.on_chat(multiplayer.get_remote_sender_id(), text)


## Own whiff (a swing past the ball without touching it): relayed to the room for other players' view of us.
@rpc("any_peer", "call_local", "reliable")
func whiffed() -> void:
	if server:
		server.on_whiff(multiplayer.get_remote_sender_id())


# --- server → clients --------------------------------------------------------------------------

## This player's coins for a hole (empty: just the balance, on joining) and their balance after it.
@rpc("authority", "call_local", "reliable")
func coins(awarded: Dictionary, new_balance: int) -> void:
	balance = new_balance
	if _trusted_server(): # the real server's: kept on this computer too
		ProfileStore.remember(new_balance)
	coins_received.emit(awarded)


## The shop's view of this player's profile, after an open, a buy or an equip (`why`: "" or why not).
@rpc("authority", "call_local", "reliable")
func shop_state(new_balance: int, owned: Array, equipped: Dictionary, why: String) -> void:
	if is_connected_to_server() and not _synced:
		return # (not our profile as it stands: the shop waits, then shows this computer's)
	balance = new_balance
	if _trusted_server():
		ProfileStore.remember(new_balance, owned, equipped)
	shop_changed.emit(owned, equipped, why)


@rpc("authority", "call_local", "reliable")
func offline_synced(new_balance: int, owned: Array, equipped: Dictionary) -> void:
	balance = new_balance
	var me := ProfileStore.mine()
	_synced = true
	me.pending = maxi(int(me.get("pending", 0)) - (int(_sent_offline[0]) if me.has("server_balance") else int(me.get("pending", 0))), 0)
	me.pending_buys = me.get("pending_buys", []).filter(func(i: Variant) -> bool: return not i in _sent_offline[1])
	me.equip_dirty = false
	ProfileStore.remember(new_balance, owned, equipped)
	offline_sync_done.emit()


@rpc("authority", "call_local", "reliable")
func chat(player_name: String, text: String) -> void:
	chat_received.emit(player_name, text)


@rpc("authority", "call_local", "reliable")
func remote_whiff(id: int) -> void:
	whiff_received.emit(id)


@rpc("authority", "call_local", "reliable")
func room_error(reason: String) -> void:
	room_failed.emit(reason)


@rpc("authority", "call_local", "reliable")
func lobby_state(code: String, host: int, state: int, members: Dictionary, room_rules: Dictionary) -> void:
	room_code = code
	host_id = host
	room_state = state
	lobby = members
	rules = room_rules
	lobby_changed.emit()


@rpc("authority", "call_local", "reliable")
func round_started(seed: int, number: int, rest_positions: Dictionary, roster: Dictionary, scores: Dictionary) -> void:
	my_id = multiplayer.get_unique_id()
	course_seed = seed
	hole_number = number
	rests = rest_positions
	players = roster
	card = scores
	room_state = RoomState.PLAYING
	clock_live = false
	round_began.emit()


@rpc("authority", "call_local", "reliable")
func start_hole(number: int, rest_positions: Dictionary) -> void:
	hole_number = number
	rests = rest_positions
	clock_live = false
	hole_started.emit(number, rest_positions)


## This client's own flyover of hole `number` is over (finished or skipped): its shot clock starts
## here and on the server. Nothing else waits on it, here or for anyone else.
func my_flyover_done(number: int) -> void:
	if number != hole_number or clock_live:
		return
	clock_live = true
	_start_clock()
	if not Boot.flag("no-flyover-ready"): # (test bot: the message lost)
		flyover_done.rpc_id(1, number)


## A client finished or skipped hole `number`'s flyover: its shot clock may start.
@rpc("any_peer", "call_local", "reliable")
func flyover_done(number: int) -> void:
	if server:
		server.on_flyover_done(multiplayer.get_remote_sender_id(), number)


@rpc("authority", "call_local", "reliable")
func at_rest(id: int, position: Vector3) -> void:
	if id == my_id and clock_live:
		_start_clock()
	ball_at_rest.emit(id, position)


## The own shot clock runs from each rest on a live hole (the server's runs on the same events).
func _start_clock() -> void:
	clock_ends = Time.get_ticks_msec() / 1000.0 + int(rules.get("shot_clock", 0)) if int(rules.get("shot_clock", 0)) > 0 else 0.0


## s left on the own shot clock, or -1 with no clock.
func clock_left() -> float:
	return maxf(clock_ends - Time.get_ticks_msec() / 1000.0, 0.0) if clock_ends > 0.0 else -1.0


@rpc("authority", "call_local", "reliable")
func player_update(id: int, player_name: String, strokes: int, score: int, message: String, mulligans: int) -> void:
	players[id] = {name = player_name, strokes = strokes, score = score, message = message, mulligans = mulligans,
		equipped = players.get(id, {}).get("equipped", {})} # (what they wear came with the roster)
	player_changed.emit(id)


@rpc("authority", "call_local", "reliable")
func player_left(id: int) -> void:
	players.erase(id)
	player_changed.emit(id)


## Another player's swing, stamped with the room's physics tick (the ball snapshots' clock).
@rpc("authority", "call_local", "unreliable", 1)
func remote_swing(id: int, seq: int, tick: int, angle: float, pitch: float, club: int) -> void:
	swing_received.emit(id, seq, tick, angle, pitch, club)


## Another player walking, stamped with the room's physics tick like remote_swing.
@rpc("authority", "call_local", "unreliable", 1)
func remote_walk(id: int, seq: int, tick: int, position: Vector3, yaw: float) -> void:
	walk_received.emit(id, seq, tick, position, yaw)


## Per ball: peer id, position mm (x, y, z), velocity mm/s (x, y, z).
@rpc("authority", "call_local", "unreliable", 1)
func snapshot(tick: int, data: PackedInt32Array) -> void:
	snapshot_received.emit(tick, data)


@rpc("authority", "call_local", "reliable")
func scorecard(scores: Dictionary) -> void:
	card = scores
	card_changed.emit()


@rpc("authority", "call_local", "reliable")
func hole_complete(scores: Dictionary) -> void:
	card = scores
	card_changed.emit()
	hole_completed.emit()


@rpc("authority", "call_local", "reliable")
func round_over(scores: Dictionary) -> void:
	card = scores
	room_state = RoomState.ROUND_OVER
	card_changed.emit()
	round_ended.emit()
