class_name PlanetMesher
extends RefCounted
## Turns PlanetData into meshes: stepped hex terrain plus placeholder props
## (trees, rocks, shrines and a tiny village).
##
## The planet is split into 80 chunks. Each chunk is its own mesh, so the
## renderer can skip chunks behind the camera, and each one stays under the
## Mobile renderer's limit of 8 lights per mesh.
##
## Terrain: each tile is a flat hexagon (or pentagon) at its level's radius.
## Where a neighbour is lower, a wall drops from this tile's edge to the
## neighbour's height. The top few centimetres of the wall use the top colour,
## like the grass lip on a terrace. Props are merged into the chunk meshes, so a
## chunk is one draw call.

const LIP_HEIGHT := 0.18
## Rings of tiles around home kept clear of trees for the village.
const VILLAGE_CLEAR_RINGS := 2


static func build(data: PlanetData) -> Dictionary:
	var sphere := data.sphere
	var chunk_dirs := chunk_directions()
	var chunks: Array[MeshData] = []
	for i in chunk_dirs.size():
		chunks.append(MeshData.new())
	var chunk_radii := PackedFloat32Array()
	chunk_radii.resize(chunk_dirs.size())
	var village := data.tiles_within(data.home_tile, VILLAGE_CLEAR_RINGS)

	for t in sphere.tile_count():
		var chunk := nearest_direction(chunk_dirs, sphere.centers[t])
		var md: MeshData = chunks[chunk]
		# Angular size of the chunk: its farthest tile corner from the centre.
		for corner in sphere.tile_corners(t):
			chunk_radii[chunk] = maxf(chunk_radii[chunk], chunk_dirs[chunk].angle_to(corner))
		_add_tile(md, data, t)
		if village.has(t) or data.is_water(t):
			continue
		if sphere.is_pentagon(t):
			_add_shrine(md, data, t)
		else:
			_add_nature(md, data, t)

	var lamps: Array[Vector3] = []
	_add_village(data, chunks, chunk_dirs, lamps)
	return {"chunks": chunks, "chunk_dirs": chunk_dirs, "chunk_radii": chunk_radii, "lamps": lamps}


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

static func _add_tile(md: MeshData, data: PlanetData, t: int) -> void:
	var sphere := data.sphere
	var s := sphere.corner_start[t]
	var e := sphere.corner_start[t + 1]
	var center := sphere.centers[t]
	var r := data.top_radius(t)
	var top_uv := Palette.uv(_top_swatch(data, t))
	var cliff_uv := Palette.uv(Biome.CLIFF_SWATCH[data.biome[t]])
	for i in range(s, e):
		var a := sphere.corners[i]
		var b := sphere.corners[s if i + 1 == e else i + 1]
		# Top: a fan from the centre. Normals point straight out from the planet
		# so tiles on the same level shade as one smooth terrace.
		md.add_tri_smooth(center * r, a * r, b * r, center, a, b, top_uv)
		var n := sphere.edge_neighbors[i]
		if data.level[n] >= data.level[t]:
			continue
		# Wall down to the lower neighbour. It faces away from this tile: the
		# plane through the planet centre, a and b has normal cross(a, b),
		# which points into this tile, so the wall faces the other way.
		var r_low := data.top_radius(n)
		var outward := -a.cross(b).normalized()
		var lip := minf(LIP_HEIGHT, (r - r_low) * 0.3)
		md.add_quad(a * r, b * r, b * (r - lip), a * (r - lip), outward, top_uv)
		md.add_quad(a * (r - lip), b * (r - lip), b * r_low, a * r_low, outward, cliff_uv)


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


## Upright transform on tile `t`, `offset` metres from its centre toward `toward`.
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


# --- Nature --------------------------------------------------------------------

