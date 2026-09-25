class_name PropLibrary
extends RefCounted
## Loads the models built by tools/blender/build_assets.py and hands out their
## triangles and meshes: PlanetMesher merges the simple versions into chunk
## meshes, and Planet draws the full-detail ones with GPU instancing.
##
## Each model comes in two detail levels: 0 (close up) and 1 (far away, much
## simpler). Loaded arrays are cached, so each file is read once.

const MODEL_DIR := "res://assets/models/"

static var _cache := {}
static var _meshes := {}


## Surface arrays (Mesh.ARRAY_*) of a model, e.g. arrays("tree_round", 1).
static func arrays(model: String, lod: int = 0) -> Array:
	var path := MODEL_DIR + model + ("" if lod == 0 else "_lod1") + ".glb"
	if _cache.has(path):
		return _cache[path]
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("PropLibrary: can't load %s (run tools/blender/build_assets.py, then import)" % path)
		_cache[path] = []
		return []
	var root := scene.instantiate()
	var instance := _find_mesh(root)
	var result: Array = []
	if instance:
		result = instance.mesh.surface_get_arrays(0)
		# Bake the node's own transform in, in case the exporter left one.
		var xf := instance.transform
		if not xf.is_equal_approx(Transform3D.IDENTITY):
			var md := MeshData.new()
			md.add_arrays(xf, result)
			result = md.to_arrays()
	root.free()
	_cache[path] = result
	return result


@warning_ignore("integer_division")
static func triangle_count(model: String, lod: int = 0) -> int:
	var a := arrays(model, lod)
	if a.is_empty():
		return 0
	var indices = a[Mesh.ARRAY_INDEX]
	return (indices.size() if indices != null else a[Mesh.ARRAY_VERTEX].size()) / 3


## A model as a mesh using `material`, for drawing with instancing. Cached per
## model, detail level and material.
static func mesh(model: String, lod: int, material: Material) -> ArrayMesh:
	var key := "%s#%d#%d" % [model, lod, material.get_instance_id()]
	if _meshes.has(key):
		return _meshes[key]
	var result := ArrayMesh.new()
	var a := arrays(model, lod)
	if not a.is_empty():
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		result.surface_set_material(0, material)
	_meshes[key] = result
	return result


static func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_mesh(child)
		if found:
			return found
	return null
