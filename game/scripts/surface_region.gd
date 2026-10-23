class_name SurfaceRegion
extends MeshInstance3D
## Flat patch of one surface. Node scale sets its size: unit square, or unit circle if ellipse.

@export var surface: SurfaceData
@export var ellipse := false


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = surface.color
	if ellipse:
		var disc := CylinderMesh.new()
		disc.top_radius = 0.5
		disc.bottom_radius = 0.5
		disc.height = 0.001
		disc.material = mat
		mesh = disc
	else:
		var quad := PlaneMesh.new()
		quad.size = Vector2.ONE
		quad.material = mat
		mesh = quad


func contains(p: Vector3) -> bool:
	var l := to_local(p)
	if ellipse:
		return Vector2(l.x, l.z).length() <= 0.5
	return absf(l.x) <= 0.5 and absf(l.z) <= 0.5
