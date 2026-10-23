class_name BallPuppets
extends Node3D
## Server balls on a client. Remote balls render interp_delay behind the newest snapshot with
## Hermite interpolation (position + velocity); the player's own ball, once its prediction
## window ends, shows the newest server state extrapolated by at most extrapolate_max.
## Other players also get a golfer: at address beside their resting ball, playing their streamed
## swing (angle and pitch, interpolated at the same render tick as the balls), snapping to the
## finish pose once the ball flies, gone once they have holed out. A player walking (F) streams
## feet and facing at walk_send_hz; their golfer walks there instead, at their pace.

const KEEP := 8 # snapshots kept per ball
const LAUNCH_SPEED := 1.0 ## m/s: a ball at rest that goes faster than this was just hit
const REST_SPEED := 0.1 ## m/s: below this a ball counts as at rest
const FEEDBACK: FeedbackParams = preload("res://data/feedback.tres")
const NOVELTY: NoveltyParams = preload("res://data/novelty.tres")

var own_visible := false
var own_look: CharacterLook ## the player's own look (from main): their ball here wears it, whatever the server's roster says
var hole: Hole ## set per hole by main; golfers stand on its ground and aim at its cup
var character: CharacterParams
var look: CharacterLook
var address_angle := 0.0 ## from swing_feel
var stance := 1.3 ## m, ball to feet (driver)
var walk_speed := 4.0 ## m/s, from swing_feel: a remote golfer's walk cycle runs at their pace / this
## Tests: log received swing samples and the angles drawn, per sender name.
var record := false
var swing_log := {}
var walk_log := {} ## per sender name: render frames drawn walking

var _samples := {} ## peer id → Array of [tick, position, velocity], oldest first
var _views := {} ## peer id → Node3D
var _rendered := {} ## peer id → last drawn position
var _newest_tick := -1
var _newest_at := 0.0 ## s, when _newest_tick arrived
var _ball_mesh: Mesh
var _rigs := {} ## peer id → GolferRig
var _rests := {} ## peer id → where the server last put their ball at rest
var _swings := {} ## peer id → Array of [tick, angle, pitch, seq] for the current shot, oldest first
var _render_tick := 0.0
var _clubs := {} ## peer id → club index in hand, from their swing stream (driver until known)
var _walks := {} ## peer id → Array of [tick, position, yaw, seq] while walking, oldest first
var _still := {} ## peer id → their ball was at rest last frame
var hit_sounds := {} ## ClubData.Model → stream (from main), for other players' hits
var novelty_sounds := {} ## club_style → stream (from main): Fresh Catch's slap, Squeaky Set's squeak
var _looks := {} ## peer id → what they wear (their shop items over the standard look)
var _powers := {} ## peer id → their swing's power as it looks from here (their hat's propeller)
var _angles := {} ## peer id → their swing angle drawn last frame


func _ready() -> void:
	_ball_mesh = Ball.view_mesh()


func on_snapshot(tick: int, data: PackedInt32Array) -> void:
	if tick <= _newest_tick:
		return # unreliable channel: older or duplicate, newest wins
	_newest_tick = tick
	_newest_at = Time.get_ticks_usec() / 1000000.0
	for k in data.size() / 7:
		var id := data[7 * k]
		var pos := Vector3(data[7 * k + 1], data[7 * k + 2], data[7 * k + 3]) / 1000.0
		var vel := Vector3(data[7 * k + 4], data[7 * k + 5], data[7 * k + 6]) / 1000.0
		var list: Array = _samples.get_or_add(id, [])
		list.append([tick, pos, vel])
		if list.size() > KEEP:
			list.pop_front()


## Newest server state of the own ball, run forward briefly by its velocity.
func own_position() -> Vector3:
	var list: Array = _samples.get(Net.my_id, [])
	if list.is_empty():
		return Vector3.ZERO
	var last: Array = list[-1]
	var ahead := minf(_now() - _newest_at, Net.PARAMS.extrapolate_max)
	return last[1] + last[2] * ahead


