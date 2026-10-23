extends Node3D
## The player's view: swing, club picker, aiming, walk mode, debug overlay.
## Offline: a local PlayerRound applies the rules. Online (a lobby room): the server owns rules
## and balls; this sends shot commands, predicts its own ball for prediction_window, then shows
## server state; scorecards, spectating once holed, and the end-of-round summary.

enum Mode { SHOOTING, AIMING, WALKING, SPECTATING, FOLLOWING }

const CLUBS := Clubs.ALL
const CHARACTER: CharacterParams = preload("res://data/character.tres")
const LOOK: CharacterLook = preload("res://data/characters/default_look.tres")
const FEEDBACK: FeedbackParams = preload("res://data/feedback.tres")
const CELEBRATION: CelebrationParams = preload("res://data/celebration.tres")
const FLYOVER: FlyoverParams = preload("res://data/flyover.tres")

@export var rules: RulesData
@export var procgen: ProcgenParams
@export var random_course := true ## offline: a fresh course seed from the clock each game (tests and captures use the default)

var mode := Mode.SHOOTING
var course_seed := 0
var hole_number := 0 ## 1-based index into the course; 0 = a hand-placed hole
var strokes: int:
	get: return Net.players.get(Net.my_id, {}).get("strokes", 0) if Net.online() else _round.strokes
	set(value): _round.strokes = value
var score: int: ## final hole score; -1 while playing
	get: return Net.players.get(Net.my_id, {}).get("score", -1) if Net.online() else _round.score
var message: String:
	get: return Net.players.get(Net.my_id, {}).get("message", "") if Net.online() else _round.message

var _course: Array[Dictionary] = []
var _hole: Hole
var _club_index := 0
var _meter: PowerMeter
var _compass: Compass
var _wheel: ClubWheel
var _sound := AudioStreamPlayer.new()
var _hit_sounds := {} ## ClubData.Model → AudioStreamWAV
var _novelty_sounds := {} ## club_style → its impact sound (the shop's novelty heads)
const NOVELTY: NoveltyParams = preload("res://data/novelty.tres")
var _swish: AudioStreamWAV
var _applause := [] ## hole-in applause by result tier: over par, par, birdie, eagle
var _celebrated := {} # player id (0 offline) → true once their ball has dropped into this hole's cup
var _contact_locked := false # the first-person club has been placed at this shot's contact
var _show_hitbox := false # H: hitbox wireframe
var _menu: EscMenu
var _flyover: Flyover # this hole's flyover while it plays
var _hitbox_wire: MeshInstance3D
var _wind_streaks: CPUParticles3D
var _round := PlayerRound.new()
var _puppets: BallPuppets
var _card: ScorecardView
var _awaiting_rest := false # online: shot sent, waiting for the server to report our ball at rest
var _walk_mid_shot := false # walking (F) while our ball flies or rolls: F again goes back to it
var _rested_while_walking := false # and it came to rest meanwhile: F again takes the stance there
var _shot_token := 0
var _popup_token := 0
var _tab_time := 0.0
var _spectate_id := 0
var _spectate_yaw := 0.0
var _spectate_pitch := -0.35
var _bot_wait := 0.0
var _bot_shots := 0
var _bot_walked := false # bot: walked once (before its second shot), so remote walking gets exercised
var _bot_from := Vector3.INF # bot: where its last shot was played from
var _bot_repeat := 0 # bot: shots in a row from that same spot (back after a hazard)
var _since_hit := 0.0 # s since our shot fired (the follow camera takes over at follow_delay)
var _follow_dir := Vector3.FORWARD # follow camera heading (horizontal, unit)
var _follow_look := Vector3.ZERO # follow camera: the smoothed ball it looks at
var _follow_offset := Vector3.ZERO # follow camera: its smoothed offset from that
var _follow_fresh := true # follow camera: take over from wherever the camera is
var _spectate_shot_t := -1.0 # s into the watched player's shot; −1 between shots
var _swung_back := false # the club has been back past the contact window since address
var _fp_offset := Vector3.ZERO # first person: the constant correction that puts the face on the hitbox at address
var _fp_offset_key := [] # the address it was worked out for (club, ball, aim, eye)
var _fp_clearance := 0.0 # first person: the face's height over the ground at address (the soft floor)
var _ft_body := Vector3.ZERO # follow-through: where the (hidden) body faces now; zero = not started
var _ft_axis := Vector3.ZERO # follow-through: the swing plane's axis yawed so far (zero = the address one)
var _ft_right := Vector3.ZERO # follow-through: the eye's right turned with the body (zero = the address one)
var _pitch_follow_back := 0.0 # this swing: furthest back from address (rad), fading the address pitch-follow
var _caddied_at := Vector3.INF # where the ball was when the caddy last picked (a new lie picks again)
var _first_shot := true # no shot yet on this hole: the caddy may offer the driver
var _hud: Hud # player panel and club chip
var _hud_root := Control.new() # the HUD: faded in after the flyover
var _dim := Control.new() # inside it: dimmed while swinging
var _caddy_pending := false # a pick made during the flyover: pulsed once the HUD is back
var _pulse_token := 0 # the latest pick (a later one wins)
var _rules_label: Label # top right while Tab is held
var _clink: AudioStream # coins at hole-out
var _ui_sound := AudioStreamPlayer.new() # the scorecard's pop (never cuts a hit or the coins)
const SOUNDS: SoundParams = preload("res://data/sounds.tres")
var _chat: ChatBox # multiplayer rooms only
var _ambience: Ambience # the biome's air round the camera (clients)
var _soundscape: Soundscape # and its sound
var _warming := false # the shader warm-up is drawing (the air shows behind the black meanwhile)
const WARM_FRAMES := 3
const WARM_PEEKS := 32 ## points along the flight the warm-up looks from (a frame each)
var _practice: PracticeRange # the menu's Practice (offline), else null
var _bot_swing := Vector3.ZERO # bot: scripted swing angle, pitch, progress 0..1
var _swing_seq := 0
var _swing_clock := 0.0
var _walk_seq := 0
var _walk_clock := 0.0
var _swing_sent := [] # bot: [seq, angle] it sent, for the rooms test
var _tee_log := [] # bot: every player's tee spot per hole, for the lobby rules test
var _rig: GolferRig # the player's own golfer: arms and club in first person, whole body otherwise
var _rig_yaw := 0.0

@onready var _seed_field: LineEdit = $Overlay/Seed
@onready var _swing: Swing = $Swing
@onready var _ball: Ball = $Ball
@onready var _walker: Walker = $Walker
@onready var _camera: Camera3D = $Camera3D
@onready var _label: Label = $Overlay/Label


func _ready() -> void:
	Settings.apply_shadows() # this scene's sun, at the player's shadow quality
	_camera.fov = _swing.feel.view_fov # every view: one fixed FOV
	_swing.hit.connect(_on_hit)
	_swing.ticked.connect(_lock_club)
	_swing.spin_locked.connect(_on_spin_locked)
	_swing.whiffed.connect(_on_whiff)
	_rig = GolferRig.new(CHARACTER, ShopCatalog.my_look()) # as equipped in the shop
	_ball.wear(_rig.look)
	add_child(_rig)
	_build_hitbox_wire()
	_build_wind_streaks()
	_build_feedback()
	_build_menu()
	if Net.online():
		_go_online()
		return
	add_child(_round)
	_round.setup(rules, _ball)
	_round.at_rest.connect(func(_at: Vector3): _address())
	_seed_field.text_submitted.connect(_on_seed_submitted)
	if PracticeRange.requested: # the menu's Practice: the range and putting green instead of a course
		_practice = PracticeRange.new()
		add_child(_practice)
		_practice.start(self)
		return
	set_course(clock_seed() if random_course else procgen.default_course_seed)




## Esc: pause / settings overlay (EscMenu).
func _build_menu() -> void:
	_menu = EscMenu.new()
	_menu.main = self
	$Overlay.add_child(_menu)


## A course seed from the system clock (ms since the epoch, 32 bits), for a fresh course each game.
static func clock_seed() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0) & 0xFFFFFFFF


## New course from a 64-bit seed; plays its first hole.
func set_course(seed: int) -> void:
	course_seed = seed
	_course = Procgen.course(seed, procgen)
	_seed_field.text = "0x" + String.num_uint64(seed, 16)
	play_hole(1)


func play_hole(number: int) -> void:
	var wrapped := wrapi(number, 1, _course.size() + 1)
	load_hole(_build_hole(wrapped), wrapped)


## Swap in any hole (generated or hand-placed) and tee off.
func load_hole(hole: Hole, number := 0) -> void:
	_swap_hole(hole, number)
	restart()
	_begin_flyover()