static func _add_nature(md: MeshData, data: PlanetData, t: int) -> void:
	var rng := tile_rng(data, t)
	var biome := data.biome[t]
	var density: float = [0.0, 0.25, 0.6, 0.45, 0.3, 0.75, 0.35][biome]
	for attempt in 3:
		if rng.randf() > density:
			continue
		var xf := scatter_transform(data, t, rng, 0.65)
		var s := rng.randf_range(0.8, 1.25)
		var roll := rng.randf()
		match biome:
			Biome.POLAR:
				add_ice_spire(md, xf, s)
			Biome.TUNDRA:
				if roll < 0.8:
					add_pine(md, xf, s)
				else:
					add_boulder(md, xf, s)
			Biome.GRASSLAND:
				if roll < 0.6:
					add_round_tree(md, xf, s)
				elif roll < 0.85:
					add_bush(md, xf, s)
				else:
					add_flowers(md, xf, rng)
			Biome.DESERT:
				if roll < 0.7:
					add_cactus(md, xf, s)
				else:
					add_boulder(md, xf, s * 0.8)
			Biome.JUNGLE:
				if roll < 0.75:
					add_jungle_tree(md, xf, s)
				else:
					add_bush(md, xf, s * 1.3)
			Biome.MOUNTAIN:
				add_boulder(md, xf, s * 1.2)


static func add_round_tree(md: MeshData, xf: Transform3D, s: float) -> void:
	md.add_prism(xf, 0.28 * s, 0.2 * s, 1.8 * s, 5, Palette.uv("trunk"))
	md.add_blob(xf.translated_local(Vector3(0, 2.5 * s, 0)), Vector3(1.4, 1.2, 1.4) * s, Palette.uv("leaf"), 0)


static func add_pine(md: MeshData, xf: Transform3D, s: float) -> void:
	md.add_prism(xf, 0.22 * s, 0.16 * s, 0.9 * s, 5, Palette.uv("trunk"))
	md.add_prism(xf.translated_local(Vector3(0, 0.6 * s, 0)), 1.2 * s, 0.0, 1.9 * s, 7, Palette.uv("pine"))
	md.add_prism(xf.translated_local(Vector3(0, 1.7 * s, 0)), 0.85 * s, 0.0, 1.6 * s, 7, Palette.uv("pine"))


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


static func add_boulder(md: MeshData, xf: Transform3D, s: float) -> void:
	md.add_blob(xf.translated_local(Vector3(0, 0.3 * s, 0)), Vector3(1.0, 0.7, 0.9) * s, Palette.uv("boulder"), 0)


static func add_bush(md: MeshData, xf: Transform3D, s: float) -> void:
	md.add_blob(xf.translated_local(Vector3(0, 0.35 * s, 0)), Vector3(0.75, 0.55, 0.75) * s, Palette.uv("leaf_dark"), 0)


static func add_flowers(md: MeshData, xf: Transform3D, rng: RandomNumberGenerator) -> void:
	for i in 3:
		var at := Vector3(rng.randf_range(-0.8, 0.8), 0.12, rng.randf_range(-0.8, 0.8))
		md.add_blob(xf.translated_local(at), Vector3.ONE * 0.13, Palette.uv("flower"), 0)


# --- Shrines and village -----------------------------------------------------

## The 12 pentagon tiles are ancient shrines (and later, fast-travel points).
static func _add_shrine(md: MeshData, data: PlanetData, t: int) -> void:
	var center := data.sphere.centers[t]
	var xf := Transform3D(SphereMath.basis_from_up(center), center * data.top_radius(t))
	md.add_prism(xf, 1.4, 1.2, 0.35, 5, Palette.uv("shrine_stone"))
	md.add_prism(xf.translated_local(Vector3(0, 0.35, 0)), 0.45, 0.32, 2.3, 5, Palette.uv("shrine_stone"))
	md.add_blob(xf.translated_local(Vector3(0, 3.0, 0)), Vector3(0.45, 0.6, 0.45), Palette.uv("shrine_glow"), 0)


