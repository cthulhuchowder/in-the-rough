class_name ProfileStore
## Player profiles — name, coin balance, stats — kept in one JSON file and written whole each change
## (to a temp file, then renamed over it, the one before kept as <file>.bak, so a crash never leaves half
## a file). A file that is there but does not read back as profiles is never saved over (loaded false). The dedicated server keeps
## one next to its binary for every name that plays there; offline (single player) is
## user://profile.json. ponytail: a JSON file, not SQLite — no SQLite binding is in the project
## (it needs the godot-sqlite GDExtension); swap this class's load/save for it when added, the
## rest only calls get/save.

var path := ""
var loaded := true ## false: the file was there but would not read (empty, cut short, not JSON): never saved over
var profiles := {} ## name → {name, balance, stats {rounds, holes, coins_earned, holes_in_one, best_drive}, synced}; offline also pending, pending_buys, equip_dirty

static var _offline: ProfileStore # this computer's, loaded once and shared (the local server, menu, shop, Net)
static var test_path := "" ## tests: offline() on this file instead of in memory (never the player's own)
static var test_key := "" ## tests: this computer's player key
static var _key := ""
const KEY_PATH := "user://player.key"


static func open(at: String) -> ProfileStore:
	var store := ProfileStore.new()
	store.path = at
	if not FileAccess.file_exists(at):
		return store # (a first run: nothing to keep)
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(at))
	if data is Dictionary:
		store.profiles = data
	else:
		store.loaded = false
		push_error("profiles: %s would not read; left as it is, nothing will be saved over it" % at)
	return store


func has(player_name: String) -> bool:
	return profiles.has(player_name)


## The profile for this name, made on first use.
func get_profile(player_name: String) -> Dictionary:
	if not profiles.has(player_name):
		profiles[player_name] = {name = player_name, balance = 0, synced = false,
			stats = {rounds = 0, holes = 0, coins_earned = 0, holes_in_one = 0, best_drive = 0.0}}
	return profiles[player_name]


func save() -> void:
	if path == "":
		return
	if not loaded:
		push_error("profiles: not saving over %s (it did not load)" % path)
		return
	var temp := path + ".tmp"
	var f := FileAccess.open(temp, FileAccess.WRITE)
	if f == null:
		push_warning("profiles: cannot write %s" % temp)
		return
	f.store_string(JSON.stringify(profiles, "\t"))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, path + ".bak")
		DirAccess.remove_absolute(path) # (Windows will not rename over a file)
	DirAccess.rename_absolute(temp, path)


## This computer's profiles (user://profile.json): one balance per name, the same one everywhere. Online
## it mirrors the server's (remember()); earned or spent offline it changes here and is owed to the
## server (pending: coins earned, pending_buys: items bought, equip_dirty: looks worn) until the next
## connect sends it (Net). One shared instance, so no copy ever saves over another's change.
static func offline() -> ProfileStore:
	if _offline == null and test_path != "":
		_offline = open(test_path)
	if _offline == null:
		var own := not Settings._running_script() and not "--bot" in OS.get_cmdline_user_args() # (tests, captures, bots: in memory only, the player's own untouched)
		_offline = open("user://profile.json") if own else ProfileStore.new()
	return _offline


## This computer's player key: 32 random hex digits, made on its first launch and kept in
## user://player.key. The coins, items and stats belong to it, here and on the server; the name is only
## what others see, free to change. A secret: whoever has it has the coins, so it goes to the server
## alone (sync_offline), never to other players. Tests and bots: one in memory per process (a bot may
## be handed one with --key).
static func my_key() -> String:
	if _key != "":
		return _key
	var args := OS.get_cmdline_user_args()
	var at := args.find("--key")
	if test_key != "":
		_key = test_key
	elif at >= 0 and at + 1 < args.size() and is_key(args[at + 1]):
		_key = args[at + 1]
	elif Settings._running_script() or "--bot" in args:
		_key = new_key()
	else:
		_key = FileAccess.get_file_as_string(KEY_PATH).strip_edges() if FileAccess.file_exists(KEY_PATH) else ""
		if not is_key(_key): # (first launch, or a broken file: mine() adopts the profile left on this computer)
			_key = new_key()
			var f := FileAccess.open(KEY_PATH, FileAccess.WRITE)
			if f:
				f.store_string(_key)
				f.close()
	return _key


static func new_key() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


static func is_key(key: String) -> bool:
	return key.length() == 32 and key.is_valid_hex_number()


## This computer's player's profile, under its key, named with the current name. The first time a key
## has none here, the profile from before keys (under the player's name, or else the only one on this
## computer) moves to it; the server never had it under the key, so all of it goes there at the next
## sync (no server_balance).
static func mine() -> Dictionary:
	var store := offline()
	var key := my_key()
	if not store.profiles.has(key):
		var old := my_name() if store.profiles.has(my_name()) else (str(store.profiles.keys()[0]) if store.profiles.size() == 1 else "")
		if old != "":
			var prof: Dictionary = store.profiles[old]
			store.profiles.erase(old)
			prof.erase("server_balance")
			prof.pending = 0
			prof.pending_buys = []
			store.profiles[key] = prof
			store.save()
	var me := store.get_profile(key)
	me.name = my_name()
	return me


## A player's name as shown (the menu's chip; trimmed, "Player" when empty).
static func clean_name(player_name: String) -> String:
	var n := player_name.strip_edges().left(24)
	return n if n != "" else "Player"


## This player's name (the menu's profile chip).
static func my_name() -> String:
	return clean_name(Settings.player_name)


## The server's word on this player's profile, kept here so offline shows the same.
static func remember(balance: int, owned: Variant = null, equipped: Variant = null) -> void:
	var store := offline()
	var me := mine()
	me.balance = balance
	me.server_balance = balance # (what the server holds: a profile without it predates the one balance)
	if owned is Array:
		me.owned = owned
	if equipped is Dictionary:
		me.equipped = equipped
	me.synced = true
	store.save()