## Entering a hole: the flyover down it (Flyover), ending on the shooting camera; HUD hidden and
## the swing blocked meanwhile. Skipped for test bots and script runs (tests, captures).
func _begin_flyover() -> void:
	if _flyover:
		_flyover.finished.disconnect(_flyover_done)
		_flyover.queue_free()
	if Net.bot or Settings._running_script():
		_flyover_done()
		return
	$Overlay.visible = false
	_swing.gesture.blocked = true
	_flyover = Flyover.new()
	_flyover.params = FLYOVER
	add_child(_flyover)
	var along := (_hole.cup.global_position - _hole.tee.global_position) * Vector3(1, 0, 1)
	if _hole is GeneratedHole and (_hole as GeneratedHole).is_building(): # on black until it is all built, building fast meanwhile
		var generated := _hole as GeneratedHole
		_flyover.progress = generated.build_progress
		generated.built.connect(_warm_up.bind(_flyover), CONNECT_ONE_SHOT)
		generated.stream_budget_ms = FLYOVER.hold_budget_ms
		_flyover.hold_ended.connect(func() -> void:
			if is_instance_valid(generated):
				generated.stream_budget_ms = GeneratedHole.STREAM_BUDGET_MS)
	else:
		_warm_up(_flyover) # nothing left to build
	var biome := _biome_of(_hole)
	_flyover.start(_camera, _hole, _camera.global_transform, _hole_card(), _hole.wind, along,
		biome.display_name if _hole is GeneratedHole else "", biome.card_color)
	_flyover.finished.connect(_flyover_done)


## Shader warm-up, behind the loading screen's black once the hole is built: one of everything the
## hole draws (each batched prop look, a tuft tile, a fog band, the water) and the biome's air is
## put in front of the camera for WARM_FRAMES frames so every pipeline compiles now, not mid-flyover;
## then the hold lifts.
func _warm_up(fly: Flyover) -> void:
	var kit := Node3D.new()
	add_child(kit)
	var ahead := _camera.global_transform * Vector3(0, -1.2, -6.0)
	if _hole is GeneratedHole:
		var k := 0
		for sample in (_hole as GeneratedHole).warmup_samples():
			var copy := sample.duplicate() as GeometryInstance3D
			copy.visibility_range_end = 0.0 # (drawn whatever the distance)
			kit.add_child(copy)
			if copy is MultiMeshInstance3D: # just its first instance, small, in a row in front of the camera
				var mm := (copy as MultiMeshInstance3D).multimesh.duplicate() as MultiMesh
				mm.instance_count = 1
				mm.set_instance_transform(0, Transform3D(Basis.from_scale(Vector3.ONE * 0.2), Vector3.ZERO))
				(copy as MultiMeshInstance3D).multimesh = mm
			copy.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * 0.2), # level (flat ones — water — face the lens)
				ahead + _camera.global_basis.x * (float(k % 9) - 4.0) * 0.5 + _camera.global_basis.y * float(k / 9) * 0.4)
			# ...and a second copy inside its own visibility fade (that draws with its own variant)
			var fading := copy.duplicate() as GeometryInstance3D
			fading.visibility_range_end = 7.0
			fading.visibility_range_end_margin = 3.0
			fading.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			kit.add_child(fading)
			fading.global_transform = copy.global_transform
			k += 1
	_warming = true # the biome's air drawn too
	for i in WARM_FRAMES:
		await get_tree().process_frame
	_warming = false
	kit.queue_free()
	# Then look along the flight, still behind the black, so what it will see draws once first
	for i in WARM_PEEKS:
		if not is_instance_valid(fly):
			return
		fly.peek = FLYOVER.duration * i / float(WARM_PEEKS - 1)
		await get_tree().process_frame
	if is_instance_valid(fly):
		fly.peek = -1.0
	if is_instance_valid(fly):
		fly.release()


## "Hole 7 · Par 4 · 412 m": the number, par and length along its centreline (the biome follows on the card).
func _hole_card() -> String:
	var length := 0.0
	for i in _hole.centreline.size() - 1:
		length += _hole.centreline[i].distance_to(_hole.centreline[i + 1])
	var parts: Array[String] = ["Hole %d" % hole_number if hole_number > 0 else "Practice hole", "Par %d" % _hole.par,
		"%d m" % roundi(length)]
	return " · ".join(parts) # (the biome follows in its own colour: Flyover.start's accent)


## While the flyover is up, the golfer stands at address in full view at the tee (it cuts to first person).
func _flyover_shows_golfer() -> bool:
	return _flyover != null


func _flyover_done() -> void:
	_flyover = null
	$Overlay.visible = true
	for item in $Overlay.get_children(): # no pop: the HUD fades back in
		if item is CanvasItem:
			item.modulate.a = 0.0
			create_tween().tween_property(item, "modulate:a", 1.0, FLYOVER.hud_fade)
	if _caddy_pending: # picked while the flyover hid the HUD: pulse once it has faded back in
		_caddy_pending = false
		var token := _pulse_token
		get_tree().create_timer(FLYOVER.hud_fade, false).timeout.connect(func() -> void:
			if token == _pulse_token and _flyover == null:
				_hud.pulse())
	_swing.gesture.blocked = _wheel.visible or _menu.visible
	if Net.online():
		Net.flyover_done.rpc_id(1, hole_number) # the server starts the hole once everyone's is done


## R: back to address — the Shooting-state reset (angle, pitch, speed state, club pose), the ball
## and the stroke count untouched. Only while addressing a ball at rest.
func _readdress() -> void:
	if (mode == Mode.SHOOTING or mode == Mode.AIMING) and not _swing.has_hit:
		_swung_back = false
		_follow_through_reset()
		_set_mode(Mode.SHOOTING)


## Back to the tee: the hole starts over (the Esc menu's Reset to tee, offline).
func restart() -> void:
	_first_shot = true
	_walk_mid_shot = false # (a reset or new hole: straight to the stance)
	_caddied_at = Vector3.INF
	_round.start(_hole, _hole.tee.global_position)


## 0..9 = driver..sand wedge (keys 1..0), 10 = putter (P). Bag is locked while the ball is in play.
func select_club(index: int) -> void:
	if not _ready_to_hit():
		return
	_club_index = wrapi(index, 0, CLUBS.size())
	_swing.club = CLUBS[_club_index]
	_swing.reset()


func _build_hole(number: int) -> GeneratedHole:
	var entry := _course[number - 1]
	var hole := GeneratedHole.new()
	hole.build(Procgen.hole(entry.seed, entry.par, procgen, procgen.biomes[entry.biome]), procgen)
	return hole


func _swap_hole(hole: Hole, number: int) -> void:
	hole_number = number
	if _hole:
		remove_child(_hole)
		_hole.queue_free()
	_hole = hole
	add_child(hole)
	_ball.course = hole
	_celebrated.clear()
	_first_shot = true # the caddy may offer the driver
	_caddied_at = Vector3.INF
	_apply_biome(_biome_of(hole))


func _biome_of(hole: Hole) -> Biome:
	return (hole as GeneratedHole).data.biome if hole is GeneratedHole else procgen.biomes[0] # hand-placed: parkland


## The biome's light on the scene (before the flyover, so it flies in it): sky gradient, fog, the
## sun's angle, colour and strength, and its air (Ambience).
func _apply_biome(b: Biome) -> void:
	var env := get_node_or_null("Look/Environment") as WorldEnvironment
	var sun := get_tree().get_first_node_in_group("sun") as DirectionalLight3D
	b.light(env.environment if env else null, sun, (_hole as GeneratedHole).data.water / 100.0 if _hole is GeneratedHole else 0.0)
	if DisplayServer.get_name() != "headless":
		if _ambience == null:
			_ambience = Ambience.new()
			add_child(_ambience)
		_ambience.set_kind(b.ambient, -sun.global_basis.z if sun else Vector3.DOWN, _hole, b.sun_bloom, b.sun_bloom_color, b.heat_shimmer)
		if _soundscape == null:
			_soundscape = Soundscape.new()
			add_child(_soundscape)
		_soundscape.play(b.soundscape, _hole)


func _ready_to_hit() -> bool:
	if mode != Mode.SHOOTING or _swing.has_hit:
		return false
	if Net.online():
		return not _awaiting_rest and score < 0 and Net.room_state == Net.RoomState.PLAYING and Net.hole_live
	return _round.can_shoot()


