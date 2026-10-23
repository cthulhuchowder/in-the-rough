class_name PlayerRound
extends Node
## One player's hole under stroke play: strokes, holed once the ball settles in the cup, water
## and OB drops, pickup cap. Drives one Ball on one Hole. Offline uses one; the server runs one per
## player.

signal at_rest(position: Vector3) ## ball settled or dropped; the next shot is from here
signal finished(score: int)
signal changed ## strokes, score or message

var rules: RulesData
var hole: Hole
var ball: Ball
var strokes := 0
var score := -1 ## final hole score; -1 while playing
var message := ""
var gimme := 0.0 ## m: a ball at rest this close to the cup is given (holed, one more stroke); 0 = off
var mulligans := 0 ## left this round: retake the last shot from where it was played

var _before_shot := {} # {position, strokes} when the last shot was played; empty once used or on a new hole

var picked_up := false ## this hole ended picked up at max_strokes, not holed
var _token := 0 # bumped per hole so a pending water drop from the last one is abandoned
var _water_pending := false


func setup(play_rules: RulesData, play_ball: Ball) -> void:
	rules = play_rules
	ball = play_ball
	ball.stopped.connect(_on_ball_stopped)


func start(on: Hole, tee: Vector3) -> void:
	_token += 1
	picked_up = false
	_water_pending = false
	hole = on
	ball.course = on
	strokes = 0
	score = -1
	message = ""
	_before_shot = {}
	ball.place(on.rest_point(tee, rules.drop_height))
	changed.emit()
	at_rest.emit(ball.global_position)


func can_shoot() -> bool:
	return hole != null and score < 0 and not ball.in_play and not _water_pending


func shot_taken() -> void:
	_before_shot = {position = ball.global_position, strokes = strokes}
	strokes += 1
	message = ""
	changed.emit()


## The shot clock ran out: a stroke with no movement (picked up at max_strokes).
func whiff() -> void:
	if not can_shoot():
		return
	_before_shot = {}
	strokes += 1
	if strokes >= rules.max_strokes:
		_finish(rules.pickup_score, "Picked up")
		return
	message = "Shot clock: whiff"
	changed.emit()
	at_rest.emit(ball.global_position)


## Retake the last shot: back where it was played from, its stroke and any penalty undone.
func mulligan() -> bool:
	if mulligans <= 0 or _before_shot.is_empty() or not can_shoot():
		return false
	mulligans -= 1
	strokes = _before_shot.strokes
	ball.place(_before_shot.position)
	_before_shot = {}
	message = "Mulligan (%d left)" % mulligans
	changed.emit()
	at_rest.emit(ball.global_position)
	return true


func _physics_process(_delta: float) -> void:
	if hole == null or not ball.in_play:
		return
	var pos := ball.global_position
	if pos.y - hole.height_at(pos) > rules.ground_band:
		return
	if ball.lie.hazard == SurfaceData.Hazard.WATER and not ball.in_cup:
		_water_drop()


func _water_drop() -> void:
	ball.halt()
	_water_pending = true
	var named := (hole as GeneratedHole).data.biome.water_name if hole is GeneratedHole else "Water" # lava, a brine pool…
	message = "%s: +%d" % [named.left(1).to_upper() + named.substr(1), rules.penalty_strokes]
	changed.emit()
	var token := _token
	await get_tree().create_timer(rules.water_delay, false, true).timeout
	if token != _token:
		return
	_water_pending = false
	strokes += rules.penalty_strokes
	# Back to the last safe lie (where the shot was played from), at a spot the golfer can stand
	var back: Vector3 = _before_shot.get("position", hole.tee.global_position)
	ball.place(hole.clear_spot(back, rules.drop_clearance, rules.drop_height))
	changed.emit()
	at_rest.emit(ball.global_position)


func _on_ball_stopped() -> void:
	if score >= 0:
		return
	if ball.in_cup:
		_finish(strokes, "Holed")
		return
	var cup := hole.cup.global_position - ball.global_position
	if gimme > 0.0 and Vector2(cup.x, cup.z).length() <= gimme:
		_finish(strokes + 1, "Gimme")
		return
	if strokes >= rules.max_strokes:
		_finish(rules.pickup_score, "Picked up")
		return
	if ball.lie.hazard == SurfaceData.Hazard.OUT_OF_BOUNDS:
		strokes += rules.penalty_strokes
		message = "Out of bounds: +%d" % rules.penalty_strokes
		ball.place(hole.clear_spot(hole.drop_point(ball.global_position, rules), rules.drop_clearance, rules.drop_height))
		changed.emit()
	at_rest.emit(ball.global_position)


func _finish(final_score: int, how: String) -> void:
	score = final_score
	picked_up = how == "Picked up" # (no base coins for it)
	var to_par := score - hole.par
	message = "%s: %d (%s)" % [how, score, "E" if to_par == 0 else "%+d" % to_par]
	changed.emit()
	finished.emit(score)
