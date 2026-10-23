class_name ClubModel
## A club built from its ClubData in the project look: beveled low-poly, flat shaded, vertex colors
## as shade (multiplied by the look's club color), one grip material. Origin at the hands, shaft
## down −Y. A "Head" child at the shaft end holds the head: in its frame toe is +X, up is +Y, the
## face looks along −Z and leans back by the club's loft about the shaft-end height (so the hosel meets
## the heel and face_centre() is on the face; the sole stays flat). The rig turns
## "Head" about Z to the club's lie so the sole sits on the ground at address.
## Materials: `club_mat` the head and hosel, `shaft_mat` the shaft (null: club_mat), `grip_mat` the grip.
## Visual scales: `scale` girth, grip and head; `head_scale` the head on top; `length_scale` the
## hands-to-sole length (the rig places the hands with it, so the club still soles at the ball).
## `style`: the look's club_style (the shop's novelty heads, _novelty()).

const SHAFT_RADIUS := Vector2(0.0055, 0.0075) ## tip, butt
const GRIP_RADIUS := 0.013
const SOLE_DROP := 0.045 ## sole below the shaft end (the ball's centre height above ground)
const BALL_RADIUS := 0.05
const HEEL := 0.006 ## m from the shaft axis to the head's heel

# Shades (multiplied by the club color).
const FACE := Color(1.0, 1.0, 1.0)
const BODY := Color(0.86, 0.86, 0.86)
const CROWN := Color(0.62, 0.63, 0.64)
const SOLE := Color(0.78, 0.78, 0.78)
const GROOVE := Color(0.5, 0.5, 0.5)
const LINE := Color(1.15, 1.15, 1.15)

## Blade outline (toe u, height v), heel to toe along the sole then back over the top.
const BLADE := [Vector2(0.02, 0.0), Vector2(0.35, 0.0), Vector2(0.7, 0.0), Vector2(0.9, 0.01), Vector2(0.98, 0.08),
	Vector2(1.0, 0.28), Vector2(0.99, 0.55), Vector2(0.94, 0.8), Vector2(0.83, 0.96), Vector2(0.64, 1.0),
	Vector2(0.44, 0.89), Vector2(0.24, 0.75), Vector2(0.08, 0.62), Vector2(0.0, 0.42), Vector2(0.0, 0.14)]
## Driver top view (toe x, back z): flat face along z ≈ 0, teardrop behind.
const DRIVER_TOP := [Vector2(0.03, 0.0), Vector2(0.34, -0.012), Vector2(0.66, -0.012), Vector2(0.97, 0.0),
	Vector2(1.0, 0.13), Vector2(0.97, 0.36), Vector2(0.88, 0.6), Vector2(0.72, 0.82), Vector2(0.52, 0.95),
	Vector2(0.32, 0.93), Vector2(0.16, 0.79), Vector2(0.06, 0.52), Vector2(0.0, 0.22)]
const DRIVER_FACE_POINTS := 4 ## the first points of DRIVER_TOP lie on the face
## Driver levels: (height fraction, outline scale): sole to crown dome.
const DRIVER_LEVELS := [Vector2(0.0, 0.84), Vector2(0.1, 0.96), Vector2(0.3, 1.0), Vector2(0.55, 0.98),
	Vector2(0.76, 0.86), Vector2(0.92, 0.6)]


