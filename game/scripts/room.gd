class_name Room
extends SubViewport
## One room on the dedicated server: its own physics world (so rooms never touch each other),
## course seed and up to max_players. Lobby → round → summary → play again. Everyone plays each
## hole at once; it ends when every player still in the room has finished. Joining and leaving
## work in every state.

enum State { LOBBY, PLAYING, ROUND_OVER }

const BALL := preload("res://ball.tscn")

var code := ""
var host_id := 0
var state := State.LOBBY
var course_seed := 0
var hole_number := 0
var rules := RoomRules.defaults() ## the host's custom rules (RoomRules), enforced here

var _rules: RulesData = preload("res://data/rules.tres")
var _procgen: ProcgenParams = preload("res://data/procgen.tres")
var _course: Array[Dictionary] = []
var _hole: GeneratedHole
var _players := {} ## peer id → {name, ready, slot, ball, round, clock (shot clock token)}
var _pars: Array[int] = []
var _scores := {} ## peer id → Array[int] per hole of this round, -1 = not played
var _advancing := false
var _tick := 0
var _tee_count := 1 # players lined up across the tee at this hole's start
var _coins := {} ## peer id → this round's coins by category (Economy)
var _hole_log := {} ## peer id → per hole {score, picked_up, drive, drive_ok, closest, award}: what the coins came from


func _init() -> void:
	own_world_3d = true
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	size = Vector2i(2, 2)


func is_empty() -> bool:
	return _players.is_empty()


func has_player(id: int) -> bool:
	return _players.has(id)


func add_player(id: int, player_name: String) -> bool:
	if _players.size() >= Net.PARAMS.max_players:
		Net.room_error.rpc_id(id, "Room %s is full" % code)
		return false
	var profile: String = get_parent().profile_key(id, player_name) # coins go to the player's key, whatever the name
	get_parent().store.get_profile(profile).name = ProfileStore.clean_name(player_name)
	player_name = _unique_name(player_name)
	_players[id] = {name = player_name, profile = profile, ready = false, slot = _free_slot(), ball = null, round = null, clock = 0, clock_live = false}
	var missed: Array[int] = []
	missed.resize(_pars.size())
	missed.fill(-1)
	_scores[id] = missed
	if host_id == 0:
		host_id = id
	_send_lobby()
	Net.coins.rpc_id(id, {}, int(get_parent().store.get_profile(profile).balance)) # their balance so far
	match state:
		State.PLAYING:
			_spawn(id)
			_apply_rules(id)
			_players[id].round.start(_hole, _tee_slot(_players[id].slot))
			Net.round_started.rpc_id(id, course_seed, hole_number, _rests(), _roster(), card())
			_each(func(m): Net.scorecard.rpc_id(m, card()))
			_await_flyover(id)
		State.ROUND_OVER:
			Net.round_over.rpc_id(id, card())
	print("room %s: %s joined (%d players)" % [code, player_name, _players.size()])
	return true


func remove_player(id: int) -> void:
	if not _players.has(id):
		return
	var p: Dictionary = _players[id]
	if p.ball:
		p.ball.queue_free()
		p.round.queue_free()
	_players.erase(id)
	_scores.erase(id)
	if host_id == id:
		host_id = _players.keys()[0] if not _players.is_empty() else 0
	print("room %s: %s left (%d players)" % [code, p.name, _players.size()])
	_each(func(m): Net.player_left.rpc_id(m, id))
	_send_lobby()
	if state == State.PLAYING:
		_each(func(m): Net.scorecard.rpc_id(m, card()))
		_maybe_advance()


func set_ready(id: int, ready: bool) -> void:
	if state == State.LOBBY and _players.has(id):
		_players[id].ready = ready
		_send_lobby()


## Host only, once everyone is ready.
func start(id: int, seed: int) -> void:
	if id != host_id or state != State.LOBBY:
		return
	for pid in _players:
		if not _players[pid].ready:
			return
	_start_round(seed)


## Host only, from the end-of-round summary: same room, fresh seed.
func play_again(id: int, seed: int) -> void:
	if id == host_id and state == State.ROUND_OVER:
		_start_round(seed)


