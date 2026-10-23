extends SceneTree
## The menu's title never goes behind the button column. At 16:9 and 16:10, at 16 points through
## the camera's drift (one full to and fro), the title's whole on-screen box (every letter, the ball
## on the I, the tuft on the R: every mesh's bounds, projected) stays at least MARGIN px right of the
## column's right edge. The worst point is saved as docs/art/menu-drift-check.png, the box drawn.
## Windowed (it renders): godot --path game -s res://tests/menu_drift_test.gd

const MARGIN := 40.0 ## window px
const SIZES := [Vector2i(1920, 1080), Vector2i(1920, 1200)] ## 16:9, 16:10
const POINTS := 16

var _failed := false


func _check(ok: bool, what: String) -> void:
	_failed = _failed or not ok
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])


func _initialize() -> void:
	var worst := {margin = INF}
	for size: Vector2i in SIZES:
		DisplayServer.window_set_size(size)
		for i in 30: # (the resize and the stretch settle)
			await process_frame
		var lobby: Control = load("res://lobby.tscn").instantiate()
		root.add_child(lobby)
		for i in 5:
			await process_frame
		var scene: Node3D = lobby.find_children("*", "MenuScene", true, false)[0]
		scene.set_process(false) # (driven here, point by point)
		var scale: float = root.get_final_transform().x.x # canvas units → window px
		var column: float = lobby.get_node("Entry/Column").get_global_rect().end.x * scale
		var period: float = TAU / scene.PARAMS.orbit_speed
		var least := INF
		var least_k := 0
		var cast_out := -INF # the golfer and flag: px past the right edge, at worst (< 0: to spare)
		for k in POINTS:
			scene._t = 100.0 * period + period * k / POINTS # (long after the bounce-in: every letter at rest)
			scene._process(0.0)
			var box := _title_box(scene)
			var margin := box.position.x * scale - column
			var cast := _box_of(scene, [scene._rig, scene.find_children("*", "Hole", true, false)[0]._pin])
			cast_out = maxf(cast_out, cast.end.x * scale - size.x)
			if margin < least:
				least = margin
				least_k = k
			if margin < worst.margin:
				worst = {margin = margin, size = size, k = k, box = box}
		_check(least >= MARGIN, "%d×%d: the title's left edge at least %.0f px right of the column (%.0f px) at all %d points; least %.0f px (point %d)" % [
			size.x, size.y, MARGIN, column, POINTS, least, least_k])
		_check(cast_out <= 0.0 and absf(float(get_root().size.x) - size.x) < 1.0, "%d×%d: the waving golfer and the flag fully in frame on the right (%.0f px to spare at worst)" % [size.x, size.y, -cast_out])
		lobby.free()
		await process_frame

	# The worst point, rendered, its box drawn
	DisplayServer.window_set_size(worst.size)
	for i in 5:
		await process_frame
	var lobby: Control = load("res://lobby.tscn").instantiate()
	root.add_child(lobby)
	var scene: Node3D = lobby.find_children("*", "MenuScene", true, false)[0]
	scene.set_process(false)
	var period: float = TAU / scene.PARAMS.orbit_speed
	scene._t = 100.0 * period + period * worst.k / POINTS
	scene._process(0.0)
	var outline := ReferenceRect.new()
	outline.editor_only = false
	outline.border_color = Color(1, 0.2, 0.2)
	outline.border_width = 2.0
	outline.position = _title_box(scene).position
	outline.size = _title_box(scene).size
	lobby.add_child(outline)
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var out := ProjectSettings.globalize_path("res://").path_join("../docs/art/menu-drift-check.png").simplify_path()
	root.get_texture().get_image().save_png(out)
	print("  worst: %d×%d point %d, %.0f px clear → %s" % [worst.size.x, worst.size.y, worst.k, worst.margin, out])
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


## The title's screen box (canvas units): every corner of every mesh's bounds under every letter.
func _title_box(scene: Node3D) -> Rect2:
	return _box_of(scene, scene._letters)


## The screen box (canvas units) of every mesh under these nodes (nested arrays flattened).
func _box_of(scene: Node3D, nodes: Array) -> Rect2:
	var cam := scene.get_viewport().get_camera_3d()
	var box := Rect2()
	var first := true
	var flat := []
	for n in nodes:
		flat.append_array(n if n is Array else [n])
	for letter: Node3D in flat:
		for view in letter.find_children("*", "MeshInstance3D", true, false):
			var aabb: AABB = (view as MeshInstance3D).get_aabb()
			for c in 8:
				var p := cam.unproject_position((view as MeshInstance3D).global_transform * aabb.get_endpoint(c))
				if first:
					box = Rect2(p, Vector2.ZERO)
					first = false
				else:
					box = box.expand(p)
	return box
