class_name PlanetMesher
extends RefCounted
## Turns PlanetData into meshes: terraced terrain plus the props PropPlacer
## decided on (trees, rocks, shrines and the village).
##
## The planet is split into 80 chunks, so the renderer can skip chunks that
## are off screen or over the horizon, and so each stays under the Mobile
## renderer's limit of 8 lights per mesh. Every chunk has:
## - a terrain mesh
## - near props: where each full-detail model stands, drawn with GPU
##   instancing when the camera is close (one copy of each model in memory,
##   one draw call per model per chunk), plus a mesh of small ground detail
##   (grass tufts, flowers, pebbles, stepping stones)
## - far props: the simple (lod1) version of every prop merged into one mesh,
##   drawn otherwise
##
## Terrain: each tile's top is flat at its level's radius. Colours are blended
## across tile borders (each corner averages the tiles meeting there), so
## biomes fade into each other instead of forming a mosaic of hexagons. Where
## a neighbour is lower, a rocky wall drops to it: a grassy lip at the top,
## then rock whose in-between rows are pushed around by noise, darkening
## toward the bottom. The ground at the foot of a cliff is darkened too, like
## the soft contact shadows in the concept art.

const LIP_HEIGHT := 0.18
## Ground colour at the foot of a higher terrace (fake ambient occlusion).
const CLIFF_FOOT_SHADE := 0.72
## How far the rocky wall rows are pushed around, in metres.
const ROCK_JITTER := 0.22
## Share of the way from a tile's centre to its edge where colour blending starts.
const BLEND_START := 0.3

static var _rock_noise: FastNoiseLite


static func build(data: PlanetData) -> Dictionary:
	var sphere := data.sphere
	var chunk_dirs := chunk_directions()
	var terrain: Array[MeshData] = []
	var near: Array[Props] = []
	var far: Array[MeshData] = []
	for i in chunk_dirs.size():
		terrain.append(MeshData.new())
		near.append(Props.new())
		far.append(MeshData.new())
	var chunk_radii := PackedFloat32Array()
	chunk_radii.resize(chunk_dirs.size())
	var chunk_of := PackedInt32Array()
	chunk_of.resize(sphere.tile_count())

	_rock_noise = FastNoiseLite.new()
	_rock_noise.seed = data.world_seed + 404
	_rock_noise.frequency = 0.6
	var top_colors := _top_colors(data)
	for t in sphere.tile_count():
		var chunk := nearest_direction(chunk_dirs, sphere.centers[t])
		chunk_of[t] = chunk
		# Angular size of the chunk: its farthest tile corner from the centre.
		for corner in sphere.tile_corners(t):
			chunk_radii[chunk] = maxf(chunk_radii[chunk], chunk_dirs[chunk].angle_to(corner))
		_add_tile(terrain[chunk], data, t, top_colors)
		_add_ground_detail(near[chunk].shapes, data, t)

	for prop: Dictionary in data.props:
		# The shop changes as it's upgraded, so the village draws it (Village).
		if prop.get("dynamic", false):
			continue
		var chunk := chunk_of[prop["tile"]]
		add_prop(near[chunk], far[chunk], prop["model"], prop["xf"])
	_add_paths(near, chunk_of, data)

	return {
		"terrain": terrain, "near": near, "far": far,
		"chunk_dirs": chunk_dirs, "chunk_radii": chunk_radii, "lamps": data.village.get("lamps", []),
	}


## 80 evenly spread directions: the centres of an icosahedron's faces after
## splitting each face into 4.
static func chunk_directions() -> PackedVector3Array:
	var ico := HexSphere.icosahedron()
	var v: PackedVector3Array = ico[0]
	var dirs := PackedVector3Array()
	for face: Vector3i in ico[1]:
		var a := v[face.x]
		var b := v[face.y]
		var c := v[face.z]
		var ab := (a + b).normalized()
		var bc := (b + c).normalized()
		var ca := (c + a).normalized()
		for tri: Array in [[a, ab, ca], [b, bc, ab], [c, ca, bc], [ab, bc, ca]]:
			dirs.append((tri[0] + tri[1] + tri[2]).normalized())
	return dirs


