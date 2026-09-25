class_name PlanetGenerator
extends RefCounted
## Builds a PlanetData from a seed. It is a pure function of its inputs: noise
## comes from FastNoiseLite seeded from `world_seed`, and nothing reads the clock or
## a global random generator. The home planet and future procedural planets
## share this code with different settings.

## Share of tiles that end up under water.
const OCEAN_FRACTION := 0.4
const MIN_LEVEL := -2
const MAX_LEVEL := 6
## Water this close to the poles freezes into walkable ice-cap shelf.
const ICE_SHELF_LATITUDE := 76.0
## Temperature at the plan's biome latitudes: 1 - latitude / 90.
const POLAR_BELOW := 0.222     # above ~70 degrees
const TUNDRA_BELOW := 0.444    # 50-70 degrees
const TEMPERATE_BELOW := 0.778 # 20-50 degrees; warmer is desert or jungle
const MOUNTAIN_LEVEL := 5
## Each terrace above the first cools a tile by this much.
const ALTITUDE_COOLING := 0.06


static func generate(world_seed: int, frequency: int = 16, radius: float = 134.0, level_height: float = 1.0) -> PlanetData:
	var data := PlanetData.new()
	data.world_seed = world_seed
	data.sphere = HexSphere.new(frequency)
	data.radius = radius
	data.level_height = level_height
	data.sea_level_radius = radius + level_height * 0.45
	var count := data.sphere.tile_count()
	data.level.resize(count)
	data.biome.resize(count)
	data.temperature.resize(count)
	data.moisture.resize(count)

	_assign_levels(data)
	_assign_climate(data)
	_choose_home(data)
	_flatten_village(data)
	_assign_climate(data)
	PropPlacer.place(data)
	return data


static func _noise(noise_seed: int, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	return noise


## Heights come from 3D noise sampled on the unit sphere (so there is no seam
## or pole pinching). The sea threshold is picked from the sorted heights so the
## ocean always covers OCEAN_FRACTION of the planet, whatever the seed.
static func _assign_levels(data: PlanetData) -> void:
	var noise := _noise(data.world_seed, 4)
	var count := data.tile_count()
	var raw := PackedFloat32Array()
	raw.resize(count)
	for t in count:
		raw[t] = noise.get_noise_3dv(data.sphere.centers[t] * 1.6)
	var sorted := raw.duplicate()
	sorted.sort()
	var sea: float = sorted[int(OCEAN_FRACTION * (count - 1))]
	var low: float = sorted[0]
	var high: float = sorted[count - 1]
	for t in count:
		var h := raw[t]
		var lvl: int
		if h <= sea:
			var depth := (sea - h) / maxf(sea - low, 1e-5)
			lvl = -int(floor(depth * (1 - MIN_LEVEL - 0.001)))
		else:
			var rise := (h - sea) / maxf(high - sea, 1e-5)
			# The curve keeps most land low and makes tall peaks rare.
			lvl = 1 + int(floor(pow(rise, 1.4) * (MAX_LEVEL - 0.001)))
		if lvl <= 0 and absf(SphereMath.latitude_degrees(data.sphere.centers[t])) >= ICE_SHELF_LATITUDE:
			lvl = 1
		data.level[t] = clampi(lvl, MIN_LEVEL, MAX_LEVEL)


## Latitude sets temperature, altitude cools it, and a separate moisture noise
## field decides desert versus jungle near the equator.
static func _assign_climate(data: PlanetData) -> void:
	var moisture_noise := _noise(data.world_seed + 101, 3)
	var wobble_noise := _noise(data.world_seed + 202, 2)
	for t in data.tile_count():
		var dir := data.sphere.centers[t]
		var lat := absf(SphereMath.latitude_degrees(dir))
		var temp := 1.0 - lat / 90.0
		temp -= maxi(data.level[t] - 1, 0) * ALTITUDE_COOLING
		temp += wobble_noise.get_noise_3dv(dir * 2.5) * 0.05
		data.temperature[t] = clampf(temp, 0.0, 1.0)
		data.moisture[t] = clampf(moisture_noise.get_noise_3dv(dir * 1.4) * 0.9 + 0.5, 0.0, 1.0)
		data.biome[t] = _biome_for(data, t)


static func _biome_for(data: PlanetData, t: int) -> int:
	if data.is_water(t):
		return Biome.OCEAN
	if data.level[t] >= MOUNTAIN_LEVEL:
		return Biome.MOUNTAIN
	var temp := data.temperature[t]
	if temp < POLAR_BELOW:
		return Biome.POLAR
	if temp < TUNDRA_BELOW:
		return Biome.TUNDRA
	if temp < TEMPERATE_BELOW:
		return Biome.GRASSLAND
	return Biome.DESERT if data.moisture[t] < 0.5 else Biome.JUNGLE


## The village goes on low grassland in the northern mid-latitudes, preferring
## wide flat ground with the sea a short walk away.
static func _choose_home(data: PlanetData) -> void:
	var best := -1
	var best_score := -1
	for t in data.tile_count():
		var lat := SphereMath.latitude_degrees(data.sphere.centers[t])
		if data.sphere.is_pentagon(t) or data.level[t] < 1 or data.level[t] > 2:
			continue
		if lat < 22.0 or lat > 48.0 or data.biome[t] != Biome.GRASSLAND:
			continue
		var score := 0
		var near_sea := false
		var area := data.tiles_within(t, 3)
		for other: int in area:
			var ring: int = area[other]
			if ring <= 2 and not data.is_water(other) and absi(data.level[other] - data.level[t]) <= 1:
				score += 2
			if data.is_water(other):
				near_sea = true
		if near_sea:
			score += 6
		if score > best_score:
			best_score = score
			best = t
	if best == -1:
		for t in data.tile_count():
			if not data.is_water(t) and data.level[t] < MOUNTAIN_LEVEL:
				best = t
				break
	data.home_tile = maxi(best, 0)


## Level the ground right around home so the placeholder village sits flat.
static func _flatten_village(data: PlanetData) -> void:
	var home := data.home_tile
	for n in data.sphere.neighbors(home):
		if not data.is_water(n):
			data.level[n] = data.level[home]
