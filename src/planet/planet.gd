class_name Planet
extends Node3D
## A planet in the scene: terrain chunks, ocean, atmosphere and night lamps,
## plus the queries movement needs (which tile is here, how high is it).
##
## All the decisions live in PlanetData; this node only draws them. The planet
## centre is this node's position.

signal generated

const SURFACE_SHADER := preload("res://shaders/planet_surface.gdshader")
const WATER_SHADER := preload("res://shaders/water.gdshader")
const ATMOSPHERE_SHADER := preload("res://shaders/atmosphere.gdshader")
## Tallest thing above sea level (mountain terrace plus a tree), for horizon culling.
const TALLEST_OBJECT := 12.0
## Camera distance (metres, to a chunk's centre) where props switch from full
## detail to their simple far-away versions.
const DETAIL_DISTANCE := 60.0

@export var frequency := 16
## Radius of the level-0 terrace. At the player's 4 m/s, 134 m makes a walk
## around the equator take about 3.5 minutes (2 * PI * 134 / 4 = 210 s).
@export var radius := 134.0
@export var level_height := 1.0
## Atmosphere shell radius as a multiple of the planet radius.
@export var atmosphere_scale := 1.22

var data: PlanetData
var surface_material: ShaderMaterial
## The surface material for close-up props: they dissolve (dithered) where
## they stand between the camera and `focus`, so trees never hide the player.
var prop_material: ShaderMaterial
## For characters, items and anything else that shouldn't follow the
## seasons (same look, no autumn leaves or snow).
var object_material: ShaderMaterial
## What the camera is looking at, usually the player.
var focus: Node3D
var water_material: ShaderMaterial
var atmosphere_material: ShaderMaterial
var atmosphere_radius := 0.0

var _content: Node3D
var _chunks: Array[Node3D] = []
var _chunk_dirs := PackedVector3Array()
var _chunk_radii := PackedFloat32Array()


func _init() -> void:
	var palette := Palette.make_texture()
	surface_material = ShaderMaterial.new()
	surface_material.shader = SURFACE_SHADER
	surface_material.set_shader_parameter("palette", palette)
	object_material = surface_material.duplicate()
	surface_material.set_shader_parameter("seasonal", true)
	prop_material = surface_material.duplicate()
	prop_material.set_shader_parameter("fade_occluders", true)
	water_material = ShaderMaterial.new()
	water_material.shader = WATER_SHADER
	atmosphere_material = ShaderMaterial.new()
	atmosphere_material.shader = ATMOSPHERE_SHADER
	atmosphere_material.render_priority = 10


func generate(world_seed: int) -> void:
	if _content:
		remove_child(_content)
		_content.queue_free()
	_content = Node3D.new()
	_content.name = "Content"
	add_child(_content)

	data = PlanetGenerator.generate(world_seed, frequency, radius, level_height)
	atmosphere_radius = radius * atmosphere_scale
	var built := PlanetMesher.build(data)
	_chunks.clear()
	_chunk_dirs = built["chunk_dirs"]
	_chunk_radii = built["chunk_radii"]
	var terrain: Array[MeshData] = built["terrain"]
	var near: Array = built["near"]
	var far: Array[MeshData] = built["far"]
	for i in terrain.size():
		var chunk := Node3D.new()
		chunk.name = "Chunk%d" % i
		_content.add_child(chunk)
		_chunks.append(chunk)
		_add_chunk_mesh(chunk, "Terrain", terrain[i], 0.0, 0.0)
		_add_chunk_mesh(chunk, "NearShapes", near[i].shapes, 0.0, DETAIL_DISTANCE)
		for model: String in near[i].placements:
			_add_instanced(chunk, model, near[i].placements[model])
		_add_chunk_mesh(chunk, "Far", far[i], DETAIL_DISTANCE, 0.0)
	for lamp_position: Vector3 in built["lamps"]:
		_add_lamp_light(lamp_position)
	_add_water()
	_add_atmosphere()
	for material: ShaderMaterial in [surface_material, prop_material, object_material, water_material]:
		material.set_shader_parameter("planet_center", global_position)
	generated.emit()


## Called by the cloud layer once it knows where its clouds are.
func set_cloud_shadows(shadow_map: Texture2D, cloud_radius: float) -> void:
	for material: ShaderMaterial in [surface_material, prop_material, object_material, water_material]:
		material.set_shader_parameter("cloud_shadow_map", shadow_map)
		material.set_shader_parameter("cloud_radius", cloud_radius)


