extends SceneTree
## First-person contact by visible gap, every club (wedges' hitbox_late_offset included). The club rides
## one continuous swing arc, its face on the hitbox at address, drawn back by the club's own
## fp_contact_offset eased in toward the hit (Main.contact_ramp). The gap is the closest distance from the drawn clubhead (every
## triangle: ClubModel.head_gap; on a lofted head the leading edge) to the ball's surface:
## at address > 0, through a backswing > 0, every tick of a slow push before the hit > 0, and on the
## tick the hit fires 0 within 5 mm (docs/art/contact-<club>.png show it from the side and face on).
## At address the face also looks along the hitbox's forward (< 0.5°).
## Run: godot --headless --fixed-fps 120 --path game -s res://tests/contact_alignment_test.gd

const NORMAL_TOLERANCE_DEG := 0.5
const PUSH_TOLERANCE := 0.005 ## m, the head to the ball's surface on the hit tick of the slow push, each club

var _main: Node
var _swing: Swing
var _failed := false


func _initialize() -> void:
	_main = load("res://main.tscn").instantiate()
	_main.random_course = false
	root.add_child(_main)
	_swing = _main.get_node("Swing")
	var feeder: MouseSwingFeeder = _main.get_node("MouseSwingFeeder")
	await physics_frame
	_main.load_hole(load("res://holes/test_hole.tscn").instantiate())
	print("  club   visible gap (drawn head to the ball's surface): at address, least in the backswing, least before the hit, on the hit tick   face normal at address")
	for i in _main.CLUBS.size():
		_main.restart()
		_main.select_club(i)
		for k in 10:
			await physics_frame
		var ball := _swing.address_point()
		var address := _gap(ball)
		var normal := _normal_error()
		var backswing := INF
		for k in 60:
			feeder.add_motion(Vector2(4, 0))
			await physics_frame
			backswing = minf(backswing, _gap(ball))
		_main.restart()
		_main.select_club(i)
		for k in 10:
			await physics_frame
		var before := INF
		var ticks := 0
		while ticks < 1200:
			feeder.add_motion(Vector2(-1, 0)) # (the calibration's push: art/fp_contact_calibration.gd)
			await physics_frame
			ticks += 1
			if _swing.has_hit:
				break
			before = minf(before, _gap(ball))
		var hit := _gap(ball)
		var ok: bool = _swing.has_hit and address > 0.0 and backswing > 0.0 and before > 0.0 and absf(hit) < PUSH_TOLERANCE and normal < NORMAL_TOLERANCE_DEG
		_failed = _failed or not ok
		print("  %s  %-3s  %7.1f mm   %7.1f mm   %6.2f mm   %+5.2f mm (tick %d)   %.2f°" % ["ok  " if ok else "FAIL",
			_swing.club.label, address * 1000.0, backswing * 1000.0, before * 1000.0, hit * 1000.0, ticks, normal])
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _gap(ball: Vector3) -> float:
	return ClubModel.head_gap(_main._rig._club_model.get_node("Head"), ball)


## Degrees between the drawn face's normal and the hitbox's forward, now.
func _normal_error() -> float:
	var box := _swing.hitbox_box(_swing.hitbox_position())
	var head: Node3D = _main._rig._club_model.get_node("Head")
	return rad_to_deg((-head.global_basis.z.normalized()).angle_to(-box.basis.x.normalized()))