## Host only, between rounds. Untrusted: RoomRules.clean keeps only valid values.
func set_rules(id: int, wanted: Variant) -> void:
	if id == host_id and state != State.PLAYING:
		rules = RoomRules.clean(wanted, rules)
		_send_lobby()


## A member's chat line to everyone in the room (themselves too), as "name: text". From a client,
## so it is cleaned here: one line, control characters dropped, at most chat_max_length, and at
## most one line per chat_min_interval per player (faster ones are dropped).
func chat(id: int, text: String) -> void:
	var p: Dictionary = _players.get(id, {})
	if p.is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - int(p.get("chat_at", -100000)) < Net.PARAMS.chat_min_interval * 1000.0:
		return
	var clean := ""
	for c in text.left(Net.PARAMS.chat_max_length * 4):
		if c.unicode_at(0) >= 32 and c.unicode_at(0) != 127:
			clean += c
	clean = clean.strip_edges().left(Net.PARAMS.chat_max_length)
	if clean == "":
		return
	p.chat_at = now
	_each(func(m): Net.chat.rpc_id(m, p.name, clean))


## Retake the last shot, if the rules leave this player a mulligan and the ball is at rest.
func mulligan(id: int) -> void:
	var p: Dictionary = _players.get(id, {})
	if state == State.PLAYING and not p.is_empty() and p.round:
		p.round.mulligan()


## Untrusted input: clamp everything and ignore shots the rules don't allow right now.
func shot(id: int, dir: Vector3, path_angle: float, power: float, club: int, spin: float) -> void:
	var p: Dictionary = _players.get(id, {})
	if state != State.PLAYING or p.is_empty() or p.round == null or not p.round.can_shoot():
		return
	dir.y = 0.0
	if not dir.is_finite() or dir.length() < 0.01:
		return
	dir = dir.normalized()
	var ball: Ball = p.ball
	ball.launch(dir, clampf(path_angle, -PI, PI), clampf(power, 0.0, 1.0),
		Clubs.ALL[clampi(club, 0, Clubs.ALL.size() - 1)], (-dir).cross(Vector3.UP))
	if spin >= 0.0:
		ball.set_backspin(clampf(spin, 0.0, 1.0))
	else:
		ball.spin_pending = true
	p.round.shot_taken()


## Untrusted swing pose: only while that player could shoot; relayed to everyone else with the
## room tick so their golfer plays it on the same clock as the balls.
func swing(id: int, seq: int, angle: float, pitch: float, club: int) -> void:
	var p: Dictionary = _players.get(id, {})
	if state != State.PLAYING or p.is_empty() or p.round == null or not p.round.can_shoot():
		return
	if not (is_finite(angle) and is_finite(pitch)):
		return
	angle = clampf(angle, -PI, PI)
	pitch = clampf(pitch, -1.0, 1.0)
	club = clampi(club, 0, Clubs.ALL.size() - 1)
	for m in _players:
		if m != id:
			Net.remote_swing.rpc_id(m, id, seq, _tick, angle, pitch, club)


## A member's whiff, to everyone else (cosmetic: their hat sputters there). Only during play.
func whiff(id: int) -> void:
	if state == State.PLAYING and _players.has(id):
		for m in _players:
			if m != id:
				Net.remote_whiff.rpc_id(m, id)


## Untrusted walk pose: only during play, finite, and within walk_max_range of the player's own
## ball; relayed to everyone else with the room tick.
func walk(id: int, seq: int, position: Vector3, yaw: float) -> void:
	var p: Dictionary = _players.get(id, {})
	if state != State.PLAYING or p.is_empty() or p.ball == null:
		return
	if not (position.is_finite() and is_finite(yaw)):
		return
	if position.distance_to(p.ball.global_position) > Net.PARAMS.walk_max_range:
		return
	yaw = wrapf(yaw, -PI, PI)
	for m in _players:
		if m != id:
			Net.remote_walk.rpc_id(m, id, seq, _tick, position, yaw)


