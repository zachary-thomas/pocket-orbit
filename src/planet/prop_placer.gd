class_name PropPlacer
extends RefCounted
## Decides where every prop stands: trees, rocks, shrines and the village.
## It only produces data; PlanetMesher draws it and gameplay uses it for
## harvesting and collisions.
##
## Each prop is a Dictionary:
##   id      stable id, e.g. "t812-1" (tile 812, second attempt); the same
##           seed always gives the same ids, so saves can refer to them
##   model   a PropLibrary model ("tree_round")
##   xf      Transform3D relative to the planet centre
##   tile    tile it stands on
##   radius  collision radius in metres (0 = walk through)
##   source  what harvesting it gives (see CatchTables.gather), or ""
##
## The village layout goes in PlanetData.village.

## Rings of tiles around home kept clear of wild plants for the village.
const VILLAGE_CLEAR_RINGS := 2

const RADIUS := {
	"tree_round": 0.5, "tree_pine": 0.55, "rock": 0.85, "bush": 0.55, "cactus": 0.45,
	"jungle_tree": 0.4, "ice_spire": 0.65, "shrine": 1.4, "lamp_post": 0.2,
	"market_stall": 1.45, "cottage": 2.15, "cargo_pod": 2.0, "tide_pool": 0.0, "fence": 0.0,
	"general_shop": 2.4, "archive": 2.3, "burrow_house": 2.1, "landing_pad": 0.0,
}
## Village plots for buildings you put up later (landing pad, Archive, ...).
const PLOT_COUNT := 4
## Chance a stretch of low shore gets a tide pool.
const TIDE_POOL_CHANCE := 0.1
## The shore tiles nearest home always get one, so there's one to find.
const TIDE_POOLS_NEAR_HOME := 2
const SOURCE := {"tree_round": "tree_round", "tree_pine": "tree_pine", "rock": "rock", "jungle_tree": "jungle_tree", "cactus": "cactus"}


static func place(data: PlanetData) -> void:
	data.props.clear()
	data.props_by_tile.clear()
	var forest_noise := FastNoiseLite.new()
	forest_noise.seed = data.world_seed + 303
	forest_noise.frequency = 3.0
	var village := data.tiles_within(data.home_tile, VILLAGE_CLEAR_RINGS)
	for t in data.tile_count():
		if village.has(t) or data.is_water(t):
			continue
		if data.sphere.is_pentagon(t):
			var center := data.sphere.centers[t]
			_add(data, "shrine-%d" % t, "shrine", Transform3D(SphereMath.basis_from_up(center), center * data.top_radius(t)), t, 1.0)
		else:
			var forest := forest_noise.get_noise_3dv(data.sphere.centers[t]) * 0.5 + 0.5
			_add_nature(data, t, forest)
	_add_village(data)
	_add_tide_pools(data)


static func _add(data: PlanetData, id: String, model: String, xf: Transform3D, tile: int, size: float) -> Dictionary:
	var prop := {
		"id": id, "model": model, "xf": xf, "tile": tile,
		"radius": RADIUS.get(model, 0.0) * size, "source": SOURCE.get(model, ""),
	}
	data.props.append(prop)
	if not data.props_by_tile.has(tile):
		data.props_by_tile[tile] = []
	data.props_by_tile[tile].append(prop)
	return prop


## Trees grow in clumps: `forest` (0..1, from noise) scales how many props a
## tile gets, so there are groves and open meadows rather than an even spread.
static func _add_nature(data: PlanetData, t: int, forest: float) -> void:
	var rng := tile_rng(data, t)
	var biome := data.biome[t]
	var density: float = [0.0, 0.25, 0.55, 0.4, 0.3, 0.7, 0.35][biome]
	density *= lerpf(0.2, 1.8, smoothstep(0.35, 0.72, forest))
	for attempt in 3:
		if rng.randf() > density:
			continue
		var xf := scatter_transform(data, t, rng, 0.7)
		var s := rng.randf_range(0.8, 1.2)
		var roll := rng.randf()
		var model := ""
		match biome:
			Biome.POLAR:
				model = "ice_spire"
			Biome.TUNDRA:
				model = "tree_pine" if roll < 0.8 else "rock"
			Biome.GRASSLAND:
				model = "tree_round" if roll < 0.55 else ("bush" if roll < 0.85 else "rock")
				if model == "rock":
					s *= 0.8
			Biome.DESERT:
				model = "cactus" if roll < 0.7 else "rock"
			Biome.JUNGLE:
				model = "jungle_tree" if roll < 0.7 else "bush"
				if model == "bush":
					s *= 1.3
			Biome.MOUNTAIN:
				model = "rock"
				s *= 1.3
		if model != "":
			_add(data, "t%d-%d" % [t, attempt], model, xf.scaled_local(Vector3.ONE * s), t, s)


