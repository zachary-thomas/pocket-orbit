class_name CloudLayer
extends Node3D
## Low-poly clouds on a slowly turning shell above the planet.
##
## The clouds don't cast real-time shadows (too costly on phones). Instead,
## when the clouds are built, their footprint is baked into an
## equirectangular coverage map: a 1024 x 512 image wrapped around the sphere
## in the layer's own un-rotated frame. The surface shaders undo the layer's
## current rotation and look up that map (see planet_lighting.gdshaderinc).

const CLUSTER_COUNT := 46
const SHADOW_WIDTH := 1024
const SHADOW_HEIGHT := 512
## Height of the cloud shell above the level-0 terrace, in metres.
const ALTITUDE := 18.0

## How fast the layer drifts around the planet: a full turn in 20 minutes.
@export var degrees_per_second := 0.3

var radius := 0.0
var angle := 0.0
var shadow_texture: ImageTexture
var material: ShaderMaterial

var _mesh_instance: MeshInstance3D


func build(planet: Planet, world_seed: int) -> void:
	radius = planet.data.radius + ALTITUDE
	if material == null:
		material = planet.surface_material.duplicate() as ShaderMaterial
		material.set_shader_parameter("receive_cloud_shadow", false)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, "clouds"])
	var md := MeshData.new()
	var blobs: Array[Vector4] = []  # xyz = direction, w = angular radius
	var white := Palette.uv("cloud")
	for c in CLUSTER_COUNT:
		var dir := _random_direction(rng)
		var frame := Transform3D(SphereMath.basis_from_up(dir, rng.randf() * TAU), dir * (radius + rng.randf_range(-2.0, 3.0)))
		var count := rng.randi_range(3, 5)
		var size := rng.randf_range(2.2, 3.8)
		for b in count:
			var along := (b - (count - 1) * 0.5) * size * 1.1
			var offset := Vector3(along, rng.randf_range(-0.3, 0.5) * size, rng.randf_range(-0.5, 0.5) * size)
			var s := size * rng.randf_range(0.75, 1.2) * (1.25 if b == int(count / 2.0) else 1.0)
			var xf := frame.translated_local(offset)
			md.add_blob(xf, Vector3(s, s * 0.72, s), white, 0)
			blobs.append(_blob(xf.origin, s * 1.1))

	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "Clouds"
		_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mesh_instance)
	_mesh_instance.mesh = md.to_mesh(material)
	material.set_shader_parameter("planet_center", planet.global_position)
	shadow_texture = _bake_shadow_map(blobs)
	planet.set_cloud_shadows(shadow_texture, radius)


func _process(delta: float) -> void:
	angle = fposmod(angle + deg_to_rad(degrees_per_second) * delta, TAU)
	rotation.y = angle
	RenderingServer.global_shader_parameter_set("cloud_rotation", angle)


static func _blob(centre: Vector3, size: float) -> Vector4:
	var dir := centre.normalized()
	return Vector4(dir.x, dir.y, dir.z, size / centre.length())


static func _random_direction(rng: RandomNumberGenerator) -> Vector3:
	var y := rng.randf_range(-1.0, 1.0)
	var around := rng.randf() * TAU
	var ring := sqrt(1.0 - y * y)
	return Vector3(ring * cos(around), y, ring * sin(around))


## Pixel (x, y) covers longitude (x + 0.5) / W * TAU - PI (measured as
## atan2(z, x), matching the shader) and colatitude (y + 0.5) / H * PI. Each
## blob only touches the pixels in its own small lat/long box.
static func _bake_shadow_map(blobs: Array[Vector4]) -> ImageTexture:
	var cover := PackedFloat32Array()
	cover.resize(SHADOW_WIDTH * SHADOW_HEIGHT)
	for blob in blobs:
		var d := Vector3(blob.x, blob.y, blob.z)
		var reach := blob.w
		var colat := acos(clampf(d.y, -1.0, 1.0))
		var lon := atan2(d.z, d.x)
		var y0 := clampi(int(floor((colat - reach) / PI * SHADOW_HEIGHT)), 0, SHADOW_HEIGHT - 1)
		var y1 := clampi(int(ceil((colat + reach) / PI * SHADOW_HEIGHT)), 0, SHADOW_HEIGHT - 1)
		var lon_reach := reach / maxf(sin(colat), 0.05)
		var x0 := int(floor((lon - lon_reach + PI) / TAU * SHADOW_WIDTH))
		var x1 := int(ceil((lon + lon_reach + PI) / TAU * SHADOW_WIDTH))
		if lon_reach >= PI:
			x0 = 0
			x1 = SHADOW_WIDTH - 1
		var cos_edge := cos(reach)
		var cos_core := cos(reach * 0.45)
		for y in range(y0, y1 + 1):
			var pixel_colat := (y + 0.5) / SHADOW_HEIGHT * PI
			var ring := sin(pixel_colat)
			var height := cos(pixel_colat)
			for xi in range(x0, x1 + 1):
				var x := posmod(xi, SHADOW_WIDTH)
				var pixel_lon := (x + 0.5) / SHADOW_WIDTH * TAU - PI
				var p := Vector3(ring * cos(pixel_lon), height, ring * sin(pixel_lon))
				var c := p.dot(d)
				if c <= cos_edge:
					continue
				var v := clampf((c - cos_edge) / (cos_core - cos_edge), 0.0, 1.0)
				v = v * v * (3.0 - 2.0 * v)
				var i := y * SHADOW_WIDTH + x
				cover[i] = maxf(cover[i], v)
	var bytes := PackedByteArray()
	bytes.resize(cover.size())
	for i in cover.size():
		bytes[i] = int(cover[i] * 255.0)
	var image := Image.create_from_data(SHADOW_WIDTH, SHADOW_HEIGHT, false, Image.FORMAT_L8, bytes)
	return ImageTexture.create_from_image(image)
