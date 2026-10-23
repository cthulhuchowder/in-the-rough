class_name HatToy
extends Node3D
## The shop's reactive hats, on the golfer's head joint (GolferRig builds one for hat_style 3–5):
## Hat Green: a putting-green disc worn flat, a mini flagstick and a ball that rolls round it with the
## head's movement (inertia and tilt) and drops into the mini cup on a birdie or better. Course Goose: a
## chubby goose sitting on the head that blinks and turns its head now and then, and honks on a bogey
## or worse. Power Propeller: a beanie whose propeller spins with the swing's power, sputtering to a
## stop on a whiff. The owner feeds `power` every frame and calls react() / whiffed() on the events;
## the same for the player's own golfer and other players' (ball_puppets). Flat-shaded vertex colours.
## Values in data/novelty.tres.

const P: NoveltyParams = preload("res://data/novelty.tres")
enum Kind { GREEN = 3, GOOSE = 4, PROPELLER = 5 }

var kind: int
var power := 0.0 ## 0..1, the swing's power now (the propeller)
var _t := 0.0
# Hat Green
var _ball: Node3D
var _cup := Vector2.ZERO
var _radius := 0.0 # the disc's
var _roll := Vector2.ZERO # ball on the disc, m from its centre (x, z)
var _roll_v := Vector2.ZERO
var _last := Vector3.ZERO # the disc's world position last frame, and the velocity before
var _last_v := Vector3.ZERO
var _sunk := -1.0 # s since it dropped in (−1: on the green)
# Course Goose
var _neck: Node3D
var _head: Node3D
var _jaw: Node3D
var _eyes: Array[Node3D] = []
var _look := 0.0 # its head's turn now, and where it is turning to
var _look_to := 0.0
var _next_look := 1.0
var _next_blink := 2.0
var _honk := -1.0 # s since it honked
# Power Propeller
var _prop: Node3D
var _spin := 0.0 # rad/s
var _sputter := -1.0 # s since the whiff (−1: none)
var _sputter_from := 0.0 # rad/s when it whiffed
var _sound: AudioStreamPlayer3D
static var _sounds := {}


## `top`: the crown of the head (head joint space), `width` the head's.
func _init(hat_kind: int, top: Vector3, width: float) -> void:
	kind = hat_kind
	position = top
	match kind:
		Kind.GREEN:
			_build_green(width)
		Kind.GOOSE:
			_build_goose(width)
		Kind.PROPELLER:
			_build_propeller(width)
	if DisplayServer.get_name() != "headless":
		_sound = AudioStreamPlayer3D.new()
		_sound.bus = &"SFX"
		add_child(_sound)


## The hole result (strokes − par) of this golfer: a birdie or better sinks the green's ball, a bogey
## or worse sets the goose off.
func react(result: int) -> void:
	if kind == Kind.GREEN and result <= -1:
		_sunk = 0.0
	elif kind == Kind.GOOSE and result >= 1:
		_honk = 0.0
		_play("honk")


## A whiff: the propeller sputters to a stop.
func whiffed() -> void:
	if kind == Kind.PROPELLER:
		_sputter = 0.0
		_sputter_from = _spin


func _process(delta: float) -> void:
	_t += delta
	match kind:
		Kind.GREEN:
			_roll_green(delta)
		Kind.GOOSE:
			_animate_goose(delta)
		Kind.PROPELLER:
			_animate_propeller(delta)


# --- Hat Green ------------------------------------------------------------------------------------