## Face the cup from the ball and take the shooting stance.
func _address() -> void:
	_swung_back = false
	_follow_through_reset()
	var to_cup := _hole.cup.global_position - _ball.global_position
	to_cup.y = 0.0
	_swing.aim = to_cup.normalized()
	if _ball.global_position.distance_to(_caddied_at) > 0.5: # a new lie (not a re-address)
		_caddied_at = _ball.global_position
		_wheel_carries(_ball.lie)
		if Settings.auto_caddy and not Net.bot: # set straight in: a new lie is when the bag opens
			_club_index = Clubs.caddy_pick(CLUBS, _ball.lie, to_cup.length(), _first_shot)
			_swing.club = CLUBS[_club_index]
			_caddy_pulse()
	if mode == Mode.WALKING and _walk_mid_shot: # walking off mid-shot: the stance waits for F
		_rested_while_walking = true
		return
	_set_mode(Mode.SHOOTING)


## The caddy's pick: the club chip pulses. During a flyover (HUD hidden) it waits until the HUD is
## back in (_flyover_done); a new pick restarts it.
func _caddy_pulse() -> void:
	_pulse_token += 1
	_caddy_pending = _flyover != null
	if not _caddy_pending:
		_hud.pulse()


## The club wheel's distances for this lie: measured carries, and the putter's longest putt on a green.
func _wheel_carries(lie: SurfaceData) -> void:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	_wheel.carries.clear()
	for club in CLUBS:
		if club.model == ClubData.Model.PUTTER: # it rolls: show the longest putt on a green
			var v := club.strength * club.power_mul * club.smash
			_wheel.carries.append("≤ %d m" % roundi(v * v / (2.0 * procgen.green.friction * gravity)))
		else:
			_wheel.carries.append("%d m" % roundi(club.carry_for(lie)))


## Entering Shooting always runs a full swing reset (stance, camera, skip first tick).
func _set_mode(next: Mode) -> void:
	mode = next
	# The swing keeps running while the follow camera flies: the follow-through still sets backspin.
	_swing.set_physics_process(mode == Mode.SHOOTING or mode == Mode.FOLLOWING)
	_swing.visible = mode == Mode.SHOOTING
	if mode == Mode.WALKING:
		_walker.enter(_swing.feet, _swing.aim)
	else:
		_walker.exit()
	if mode == Mode.SHOOTING:
		_swing.reset()
		_meter.release()
	elif mode == Mode.AIMING:
		_place_aim_camera()
	elif mode == Mode.SPECTATING:
		_spectate_id = 0
		_spectate_shot_t = -1.0
		_cycle_spectate()


## Looking down the aim line from above the ball; side-view clubs sit low behind it.
func _place_aim_camera() -> void:
	var feel := _swing.feel
	var aim := _swing.aim
	var eye := _ball.global_position + Vector3.UP * feel.aim_camera_height
	if _swing.club.aim_side_view:
		eye = _ball.global_position + Vector3.UP * feel.aim_side_height - aim * feel.aim_side_back
	_camera.look_at_from_position(eye, eye + aim)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER) and _chat and not _menu.visible:
			_chat.open() # (while it is open its box takes the keys)
		elif event.keycode == KEY_R:
			_readdress()
		elif event.keycode == KEY_N and hole_number > 0 and not Net.online():
			play_hole(hole_number + 1)
		elif event.keycode == KEY_M and Net.online() and _ready_to_hit() and _mulligans_left() > 0:
			Net.mulligan.rpc_id(1) # the server puts the ball back and re-sends the rest
		elif event.keycode == KEY_F:
			if mode == Mode.WALKING and _walk_mid_shot: # back to the ball: the stance if it has stopped, else the follow camera
				_walk_mid_shot = false
				if _rested_while_walking:
					_rested_while_walking = false
					_address()
				else:
					_follow_dir = _flat_dir(_ball_shown() - _camera.global_position)
					_follow_fresh = true
					_set_mode(Mode.FOLLOWING)
			elif mode == Mode.WALKING:
				_set_mode(Mode.SHOOTING)
			elif _swing.has_hit and (mode == Mode.SHOOTING or mode == Mode.FOLLOWING) and score < 0: # the ball out: walk on
				_swing.lock_spin() # (the follow-through stops here; the ball flies and rolls on as it is)
				_walk_mid_shot = true
				_rested_while_walking = false
				_set_mode(Mode.WALKING)
			elif _ready_to_hit() or ((mode == Mode.SHOOTING or mode == Mode.FOLLOWING) and score >= 0):
				_set_mode(Mode.WALKING)
		elif event.keycode == KEY_H:
			_show_hitbox = not _show_hitbox
		elif event.keycode == KEY_F3:
			Settings.change("show_debug", not Settings.show_debug) # F3: swing numbers, seeds, seed field, key legend
		elif event.keycode == KEY_P:
			select_club(CLUBS.size() - 1)
		elif event.keycode == KEY_Q and _ready_to_hit() and not _wheel.visible:
			_wheel.open(_club_index)
			_swing.gesture.blocked = true
		elif event.keycode == KEY_ESCAPE and _wheel.visible:
			_close_wheel(false)
		elif event.keycode == KEY_BRACKETLEFT:
			select_club(_club_index - 1)
		elif event.keycode == KEY_BRACKETRIGHT:
			select_club(_club_index + 1)
		elif event.keycode >= KEY_0 and event.keycode <= KEY_9:
			select_club((event.keycode - KEY_1 + 10) % 10)
	elif event is InputEventKey and not event.pressed and event.keycode == KEY_Q and _wheel.visible:
		_close_wheel(true)


## Release Q: take the highlighted club. Esc: keep the current one. Either way the swing resumes.
func _close_wheel(pick: bool) -> void:
	_wheel.close()
	_swing.gesture.blocked = false
	if pick and _wheel.selected >= 0 and _wheel.selected != _club_index:
		select_club(_wheel.selected)


func _physics_process(delta: float) -> void:
	var feel := _swing.feel
	var gesture := _swing.gesture
	if _wheel.visible:
		_wheel.steer(gesture.look)
		if not _ready_to_hit():
			_close_wheel(false) # the bag locks once the ball is in play
	if mode == Mode.SHOOTING and not _swing.has_hit:
		_meter.update(_swing.power, _swing.backswinging, delta)
	if _rig.hat_toy: # the propeller spins with the swing's power, easing back once it is over
		_rig.hat_toy.power = _swing.power if mode == Mode.SHOOTING and not _swing.has_hit else maxf(0.0, _rig.hat_toy.power - delta * 0.6)
	if mode == Mode.SHOOTING and _swing.swing_started: # the Eyeball looks at whoever swings
		Ball.eye_target = _camera.global_position if _rig.first_person else _rig._head.global_position
	# Spin bar: only while an iron or wedge shot is in the air (it locks on the first landing)
	_meter.spin_visible = _swing.has_hit and _swing.club.model in [ClubData.Model.IRON, ClubData.Model.WEDGE] \
		and _ball.in_play and _ball.carry < 0.0
	# The HUD dims while swinging and the ball is out, back to full once it settles (a new address)
	var swinging := (mode == Mode.SHOOTING and (_swing.swing_started or _swing.has_hit)) or mode == Mode.FOLLOWING
	_dim.modulate.a = move_toward(_dim.modulate.a, FEEDBACK.hud_dim_alpha if swinging else 1.0, FEEDBACK.hud_dim_rate * delta)
	_meter.spin = _swing.spin if _swing.spin_decided else _swing.spin_now()
	if _meter.spin_visible:
		_meter.queue_redraw() # the bar is frozen after impact; spin still moves
	if mode == Mode.AIMING:
		if not gesture.aim_held:
			_set_mode(Mode.SHOOTING)
		else:
			var yaw := feel.stance_rotate_speed * (-gesture.look.x * Settings.sensitivity_for(_swing.club) * feel.aim_mouse_gain) * delta
			_swing.aim = _swing.aim.rotated(Vector3.UP, yaw)
			_place_aim_camera()
	elif mode == Mode.SPECTATING:
		_spectate_yaw -= gesture.look.x * Net.PARAMS.spectate_look_gain
		_spectate_pitch = clampf(_spectate_pitch - gesture.look.y * Net.PARAMS.spectate_look_gain, -1.4, 0.3)
	elif mode == Mode.WALKING and Net.bot: # test bot: a short stroll along the aim, then back to the ball
		_bot_wait += delta
		_walker.global_position += _swing.aim * feel.walk_speed * 0.5 * delta
		_rig_yaw = atan2(-_swing.aim.x, -_swing.aim.z)
		if _bot_wait >= Net.PARAMS.bot_walk_time:
			_bot_wait = 0.0
			_set_mode(Mode.SHOOTING)
	elif _ready_to_hit():
		if Net.bot and not _bot_walked and Net.online() and _bot_shots >= 1: # by then every client has the hole
			_bot_walked = true
			_bot_wait = 0.0
			_set_mode(Mode.WALKING)
		elif Net.bot and strokes < int(Boot.arg("idle-shots", "0")):
			pass # test bot: stand there until the shot clock whiffs this many strokes on each hole
		elif Net.bot:
			_bot_wait += delta
			if _bot_wait >= Net.PARAMS.bot_think_time:
				if _club_index != _bot_club():
					_club_index = _bot_club() # take the club before swinging, so it shows remotely
					_swing.club = CLUBS[_club_index]
				_bot_swing = _bot_swing_pose(_bot_wait - Net.PARAMS.bot_think_time)
				if _bot_swing.z >= 1.0:
					_bot_wait = 0.0
					_bot_swing = Vector3(feel.address_angle, 0.0, 0.0)
					_bot_shot()
		elif gesture.aim_held:
			_set_mode(Mode.AIMING)
		elif not _swing.swing_started and not gesture.blocked: # A/D turns the stance only at address (not while typing)
			var turn := float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
			if turn != 0.0:
				_swing.aim = _swing.aim.rotated(Vector3.UP, -turn * feel.stance_rotate_speed * delta)
				_swing.reset()
	_send_swing(delta)
	_send_walk(delta)
	if mode == Mode.SHOOTING and _swing.has_hit:
		_since_hit += delta
		if _since_hit >= feel.follow_delay:
			_follow_dir = _flat_dir(_ball_shown() - _camera.global_position)
			_follow_fresh = true
			_set_mode(Mode.FOLLOWING)
	elif mode != Mode.FOLLOWING:
		_since_hit = 0.0


