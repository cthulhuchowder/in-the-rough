extends SceneTree
## The main menu. The left column — Play (its panel: Single player, Host a room, Join with code),
## Practice, Shop, Settings, Quit — each button sliding out on hover with a soft click; the profile
## chip (the name, edited in place, and the coins); the version; Settings opens the settings page and
## Back returns. The backdrop: a biome (random unless set), the title IN THE ROUGH in block letters
## (a ball dotting the I, a tuft on the R) bouncing in and settling, the golfer, flag, cart and caddy on
## the right of it.
## Run: godot --headless --path game -s res://tests/menu_test.gd

var _failed := false


func _check(ok: bool, what: String) -> void:
	_failed = _failed or not ok
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])


func _initialize() -> void:
	var lobby: Control = load("res://lobby.tscn").instantiate()
	root.add_child(lobby)
	await process_frame
	var column: Array = lobby.get_node("Entry/Column").get_children().map(func(b: Node) -> String: return (b as Button).text)
	var play_rows: Array = lobby.get_node("%PlayPanel").find_children("*", "Button", true, false).map(func(b: Node) -> String: return (b as Button).text)
	_check(column == ["Play", "Practice", "Shop", "Settings", "Quit"] and play_rows == ["Single player", "Host a room", "Join with code"],
		"the left column %s; Play's panel %s" % [column, play_rows])
	var panel: Control = lobby.get_node("%PlayPanel")
	var closed := not panel.visible
	(lobby.get_node("%Play") as Button).pressed.emit()
	_check(closed and panel.visible, "Play opens its panel")
	var shop: Button = lobby.get_node("%Shop")
	var x0 := shop.position.x
	shop.mouse_entered.emit()
	for i in 20:
		await process_frame
	var out := shop.position.x - x0
	shop.mouse_exited.emit()
	for i in 20:
		await process_frame
	_check(out > 5.0 and absf(shop.position.x - x0) < 0.5 and lobby._click.stream != null, "hover: the button slides out %.0f px with a click, and back" % out)
	(lobby.get_node("%NameShown") as Button).pressed.emit()
	var editing: bool = (lobby.get_node("%Name") as LineEdit).visible
	(lobby.get_node("%Name") as LineEdit).text = "Ana"
	lobby._name_done()
	_check(editing and (lobby.get_node("%NameShown") as Button).text == "Ana" and lobby._player_name() == "Ana" and (lobby.get_node("%Coins") as Label).text.is_valid_int(),
		"the profile chip: click edits the name in place (now %s), coins %s" % [lobby._player_name(), (lobby.get_node("%Coins") as Label).text])
	_check((lobby.get_node("%Version") as Label).text == "v" + str(ProjectSettings.get_setting("application/config/version")), "the version bottom right (%s)" % (lobby.get_node("%Version") as Label).text)
	(lobby.get_node("%Settings") as Button).pressed.emit()
	await process_frame
	var settings: Control = lobby._settings_menu
	var shown: bool = settings != null and settings.visible and settings.get("_settings").visible
	settings.get("_settings").get_children().filter(func(c: Node) -> bool: return c is Button and (c as Button).text == "Back")[0].pressed.emit()
	_check(shown and not settings.visible, "Settings opens the settings page; Back closes it")
	lobby.free()

	var menu_script: GDScript = load("res://scripts/menu_scene.gd")
	menu_script.set("biome_override", 6)
	var scene: Node3D = menu_script.new()
	root.add_child(scene)
	await process_frame
	var letters: Array = scene._letters
	var high: bool = letters.all(func(l: Node3D) -> bool: return l.position.y > (l.get_meta("rest") as Vector3).y + 1.0)
	var t := 0.0
	while t < 3.5:
		scene._process(1.0 / 60.0)
		t += 1.0 / 60.0
	var settled: bool = letters.all(func(l: Node3D) -> bool: return l.position.is_equal_approx(l.get_meta("rest")))
	var ball := false
	var tuft := false
	for l: Node3D in letters:
		ball = ball or l.get_child_count() > 1 and l.get_child(1) is MeshInstance3D and l.get_child_count() == 2
		tuft = tuft or l.get_child_count() > 3
	_check(letters.size() == 10 and high and settled and ball and tuft,
		"the title: %d letters, starting high, bounced in and settled by 3.5 s; a ball on the I, a tuft on the R" % letters.size())
	var right: bool = scene._rig.global_position.x > scene._centre.x and scene._caddy.global_position.x > scene._centre.x
	_check(scene.biome.name == "cemetery" and right, "the backdrop in its biome (%s), golfer and caddy right of the frame's centre" % scene.biome.name)
	menu_script.set("biome_override", -1)
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)
