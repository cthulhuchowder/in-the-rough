class_name PracticeRange
extends Node
## Practice (from the main menu; offline, no scoring): a flat parkland range — a tee mat, a fairway
## strip with distance boards every 25 m, unlimited balls (R re-tees, the landing distance pops up
## after each shot) — and beside it a gently rolling putting green with nine cups at varied distances
## and slopes (C picks the next cup; after each putt the ball goes back to that cup's distance).
## G switches between them; Esc returns to the menu. The hole is a hand-made HoleData built by
## GeneratedHole; the chosen cup is the real one (rebuilt on a change), the others drawn as rims.

static var requested := false ## the menu asks main for practice instead of a course

const N := 200 ## grid px
const M := 2.0 ## m per px
const TEE := Vector2(200.0, 40.0) ## m: the range's tee
const RANGE_HALF := 44.0 ## m: half the fairway strip's width
const GREEN := Vector2(106.0, 30.0) ## m: the putting green's centre — beside and a little behind the tee, off the range
const GREEN_R := 18.0 ## m
## Per cup: [offset from the green's centre (m), putt distance (m) from its ball spot]
const CUPS := [[Vector2(-6, -4), 1.5], [Vector2(4, -8), 2.5], [Vector2(9, 1), 3.5], [Vector2(-10, 5), 4.5],
	[Vector2(2, 9), 6.0], [Vector2(-3, -12), 7.5], [Vector2(12, -7), 9.0], [Vector2(-13, -6), 10.5], [Vector2(6, 12), 12.0]]

var main: Node
var on_green := false
var cup_index := 0
var _popup := Label.new()
var _popup_tween: Tween
var _shot_from := Vector3.ZERO


func start(game: Node) -> void:
	main = game
	_popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_popup.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_popup.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_popup.position.y = 120.0
	_popup.add_theme_font_size_override("font_size", 30)
	_popup.add_theme_color_override("font_color", main.FEEDBACK.meter_peak)
	_popup.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_popup.add_theme_constant_override("outline_size", 6)
	_popup.modulate.a = 0.0
	main.get_node("Overlay").add_child(_popup)
	main._round.at_rest.connect(_on_rest)
	main._round.finished.connect(func(_score: int) -> void: _back_to_cup(1.2))
	main._swing.hit.connect(func() -> void: _shot_from = main._ball.global_position)
	_rebuild()


## The HUD line: where you are and what is set.
func status() -> String:
	if on_green:
		return "Practice · Green · Cup %d of %d · %.1f m  (C: next cup, G: range)" % [cup_index + 1, CUPS.size(), CUPS[cup_index][1]]
	return "Practice · Range  (R: new ball, G: putting green)"


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			requested = false
			get_tree().change_scene_to_file("res://lobby.tscn")
		KEY_R:
			get_viewport().set_input_as_handled()
			_place_ball()
		KEY_G:
			get_viewport().set_input_as_handled()
			on_green = not on_green
			_place_ball()
		KEY_C:
			if on_green:
				get_viewport().set_input_as_handled()
				cup_index = (cup_index + 1) % CUPS.size()
				_rebuild()


func _on_rest(at: Vector3) -> void:
	if not on_green: # on the range always face down it, toward the distance boards (main faces the cup)
		main._swing.aim = Vector3.BACK
		main._swing.reset()
	if on_green:
		if main._ball.global_position.distance_to(_ball_spot()) > 0.3:
			_back_to_cup(1.0) # missed: the same putt again
		return
	if _shot_from != Vector3.ZERO and main._ball.carry >= 0.0:
		var total := Vector2(at.x - _shot_from.x, at.z - _shot_from.z).length()
		_pop("Carry %d m  ·  Total %d m" % [roundi(main._ball.carry), roundi(total)])
		_shot_from = Vector3.ZERO


func _back_to_cup(after: float) -> void:
	await get_tree().create_timer(after, false).timeout
	if on_green and is_inside_tree():
		_place_ball()


