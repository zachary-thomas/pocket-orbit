class_name PlanetData
extends RefCounted
## Everything the generator decides about one planet. It holds only plain data
## (no nodes), so game rules can run on it without the 3D scene. The same seed
## always produces the same PlanetData.
##
## Heights are whole "levels" (terraces). Level 0 and below are under water;
## level 1 is the first dry step above the sea.

var world_seed: int
var sphere: HexSphere
## Radius of the level-0 terrace, in metres.
var radius: float
## Height of one terrace step, in metres.
var level_height: float
var sea_level_radius: float

var level := PackedInt32Array()
var biome := PackedByteArray()
## 0 (polar) .. 1 (equator), after cooling with altitude.
var temperature := PackedFloat32Array()
## 0 (dry) .. 1 (wet).
var moisture := PackedFloat32Array()
## Where the village starts and the player spawns.
var home_tile := -1


func tile_count() -> int:
	return sphere.tile_count()


func top_radius(tile: int) -> float:
	return radius + level[tile] * level_height


func is_water(tile: int) -> bool:
	return level[tile] <= 0


func is_coast(tile: int) -> bool:
	if is_water(tile):
		return false
	for n in sphere.neighbors(tile):
		if is_water(n):
			return true
	return false


## Tiles within `rings` steps of `tile` (including it), mapped to their ring.
func tiles_within(tile: int, rings: int) -> Dictionary:
	var found := {tile: 0}
	var frontier: Array[int] = [tile]
	for ring in range(1, rings + 1):
		var next: Array[int] = []
		for t in frontier:
			for n in sphere.neighbors(t):
				if not found.has(n):
					found[n] = ring
					next.append(n)
		frontier = next
	return found
