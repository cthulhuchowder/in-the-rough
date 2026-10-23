extends SceneTree
## The game is In The Rough: its name (window title), the lobby's title and the export file names;
## and a player's saved files (profile, coins, settings, the look) come across from the old "game"
## user folder on the first run, never over anything already there, and only once.
## Run: godot --headless --path game -s res://tests/rename_test.gd

var _failed := false


func _check(ok: bool, what: String) -> void:
	_failed = _failed or not ok
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])


func _initialize() -> void:
	var name: String = ProjectSettings.get_setting("application/config/name")
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	var title: String = " ".join(load("res://scripts/menu_scene.gd").TITLE)
	_check(name == "In The Rough" and title == "IN THE ROUGH" and presets.contains("InTheRough.exe")
		and presets.contains("InTheRough.zip") and presets.contains("in-the-rough-server.x86_64") and not presets.contains("golf"),
		"named In The Rough: window title, the menu's title, InTheRough.exe / .zip, in-the-rough-server.x86_64")
	var base := OS.get_cache_dir().path_join("itr_rename_test_%d" % Time.get_ticks_usec())
	var old := base.path_join("game")
	var here := base.path_join("In The Rough")
	DirAccess.make_dir_recursive_absolute(old.path_join("sub"))
	DirAccess.make_dir_recursive_absolute(here)
	for f in [["profile.json", "{\"balance\": 420}"], ["settings.cfg", "old"], ["sub/look.tres", "look"]]:
		var w := FileAccess.open(old.path_join(f[0]), FileAccess.WRITE)
		w.store_string(f[1])
		w.close()
	var keep := FileAccess.open(here.path_join("settings.cfg"), FileAccess.WRITE)
	keep.store_string("new")
	keep.close()
	var boot: GDScript = load("res://scripts/boot.gd") # (at run time: it names the Net autoload)
	var copied: int = boot.migrate(old, here)
	var again: int = boot.migrate(old, here)
	_check(copied == 2 and again == 0 and FileAccess.get_file_as_string(here.path_join("profile.json")).contains("420")
		and FileAccess.get_file_as_string(here.path_join("settings.cfg")) == "new" and FileAccess.file_exists(here.path_join("sub/look.tres")),
		"the old folder's saves come across (%d files), none over a newer one, only once (%d the second time)" % [copied, again])
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)