## A fresh ball: on the tee (range), or at the chosen cup's distance (green). A new round each time: no scoring.
func _place_ball() -> void:
	var hole: Hole = main._hole
	var at: Vector3 = hole.tee.global_position if not on_green else _ball_spot()
	main._first_shot = true
	main._caddied_at = Vector3.INF
	main._round.start(hole, at)


func _ball_spot() -> Vector3:
	var cup: Vector2 = GREEN + CUPS[cup_index][0]
	var away := (cup - GREEN).normalized() if (cup - GREEN).length() > 0.5 else Vector2(1, 0)
	var spot: Vector2 = cup - away * float(CUPS[cup_index][1]) # from the green's middle side, so it stays on the green
	return Vector3(spot.x, main._hole.height_at(Vector3(spot.x, 0, spot.y)), spot.y)


func _pop(text: String) -> void:
	_popup.text = text
	if _popup_tween:
		_popup_tween.kill()
	_popup.modulate.a = 1.0
	_popup_tween = create_tween()
	_popup_tween.tween_interval(3.0)
	_popup_tween.tween_property(_popup, "modulate:a", 0.0, 0.6)


## The practice hole with the chosen cup cut in; then a ball where it belongs.
func _rebuild() -> void:
	var hole := GeneratedHole.new()
	hole.build(data(main.procgen, cup_index), main.procgen)
	main._swap_hole(hole, 0)
	_dress(hole)
	_place_ball()


## The range and green as hole data (hand-made, not procedural): flat ground, a fairway strip, rough
## either side then out of bounds, trees in rows beyond, the green's gentle slopes.
static func data(p: ProcgenParams, cup: int) -> Procgen.HoleData:
	var d := Procgen.HoleData.new()
	d.seed = 0x7072616374
	d.par = 3
	d.size = N
	d.metres_per_px = M
	d.biome = p.biomes[0]
	d.water = -1000000
	d.wind = Vector2.ZERO
	d.tee = Vector2i(roundi(TEE.x / M), roundi(TEE.y / M))
	var c: Vector2 = GREEN + CUPS[cup][0]
	d.cup = Vector2i(roundi(c.x / M), roundi(c.y / M))
	d.route = PackedVector2Array([Vector2(d.tee), Vector2(d.tee) + Vector2(0, 150), Vector2(d.cup)])
	for mask in ["fairway", "green", "rough", "bunker"]:
		var bytes := PackedByteArray()
		bytes.resize(N * N)
		d.set(mask, bytes)
	d.heights.resize(N * N)
	for y in N:
		for x in N:
			var i := y * N + x
			var at := Vector2(x, y) * M
			var to_green := at.distance_to(GREEN)
			var h := 0.0
			if to_green < GREEN_R + 6.0: # rolling: a few gentle swells, eased out at the edge
				var w := 1.0 - smoothstep(GREEN_R - 2.0, GREEN_R + 6.0, to_green)
				h = (0.22 * sin(at.x * 0.31) + 0.18 * cos(at.y * 0.27) + 0.12 * sin((at.x + at.y) * 0.45)) * w
			d.heights[i] = roundi(h * 100.0)
			var in_range := absf(at.x - TEE.x) < RANGE_HALF and at.y > TEE.y - 12.0 and at.y < N * M - 10.0
			d.fairway[i] = 255 if in_range else 0
			d.green[i] = 255 if to_green < GREEN_R else 0
			var wild := absf(at.x - TEE.x) > 160.0 or at.y < 8.0 or at.y > N * M - 6.0
			d.rough[i] = 255 if wild else (0 if in_range or to_green < GREEN_R else 60)
	# Rows of parkland trees beyond the rough on both sides of the range
	var trees := PackedInt32Array()
	var scales := PackedInt32Array()
	var k := 0
	for z in range(int(TEE.y), int(N * M) - 20, 18):
		for side in [-1.0, 1.0]:
			var x: float = TEE.x + side * (RANGE_HALF + 30.0 + float((k * 7) % 11))
			var species := k % d.biome.trees.size()
			trees.append_array([roundi(x * 100.0), roundi(float(z) * 100.0), species, k % d.biome.trees[species].sizes.size()])
			scales.append_array([1000 + (k * 37) % 400, 1000, 1000])
			k += 1
	d.trees = trees
	d.tree_scale = scales
	d.forest_from = trees.size() / 4
	d.undergrowth_from = 0
	return d


