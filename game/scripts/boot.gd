class_name Boot
extends Node
## Entry scene. --server: headless authority. Otherwise the lobby (test bots use it too, with
## --bot). Flags work before or after "--".


static func flag(key: String) -> bool:
	return ("--" + key) in (OS.get_cmdline_args() + OS.get_cmdline_user_args())


static func arg(key: String, fallback := "") -> String:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	var i := args.find("--" + key)
	if i < 0 or i + 1 >= args.size():
		return fallback
	return args[i + 1]


## The game was "game" before it was In The Rough: user:// moved with the name (Godot keys it on
## config/name). Once, on the first run under the new name, copy the old folder's files (profile,
## coins, settings, the look) across, never over anything already there. Server and clients alike.
static func migrate_user_data(old_name := "game") -> int:
	var here := OS.get_user_data_dir()
	return migrate(here.get_base_dir().path_join(old_name), here)


## The files of `old` copied into `here` (none over existing ones), once (a .migrated marker).
static func migrate(old: String, here: String) -> int:
	if old == here or not DirAccess.dir_exists_absolute(old) or FileAccess.file_exists(here.path_join(".migrated")):
		return 0
	var copied := _copy_tree(old, here)
	var mark := FileAccess.open(here.path_join(".migrated"), FileAccess.WRITE)
	if mark:
		mark.store_string(old)
	return copied


static func _copy_tree(from: String, to: String) -> int:
	DirAccess.make_dir_recursive_absolute(to)
	var copied := 0
	for file in DirAccess.get_files_at(from):
		if not FileAccess.file_exists(to.path_join(file)):
			copied += int(DirAccess.copy_absolute(from.path_join(file), to.path_join(file)) == OK)
	for dir in DirAccess.get_directories_at(from):
		if dir != "shader_cache" and dir != "vulkan": # (engine caches: rebuilt anyway)
			copied += _copy_tree(from.path_join(dir), to.path_join(dir))
	return copied


func _ready() -> void:
	if not OS.get_cmdline_args().has("-s"): # (tests and captures leave the user's folders alone)
		migrate_user_data()
	if flag("server"):
		get_tree().root.add_child.call_deferred(GameServer.new())
		return
	if flag("bot"):
		Net.bot = true
		Net.report_path = arg("report")
		Net.connection_failed.connect(func(reason: String):
			printerr("bot: " + reason)
			get_tree().quit(1))
		Net.room_failed.connect(func(reason: String):
			printerr("bot: " + reason)
			get_tree().quit(1))
	get_tree().change_scene_to_file.call_deferred("res://lobby.tscn")
