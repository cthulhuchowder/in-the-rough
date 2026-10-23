extends Control
## Lobby flow: Host makes a room and shows its code; Join takes a code; Play makes a room of one on a
## local server (single player). In the room: names,
## ready toggles, the room's rules (the host picks; saved as their default), Start for the host
## once everyone is ready, Steam invites when available.
## The server address never appears: it comes from net.tres.
## Test bots drive the same screen: --create [--code-file PATH] [--expect N] [--rules k=v,...] or --code CODE.

@onready var _entry: Control = %Entry
@onready var _room: Control = %Room
@onready var _name: LineEdit = %Name
@onready var _code: LineEdit = %Code
@onready var _status: Label = %Status
@onready var _room_title: Label = %RoomTitle
@onready var _players: VBoxContainer = %Players
@onready var _ready_toggle: CheckButton = %Ready
@onready var _start: Button = %Start
@onready var _invite: Button = %Invite
@onready var _name_shown: Button = %NameShown
@onready var _coins: Label = %Coins

const FEEDBACK: FeedbackParams = preload("res://data/feedback.tres")
const SOUNDS: SoundParams = preload("res://data/sounds.tres") ## hover, click, back
const NUDGE := 10.0 ## px a hovered menu button slides out
var _click := AudioStreamPlayer.new()
var _settings_menu: EscMenu

var _pending: Callable # what to send once connected
var _rule_pickers := {} # rule key → OptionButton (host picks, everyone sees)
var _rules_sent := false # the host's saved rules go to a new room once

# Rule key → [label, values, how each value reads]
const RULE_ROWS := [
	["holes", "Holes", RoomRules.HOLES, "%d"],
	["shot_clock", "Shot clock", RoomRules.SHOT_CLOCK, "%d s"],
	["wind", "Wind", [0, 1, 2], ""],
	["mulligans", "Mulligans per round", RoomRules.MULLIGANS, "%d"],
	["gimme", "Gimme radius (putts)", RoomRules.GIMME, "%s m"],
	["biome", "Biome", [0, 1, 2, 3, 4, 5, 6, 7], ""], # RoomRules.BIOMES
]


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	theme = EscMenu.theme_of() # the HUD's flat rounded look
	_build_menu()
	%Host.pressed.connect(func(): _with_server(func(): Net.create_room.rpc_id(1, _player_name())))
	%Join.pressed.connect(_join_typed)
	_code.text_submitted.connect(func(_t): _join_typed())
	%Offline.pressed.connect(_play_local)
	%Shop.pressed.connect(func() -> void: # the fitting room: coins, items, looks
		ShopScene.player_name = _player_name()
		get_tree().change_scene_to_file("res://shop.tscn"))
	%Practice.pressed.connect(func() -> void: # the range and putting green, offline, no scoring
		PracticeRange.requested = true
		get_tree().change_scene_to_file("res://main.tscn"))
	%Leave.pressed.connect(func():
		ui_sound(SOUNDS.ui_back)
		Net.leave()
		_refresh())
	_ready_toggle.toggled.connect(func(on: bool): Net.set_ready.rpc_id(1, on))
	_start.pressed.connect(func(): Net.start_round.rpc_id(1))
	_invite.pressed.connect(SteamInvites.invite)
	_invite.visible = SteamInvites.available
	Net.connected.connect(_on_connected)
	Net.offline_sync_done.connect(_show_profile) # (the server's balance, offline play added in)
	Net.connection_failed.connect(func(reason: String): if not Net.local: _show_status(reason)) # (multiplayer only)
	Net.room_failed.connect(_show_status)
	Net.lobby_changed.connect(_refresh)
	Net.round_began.connect(func(): get_tree().change_scene_to_file("res://main.tscn"))
	SteamInvites.join_requested.connect(_join)
	_build_rules()
	if DisplayServer.get_name() != "headless": # the live backdrop (bots run headless)
		add_child(MenuScene.new())
		move_child(get_child(-1), 0)
		$Background.hide()
	_refresh()
	if Net.bot:
		_bot_start()
	elif Boot.arg("room") != "":
		_join(Boot.arg("room")) # launched from a Steam invite