static func build(club: ClubData, bevel: float, segments: int, club_mat: Material, grip_mat: Material, shaft_mat: Material,
		scale := 1.0, head_scale := 1.0, length_scale := 1.0, style := 0) -> Node3D:
	var root := Node3D.new()
	var reach := hands_to_sole(club, length_scale)
	var grip_len := club.grip_length * scale
	var grip_r := GRIP_RADIUS * scale
	_part(root, LowPoly.flat(LowPoly.rounded_prism(6, Vector3(grip_r * 2.0, grip_len, grip_r * 2.0), grip_r * 0.6,
		segments, 0.85), Color.WHITE), grip_mat, Vector3(0, grip_len * 0.4 - grip_len * 0.5, 0))
	# Hosel along the shaft: the shaft enters it at the club's lie.
	var hosel := 0.05 * scale * head_scale
	var shaft_len := reach - grip_len * 0.6 - hosel + 0.01
	_part(root, LowPoly.flat(LowPoly.cylinder(SHAFT_RADIUS.y * scale, SHAFT_RADIUS.x * scale, shaft_len, 5), Color.WHITE),
		shaft_mat if shaft_mat else club_mat, Vector3(0, -grip_len * 0.6 - shaft_len * 0.5 + 0.005, 0))
	var neck := 0.0095 * scale * head_scale
	_part(root, LowPoly.flat(LowPoly.rounded_prism(6, Vector3(neck * 2.0, hosel, neck * 2.0), neck * 0.4, segments, 0.75),
		BODY), club_mat, Vector3(0, -reach + hosel * 0.5, 0))
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, -reach, 0)
	root.add_child(head)
	var s := club.head_size * scale * head_scale
	if style > 0: # the shop's novelty heads (same face plane)
		_novelty(head, club, s, style)
		return root
	var loft := deg_to_rad(club.loft_deg)
	var mesh := Tris.new()
	match club.model:
		ClubData.Model.DRIVER:
			_driver(mesh, s, loft)
		ClubData.Model.PUTTER:
			_putter(mesh, s, bevel, segments)
		_:
			_blade(mesh, s, loft, bevel, club.model == ClubData.Model.WEDGE)
	_part(head, mesh.build(), club_mat, Vector3.ZERO)
	return root


## Distance from where the hands hold the grip to the sole point, at a model scale.
static func hands_to_sole(club: ClubData, scale := 1.0) -> float:
	return (club.shaft_length - club.grip_length * 0.4) * scale


## Face centre in the head frame (toe +X, up +Y, face toward −Z): the middle of the face's own
## outline (face_outline()), on the lofted face plane — not the shaft end's height. The rig puts this
## point just behind the ball, and first person on the hitbox's leading face.
static func face_centre(club: ClubData, scale := 1.0, head_scale := 1.0) -> Vector3:
	var outline := face_outline(club, scale, head_scale)
	var lo := outline[0]
	var hi := outline[0]
	for p in outline:
		lo = lo.min(p)
		hi = hi.max(p)
	var s := club.head_size * scale * head_scale
	var x := HEEL + s.x * (0.42 if club.model == ClubData.Model.PUTTER else 0.5)
	var y := (lo.y + hi.y) * 0.5
	return Vector3(x, y, face_z(club, y))


## The face's outline in the head frame, the polygon the ball meets: a blade's outline on its lofted
## face, the driver's flat face (heel to toe, sole to crown), the putter's front.
static func face_outline(club: ClubData, scale := 1.0, head_scale := 1.0) -> PackedVector3Array:
	var s := club.head_size * scale * head_scale
	var out := PackedVector3Array()
	match club.model:
		ClubData.Model.PUTTER:
			var left := HEEL + s.x * 0.42 - s.x * 0.5
			for c in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
				out.append(Vector3(left + c.x * s.x, -SOLE_DROP + c.y * s.y, 0.0))
		ClubData.Model.DRIVER:
			for c in [Vector2(0.03, 0.0), Vector2(0.97, 0.0), Vector2(0.92, 0.92), Vector2(0.08, 0.92)]:
				var y: float = -SOLE_DROP + c.y * s.y
				out.append(Vector3(HEEL + c.x * s.x, y, face_z(club, y)))
		_:
			for p: Vector2 in BLADE:
				var y := -SOLE_DROP + p.y * s.y
				out.append(Vector3(HEEL + p.x * s.x, y, face_z(club, y)))
	return out


