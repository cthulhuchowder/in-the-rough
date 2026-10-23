class_name LowPoly
## Flat-shaded, vertex-colored primitives (the project look: no textures, one color per part)
## shared by the game (GeneratedHole, Flora, the golfer) and the art mocks (ArtDresser).


static func part(parent: Node3D, mesh: Mesh, color: Color, at: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var view := MeshInstance3D.new()
	view.mesh = flat(mesh, color)
	view.material_override = material()
	view.position = at
	view.rotation = rot
	parent.add_child(view)
	return view


## Any primitive → unindexed triangles with per-face normals and one vertex color (flat shading).
static func flat(source: Mesh, color: Color) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, flat_arrays(source, color))
	return mesh


## A part that is only ever merged (merge()): a bare node holding its flat arrays, so no mesh or
## material is made for it. Placed like part(). While `dry` (a body-only build: Flora on the server)
## nothing is made at all: one shared stand-in node comes back, in no tree.
static func piece(parent: Node3D, mesh: Mesh, color: Color, at: Vector3, rot := Vector3.ZERO) -> Node3D:
	if dry:
		if _dry_node == null:
			_dry_node = Node3D.new()
		return _dry_node
	var node := Node3D.new()
	node.set_meta("flat", flat_arrays(mesh, color))
	node.position = at
	node.rotation = rot
	parent.add_child(node)
	return node


## One material for everything merged: they all share the vertex-color look.
static func shared_material() -> StandardMaterial3D:
	if _shared == null:
		_shared = material()
	return _shared


static var _shared: StandardMaterial3D
static var dry := false ## piece() makes nothing (see piece())
static var _dry_node: Node3D


## flat()'s arrays.
static func flat_arrays(source: Mesh, color: Color) -> Array:
	# A primitive generates its arrays on the CPU; surface_get_arrays would read them back off the GPU.
	var arrays: Array = source.get_mesh_arrays() if source is PrimitiveMesh \
		else (source.get_meta("src") if source.has_meta("src") else source.surface_get_arrays(0))
	var src: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var count := index.size() if not index.is_empty() else src.size()
	for k in range(0, count, 3):
		var a := src[index[k] if not index.is_empty() else k]
		var b := src[index[k + 1] if not index.is_empty() else k + 1]
		var c := src[index[k + 2] if not index.is_empty() else k + 2]
		var normal := (c - a).cross(b - a).normalized()
		verts.append_array([a, b, c])
		normals.append_array([normal, normal, normal])
	var colors := PackedColorArray()
	colors.resize(verts.size())
	colors.fill(color)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_COLOR] = colors
	return out


## Pieces (piece()) as one mesh in their parent's space: their arrays, transformed and concatenated.
static func merge(parts: Array[Node3D]) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for part in parts:
		var a: Array = part.get_meta("flat")
		var xf := part.transform
		for v: Vector3 in a[Mesh.ARRAY_VERTEX]:
			verts.append(xf * v)
		for n: Vector3 in a[Mesh.ARRAY_NORMAL]:
			normals.append((xf.basis * n).normalized())
		colors.append_array(a[Mesh.ARRAY_COLOR])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return mesh


## Matte, vertex colors read as sRGB so palette hex values land on screen as written.
static func material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	mat.metallic_specular = 0.0
	return mat


static func cylinder(top: float, bottom: float, height: float, sides: int) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	return mesh


static func capsule(radius: float, height: float, sides: int) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 2
	return mesh


static func sphere(radius: float, sides: int, rings: int) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = sides
	mesh.rings = rings
	return mesh


static func box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


## N-sided prism along +Y (centred), one flat face pointing at −Z. Radii are to the corners.
## `open_front` leaves that front face out (a vest's opening); `caps` closes top and bottom.
static func prism(sides: int, bottom: float, top: float, height: float, open_front := false, caps := true) -> ArrayMesh:
	var verts := PackedVector3Array()
	var lo := -height * 0.5
	var hi := height * 0.5
	for k in sides:
		if open_front and k == sides - 1:
			continue # the face between the last and first corners is the −Z one
		var a0 := (k + 0.5) * TAU / sides
		var a1 := (k + 1.5) * TAU / sides
		var b0 := Vector3(sin(a0) * bottom, lo, -cos(a0) * bottom)
		var b1 := Vector3(sin(a1) * bottom, lo, -cos(a1) * bottom)
		var t0 := Vector3(sin(a0) * top, hi, -cos(a0) * top)
		var t1 := Vector3(sin(a1) * top, hi, -cos(a1) * top)
		verts.append_array([b0, b1, t0, t0, b1, t1])
		if caps:
			verts.append_array([Vector3(0, hi, 0), t0, t1, Vector3(0, lo, 0), b1, b0])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.set_meta("src", arrays) # flat() reads these, not the GPU
	return mesh


