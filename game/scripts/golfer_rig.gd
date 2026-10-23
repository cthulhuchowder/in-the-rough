class_name GolferRig
extends Node3D
## Low-poly golfer: flat-shaded rigid parts on a joint hierarchy (pelvis, torso, head, upper and
## lower arms, hands, upper and lower legs) plus the club. One material per color slot (skin,
## shirt, outerwear, pants, hat), so a look or skin recolors it without new meshes. Poses: the
## swing, driven by the swing angle and pitch; a two-pose walk loop; idle, slouched. Faces −Z with
## the target at −X (a right-handed golfer, as Swing). Arms and legs reach with a two-bone solver.

const SLOTS := ["skin", "shirt", "outerwear", "pants", "hat", "features", "eye_white", "club", "shoes", "sole", "belt", "band", "toy"]
const NOVELTY: NoveltyParams = preload("res://data/novelty.tres")
const CLUB_HEAD_ROUGHNESS := 0.3
const CLUB_SHAFT_ROUGHNESS := 0.2
const CLUB_METALLIC := 0.9

var params: CharacterParams
var club: ClubData ## the club in hand (its model, length and loft); set_club() to change
var look: CharacterLook:
	set(value):
		look = value
		_apply_look()
## Only the club shows (the camera is the player's eye while shooting).
var first_person := false:
	set(value):
		if value == first_person:
			return
		first_person = value
		for view in _body_parts:
			view.visible = not value
		_refresh_styles()
		_build_club() # first person has its own club length

var _mats := {}
var _body_parts: Array[MeshInstance3D] = []
var _hat_parts: Array[MeshInstance3D] = [] # the hat's pieces (rebuilt with its style)
var _hat_style := -1
var hat_toy: HatToy ## the reactive hat (hat_style 3–5), or null: feed its power, tell it the events
var _club_style := -1
var _style_parts := {} # _build_styles()' pieces by style key
var _slot_parts := {} # slot → its parts
var _shoe_parts: Array[MeshInstance3D] = [] # the standard shoes (hidden under novelty ones)
var _shin_parts: Array[MeshInstance3D] = [] # the trousers below the knee (socks under knickerbockers)
var _flop := -1.0 # s since a novelty head's impact (−1: still)
var _flop_power := 0.0
var _flop_beak := false
var _feet_sound: AudioStreamPlayer3D
var _joints: Array[Node3D] = []
var _pelvis: Node3D
var _torso: Node3D
var _head: Node3D
var _arms := {} ## "l"/"r" → [upper, lower]
var _legs := {} ## "l"/"r" → [upper, lower]
var _club: Node3D
var _club_model: Node3D
var _walk_phase := 0.0
# Address geometry in rig space, fixed until the next address().
var _chest := Vector3.ZERO
var _hands := Vector3.ZERO
var _club_dir := Vector3.DOWN
var _club_len := 1.0
var _plane_axis := Vector3.BACK
var _fp_reach := 0.0 # first person: hands-to-shaft-end length (m), the address hands to the ball; 0 = from the club
var fp_axis0 := Vector3.ZERO ## first person: the swing plane's axis at address (last pose_fp), for the follow-through
var fp_head_basis := Basis() ## first person: the head's basis in the club, squared at address (identity: from the lie)
var _end_offset := Vector3.ZERO # shaft end from the face centre at address, rig space
var _hip_back := 0.0 # m the hips sit back from the feet at address, so the arms hang near straight
var _shadow: MeshInstance3D
var _ground_y := 0.0 # world height of the ground under the ball at address
var _ball := Vector3.ZERO # world ball centre at address
var _face_behind_ball := true # the drawn face was behind the ball (target side away) last pose


func _init(character: CharacterParams, character_look: CharacterLook) -> void:
	params = character
	for slot in SLOTS:
		_mats[slot] = LowPoly.material()
	# Clubs are metal: vertex colors still tint them; the grip (features) stays matte
	_mats.club = _metal(CLUB_HEAD_ROUGHNESS)
	_mats.club_shaft = _metal(CLUB_SHAFT_ROUGHNESS)
	look = character_look
	_build()


## Stand at `feet` facing the ball, target along `aim`; the club soles at `ball`. World space.
func address(feet: Vector3, aim: Vector3, ball: Vector3) -> void:
	var p := params
	_ball = ball
	var side := (-aim).cross(Vector3.UP)
	transform = Transform3D(Basis(-aim, Vector3.UP, side), feet)
	var b := basis.inverse() * (ball - feet)
	var hip := _hip_height() - p.knee_flex
	_chest = Vector3(0, hip, 0) + Vector3(0, p.torso_length - 0.05, 0).rotated(Vector3.RIGHT, -p.address_lean)
	_club_len = ClubModel.hands_to_sole(club, length_scale())
	# The face centre sits just behind the ball (ball off the middle of the face); the shaft rises
	# toward the golfer at the club's lie, so the head soles flat with the face square to the aim.
	var lie := deg_to_rad(club.lie_deg)
	var toward := -signf(b.z) if b.z != 0.0 else 1.0 # from the ball toward the golfer
	_end_offset = Vector3(ClubModel.BALL_RADIUS, 0.0, ClubModel.face_centre(club, girth_scale(), p.club_head_scale).x * toward)
	var end := b + _end_offset
	_hands = end + Vector3(0.0, sin(lie), cos(lie) * toward) * _club_len
	_ground_y = ball.y - ClubModel.BALL_RADIUS
	_club_dir = (end - _hands).normalized()
	_club_model.get_node("Head").rotation.z = lie - PI * 0.5 # toe away from the golfer, sole flat
	_plane_axis = _club_dir.cross(Vector3.LEFT).normalized() # dir(hands→ball) × aim, as Swing
	# Sit the hips back until an arm reaches its hand on the grip with only address_elbow_bend
	# left in the elbow (the other arm bends a little more), capped so the legs still reach the feet.
	var a := p.arm_upper
	var r := p.arm_lower + p.hand_size.y * 0.35
	var reach := sqrt(a * a + r * r + 2.0 * a * r * cos(p.address_elbow_bend))
	var lean := Basis.from_euler(Vector3(-p.address_lean, 0, p.side_bend))
	_hip_back = p.hip_back_max
	for s in [-1.0, 1.0]: # lead hand on the grip, trail hand grip_gap below it
		var d: Vector3 = _hands + _club_dir * (p.grip_gap if s > 0.0 else 0.0) \
			- Vector3(0, hip, 0) - lean * Vector3(s * p.shoulder_width, p.torso_length - 0.05, -p.shoulder_roll)
		_hip_back = minf(_hip_back, d.z + sqrt(maxf(reach * reach - d.x * d.x - d.y * d.y, 0.0)))
	_hip_back = maxf(_hip_back, 0.0)
	_chest.z += _hip_back