## The starting village on and around the home tile: the market stall where
## Vessa waits, the player's cargo-pod home, two empty cottages for the
## refugees to come, street lamps and a few garden plants.
static func _add_village(data: PlanetData) -> void:
	var home := data.home_tile
	var home_dir := data.sphere.centers[home]
	var neighbors := data.sphere.neighbors(home)
	var land: Array[int] = []
	for n in neighbors:
		if not data.is_water(n) and data.level[n] == data.level[home]:
			land.append(n)
	# The stall faces its "street": the first flat neighbour, kept free of
	# buildings so customers can walk up to it.
	var street := land[0] if not land.is_empty() else neighbors[0]
	var stall := transform_toward(data, home, data.sphere.centers[street], 0.5)
	_add(data, "stall", "market_stall", stall, home, 1.0)["dynamic"] = true
	var lamps: Array[Vector3] = []
	for side in [-1.0, 1.0]:
		var lamp := stall.translated_local(Vector3(2.3 * side, 0, 1.6))
		_add(data, "lamp-stall-%d" % int(side), "lamp_post", lamp, home, 1.0)
		lamps.append(lamp * Vector3(0, 2.3, 0))

	var buildings: Array[int] = []
	for n in land:
		if n != street:
			buildings.append(n)
	var home_building := -1
	for i in mini(buildings.size(), 3):
		var tile := buildings[int(i * buildings.size() / 3.0)]
		var model := "cargo_pod" if i == 0 else "cottage"
		var xf := transform_toward(data, tile, home_dir, 0.0)
		var id := "home" if i == 0 else "cottage-%d" % i
		_add(data, id, model, xf, tile, 1.0)
		if i == 0:
			home_building = tile
		var lamp := xf.translated_local(Vector3(1.9, 0, 2.6))
		_add(data, "lamp-%s" % id, "lamp_post", lamp, tile, 1.0)
		lamps.append(lamp * Vector3(0, 2.3, 0))
		var rng := tile_rng(data, tile, 7)
		for k in 3:
			var angle := rng.randf_range(0.6, TAU - 0.6)
			var at := xf.rotated_local(Vector3.UP, angle).translated_local(Vector3(0, 0, 3.0))
			var s := rng.randf_range(0.6, 0.9)
			var garden := "rock" if k == 2 else "bush"
			_add(data, "garden-%s-%d" % [id, k], garden, at.scaled_local(Vector3.ONE * s), tile, s)

	# Fences behind each house, closing off the back garden.
	for id in ["home", "cottage-1", "cottage-2"]:
		var house := _find(data, id)
		if house.is_empty():
			continue
		for side in [-1.0, 1.0]:
			var fence := (house["xf"] as Transform3D).translated_local(Vector3(side * 1.05, 0, -3.3))
			_add(data, "fence-%s-%d" % [id, int(side)], "fence", fence, house["tile"], 1.0)

	var home_prop := _find(data, "home")
	data.village = {
		"stall": stall,
		"street_tile": street,
		# Where customers stand to browse, in front of the counter.
		"stall_front": stall * Vector3(0, 0, 2.3),
		"vessa": stall.translated_local(Vector3(-1.9, 0, 1.0)).rotated_local(Vector3.UP, deg_to_rad(25)),
		"home_tile": home_building,
		"home_door": (home_prop["xf"] as Transform3D) * Vector3(0, 0, 2.6) if home_prop else stall.origin,
		"lamps": lamps,
		"plots": _plots(data, street),
	}


## Empty building plots on the second ring around home, on flat land and
## spread out around the village, leaving the street clear. Each is
## {"id", "tile", "xf"} with the front facing home.
static func _plots(data: PlanetData, street: int) -> Array:
	var home := data.home_tile
	var home_dir := data.sphere.centers[home]
	var around := data.tiles_within(home, 2)
	var street_side := Array(data.sphere.neighbors(street))
	var candidates: Array[int] = []
	for t: int in around:
		if around[t] == 2 and not data.is_water(t) and data.level[t] == data.level[home] 				and not data.sphere.is_pentagon(t) and not t in street_side:
			candidates.append(t)
	# Order round the village, then take every n-th so they're spread out.
	var frame := SphereMath.basis_from_up(home_dir)
	var angle := func(t: int) -> float:
		var d := data.sphere.centers[t] - home_dir
		return atan2(d.dot(frame.z), d.dot(frame.x))
	candidates.sort_custom(func(a: int, b: int) -> bool: return angle.call(a) < angle.call(b))
	var plots := []
	var count := mini(PLOT_COUNT, candidates.size())
	for i in count:
		var t := candidates[int(i * candidates.size() / float(count))]
		plots.append({"id": "plot-%d" % i, "tile": t, "xf": transform_toward(data, t, home_dir, 0.0)})
	return plots


## Rock pools on the shallow sea floor just off low shores, a little way out
## from the beach: under water most of the day, uncovered at low tide.
static func _add_tide_pools(data: PlanetData) -> void:
	var candidates: Array[Vector2i] = []
	for t in data.tile_count():
		if data.level[t] != 0:
			continue
		for n in data.sphere.neighbors(t):
			if data.level[n] == 1:
				candidates.append(Vector2i(t, n))
				break
	var home_dir := data.sphere.centers[data.home_tile]
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return data.sphere.centers[a.x].distance_squared_to(home_dir) < data.sphere.centers[b.x].distance_squared_to(home_dir))
	for i in candidates.size():
		var t := candidates[i].x
		var rng := tile_rng(data, t, 23)
		if i >= TIDE_POOLS_NEAR_HOME and rng.randf() > TIDE_POOL_CHANCE:
			continue
		var shore := data.sphere.centers[candidates[i].y]
		var dir := data.sphere.centers[t].lerp(shore, 0.3).normalized()
		var xf := Transform3D(SphereMath.basis_from_up(dir, rng.randf() * TAU), dir * data.top_radius(t))
		var prop := _add(data, "pool-%d" % t, "tide_pool", xf, t, 1.0)
		prop["source"] = "tide_pool"


static func _find(data: PlanetData, id: String) -> Dictionary:
	for prop: Dictionary in data.props:
		if prop["id"] == id:
			return prop
	return {}


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
