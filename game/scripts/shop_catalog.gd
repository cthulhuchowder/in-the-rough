class_name ShopCatalog
extends Resource
## The shop's items, and the rules for buying and wearing them — the same on the server (online:
## it holds the coins) and offline (the local profile). A profile's `owned` lists item ids;
## `equipped` maps a tab's name to an item id ("" = the standard look). look_for() turns that into
## the CharacterLook the golfer and ball are drawn with. Values in data/shop_catalog.tres.

static var _catalog: Resource # data/shop_catalog.tres, loaded on first use (it is made of this script)
const DEFAULT_LOOK: CharacterLook = preload("res://data/characters/default_look.tres")
const LOOK_PATH := "user://look.tres" ## the player's equipped look, for their own golfer
const TAB_NAMES := ["Hat", "Shirt", "Pants", "Shoes", "Ball", "Club set", "Trail"]

@export var items: Array[ShopItem] = []


static func item(item_id: String) -> ShopItem:
	for it in catalog().items:
		if it.id == item_id:
			return it
	return null


static func tab_key(tab: int) -> String:
	return TAB_NAMES[tab].to_lower().replace(" ", "_")


## Buy: an item that exists, not owned yet, and affordable; spends the coins. "" or why not.
static func buy(profile: Dictionary, item_id: String) -> String:
	var it := item(item_id)
	if it == null:
		return "No such item"
	var owned: Array = profile.get("owned", [])
	if item_id in owned:
		return "Already owned"
	if int(profile.get("balance", 0)) < it.price:
		return "Not enough coins"
	profile.balance = int(profile.balance) - it.price
	owned.append(item_id)
	profile.owned = owned
	return ""


## Equip an owned item (or "" for the tab's standard look). "" or why not.
static func equip(profile: Dictionary, tab: int, item_id: String) -> String:
	if tab < 0 or tab >= TAB_NAMES.size():
		return "No such tab"
	if item_id != "":
		var it := item(item_id)
		if it == null or it.tab != tab:
			return "No such item"
		if not item_id in profile.get("owned", []):
			return "Not owned"
	var equipped: Dictionary = profile.get("equipped", {})
	equipped[tab_key(tab)] = item_id
	profile.equipped = equipped
	return ""


## The look these equipped items make, over the standard one.
static func look_for(equipped: Dictionary) -> CharacterLook:
	var look: CharacterLook = DEFAULT_LOOK.duplicate()
	for key in equipped:
		var it := item(str(equipped[key]))
		if it == null:
			continue
		match it.tab:
			ShopItem.Tab.HAT:
				look.hat = it.color
				look.hat_style = it.style
			ShopItem.Tab.SHIRT:
				look.shirt = it.color
				look.shirt_style = it.style
			ShopItem.Tab.PANTS:
				look.pants = it.color
				look.pants_style = it.style
			ShopItem.Tab.SHOES:
				look.shoes = it.color
				look.shoe_style = it.style
			ShopItem.Tab.BALL:
				look.ball_color = it.color
				look.ball_accent = it.accent
				look.ball_style = it.style
			ShopItem.Tab.CLUB:
				look.club = it.color
				look.club_style = it.style
			ShopItem.Tab.TRAIL:
				look.trail_style = it.style
	return look


## The player's own look: as last equipped (saved by the shop), else the standard one. Script runs
## (tests, captures) always get the standard one, or with GOLF_TEST_EQUIP set (item ids, comma
## separated) those items over it: the feel tests run with each club set.
static func my_look() -> CharacterLook:
	if OS.get_environment("GOLF_TEST_EQUIP") != "" and OS.get_cmdline_args().has("-s"):
		var wearing := {}
		for id in OS.get_environment("GOLF_TEST_EQUIP").split(","):
			if item(id):
				wearing[tab_key(item(id).tab)] = id
		return look_for(wearing)
	if Engine.get_main_loop() and not OS.get_cmdline_args().has("-s") and ResourceLoader.exists(LOOK_PATH):
		var saved := ResourceLoader.load(LOOK_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as CharacterLook
		if saved:
			return saved
	return DEFAULT_LOOK.duplicate()


static func save_my_look(equipped: Dictionary) -> void:
	if not OS.get_cmdline_args().has("-s"): # (tests and captures never touch the player's own look)
		ResourceSaver.save(look_for(equipped), LOOK_PATH)


## The shop's items (data/shop_catalog.tres).
static func catalog() -> ShopCatalog:
	if _catalog == null:
		_catalog = load("res://data/shop_catalog.tres")
	return _catalog