## Swing pose: hands on the arc by the swing angle, club turning wrist_ratio times as far,
## shoulders and hips turning, pitch tilting the plane. Matches Swing's sign: angle < 0 is the
## backswing. Call after address(), while in the tree. With `contact` > 0 the club end is pulled
## that far (0..1) onto `head_target` (world), moving the grip, so the visible head meets the
## hitbox at impact; the arms follow through the reach solver. With `hold_at_ball` a head that
## would overlap the address ball is held with its face on the ball's surface (a slow swing).
func pose_swing(angle: float, pitch: float, head_target := Vector3.ZERO, contact := 0.0, hold_at_ball := false) -> void:
	var p := params
	_rest()
	_club.visible = true
	_pelvis.position.y -= p.knee_flex
	_pelvis.position.z += _hip_back
	var hips := clampf(angle * p.hip_turn, -p.turn_limit, p.turn_limit)
	_pelvis.rotation.y = hips
	_torso.rotation = Vector3(-p.address_lean, clampf(angle * p.shoulder_turn, -p.turn_limit, p.turn_limit) - hips, p.side_bend)
	_head.look_at(_ball) # eyes stay on the ball
	var hands := _chest + (_hands - _chest).rotated(_plane_axis, angle).rotated(Vector3.RIGHT, pitch)
	var dir := _club_dir.rotated(_plane_axis, angle * p.wrist_ratio).rotated(Vector3.RIGHT, pitch)
	var grip := to_global(hands)
	var down := to_global(hands + dir) - grip
	var face := basis * Vector3.LEFT.rotated(_plane_axis, angle * p.wrist_ratio).rotated(Vector3.RIGHT, pitch)
	# The shaft end sits off the face centre; that offset turns with the club.
	var offset := basis * _end_offset.rotated(_plane_axis, angle * p.wrist_ratio).rotated(Vector3.RIGHT, pitch)
	if contact > 0.0: # put the face centre on head_target
		grip = grip.lerp(head_target + offset - down * _club_len, contact)
	# Hands stay stacked on the grip all the way round: where the arc would take the grip out of
	# an arm's reach, the grip (and club) comes back toward that shoulder instead.
	var full := p.arm_upper + p.arm_lower + p.hand_size.y * 0.35 - 0.001
	for i in 2:
		for arm in [[_arms.l, 0.0], [_arms.r, p.grip_gap]]:
			var d: Vector3 = grip + down * arm[1] - (arm[0][0] as Node3D).global_position
			if d.length() > full:
				grip -= d.normalized() * (d.length() - full)
	# offset is the shaft end from the face centre plus r back along the face (address: just behind the ball)
	var face_c := grip + down * _club_len - offset - face * ClubModel.BALL_RADIUS
	var n := (face - down * face.dot(down)).normalized() # the face looks along n, as _place_club()
	grip += _hold_face(face_c, n, hold_at_ball) - face_c
	var pole := p.elbow_pole
	_reach(_arms.l, grip, basis * pole)
	_reach(_arms.r, grip + down * p.grip_gap, basis * Vector3(-pole.x, pole.y, pole.z))
	_place_club(grip, down, face)
	_plant_feet()
	_place_shadow()


## Two-pose walk loop (left leg forward ↔ right leg forward), arms counter-swinging.
## `pace` is speed / walk speed; 0 settles to standing.
func pose_walk(pace: float, delta: float) -> void:
	var p := params
	_rest()
	_slouch()
	_club.visible = false
	pace = clampf(pace, 0.0, 1.5)
	var before := _walk_phase
	_walk_phase = fmod(_walk_phase + delta * p.stride_hz * TAU * pace, TAU)
	if floori(before / PI) != floori(_walk_phase / PI) and pace > 0.1: # a foot comes down
		_stepped()
	var s := sin(_walk_phase) * minf(pace * 2.0, 1.0)
	_legs.l[0].rotation.x = s * p.leg_swing
	_legs.r[0].rotation.x = -s * p.leg_swing
	_legs.l[1].rotation.x = -maxf(0.0, -s) * p.knee_bend
	_legs.r[1].rotation.x = -maxf(0.0, s) * p.knee_bend
	_arms.l[0].rotation = Vector3(-s * p.arm_swing, 0, -0.08)
	_arms.r[0].rotation = Vector3(s * p.arm_swing, 0, 0.08)
	_pelvis.position.y += absf(cos(_walk_phase)) * p.bob * minf(pace, 1.0)


func pose_idle() -> void:
	var p := params
	_rest()
	_slouch()
	var breath := sin(Time.get_ticks_msec() / 1000.0 * TAU / p.breath_period) # a slow breath: the chest lifts
	_torso.rotation.x -= p.breath_depth * breath
	_head.rotation.x += p.breath_depth * 0.8 * breath
	_club.visible = false
	_arms.l[0].rotation.z = -0.08
	_arms.r[0].rotation.z = 0.08
	for side in ["l", "r"]:
		_legs[side][0].rotation.x = p.knee_bend_idle
		_legs[side][1].rotation.x = -p.knee_bend_idle * 2.0


## Standing, waving the right hand above the shoulder (the menu scene): idle, then the arm reaches
## to a point `height` above and `out` beside its shoulder, swaying by `sway` at `rate` Hz.
func pose_wave(t: float, out: float, height: float, sway: float, rate: float) -> void:
	pose_idle()
	var shoulder: Vector3 = _arms.r[0].global_position
	var side := (shoulder - (_arms.l[0].global_position as Vector3)).normalized()
	var up := global_basis.y.normalized()
	var hand := shoulder + side * (out + sway * sin(TAU * rate * t)) + up * height
	_reach(_arms.r, hand, side - up * 0.3)