## The face plane's depth at height `y` (head frame): leaned back by the loft about the shaft end's
## height (the putter's front is upright).
static func face_z(club: ClubData, y: float) -> float:
	return 0.0 if club.model == ClubData.Model.PUTTER else y * tan(deg_to_rad(club.loft_deg))


## The face's outward normal in the head frame.
static func face_normal(club: ClubData) -> Vector3:
	var loft := 0.0 if club.model == ClubData.Model.PUTTER else deg_to_rad(club.loft_deg)
	return Vector3(0, sin(loft), -cos(loft))


## The visible gap: m from a ball's surface (centre `ball`, radius `radius`, world) to the nearest point
## of the drawn clubhead under `head` — every triangle of its meshes (face, leading edge, sole, a novelty
## head's fish or chicken), so on a lofted head it is usually the leading edge that meets the ball
## first. < 0 where the head is inside the ball.
static func head_gap(head: Node3D, ball: Vector3, radius := BALL_RADIUS) -> float:
	var best := INF
	for view in head.find_children("*", "MeshInstance3D", true, false):
		var mesh := (view as MeshInstance3D).mesh
		if mesh == null or not (view as MeshInstance3D).is_visible_in_tree():
			continue
		var xf := (view as MeshInstance3D).global_transform
		var local := xf.affine_inverse() * ball # (the ball in the mesh's frame: one transform per mesh, not per vertex)
		var scale := xf.basis.get_scale().x
		for s in mesh.get_surface_count():
			var verts: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for k in range(0, verts.size() - 2, 3):
				best = minf(best, local.distance_to(_closest_on_triangle(local, verts[k], verts[k + 1], verts[k + 2])) * scale)
	return best - radius


## The point of triangle a b c nearest `p` (Ericson, Real-Time Collision Detection 5.1.5).
static func _closest_on_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and d4 - d3 >= 0.0 and d5 - d6 >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var denom := 1.0 / (va + vb + vc)
	return a + ab * (vb * denom) + ac * (vc * denom)


## m from a ball (centre `ball`, radius `radius`, world) to the face of the club whose head is `head`:
## the ball's surface to the nearest point of the face polygon; < 0 where the face is inside the ball.
static func face_gap(head: Node3D, club: ClubData, scale: float, head_scale: float, ball: Vector3, radius := BALL_RADIUS) -> float:
	var xf := head.global_transform
	var poly := PackedVector3Array()
	for p in face_outline(club, scale, head_scale):
		poly.append(xf * p)
	var n := (xf.basis * face_normal(club)).normalized()
	var u := (xf.basis.x).normalized()
	var v := n.cross(u).normalized()
	var d := (ball - poly[0]).dot(n) # in front of the plane (+)
	var q := ball - n * d
	var flat := PackedVector2Array()
	for p in poly:
		flat.append(Vector2((p - poly[0]).dot(u), (p - poly[0]).dot(v)))
	if Geometry2D.is_point_in_polygon(Vector2((q - poly[0]).dot(u), (q - poly[0]).dot(v)), flat):
		return d - radius
	var best := INF
	for k in poly.size():
		var c := Geometry3D.get_closest_point_to_segment(ball, poly[k], poly[(k + 1) % poly.size()])
		best = minf(best, ball.distance_to(c))
	return (best if d >= 0.0 else -best) - radius