## The left column (Play opens its panel: Single player, Host a room, Join with code; Practice; Shop;
## Settings; Quit), each button sliding out a little with a soft click when hovered; the profile chip
## top left (the name: click to edit; the coins); the version bottom right.
func _build_menu() -> void:
	_click.volume_db = SOUNDS.ui_db
	_click.bus = Settings.SFX_BUS
	add_child(_click)
	%Play.pressed.connect(func() -> void: %PlayPanel.visible = not %PlayPanel.visible)
	%Settings.pressed.connect(_open_settings)
	%Quit.pressed.connect(func() -> void: get_tree().quit())
	for button in (%Entry as Node).find_children("*", "Button", true, false):
		_juice(button)
	_name.text = Settings.player_name
	_name_shown.pressed.connect(func() -> void: # edit the name in place
		_name_shown.hide()
		_name.show()
		_name.grab_focus()
		_name.select_all())
	_name.text_submitted.connect(func(_t: String) -> void: _name.release_focus())
	_name.focus_exited.connect(_name_done)
	%Profile.get_node("Row").add_child(Hud.coin_icon(20.0))
	%Profile.get_node("Row").move_child(_coins, -1) # (the coin, then the count)
	_show_profile()
	%Profile.add_theme_stylebox_override("panel", EscMenu._box(FEEDBACK.meter_back, FEEDBACK.meter_frame, 10, 10))
	%Version.text = "v%s" % ProjectSettings.get_setting("application/config/version", "0")


func _name_done() -> void:
	_name.hide()
	_name_shown.show()
	if _name.text.strip_edges() != Settings.player_name:
		Settings.change("player_name", _name.text.strip_edges())
	_show_profile()


## The chip: the name, and this name's coins (the server's once online, else this computer's).
func _show_profile() -> void:
	_name_shown.text = _player_name()
	var coins := int(ProfileStore.mine().balance) # (the one balance: the server's as last heard, plus offline play)
	_coins.text = str(coins)


## Hover: the button slides out by NUDGE and clicks softly; back when the pointer leaves.
func _juice(button: Button) -> void:
	button.mouse_entered.connect(func() -> void:
		if button.disabled:
			return
		var tween := button.create_tween()
		tween.tween_property(button, "position:x", button.get_meta("rest_x", button.position.x) + NUDGE, 0.08)
		if not button.has_meta("rest_x"):
			button.set_meta("rest_x", button.position.x)
		ui_sound(SOUNDS.ui_hover))
	button.pressed.connect(func() -> void: ui_sound(SOUNDS.ui_click))
	button.mouse_exited.connect(func() -> void:
		if button.has_meta("rest_x"):
			button.create_tween().tween_property(button, "position:x", float(button.get_meta("rest_x")), 0.1))


func ui_sound(stream: AudioStream) -> void:
	_click.stream = stream
	_click.play()


func _open_settings() -> void:
	if _settings_menu == null:
		_settings_menu = EscMenu.new() # its settings page alone (no game behind it)
		add_child(_settings_menu)
	_settings_menu.show_settings_only()


func _player_name() -> String:
	return ProfileStore.clean_name(_name.text)


func _join_typed() -> void:
	_join(_code.text)


func _join(code: String) -> void:
	code = code.strip_edges().to_upper()
	if code.length() != Net.PARAMS.room_code_length:
		_show_status("Room codes are %d characters" % Net.PARAMS.room_code_length)
		return
	_with_server(func(): Net.join_room.rpc_id(1, code, _player_name()))


## Play: single player is a room like any other, on a server inside this game (the same server
## code, so the same rules and physics) that never touches the network; gone when the room closes.
func _play_local() -> void:
	if Net.server == null:
		var server := GameServer.new()
		server.local = true
		get_tree().root.add_child(server) # outlives the lobby scene
	Net.local = true
	_pending = Callable() # (a Host or Join still connecting is dropped)
	_show_status("")
	Net.create_room.rpc_id(1, _player_name())


func _with_server(action: Callable) -> void:
	_pending = action
	_show_status("Connecting…")
	Net.connect_to_server()


func _on_connected() -> void:
	_show_status("")
	if _pending.is_valid():
		_pending.call()
		_pending = Callable()


func _show_status(text: String) -> void:
	_status.text = text