## Decimal, or 0x-hex up to 64 bits (wraps into the signed int, same bits).
func _on_seed_submitted(text: String) -> void:
	text = text.strip_edges().to_lower()
	var seed := 0
	if text.begins_with("0x"):
		for ch in text.substr(2):
			var digit := "0123456789abcdef".find(ch)
			if digit >= 0:
				seed = (seed << 4) | digit
	else:
		seed = text.to_int()
	_seed_field.release_focus()
	set_course(seed)


func _on_hit() -> void:
	_first_shot = false
	_impact_feedback()
	if not Net.online():
		_round.shot_taken()
		return
	var spin := 0.0 if _swing.spin_decided else -1.0
	_send_shot(_swing.shot_dir, _swing.path_angle, _swing.power, _club_index, spin)


func _on_spin_locked(spin: float) -> void:
	if Net.online():
		Net.shot_spin.rpc_id(1, spin)


# --- online ------------------------------------------------------------------------------------

func _go_online() -> void:
	_seed_field.editable = false
	_seed_field.focus_mode = Control.FOCUS_NONE
	_puppets = BallPuppets.new()
	_puppets.character = CHARACTER
	_puppets.look = LOOK
	_puppets.address_angle = _swing.feel.address_angle
	_puppets.stance = CLUBS[0].stance_dist
	_puppets.walk_speed = _swing.feel.walk_speed
	_puppets.hit_sounds = _hit_sounds
	_puppets.own_look = _rig.look # (our ball, when the server's copy of it is shown, in our own skin)
	_puppets.novelty_sounds = _novelty_sounds
	Net.whiff_received.connect(_puppets.on_whiff)
	add_child(_puppets)
	_card = ScorecardView.new()
	$Overlay.add_child(_card)
	_card.play_again_pressed.connect(func(): Net.play_again.rpc_id(1))
	_card.leave_pressed.connect(_leave)
	if not Net.local: # chat: multiplayer rooms only, over the scorecard
		_chat = ChatBox.new()
		_chat.gesture = _swing.gesture
		$Overlay.add_child(_chat)
	Net.snapshot_received.connect(_puppets.on_snapshot)
	Net.swing_received.connect(_puppets.on_swing)
	Net.walk_received.connect(_puppets.on_walk)
	_puppets.record = Net.bot
	Net.round_began.connect(_start_online_round)
	Net.hole_started.connect(_on_net_hole)
	Net.ball_at_rest.connect(_on_net_rest)
	Net.player_changed.connect(_on_player_changed)
	Net.hole_completed.connect(_on_hole_completed)
	Net.round_ended.connect(_on_round_ended)
	Net.coins_received.connect(func(awarded: Dictionary) -> void: # coins for the hole: a pop and a clink
		if int(awarded.get("total", 0)) > 0:
			_hud.pop_coins(int(awarded.total))
			_play(_clink, FEEDBACK.coin_clink_db, 1.0))
	Net.connection_failed.connect(func(_reason: String): get_tree().change_scene_to_file("res://lobby.tscn"))
	_start_online_round()


func _start_online_round() -> void:
	_card.close()
	course_seed = Net.course_seed
	_course = Procgen.course(course_seed, procgen, int(Net.rules.get("biome", 0))) # the room's biome pick, as the server
	_card.round_pars = _course.map(func(entry: Dictionary): return entry.par)
	_seed_field.text = "0x" + String.num_uint64(course_seed, 16)
	_on_net_hole(Net.hole_number, Net.rests)
	if Net.room_state == Net.RoomState.ROUND_OVER:
		_on_round_ended()


func _leave() -> void:
	Net.leave()
	get_tree().change_scene_to_file("res://lobby.tscn")


func _on_net_hole(number: int, rests: Dictionary) -> void:
	var hole := _build_hole(number)
	hole.wind *= RoomRules.wind_scale(Net.rules, rules) # the room's wind rule, as the server applies it
	_swap_hole(hole, number)
	_tee_log.append(rests.values().map(func(at: Vector3): return [at.x, at.y, at.z]))
	_puppets.hole = _hole
	for id in rests:
		_puppets.at_rest(id, rests[id])
	_on_net_rest(Net.my_id, rests.get(Net.my_id, _hole.tee.global_position), true)
	_begin_flyover()


## `new_hole`: the ball is on this player's tee of a hole just spawned, so Shooting starts there
## (the camera at the tee) whatever the last hole's score still reads (its update may come later)
## and wherever the follow camera was.
func _on_net_rest(id: int, at: Vector3, new_hole := false) -> void:
	_puppets.at_rest(id, at)
	if id != Net.my_id:
		return
	_shot_token += 1
	_awaiting_rest = false
	_ball.place(at)
	_ball.visible = true
	_puppets.own_visible = false
	if new_hole:
		_walk_mid_shot = false
	if score < 0 or new_hole:
		_address()


## Shot command to the server, and the same shot simulated locally as the prediction.
func _send_shot(dir: Vector3, path_angle: float, power: float, club: int, spin: float) -> void:
	Net.shot.rpc_id(1, dir, path_angle, power, club, spin)
	_awaiting_rest = true
	_shot_token += 1
	var token := _shot_token
	_ball.visible = true
	_puppets.own_visible = false
	await get_tree().create_timer(Net.PARAMS.prediction_window, false, true).timeout
	if token == _shot_token:
		_ball.visible = false # keeps simulating hidden: its landing still times the spin lock
		_puppets.own_visible = true


func _on_player_changed(id: int) -> void:
	if id == Net.my_id and score >= 0 and mode != Mode.SPECTATING and Net.room_state == Net.RoomState.PLAYING:
		_set_mode(Mode.SPECTATING) # holed or picked up: watch the others
	elif mode == Mode.SPECTATING and not Net.players.has(_spectate_id):
		_cycle_spectate()


## Tab tap while spectating: next player still on the course (else anyone, else the cup).
func _cycle_spectate() -> void:
	var others: Array = Net.players.keys().filter(func(id): return id != Net.my_id)
	others.sort()
	var playing: Array = others.filter(func(id): return Net.players[id].score < 0)
	var pool: Array = playing if not playing.is_empty() else others
	if pool.is_empty():
		_spectate_id = 0
		_spectate_shot_t = -1.0
		return
	var at := pool.find(_spectate_id)
	_spectate_id = pool[(at + 1) % pool.size()]


func _on_hole_completed() -> void:
	_card.show_hole(Net.card, hole_number)
	_pop_card()
	_popup_token += 1
	var token := _popup_token
	await get_tree().create_timer(Net.PARAMS.scorecard_delay, false, true).timeout
	if token == _popup_token and _card.showing == "hole":
		_card.close()


func _on_round_ended() -> void:
	_popup_token += 1
	_card.show_summary(Net.card, Net.is_host(), Net.my_id)
	_pop_card()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Net.bot and Net.report_path != "":
		var f := FileAccess.open(Net.report_path, FileAccess.WRITE)
		f.store_string(JSON.stringify({card = Net.card, balance = Net.balance, swing = {name = Net.players.get(Net.my_id, {}).get("name", ""),
			sent = _swing_sent, seen = _puppets.swing_log}, walk = {sent = _walk_seq, seen = _puppets.walk_log}, tees = _tee_log}))
		f.close()
		get_tree().quit()