func _process(delta: float) -> void:
	var rate := float(Engine.physics_ticks_per_second)
	var render_tick := _newest_tick + (_now() - _newest_at - Net.PARAMS.interp_delay) * rate
	_render_tick = render_tick
	for id in _samples.keys():
		if not Net.players.has(id):
			_samples.erase(id)
			_rendered.erase(id)
			if _views.has(id):
				_views[id].queue_free()
				_views.erase(id)
			if _rigs.has(id):
				_rigs[id].queue_free()
				_rigs.erase(id)
			_looks.erase(id)
			continue
		var view := _view(id)
		if id == Net.my_id:
			view.visible = own_visible
			view.position = own_position()
		else:
			view.position = _at(_samples[id], render_tick, rate)
			_pose_golfer(id, delta)
		var skin := Ball.view_mesh_for(look_of(id)) # kept on through every snapshot, rest, drop and re-tee
		if (view.get_child(0) as MeshInstance3D).mesh != skin:
			(view.get_child(0) as MeshInstance3D).mesh = skin
		Ball.spin(view.get_child(0), velocity_of(id), delta)
		Ball.animate(view.get_child(0), look_of(id), velocity_of(id), delta)
		(view.get_child(2) as BallTrail).hole = hole
		_rendered[id] = view.position
		_watch_launch(id, view)


## A ball that was at rest and now flies: its trail starts (every club but the putter) and, for
## another player, their hit sounds here at remote_hit_volume_db, by the shot's power.
func _watch_launch(id: int, view: Node3D) -> void:
	var trail: BallTrail = view.get_child(2)
	var speed := velocity_of(id).length()
	var club: ClubData = Clubs.ALL[_clubs.get(id, 0)]
	if speed > LAUNCH_SPEED and _still.get(id, true):
		var power := clampf(speed / (club.strength * club.power_mul * club.smash), 0.0, 1.0)
		if club.model != ClubData.Model.PUTTER:
			trail.start(view.position, power)
		else:
			trail.clear()
		var style := look_of(id).club_style
		if id != Net.my_id and _rigs.has(id):
			_rigs[id].club_impact(power) # (a novelty head flops)
		if id != Net.my_id and (hit_sounds.has(club.model) or novelty_sounds.has(style)):
			var sound: AudioStreamPlayer3D = view.get_child(3)
			sound.stream = novelty_sounds.get(style, hit_sounds.get(club.model))
			sound.volume_db = lerpf(FEEDBACK.remote_hit_volume_db.x, FEEDBACK.remote_hit_volume_db.y, power)
			sound.pitch_scale = lerpf(FEEDBACK.remote_hit_pitch.x, FEEDBACK.remote_hit_pitch.y, power)
			if style == 1: # their own power curves, a little quieter from afar
				sound.pitch_scale = lerpf(NOVELTY.slap_pitch.x, NOVELTY.slap_pitch.y, power)
			elif style == 2:
				sound.pitch_scale = lerpf(NOVELTY.squeak_pitch.x, NOVELTY.squeak_pitch.y, power)
			sound.play()
	_still[id] = speed < REST_SPEED
	if speed > REST_SPEED:
		trail.feed(view.position)
	else:
		trail.stop()


func _at(list: Array, tick: float, rate: float) -> Vector3:
	var first: Array = list[0]
	if tick <= first[0]:
		return first[1]
	for k in range(list.size() - 1):
		var a: Array = list[k]
		var b: Array = list[k + 1]
		if tick <= b[0]:
			var span: float = (b[0] - a[0]) / rate
			var s: float = (tick - a[0]) / float(b[0] - a[0])
			var s2: float = s * s
			var s3: float = s2 * s
			return a[1] * (2 * s3 - 3 * s2 + 1) + a[2] * span * (s3 - 2 * s2 + s) \
				+ b[1] * (-2 * s3 + 3 * s2) + b[2] * span * (s3 - s2)
	var last: Array = list[-1]
	return last[1] + last[2] * minf((tick - last[0]) / rate, Net.PARAMS.extrapolate_max)