func _build() -> void:
	var p := params
	_pelvis = _joint(self, Vector3(0, _hip_height(), 0))
	var waist := p.torso_waist
	_part(_pelvis, _rounded(8, Vector3(p.torso_top.x * waist * 1.05, 0.14, p.torso_top.y * waist * 1.05)), "pants", Vector3.ZERO, true)
	_torso = _joint(_pelvis, Vector3.ZERO)
	# Tall narrow soft-edged block, tapering to the waist, under an open-fronted vest.
	_part(_torso, _rounded(8, Vector3(p.torso_top.x * waist, p.torso_length, p.torso_top.y * waist), 1.0 / waist), "shirt",
		Vector3(0, p.torso_length * 0.5, 0), true)
	var vest := p.vest_size * Vector3(waist * 1.08, 1.0, waist * 1.08)
	_part(_torso, _rounded(8, vest, 1.0 / (waist * 1.08), true, false), "outerwear",
		Vector3(0, p.torso_length - p.vest_size.y * 0.5, 0), true)
	# Outfit pieces: a bevelled collar and a placket down the shirt front (darker shirt), a belt with a buckle
	var chest := Vector2(p.torso_top.x * waist, p.torso_top.y * waist)
	_part(_torso, _rounded(8, Vector3(chest.x * 0.62, 0.045, chest.y * 0.8), 0.9), "shirt", Vector3(0, p.torso_length - 0.01, 0), true,
		Vector3.ZERO, Color(0.8, 0.8, 0.8))
	_part(_torso, _rounded(4, Vector3(0.034, p.torso_length * 0.55, 0.012)), "shirt", Vector3(0, p.torso_length * 0.62, -chest.y * 0.5 - 0.004), true,
		Vector3.ZERO, Color(0.86, 0.86, 0.86))
	_part(_pelvis, _rounded(8, Vector3(chest.x * 1.1, 0.045, chest.y * 1.1)), "belt", Vector3(0, 0.06, 0), true)
	_part(_pelvis, _rounded(4, Vector3(0.05, 0.036, 0.014)), "club", Vector3(0, 0.06, -chest.y * 0.55 - 0.004), true)
	# Head: a tall faceted block sitting straight on the shoulders, flat face forward.
	_head = _joint(_torso, Vector3(0, p.torso_length - 0.02, -p.shoulder_roll * 0.5))
	var h := p.head_size.y
	var face := -p.head_size.z * 0.5
	_part(_head, _rounded(8, p.head_size, 0.94), "skin", Vector3(0, h * 0.5, 0), true)
	_part(_head, _rounded(4, p.nose_size), "skin", Vector3(0, h * 0.45, face - p.nose_size.z * 0.3), true,
		Vector3(p.nose_tilt, 0, 0))
	# Big eyes set in shallow sockets; left and right differ in size, pupil size and gaze.
	for side in ["l", "r"]:
		var left: bool = side == "l"
		var radius := p.eye_radius * (p.eye_scale.x if left else p.eye_scale.y)
		var eye := Vector3(-p.eye_spacing if left else p.eye_spacing, h * p.eye_height,
			face - radius * (2.0 * p.eye_bulge - 1.0))
		_part(_head, LowPoly.sphere(radius, 10, 7), "eye_white", eye, true)
		var look_dir := p.pupil_look_left if left else p.pupil_look_right
		var gaze := Vector3(look_dir.x, look_dir.y, -1.0).normalized()
		var pupil := p.pupil_radius * (p.pupil_scale.x if left else p.pupil_scale.y)
		_part(_head, LowPoly.sphere(pupil, 7, 5), "features", eye + gaze * (radius - pupil * 0.35), true)
		# Small rounded ear nub on each side at eye height, just proud of the tapered head side.
		var side_x := p.head_size.x * 0.5 * lerpf(1.0, 0.94, p.eye_height)
		_part(_head, _rounded(6, p.ear_size), "skin", Vector3((-1.0 if left else 1.0) * (side_x + p.ear_size.x * 0.3),
			h * p.eye_height, p.ear_back), true, Vector3(0, 0, PI * 0.5))
	_part(_head, _rounded(4, p.mouth_size), "features", Vector3(0, h * p.mouth_height, face + p.mouth_size.z * 0.2), true)
	_build_hat()
	for side in ["l", "r"]:
		var s := -1.0 if side == "l" else 1.0 # left is the target side (−X)
		var r := p.limb_radius
		var upper := _joint(_torso, Vector3(s * p.shoulder_width, p.torso_length - 0.05, -p.shoulder_roll))
		_part(upper, _rounded(6, Vector3(r * 2.5, p.arm_upper, r * 2.5), 1.1 / 1.25), "shirt", Vector3(0, -p.arm_upper * 0.5, 0), true)
		_part(upper, _rounded(6, Vector3(r * 2.8, 0.032, r * 2.8)), "shirt", Vector3(0, -p.arm_upper * 0.93, 0), true,
			Vector3.ZERO, Color(0.8, 0.8, 0.8)) # the sleeve hem
		var lower := _joint(upper, Vector3(0, -p.arm_upper, 0))
		lower.set_meta("rest_x", p.elbow_bend) # the soft bend of a relaxed arm
		_part(lower, _rounded(6, Vector3(r * 2.0, p.arm_lower, r * 2.0), 0.85), "skin", Vector3(0, -p.arm_lower * 0.5, 0), true)
		_part(lower, _rounded(6, Vector3(r * 2.2, 0.03, r * 2.2)), "shirt", Vector3(0, -p.arm_lower * 0.92, 0), true,
			Vector3.ZERO, Color(0.8, 0.8, 0.8)) # a cuff at the wrist
		var hand := p.hand_size
		_part(lower, _rounded(4, Vector3(hand.x, hand.y * 0.7, hand.z)), "skin", Vector3(0, -p.arm_lower - hand.y * 0.25, 0), true)
		for k in 3: # the mitt's fingers: three bevelled blocks
			_part(lower, _rounded(4, Vector3(hand.x * 0.3, hand.y * 0.42, hand.z * 0.82)), "skin",
				Vector3((k - 1) * hand.x * 0.33, -p.arm_lower - hand.y * 0.72, hand.z * 0.04), true, Vector3.ZERO, Color(0.95, 0.95, 0.95))
		_arms[side] = [upper, lower]
		var thigh := _joint(_pelvis, Vector3(s * p.hip_width, 0, 0))
		_part(thigh, _rounded(6, Vector3(r * 2.7, p.leg_upper, r * 2.7), 1.2 / 1.35), "pants", Vector3(0, -p.leg_upper * 0.5, 0), true)
		_part(thigh, _rounded(4, Vector3(0.01, p.leg_upper * 0.9, r * 1.3)), "pants", Vector3(s * r * 1.32, -p.leg_upper * 0.5, 0), true,
			Vector3.ZERO, Color(0.84, 0.84, 0.84)) # an outer-leg panel
		var shin := _joint(thigh, Vector3(0, -p.leg_upper, 0))
		_shin_parts.append(_part(shin, _rounded(6, Vector3(r * 2.4, p.leg_lower, r * 2.4), 1.0 / 1.2), "pants", Vector3(0, -p.leg_lower * 0.5, 0), true))
		_shin_parts.append(_part(shin, _rounded(4, Vector3(0.01, p.leg_lower * 0.9, r * 1.15)), "pants", Vector3(s * r * 1.16, -p.leg_lower * 0.5, 0), true,
			Vector3.ZERO, Color(0.84, 0.84, 0.84)))
		var foot := _joint(shin, Vector3(0, -p.leg_lower, 0)) # ankle: _plant_feet() sets the foot flat
		_shoe_parts.append(_part(foot, _rounded(4, p.foot_size), "shoes", Vector3(0, -p.foot_size.y * 0.5, -p.foot_size.z * 0.25), true))
		_shoe_parts.append(_part(foot, _rounded(4, Vector3(p.foot_size.x * 1.07, p.foot_size.y * 0.28, p.foot_size.z * 1.04)), "sole",
			Vector3(0, -p.foot_size.y * 0.86, -p.foot_size.z * 0.25), true)) # the sole
		_legs[side] = [thigh, shin, foot]
	_build_styles()
	_refresh_styles()
	_club = _joint(self, Vector3.ZERO)
	set_club(Clubs.ALL[0])
	pose_idle()


## The hat in the look's style, hugging the crown, with its band: 0 a rounded cap with a short visor,
## 1 a bucket hat with a round drooping brim, 2 a low flat cap with its peak. Rebuilt when it changes.
func _build_hat() -> void:
	for part in _hat_parts:
		_body_parts.erase(part)
		part.queue_free()
	_hat_parts.clear()
	if hat_toy:
		hat_toy.queue_free()
		hat_toy = null
	_hat_style = look.hat_style if look else 0
	var p := params
	var h := p.head_size.y
	if _hat_style >= HatToy.Kind.GREEN: # a reactive hat sits on the crown instead
		hat_toy = HatToy.new(_hat_style, Vector3(0, h - p.cap_drop * 0.25, 0), p.head_size.x)
		hat_toy.visible = not first_person
		_head.add_child(hat_toy)
		return
	var cap := Vector3(p.head_size.x * p.cap_fit, p.cap_height, p.head_size.z * p.cap_fit)
	var cap_y := h - p.cap_drop + p.cap_height * 0.5
	match _hat_style:
		1: # bucket hat
			_hat_parts.append(_part(_head, LowPoly.rounded_prism(10, cap * Vector3(1.0, 1.05, 1.0), p.cap_height * 0.2, 1, 0.82), "hat",
				Vector3(0, cap_y + p.cap_height * 0.04, 0), true))
			_hat_parts.append(_part(_head, LowPoly.cylinder(cap.x * 0.62, cap.x * 0.82, p.cap_height * 0.12, 12), "hat",
				Vector3(0, cap_y - p.cap_height * 0.5, 0), true, Vector3.ZERO, Color(0.9, 0.9, 0.9)))
		2: # flat cap
			_hat_parts.append(_part(_head, LowPoly.rounded_prism(8, cap * Vector3(1.04, 0.55, 1.1), p.cap_height * 0.12, 1, 0.94), "hat",
				Vector3(0, cap_y + p.cap_height * 0.05, -cap.z * 0.04), true, Vector3(-0.08, 0, 0))) # (its top above the head's: it covers it)
			_hat_parts.append(_part(_head, _rounded(4, p.visor_size * Vector3(1.0, 0.7, 0.8)), "hat", Vector3(0, cap_y - p.cap_height * 0.17,
				-cap.z * 0.5 - p.visor_size.z * 0.2), true, Vector3(-0.22, 0, 0), Color(0.9, 0.9, 0.9)))
		_: # the cap
			_hat_parts.append(_part(_head, LowPoly.rounded_prism(8, cap, p.cap_height * p.cap_round, p.bevel_segments + 1, 0.9), "hat",
				Vector3(0, cap_y, 0), true))
			_hat_parts.append(_part(_head, _rounded(4, p.visor_size), "hat", Vector3(0, cap_y - p.cap_height * 0.4,
				-cap.z * 0.5 - p.visor_size.z * 0.35), true, Vector3(-0.12, 0, 0)))
	var band_y := cap_y - p.cap_height * (0.33 if _hat_style != 2 else 0.16)
	_hat_parts.append(_part(_head, LowPoly.rounded_prism(8, Vector3(cap.x * 1.02, p.cap_height * 0.2, cap.z * 1.02), p.cap_height * 0.05, 1), "band",
		Vector3(0, band_y, 0), true)) # the hat band


func _apply_look() -> void:
	if look == null:
		return
	if _head and look.hat_style != _hat_style:
		_build_hat()
	if _club_model and look.club_style != _club_style:
		_build_club()
	_refresh_styles()
	_mats.toy.albedo_color = Color.WHITE
	_mats.skin.albedo_color = look.skin
	_mats.shirt.albedo_color = look.shirt
	_mats.outerwear.albedo_color = look.outerwear
	_mats.pants.albedo_color = look.pants
	_mats.hat.albedo_color = look.hat
	_mats.features.albedo_color = params.features
	_mats.eye_white.albedo_color = params.eye_white
	_mats.club.albedo_color = look.club
	_mats.club_shaft.albedo_color = look.club
	_mats.shoes.albedo_color = look.shoes
	_mats.sole.albedo_color = Color(0.93, 0.91, 0.86)
	_mats.belt.albedo_color = Color(0.25, 0.2, 0.16)
	_mats.band.albedo_color = look.hat.darkened(0.45)


## Every edge chamfered by `bevel` of the part's smallest dimension, rounded in a few facets.
func _rounded(sides: int, size: Vector3, top_scale := 1.0, open_front := false, caps := true) -> ArrayMesh:
	var smallest := minf(size.x, minf(size.y, size.z))
	return LowPoly.rounded_prism(sides, size, smallest * params.bevel, params.bevel_segments, top_scale, open_front, caps)


func _hip_height() -> float:
	return params.leg_upper + params.leg_lower + params.foot_size.y


## Standing posture: upper body tipped forward, head tipped back to keep the face level.
func _slouch() -> void:
	_torso.rotation.x = -params.slouch
	_head.rotation.x = params.slouch * 0.8


func _joint(parent: Node3D, at: Vector3) -> Node3D:
	var joint := Node3D.new()
	joint.position = at
	joint.set_meta("rest", at)
	parent.add_child(joint)
	_joints.append(joint)
	return joint


## `shade`: the part's vertex colour, times its slot's colour (two-tone pieces of one garment).
func _part(parent: Node3D, mesh: Mesh, slot: String, at: Vector3, body: bool, rot := Vector3.ZERO, shade := Color.WHITE) -> MeshInstance3D:
	var view := LowPoly.part(parent, mesh, shade, at, rot)
	view.material_override = _mats[slot]
	_slot_parts.get_or_add(slot, []).append(view)
	if body:
		_body_parts.append(view)
		view.visible = not first_person
	return view


## Every joint back to its rest transform (elbows keep their soft bend).
func _rest() -> void:
	if _shadow:
		_shadow.visible = false
	for joint in _joints:
		joint.transform = Transform3D(Basis.from_euler(Vector3(joint.get_meta("rest_x", 0.0), 0, 0)), joint.get_meta("rest"))


## First person: the club on the swing arc, one continuous rotation, the same rule at
## every angle. `rel` is the swing angle from address. The address hands (H) are fp_arm_length from
## the `eye` along the eye→ball line tilted by the club's hand_angle about the eye's right; the plane axis is
## dir(H→ball) × the eye's left. Hands: H about the plane axis by `rel`; shaft: dir(H→ball) about it by
## 1.5 × `rel`, the head a club length (|H − ball|) along it, the club's frame turned from its square
## address frame the same way, the face closed about the shaft by clamp(`rel`, 0, π/8); then the whole
## pose about the eye's right through the eye by `pitch` (positive lifts the arc). Then `offset` (world) is
## added. After the hit `axis_now` / `right_now` (non-zero) are the follow-through's yawed plane axis
## and the eye's right; the address hands stay as they were. Call after address().
func pose_fp(rel: float, pitch: float, eye: Vector3, cam_right: Vector3, forward: Vector3, offset: Vector3,
		axis_now := Vector3.ZERO, right_now := Vector3.ZERO) -> void:
	var p := params
	var right := cam_right.normalized()
	var hands0 := eye + (_ball - eye).normalized().rotated(right, -club.hand_angle) * p.fp_arm_length
	# The club's constant address leans, about the ball, before any of the arc: about the aim line
	# (fp_shaft_lean) and about the axis toward the golfer (fp_shaft_forward_lean)
	var aim_axis := Vector3(forward.x, 0.0, forward.z).normalized()
	var toward := aim_axis.cross(Vector3.UP).normalized()
	if (global_position - _ball).dot(toward) < 0.0:
		toward = -toward
	hands0 = _ball + Basis(toward, club.fp_shaft_forward_lean) * Basis(aim_axis, club.fp_shaft_lean) * (hands0 - _ball)
	var d0 := (_ball - hands0).normalized() # the address shaft, hands → head
	_fit_reach(hands0.distance_to(_ball))
	var head: Node3D = _club_model.get_node("Head")
	if fp_head_basis != Basis(): # squared at address (main): face along the target, sole flat, crown up
		head.basis = fp_head_basis
	else:
		head.rotation.z = asin(clampf(-d0.y, -1.0, 1.0)) - PI * 0.5 # sole flat at the address shaft angle, toe away
	fp_axis0 = d0.cross(-right).normalized()
	var axis := axis_now if axis_now != Vector3.ZERO else fp_axis0 # (after the hit: the follow-through's yaw)
	# Pitch turns the whole pose about the eye's right through the eye, the sense that lifts the arc for
	# positive pitch (mouse up) — the hands and the shaft alike, after the plane-axis turn.
	var pitch_right := right_now.normalized() if right_now != Vector3.ZERO else right
	var lift := Basis(pitch_right, pitch if (_ball - eye).rotated(pitch_right, 0.01).y > (_ball - eye).y else -pitch)
	var hands := eye + lift * (hands0 - eye).rotated(axis, rel)
	var spin := lift * Basis(axis, 1.5 * rel) # the shaft's turn from address
	var up0 := -d0
	var n0 := (forward - d0 * forward.dot(d0)).normalized() # face square to the target at address
	var b := spin * Basis(up0.cross(-n0), up0, -n0)
	var shaft := spin * d0
	var close := clampf(rel, 0.0, PI / 8.0)
	var toward_golfer := (global_position - _ball) * Vector3(1, 0, 1)
	if (spin * n0).rotated(shaft, 0.01).dot(toward_golfer) < (spin * n0).dot(toward_golfer):
		close = -close # closing turns the face toward the golfer
	_club.visible = true
	_club.global_transform = Transform3D(Basis(shaft, close) * b, hands + offset)
	_place_shadow()


