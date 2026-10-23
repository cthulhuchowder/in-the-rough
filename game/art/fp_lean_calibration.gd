extends SceneTree
## Address pose match: per club, fits fp_shaft_lean (about the aim line) and fp_shaft_forward_lean
## (about the axis toward the golfer) so that at address the shaft projects as in the target framing — the
## grip TARGET from the head on screen (the target driver: grip (0.50, 0.68), head (0.53, 0.52)) —
## and writes both into data/clubs/*.tres. Newton on the 2D screen error. Re-run after changing the
## view or a club's shaft; then re-run fp_contact_calibration.gd.
## Run: godot --path game --resolution 1920x1080 -s res://art/fp_lean_calibration.gd

const TARGET := Vector2(-0.03, 0.16) ## grip minus head, normalized screen

var _main: Node


func _initialize() -> void:
	_main = load("res://main.tscn").instantiate()
	_main.random_course = false
	root.add_child(_main)
	for i in 5:
		await process_frame
	for i in _main.CLUBS.size():
		var club: ClubData = _main.CLUBS[i]
		var p := Vector2.ZERO # (lean, forward lean)
		for step in 15:
			var r := await _residual(club, i, p)
			if r.length() < 0.001:
				break
			var dl := (await _residual(club, i, p + Vector2(0.01, 0.0)) - r) / 0.01
			var df := (await _residual(club, i, p + Vector2(0.0, 0.01)) - r) / 0.01
			var det := dl.x * df.y - df.x * dl.y
			if absf(det) < 1e-9:
				break
			var stepv := Vector2(df.y * r.x - df.x * r.y, -dl.y * r.x + dl.x * r.y) / det
			p -= stepv.limit_length(0.3)
		club.fp_shaft_lean = snappedf(p.x, 0.001)
		club.fp_shaft_forward_lean = snappedf(p.y, 0.001)
		var got := await _vector(club, i)
		print("%-3s fp_shaft_lean %+.3f  fp_shaft_forward_lean %+.3f: head→grip (%+.3f, %+.3f)" % [club.label, club.fp_shaft_lean,
			club.fp_shaft_forward_lean, got.x, got.y])
		_write(club)
	quit()


func _residual(club: ClubData, i: int, p: Vector2) -> Vector2:
	club.fp_shaft_lean = p.x
	club.fp_shaft_forward_lean = p.y
	return (await _vector(club, i)) - TARGET


## Grip end minus face centre on screen (normalized) at a fresh address.
func _vector(club: ClubData, i: int) -> Vector2:
	_main.select_club(i)
	_main._readdress()
	_main._fp_offset_key = [] # the leans changed: work the address offset out again
	await process_frame
	_main._lock_club()
	var rig: GolferRig = _main._rig
	var cam: Camera3D = _main._camera
	var size := root.get_visible_rect().size
	var grip := rig._club_model.to_global(Vector3(0, club.grip_length * rig.girth_scale() * 0.4, 0))
	return cam.unproject_position(grip) / size - cam.unproject_position(_main._fp_face()) / size


func _write(club: ClubData) -> void:
	var path := ProjectSettings.globalize_path(club.resource_path)
	var lines := FileAccess.get_file_as_string(path).split("\n")
	for k in lines.size():
		if lines[k].begins_with("fp_shaft_lean = "):
			lines[k] = "fp_shaft_lean = %s" % str(club.fp_shaft_lean)
		elif lines[k].begins_with("fp_shaft_forward_lean = "):
			lines[k] = "fp_shaft_forward_lean = %s" % str(club.fp_shaft_forward_lean)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