## Bladed iron or wedge: the blade outline extruded behind a lofted face, every edge chamfered,
## thick at the sole and thin at the top line (wedges: wider sole), grooves as shallow ridges.
static func _blade(t: Tris, s: Vector3, loft: float, bevel: float, wedge: bool) -> void:
	var length := s.x
	var height := s.y
	var sole := s.z
	var top := s.z * (0.25 if wedge else 0.38)
	var e := minf(height, top) * bevel * 2.0
	var centre := Vector2.ZERO
	for p in BLADE:
		centre += p
	centre /= BLADE.size()
	var rings: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array(), PackedVector3Array(), PackedVector3Array()]
	for p: Vector2 in BLADE:
		var inset := p - (p - centre).normalized() * Vector2(e / length, e / height)
		for r in 4:
			var uv: Vector2 = inset if r == 0 or r == 3 else p
			var y := uv.y * height
			var face_z := (y - SOLE_DROP) * tan(loft) # leans back about the shaft-end height: the hosel meets the heel
			var depth := lerpf(sole, top, uv.y)
			var z: float = [face_z, face_z + e, face_z + depth - e, face_z + depth][r]
			rings[r].append(Vector3(HEEL + uv.x * length, -SOLE_DROP + y, z))
	var mid := Vector3(HEEL + centre.x * length, -SOLE_DROP + centre.y * height,
		(centre.y * height - SOLE_DROP) * tan(loft) + lerpf(sole, top, centre.y) * 0.5)
	t.cap(rings[0], mid, FACE)
	t.band(rings[0], rings[1], mid, BODY)
	t.band(rings[1], rings[2], mid, BODY, SOLE)
	t.band(rings[2], rings[3], mid, BODY)
	t.cap(rings[3], mid, BODY)
	var normal := Vector3(0, sin(loft), -cos(loft))
	var up := Vector3(0, cos(loft), sin(loft))
	for k in 4:
		var v := 0.18 + k * 0.15
		var at := Vector3(HEEL + 0.47 * length, -SOLE_DROP + v * height, (v * height - SOLE_DROP) * tan(loft)) + normal * 0.0008
		t.box(at, Vector3.RIGHT * length * 0.31, up * height * 0.016, normal * 0.0012, GROOVE)


## Driver: a teardrop crown lofted in rings from sole to dome, its flat face leaning back by the
## loft, a darker crown and a light crown line along the top of the face.
static func _driver(t: Tris, s: Vector3, loft: float) -> void:
	var width := s.x
	var height := s.y
	var depth := s.z
	var centre := Vector2.ZERO
	for p in DRIVER_TOP:
		centre += p
	centre /= DRIVER_TOP.size()
	var rings: Array[PackedVector3Array] = []
	for level: Vector2 in DRIVER_LEVELS:
		var y := level.x * height
		var ring := PackedVector3Array()
		for i in DRIVER_TOP.size():
			var p: Vector2 = DRIVER_TOP[i]
			var x := centre.x + (p.x - centre.x) * level.y
			var z := p.y if i < DRIVER_FACE_POINTS else centre.y + (p.y - centre.y) * level.y
			ring.append(Vector3(HEEL + x * width, -SOLE_DROP + y, (y - SOLE_DROP) * tan(loft) + z * depth))
		rings.append(ring)
	var mid := Vector3(HEEL + centre.x * width, -SOLE_DROP + height * 0.45, centre.y * depth)
	t.cap(rings[0], mid, SOLE)
	for k in rings.size() - 1:
		t.band(rings[k], rings[k + 1], mid, CROWN if k >= 3 else BODY, Color(), DRIVER_FACE_POINTS - 1, FACE)
	t.cap(rings[-1], mid, CROWN)
	var top := rings[-2]
	for i in DRIVER_FACE_POINTS - 1: # crown line along the top of the face
		var a := top[i] + Vector3(0, 0.0012, 0.003)
		var b := top[i + 1] + Vector3(0, 0.0012, 0.003)
		t.quad(a, b, b + Vector3(0, 0.0004, 0.006), a + Vector3(0, 0.0004, 0.006), Vector3.UP, LINE)