## First person: the club's hands-to-shaft-end length set to `reach` m (rebuilt when it changes).
func _fit_reach(reach: float) -> void:
	if absf(reach - _fp_reach) < 0.005:
		return
	_fp_reach = reach
	_build_club()


## With `hold`, a face (centre `face_c`, looking along `n`) coming from behind the address ball
## that would reach into it is held on its surface. Tracks which side the face is on even without
## `hold`, so a fast swing that went through isn't pulled back when it slows. World space.
func _hold_face(face_c: Vector3, n: Vector3, hold: bool) -> Vector3:
	var r := ClubModel.BALL_RADIUS
	var s := club.head_size * girth_scale() * params.club_head_scale
	var to_ball := _ball - face_c
	var depth := to_ball.dot(n) # r: face touching the ball from behind
	var over_ball := (to_ball - n * depth).length() < s.x * 0.5 + r
	if hold and _face_behind_ball and over_ball and depth < r:
		face_c -= n * (r - depth)
		depth = r
	_face_behind_ball = depth >= r - 0.001 if over_ball else depth > 0.0
	return face_c


## Club along `down` from the grip, its face (−Z) turned toward `face`. World space.
func _place_club(grip: Vector3, down: Vector3, face: Vector3) -> void:
	_club.global_position = grip
	var y := -down.normalized()
	var z := -(face - y * face.dot(y)).normalized()
	_club.global_basis = Basis(y.cross(z), y, z)


func _plant_feet() -> void:
	var p := params
	for side in ["l", "r"]:
		var s := -1.0 if side == "l" else 1.0
		var ankle := to_global(Vector3(s * p.stance_width, p.foot_size.y, 0))
		var toes := basis * Vector3.FORWARD.rotated(Vector3.UP, -s * p.foot_splay) # facing the ball, turned out
		_reach(_legs[side], ankle, basis * Vector3(0, 0, -1), p.leg_upper, p.leg_lower, toes)
		# Sole flat on the ground under the stance, toes forward, whatever angle the shin takes.
		var up := basis.y.normalized()
		var flat := -(toes - up * toes.dot(up)).normalized()
		(_legs[side][2] as Node3D).global_transform = Transform3D(Basis(up.cross(flat), up, flat), ankle)


## Two-bone reach: upper/lower joints toward `target`, bending toward `pole`. World space.
## With `toward`, each joint's −Z (a foot's toes) turns toward it instead of a fixed world axis.
func _reach(chain: Array, target: Vector3, pole: Vector3, a := -1.0, b := -1.0, toward := Vector3.ZERO) -> void:
	if a < 0.0:
		a = params.arm_upper
		b = params.arm_lower + params.hand_size.y * 0.35
	var upper: Node3D = chain[0]
	var root := upper.global_position
	var to := target - root
	var dist := clampf(to.length(), 0.001, a + b - 0.0005)
	var dir := to.normalized()
	var cos_a := clampf((a * a + dist * dist - b * b) / (2.0 * a * dist), -1.0, 1.0)
	var bend := pole - dir * pole.dot(dir)
	if bend.length() < 0.0001:
		bend = dir.cross(Vector3.RIGHT)
	bend = bend.normalized()
	var elbow := root + dir * a * cos_a + bend * a * sqrt(1.0 - cos_a * cos_a)
	_point(upper, elbow - root, toward)
	_point(chain[1], root + dir * dist - elbow, toward)


## Orient a joint so its −Y (where its part hangs) points along `dir`, and its −Z toward `toward`
## if given (else a fixed world reference). World space.
static func _point(joint: Node3D, dir: Vector3, toward := Vector3.ZERO) -> void:
	var y := -dir.normalized()
	if toward != Vector3.ZERO:
		var z := -(toward - y * toward.dot(y)).normalized()
		joint.global_basis = Basis(y.cross(z), y, z)
		return
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	joint.global_basis = Basis(x, y, x.cross(y))


## Swap the club in hand: builds its model (grip, shaft, hosel, head with loft) from the ClubData.
func set_club(next: ClubData) -> void:
	if next == club:
		return
	club = next
	_build_club()


func _build_club() -> void:
	if club == null:
		return
	if _club_model:
		_club.remove_child(_club_model)
		_club_model.queue_free()
	_club_style = look.club_style if look else 0
	_club_model = ClubModel.build(club, params.bevel, params.bevel_segments, _mats.club, _mats.features, _mats.club_shaft,
		girth_scale(), params.club_head_scale, length_scale(), _club_style)
	_club.add_child(_club_model)


## Club girth, grip and head scale (the same in first and third person).
func girth_scale() -> float:
	return params.club_scale


## Club length: fp_club_length_scale in first person (the club alone), club_length_scale with a body.
func length_scale() -> float:
	if first_person and _fp_reach > 0.0 and club: # the club length from the hands (pose_fp)
		return _fp_reach / ClubModel.hands_to_sole(club, 1.0)
	return params.fp_club_length_scale if first_person else params.club_length_scale


## Faint contact shadow on the ground under the head, fading as the head lifts.
func _place_shadow() -> void:
	var p := params
	if not _shadow:
		_shadow = MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.5
		disc.bottom_radius = 0.5
		disc.height = 0.001
		disc.radial_segments = 12
		disc.rings = 1
		_shadow.mesh = disc
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0, 0, 0, 0)
		_shadow.material_override = mat
		_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_shadow.top_level = true
		add_child(_shadow)
	var head: Node3D = _club_model.get_node("Head")
	var s := club.head_size * girth_scale() * p.club_head_scale
	var centre := head.to_global(Vector3(ClubModel.HEEL + s.x * 0.5, -ClubModel.SOLE_DROP, s.z * 0.5))
	var lift := centre.y - _ground_y
	var fade := clampf(1.0 - lift / p.shadow_fade_height, 0.0, 1.0)
	_shadow.visible = fade > 0.0
	(_shadow.material_override as StandardMaterial3D).albedo_color.a = p.shadow_alpha * fade
	var along := head.global_basis.x
	along.y = 0.0
	var yaw := atan2(along.x, along.z) - PI * 0.5 if along.length() > 0.01 else 0.0
	_shadow.global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(s.x * p.shadow_size, 1.0, maxf(s.z, s.y) * p.shadow_size)),
		Vector3(centre.x, _ground_y + 0.004, centre.z))


## A club metal: the vertex-color look (colors as the base tint) made metallic and fairly smooth, so
## it catches the sky's reflection.
static func _metal(roughness: float) -> StandardMaterial3D:
	var mat := LowPoly.material()
	mat.metallic = CLUB_METALLIC
	mat.metallic_specular = 0.5
	mat.roughness = roughness
	return mat


