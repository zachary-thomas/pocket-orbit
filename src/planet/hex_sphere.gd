class_name HexSphere
extends RefCounted
## A Goldberg polyhedron: a sphere tiled with hexagons plus exactly 12 pentagons.
##
## It is built as the dual of a subdivided icosahedron:
## 1. Split each of the icosahedron's 20 triangles into frequency^2 smaller
##    triangles and push every vertex out onto the unit sphere.
## 2. Every vertex of that triangle mesh becomes one tile. The 12 original
##    icosahedron corners touch 5 triangles and become pentagons; every other
##    vertex touches 6 and becomes a hexagon. Tile count = 10 * frequency^2 + 2
##    (frequency 16 gives 2,562 tiles).
## 3. A tile's corners are the centres of the triangles around its vertex, so
##    two neighbouring tiles always share exactly the two corners of the edge
##    between them and the tiling has no gaps.
##
## Everything is a unit direction from the planet centre. Corners are stored
## counter-clockwise as seen from outside the planet. Generation uses no
## randomness, so the same frequency always gives the same tile numbering.

var frequency: int
## Unit direction to each tile's centre.
var centers := PackedVector3Array()
## Tile t's corners are corners[corner_start[t] .. corner_start[t + 1]).
var corner_start := PackedInt32Array()
var corners := PackedVector3Array()
## Parallel to `corners`: the tile on the other side of the edge from corner k
## to corner k + 1.
var edge_neighbors := PackedInt32Array()


func _init(p_frequency: int = 16) -> void:
	frequency = p_frequency
	_build()


func tile_count() -> int:
	return centers.size()


func corner_count(tile: int) -> int:
	return corner_start[tile + 1] - corner_start[tile]


func is_pentagon(tile: int) -> bool:
	return corner_count(tile) == 5


func tile_corners(tile: int) -> PackedVector3Array:
	return corners.slice(corner_start[tile], corner_start[tile + 1])


func neighbors(tile: int) -> PackedInt32Array:
	return edge_neighbors.slice(corner_start[tile], corner_start[tile + 1])


## Returns the tile containing `dir`. Starting from `hint` (the tile the caller
## was on last frame) this is a couple of dot products; from far away it walks
## across the sphere tile by tile.
func find_tile(dir: Vector3, hint: int = 0) -> int:
	var tile := clampi(hint, 0, centers.size() - 1)
	var best := centers[tile].dot(dir)
	# Greedy walk: hop to whichever neighbour's centre is closer until none is.
	while true:
		var next := tile
		for i in range(corner_start[tile], corner_start[tile + 1]):
			var d := centers[edge_neighbors[i]].dot(dir)
			if d > best:
				best = d
				next = edge_neighbors[i]
		if next == tile:
			break
		tile = next
	# The nearest centre almost always owns the point, but tile edges aren't
	# exactly half-way between centres, so confirm against the real polygon.
	if contains(tile, dir):
		return tile
	for i in range(corner_start[tile], corner_start[tile + 1]):
		if contains(edge_neighbors[i], dir):
			return edge_neighbors[i]
	return tile


## True when `dir` lies inside the tile's polygon. Each edge from corner a to b
## is a great-circle arc; the plane through the centre, a and b splits the
## sphere, and cross(a, b) points to the side the tile is on (corners are
## counter-clockwise from outside).
func contains(tile: int, dir: Vector3) -> bool:
	var s := corner_start[tile]
	var e := corner_start[tile + 1]
	for i in range(s, e):
		var a := corners[i]
		var b := corners[s if i + 1 == e else i + 1]
		if a.cross(b).dot(dir) < -1e-7:
			return false
	return dir.dot(centers[tile]) > 0.0