func _build_green(width: float) -> void:
	var r := width * P.green_radius
	_radius = r
	_piece(LowPoly.cylinder(r, r * 1.02, r * 0.14, 14), Color(0.38, 0.66, 0.32), Vector3(0, r * 0.07, 0))
	_piece(LowPoly.cylinder(r * 1.03, r * 1.05, r * 0.06, 14), Color(0.3, 0.52, 0.26), Vector3(0, r * 0.02, 0)) # the fringe
	_cup = Vector2(r * 0.45, -r * 0.3)
	_piece(LowPoly.cylinder(r * 0.11, r * 0.11, r * 0.02, 10), Color(0.1, 0.1, 0.1), Vector3(_cup.x, r * 0.145, _cup.y))
	_piece(LowPoly.cylinder(r * 0.012, r * 0.012, r * 1.1, 4), Color(0.95, 0.95, 0.92), Vector3(_cup.x, r * 0.69, _cup.y))
	var flag := _piece(LowPoly.prism(3, r * 0.3, r * 0.3, r * 0.01), Color(0.86, 0.22, 0.2), Vector3(_cup.x + r * 0.11, r * 1.1, _cup.y), Vector3(PI * 0.5, 0, 0))
	flag.scale = Vector3(1.0, 1.0, 0.6)
	_ball = Node3D.new()
	add_child(_ball)
	var view := LowPoly.part(_ball, LowPoly.sphere(r * P.green_ball, 8, 5), Color(0.98, 0.98, 0.96), Vector3.ZERO)
	view.material_override = LowPoly.shared_material()
	_ball.position = Vector3(-r * 0.3, r * (0.14 + P.green_ball), r * 0.2)
	_roll = Vector2(-r * 0.3, r * 0.2)


## The ball rolls on the disc: pushed opposite the head's acceleration (inertia) and down its tilt,
## rolling friction, kept on the disc by its rim. Once sunk it drops into the cup and stays a while.
func _roll_green(delta: float) -> void:
	if delta <= 0.0:
		return
	var radius := _radius
	var lift := radius * (0.14 + P.green_ball)
	if _sunk >= 0.0:
		_sunk += delta
		var sink := clampf(_sunk / 0.25, 0.0, 1.0)
		_roll = _roll.lerp(_cup, minf(1.0, delta * 12.0))
		_ball.position = Vector3(_roll.x, lift - sink * radius * 0.2, _roll.y)
		if _sunk > P.green_sunk_time: # back on the green after a while
			_sunk = -1.0
			_roll = -_cup * 0.6
			_roll_v = Vector2.ZERO
		return
	var at := global_position
	var v := (at - _last) / delta
	var a := (v - _last_v) / delta if _last != Vector3.ZERO else Vector3.ZERO
	_last = at
	_last_v = v
	var down := global_basis.inverse() * (Vector3.DOWN * 9.8 - a.limit_length(P.green_accel_max)) # felt by the ball, in the disc's frame
	_roll_v += Vector2(down.x, down.z) * P.green_gain * delta
	_roll_v *= exp(-P.green_friction * delta)
	_roll += _roll_v * delta
	var edge := radius * 0.9
	if _roll.length() > edge: # off the rim: back in, the outward part bounced back
		var n := _roll.normalized()
		_roll = n * edge
		_roll_v -= n * maxf(0.0, _roll_v.dot(n)) * 1.6
	_ball.position = Vector3(_roll.x, lift, _roll.y)


# --- Course Goose ---------------------------------------------------------------------------------