## Placeholder village: a market stall on the home tile, a hut on up to three
## neighbouring tiles, and street lamps that switch on at night.
static func _add_village(data: PlanetData, chunks: Array[MeshData], chunk_dirs: PackedVector3Array, lamps: Array[Vector3]) -> void:
	var home := data.home_tile
	var home_dir := data.sphere.centers[home]
	var md_home: MeshData = chunks[nearest_direction(chunk_dirs, home_dir)]
	var neighbors := data.sphere.neighbors(home)
	var land: Array[int] = []
	for n in neighbors:
		if not data.is_water(n) and data.level[n] == data.level[home]:
			land.append(n)

	# The stall faces the first neighbour; lamps stand either side of it.
	var facing := data.sphere.centers[land[0]] if not land.is_empty() else data.sphere.centers[neighbors[0]]
	var stall := transform_toward(data, home, facing, 0.5)
	add_stall(md_home, stall)
	for side in [-1.0, 1.0]:
		var lamp := stall.translated_local(Vector3(2.0 * side, 0, 1.4))
		add_lamp(md_home, lamp)
		lamps.append(lamp * Vector3(0, 2.1, 0))

	var roofs := ["roof_red", "roof_blue", "roof_red"]
	for i in mini(land.size(), 3):
		var tile := land[(i * 2 + 1) % land.size()]
		var md: MeshData = chunks[nearest_direction(chunk_dirs, data.sphere.centers[tile])]
		var hut := transform_toward(data, tile, home_dir, 0.0)
		add_hut(md, hut, roofs[i])
		var lamp := hut.translated_local(Vector3(1.6, 0, 2.2))
		add_lamp(md, lamp)
		lamps.append(lamp * Vector3(0, 2.1, 0))


static func add_stall(md: MeshData, xf: Transform3D) -> void:
	var wood := Palette.uv("wood")
	md.add_box(xf.translated_local(Vector3(0, 0.45, 0)), Vector3(2.6, 0.9, 1.0), wood)
	for x in [-1.2, 1.2]:
		for z in [-0.45, 0.45]:
			md.add_box(xf.translated_local(Vector3(x, 1.15, z)), Vector3(0.12, 2.3, 0.12), Palette.uv("wood_dark"))
	for i in 5:
		var swatch := "awning_red" if i % 2 == 0 else "awning_white"
		var stripe := xf.translated_local(Vector3(-1.08 + i * 0.54, 2.3, 0.1))
		md.add_box(stripe.rotated_local(Vector3.RIGHT, 0.25), Vector3(0.54, 0.1, 1.5), Palette.uv(swatch))
	md.add_box(xf.translated_local(Vector3(-0.7, 1.05, 0.1)), Vector3(0.5, 0.3, 0.4), Palette.uv("wood_dark"))
	md.add_blob(xf.translated_local(Vector3(0.6, 1.05, 0.1)), Vector3(0.3, 0.2, 0.25), Palette.uv("flower"), 0)
	md.add_box(xf.translated_local(Vector3(1.7, 0.3, -0.3)), Vector3(0.6, 0.6, 0.6), wood)


static func add_hut(md: MeshData, xf: Transform3D, roof: String) -> void:
	md.add_prism(xf, 1.6, 1.5, 2.0, 8, Palette.uv("wall_cream"))
	md.add_prism(xf.translated_local(Vector3(0, 1.95, 0)), 2.1, 0.0, 1.6, 8, Palette.uv(roof))
	md.add_box(xf.translated_local(Vector3(0, 0.6, 1.5)), Vector3(0.7, 1.2, 0.14), Palette.uv("wood_dark"))
	for side in [-1.0, 1.0]:
		var angle: float = 0.75 * side
		var window := xf.rotated_local(Vector3.UP, angle).translated_local(Vector3(0, 1.25, 1.52))
		md.add_box(window, Vector3(0.5, 0.5, 0.12), Palette.uv("window_glow"))
	md.add_box(xf.translated_local(Vector3(0.9, 2.9, -0.4)), Vector3(0.3, 0.8, 0.3), Palette.uv("stone"))


static func add_lamp(md: MeshData, xf: Transform3D) -> void:
	md.add_prism(xf, 0.09, 0.07, 1.9, 5, Palette.uv("lamp_post"))
	md.add_box(xf.translated_local(Vector3(0, 2.05, 0)), Vector3(0.32, 0.36, 0.32), Palette.uv("lamp_glow"))
	md.add_prism(xf.translated_local(Vector3(0, 2.23, 0)), 0.3, 0.0, 0.22, 4, Palette.uv("lamp_post"))