func _view(id: int) -> Node3D:
	if _views.has(id):
		var label: Label3D = _views[id].get_child(1)
		label.text = Net.players[id].name
		return _views[id]
	var view := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = Ball.view_mesh_for(look_of(id)) # their shop ball (the standard one unless they wear one)
	view.add_child(mesh)
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.no_depth_test = true
	label.pixel_size = 0.0015
	label.position.y = 0.3
	label.text = Net.players[id].name
	label.visible = id != Net.my_id # never your own tag (single player, or your own ball in a room)
	view.add_child(label)
	var trail := BallTrail.new()
	trail.style = look_of(id).trail_style # their shop trail
	view.add_child(trail)
	var sound := AudioStreamPlayer3D.new()
	sound.bus = Settings.CLUBS_BUS
	view.add_child(sound)
	add_child(view)
	view.add_to_group("balls")
	_views[id] = view
	return view


func _now() -> float:
	return Time.get_ticks_usec() / 1000000.0


## Where a player's ball is currently drawn (for the spectator camera).
func position_of(id: int) -> Vector3:
	return _rendered.get(id, Vector3.ZERO)


func has_ball(id: int) -> bool:
	return _rendered.has(id)


## The server put a player's ball at rest here (start of hole, after a shot, after a drop).
func at_rest(id: int, position: Vector3) -> void:
	_rests[id] = position
	_swings.erase(id) # a new address: the last shot's swing must not replay


## Another player's swing sample, on the server tick clock. Unreliable: newest (by seq) wins.
func on_swing(id: int, seq: int, tick: int, angle: float, pitch: float, club: int) -> void:
	var list: Array = _swings.get_or_add(id, [])
	if not list.is_empty() and seq <= list[-1][3]:
		return # ordered by the sender's sequence: several may share a server tick
	list.append([tick, angle, pitch, seq])
	_clubs[id] = club
	if list.size() > KEEP:
		list.pop_front()
	if record and Net.players.has(id):
		_log(id).received.append([seq, tick, angle])


## Another player walking, on the server tick clock. Unreliable: newest (by seq) wins.
func on_walk(id: int, seq: int, tick: int, position: Vector3, yaw: float) -> void:
	var list: Array = _walks.get_or_add(id, [])
	if not list.is_empty() and seq <= list[-1][3]:
		return
	list.append([tick, position, yaw, seq])
	if list.size() > KEEP:
		list.pop_front()


## A remote golfer walking: still walking while their newest sample is within walk_timeout of the
## render tick. Position and facing interpolated at the render tick; the walk cycle at their pace.
func _pose_walking(id: int, rig: GolferRig, delta: float) -> bool:
	var list: Array = _walks.get(id, [])
	var rate := float(Engine.physics_ticks_per_second)
	if list.is_empty() or _render_tick - list[-1][0] > Net.PARAMS.walk_timeout * rate:
		return false
	var a: Array = list[0]
	var b: Array = list[0]
	for k in range(list.size() - 1):
		a = list[k]
		b = list[k + 1]
		if _render_tick <= b[0]:
			break
	var t := clampf((_render_tick - a[0]) / float(b[0] - a[0]), 0.0, 1.0) if b[0] > a[0] else 1.0
	var at: Vector3 = (a[1] as Vector3).lerp(b[1], t)
	var speed := 0.0
	if b[0] > a[0]:
		speed = Vector2(b[1].x - a[1].x, b[1].z - a[1].z).length() / ((b[0] - a[0]) / rate)
	rig.transform = Transform3D(Basis(Vector3.UP, lerp_angle(a[2], b[2], t)), at)
	rig.pose_walk(speed / walk_speed, delta)
	if record:
		walk_log[Net.players[id].name] = walk_log.get(Net.players[id].name, 0) + 1
	return true


