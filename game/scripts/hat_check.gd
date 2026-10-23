class_name HatCheck
## Does a golfer's hat sit on the head and enclose its top? From every head vertex in the top
## `depth` of the head, rays straight up and straight out (sideways from the head's axis) must each
## meet the hat. Head-joint space; the rig must be in the tree. Used by novelty_test.

static func report(rig: GolferRig, depth := 0.04) -> Dictionary:
	var head := rig._head
	var to_head := head.global_transform.affine_inverse()
	var tris := PackedVector3Array()
	var views: Array = rig._hat_parts.duplicate()
	if rig.hat_toy:
		views.append_array(rig.hat_toy.find_children("*", "MeshInstance3D", true, false))
	for view: MeshInstance3D in views:
		var xf := to_head * view.global_transform
		for v: Vector3 in view.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			tris.append(xf * v)
	var skull: MeshInstance3D = head.get_child(0)
	var top := -INF
	var verts: PackedVector3Array = skull.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for k in verts.size():
		verts[k] = skull.transform * verts[k]
		top = maxf(top, verts[k].y)
	var checked := 0
	var bare := 0
	var worst := Vector3.ZERO
	var seen := {}
	for v in verts:
		if v.y < top - depth or seen.has(v):
			continue
		seen[v] = true
		checked += 1
		var out := Vector3(v.x, 0.0, v.z).normalized()
		if not (_hits(tris, v, Vector3.UP) and (out == Vector3.ZERO or _hits(tris, v, out))):
			bare += 1
			worst = v
	return {checked = checked, bare = bare, at = worst}


static func _hits(tris: PackedVector3Array, from: Vector3, dir: Vector3) -> bool:
	for k in range(0, tris.size(), 3):
		if Geometry3D.ray_intersects_triangle(from, dir, tris[k], tris[k + 1], tris[k + 2]) != null:
			return true
	return false