func spin(id: int, value: float) -> void:
	var p: Dictionary = _players.get(id, {})
	if not p.is_empty() and p.ball and p.ball.spin_pending:
		p.ball.set_backspin(clampf(value, 0.0, 1.0))


## {pars: [..], rows: [{id, name, scores: [..]}]} in join order; -1 = hole not played.
## What the coins came from, per player and hole (the server's --report).
func report() -> Dictionary:
	var out := card()
	var log := {}
	for id in _hole_log:
		log[_players[id].name if _players.has(id) else str(id)] = _hole_log[id]
	out.holes = log
	out.share = get_parent().coin_share
	return out


## A player's ball came to rest: their first shot of the hole is their drive (its length, and whether
## it stayed out of hazards); on a par 3 the tee shot's distance to the cup if it is on the green.
func _note_shot(id: int, pos: Vector3) -> void:
	var p: Dictionary = _players.get(id, {})
	if p.is_empty() or p.round == null or p.round.strokes != 1 or p.get("drive_hole", 0) == hole_number:
		return
	p.drive_hole = hole_number
	var tee := _tee_slot(p.slot)
	var lie := _hole.surface_at(pos)
	p.drive = Vector2(pos.x - tee.x, pos.z - tee.z).length()
	p.drive_ok = lie.hazard == SurfaceData.Hazard.NONE
	var cup := _hole.cup.global_position
	p.closest = Vector2(pos.x - cup.x, pos.z - cup.z).length() if lie == _procgen.green else -1.0


## Everyone has finished the hole: each player's coins (Economy), into their profile, sent to them.
func _award_hole() -> void:
	var par := _hole.par
	var longest_id := 0
	var longest := -1.0
	var closest_id := 0
	var closest := INF
	for id in _players:
		var p: Dictionary = _players[id]
		var here: bool = p.get("drive_hole", 0) == hole_number
		if here and par >= 4 and p.drive_ok and p.drive > longest:
			longest = p.drive
			longest_id = id
		if here and par == 3 and p.closest >= 0.0 and p.closest < closest:
			closest = p.closest
			closest_id = id
	var server: Node = get_parent()
	for id in _players:
		var p: Dictionary = _players[id]
		var r: PlayerRound = p.round
		var here: bool = p.get("drive_hole", 0) == hole_number
		var a := Economy.award(par, r.score, r.picked_up, id == longest_id, id == closest_id, server.coin_share)
		_coins[id] = Economy.add(_coins.get(id, {}), a)
		if not _hole_log.has(id):
			_hole_log[id] = []
		_hole_log[id].append({par = par, score = r.score, picked_up = r.picked_up, drive = p.drive if here else -1.0,
			drive_ok = here and p.drive_ok, closest = p.closest if here else -1.0, award = a})
		var prof: Dictionary = server.store.get_profile(p.profile)
		prof.balance = int(prof.balance) + int(a.total)
		if server.local: # earned offline: owed to the real server at the next connect
			prof.pending = int(prof.get("pending", 0)) + int(a.total)
		prof.stats.holes = int(prof.stats.holes) + 1
		prof.stats.coins_earned = int(prof.stats.coins_earned) + int(a.total)
		prof.stats.holes_in_one = int(prof.stats.holes_in_one) + (1 if r.score == 1 else 0)
		if here:
			prof.stats.best_drive = maxf(float(prof.stats.best_drive), p.drive)
		Net.coins.rpc_id(id, a, int(prof.balance))
	server.store.save()


func card() -> Dictionary:
	var rows := []
	for id in _players:
		rows.append({id = id, name = _players[id].name, scores = _scores[id].duplicate(), coins = _coins.get(id, {}).duplicate()})
	return {pars = _pars.duplicate(), rows = rows, rules = rules.duplicate()}


func _start_round(seed: int) -> void:
	course_seed = seed
	_course = Procgen.course(seed, _procgen, int(rules.get("biome", 0))) # (the room's biome pick; clients build the same)
	_pars.clear()
	for id in _players:
		_scores[id] = [] as Array[int]
		_coins[id] = {}
		_hole_log[id] = []
		_spawn(id)
		_apply_rules(id)
	state = State.PLAYING
	_send_lobby()
	_load_hole(1)
	print("room %s: round on course 0x%s" % [code, String.num_uint64(seed, 16)])