func _process(_delta: float) -> void:
	_cull_behind_horizon()
	if focus:
		# Aim at the chest, so the head and body both stay clear.
		prop_material.set_shader_parameter("focus_position", focus.global_position + (focus.global_position - global_position).normalized() * 0.9)


## Hides chunks that are entirely over the horizon. The renderer's frustum
## culling can't do this: the far side of the planet is inside the view, just
## hidden behind the near side. From the ground this skips most of the planet.
##
## From a camera at distance d, the planet's surface is visible up to the angle
## acos(r_low / d) from the point under the camera, and anything up to
## TALLEST_OBJECT metres high can peek over the horizon from a further
## acos(r_low / (r_low + TALLEST_OBJECT)). A chunk is kept if any part of it
## could be within that angle.
func _cull_behind_horizon() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or data == null:
		return
	var from_center := camera.global_position - global_position
	var d := from_center.length()
	var r_low := data.sea_level_radius
	if d <= r_low:
		return
	var view_dir := from_center / d
	var reach := acos(r_low / d) + acos(r_low / (r_low + TALLEST_OBJECT))
	for i in _chunks.size():
		_chunks[i].visible = view_dir.angle_to(_chunk_dirs[i]) < reach + _chunk_radii[i]


# --- Queries -------------------------------------------------------------------

func up_at(world_position: Vector3) -> Vector3:
	return (world_position - global_position).normalized()


func find_tile(world_position: Vector3, hint: int = 0) -> int:
	return data.sphere.find_tile(up_at(world_position), hint)


func find_tile_dir(dir: Vector3, hint: int = 0) -> int:
	return data.sphere.find_tile(dir, hint)


## Distance from the centre to the top of the tile.
func ground_radius(tile: int) -> float:
	return data.top_radius(tile)


func is_walkable(tile: int) -> bool:
	return not data.is_water(tile)


func tile_center(tile: int) -> Vector3:
	return data.sphere.centers[tile]


# --- Visual pieces ---------------------------------------------------------

## A chunk mesh, drawn only between `begin` and `end` metres from the camera
## (0 = no limit).
func _add_chunk_mesh(chunk: Node3D, part: String, md: MeshData, begin: float, end: float) -> void:
	if md.is_empty():
		return
	var instance := MeshInstance3D.new()
	instance.name = part
	instance.mesh = md.to_mesh(surface_material)
	instance.visibility_range_begin = begin
	instance.visibility_range_end = end
	if begin > 0.0:
		instance.visibility_range_begin_margin = 5.0
	if end > 0.0:
		instance.visibility_range_end_margin = 5.0
	chunk.add_child(instance)


## Full-detail copies of one model, drawn with GPU instancing while the
## camera is within DETAIL_DISTANCE.
func _add_instanced(chunk: Node3D, model: String, placements: Array) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = PropLibrary.mesh(model, 0, prop_material)
	multimesh.instance_count = placements.size()
	for i in placements.size():
		multimesh.set_instance_transform(i, placements[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = model
	instance.multimesh = multimesh
	instance.visibility_range_end = DETAIL_DISTANCE
	instance.visibility_range_end_margin = 5.0
	chunk.add_child(instance)


func _add_lamp_light(at: Vector3) -> void:
	var light := OmniLight3D.new()
	light.position = at
	light.omni_range = 6.0
	light.light_energy = 0.9
	light.light_color = Color("ffd59a")
	light.shadow_enabled = false
	light.add_to_group("night_lights")
	_content.add_child(light)


func _add_water() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = data.sea_level_radius
	sphere.height = data.sea_level_radius * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	var water := MeshInstance3D.new()
	water.name = "Ocean"
	water.mesh = sphere
	water.material_override = water_material
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_content.add_child(water)


func _add_atmosphere() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = atmosphere_radius
	sphere.height = atmosphere_radius * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	var shell := MeshInstance3D.new()
	shell.name = "Atmosphere"
	shell.mesh = sphere
	shell.material_override = atmosphere_material
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	atmosphere_material.set_shader_parameter("planet_radius", data.sea_level_radius)
	atmosphere_material.set_shader_parameter("atmosphere_radius", atmosphere_radius)
	_content.add_child(shell)