func _mulligans_left() -> int:
	return int(Net.players.get(Net.my_id, {}).get("mulligans", 0))


## Test bot: aim at the cup, putter on the green, otherwise a club and power scaled to distance.
## --leave-after-shots N makes it drop out of the room right after its Nth shot.
func _bot_shot() -> void:
	var to_cup := _hole.cup.global_position - _ball.global_position
	to_cup.y = 0.0
	var d := to_cup.length()
	var club := _bot_club()
	var power := clampf(d / 230.0, 0.3, 1.0)
	if club == CLUBS.size() - 1:
		var arrive := _ball.feel.cup_capture_speed * 0.5 # die at the hole: a charged putt lips out
		var roll := sqrt(2.0 * procgen.green.friction * 9.8 * d + arrive * arrive)
		power = clampf(roll / CLUBS[club].strength, 0.05, 1.0)
	elif club == 8:
		power = clampf(d / 85.0, 0.2, 1.0)
	var dir := to_cup.normalized()
	# Back where the last shot was played from (a hazard: stroke and distance): lay up shorter and
	# a little to one side each time, as a player would, rather than repeat the same shot forever
	_bot_repeat = _bot_repeat + 1 if _ball.global_position.distance_to(_bot_from) < 0.5 else 0
	_bot_from = _ball.global_position
	if _bot_repeat > 0 and club != CLUBS.size() - 1:
		power *= pow(0.65, _bot_repeat)
		dir = dir.rotated(Vector3.UP, 0.25 * _bot_repeat * (1.0 if _bot_repeat % 2 == 1 else -1.0))
	_ball.launch(dir, 0.0, power, CLUBS[club], (-dir).cross(Vector3.UP))
	_send_shot(dir, 0.0, power, club, 0.0)
	_bot_shots += 1
	if _bot_shots == int(Boot.arg("leave-after-shots", "0")):
		await get_tree().create_timer(0.5, false, true).timeout
		get_tree().quit() # drop the connection mid-hole, like closing the game


func _process(delta: float) -> void:
	if Net.online():
		_update_tab(delta)
	var shown := _ball.global_position
	if Net.online() and _puppets.own_visible:
		shown = _puppets.own_position()
	if mode == Mode.SPECTATING:
		var target := _hole.cup.global_position
		var moving := false
		if _spectate_id != 0 and _puppets.has_ball(_spectate_id):
			target = _puppets.position_of(_spectate_id)
			moving = _puppets.velocity_of(_spectate_id).length() > 0.05
		# Their shot: the camera stays and tracks, then follows the ball, then cuts back to them.
		if moving and _spectate_shot_t < 0.0:
			_spectate_shot_t = 0.0
			_follow_dir = _flat_dir(target - _camera.global_position)
			_follow_fresh = true
		if _spectate_shot_t >= 0.0:
			_spectate_shot_t += delta
			if not moving and _spectate_shot_t > 0.5:
				_spectate_shot_t = -1.0
			elif _spectate_shot_t < _swing.feel.follow_delay:
				_track(target, delta)
			else:
				_follow(target, _puppets.velocity_of(_spectate_id), delta)
		if _spectate_shot_t < 0.0:
			var offset := Basis(Vector3.UP, _spectate_yaw) * Basis(Vector3.RIGHT, _spectate_pitch) \
				* Vector3(0, 0, Net.PARAMS.spectate_distance)
			_camera.look_at_from_position(target + offset + Vector3.UP * Net.PARAMS.spectate_height, target)
		shown = target
	elif mode == Mode.SHOOTING and _swing.has_hit:
		_track(shown, delta) # the shooting camera stays put and turns after the ball
	elif mode == Mode.FOLLOWING:
		_follow(shown, _own_ball_velocity(), delta)
	if _ambience:
		_ambience.visible = _flyover == null or _warming # (none of it over the flyover)
		_ambience.running = _flyover == null or _warming # (and not even simulating: it starts when the flyover ends)
		_ambience.follow(_camera)
	if _soundscape:
		_soundscape.follow(_camera)
	_watch_cup(shown)
	_hole.lift_flag(shown, delta, _celebrated.has(Net.my_id if Net.online() else 0))
	_pose_rig(delta)
	_draw_overlay(shown)
	_update_compass(shown)


## The compass centres on the stance's aim while addressing the ball, else on where the camera looks.
func _update_compass(shown: Vector3) -> void:
	var aim := _swing.aim if mode == Mode.SHOOTING or mode == Mode.AIMING else -_camera.global_basis.z
	var pin := _hole.cup.global_position
	var tee := _hole.tee.global_position
	_compass.markers = [{bearing = Compass.bearing(aim, shown, pin), color = FEEDBACK.compass_pin, shape = "flag",
		label = "%d m" % roundi(Vector2(pin.x - shown.x, pin.z - shown.z).length())}]
	if Vector2(tee.x - shown.x, tee.z - shown.z).length() > 2.0: # not while the ball is still on it
		_compass.markers.append({bearing = Compass.bearing(aim, shown, tee), color = FEEDBACK.compass_tee, shape = "tee"})
	var wind := _hole.wind
	if wind.length() > 0.05:
		_compass.markers.append({bearing = Compass.bearing(aim, Vector3.ZERO, wind), color = FEEDBACK.compass_wind,
			shape = "wind", label = "%.1f m/s" % wind.length()})
	_compass.queue_redraw()
	_update_wind_streaks(shown)


## A few faint streaks drifting past the ball with the wind while addressing it.
func _update_wind_streaks(shown: Vector3) -> void:
	var wind := _hole.wind
	var at_address := (mode == Mode.SHOOTING or mode == Mode.AIMING) and not _swing.has_hit
	_wind_streaks.emitting = at_address and wind.length() > FEEDBACK.wind_streak_min_speed
	if not _wind_streaks.emitting:
		return
	var dir := wind.normalized()
	_wind_streaks.global_position = shown - dir * FEEDBACK.wind_streak_upwind + Vector3.UP * FEEDBACK.wind_streak_height
	_wind_streaks.direction = dir
	_wind_streaks.initial_velocity_min = wind.length() * FEEDBACK.wind_streak_speed
	_wind_streaks.initial_velocity_max = wind.length() * FEEDBACK.wind_streak_speed * 1.3


func _build_wind_streaks() -> void:
	var p := CPUParticles3D.new()
	p.amount = FEEDBACK.wind_streak_amount
	p.lifetime = FEEDBACK.wind_streak_lifetime
	p.local_coords = false
	p.emitting = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(1.2, 0.25, 1.2)
	p.spread = 4.0
	p.gravity = Vector3.ZERO
	p.particle_flag_align_y = true # each streak lies along its travel
	var streak := BoxMesh.new()
	streak.size = Vector3(0.006, FEEDBACK.wind_streak_length, 0.006)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	streak.material = mat
	p.mesh = streak
	var fade := Gradient.new()
	fade.set_color(0, Color(FEEDBACK.wind_streak_color, 0.0))
	fade.set_color(1, Color(FEEDBACK.wind_streak_color, 0.0))
	fade.add_point(0.5, FEEDBACK.wind_streak_color)
	p.color_ramp = fade
	add_child(p)
	_wind_streaks = p


## Every ball this client draws (its own, and other players' from their snapshots): the moment one
## drops into the cup (inside the opening, below the rim), celebrate by its strokes against par.
## Client-side; a ball that leaves the cup's surroundings may celebrate again (a replayed hole).
func _watch_cup(shown: Vector3) -> void:
	var cup := _hole.cup.global_position
	var balls := {}
	if Net.online():
		for id in Net.players:
			if id == Net.my_id or _puppets.has_ball(id):
				balls[id] = [shown if id == Net.my_id else _puppets.position_of(id), int(Net.players[id].strokes)]
	else:
		balls[0] = [shown, strokes]
	for id in balls:
		var at: Vector3 = balls[id][0]
		var off := Vector2(at.x - cup.x, at.z - cup.z).length()
		if off > 1.0:
			_celebrated.erase(id)
		elif not _celebrated.has(id) and off < _swing.feel.cup_radius and at.y < cup.y - Ball.RADIUS:
			_celebrated[id] = true
			_celebrate(cup, balls[id][1] - _hole.par)
			if id == Net.my_id or not Net.online(): # reactive hats answer the result
				if _rig.hat_toy:
					_rig.hat_toy.react(balls[id][1] - _hole.par)
			else:
				_puppets.react(id, balls[id][1] - _hole.par)