func _spawn(id: int) -> void:
	var p: Dictionary = _players[id]
	if p.ball:
		return
	p.ball = BALL.instantiate()
	add_child(p.ball)
	p.round = PlayerRound.new()
	add_child(p.round)
	p.round.setup(_rules, p.ball)
	p.round.changed.connect(_broadcast_player.bind(id))
	p.round.at_rest.connect(func(pos: Vector3):
		_note_shot(id, pos)
		_each(func(m): Net.at_rest.rpc_id(m, id, pos))
		_arm_clock(id))
	p.round.finished.connect(_on_finished.bind(id))


## A new round's allowances under the room's rules.
func _apply_rules(id: int) -> void:
	var r: PlayerRound = _players[id].round
	r.mulligans = int(rules.mulligans)
	r.gimme = float(rules.gimme)


## Shot clock: from now (the ball at rest, this player's own flyover over) the player has shot_clock s,
## or the server plays a whiff for them. Re-armed at every rest; a stale timer (an earlier rest or
## hole) finds its token moved on.
func _arm_clock(id: int) -> void:
	if int(rules.shot_clock) <= 0 or not _players.has(id) or not _players[id].clock_live:
		return
	var p: Dictionary = _players[id]
	p.clock += 1
	var token: int = p.clock
	get_tree().create_timer(int(rules.shot_clock), true, false, true).timeout.connect(func() -> void:
		if state == State.PLAYING and _players.has(id) and _players[id].clock == token:
			_players[id].round.whiff())


func _load_hole(number: int) -> void:
	hole_number = number
	if _hole:
		remove_child(_hole)
		_hole.queue_free()
	var entry := _course[number - 1]
	_hole = GeneratedHole.new()
	_hole.build(Procgen.hole(entry.seed, entry.par, _procgen, _procgen.biomes[entry.biome]), _procgen)
	_hole.wind *= RoomRules.wind_scale(rules, _rules)
	add_child(_hole)
	_pars.append(entry.par)
	var order := 0
	for id in _players: # tee spots in join order, centred across the tee
		_scores[id].append(-1)
		_players[id].slot = order
		order += 1
	_tee_count = _players.size()
	var rests := {}
	for id in _players:
		rests[id] = _hole.rest_point(_tee_slot(_players[id].slot), _rules.drop_height)
	if number == 1:
		_each(func(m): Net.round_started.rpc_id(m, course_seed, number, rests, _roster(), card()))
	else:
		_each(func(m): Net.start_hole.rpc_id(m, number, rests))
	for id in _players:
		_players[id].round.start(_hole, _tee_slot(_players[id].slot))
	for id in _players:
		_await_flyover(id)


## Each player's hole is on from the moment it spawns: shots count at once, nobody waits for anyone.
## Their flyover only holds back their own shot clock, until they say it is over (flyover_done)
## or flyover_wait_max passes, so a late or lost message costs at most a late clock, never a shot.
func _await_flyover(id: int) -> void:
	_players[id].clock_live = false
	_players[id].clock += 1 # (the last hole's clock, if still running, is stale now)
	var number_now := hole_number
	get_tree().create_timer(Net.PARAMS.flyover_wait_max, true, false, true).timeout.connect(func() -> void:
		if hole_number == number_now:
			_clock_on(id))


## A player finished or skipped hole `number`'s flyover (an earlier hole's arrives late: ignored).
func flyover_done(id: int, number: int) -> void:
	if number == hole_number:
		_clock_on(id)


func _clock_on(id: int) -> void:
	if state != State.PLAYING or not _players.has(id) or _players[id].clock_live:
		return
	_players[id].clock_live = true
	if _players[id].round.can_shoot():
		_arm_clock(id)


func _on_finished(score: int, id: int) -> void:
	_scores[id][hole_number - 1] = score
	print("room %s: hole %d (par %d): %s %s" % [code, hole_number, _hole.par, _players[id].name, _players[id].round.message])
	_maybe_advance()