static func nearest_direction(dirs: PackedVector3Array, dir: Vector3) -> int:
	var best := 0
	var best_dot := -2.0
	for i in dirs.size():
		var d := dirs[i].dot(dir)
		if d > best_dot:
			best_dot = d
			best = i
	return best


# --- Terrain -----------------------------------------------------------------

static func _top_colors(data: PlanetData) -> PackedColorArray:
	var colors := PackedColorArray()
	colors.resize(data.tile_count())
	for t in data.tile_count():
		colors[t] = Palette.linear(_top_swatch(data, t))
	return colors


static func _add_tile(md: MeshData, data: PlanetData, t: int, top_colors: PackedColorArray) -> void:
	var sphere := data.sphere
	var s := sphere.corner_start[t]
	var e := sphere.corner_start[t + 1]
	var count := e - s
	var center := sphere.centers[t]
	var r := data.top_radius(t)
	var own := top_colors[t]
	var white := Palette.uv("white")

	# Colour at each corner: the average of the tiles meeting there that are on
	# this level, darkened if a higher terrace rises beside it.
	var corner_colors := PackedColorArray()
	for k in count:
		var before := sphere.edge_neighbors[s + (k - 1 + count) % count]
		var after := sphere.edge_neighbors[s + k]
		var sum := own
		var n := 1
		var shaded := false
		for other in [before, after]:
			if data.level[other] == data.level[t]:
				sum += top_colors[other]
				n += 1
			elif data.level[other] > data.level[t]:
				shaded = true
		var c := sum / n
		if shaded:
			c = c * CLIFF_FOOT_SHADE
		c.a = 1.0
		corner_colors.append(c)

	for k in count:
		var j := (k + 1) % count
		var a := sphere.corners[s + k]
		var b := sphere.corners[s + j]
		# Inner triangle in the tile's own colour, outer band blending to the
		# corners. Normals point straight out so a terrace shades as one piece.
		var ma := center.lerp(a, BLEND_START).normalized()
		var mb := center.lerp(b, BLEND_START).normalized()
		md.add_tri_shaded(center * r, ma * r, mb * r, center, ma, mb, own, own, own, white)
		md.add_tri_shaded(ma * r, a * r, b * r, ma, a, b, own, corner_colors[k], corner_colors[j], white)
		md.add_tri_shaded(ma * r, b * r, mb * r, ma, b, mb, own, corner_colors[j], own, white)

		var nb := sphere.edge_neighbors[s + k]
		if data.level[nb] < data.level[t]:
			_add_wall(md, data, t, a, b, r, data.top_radius(nb), corner_colors[k], corner_colors[j])


## Rocky wall under the edge a-b, from this tile's top (radius `top`) down to
## the neighbour's (`bottom`). Rows sit at fixed radii (the lip, then every
## half level), and each row's corner points depend only on where they are,
## so walls meeting at a corner line up exactly.
static func _add_wall(md: MeshData, data: PlanetData, t: int, a: Vector3, b: Vector3,
		top: float, bottom: float, color_a: Color, color_b: Color) -> void:
	var outward := -a.cross(b).normalized()
	var rock := Palette.linear(Biome.CLIFF_SWATCH[data.biome[t]])
	var white := Palette.uv("white")
	var rows: Array[float] = [top, top - minf(LIP_HEIGHT, (top - bottom) * 0.3)]
	var step := data.level_height * 0.5
	var radius := top - step
	while radius > bottom + 0.01:
		if radius < rows[-1] - 0.05:
			rows.append(radius)
		radius -= step
	rows.append(bottom)

	var span := maxf(top - bottom, 0.01)
	for i in rows.size() - 1:
		var r0 := rows[i]
		var r1 := rows[i + 1]
		var p := [_wall_point(a, r0, data), _wall_point(b, r0, data), _wall_point(b, r1, data), _wall_point(a, r1, data)]
		var top_a: Color
		var top_b: Color
		var low_a: Color
		var low_b: Color
		if i == 0:
			# The lip: ground colour curling over the edge.
			top_a = color_a
			top_b = color_b
			low_a = color_a * 0.85
			low_b = color_b * 0.85
		else:
			top_a = _rock_shade(rock, a * r0, (top - r0) / span)
			top_b = _rock_shade(rock, b * r0, (top - r0) / span)
			low_a = _rock_shade(rock, a * r1, (top - r1) / span)
			low_b = _rock_shade(rock, b * r1, (top - r1) / span)
		md.add_tri_facing_shaded(p[0], p[1], p[2], outward, top_a, top_b, low_b, white)
		md.add_tri_facing_shaded(p[0], p[2], p[3], outward, top_a, low_b, low_a, white)