## Confetti out of the cup, scaled by `result` (strokes − par): bogey or worse a puff, par a small
## burst, birdie bigger with a second pop, eagle or better big with a short slow motion (offline).
## Confetti, applause by the result, and the flagstick hops back in.
func _celebrate(at: Vector3, result: int) -> void:
	var p := CELEBRATION
	_hole.bounce_flag(p)
	if DisplayServer.get_name() == "headless":
		return
	var amount := p.amount_over_par if result > 0 else (p.amount_par if result == 0 else (p.amount_birdie if result == -1 else p.amount_eagle))
	Confetti.pop(self, at, amount, p)
	if result < 0:
		get_tree().create_timer(p.second_pop_delay, true, false, true).timeout.connect(
			func() -> void: Confetti.pop(self, at, int(amount * p.second_pop_share), p))
	var tier := 0 if result > 0 else (1 if result == 0 else (2 if result == -1 else 3))
	_play(_applause[tier], p.applause_volume_db[tier], 1.0) # polite for par, more for a birdie, cheering for an eagle
	if _soundscape: # the birds and the wind step back while the crowd cheers
		_soundscape.duck(_applause[tier].get_length())
	if result <= -2 and not Net.online(): # the server keeps time online
		Engine.time_scale = p.slowmo_scale
		get_tree().create_timer(p.slowmo_time, true, false, true).timeout.connect(func() -> void: Engine.time_scale = 1.0)


## Tab held: full scorecard. Tab tapped while spectating: next player.
func _update_tab(delta: float) -> void:
	if _chat and _chat.is_open():
		return # typing: Tab is the chat box's (the card stays as it is)
	if Input.is_key_pressed(KEY_TAB):
		_tab_time += delta
		if _tab_time >= Net.PARAMS.tab_hold_time and _card.showing == "":
			_card.show_full(Net.card, hole_number)
			_show_rules(true)
	elif _tab_time > 0.0:
		if _tab_time < Net.PARAMS.tab_hold_time and mode == Mode.SPECTATING:
			_cycle_spectate()
		if _card.showing == "full":
			_card.close()
		_show_rules(false)
		_tab_time = 0.0


## The room's rules (holes, shot clock, wind, mulligans, gimmes), small at the top right, while Tab is held.
func _show_rules(on: bool) -> void:
	if _rules_label == null:
		_rules_label = Label.new()
		_rules_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_rules_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		_rules_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_rules_label.position += Vector2(-FEEDBACK.rules_margin, FEEDBACK.rules_margin + FEEDBACK.hud_height + 8.0) # (under the coins)
		_rules_label.add_theme_font_size_override("font_size", FEEDBACK.rules_font)
		_rules_label.add_theme_color_override("font_color", FEEDBACK.card_muted)
		$Overlay.add_child(_rules_label)
		$Overlay.move_child(_rules_label, 0)
	_rules_label.text = RoomRules.describe(Net.card.get("rules", Net.rules))
	_rules_label.visible = on


func _draw_overlay(shown: Vector3) -> void:
	var pin := _hole.cup.global_position - shown
	var where := "hand-placed hole"
	if hole_number > 0:
		where = "course 0x%s   hole %d/%d   hole seed 0x%s" % [String.num_uint64(course_seed, 16), hole_number,
			_course.size(), String.num_uint64(_course[hole_number - 1].seed, 16)]
	var board := ""
	var keys := "   R: re-address   reset to tee: in the Esc menu   N: next hole   seed field: Esc, click, type, Enter"
	if Net.online():
		where = "room %s   %s   " % [Net.room_code, Net.players.get(Net.my_id, {}).get("name", "?")] + where
		for id in Net.players:
			var p: Dictionary = Net.players[id]
			var watching := "  ◀ watching" if mode == Mode.SPECTATING and id == _spectate_id else ""
			board += "\n  %s  %s%s" % [p.name, ("done: %d" % p.score) if p.score >= 0 else ("shot %d" % p.strokes), watching]
		keys = "   Tab hold: scorecard%s   Esc: menu" % ("   Tab tap: next player" if mode == Mode.SPECTATING else "")
	_seed_field.visible = Settings.show_debug
	_hud.visible = not Settings.show_debug
	if not Settings.show_debug: # the player's HUD (Hud, compass, power meter); the label keeps the messages
		_hud.show_state(strokes + (1 if score < 0 else 0), _hole.par, Vector2(pin.x, pin.z).length(),
			_swing.club.label, _wheel.carries[_club_index], _practice.status() if _practice else "")
		_label.position.y = _hud.panel_bottom() + 10.0
		_hud.set_coins(Net.balance if Net.online() else -1)
		# Messages while the hole is on (penalties, shot clock…); not the finish ("Holed: 5 (E)")
		_label.text = message if message != "" and score < 0 else ("Waiting for the others' flyovers…" if Net.online() and not Net.hole_live else "")
		if Net.online() and _ready_to_hit():
			var clock := Net.clock_left()
			if clock >= 0.0:
				_label.text += "\nShot clock  %d s" % ceili(clock)
			if _mulligans_left() > 0 and strokes > 0:
				_label.text += "\nM: mulligan (%d left)" % _mulligans_left()
		return
	_label.position.y = 16.0
	_label.text = "%s\n%s\nclub  %s     lie  %s\nshot  %d     par  %d     to pin  %.1f m\n\npower  %.3f\npeak speed  %.1f m/s\npath angle  %.1f°\npitch  %.3f rad\nspin  %.2f\ncarry  %s\n\n%s%s\n\nclick: capture   Esc: menu   1-0 / P / [ ] / hold Q: club   A/D: aim   RMB hold: look down the line   F: walk   H: hitbox   F3: debug%s" % [
		where,
		Mode.keys()[mode],
		_swing.club.label,
		_ball.lie.resource_name if _ball.lie else "-",
		strokes,
		_hole.par,
		Vector2(pin.x, pin.z).length(),
		_swing.power,
		_swing.peak_speed,
		rad_to_deg(_swing.path_angle),
		_swing.pitch,
		_swing.spin_now() if _swing.has_hit and _swing.spin == 0.0 else _swing.spin,
		"%.1f m" % _ball.carry if _ball.carry >= 0.0 else "-",
		message,
		board,
		keys,
	]


## First person, every physics tick after Swing has moved the hitbox: the club on the swing arc
## (GolferRig.pose_fp) at this tick's angle and pitch, plus one constant offset worked out at address
## (the hitbox's leading-face centre there minus the club's face centre there), the address pitch-follow,
## the soft floor, and
## after the hit the follow-through (_follow_through). Nothing holds, clamps or corrects it at impact.
func _lock_club() -> void:
	if mode != Mode.SHOOTING or _flyover_shows_golfer():
		return
	var after_hit := _swing.has_hit and _contact_locked # from the tick after the hit
	var hit_tick := _swing.has_hit and not _contact_locked
	_contact_locked = _swing.has_hit
	var box := _swing.hitbox_box(_swing.hitbox_position())
	_hitbox_wire.global_transform = box
	_rig.first_person = true
	_rig.set_club(_swing.club)
	_rig.address(_swing.feet, _swing.aim, _swing.address_point())
	var rest := _swing.feel.address_angle
	var rel := _swing.angle - rest
	var forward := -box.basis.x.normalized()
	var eye := _camera.global_position
	var right := _swing.eye_right()
	var key := [_swing.club, _swing.address_point(), _swing.aim, eye]
	if key != _fp_offset_key: # a new address: the head squared, then the offset that puts the face on the hitbox there
		_fp_offset_key = key
		_rig.fp_head_basis = Basis()
		_rig.pose_fp(0.0, 0.0, eye, right, forward, Vector3.ZERO)
		# The head turned in the club so that at address its face looks along the target, sole flat and
		# crown up (to the camera); it then rides the arc with the club, the same turn at every angle
		var square := Basis(Vector3.UP.cross(-forward).normalized(), Vector3.UP, -forward)
		_rig.fp_head_basis = _rig._club_model.global_basis.inverse() * square
		_rig.pose_fp(0.0, 0.0, eye, right, forward, Vector3.ZERO)
		var rest_box := _swing.hitbox_box(_swing.hitbox_position_at(rest, 0.0))
		_fp_offset = rest_box.origin - rest_box.basis.x * 0.5 - _fp_face() # the face's centre on the hitbox's leading face
		_rig.pose_fp(0.0, 0.0, eye, right, forward, _fp_offset)
		_fp_clearance = _fp_face().y - _hole.height_at(_fp_face()) # the face's height over the ground at address
		_pitch_follow_back = 0.0
	# The club at this tick's angle and pitch (posed before the hit test), the swing
	# plane and the eye's right as the follow-through has yawed them so far
	# Pitch at address: before the backswing the face follows the hitbox's own pitch shift (as if the
	# pitch turn pivoted on the face), fading into the turn about the eye by fp_pitch_follow_span
	# of backswing (by the furthest back this swing, so it never comes back at impact)
	_pitch_follow_back = maxf(_pitch_follow_back, -rel)
	var follow := 1.0 - smoothstep(0.0, CHARACTER.fp_pitch_follow_span, _pitch_follow_back)
	var pitch := _swing.pitch
	var face_flat := Vector3.ZERO
	if follow > 0.0 and pitch != 0.0:
		_rig.pose_fp(rel, 0.0, eye, right, forward, _fp_offset, _ft_axis, _ft_right)
		face_flat = _fp_face()
	_rig.pose_fp(rel, pitch, eye, right, forward, _fp_offset, _ft_axis, _ft_right)
	if follow > 0.0 and pitch != 0.0:
		var shift := _swing.hitbox_position_at(_swing.angle, pitch) - _swing.hitbox_position_at(_swing.angle, 0.0)
		_rig._club.global_position += (face_flat + shift - _fp_face()) * follow
	# The arc outruns the hitbox's slide: drawn back by the club's fp_contact_offset, eased in from address
	# (none) to impact (all), so the face stays on the box's leading face at both
	_rig._club.global_position -= _swing.aim * _swing.club.fp_contact_offset * contact_ramp(_swing, _swing.angle)
	# Soft floor: a face that would sink below its address height over the ground lifts the whole club
	# just enough (never turning it), easing in over fp_floor_soft
	var face_now := _fp_face()
	var sink := _hole.height_at(face_now) + _fp_clearance - face_now.y
	var soft := CHARACTER.fp_floor_soft
	if sink > 0.0:
		_rig._club.global_position.y += sink * sink / (2.0 * soft) if sink < soft else sink - soft * 0.5
		_rig._place_shadow()
	if after_hit and _swing.club.model != ClubData.Model.PUTTER:
		_follow_through(rel, right)
	_rig_yaw = _rig.rotation.y
	if hit_tick: # the drawn face at or past the ball's back: the ball's look starts ahead of it (visual only)
		var overlap := (_fp_face() - (_swing.address_point() - _swing.aim * Ball.RADIUS)).dot(_swing.aim)
		if overlap >= 0.0:
			_ball.nudge_view(_swing.aim * (overlap + FEEDBACK.impact_nudge_margin), FEEDBACK.impact_nudge_time)