## Prism with every edge rounded: an N-sided cross-section (flat face at −Z) of `size` (width,
## height, depth at the bottom), its corners filleted and its top and bottom edges rolled with
## radius `bevel` in `segments` facets each. `top_scale` tapers it. Built at real size, so the
## bevel is the same in every direction. `open_front` drops the −Z face (a vest's opening).
static func rounded_prism(sides: int, size: Vector3, bevel: float, segments: int, top_scale := 1.0,
		open_front := false, caps := true) -> ArrayMesh:
	var w := size.x
	var h := size.y
	var d := size.z
	var r := minf(bevel, minf(minf(w, d) * 0.45, h * 0.45))
	var corner := 0.5 / cos(PI / sides)
	var base: Array[Vector2] = []
	for k in sides:
		var a := (k + 0.5) * TAU / sides
		base.append(Vector2(sin(a) * corner * w, -cos(a) * corner * d))
	# Cross-section: each corner replaced by an arc; every point keeps its outward normal.
	var points := PackedVector2Array()
	var normals := PackedVector2Array()
	for k in sides:
		var v := base[k]
		var to_prev := (base[(k - 1 + sides) % sides] - v).normalized()
		var to_next := (base[(k + 1) % sides] - v).normalized()
		var half := acos(clampf(to_prev.dot(to_next), -1.0, 1.0)) * 0.5
		var centre := v + (to_prev + to_next).normalized() * (r / sin(half))
		var a1 := (v + to_prev * (r / tan(half)) - centre).angle()
		var a2 := (v + to_next * (r / tan(half)) - centre).angle()
		var sweep := wrapf(a2 - a1, -PI, PI)
		for s in segments + 1:
			var dir := Vector2.from_angle(a1 + sweep * s / segments)
			points.append(centre + dir * r)
			normals.append(dir)
	# Vertical profile: rings inset along the normals by a quarter-round at each end.
	var rings: Array[PackedVector3Array] = []
	for end in 2:
		for s in segments + 1:
			var phi := PI * 0.5 * s / segments
			var inset := r * (1.0 - sin(phi)) if end == 0 else r * (1.0 - cos(phi))
			var y := -h * 0.5 + r * (1.0 - cos(phi)) if end == 0 else h * 0.5 - r + r * sin(phi)
			var taper := lerpf(1.0, top_scale, (y + h * 0.5) / h)
			var ring := PackedVector3Array()
			for i in points.size():
				var p := (points[i] - normals[i] * inset) * taper
				ring.append(Vector3(p.x, y, p.y))
			rings.append(ring)
	var verts := PackedVector3Array()
	var n := points.size()
	for j in rings.size() - 1:
		var lo := rings[j]
		var hi := rings[j + 1]
		for i in n:
			if open_front and i == n - 1:
				continue # the segment from the last point back to the first is the −Z face
			var i1 := (i + 1) % n
			_tri(verts, lo[i], lo[i1], hi[i])
			_tri(verts, hi[i], lo[i1], hi[i1])
	if caps:
		var bottom := rings[0]
		var top := rings[rings.size() - 1]
		for i in n:
			var i1 := (i + 1) % n
			_tri(verts, Vector3(0, top[i].y, 0), top[i], top[i1])
			_tri(verts, Vector3(0, bottom[i].y, 0), bottom[i1], bottom[i])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.set_meta("src", arrays) # flat() reads these, not the GPU
	return mesh


## Append a triangle unless it is degenerate (collapsed fillet points at a cap ring).
static func _tri(verts: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	if (c - a).cross(b - a).length_squared() > 1e-12:
		verts.append_array([a, b, c])