## A wall corner point. Rows at whole-level radii stay put (they meet the
## flat ground); rows in between wobble with noise so the rock looks chipped.
static func _wall_point(dir: Vector3, radius: float, data: PlanetData) -> Vector3:
	var p := dir * radius
	var levels := (radius - data.radius) / data.level_height
	var off_grid := absf(levels - roundf(levels)) > 0.01
	if not off_grid:
		return p
	var push := Vector3(
		_rock_noise.get_noise_3dv(p),
		_rock_noise.get_noise_3dv(p + Vector3(31.7, 0, 0)),
		_rock_noise.get_noise_3dv(p + Vector3(0, 57.3, 0)))
	push -= dir * push.dot(dir)
	return p + push * ROCK_JITTER * 2.0


## Rock colour with a little variation, darker toward the foot of the wall.
static func _rock_shade(rock: Color, p: Vector3, depth: float) -> Color:
	var variation := 1.0 + _rock_noise.get_noise_3dv(p * 3.0) * 0.12
	var c := rock * variation * lerpf(1.0, 0.68, depth)
	c.a = 1.0
	return c


static func _top_swatch(data: PlanetData, t: int) -> String:
	match data.biome[t]:
		Biome.OCEAN:
			return "shallows" if data.level[t] == 0 else "seabed"
		Biome.POLAR:
			return "snow"
		Biome.TUNDRA:
			return "tundra"
		Biome.GRASSLAND:
			return "sand" if data.level[t] == 1 and data.is_coast(t) else "grass"
		Biome.DESERT:
			return "sand"
		Biome.JUNGLE:
			return "sand" if data.level[t] == 1 and data.is_coast(t) else "jungle"
		Biome.MOUNTAIN:
			return "snow" if data.level[t] >= PlanetGenerator.MAX_LEVEL else "rock"
	return "grass"


## Close-up props for one chunk: model placements (drawn instanced) and a
## mesh of small ground detail.
class Props:
	var placements := {}  # model name -> Array of Transform3D
	var shapes := MeshData.new()

	func place(model: String, xf: Transform3D) -> void:
		if not placements.has(model):
			placements[model] = []
		placements[model].append(xf)

	func triangle_count() -> int:
		var total := shapes.triangle_count()
		for model: String in placements:
			total += PropLibrary.triangle_count(model, 0) * placements[model].size()
		return total


## A prop: its full model is placed for instancing close up and its simple
## version is merged into `far`.
static func add_prop(near: Props, far: MeshData, model: String, xf: Transform3D) -> void:
	near.place(model, xf)
	far.add_arrays(xf, PropLibrary.arrays(model, 1))


# --- Ground detail -------------------------------------------------------------
# Little things that make the ground read as alive up close: tufts of grass
# and flowers on meadows, pebbles in deserts, and stepping stones between
# the village buildings. Drawn only near the camera, merged per chunk.

## Tufts, flowers and pebbles per tile, by biome.
const DETAIL_COUNT := [0, 5, 9, 3, 0, 10, 1]
const FLOWER_SWATCHES := ["flower", "flower_white", "flower_yellow"]