func _refresh() -> void:
	var in_room := Net.room_code != ""
	_entry.visible = not in_room
	_room.visible = in_room
	%Profile.visible = not in_room
	if is_node_ready():
		_show_profile()
	if not in_room:
		return
	_room_title.text = "Single player" if Net.local else "Room  %s" % Net.room_code
	_ready_toggle.visible = not Net.local
	_invite.visible = SteamInvites.available and not Net.local
	%Room.get_node("Hint").visible = not Net.local # single player: no code to share, no list of one, plain Start
	_players.visible = not Net.local
	_start.text = "Start" if Net.local else "Start (everyone ready)"
	if Net.local and not Net.lobby.get(multiplayer.get_unique_id(), {}).get("ready", true):
		(func(): Net.set_ready.rpc_id(1, true)).call_deferred() # just you: Start is enough (deferred: in-process
		# the server answers inside this call, re-entering _refresh)
	for child in _players.get_children():
		child.queue_free()
	var all_ready := true
	for id in Net.lobby:
		var p: Dictionary = Net.lobby[id]
		var line := Label.new()
		line.text = "%s  %s%s" % ["✓" if p.ready else "·", p.name, "  (host)" if id == Net.host_id else ""]
		_players.add_child(line)
		all_ready = all_ready and p.ready
	var me: Dictionary = Net.lobby.get(multiplayer.get_unique_id(), {})
	_ready_toggle.set_pressed_no_signal(me.get("ready", false))
	_start.visible = Net.is_host()
	_start.disabled = not all_ready
	_refresh_rules()
	if Net.room_state != Net.RoomState.LOBBY:
		_show_status("Round in progress — you'll join the current hole")
	if Net.bot:
		_bot_lobby(all_ready)


# --- room rules --------------------------------------------------------------------------------

func _build_rules() -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	for row in RULE_ROWS:
		var label := Label.new()
		label.text = row[1]
		grid.add_child(label)
		var pick := OptionButton.new()
		for v in row[2]:
			var off: bool = (row[0] in ["shot_clock", "gimme"] and float(v) == 0.0)
			pick.add_item("Off" if off else (RoomRules.WIND[v] if row[0] == "wind" else (RoomRules.BIOMES[v] if row[0] == "biome" else row[3] % v)))
		pick.item_selected.connect(func(_i: int): _send_rules())
		grid.add_child(pick)
		_rule_pickers[row[0]] = pick
	_room.add_child(grid)
	_room.move_child(grid, _players.get_index() + 1)


## Host: what the pickers say → the server, and saved as this player's default.
func _send_rules() -> void:
	var wanted := {}
	for row in RULE_ROWS:
		var i: int = _rule_pickers[row[0]].selected
		if i >= 0:
			wanted[row[0]] = row[2][i]
	Net.set_rules.rpc_id(1, wanted)
	Settings.change("room_rules", wanted)


## Pickers show the room's rules; only the host, between rounds, can change them.
func _refresh_rules() -> void:
	if Net.is_host() and not _rules_sent and Net.room_state == Net.RoomState.LOBBY:
		_rules_sent = true
		var saved: Dictionary = _bot_rules() if Net.bot else Settings.room_rules
		if not saved.is_empty():
			Net.set_rules.rpc_id(1, saved)
	for row in RULE_ROWS:
		var pick: OptionButton = _rule_pickers[row[0]]
		var at := -1
		for i in row[2].size():
			if Net.rules.has(row[0]) and is_equal_approx(float(row[2][i]), float(Net.rules[row[0]])):
				at = i
		pick.select(at)
		pick.disabled = not Net.is_host() or Net.room_state == Net.RoomState.PLAYING


# --- test bots ---------------------------------------------------------------------------------

## --rules holes=3,shot_clock=5 → {holes = 3, shot_clock = 5}
func _bot_rules() -> Dictionary:
	var out := {}
	for pair in Boot.arg("rules").split(",", false):
		var kv := pair.split("=")
		if kv.size() == 2:
			out[kv[0]] = float(kv[1])
	return out



func _bot_start() -> void:
	_name.text = Boot.arg("name", "bot")
	if Boot.flag("create"):
		_with_server(func(): Net.create_room.rpc_id(1, _player_name()))
	else:
		_join(Boot.arg("code"))


func _bot_lobby(all_ready: bool) -> void:
	var me: Dictionary = Net.lobby.get(multiplayer.get_unique_id(), {})
	if not me.get("ready", false):
		Net.set_ready.rpc_id(1, true)
	if Boot.arg("code-file") != "" and not FileAccess.file_exists(Boot.arg("code-file")):
		var f := FileAccess.open(Boot.arg("code-file"), FileAccess.WRITE)
		f.store_string(Net.room_code)
		f.close()
	var wanted := _bot_rules()
	var rules_in := wanted.keys().all(func(k): return is_equal_approx(float(Net.rules.get(k, -1)), float(wanted[k])))
	if Net.is_host() and all_ready and rules_in and Net.lobby.size() >= int(Boot.arg("expect", "1")):
		Net.start_round.rpc_id(1)