func _maybe_advance() -> void:
	if _advancing or _players.is_empty():
		return
	for id in _players:
		if _players[id].round == null or _players[id].round.score < 0:
			return
	_advancing = true
	var number := hole_number
	_award_hole()
	_each(func(m): Net.hole_complete.rpc_id(m, card()))
	await get_tree().create_timer(Net.PARAMS.scorecard_delay, false, true).timeout
	_advancing = false
	if state != State.PLAYING or number != hole_number or _players.is_empty():
		return
	if hole_number >= mini(int(rules.holes), _course.size()):
		state = State.ROUND_OVER
		for id in _players:
			var prof: Dictionary = get_parent().store.get_profile(_players[id].profile)
			prof.stats.rounds = int(prof.stats.rounds) + 1
		get_parent().store.save()
		_send_lobby()
		_each(func(m): Net.round_over.rpc_id(m, card()))
		get_parent().on_round_over(self)
	else:
		_load_hole(hole_number + 1)


func _physics_process(_delta: float) -> void:
	_tick += 1
	if state != State.PLAYING or _tick % maxi(1, roundi(Engine.physics_ticks_per_second / Net.PARAMS.snapshot_hz)) != 0:
		return
	var data := PackedInt32Array()
	for id in _players:
		var ball: Ball = _players[id].ball
		if ball == null:
			continue
		var pos := ball.global_position * 1000.0
		var vel := ball.linear_velocity * 1000.0 if ball.in_play else Vector3.ZERO
		data.append_array([id, roundi(pos.x), roundi(pos.y), roundi(pos.z), roundi(vel.x), roundi(vel.y), roundi(vel.z)])
	_each(func(m): Net.snapshot.rpc_id(m, _tick, data))


func _broadcast_player(id: int) -> void:
	var r: PlayerRound = _players[id].round
	var player_name: String = _players[id].name
	_each(func(m): Net.player_update.rpc_id(m, id, player_name, r.strokes, r.score, r.message, r.mulligans))


func _send_lobby() -> void:
	var lobby := {}
	for id in _players:
		lobby[id] = {name = _players[id].name, ready = _players[id].ready}
	_each(func(m): Net.lobby_state.rpc_id(m, code, host_id, state, lobby, rules))


func _each(send: Callable) -> void:
	for id in _players:
		send.call(id)


func _rests() -> Dictionary:
	var out := {}
	for id in _players:
		if _players[id].ball:
			out[id] = _players[id].ball.global_position
	return out


func _roster() -> Dictionary:
	var out := {}
	for id in _players:
		var r: PlayerRound = _players[id].round
		out[id] = {name = _players[id].name, strokes = r.strokes if r else 0, score = r.score if r else -1,
			message = r.message if r else "", mulligans = r.mulligans if r else 0,
			equipped = get_parent().store.get_profile(_players[id].profile).get("equipped", {})} # their shop look, for everyone to see
	return out


func _unique_name(wanted: String) -> String:
	wanted = wanted.strip_edges().left(16)
	if wanted.is_empty():
		wanted = "Player"
	var taken := []
	for id in _players:
		taken.append(_players[id].name)
	var candidate := wanted
	var n := 2
	while candidate in taken:
		candidate = "%s %d" % [wanted, n]
		n += 1
	return candidate


func _free_slot() -> int:
	var used := []
	for id in _players:
		used.append(_players[id].slot)
	var slot := 0
	while slot in used:
		slot += 1
	return slot


## Slot k of this hole's _tee_count, tee_slot_spacing apart across the tee (perpendicular to the
## hole's first leg), centred on the tee marker. Late joiners take the next free slot past the row.
func _tee_slot(slot: int) -> Vector3:
	var line := _hole.centreline
	var ahead := ((line[1] - line[0]) * Vector3(1, 0, 1)).normalized() if line.size() > 1 else Vector3.FORWARD
	var across := ahead.cross(Vector3.UP)
	return _hole.tee.global_position + across * (slot - (_tee_count - 1) * 0.5) * Net.PARAMS.tee_slot_spacing