## Idle with the head turned `yaw` (rad, + left) and the body swayed `sway` (rad) from the hips:
## a bystander's look-around (the tee's caddies).
func pose_idle_look(yaw: float, sway: float) -> void:
	pose_idle()
	_head.rotation.y += yaw
	_torso.rotation.z += sway


# --- the shop's styles: prints, plaid, knickerbockers, novelty shoes, toy hats, club flops ---------

## The outfit pieces some styles add, built once (hidden), shown by _refresh_styles(): the flamingo
## print on the shirt (sleeves and the front), the knickerbockers' puffs at the knee, the clown shoes
## and the bunny slippers.
func _build_styles() -> void:
	var p := params
	var r := p.limb_radius
	var waist := p.torso_waist
	var chest := Vector2(p.torso_top.x * waist, p.torso_top.y * waist)
	var bird := _flamingo_mesh(0.11)
	for x in [-0.055, 0.055]: # down the front, either side of the placket
		_extra("shirt1", _torso, bird, "toy", Vector3(x, p.torso_length * 0.45, -chest.y * 0.5 - 0.006))
	for side in ["l", "r"]:
		var s := -1.0 if side == "l" else 1.0
		var upper: Node3D = _arms[side][0]
		for k in 2: # two on each sleeve, outside
			_extra("shirt1", upper, bird, "toy", Vector3(s * r * 1.3, -p.arm_upper * (0.3 + 0.38 * k), (k - 0.5) * r * 0.5), Vector3(0, -s * PI * 0.5, 0))
		var shin: Node3D = _legs[side][1]
		_extra("pants2", shin, _rounded(8, Vector3(r * 3.3, p.leg_lower * 0.32, r * 3.3), 0.8), "pants", Vector3(0, -p.leg_lower * 0.12, 0)) # the knee puff
		_extra("pants2", shin, _rounded(8, Vector3(r * 2.6, 0.03, r * 2.6)), "belt", Vector3(0, -p.leg_lower * 0.28, 0)) # its band
		var foot: Node3D = _legs[side][2]
		var f := p.foot_size
		_clown_shoe(foot, f)
		_bunny_slipper(foot, f)


func _extra(key: String, parent: Node3D, mesh: Mesh, slot: String, at: Vector3, rot := Vector3.ZERO) -> void:
	var view := MeshInstance3D.new()
	view.mesh = mesh if mesh.has_meta("vc") else LowPoly.flat(mesh, Color.WHITE) # (merged pieces keep their own colours)
	view.position = at
	view.rotation = rot
	parent.add_child(view)
	view.material_override = _mats[slot]
	view.visible = false
	_style_parts.get_or_add(key, []).append(view)


## Each style's pieces on or off, the standard shoes and slacks shins to match; the plaid's material
## on the trousers; the toy hat. Nothing of the body shows in first person.
func _refresh_styles() -> void:
	if look == null:
		return
	var on := {"shirt1": look.shirt_style == 1, "pants2": look.pants_style == 2, "shoe1": look.shoe_style == 1, "shoe2": look.shoe_style == 2}
	for key in _style_parts:
		for view in _style_parts[key]:
			view.visible = on.get(key, false) and not first_person
	for view in _shoe_parts:
		view.visible = look.shoe_style == 0 and not first_person
	for view in _slot_parts.get("pants", []):
		view.material_override = _plaid() if look.pants_style == 1 else _mats.pants
	for view in _shin_parts:
		view.material_override = _socks() if look.pants_style == 2 else (_plaid() if look.pants_style == 1 else _mats.pants)
	if hat_toy:
		hat_toy.visible = not first_person


## Clash plaid: the trousers' colour crossed by green bands and thin yellow lines (in each part's own
## space), shaded by the part's vertex colour like the rest.
func _plaid() -> ShaderMaterial:
	if _mats.has("plaid"):
		_mats.plaid.set_shader_parameter("base", look.pants)
		return _mats.plaid
	_mats.plaid = _pattern("""
	vec3 c = base.rgb;
	vec2 g = fract(p.xy / 0.07);
	vec2 h = fract(p.zy / 0.07);
	float band = max(step(g.x, 0.34), step(g.y, 0.34)) * 0.5 + step(g.x, 0.34) * step(g.y, 0.34) * 0.3;
	c = mix(c, vec3(0.08, 0.36, 0.16), band);
	float line = max(max(step(abs(g.x - 0.62), 0.03), step(abs(g.y - 0.62), 0.03)), step(abs(h.x - 0.62), 0.03));
	c = mix(c, vec3(0.95, 0.82, 0.18), line);
""")
	_mats.plaid.set_shader_parameter("base", look.pants)
	return _mats.plaid


## Argyle socks under the knickerbockers: cream with green diamonds and a thin red line.
func _socks() -> ShaderMaterial:
	if not _mats.has("socks"):
		_mats.socks = _pattern("""
	vec2 d = vec2(atan(p.x, p.z) / 6.2832 * 4.0, p.y / 0.06);
	float diamond = abs(fract(d.x) - 0.5) + abs(fract(d.y) - 0.5);
	vec3 c = mix(vec3(0.92, 0.89, 0.8), vec3(0.18, 0.46, 0.3), step(diamond, 0.32));
	c = mix(c, vec3(0.78, 0.2, 0.2), step(abs(abs(fract(d.x + d.y * 0.5) - 0.5) - 0.25), 0.02));
""")
	return _mats.socks


static func _pattern(body: String) -> ShaderMaterial:
	var s := Shader.new()
	s.code = """
shader_type spatial;
uniform vec4 base : source_color = vec4(1.0);
varying vec3 p;
vec3 linear(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c)); }
void vertex() { p = VERTEX; }
void fragment() {
%s
	ALBEDO = c * linear(COLOR.rgb);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
""" % body
	var mat := ShaderMaterial.new()
	mat.shader = s
	return mat


## A flat pink flamingo `height` tall standing on one leg, facing −Z (the print's motif).
static func _flamingo_mesh(height: float) -> ArrayMesh:
	var root := Node3D.new()
	var pink := Color(0.97, 0.5, 0.66)
	var h := height
	var t := h * 0.04 # thickness: flat on the cloth
	var body := LowPoly.piece(root, LowPoly.sphere(h * 0.22, 8, 4), pink, Vector3(0, h * 0.5, 0))
	body.scale = Vector3(1.3, 0.8, t / (h * 0.22))
	LowPoly.piece(root, LowPoly.box(Vector3(h * 0.05, h * 0.3, t)), pink, Vector3(h * 0.18, h * 0.72, 0), Vector3(0, 0, -0.35)) # the neck
	LowPoly.piece(root, LowPoly.box(Vector3(h * 0.05, h * 0.14, t)), pink, Vector3(h * 0.2, h * 0.9, 0), Vector3(0, 0, 0.6))
	LowPoly.piece(root, LowPoly.box(Vector3(h * 0.12, h * 0.09, t)), pink.lightened(0.1), Vector3(h * 0.16, h * 0.98, 0)) # the head
	LowPoly.piece(root, LowPoly.box(Vector3(h * 0.09, h * 0.04, t)), Color(0.15, 0.12, 0.12), Vector3(h * 0.06, h * 0.95, 0), Vector3(0, 0, -0.5)) # the beak
	LowPoly.piece(root, LowPoly.box(Vector3(h * 0.025, h * 0.4, t)), Color(0.9, 0.45, 0.5), Vector3(0, h * 0.2, 0)) # the leg
	LowPoly.piece(root, LowPoly.box(Vector3(h * 0.025, h * 0.18, t)), Color(0.9, 0.45, 0.5), Vector3(-h * 0.06, h * 0.3, 0), Vector3(0, 0, 1.3)) # the tucked one
	var leaf := LowPoly.piece(root, LowPoly.sphere(h * 0.14, 6, 2), Color(0.3, 0.6, 0.3), Vector3(-h * 0.3, h * 0.2, 0), Vector3(0, 0, 0.8)) # a palm leaf
	leaf.scale = Vector3(1.6, 0.35, t / (h * 0.14))
	return _merged(root)