## Putter: a beveled blade beside a short neck, with a white alignment line on top.
static func _putter(t: Tris, s: Vector3, bevel: float, segments: int) -> void:
	var blade := LowPoly.rounded_prism(4, s, minf(s.x, minf(s.y, s.z)) * bevel * 1.5, segments)
	var verts: PackedVector3Array = blade.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var at := Vector3(HEEL + s.x * 0.42, -SOLE_DROP + s.y * 0.5, s.z * 0.5)
	for k in range(0, verts.size(), 3):
		t.raw(verts[k] + at, verts[k + 1] + at, verts[k + 2] + at, BODY)
	t.box(at + Vector3(0, s.y * 0.5 + 0.0008, 0), Vector3(0.0018, 0, 0), Vector3(0, 0.0006, 0),
		Vector3(0, 0, s.z * 0.45), LINE)


static func _part(parent: Node3D, mesh: Mesh, material: Material, at: Vector3) -> void:
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.material_override = material
	view.position = at
	parent.add_child(view)


## Flat-shaded triangle soup with per-face shades; faces are wound outward from a point inside.
class Tris:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()

	## One triangle, flipped if needed so its normal points away from `inside`.
	func tri(a: Vector3, b: Vector3, c: Vector3, inside: Vector3, color: Color) -> void:
		var n := (c - a).cross(b - a)
		if n.length_squared() < 1e-14:
			return
		if n.dot((a + b + c) / 3.0 - inside) < 0.0:
			raw(a, c, b, color, -n.normalized())
		else:
			raw(a, b, c, color, n.normalized())

	## Already wound: normal from the winding unless given.
	func raw(a: Vector3, b: Vector3, c: Vector3, color: Color, n := Vector3.ZERO) -> void:
		if n == Vector3.ZERO:
			n = (c - a).cross(b - a).normalized()
		verts.append_array([a, b, c])
		normals.append_array([n, n, n])
		colors.append_array([color, color, color])

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, color: Color) -> void:
		var inside := (a + b + c + d) * 0.25 - outward
		tri(a, b, c, inside, color)
		tri(a, c, d, inside, color)

	## Fan from a ring's centroid, facing away from `inside`.
	func cap(ring: PackedVector3Array, inside: Vector3, color: Color) -> void:
		var middle := Vector3.ZERO
		for p in ring:
			middle += p
		middle /= ring.size()
		for i in ring.size():
			tri(middle, ring[i], ring[(i + 1) % ring.size()], inside, color)

	## Side band between two rings of equal size. Segments with both ends on the lowest height
	## take `low_shade` (the sole); the first `face_count` segments take `face_shade`.
	func band(lo: PackedVector3Array, hi: PackedVector3Array, inside: Vector3, shade: Color,
			low_shade := Color(), face_count := 0, face_shade := Color()) -> void:
		var floor_y := INF
		for p in lo:
			floor_y = minf(floor_y, p.y)
		for i in lo.size():
			var j := (i + 1) % lo.size()
			var color := shade
			if i < face_count:
				color = face_shade
			elif low_shade != Color() and absf(lo[i].y - floor_y) < 1e-5 and absf(lo[j].y - floor_y) < 1e-5:
				color = low_shade
			tri(lo[i], lo[j], hi[i], inside, color)
			tri(hi[i], lo[j], hi[j], inside, color)

	## Oriented box: centre and three half-axis vectors.
	func box(at: Vector3, x: Vector3, y: Vector3, z: Vector3, color: Color) -> void:
		for axes in [[x, y, z], [y, z, x], [z, x, y]]:
			for sgn: float in [-1.0, 1.0]:
				var n: Vector3 = axes[0] * sgn
				var u: Vector3 = axes[1]
				var w: Vector3 = axes[2]
				quad(at + n + u + w, at + n - u + w, at + n - u - w, at + n + u - w, n, color)

	func build() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh


# --- the shop's novelty heads ------------------------------------------------------------------