static func _add_ground_detail(md: MeshData, data: PlanetData, t: int) -> void:
	if data.is_water(t):
		return
	var biome := data.biome[t]
	var count: int = DETAIL_COUNT[biome]
	if biome == Biome.MOUNTAIN and data.level[t] >= PlanetGenerator.MAX_LEVEL:
		count = 0
	if count == 0:
		return
	var rng := PropPlacer.tile_rng(data, t, 11)
	var sand := _top_swatch(data, t) == "sand"
	for i in count:
		var xf := PropPlacer.scatter_transform(data, t, rng, 0.9)
		var roll := rng.randf()
		if biome == Biome.DESERT or biome == Biome.MOUNTAIN or sand:
			_add_pebbles(md, xf, rng, "rock_dark" if biome == Biome.MOUNTAIN else "sandstone")
		elif biome == Biome.TUNDRA:
			_add_tuft(md, xf, rng, "pine", 0.35)
		elif roll < 0.3:
			_add_flower(md, xf, rng)
		else:
			_add_tuft(md, xf, rng, "pine" if biome == Biome.JUNGLE else "leaf", 0.45)


## A few thin blades leaning outward.
static func _add_tuft(md: MeshData, xf: Transform3D, rng: RandomNumberGenerator, swatch: String, height: float) -> void:
	var uv := Palette.uv(swatch)
	md.tint = Color.WHITE.lerp(Color(0.85, 0.95, 0.8), rng.randf())
	for k in 4:
		var angle := TAU * k / 4.0 + rng.randf() * 0.6
		var blade := xf.rotated_local(Vector3.UP, angle).translated_local(Vector3(0.06, 0, 0)).rotated_local(Vector3.BACK, -0.35 - rng.randf() * 0.3)
		md.add_prism(blade, 0.06, 0.0, height * rng.randf_range(0.7, 1.2), 3, uv)
	md.tint = Color.WHITE


## A small flower on a stalk, with a couple of leaves.
static func _add_flower(md: MeshData, xf: Transform3D, rng: RandomNumberGenerator) -> void:
	var height := rng.randf_range(0.2, 0.34)
	md.add_prism(xf, 0.02, 0.015, height, 3, Palette.uv("leaf_dark"))
	md.add_blob(xf.translated_local(Vector3(0.06, 0.03, 0)), Vector3(0.08, 0.02, 0.04), Palette.uv("leaf"))
	var head := xf.translated_local(Vector3(0, height, 0))
	md.add_prism(head, 0.09, 0.07, 0.03, 5, Palette.uv(FLOWER_SWATCHES[rng.randi() % FLOWER_SWATCHES.size()]))
	md.add_prism(head.translated_local(Vector3(0, 0.02, 0)), 0.035, 0.02, 0.03, 5, Palette.uv("flower_yellow"))


static func _add_pebbles(md: MeshData, xf: Transform3D, rng: RandomNumberGenerator, swatch: String) -> void:
	for k in rng.randi_range(1, 3):
		var at := xf.rotated_local(Vector3.UP, rng.randf() * TAU).translated_local(Vector3(rng.randf() * 0.3, 0, 0))
		var size := rng.randf_range(0.06, 0.14)
		md.add_blob(at, Vector3(size * 1.3, size * 0.6, size), Palette.uv(swatch))


## Stepping stones from the front of the stall to each building's door.
static func _add_paths(near: Array[Props], chunk_of: PackedInt32Array, data: PlanetData) -> void:
	if data.village.is_empty():
		return
	var from: Vector3 = data.village["stall_front"]
	for prop: Dictionary in data.props:
		if prop["model"] not in ["cargo_pod", "cottage"]:
			continue
		var door: Vector3 = (prop["xf"] as Transform3D) * Vector3(0, 0, 2.6)
		var rng := PropPlacer.tile_rng(data, prop["tile"], 12)
		var length := from.distance_to(door)
		var steps := int(length / 0.75)
		for i in range(1, steps):
			var p := from.lerp(door, float(i) / steps)
			var up := p.normalized()
			var tile := data.sphere.find_tile(up, prop["tile"])
			var r := data.top_radius(tile)
			var side := SphereMath.tangent(door - from, up).cross(up).normalized() * sin(i * 1.7) * 0.15
			var at := Transform3D(SphereMath.basis_from_up(up, rng.randf() * TAU), (up * r + side).normalized() * r)
			var size := rng.randf_range(0.17, 0.23)
			near[chunk_of[tile]].shapes.add_blob(at, Vector3(size * 1.2, 0.04, size), Palette.uv("stone"))
