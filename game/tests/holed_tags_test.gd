extends SceneTree
## Other players' balls on a client (BallPuppets): a player who holes out keeps their ball and tag
## through the drop, then both go (holed_hide_delay after their score comes in) and a faded
## "✓ Name" stands beside the flag, clear of the cup, stacked in finishing order; a new hole brings
## the ball back. A ball still in play keeps its tag at a distance and fades it out close to the
## camera (gone by tag_fade_near − tag_fade_band), so it never sits over a putt.
## Run: godot --headless --path game -s res://tests/holed_tags_test.gd

const P: FeedbackParams = preload("res://data/feedback.tres")
const FEEL: SwingFeel = preload("res://data/swing_feel.tres")

var _failed := false
var _net: Node
var _puppets: Node3D # (BallPuppets, loaded at run time: it uses the Net autoload)
var _tick := 0
var _at := {}


func _check(ok: bool, what: String) -> void:
	_failed = _failed or not ok
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])


func _initialize() -> void:
	_net = root.get_node("Net")
	_net.my_id = 1
	_net.players = {1: {name = "Me", strokes = 0, score = -1}, 2: {name = "Bo", strokes = 3, score = -1}, 3: {name = "Cy", strokes = 2, score = -1},
		4: {name = "Di", strokes = 3, score = -1}}
	var hole: Node3D = load("res://holes/test_hole.tscn").instantiate()
	root.add_child(hole)
	await process_frame # (the hole finds its cup in _ready)
	var cup: Vector3 = hole.cup.global_position
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.look_at_from_position(cup + Vector3(0, 1.6, 12), cup)
	camera.make_current()
	_puppets = load("res://scripts/ball_puppets.gd").new()
	_puppets.hole = hole
	root.add_child(_puppets)
	_at = {1: cup + Vector3(0, 0, 9), 2: cup + Vector3(0, -0.05, 0), 3: cup + Vector3(2, 0, 6), 4: cup + Vector3(0, -0.05, 0)}
	await _frames(10)
	var bo: Node3D = _puppets._views[2]
	var cy_tag: Label3D = _puppets._views[3].get_child(1)

	# Bo holes out: ball and tag stay through the drop, then go; the marker shows by the flag
	_net.players[2].score = 3
	await _seconds(P.holed_hide_delay * 0.5)
	_check(bo.visible and not _puppets._markers.has(2), "just holed: Bo's ball and tag still show (the drop)")
	await _seconds(P.holed_hide_delay * 0.5 + 0.2)
	var marker: Label3D = _puppets._markers.get(2)
	_check(not bo.visible, "after holed_hide_delay (%.1f s): Bo's ball and tag are hidden" % P.holed_hide_delay)
	var off := Vector2(marker.global_position.x - cup.x, marker.global_position.z - cup.z).length() if marker else 0.0
	_check(marker != null and marker.visible and marker.text == "✓ Bo" and marker.modulate.a < 1.0 and off > FEEL.cup_radius * 2.0
		and marker.global_position.y - cup.y >= 1.0,
		"\"%s\" beside the flag: %.2f m to the side, %.2f m up, alpha %.2f" % [marker.text if marker else "?", off,
		marker.global_position.y - cup.y if marker else 0.0, marker.modulate.a if marker else 1.0])
	_check(marker != null and absf(camera.global_basis.x.normalized().dot((marker.global_position - cup).normalized())) > 0.2,
		"the marker is off to the side on screen, not over the cup")

	# Di holes out next: stacked above Bo
	_net.players[4].score = 4
	await _seconds(P.holed_hide_delay + 0.2)
	var di: Label3D = _puppets._markers.get(4)
	_check(di != null and di.visible and di.global_position.y > marker.global_position.y + 0.1, "Di's marker stacks above Bo's (finishing order)")

	# Cy, still in play: its tag shows at a distance and fades out near the camera
	var cy_at: Vector3 = _puppets._views[3].global_position
	var dir := (camera.global_position - cy_at).normalized()
	var alphas := []
	for d: float in [8.0, P.tag_fade_near + 0.2, P.tag_fade_near - P.tag_fade_band * 0.5, P.tag_fade_near - P.tag_fade_band - 0.2, 0.6]:
		camera.look_at_from_position(cy_at + dir * d + Vector3(0, 0.01, 0), cy_at)
		await _frames(3)
		alphas.append(snappedf(cy_tag.modulate.a, 0.01))
	_check(alphas[0] == 1.0 and alphas[1] == 1.0 and alphas[2] > 0.0 and alphas[2] < 1.0 and alphas[3] == 0.0 and alphas[4] == 0.0,
		"Cy's tag at 8 / %.1f / %.2f / %.1f / 0.6 m: alpha %s (gone within %.1f m)" % [P.tag_fade_near + 0.2,
		P.tag_fade_near - P.tag_fade_band * 0.5, P.tag_fade_near - P.tag_fade_band - 0.2, alphas, P.tag_fade_near - P.tag_fade_band])
	_check(_puppets._views[3].visible and not _puppets._markers.has(3), "Cy's ball stays (not holed)")

	# The next hole: scores back to −1, balls back, markers gone
	for id in [2, 4]:
		_net.players[id].score = -1
	await _frames(3)
	_check(bo.visible and not _puppets._markers[2].visible and not _puppets._markers[4].visible, "a new hole: Bo's ball is back, the markers gone")
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _frames(n: int) -> void:
	for i in n:
		_snap()
		await process_frame


func _seconds(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		_snap()
		await process_frame


## A snapshot of every ball at rest at its spot (the server's 30 Hz stream, one per frame here).
func _snap() -> void:
	_tick += 4
	var data := PackedInt32Array()
	for id: int in _at:
		var p: Vector3 = _at[id] * 1000.0
		data.append_array([id, int(p.x), int(p.y), int(p.z), 0, 0, 0])
	_puppets.on_snapshot(_tick, data)