## Visual dressing: a tee mat, distance boards every 25 m, rims for the cups not in play.
func _dress(hole: GeneratedHole) -> void:
	var root := Node3D.new()
	var tee := hole.tee.global_position
	var mat := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(3.0, 0.04, 2.0)
	mat.mesh = box
	var mat_mat := StandardMaterial3D.new()
	mat_mat.albedo_color = Color(0.22, 0.4, 0.24)
	box.material = mat_mat
	mat.position = tee + Vector3(0, 0.0, 0)
	root.add_child(mat)
	for metres in range(25, 325, 25):
		var at := tee + Vector3(-RANGE_HALF + 4.0, 0, metres)
		var post := MeshInstance3D.new()
		var pole := CylinderMesh.new()
		pole.top_radius = 0.06
		pole.bottom_radius = 0.06
		pole.height = 1.6
		post.mesh = pole
		post.position = at + Vector3(0, 0.8, 0)
		root.add_child(post)
		var board := Label3D.new()
		board.text = "%d" % metres
		board.font_size = 160
		board.pixel_size = 0.01
		board.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		board.modulate = Color(1.0, 0.95, 0.75)
		board.outline_size = 24
		board.position = at + Vector3(0, 2.2, 0)
		root.add_child(board)
		var flag := Label3D.new() # the same at the strip's centre, low, so it reads from the tee
		flag.text = "%d" % metres
		flag.font_size = 120
		flag.pixel_size = 0.012
		flag.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		flag.modulate = Color(1, 1, 1, 0.85)
		flag.outline_size = 18
		flag.position = tee + Vector3(0, 0.9, metres)
		root.add_child(flag)
	for k in CUPS.size():
		if k == cup_index:
			continue
		var c: Vector2 = GREEN + CUPS[k][0]
		var rim := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.06
		disc.bottom_radius = 0.06
		disc.height = 0.006
		rim.mesh = disc
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.12, 0.13, 0.12)
		disc.material = dark
		rim.position = Vector3(c.x, hole.height_at(Vector3(c.x, 0, c.y)) + 0.004, c.y)
		root.add_child(rim)
	# Signs with the keys: by the tee mat, and at the green
	_sign(root, tee + Vector3(-11.0, 0, -5.0), "Putting green: G   ·   New ball: R") # (left of the mat, out of the line of play)
	_sign(root, Vector3(GREEN.x + GREEN_R * 0.7, hole.height_at(Vector3(GREEN.x, 0, GREEN.y)), GREEN.y - GREEN_R * 0.7),
		"Driving range: G   ·   Next cup: C")
	hole.add_child(root)


## A small board on a post, its text facing whoever looks at it.
static func _sign(root: Node3D, at: Vector3, text: String) -> void:
	var post := MeshInstance3D.new()
	var pole := CylinderMesh.new()
	pole.top_radius = 0.05
	pole.bottom_radius = 0.05
	pole.height = 1.4
	post.mesh = pole
	post.position = at + Vector3(0, 0.7, 0)
	root.add_child(post)
	var board := Label3D.new()
	board.text = text
	board.font_size = 72
	board.pixel_size = 0.0042
	board.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	board.modulate = Color(0.95, 0.93, 0.85)
	board.outline_size = 14
	board.outline_modulate = Color(0.12, 0.16, 0.12)
	board.position = at + Vector3(0, 1.6, 0)
	root.add_child(board)