func _build_goose(width: float) -> void:
	var s := width * P.goose_size
	var white := Color(0.96, 0.95, 0.92)
	var grey := Color(0.82, 0.82, 0.8)
	var orange := Color(0.96, 0.56, 0.16)
	# A straw nest hugging the crown of the head (it sits on it and covers the top), the goose in it
	var nest := width * 0.56
	var straw := Color(0.78, 0.64, 0.4)
	_piece(LowPoly.cylinder(nest * 1.06, nest * 0.92, width * 0.17, 10), straw, Vector3(0, width * 0.012, 0))
	for k in 9: # twigs round the rim
		var a := TAU * k / 9.0
		_piece(LowPoly.box(Vector3(nest * 0.7, width * 0.025, width * 0.025)), straw.darkened(0.15 + 0.1 * (k % 2)),
			Vector3(cos(a), 0.0, sin(a)) * nest * 0.95 + Vector3(0, width * 0.09, 0), Vector3(0, -a + PI * 0.5, 0.15 * (k % 3 - 1)))
	var body := _piece(LowPoly.sphere(s * 0.5, 9, 5), white, Vector3(0, s * 0.32, s * 0.08))
	body.scale = Vector3(0.9, 0.7, 1.15)
	for side in [-1.0, 1.0]: # folded wings
		var wing := _piece(LowPoly.sphere(s * 0.34, 7, 4), grey, Vector3(side * s * 0.36, s * 0.38, s * 0.16), Vector3(0.2, 0, side * 0.25))
		wing.scale = Vector3(0.35, 0.7, 1.2)
		var foot := _piece(LowPoly.box(Vector3(s * 0.14, s * 0.03, s * 0.18)), orange, Vector3(side * s * 0.18, s * 0.015, -s * 0.12)) # tucked feet peeking out
		foot.rotation.y = side * 0.2
	_piece(LowPoly.cylinder(0.0, s * 0.18, s * 0.24, 5), grey, Vector3(0, s * 0.48, s * 0.62), Vector3(-1.9, 0, 0)) # the tail
	_neck = Node3D.new()
	_neck.position = Vector3(0, s * 0.5, -s * 0.36)
	add_child(_neck)
	for k in 3: # a neck in short segments, leaning back up
		LowPoly.part(_neck, LowPoly.cylinder(s * 0.1, s * 0.12, s * 0.2, 6), white, Vector3(0, s * (0.08 + 0.17 * k), s * 0.03 * k), Vector3(0.18, 0, 0)).material_override = LowPoly.shared_material()
	_head = Node3D.new()
	_head.position = Vector3(0, s * 0.6, s * 0.08)
	_neck.add_child(_head)
	var skull := LowPoly.part(_head, LowPoly.sphere(s * 0.16, 8, 4), white, Vector3.ZERO)
	skull.scale = Vector3(0.95, 0.9, 1.15)
	skull.material_override = LowPoly.shared_material()
	LowPoly.part(_head, LowPoly.box(Vector3(s * 0.1, s * 0.05, s * 0.2)), orange, Vector3(0, s * 0.01, -s * 0.22)).material_override = LowPoly.shared_material()
	_jaw = Node3D.new()
	_jaw.position = Vector3(0, -s * 0.02, -s * 0.13)
	_head.add_child(_jaw)
	LowPoly.part(_jaw, LowPoly.box(Vector3(s * 0.09, s * 0.03, s * 0.17)), orange.darkened(0.1), Vector3(0, -s * 0.01, -s * 0.08)).material_override = LowPoly.shared_material()
	for side in [-1.0, 1.0]:
		var eye := Node3D.new()
		eye.position = Vector3(side * s * 0.13, s * 0.05, -s * 0.07)
		_head.add_child(eye)
		LowPoly.part(eye, LowPoly.sphere(s * 0.04, 6, 3), Color(0.08, 0.08, 0.1), Vector3.ZERO).material_override = LowPoly.shared_material()
		_eyes.append(eye)


## Now and then it turns its head to look somewhere else, and blinks; on a honk its neck stretches up
## and forward, beak wide.
func _animate_goose(delta: float) -> void:
	if _t > _next_look:
		var h := Procgen.mix(int(_t * 1000.0) ^ get_instance_id())
		_look_to = (float(h % 1000) / 1000.0 - 0.5) * 2.0 * P.goose_turn
		_next_look = _t + P.goose_look_every * (0.6 + float((h >> 10) % 1000) / 1000.0 * 0.8)
	_look = lerpf(_look, _look_to, 1.0 - exp(-6.0 * delta))
	_head.rotation.y = _look
	_neck.rotation.y = _look * 0.4
	var blink := 1.0
	if _t > _next_blink:
		var into := _t - _next_blink
		blink = absf(into / P.goose_blink - 1.0) if into < 2.0 * P.goose_blink else 1.0
		if into >= 2.0 * P.goose_blink:
			_next_blink = _t + P.goose_blink_every * (0.7 + 0.6 * float(Procgen.mix(int(_t * 977.0)) % 1000) / 1000.0)
	for eye in _eyes:
		eye.scale = Vector3(1.0, maxf(blink, 0.1), 1.0)
	var open := 0.0
	var stretch := 0.0
	if _honk >= 0.0:
		_honk += delta
		var f := _honk / P.goose_honk_time
		if f >= 1.0:
			_honk = -1.0
		else:
			open = sin(PI * f) * (0.6 + 0.4 * absf(sin(f * 14.0))) # two blasts
			stretch = sin(PI * f)
	_jaw.rotation.x = open * 0.7
	_neck.rotation.x = -stretch * 0.5
	_head.rotation.x = stretch * 0.35