## How much of fp_contact_offset is taken back at swing angle `angle`, in units of u = the angle from
## address over the angle from address to where the hitbox's leading face meets the ball's back (so 0
## at address, 1 there): u itself through address and up to the meeting (no crease at address), then
## easing to a stop over fp_contact_ramp more units each side (quadratic, so the head's path stays
## smooth: past the meeting it settles at 1 + ramp/2, back in the backswing at −ramp/2).
static func contact_ramp(swing: Swing, angle: float) -> float:
	var rest := swing.feel.address_angle
	var box := swing.hitbox_box(swing.hitbox_position_at(rest, 0.0))
	var half := box.basis.x.length() * 0.5
	var meet := swing.angle_at(swing.address_point() - swing.aim * (ClubModel.BALL_RADIUS + half))
	if meet <= rest:
		return 0.0
	var u := (angle - rest) / (meet - rest)
	var w := CHARACTER.fp_contact_ramp
	if u > 1.0:
		var e := minf(u - 1.0, w)
		return 1.0 + e - e * e / (2.0 * w)
	if u < 0.0:
		var e := minf(-u, w)
		return -(e - e * e / (2.0 * w))
	return u


## The follow-through (from the tick after the hit, not the
## putter; it runs after the pose, so it shows from the tick after that): the body turns at
## fp_follow_body_rate toward the face direction slerped to the target by factor = clamp(angle / π, 0, 1), the eye's right
## turns with it, and the swing plane's axis yaws about UP by half its flat angle to the target, times
## factor.
func _follow_through(rel: float, right: Vector3) -> void:
	var factor := clampf(rel / PI, 0.0, 1.0)
	var face_dir := -_swing.body_frame().z # away from the golfer: the way the body faces at address
	var target := _swing.aim
	if _ft_body == Vector3.ZERO:
		_ft_body = face_dir
	var want := face_dir.slerp(target, factor)
	_ft_body = _ft_body.slerp(want, 1.0 - exp(-CHARACTER.fp_follow_body_rate / Engine.physics_ticks_per_second)).normalized()
	_ft_right = right.rotated(Vector3.UP, face_dir.signed_angle_to(_ft_body, Vector3.UP))
	var axis0 := _rig.fp_axis0
	var flat := Vector3(axis0.x, 0.0, axis0.z)
	_ft_axis = axis0.rotated(Vector3.UP, 0.5 * flat.signed_angle_to(target, Vector3.UP) * factor)


## Back to address: no follow-through.
func _follow_through_reset() -> void:
	_pitch_follow_back = 0.0
	_ft_body = Vector3.ZERO
	_ft_axis = Vector3.ZERO
	_ft_right = Vector3.ZERO


## The first-person club's face centre (world).
func _fp_face() -> Vector3:
	var head: Node3D = _rig._club_model.get_node("Head")
	return head.to_global(ClubModel.face_centre(_swing.club, _rig.girth_scale(), _rig.params.club_head_scale))


## The swing rests at a slight takeaway (address_angle): show the club at address there, easing to
## the true angle by the time it is back past the contact window. Sets _swung_back.
func _shown_angle(angle: float) -> float:
	var back := _swing.impact_angle() - CHARACTER.contact_blend
	if angle < back:
		_swung_back = true
	if _swung_back:
		return angle
	var rest := _swing.feel.address_angle
	return angle - rest * clampf((angle - back) / (rest - back), 0.0, 1.0)


## Debug (H): the hitbox's edges, drawn over everything.
func _build_hitbox_wire() -> void:
	var lines := PackedVector3Array()
	for a in 3: # 4 edges along each axis of a unit cube
		for u in [-0.5, 0.5]:
			for v in [-0.5, 0.5]:
				var p := Vector3.ZERO
				p[(a + 1) % 3] = u
				p[(a + 2) % 3] = v
				p[a] = -0.5
				lines.append(p)
				p[a] = 0.5
				lines.append(p)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = lines
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.2, 0.2)
	mat.no_depth_test = true
	mesh.surface_set_material(0, mat)
	_hitbox_wire = MeshInstance3D.new()
	_hitbox_wire.mesh = mesh
	_hitbox_wire.top_level = true
	_hitbox_wire.visible = false
	add_child(_hitbox_wire)


## Own golfer per mode: first-person club locked to the hitbox while shooting (_lock_club()),
## the whole body while aiming, the walk loop in walk mode, hidden while spectating.
func _pose_rig(delta: float) -> void:
	_rig.visible = mode != Mode.SPECTATING
	_hitbox_wire.visible = _show_hitbox and mode == Mode.SHOOTING
	if mode == Mode.SHOOTING and not _flyover_shows_golfer():
		pass # first person: the club is placed every physics tick by _lock_club()
	elif mode == Mode.AIMING or mode == Mode.FOLLOWING or mode == Mode.SHOOTING: # (shooting: the flyover sees the golfer at the tee)
		_rig.first_person = false # the aim and follow cameras see the whole golfer
		_rig.set_club(_swing.club)
		_rig.address(_swing.feet, _swing.aim, _swing.address_point())
		# Around impact, pull the visible head onto the hitbox so it meets the ball as the hit fires;
		# only on the way down (at address the head rests on the ball, not on the waiting hitbox).
		var shown_angle := _shown_angle(_swing.angle)
		var near := 0.0
		if _swung_back:
			near = clampf(1.0 - absf(_swing.angle - _swing.impact_angle()) / CHARACTER.contact_blend, 0.0, 1.0)
		var target := _swing.hitbox_position()
		# A slow swing rests the head against the ball instead of drawing it through; a real swing
		# (peak speed past the threshold) passes through on the hit tick.
		var slow := not _swing.has_hit and _swing.peak_speed < _swing.club.strength * CHARACTER.contact_clamp_speed_frac
		_rig.pose_swing(shown_angle, _swing.pitch, target, near * near * (3.0 - 2.0 * near), slow)
		_rig_yaw = _rig.rotation.y
	elif mode == Mode.WALKING:
		_rig.first_person = false
		var flat := _walker.velocity * Vector3(1, 0, 1)
		if flat.length() > 0.1:
			_rig_yaw = lerp_angle(_rig_yaw, atan2(-flat.x, -flat.z), 1.0 - exp(-CHARACTER.turn_rate * delta))
		_rig.transform = Transform3D(Basis(Vector3.UP, _rig_yaw), _walker.global_position)
		_rig.pose_walk(flat.length() / _swing.feel.walk_speed, delta)