## A novelty head in place of the standard one (CharacterLook.club_style: 1 Fresh Catch, 2 Squeaky
## Set), sized to the club's head: its flat face is the standard face plane — the head frame's z = 0
## plane through the shaft end, leaned back by the loft — over the same heel-to-toe span and height,
## so face_centre(), the hitbox and every contact offset are unchanged. Fresh Catch: a stiff fish, its
## flank the face, the tail past the toe ("Tail", flops on impact); the putter a flat flounder.
## Squeaky Set: a rubber chicken, its neck and head past the toe with a beak whose lower half
## ("Beak") drops open on a big drive; the putter a rubber duck. Vertex colours, matte.
static func _novelty(head: Node3D, club: ClubData, s: Vector3, style: int) -> void:
	var frame := Node3D.new() # unlofted: face at z = 0 looking −Z; the loft leans it all back
	frame.name = "Novelty"
	frame.basis = Basis(Vector3.RIGHT, deg_to_rad(club.loft_deg))
	head.add_child(frame)
	var putter := club.model == ClubData.Model.PUTTER
	var centre := Vector3(HEEL + s.x * (0.42 if putter else 0.5), -SOLE_DROP + s.y * 0.5, 0.0)
	var body := Node3D.new()
	var extra := Node3D.new() # pieces that are not body: never flattened onto the face
	var moving := Node3D.new() # the tail or the beak
	var hinge := Vector3.ZERO
	if style == 1 and not putter: # a fish
		var depth := maxf(s.z * 0.8, s.y * 0.38)
		var flank := LowPoly.piece(body, LowPoly.sphere(1.0, 12, 6), Color(0.78, 0.8, 0.82), centre + Vector3(-s.x * 0.04, 0, depth * 0.1))
		flank.scale = Vector3(s.x * 0.54, s.y * 0.5, depth)
		_shade_by_height(flank, centre.y + s.y * 0.12, Color(0.36, 0.48, 0.58), centre.y - s.y * 0.25, Color(0.92, 0.92, 0.88))
		LowPoly.piece(extra, LowPoly.prism(3, s.x * 0.28, s.x * 0.02, s.y * 0.3), Color(0.32, 0.44, 0.54), # the dorsal fin
			centre + Vector3(s.x * 0.08, s.y * 0.48, depth * 0.45), Vector3(0, 0, 0)).scale = Vector3(1.0, 1.0, 0.25)
		LowPoly.piece(extra, LowPoly.sphere(s.y * 0.09, 6, 3), Color(0.96, 0.96, 0.92), centre + Vector3(-s.x * 0.34, s.y * 0.1, depth * 0.85))
		LowPoly.piece(extra, LowPoly.sphere(s.y * 0.05, 6, 3), Color(0.08, 0.08, 0.1), centre + Vector3(-s.x * 0.36, s.y * 0.1, depth * 0.95))
		LowPoly.piece(extra, LowPoly.box(Vector3(s.x * 0.05, s.y * 0.35, depth * 0.6)), Color(0.55, 0.32, 0.32), centre + Vector3(-s.x * 0.5, -s.y * 0.05, depth * 0.35)) # the mouth
		hinge = centre + Vector3(s.x * 0.46, 0, depth * 0.35)
		for side in [-1.0, 1.0]: # the tail: two lobes
			var lobe := LowPoly.piece(moving, LowPoly.prism(3, s.y * 0.5, s.y * 0.05, s.x * 0.34), Color(0.4, 0.5, 0.6),
				Vector3(s.x * 0.16, side * s.y * 0.16, 0), Vector3(0, 0, -PI * 0.5 + side * 0.45))
			lobe.scale = Vector3(1.0, 1.0, 0.22)
	elif style == 1: # the flounder: wide and flat, both eyes on top
		var flat := LowPoly.piece(body, LowPoly.sphere(1.0, 12, 5), Color(0.62, 0.5, 0.36), centre + Vector3(0, 0, s.z * 0.55))
		flat.scale = Vector3(s.x * 0.56, s.y * 0.62, s.z * 1.3)
		_shade_by_height(flat, centre.y + s.y * 0.1, Color(0.5, 0.4, 0.28), centre.y - s.y * 0.2, Color(0.94, 0.92, 0.86))
		for k in 5: # mottled spots
			LowPoly.piece(extra, LowPoly.sphere(s.y * 0.2, 5, 2), Color(0.42, 0.32, 0.22), centre + Vector3((k - 2) * s.x * 0.17, s.y * 0.55, s.z * (0.5 + 0.3 * (k % 2)))).scale = Vector3(1, 0.3, 1)
		for k in 2:
			LowPoly.piece(extra, LowPoly.sphere(s.y * 0.22, 6, 3), Color(0.96, 0.95, 0.9), centre + Vector3(-s.x * (0.12 + 0.12 * k), s.y * 0.62, s.z * 0.35))
			LowPoly.piece(extra, LowPoly.sphere(s.y * 0.12, 6, 3), Color(0.08, 0.08, 0.1), centre + Vector3(-s.x * (0.12 + 0.12 * k), s.y * 0.76, s.z * 0.3))
		hinge = centre + Vector3(s.x * 0.55, 0, s.z * 0.55)
		var fin := LowPoly.piece(moving, LowPoly.prism(3, s.z * 1.4, s.z * 0.1, s.x * 0.22), Color(0.55, 0.44, 0.3), Vector3(s.x * 0.1, 0, 0), Vector3(0, 0, -PI * 0.5))
		fin.scale = Vector3(1.0, 1.0, 0.18)
	elif not putter: # a rubber chicken
		var depth := maxf(s.z * 0.8, s.y * 0.4)
		var yellow := Color(0.98, 0.9, 0.55)
		var bird := LowPoly.piece(body, LowPoly.sphere(1.0, 10, 6), yellow, centre + Vector3(-s.x * 0.05, 0, depth * 0.1))
		bird.scale = Vector3(s.x * 0.5, s.y * 0.5, depth)
		for k in 3: # plucked bumps
			LowPoly.piece(extra, LowPoly.sphere(s.y * 0.07, 5, 2), yellow.darkened(0.08), centre + Vector3((k - 1) * s.x * 0.25, s.y * 0.4, depth * 0.8))
		var neck := centre + Vector3(s.x * 0.4, s.y * 0.1, depth * 0.3)
		var up := Vector3(0.7, 0.75, 0.0).normalized()
		LowPoly.piece(extra, LowPoly.cylinder(s.y * 0.1, s.y * 0.15, s.x * 0.45, 6), yellow, neck + up * s.x * 0.2, _along_y(up))
		var crown := neck + up * s.x * 0.45
		LowPoly.piece(extra, LowPoly.sphere(s.y * 0.2, 7, 4), yellow, crown)
		for k in 3: # the comb
			LowPoly.piece(extra, LowPoly.sphere(s.y * 0.07, 5, 2), Color(0.88, 0.2, 0.18), crown + Vector3(-s.y * 0.08 + k * s.y * 0.08, s.y * 0.2, 0))
		for side in [-1.0, 1.0]:
			LowPoly.piece(extra, LowPoly.sphere(s.y * 0.04, 5, 2), Color(0.08, 0.08, 0.1), crown + Vector3(s.y * 0.06, s.y * 0.06, side * s.y * 0.17))
		LowPoly.piece(extra, LowPoly.cylinder(0.0, s.y * 0.07, s.y * 0.2, 4), Color(0.96, 0.6, 0.15), crown + Vector3(s.y * 0.26, s.y * 0.03, 0), Vector3(0, 0, -PI * 0.5)) # upper beak
		hinge = crown + Vector3(s.y * 0.16, -s.y * 0.05, 0)
		var lower := LowPoly.piece(moving, LowPoly.cylinder(0.0, s.y * 0.06, s.y * 0.18, 4), Color(0.9, 0.5, 0.12), Vector3(s.y * 0.09, -s.y * 0.01, 0), Vector3(0, 0, -PI * 0.5))
		lower.scale = Vector3(1.0, 1.0, 0.8)
	else: # the rubber duck
		var yellow := Color(0.98, 0.84, 0.2)
		var duck := LowPoly.piece(body, LowPoly.sphere(1.0, 10, 5), yellow, centre + Vector3(0, 0, s.z * 0.5))
		duck.scale = Vector3(s.x * 0.5, s.y * 0.62, s.z * 1.1)
		var crown := centre + Vector3(-s.x * 0.15, s.y * 0.95, s.z * 0.55)
		LowPoly.piece(extra, LowPoly.sphere(s.y * 0.55, 8, 4), yellow, crown)
		for side in [-1.0, 1.0]:
			LowPoly.piece(extra, LowPoly.sphere(s.y * 0.09, 5, 2), Color(0.08, 0.08, 0.1), crown + Vector3(-s.y * 0.2, s.y * 0.15, side * s.y * 0.42))
		LowPoly.piece(extra, LowPoly.sphere(s.y * 0.2, 5, 3), yellow.lightened(0.1), centre + Vector3(s.x * 0.48, s.y * 0.4, s.z * 0.6)) # the tail tuft
		hinge = crown + Vector3(-s.y * 0.5, -s.y * 0.05, 0)
		var bill := LowPoly.piece(moving, LowPoly.box(Vector3(s.y * 0.4, s.y * 0.12, s.y * 0.35)), Color(0.96, 0.52, 0.14), Vector3(-s.y * 0.18, 0, 0))
		bill.scale = Vector3.ONE
	var parts: Array[Node3D] = []
	for p in body.get_children():
		parts.append(p)
	var face := LowPoly.merge(parts)
	_flatten_face(face) # the body's front squared off onto the face plane
	var view := MeshInstance3D.new()
	view.mesh = face
	view.material_override = LowPoly.shared_material()
	frame.add_child(view)
	parts.clear()
	for p in extra.get_children():
		parts.append(p)
	var details := MeshInstance3D.new()
	details.mesh = LowPoly.merge(parts)
	details.material_override = LowPoly.shared_material()
	frame.add_child(details)
	var pivot := Node3D.new()
	pivot.name = "Tail" if style == 1 else "Beak"
	pivot.position = hinge
	frame.add_child(pivot)
	parts.clear()
	for p in moving.get_children():
		parts.append(p)
	var flop := MeshInstance3D.new()
	flop.mesh = LowPoly.merge(parts)
	flop.material_override = LowPoly.shared_material()
	pivot.add_child(flop)
	body.free()
	extra.free()
	moving.free()