## Clown Shoes on one foot (toe toward −Z): in the item's colour a long vamp running out to a big
## round toe and a padded heel; a thick two-tone sole with a heel block and a toe rim; the collar's
## dark opening and a tongue, white laces crossing over eyelets, white polka dots on the toe and a
## floppy yellow bow with ribbon tails.
func _clown_shoe(foot: Node3D, f: Vector3) -> void:
	var toe := Vector3(0, -f.y * 0.42, -f.z * 1.5) # the toe bulb's centre
	var bulb := Vector3(f.x * 0.95, f.x * 0.78, f.x * 1.05) # its radii
	var upper := Node3D.new() # (white: the item's colour comes from the shoes material)
	_blob(upper, LowPoly.sphere(1.0, 16, 9), Color.WHITE, toe, bulb)
	_blob(upper, _rounded(8, f * Vector3(1.3, 1.05, 1.0), 0.85), Color.WHITE, Vector3(0, -f.y * 0.45, -f.z * 0.15))
	_blob(upper, _rounded(8, f * Vector3(1.25, 0.82, 1.25), 0.8), Color.WHITE, Vector3(0, -f.y * 0.52, -f.z * 0.85))
	_blob(upper, LowPoly.sphere(1.0, 10, 6), Color.WHITE, Vector3(0, -f.y * 0.35, f.z * 0.28), Vector3(f.x * 0.62, f.y * 0.55, f.x * 0.45)) # the padded heel
	_extra("shoe1", foot, _merged(upper), "shoes", Vector3.ZERO)
	var sole := Node3D.new()
	_blob(sole, _rounded(6, f * Vector3(1.4, 0.3, 1.5)), Color.WHITE, Vector3(0, -f.y * 0.93, -f.z * 0.45))
	_blob(sole, LowPoly.cylinder(1.0, 1.0, 1.0, 16), Color.WHITE, Vector3(toe.x, -f.y * 0.93, toe.z), Vector3(bulb.x * 1.06, f.y * 0.3, bulb.z * 1.06))
	_blob(sole, _rounded(6, f * Vector3(1.15, 0.5, 0.5)), Color(0.82, 0.82, 0.8), Vector3(0, -f.y * 1.02, f.z * 0.12)) # the heel block
	_extra("shoe1", foot, _merged(sole), "sole", Vector3.ZERO)
	var trim := Node3D.new()
	var white := Color(0.97, 0.97, 0.95)
	var dark := Color(0.13, 0.1, 0.1)
	var yellow := Color(0.98, 0.82, 0.2)
	_blob(trim, LowPoly.cylinder(1.0, 1.0, 1.0, 14), dark, Vector3(0, f.y * 0.1, -f.z * 0.12), Vector3(f.x * 0.55, 0.004, f.z * 0.32)) # the opening
	_blob(trim, _rounded(6, Vector3(f.x * 0.7, f.y * 0.25, f.z * 0.4), 0.8), yellow.darkened(0.1), Vector3(0, f.y * 0.12, -f.z * 0.42), Vector3.ONE, Vector3(0.35, 0, 0)) # the tongue
	for k in 3: # laces over the vamp, crossing, eyelets either side
		var z := -f.z * (0.55 + 0.17 * k)
		var y := -f.y * (0.06 + 0.1 * k)
		for side in [-1.0, 1.0]:
			_blob(trim, LowPoly.box(Vector3(f.x * 0.8, f.y * 0.13, f.y * 0.16)), white, Vector3(0, y + f.y * 0.06, z), Vector3.ONE, Vector3(0, side * 0.55, 0))
			_blob(trim, LowPoly.sphere(f.y * 0.08, 6, 3), Color(0.75, 0.76, 0.78), Vector3(side * f.x * 0.34, y, z))
	for d in [Vector3(0.0, 0.55, -0.83), Vector3(0.62, 0.3, -0.72), Vector3(-0.62, 0.3, -0.72), Vector3(0.35, 0.82, -0.45),
			Vector3(-0.35, 0.82, -0.45), Vector3(0.88, -0.05, -0.47), Vector3(-0.88, -0.05, -0.47), Vector3(0.0, 0.1, -0.99)]:
		var n: Vector3 = d.normalized() # polka dots on the toe, flat on its surface
		_dot(trim, f.x * 0.17, white, toe + n * bulb * 0.99, n * Vector3(1.0 / bulb.x, 1.0 / bulb.y, 1.0 / bulb.z))
	var bow := Vector3(0, f.y * 0.32, -f.z * 0.48)
	var size := f.x * 0.8
	for side in [-1.0, 1.0]:
		_blob(trim, LowPoly.sphere(size * 0.4, 10, 6), yellow, bow + Vector3(side * size * 0.42, size * 0.04, 0), Vector3(1.15, 0.75, 0.4), Vector3(0, 0, side * 0.3)) # a loop
		_blob(trim, LowPoly.box(Vector3(size * 0.22, size * 0.7, size * 0.05)), yellow.darkened(0.08), bow + Vector3(side * size * 0.2, -size * 0.32, -size * 0.12), Vector3.ONE, Vector3(-0.5, 0, side * 0.45)) # a ribbon tail
	_blob(trim, LowPoly.sphere(size * 0.2, 8, 4), yellow.darkened(0.18), bow)
	_extra("shoe1", foot, _merged(trim), "toy", Vector3.ZERO)