# --- Power Propeller ------------------------------------------------------------------------------

func _build_propeller(width: float) -> void:
	var r := width * 0.5 * P.beanie_fit
	var colors := [Color(0.86, 0.22, 0.2), Color(0.98, 0.8, 0.22), Color(0.2, 0.45, 0.85), Color(0.3, 0.7, 0.35)]
	var dome := LowPoly.sphere(r, 12, 5)
	dome.is_hemisphere = true
	var cap := _piece(dome, colors[0], Vector3(0, -r * 0.35, 0))
	cap.scale = Vector3(1.0, 0.8, 0.95)
	var arrays: Array = cap.get_meta("flat")
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var tones: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for k in range(0, verts.size(), 3): # four coloured panels round the crown
		var c := verts[k] + verts[k + 1] + verts[k + 2]
		var panel := posmod(int(floor((atan2(c.x, c.z) / TAU + 0.5) * 4.0)), 4)
		for j in 3:
			tones[k + j] = colors[panel]
	arrays[Mesh.ARRAY_COLOR] = tones
	var panels := ArrayMesh.new()
	panels.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	(cap as MeshInstance3D).mesh = panels
	_piece(LowPoly.cylinder(r * 1.0, r * 1.02, r * 0.12, 12), Color(0.9, 0.9, 0.88), Vector3(0, -r * 0.33, 0)) # the band
	# The crown's top is at −0.35 r + 0.8 × 2 r (a hemisphere mesh is a full radius tall each side): the
	# stalk stands on it and the propeller turns clear above
	var crown := r * 1.25
	_piece(LowPoly.cylinder(r * 0.04, r * 0.05, r * 0.32, 5), Color(0.9, 0.9, 0.88), Vector3(0, crown + r * 0.12, 0)) # the stalk
	_prop = Node3D.new()
	_prop.position = Vector3(0, crown + r * 0.3, 0)
	add_child(_prop)
	LowPoly.part(_prop, LowPoly.sphere(r * 0.08, 6, 3), Color(0.98, 0.8, 0.22), Vector3.ZERO).material_override = LowPoly.shared_material()
	for side in [-1.0, 1.0]:
		var blade := LowPoly.part(_prop, LowPoly.box(Vector3(r * 0.75, r * 0.02, r * 0.16)), colors[0] if side < 0.0 else colors[2],
			Vector3(side * r * 0.42, 0, 0), Vector3(side * 0.25, 0, 0))
		blade.material_override = LowPoly.shared_material()


## Spin follows the swing's power (eased); after a whiff it sputters — stuttering, slowing — to a stop,
## and stays stopped until the next swing builds power again.
func _animate_propeller(delta: float) -> void:
	var want := lerpf(P.propeller_idle, P.propeller_max, clampf(power, 0.0, 1.0))
	if _sputter >= 0.0:
		_sputter += delta
		var f := clampf(_sputter / P.sputter_time, 0.0, 1.0)
		want = _sputter_from * (1.0 - f) * (0.55 + 0.45 * absf(sin(_sputter * 23.0)))
		if f >= 1.0:
			want = 0.0
			if power > 0.05:
				_sputter = -1.0
		_spin = want
	else:
		_spin = lerpf(_spin, want, 1.0 - exp(-P.propeller_ease * delta))
	_prop.rotate_y(_spin * delta)


func _piece(mesh: Mesh, color: Color, at: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var view := LowPoly.part(self, mesh, color, at, rot)
	view.material_override = LowPoly.shared_material()
	view.set_meta("flat", (view.mesh as ArrayMesh).surface_get_arrays(0))
	return view


func _play(which: String) -> void:
	if _sound == null:
		return
	if not _sounds.has(which):
		_sounds[which] = PlaceholderSounds.honk() # (the only one so far)
	_sound.stream = _sounds[which]
	_sound.play()