func _build() -> void:
	var ico := icosahedron()
	var ico_verts: PackedVector3Array = ico[0]
	var ico_faces: Array = ico[1]
	var n := frequency
	var vertex_of_key := {}
	var tris := PackedInt32Array()

	# Step 1: subdivide. Point (i, j) on face (a, b, c) sits at
	# a * (n - i - j) + b * i + c * j, then gets normalised onto the sphere.
	for f in ico_faces.size():
		var face: Vector3i = ico_faces[f]
		var a := ico_verts[face.x]
		var b := ico_verts[face.y]
		var c := ico_verts[face.z]
		var grid := {}
		for i in range(n + 1):
			for j in range(n + 1 - i):
				var k := n - i - j
				# Points on shared edges and corners get the same key from every
				# face that touches them, so they become one vertex.
				var key := _point_key(f, face, k, i, j)
				var id: int
				if vertex_of_key.has(key):
					id = vertex_of_key[key]
				else:
					id = centers.size()
					centers.append((a * float(k) + b * float(i) + c * float(j)).normalized())
					vertex_of_key[key] = id
				grid[Vector2i(i, j)] = id
		for i in range(n):
			for j in range(n - i):
				_add_tri(tris, grid[Vector2i(i, j)], grid[Vector2i(i + 1, j)], grid[Vector2i(i, j + 1)])
				if i + j < n - 1:
					_add_tri(tris, grid[Vector2i(i + 1, j)], grid[Vector2i(i + 1, j + 1)], grid[Vector2i(i, j + 1)])

	# Step 2: the dual. Each triangle's centre becomes a tile corner.
	var tri_count := tris.size() / 3
	var tri_center := PackedVector3Array()
	tri_center.resize(tri_count)
	var incident: Array[PackedInt32Array] = []
	incident.resize(centers.size())
	for v in centers.size():
		incident[v] = PackedInt32Array()
	for t in tri_count:
		var ia := tris[t * 3]
		var ib := tris[t * 3 + 1]
		var ic := tris[t * 3 + 2]
		tri_center[t] = (centers[ia] + centers[ib] + centers[ic]).normalized()
		incident[ia].append(t)
		incident[ib].append(t)
		incident[ic].append(t)

	# Step 3: order each vertex's triangles counter-clockwise around it. With
	# axes (x, y, normal) right-handed, increasing atan2(y, x) is counter-
	# clockwise when seen from outside.
	for v in centers.size():
		var normal := centers[v]
		var axis_x := SphereMath.any_perpendicular(normal)
		var axis_y := normal.cross(axis_x)
		var ring: Array = []
		for t in incident[v]:
			var d := tri_center[t] - normal
			ring.append(Vector2(atan2(d.dot(axis_y), d.dot(axis_x)), t))
		ring.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
		corner_start.append(corners.size())
		for k in ring.size():
			var t_a := int(ring[k].y)
			var t_b := int(ring[(k + 1) % ring.size()].y)
			corners.append(tri_center[t_a])
			# Consecutive triangles share the edge (v, w); w is the neighbour
			# across the tile edge between their two centres.
			edge_neighbors.append(_shared_other(tris, t_a, t_b, v))
	corner_start.append(corners.size())


## Stores a triangle wound counter-clockwise as seen from outside the sphere.
func _add_tri(tris: PackedInt32Array, ia: int, ib: int, ic: int) -> void:
	var pa := centers[ia]
	var pb := centers[ib]
	var pc := centers[ic]
	if (pb - pa).cross(pc - pa).dot(pa + pb + pc) < 0.0:
		tris.append_array([ia, ic, ib])
	else:
		tris.append_array([ia, ib, ic])


static func _shared_other(tris: PackedInt32Array, t_a: int, t_b: int, v: int) -> int:
	for i in 3:
		var candidate := tris[t_a * 3 + i]
		if candidate == v:
			continue
		for j in 3:
			if tris[t_b * 3 + j] == candidate:
				return candidate
	push_error("HexSphere: triangles %d and %d share no edge" % [t_a, t_b])
	return v


## A key that is identical for a point no matter which face generated it.
## Corners are keyed by icosahedron vertex, edge points by the edge's two
## vertices plus the weight toward the lower one, interior points by face.
static func _point_key(face_index: int, face: Vector3i, wa: int, wb: int, wc: int) -> Vector3i:
	var used: Array[Vector2i] = []
	if wa > 0:
		used.append(Vector2i(face.x, wa))
	if wb > 0:
		used.append(Vector2i(face.y, wb))
	if wc > 0:
		used.append(Vector2i(face.z, wc))
	match used.size():
		1:
			return Vector3i(used[0].x, -1, -1)
		2:
			var p := used[0]
			var q := used[1]
			if p.x > q.x:
				var swap := p
				p = q
				q = swap
			return Vector3i(p.x, q.x, p.y)
		_:
			return Vector3i(-1 - face_index, wb, wc)


## The 12 vertices (unit length) and 20 faces of a regular icosahedron.
static func icosahedron() -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var raw := [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]
	var verts := PackedVector3Array()
	for p: Vector3 in raw:
		verts.append(p.normalized())
	var faces: Array[Vector3i] = [
		Vector3i(0, 11, 5), Vector3i(0, 5, 1), Vector3i(0, 1, 7), Vector3i(0, 7, 10), Vector3i(0, 10, 11),
		Vector3i(1, 5, 9), Vector3i(5, 11, 4), Vector3i(11, 10, 2), Vector3i(10, 7, 6), Vector3i(7, 1, 8),
		Vector3i(3, 9, 4), Vector3i(3, 4, 2), Vector3i(3, 2, 6), Vector3i(3, 6, 8), Vector3i(3, 8, 9),
		Vector3i(4, 9, 5), Vector3i(2, 4, 11), Vector3i(6, 2, 10), Vector3i(8, 6, 7), Vector3i(9, 8, 1),
	]
	return [verts, faces]