## Bunny Slippers on one foot (toe toward −Z): in the item's colour a plush body and a round head with
## chubby cheeks, a ring of fluff round the ankle, one ear up and one flopped and a pom-pom tail; a
## pink sole; on the face shiny eyes, a pink nose, a little mouth with buck teeth, whiskers and blush.
func _bunny_slipper(foot: Node3D, f: Vector3) -> void:
	var head := Vector3(0, -f.y * 0.2, -f.z * 0.95)
	var hr := Vector3(f.x * 0.72, f.x * 0.62, f.x * 0.68) # the head's radii
	var plush := Node3D.new()
	_blob(plush, LowPoly.sphere(1.0, 14, 8), Color.WHITE, Vector3(0, -f.y * 0.45, -f.z * 0.32), Vector3(f.x * 0.78, f.y * 0.78, f.z * 0.66))
	_blob(plush, LowPoly.sphere(1.0, 14, 8), Color.WHITE, head, hr)
	for side in [-1.0, 1.0]:
		_blob(plush, LowPoly.sphere(f.x * 0.3, 10, 5), Color.WHITE, head + Vector3(side * f.x * 0.4, -f.x * 0.22, -f.x * 0.3))
	for k in 12: # fluff round the ankle
		var a := TAU * k / 12.0
		_blob(plush, LowPoly.sphere(f.x * 0.17, 7, 4), Color.WHITE, Vector3(cos(a) * f.x * 0.6, f.y * 0.12 + sin(a * 3.0) * f.y * 0.04, -f.z * 0.25 + sin(a) * f.z * 0.4))
	_blob(plush, LowPoly.sphere(f.x * 0.28, 10, 5), Color.WHITE, Vector3(0, -f.y * 0.3, f.z * 0.36)) # the tail
	var ears := [[-1.0, 0.25], [1.0, 1.15]] # [side, outward tilt]: one up, one flopped
	for ear in ears:
		_blob(plush, LowPoly.sphere(1.0, 10, 6), Color.WHITE, _ear_at(head, hr, f, ear[0], ear[1]), Vector3(f.x * 0.2, f.x * 0.62, f.x * 0.09), Vector3(-0.25, 0, -ear[0] * ear[1]))
	_extra("shoe2", foot, _merged(plush), "shoes", Vector3.ZERO)
	var face := Node3D.new()
	var pink := Color(0.96, 0.62, 0.72)
	var black := Color(0.06, 0.05, 0.07)
	for ear in ears:
		_blob(face, LowPoly.sphere(1.0, 8, 5), pink, _ear_at(head, hr, f, ear[0], ear[1]) + Vector3(0, 0, -f.x * 0.06), Vector3(f.x * 0.12, f.x * 0.5, f.x * 0.05), Vector3(-0.25, 0, -ear[0] * ear[1]))
	for side in [-1.0, 1.0]:
		var eye := _on_front(head, hr, side * f.x * 0.3, f.x * 0.16)
		_blob(face, LowPoly.sphere(f.x * 0.12, 8, 5), black, eye)
		_blob(face, LowPoly.sphere(f.x * 0.04, 6, 3), Color.WHITE, eye + Vector3(side * f.x * 0.03, f.x * 0.05, -f.x * 0.09)) # its shine
		_dot(face, f.x * 0.13, pink.lightened(0.2), _on_front(head, hr, side * f.x * 0.5, -f.x * 0.12), Vector3(side * 0.8, 0, -1)) # blush
		for w in 3: # whiskers
			_blob(face, LowPoly.box(Vector3(f.x * 0.5, 0.0025, 0.0025)), Color(0.45, 0.45, 0.47), _on_front(head, hr, side * f.x * 0.42, -f.x * (0.02 + 0.08 * w)) + Vector3(0, 0, -0.004), Vector3.ONE, Vector3(0, -side * 0.25, side * (0.18 - 0.18 * w)))
		_blob(face, LowPoly.box(Vector3(f.x * 0.16, 0.003, 0.003)), black, _on_front(head, hr, side * f.x * 0.06, -f.x * 0.12) + Vector3(0, 0, -0.003), Vector3.ONE, Vector3(0, 0, side * 0.6)) # the mouth (a smile)
		_blob(face, LowPoly.box(Vector3(f.x * 0.07, f.x * 0.1, f.x * 0.03)), Color.WHITE, _on_front(head, hr, side * f.x * 0.04, -f.x * 0.23)) # a buck tooth
	_blob(face, LowPoly.sphere(f.x * 0.09, 8, 4), pink, _on_front(head, hr, 0, -f.x * 0.02), Vector3(1.2, 0.8, 0.7)) # the nose
	_blob(face, _rounded(8, Vector3(f.x * 1.25, f.y * 0.2, f.z * 1.2)), pink.lightened(0.25), Vector3(0, -f.y * 1.0, -f.z * 0.42)) # the sole (tucked under the plush)
	_extra("shoe2", foot, _merged(face), "toy", Vector3.ZERO)


## Where a bunny ear stands on the head: on top, to `side`, tipped out by `tilt` (rad).
static func _ear_at(head: Vector3, hr: Vector3, f: Vector3, side: float, tilt: float) -> Vector3:
	var length := f.x * 0.62
	return head + Vector3(side * (f.x * 0.25 + sin(tilt) * length), hr.y * 0.8 + cos(tilt) * length, hr.z * 0.15)


## A point on the front (−Z) of an ellipsoid centred `c` with radii `r`, at `x`, `y` across it.
static func _on_front(c: Vector3, r: Vector3, x: float, y: float) -> Vector3:
	return c + Vector3(x, y, -r.z * sqrt(maxf(1.0 - x * x / (r.x * r.x) - y * y / (r.y * r.y), 0.0)))


## A piece in `root` at `at`, scaled and turned (merged later).
static func _blob(root: Node3D, mesh: Mesh, color: Color, at: Vector3, scale := Vector3.ONE, rot := Vector3.ZERO) -> void:
	LowPoly.piece(root, mesh, color, at, rot).scale = scale


## A flat round dot on a surface at `at`, facing out along `normal`.
static func _dot(root: Node3D, radius: float, color: Color, at: Vector3, normal: Vector3) -> void:
	var n := normal.normalized()
	var basis := Basis.looking_at(-n, Vector3.UP if absf(n.y) < 0.95 else Vector3.FORWARD) # (its +Z out of the surface)
	LowPoly.piece(root, LowPoly.sphere(radius, 8, 4), color, at, basis.get_euler()).scale = Vector3(1, 1, 0.12)


static func _merged(root: Node3D) -> ArrayMesh:
	var parts: Array[Node3D] = []
	for child in root.get_children():
		parts.append(child)
	var mesh := LowPoly.merge(parts)
	mesh.set_meta("vc", true)
	root.free()
	return mesh


## Contact with a novelty head (Fresh Catch: its tail flops; Squeaky Set: a drive over beak_power
## drops the chicken's beak open), by the shot's power. The player's own and other players' alike.
func club_impact(power: float) -> void:
	_flop = 0.0
	_flop_power = clampf(power, 0.0, 1.0)
	_flop_beak = club != null and club.model == ClubData.Model.DRIVER and power > NOVELTY.beak_power


func _process(delta: float) -> void:
	if _flop < 0.0 or _club_model == null:
		return
	_flop += delta
	var f := _flop / NOVELTY.flop_time
	var tail := _club_model.get_node_or_null("Head/Novelty/Tail") as Node3D
	var beak := _club_model.get_node_or_null("Head/Novelty/Beak") as Node3D
	if tail:
		tail.rotation.y = sin(_flop * 30.0) * exp(-f * 4.0) * NOVELTY.flop_angle * (0.35 + 0.65 * _flop_power)
	if beak:
		beak.rotation.z = -(0.9 if _flop_beak else 0.0) * clampf(minf(_flop / 0.05, (1.0 - f) / 0.3), 0.0, 1.0)
	if f >= 1.0:
		_flop = -1.0
		if tail:
			tail.rotation.y = 0.0
		if beak:
			beak.rotation.z = 0.0


## A walk step (each foot down): the clown shoes slap.
func _stepped() -> void:
	if look == null or look.shoe_style != 1 or DisplayServer.get_name() == "headless":
		return
	if _feet_sound == null:
		_feet_sound = AudioStreamPlayer3D.new()
		_feet_sound.bus = &"SFX"
		_feet_sound.stream = PlaceholderSounds.shoe_slap()
		add_child(_feet_sound)
	_feet_sound.global_position = (_legs.l[2] as Node3D).global_position
	_feet_sound.volume_db = NOVELTY.shoe_slap_volume_db
	_feet_sound.pitch_scale = 0.9 + 0.2 * float(Time.get_ticks_msec() % 7) / 7.0
	_feet_sound.play()
