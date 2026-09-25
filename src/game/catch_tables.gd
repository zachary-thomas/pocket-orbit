class_name CatchTables
extends RefCounted
## What you find where: fish by water temperature and time, bugs by biome and
## time, and what trees and rocks give. Rarer items are picked less often.

const RARITY_WEIGHT := {1: 60.0, 2: 25.0, 3: 6.0}


## Water temperature from latitude: polar and subpolar seas are cold, the
## tropics warm.
static func water_kind(latitude_degrees: float) -> String:
	var lat := absf(latitude_degrees)
	if lat > 50.0:
		return "cold"
	if lat > 20.0:
		return "temperate"
	return "warm"


static func _pick(rng: RandomNumberGenerator, candidates: Array[ItemDatabase.ItemDef]) -> ItemDatabase.ItemDef:
	if candidates.is_empty():
		return null
	var total := 0.0
	for item in candidates:
		total += RARITY_WEIGHT.get(item.rarity, 10.0)
	var roll := rng.randf() * total
	for item in candidates:
		roll -= RARITY_WEIGHT.get(item.rarity, 10.0)
		if roll <= 0.0:
			return item
	return candidates[-1]


static func fish(rng: RandomNumberGenerator, water: String, hour: float, season: String = "") -> ItemDatabase.ItemDef:
	var candidates: Array[ItemDatabase.ItemDef] = []
	for item in ItemDatabase.in_category("fish"):
		if water in item.waters and item.available_at(hour) and item.in_season(season):
			candidates.append(item)
	return _pick(rng, candidates)


static func bug(rng: RandomNumberGenerator, biome: int, hour: float, season: String = "") -> ItemDatabase.ItemDef:
	var candidates: Array[ItemDatabase.ItemDef] = []
	for item in ItemDatabase.in_category("bug"):
		if item.found_in(biome) and item.available_at(hour) and item.in_season(season):
			candidates.append(item)
	return _pick(rng, candidates)


## What one hit (or shake) of a prop gives: [item id, count], or [] for
## nothing. `shake` is using your hands on a tree (fruit) instead of an axe.
static func gather(rng: RandomNumberGenerator, source: String, biome: int, shake: bool = false) -> Array:
	match source:
		"rock":
			var roll := rng.randf()
			if roll < 0.45:
				return ["stone", 1]
			var minerals: Array[ItemDatabase.ItemDef] = []
			for item in ItemDatabase.in_category("mineral"):
				if item.source == "rock" and item.found_in(biome):
					minerals.append(item)
			var mineral := _pick(rng, minerals)
			return [mineral.id, 1] if mineral else ["stone", 1]
		"tree_round":
			if shake:
				return ["starfruit", 1] if rng.randf() < 0.04 else ["apple", rng.randi_range(1, 2)]
			return ["wood", 1]
		"tree_pine":
			if shake:
				return []
			return ["pine_sap", 1] if rng.randf() < 0.15 else ["softwood", 1]
		"jungle_tree":
			if shake:
				return ["coconut", 1] if rng.randf() < 0.6 else []
			return ["hardwood", 1]
		"cactus":
			return [] if shake else ["cactus_water", 1]
	return []


## What digging at a dig spot turns up: mostly fossils, some clay, and now
## and then a shard of starfall.
static func dig(rng: RandomNumberGenerator) -> Array:
	var roll := rng.randf()
	if roll < 0.25:
		return ["clay", rng.randi_range(2, 3)]
	if roll < 0.29:
		return ["starfall_shard", 1]
	var fossil := _pick(rng, ItemDatabase.in_category("fossil"))
	return [fossil.id, 1] if fossil else ["clay", 1]


## What searching a tide pool at low tide finds.
static func tide_pool(rng: RandomNumberGenerator) -> Array:
	var item := _pick(rng, ItemDatabase.in_category("shore"))
	return [item.id, 1] if item else []


## How many times a day each kind of prop can be harvested.
static func harvests_per_day(source: String, shake: bool) -> int:
	if shake or source == "tide_pool":
		return 1
	return 4 if source == "rock" else 3
