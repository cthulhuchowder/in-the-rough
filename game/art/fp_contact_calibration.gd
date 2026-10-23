extends SceneTree
## Visual contact by visible gap, every club on its own (D, 3I–9I, PW, SW, P). The first-person club
## rides the swing arc, its face on the hitbox's leading face at address, drawn back along the aim by the
## club's fp_contact_offset eased in with the angle (Main.contact_ramp). A slow push with no offset: on the tick the
## hit fires, how far back the head must be drawn for the gap between the drawn clubhead (every
## triangle of it: ClubModel.head_gap) and the ball's surface to close to 0 is that club's offset —
## on a lofted head the leading edge touches first. A second push with it checks: the gap at address
## (> 0), the least gap through a backswing from address (> 0), and the gap on the hit tick (~ 0).
## Writes fp_contact_offset into data/clubs/*.tres and prints the table.
## Re-run after changing a club's head, pose, the view or the arc.
## Run: godot --headless --fixed-fps 120 --path game -s res://art/fp_contact_calibration.gd

const PUSH := 1.0 ## px of mouse per tick: slow, under a millimetre of head a tick near the ball (contact_alignment_test pushes the same)
const BACK_TICKS := 60 ## ticks of backswing checked (at 4 px a tick)


func _initialize() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	main.random_course = false
	root.add_child(main)
	for i in 5:
		await physics_frame
	main.load_hole(load("res://holes/test_hole.tscn").instantiate())
	var table := []
	for i in main.CLUBS.size():
		var club: ClubData = main.CLUBS[i]
		club.fp_contact_offset = 0.0
		var r: Dictionary = await probe(main, i)
		club.fp_contact_offset = snappedf(r.close, 0.0001)
		r = await probe(main, i) # with it
		table.append("  %-3s  loft %2.0f°  late %.3f   %6.1f mm    gap at address %6.1f mm   least in the backswing %6.1f mm   on the hit tick %+5.2f mm (tick %d)" % [
			club.label, club.loft_deg, club.hitbox_late_offset, club.fp_contact_offset * 1000.0, r.address * 1000.0, r.backswing * 1000.0, r.hit * 1000.0, r.ticks])
		var path := ProjectSettings.globalize_path(club.resource_path)
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for k in lines.size():
			if lines[k].begins_with("fp_contact_offset = "):
				lines[k] = "fp_contact_offset = %s" % str(club.fp_contact_offset)
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string("\n".join(lines))
		f.close()
	print("  club  loft   late    fp_contact_offset   visible gap (drawn head to the ball's surface)")
	for row in table:
		print(row)
	quit()


## Club `i` at address, then a backswing and back to address, then a slow push to the hit:
## {address, backswing (least), hit: the visible gap (m) then; close: how far back along the aim the head
## would have to be drawn on the hit tick for the gap to be 0; ticks}.
static func probe(main: Node, i: int) -> Dictionary:
	var swing: Swing = main.get_node("Swing")
	var feeder: MouseSwingFeeder = main.get_node("MouseSwingFeeder")
	var tree := main.get_tree()
	main.restart()
	main.select_club(i)
	main._fp_offset_key = []
	for k in 10:
		await tree.physics_frame
	var head: Node3D = main._rig._club_model.get_node("Head")
	var ball: Vector3 = swing.address_point()
	var address := ClubModel.head_gap(head, ball)
	var least := INF
	for k in BACK_TICKS: # back
		feeder.add_motion(Vector2(4, 0))
		await tree.physics_frame
		least = minf(least, ClubModel.head_gap(main._rig._club_model.get_node("Head"), ball))
	main.restart()
	main.select_club(i)
	for k in 10:
		await tree.physics_frame
	var ticks := 0
	while not swing.has_hit and ticks < 1200:
		feeder.add_motion(Vector2(-PUSH, 0))
		await tree.physics_frame
		ticks += 1
	head = main._rig._club_model.get_node("Head")
	var hit := ClubModel.head_gap(head, ball)
	if not is_finite(hit): # (no drawn head this tick: say so rather than calibrate on nothing)
		push_error("%s: no visible head on the hit tick" % swing.club.label)
	# Drawing the head back by s is the ball s further on. The head can pass through the ball, so the
	# gap is < 0 only on a band of s: from a point inside it (lo), bisect forward for where it opens
	var lo := 0.0
	while ClubModel.head_gap(head, ball + swing.aim * lo) >= 0.0 and lo > -0.3:
		lo -= 0.005
	var hi := 0.3
	for k in 40:
		var mid := (lo + hi) * 0.5
		if ClubModel.head_gap(head, ball + swing.aim * mid) < 0.0:
			lo = mid
		else:
			hi = mid
	# the offset is eased in with the angle (Main.contact_ramp): this much of it is taken out on this tick
	var ramp: float = main.contact_ramp(swing, swing.angle)
	return {address = address, backswing = least, hit = hit, close = swing.club.fp_contact_offset + (lo + hi) * 0.5 / ramp, ticks = ticks}