func _pose_golfer(id: int, delta: float) -> void:
	if character == null:
		return
	if not _rigs.has(id):
		var equipped: Dictionary = Net.players.get(id, {}).get("equipped", {})
		var own_look: CharacterLook = ShopCatalog.look_for(equipped) if not equipped.is_empty() else look.duplicate()
		var shirts := character.remote_shirts
		if not shirts.is_empty() and not equipped.has("shirt"): # (the shop's shirt, else one of the remote ones)
			own_look.shirt = shirts[Net.players.keys().find(id) % shirts.size()]
		var rig := GolferRig.new(character, own_look)
		add_child(rig)
		_rigs[id] = rig
	var rig: GolferRig = _rigs[id]
	rig.set_club(Clubs.ALL[_clubs.get(id, 0)])
	if rig.hat_toy:
		rig.hat_toy.power = _powers.get(id, 0.0)
	_powers[id] = maxf(0.0, _powers.get(id, 0.0) - delta * 0.6) # (fading once the swing is over)
	rig.visible = hole != null and _rests.has(id) and Net.players[id].score < 0
	if not rig.visible:
		return
	if _pose_walking(id, rig, delta):
		return
	var rest: Vector3 = _rests[id]
	var aim := (hole.cup.global_position - rest) * Vector3(1, 0, 1)
	if aim.length() < 0.01:
		return
	aim = aim.normalized()
	var feet := rest + (-aim).cross(Vector3.UP) * stance
	feet.y = hole.height_at(feet)
	rig.address(feet, aim, rest)
	var last: Array = _samples[id][-1]
	var flying: bool = (last[2] as Vector3).length() > 0.01
	var swing: Array = _swings.get(id, [])
	if flying:
		rig.pose_swing(character.finish_angle, 0.0)
	elif not swing.is_empty() and _render_tick >= swing[0][0]:
		var pose := _swing_at(swing, _render_tick)
		rig.pose_swing(pose.x, pose.y)
		if delta > 0.0: # their power as it looks from here: how fast the drawn swing turns
			var rate := absf(pose.x - _angles.get(id, pose.x)) / delta
			_powers[id] = maxf(_powers.get(id, 0.0), clampf(rate / NOVELTY.remote_power_rate, 0.0, 1.0))
		_angles[id] = pose.x
		if _render_tick <= swing[-1][0] + Engine.physics_ticks_per_second * 0.5:
			Ball.eye_target = rig._head.global_position # (they are swinging: Eyeballs look at them)
		if record:
			_log(id).displayed.append([_render_tick, pose.x])
	else:
		rig.pose_swing(address_angle, 0.0)


## What a player wears: their shop items over the standard look (cached per player).
func look_of(id: int) -> CharacterLook:
	if id == Net.my_id and own_look:
		return own_look
	if not _looks.has(id):
		var equipped: Dictionary = Net.players.get(id, {}).get("equipped", {})
		_looks[id] = ShopCatalog.look_for(equipped) if not equipped.is_empty() else (look.duplicate() if look else ShopCatalog.DEFAULT_LOOK)
	return _looks[id]


## Another player's hole result (strokes − par): their reactive hat answers.
func react(id: int, result: int) -> void:
	if _rigs.has(id) and _rigs[id].hat_toy:
		_rigs[id].hat_toy.react(result)


## Another player whiffed (the server relays it): their propeller sputters.
func on_whiff(id: int) -> void:
	if _rigs.has(id) and _rigs[id].hat_toy:
		_rigs[id].hat_toy.whiffed()


## Linear between the bracketing samples; holds the newest once the sender stops (shot fired).
static func _swing_at(list: Array, tick: float) -> Vector2:
	for k in range(list.size() - 1):
		var a: Array = list[k]
		var b: Array = list[k + 1]
		if tick <= b[0]:
			var t := clampf((tick - a[0]) / float(b[0] - a[0]), 0.0, 1.0) if b[0] > a[0] else 1.0
			return Vector2(lerpf(a[1], b[1], t), lerpf(a[2], b[2], t))
	var last: Array = list[-1]
	return Vector2(last[1], last[2])


func _log(id: int) -> Dictionary:
	return swing_log.get_or_add(Net.players[id].name, {received = [], displayed = []})


## Newest server velocity of a player's ball (zero once at rest).
func velocity_of(id: int) -> Vector3:
	var list: Array = _samples.get(id, [])
	return list[-1][2] if not list.is_empty() else Vector3.ZERO
