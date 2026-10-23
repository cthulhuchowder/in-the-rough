extends Node
## Autoload "SteamInvites": Steam friend invites through GodotSteam (AppID from net.tres; 480 is
## Valve's test app). Our "connect string" is the room code: inviting opens the Steam overlay,
## and accepting launches or focuses the game with --room CODE (join_requested). Without Steam
## running, or without the GodotSteam extension (the Linux server), this is a no-op.

signal join_requested(code: String)

var available := false

var _steam: Object


func _ready() -> void:
	if DisplayServer.get_name() == "headless" or Boot.flag("server") or Boot.flag("bot") \
			or not Engine.has_singleton("Steam"):
		return
	_steam = Engine.get_singleton("Steam")
	var result: Dictionary = _steam.steamInitEx(Net.PARAMS.steam_app_id, true)
	available = result.get("status", -1) == 0
	if not available:
		print("Steam invites off: %s" % result.get("verbal", "Steam not running"))
		return
	_steam.join_game_requested.connect(func(_user: int, connect: String):
		var code := _code_in(connect)
		if code != "":
			join_requested.emit(code))
	Net.lobby_changed.connect(func(): _steam.setRichPresence("connect", "--room " + Net.room_code if Net.room_code != "" else ""))


func invite() -> void:
	if available and Net.room_code != "":
		_steam.activateGameOverlayInviteDialogConnectString("--room " + Net.room_code)


static func _code_in(connect: String) -> String:
	var parts := connect.split(" ", false)
	var i := parts.find("--room")
	return parts[i + 1] if i >= 0 and i + 1 < parts.size() else ""
