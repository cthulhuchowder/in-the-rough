class_name Scenery
extends Node3D
## A generated hole's far and wild dressing (visual only, clients; no colliders), from the hole seed:
## distant mesas — flat-topped rock stacks in banded tones — far out in the haze (Biome.mesas), and
## low soft fog bands lying in the out-of-bounds forest (Biome.ob_fog_bands), so the wild reads as
## wild from the fairway.

const MESA_RING := Vector2(1500.0, 2400.0) ## m from the hole's centre
const BAND_SIZE := Vector2(70.0, 7.0) ## m: one fog band, wide and low


func _init(hole: GeneratedHole) -> void:
	var d := hole.data
	var b := d.biome
	var rng := RandomNumberGenerator.new()
	rng.seed = Procgen.mix(d.seed ^ 0x6d657361)
	var centre := Vector3(d.size * d.metres_per_px * 0.5, 0.0, d.size * d.metres_per_px * 0.5)
	if b.mesas > 0:
		var root := Node3D.new()
		for k in b.mesas:
			var a := TAU * k / b.mesas + rng.randf_range(-0.3, 0.3)
			var at := centre + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(MESA_RING.x, MESA_RING.y)
			at.y = d.water / 100.0 - 5.0 # their feet below the map's lowest, out in the haze
			_mesa(root, at, rng, b.mesa_color)
		Flora._merge(root)
		add_child(root)
	if b.ob_fog_bands > 0:
		var spots: PackedInt32Array = Procgen._forest_spots(d, hole.params, b)[1]
		if spots.is_empty():
			return
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = Color(b.fog_color.lightened(0.15), 0.42)
		mat.albedo_texture = _soft_disc()
		mat.proximity_fade_enabled = true # no hard line where it meets the ground and trunks
		mat.proximity_fade_distance = 4.0
		mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
		mat.distance_fade_min_distance = 8.0
		mat.distance_fade_max_distance = 30.0 # fades away up close
		for k in b.ob_fog_bands:
			var cell := spots[rng.randi_range(0, spots.size() - 1)]
			var at := Vector3((cell % d.size) * d.metres_per_px, 0.0, (cell / d.size) * d.metres_per_px)
			at.y = hole.height_at(at) + BAND_SIZE.y * 0.35
			var band := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = BAND_SIZE * rng.randf_range(0.7, 1.3)
			quad.material = mat
			band.mesh = quad
			band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			band.position = at
			add_child(band)


## A mesa: three stacked, slightly narrowing rounded slabs in banded tones, the top flat.
static func _mesa(root: Node3D, at: Vector3, rng: RandomNumberGenerator, tone: Color) -> void:
	var width := rng.randf_range(160.0, 420.0)
	var depth := width * rng.randf_range(0.5, 0.9)
	var height := rng.randf_range(70.0, 170.0)
	var turn := rng.randf() * TAU
	var y := 0.0
	for tier in 3:
		var h: float = height * [0.45, 0.35, 0.2][tier]
		var scale: float = [1.0, 0.86, 0.74][tier]
		LowPoly.piece(root, LowPoly.rounded_prism(7, Vector3(width * scale, h, depth * scale), minf(width, depth) * 0.04, 1, 0.94),
			tone.darkened(0.08 * tier) if tier % 2 == 0 else tone.lightened(0.06), at + Vector3(0, y + h * 0.5, 0), Vector3(0, turn, 0))
		y += h


## A soft white disc fading to nothing at its edge (the fog band's shape).
static func _soft_disc() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex
