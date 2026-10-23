class_name ArtDresser
## Re-dresses a built GeneratedHole with an ArtPreset: flat-shaded vertex-colored terrain,
## low-poly trees and flag, plus a chunky golfer and ball. Visual only: it swaps meshes and never
## touches colliders, hole data or procgen. Used by the art mocks, not by the game yet.


static func dress(hole: GeneratedHole, art: ArtPreset) -> void:
	_terrain(hole, art)
	for child in hole.get_children():
		if child is MeshInstance3D and child.mesh is PlaneMesh: # water
			var mat := LowPoly.material()
			mat.albedo_color = Color(art.water, art.water_alpha)
			mat.vertex_color_use_as_albedo = false
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			child.mesh.material = mat
	_pin(hole.cup, art)


## Chunky golfer at address beside the ball, facing it, club soled behind the ball.
static func golfer(art: ArtPreset, ball: Vector3, aim: Vector3, ground_y: float) -> Node3D:
	var root := Node3D.new()
	var side := (-aim).cross(Vector3.UP) # towards the golfer, as in Swing
	root.position = Vector3(ball.x, ground_y, ball.z) + side * 1.1
	root.basis = Basis(-aim, Vector3.UP, side) # faces the ball (−z)
	LowPoly.part(root, LowPoly.capsule(0.2, 0.95, 8), art.pants, Vector3(0, 0.47, 0))
	LowPoly.part(root, LowPoly.capsule(0.3, 0.9, 8), art.shirt, Vector3(0, 1.15, -0.04), Vector3(-0.25, 0, 0))
	LowPoly.part(root, LowPoly.sphere(0.22, 7, 4), art.skin, Vector3(0, 1.72, -0.12))
	LowPoly.part(root, LowPoly.cylinder(0.23, 0.23, 0.12, 8), art.cap, Vector3(0, 1.86, -0.12))
	LowPoly.part(root, LowPoly.cylinder(0.0, 0.16, 0.05, 8), art.cap, Vector3(0, 1.82, -0.32), Vector3(PI * 0.5, 0, 0))
	for x in [-0.22, 0.22]:
		LowPoly.part(root, LowPoly.capsule(0.08, 0.6, 6), art.shirt, Vector3(x * 0.6, 1.05, -0.28), Vector3(-0.55, 0, -x))
	LowPoly.part(root, LowPoly.sphere(0.09, 6, 3), art.skin, Vector3(0, 0.82, -0.42))
	var hands := Vector3(0, 0.8, -0.42)
	var head := root.basis.inverse() * (Vector3(ball.x, ground_y + 0.05, ball.z) - aim * 0.12 - root.position)
	var shaft := head - hands
	var club := LowPoly.part(root, LowPoly.cylinder(0.015, 0.015, shaft.length(), 6), art.club, hands + shaft * 0.5)
	club.basis = Basis(Quaternion(Vector3.UP, shaft.normalized()))
	LowPoly.part(root, LowPoly.box(Vector3(0.12, 0.05, 0.07)), art.club, head)
	return root


static func ball(art: ArtPreset, at: Vector3) -> MeshInstance3D:
	var view := MeshInstance3D.new()
	view.mesh = LowPoly.flat(LowPoly.sphere(0.05, 8, 5), art.ball)
	view.material_override = LowPoly.material()
	view.position = at
	return view


## Flat-shaded terrain from the hole's own data: one color per face from the palette.
static func _terrain(hole: GeneratedHole, art: ArtPreset) -> void:
	var d := hole.data
	var p := hole.params
	var n := d.size
	var m := d.metres_per_px
	var palette := {p.fairway: art.fairway, p.rough: art.rough, p.green: art.green, p.sand: art.sand,
		p.water: art.water, p.out_of_bounds: art.out_of_bounds}
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for y in n - 1:
		for x in n - 1:
			var i := y * n + x
			var on_tee := absi(x - d.tee.x) <= int(p.tee_pad_half.x) and absi(y - d.tee.y) <= int(p.tee_pad_half.y)
			var base: Color = art.tee if on_tee else palette[d.lie_px(i, p)]
			var corners := [_v(d, x, y), _v(d, x + 1, y), _v(d, x, y + 1), _v(d, x + 1, y + 1)]
			for t in 2:
				var tri := [corners[0], corners[1], corners[2]] if t == 0 else [corners[1], corners[3], corners[2]]
				var jitter := (float(Procgen.mix((i * 2 + t) & Procgen.MASK32) % 1000) / 1000.0 - 0.5) * 2.0 * art.face_jitter
				var c := base.lightened(jitter) if jitter > 0.0 else base.darkened(-jitter)
				var normal: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0]).normalized()
				for v in tri:
					verts.append(v)
					normals.append(normal)
					colors.append(c)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, LowPoly.material())
	for child in hole.get_children():
		if child is StaticBody3D and not child.has_meta("surface"):
			for view in child.get_children():
				if view is MeshInstance3D:
					view.mesh = mesh


static func _v(d: Procgen.HoleData, x: int, y: int) -> Vector3:
	return Vector3(x * d.metres_per_px, d.heights[y * d.size + x] / 100.0, y * d.metres_per_px)


static func _pin(cup: Node3D, art: ArtPreset) -> void:
	for child in cup.get_children():
		child.visible = false
	LowPoly.part(cup, LowPoly.cylinder(0.16, 0.16, 0.02, 10), art.cup, Vector3(0, 0.012, 0))
	LowPoly.part(cup, LowPoly.cylinder(0.03, 0.03, 2.6, 6), art.pole, Vector3(0, 1.3, 0))
	var cloth := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 2.55, 0), Vector3(0.9, 2.3, 0), Vector3(0, 2.05, 0),
		Vector3(0, 2.05, 0), Vector3(0.9, 2.3, 0), Vector3(0, 2.55, 0)]) # both faces
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK,
		Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD])
	var flag_colors := PackedColorArray()
	flag_colors.resize(6)
	flag_colors.fill(art.flag)
	arrays[Mesh.ARRAY_COLOR] = flag_colors
	cloth.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var view := MeshInstance3D.new()
	view.mesh = cloth
	view.material_override = LowPoly.material()
	cup.add_child(view)