## Online, in Shooting with the ball at rest: own swing angle and pitch to the room at
## swing_send_hz (unreliable). Stops by itself once the shot fires (no longer ready to hit).
func _send_swing(delta: float) -> void:
	if not Net.online() or mode != Mode.SHOOTING or not _ready_to_hit():
		_swing_clock = 0.0
		return
	_swing_clock += delta
	var interval := 1.0 / Net.PARAMS.swing_send_hz
	if _swing_clock < interval:
		return
	_swing_clock = fmod(_swing_clock, interval)
	_swing_seq += 1
	var angle := _bot_swing.x if Net.bot else _swing.angle
	var pitch := _bot_swing.y if Net.bot else _swing.pitch
	Net.swing_state.rpc_id(1, _swing_seq, angle, pitch, _club_index)
	if Net.bot:
		_swing_sent.append([_swing_seq, angle])


## Online, walking: own feet and facing to the room at walk_send_hz (unreliable), so others see
## the golfer walk. Stopping is implicit: their side times out back to address.
func _send_walk(delta: float) -> void:
	if not Net.online() or mode != Mode.WALKING:
		_walk_clock = 0.0
		return
	_walk_clock += delta
	var interval := 1.0 / Net.PARAMS.walk_send_hz
	if _walk_clock < interval:
		return
	_walk_clock = fmod(_walk_clock, interval)
	_walk_seq += 1
	Net.walk_state.rpc_id(1, _walk_seq, _walker.global_position, _rig_yaw)


## Test bot's swing over time t (s): back to the top in 0.5 s, down through impact in 0.15 s.
## z is progress; at 1 the bot fires its shot.
func _bot_swing_pose(t: float) -> Vector3:
	var address := _swing.feel.address_angle
	var pitch := 0.03 * sin(t * 9.0)
	if t < 0.5:
		return Vector3(lerpf(address, -2.0, t / 0.5), pitch, t / 0.65)
	return Vector3(lerpf(-2.0, 0.3, minf((t - 0.5) / 0.15, 1.0)), pitch, minf(t / 0.65, 1.0))


## Test bot's club: putter on the green or close in, pitching wedge inside 100 m, else driver.
func _bot_club() -> int:
	var d := Vector2(_hole.cup.global_position.x - _ball.global_position.x,
		_hole.cup.global_position.z - _ball.global_position.z).length()
	if _ball.lie == procgen.green or d < 20.0:
		return CLUBS.size() - 1
	return 8 if d < 100.0 else 0


# --- impact feedback, power meter, club wheel --------------------------------------------------

func _build_feedback() -> void:
	_meter = PowerMeter.new()
	_meter.params = FEEDBACK
	$Overlay.add_child(_meter)
	# The HUD: _hud_root takes the flyover's fade-in, _dim inside it the swing dim (they multiply)
	for layer in [_hud_root, _dim]:
		layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Overlay.add_child(_hud_root)
	$Overlay.move_child(_hud_root, 0) # under the menus, the wheel and the card
	_hud_root.add_child(_dim)
	_compass = Compass.new()
	_compass.params = FEEDBACK
	_dim.add_child(_compass)
	_hud = Hud.new()
	_dim.add_child(_hud)
	_wheel = ClubWheel.new()
	_wheel.params = FEEDBACK
	_wheel.clubs = CLUBS
	_wheel_carries(null)
	$Overlay.add_child(_wheel)
	_sound.bus = Settings.SFX_BUS # the settings menu's sound-effects volume
	add_child(_sound)
	for model in ClubData.Model.values():
		_hit_sounds[model] = SOUNDS.club(model)
	_ui_sound.bus = Settings.SFX_BUS
	add_child(_ui_sound)
	_ball.add_child(BallSounds.new(_ball)) # landings, bounces, the cup
	_novelty_sounds[1] = PlaceholderSounds.wet_slap()
	_novelty_sounds[2] = PlaceholderSounds.squeak()
	_swish = PlaceholderSounds.swish()
	_clink = SOUNDS.coin
	for result in [1, 0, -1, -2]:
		_applause.append(PlaceholderSounds.applause(result))


## A whiff: the swish, the reactive hat (a propeller sputters), and the room told (their view of us).
func _on_whiff() -> void:
	_play(_swish, FEEDBACK.swish_volume_db, 1.0)
	if _rig.hat_toy:
		_rig.hat_toy.whiffed()
	if Net.online():
		Net.whiffed.rpc_id(1)


## Contact: the club's hit sound scaled by power, a camera kick, a puff of the
## lie at the ball, and the meter showing the hit.
func _impact_feedback() -> void:
	var power := _swing.power
	var pitch := FEEDBACK.driver_hit_pitch if _swing.club.model == ClubData.Model.DRIVER else FEEDBACK.hit_pitch
	match _rig.look.club_style:
		1: # Fresh Catch: a wet slap
			_play(_novelty_sounds[1], lerpf(NOVELTY.slap_volume_db.x, NOVELTY.slap_volume_db.y, power), lerpf(NOVELTY.slap_pitch.x, NOVELTY.slap_pitch.y, power), Settings.CLUBS_BUS)
		2: # Squeaky Set: a squeak
			_play(_novelty_sounds[2], lerpf(NOVELTY.squeak_volume_db.x, NOVELTY.squeak_volume_db.y, power), lerpf(NOVELTY.squeak_pitch.x, NOVELTY.squeak_pitch.y, power), Settings.CLUBS_BUS)
		_:
			_play(_hit_sounds[_swing.club.model], lerpf(FEEDBACK.hit_volume_db.x, FEEDBACK.hit_volume_db.y, power),
				lerpf(pitch.x, pitch.y, power), Settings.CLUBS_BUS)
	_rig.club_impact(power) # (a novelty head flops)
	_meter.on_hit(power)


## The scorecard comes up: a pop.
func _pop_card() -> void:
	_ui_sound.stream = SOUNDS.scorecard
	_ui_sound.volume_db = SOUNDS.scorecard_db
	_ui_sound.play()


func _play(stream: AudioStream, volume_db: float, pitch_scale: float, bus := Settings.SFX_BUS) -> void:
	_sound.bus = bus
	_sound.stream = stream
	_sound.volume_db = volume_db
	_sound.pitch_scale = pitch_scale
	_sound.play()


# --- ball cameras ------------------------------------------------------------------------------

## Stay where we are and turn toward `target`: yaw eased at track_yaw_rate, pitch at
## track_pitch_rate.
func _track(target: Vector3, delta: float) -> void:
	var feel := _swing.feel
	var to := target - _camera.global_position
	if to.length() < 0.5:
		return
	var want_yaw := atan2(-to.x, -to.z)
	var want_pitch := atan2(to.y, Vector2(to.x, to.z).length())
	var now := _camera.global_basis.get_euler()
	var yaw := lerp_angle(now.y, want_yaw, 1.0 - exp(-feel.track_yaw_rate * delta))
	var pitch := lerpf(now.x, want_pitch, 1.0 - exp(-feel.track_pitch_rate * delta))
	_camera.global_basis = Basis.from_euler(Vector3(pitch, yaw, 0.0))


## Third-person follow: it looks at a smoothed copy of the ball (follow_look_rate) and sits at a
## smoothed offset from it, behind along the ball's (smoothed) travel and above. Neither follows
## the ball's vertical turn at the apex directly, so the pitch never snaps; taking over from the
## shooting camera it starts from where that one was and what it looked at.
func _follow(target: Vector3, velocity: Vector3, delta: float) -> void:
	var feel := _swing.feel
	if _follow_fresh:
		_follow_fresh = false
		_follow_look = _camera.global_position - _camera.global_basis.z * _camera.global_position.distance_to(target)
		_follow_offset = _camera.global_position - _follow_look
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() > 0.5:
		_follow_dir = _follow_dir.slerp(flat.normalized(), 1.0 - exp(-feel.follow_turn * delta)).normalized()
	_follow_look = _follow_look.lerp(target, 1.0 - exp(-feel.follow_look_rate * delta))
	var want := -_follow_dir * feel.follow_distance + Vector3.UP * feel.follow_height
	_follow_offset = _follow_offset.lerp(want, 1.0 - exp(-feel.follow_lag * delta))
	_camera.global_position = _follow_look + _follow_offset
	if _follow_offset.length() > 0.5:
		_camera.look_at(_follow_look)


func _ball_shown() -> Vector3:
	return _puppets.own_position() if Net.online() and _puppets.own_visible else _ball.global_position


func _own_ball_velocity() -> Vector3:
	if Net.online() and _puppets.own_visible:
		return _puppets.velocity_of(Net.my_id)
	return _ball.linear_velocity


static func _flat_dir(v: Vector3) -> Vector3:
	var flat := Vector3(v.x, 0.0, v.z)
	return flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD
