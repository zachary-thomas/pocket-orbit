class_name DigSpots
extends Node3D
## Little mounds of loose earth with a crack across them, a few rings out
## from the village: dig them with the shovel for fossils and clay. A new set
## turns up every day, the same for everyone on the same planet and day.

const PER_DAY := 6
## Rings out from home they turn up in.
const MIN_RING := 3
const MAX_RING := 7

var game: Game
var _material: Material
var _day := -1
## Spot id -> world position, for today's undug spots.
var _spots := {}


func setup(p_game: Game, material: Material) -> void:
	game = p_game
	_material = material
	_day = -1
	game.state.changed.connect(func(what: String) -> void:
		if what in ["harvest", "new_day"]:
			refresh())
	refresh()


## Today's spots, dug or not: id -> position relative to the planet centre.
static func spots_for(data: PlanetData, graph: TileGraph, world_seed: int, day: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, day, "dig"])
	var rings := data.tiles_within(data.home_tile, MAX_RING)
	var tiles: Array[int] = []
	for t: int in rings:
		if rings[t] >= MIN_RING and not data.is_water(t) and not graph.is_blocked(t) and not data.sphere.is_pentagon(t):
			tiles.append(t)
	tiles.sort()
	var result := {}
	for attempt in PER_DAY * 4:
		if result.size() >= PER_DAY or tiles.is_empty():
			break
		var t: int = tiles[rng.randi() % tiles.size()]
		var id := "dig-%d" % t
		if result.has(id):
			continue
		# Keep clear of trees and rocks on the tile.
		var xf := PropPlacer.scatter_transform(data, t, rng, 0.6)
		var clear := true
		for prop: Dictionary in data.props_by_tile.get(t, []):
			if (prop["xf"] as Transform3D).origin.distance_to(xf.origin) < prop["radius"] + 0.9:
				clear = false
		if clear:
			result[id] = xf
	return result


func refresh() -> void:
	for child in get_children():
		child.queue_free()
	_spots.clear()
	var state := game.state
	var planet := game.planet
	var all := spots_for(planet.data, game.graph, state.world_seed, state.day)
	var md := MeshData.new()
	for id: String in all:
		var record: Dictionary = state.harvests.get(id, {})
		if int(record.get("day", -1)) == state.day:
			continue
		var xf: Transform3D = all[id]
		_spots[id] = planet.global_position + xf.origin
		_mound(md, xf)
	if not md.is_empty():
		var mesh := MeshInstance3D.new()
		mesh.mesh = md.to_mesh(_material)
		add_child(mesh)
		mesh.global_position = planet.global_position


static func _mound(md: MeshData, xf: Transform3D) -> void:
	md.tint = Color.WHITE
	md.add_blob(xf.translated_local(Vector3(0, 0.02, 0)), Vector3(0.55, 0.14, 0.5), Palette.uv("dirt"))
	md.add_blob(xf.translated_local(Vector3(0.28, 0.04, -0.2)), Vector3(0.22, 0.09, 0.2), Palette.uv("dirt"))
	# An X of dark cracks on top, and a few pebbles.
	for a: float in [0.6, -0.6]:
		md.add_box(xf.translated_local(Vector3(0, 0.15, 0)).rotated_local(Vector3.UP, a), Vector3(0.5, 0.02, 0.07), Palette.uv("dirt_dark"))
	for p: Vector3 in [Vector3(-0.45, 0.03, 0.2), Vector3(0.4, 0.03, 0.3), Vector3(-0.1, 0.03, -0.48)]:
		md.add_blob(xf.translated_local(p), Vector3(0.08, 0.05, 0.07), Palette.uv("stone"))


## Undug spots today: id -> world position.
func spots() -> Dictionary:
	return _spots
