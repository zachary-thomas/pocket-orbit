class_name PlanetMesher
extends RefCounted
## Turns PlanetData into meshes: terraced terrain plus props (trees, rocks,
## shrines and the village).
##
## The planet is split into 80 chunks, so the renderer can skip chunks that
## are off screen or over the horizon, and so each stays under the Mobile
## renderer's limit of 8 lights per mesh. Every chunk has:
## - a terrain mesh
## - near props: where each full-detail model stands, drawn with GPU
##   instancing when the camera is close (one copy of each model in memory,
##   one draw call per model per chunk), plus a small mesh of primitive shapes
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
## Rings of tiles around home kept clear of wild trees for the village.
const VILLAGE_CLEAR_RINGS := 2

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
	var forest_noise := FastNoiseLite.new()
	forest_noise.seed = data.world_seed + 303
	forest_noise.frequency = 3.0
	var top_colors := _top_colors(data)
	var village := data.tiles_within(data.home_tile, VILLAGE_CLEAR_RINGS)

	for t in sphere.tile_count():
		var chunk := nearest_direction(chunk_dirs, sphere.centers[t])
		chunk_of[t] = chunk
		# Angular size of the chunk: its farthest tile corner from the centre.
		for corner in sphere.tile_corners(t):
			chunk_radii[chunk] = maxf(chunk_radii[chunk], chunk_dirs[chunk].angle_to(corner))
		_add_tile(terrain[chunk], data, t, top_colors)
		if village.has(t) or data.is_water(t):
			continue
		if sphere.is_pentagon(t):
			_add_shrine(near[chunk], far[chunk], data, t)
		else:
			var forest := forest_noise.get_noise_3dv(sphere.centers[t]) * 0.5 + 0.5
			_add_nature(near[chunk], far[chunk], data, t, forest)

	var lamps: Array[Vector3] = []
	_add_village(data, near, far, chunk_of, lamps)
	return {
		"terrain": terrain, "near": near, "far": far,
		"chunk_dirs": chunk_dirs, "chunk_radii": chunk_radii, "lamps": lamps,
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


# --- Placement helpers ---------------------------------------------------------

## Distance from a tile's centre to the middle of its first edge, in metres.
static func tile_inradius(data: PlanetData, t: int) -> float:
	var s := data.sphere.corner_start[t]
	var mid := (data.sphere.corners[s] + data.sphere.corners[s + 1]).normalized()
	return data.sphere.centers[t].angle_to(mid) * data.top_radius(t)


## Upright transform at a random spot inside the tile, within `spread` of the
## inradius from the centre.
static func scatter_transform(data: PlanetData, t: int, rng: RandomNumberGenerator, spread: float) -> Transform3D:
	var center := data.sphere.centers[t]
	var r := data.top_radius(t)
	var frame := SphereMath.basis_from_up(center)
	var angle := rng.randf() * TAU
	var dist := sqrt(rng.randf()) * spread * tile_inradius(data, t)
	var offset := (frame.x * cos(angle) + frame.z * sin(angle)) * dist
	var up := (center * r + offset).normalized()
	return Transform3D(SphereMath.basis_from_up(up, rng.randf() * TAU), up * r)


## Upright transform on tile `t`, `offset` metres from its centre toward
## `toward`, with the model's front (+Z) facing `toward`.
static func transform_toward(data: PlanetData, t: int, toward: Vector3, offset: float) -> Transform3D:
	var center := data.sphere.centers[t]
	var r := data.top_radius(t)
	var dir := SphereMath.tangent(toward - center, center)
	var up := (center * r + dir * offset).normalized()
	return Transform3D(SphereMath.basis_facing(up, toward - up), up * r)


static func tile_rng(data: PlanetData, t: int, salt: int = 0) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([data.world_seed, t, salt])
	return rng


## Close-up props for one chunk: model placements (drawn instanced) and a
## mesh for primitive shapes that have no Blender model yet.
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


## A model from PropLibrary: placed for instancing close up, and merged into
## `far` as its simple version.
static func add_model(near: Props, far: MeshData, model: String, xf: Transform3D) -> void:
	near.place(model, xf)
	far.add_arrays(xf, PropLibrary.arrays(model, 1))


# --- Nature --------------------------------------------------------------------

## Trees grow in clumps: `forest` (0..1, from noise) scales how many props a
## tile gets, so there are groves and open meadows rather than an even spread.
static func _add_nature(near: Props, far: MeshData, data: PlanetData, t: int, forest: float) -> void:
	var rng := tile_rng(data, t)
	var biome := data.biome[t]
	var density: float = [0.0, 0.25, 0.55, 0.4, 0.3, 0.7, 0.35][biome]
	density *= lerpf(0.2, 1.8, smoothstep(0.35, 0.72, forest))
	for attempt in 3:
		if rng.randf() > density:
			continue
		var xf := scatter_transform(data, t, rng, 0.7)
		var s := rng.randf_range(0.8, 1.2)
		var sized := xf.scaled_local(Vector3.ONE * s)
		var roll := rng.randf()
		match biome:
			Biome.POLAR:
				_both(near, far, func(md: MeshData) -> void: add_ice_spire(md, xf, s))
			Biome.TUNDRA:
				add_model(near, far, "tree_pine" if roll < 0.8 else "rock", sized)
			Biome.GRASSLAND:
				if roll < 0.55:
					add_model(near, far, "tree_round", sized)
				elif roll < 0.85:
					add_model(near, far, "bush", sized)
				else:
					add_model(near, far, "rock", sized.scaled_local(Vector3.ONE * 0.8))
			Biome.DESERT:
				if roll < 0.7:
					_both(near, far, func(md: MeshData) -> void: add_cactus(md, xf, s))
				else:
					add_model(near, far, "rock", sized)
			Biome.JUNGLE:
				if roll < 0.7:
					_both(near, far, func(md: MeshData) -> void: add_jungle_tree(md, xf, s))
				else:
					add_model(near, far, "bush", sized.scaled_local(Vector3.ONE * 1.3))
			Biome.MOUNTAIN:
				add_model(near, far, "rock", sized.scaled_local(Vector3.ONE * 1.3))


## Primitive shapes that don't have a Blender model yet go in both meshes.
static func _both(near: Props, far: MeshData, add: Callable) -> void:
	add.call(near.shapes)
	add.call(far)


static func add_jungle_tree(md: MeshData, xf: Transform3D, s: float) -> void:
	md.add_prism(xf, 0.24 * s, 0.16 * s, 3.2 * s, 5, Palette.uv("trunk"))
	md.add_blob(xf.translated_local(Vector3(0, 3.4 * s, 0)), Vector3(1.9, 0.7, 1.9) * s, Palette.uv("leaf_dark"), 0)
	md.add_blob(xf.translated_local(Vector3(0.3 * s, 3.9 * s, 0.2 * s)), Vector3(1.2, 0.6, 1.2) * s, Palette.uv("palm"), 0)


static func add_cactus(md: MeshData, xf: Transform3D, s: float) -> void:
	var uv := Palette.uv("cactus")
	md.add_prism(xf, 0.32 * s, 0.28 * s, 1.9 * s, 6, uv)
	md.add_box(xf.translated_local(Vector3(0.42 * s, 0.9 * s, 0)), Vector3(0.5, 0.22, 0.22) * s, uv)
	md.add_prism(xf.translated_local(Vector3(0.62 * s, 0.9 * s, 0)), 0.14 * s, 0.12 * s, 0.6 * s, 5, uv)


static func add_ice_spire(md: MeshData, xf: Transform3D, s: float) -> void:
	md.add_prism(xf, 0.6 * s, 0.0, 2.6 * s, 5, Palette.uv("ice"))
	md.add_prism(xf.translated_local(Vector3(0.6 * s, 0, 0.2 * s)), 0.35 * s, 0.0, 1.4 * s, 5, Palette.uv("ice"))


# --- Shrines and village -----------------------------------------------------

## The 12 pentagon tiles are ancient shrines (and later, fast-travel points).
static func _add_shrine(near: Props, far: MeshData, data: PlanetData, t: int) -> void:
	var center := data.sphere.centers[t]
	var xf := Transform3D(SphereMath.basis_from_up(center), center * data.top_radius(t))
	for md: MeshData in [near.shapes, far]:
		md.add_prism(xf, 1.4, 1.2, 0.35, 5, Palette.uv("shrine_stone"))
		md.add_prism(xf.translated_local(Vector3(0, 0.35, 0)), 0.45, 0.32, 2.3, 5, Palette.uv("shrine_stone"))
		md.add_blob(xf.translated_local(Vector3(0, 3.0, 0)), Vector3(0.45, 0.6, 0.45), Palette.uv("shrine_glow"), 0)


## The starting village: the market stall on the home tile, a cottage on up to
## three neighbouring tiles facing it, street lamps, and a few bushes and rocks.
static func _add_village(data: PlanetData, near: Array[Props], far: Array[MeshData],
		chunk_of: PackedInt32Array, lamps: Array[Vector3]) -> void:
	var home := data.home_tile
	var home_dir := data.sphere.centers[home]
	var neighbors := data.sphere.neighbors(home)
	var land: Array[int] = []
	for n in neighbors:
		if not data.is_water(n) and data.level[n] == data.level[home]:
			land.append(n)
	var c := chunk_of[home]

	# The stall faces the first neighbour; lamps stand either side of it.
	var facing := data.sphere.centers[land[0]] if not land.is_empty() else data.sphere.centers[neighbors[0]]
	var stall := transform_toward(data, home, facing, 0.5)
	add_model(near[c], far[c], "market_stall", stall)
	for side in [-1.0, 1.0]:
		var lamp := stall.translated_local(Vector3(2.3 * side, 0, 1.6))
		add_model(near[c], far[c], "lamp_post", lamp)
		lamps.append(lamp * Vector3(0, 2.3, 0))

	for i in mini(land.size(), 3):
		var tile := land[(i * 2 + 1) % land.size()]
		var tc := chunk_of[tile]
		var cottage := transform_toward(data, tile, home_dir, 0.0)
		add_model(near[tc], far[tc], "cottage", cottage)
		var lamp := cottage.translated_local(Vector3(1.9, 0, 2.6))
		add_model(near[tc], far[tc], "lamp_post", lamp)
		lamps.append(lamp * Vector3(0, 2.3, 0))
		# Garden: a bush or two and a rock around the cottage.
		var rng := tile_rng(data, tile, 7)
		for k in 3:
			var angle := rng.randf_range(0.5, TAU - 0.5)
			var at := cottage.rotated_local(Vector3.UP, angle).translated_local(Vector3(0, 0, 2.9))
			var model := "rock" if k == 2 else "bush"
			var s := rng.randf_range(0.6, 0.9)
			add_model(near[tc], far[tc], model, at.scaled_local(Vector3.ONE * s))
