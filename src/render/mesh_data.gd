class_name MeshData
extends RefCounted
## Growable vertex arrays for building low-poly meshes in code, plus a few
## primitive shapes (box, prism/cone, blob) for placeholder models.
##
## Every triangle takes the direction it should face, and the winding is fixed
## up to match, so callers never have to think about vertex order. Godot treats
## clockwise triangles as front-facing, so that's the order they're stored in.
## All colour comes from Palette swatch UVs.

const FRONT_IS_CLOCKWISE := true

var vertices := PackedVector3Array()
var normals := PackedVector3Array()
var uvs := PackedVector2Array()

static var _blob_cache := {}


func is_empty() -> bool:
	return vertices.is_empty()


@warning_ignore("integer_division")
func triangle_count() -> int:
	return vertices.size() / 3


## Triangle with its own normal at each corner (for smooth shading).
func add_tri_smooth(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, uv: Vector2) -> void:
	# (b - a) x (c - a) points toward whoever sees a, b, c counter-clockwise.
	if (b - a).cross(c - a).dot(na + nb + nc) < 0.0:
		var p := b
		b = c
		c = p
		var q := nb
		nb = nc
		nc = q
	_push(a, na, uv)
	if FRONT_IS_CLOCKWISE:
		_push(c, nc, uv)
		_push(b, nb, uv)
	else:
		_push(b, nb, uv)
		_push(c, nc, uv)


## Flat-shaded triangle facing `normal`.
func add_tri(a: Vector3, b: Vector3, c: Vector3, normal: Vector3, uv: Vector2) -> void:
	add_tri_smooth(a, b, c, normal, normal, normal, uv)


## Flat-shaded triangle using its true face normal, flipped if needed so it
## faces roughly along `outward`.
func add_tri_facing(a: Vector3, b: Vector3, c: Vector3, outward: Vector3, uv: Vector2) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-14:
		return
	n = n.normalized()
	if n.dot(outward) < 0.0:
		n = -n
	add_tri(a, b, c, n, uv)


## Quad a-b-c-d (corners in order around its edge) facing `normal`.
func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, uv: Vector2) -> void:
	add_tri(a, b, c, normal, uv)
	add_tri(a, c, d, normal, uv)


## Box of `size`, centred on `xf`'s origin.
func add_box(xf: Transform3D, size: Vector3, uv: Vector2) -> void:
	var h := size * 0.5
	for axis in 3:
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for side in [-1.0, 1.0]:
			var loop: Array[Vector3] = []
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var p := Vector3.ZERO
				p[axis] = h[axis] * side
				p[u] = h[u] * corner.x
				p[v] = h[v] * corner.y
				loop.append(xf * p)
			var n := Vector3.ZERO
			n[axis] = side
			add_quad(loop[0], loop[1], loop[2], loop[3], (xf.basis * n).normalized(), uv)


## Upright prism from y = 0 to y = height with flat sides. A top radius of 0
## makes a cone. Low side counts give the faceted low-poly look.
func add_prism(xf: Transform3D, bottom_radius: float, top_radius: float, height: float, sides: int, uv: Vector2) -> void:
	var bottom: Array[Vector3] = []
	var top: Array[Vector3] = []
	for i in sides:
		var angle := TAU * i / sides
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		bottom.append(xf * (dir * bottom_radius))
		top.append(xf * (dir * top_radius + Vector3(0, height, 0)))
	var middle := xf * Vector3(0, height * 0.5, 0)
	var apex := xf * Vector3(0, height, 0)
	var base := xf * Vector3.ZERO
	var up := xf.basis.y.normalized()
	for i in sides:
		var j := (i + 1) % sides
		if top_radius <= 0.001:
			add_tri_facing(bottom[i], bottom[j], apex, (bottom[i] + bottom[j] + apex) / 3.0 - middle, uv)
		else:
			var centre := (bottom[i] + bottom[j] + top[i] + top[j]) * 0.25
			add_tri_facing(bottom[i], bottom[j], top[j], centre - middle, uv)
			add_tri_facing(bottom[i], top[j], top[i], centre - middle, uv)
			add_tri(apex, top[i], top[j], up, uv)
		add_tri(base, bottom[j], bottom[i], -up, uv)


## Rounded lump (an icosphere) with per-axis radii. detail 0 = 20 faces,
## 1 = 80 faces. Used for tree canopies, rocks, bushes and clouds.
func add_blob(xf: Transform3D, radii: Vector3, uv: Vector2, detail: int = 0) -> void:
	var tris := _blob_triangles(detail)
	for i in range(0, tris.size(), 3):
		var a := xf * (tris[i] * radii)
		var b := xf * (tris[i + 1] * radii)
		var c := xf * (tris[i + 2] * radii)
		add_tri_facing(a, b, c, (a + b + c) / 3.0 - xf.origin, uv)


func to_mesh(material: Material) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


func _push(p: Vector3, n: Vector3, uv: Vector2) -> void:
	vertices.append(p)
	normals.append(n)
	uvs.append(uv)


## Unit icosphere as a flat list of triangle corners.
static func _blob_triangles(detail: int) -> PackedVector3Array:
	if _blob_cache.has(detail):
		return _blob_cache[detail]
	var ico := HexSphere.icosahedron()
	var verts: PackedVector3Array = ico[0]
	var tris := PackedVector3Array()
	for face: Vector3i in ico[1]:
		tris.append_array([verts[face.x], verts[face.y], verts[face.z]])
	for _level in detail:
		var finer := PackedVector3Array()
		for i in range(0, tris.size(), 3):
			var a := tris[i]
			var b := tris[i + 1]
			var c := tris[i + 2]
			var ab := (a + b).normalized()
			var bc := (b + c).normalized()
			var ca := (c + a).normalized()
			finer.append_array([a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca])
		tris = finer
	_blob_cache[detail] = tris
	return tris