## A merged mesh's vertices in front of the face plane (z < 0) moved onto it: a flat face.
static func _flatten_face(mesh: ArrayMesh) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for k in verts.size():
		verts[k].z = maxf(verts[k].z, 0.0)
	for k in range(0, verts.size(), 3): # the flat faces' normals
		var n := (verts[k + 2] - verts[k]).cross(verts[k + 1] - verts[k])
		if n.length_squared() > 1e-16:
			n = n.normalized()
			for j in 3:
				normals[k + j] = n
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


## A piece's faces two-toned by height: above `top` the back's colour, below `low` the belly's.
static func _shade_by_height(piece: Node3D, top: float, back: Color, low: float, belly: Color) -> void:
	var arrays: Array = piece.get_meta("flat")
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for k in range(0, verts.size(), 3):
		var y := (piece.transform * ((verts[k] + verts[k + 1] + verts[k + 2]) / 3.0)).y
		var c := back if y > top else (belly if y < low else colors[k])
		for j in 3:
			colors[k + j] = c
	arrays[Mesh.ARRAY_COLOR] = colors


## Euler angles turning +y onto `dir`.
static func _along_y(dir: Vector3) -> Vector3:
	var axis := Vector3.UP.cross(dir)
	if axis.length() < 0.0001:
		return Vector3.ZERO
	return Basis(axis.normalized(), Vector3.UP.angle_to(dir)).get_euler()
