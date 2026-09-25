class_name TileGraph
extends RefCounted
## Walking routes and placement spots on the hex planet.
##
## Pathfinding is A* over tile neighbours. The engine's navigation meshes
## assume flat ground, so the planet does its own. A step to a neighbour is
## allowed if it's dry land at most one terrace higher (dropping down any
## number of terraces is fine), and the tile isn't taken by a building.
##
## Placement: tiles are about 8.7 m across, too coarse to place things on
## directly, so each tile has 7 spots (6 on a pentagon): its centre plus one
## part-way toward each corner. Spot ids are tile * 7 + k.

const SLOTS_PER_TILE := 7
## How far toward the corner the outer spots sit (0 = centre, 1 = corner).
const SLOT_REACH := 0.55

var data: PlanetData
var _blocked := {}


func _init(p_data: PlanetData) -> void:
	data = p_data


func block(tile: int) -> void:
	_blocked[tile] = true


func is_blocked(tile: int) -> bool:
	return _blocked.has(tile)


func can_step(from: int, to: int) -> bool:
	if data.is_water(to) or _blocked.has(to):
		return false
	return data.level[to] - data.level[from] <= 1


## Tiles from `start` to `goal` inclusive, or [] if there's no way. If the
## goal itself can't be entered (water, a building), the path ends next to it.
func find_path(start: int, goal: int) -> PackedInt32Array:
	if start == goal:
		return PackedInt32Array([start])
	var sphere := data.sphere
	var goal_dir := sphere.centers[goal]
	var came_from := {start: -1}
	var cost := {start: 0.0}
	var open := _Heap.new()
	open.push(start, 0.0)
	var reached := -1
	while not open.is_empty():
		var current := open.pop()
		if current == goal:
			reached = goal
			break
		var goal_adjacent := false
		for n in sphere.neighbors(current):
			if n == goal and not can_step(current, goal):
				goal_adjacent = true
				continue
			if not can_step(current, n):
				continue
			var step := sphere.centers[current].angle_to(sphere.centers[n])
			var new_cost: float = cost[current] + step
			if not cost.has(n) or new_cost < cost[n]:
				cost[n] = new_cost
				came_from[n] = current
				open.push(n, new_cost + sphere.centers[n].angle_to(goal_dir))
		if goal_adjacent:
			reached = current
			break
	if reached == -1:
		return PackedInt32Array()
	var path := PackedInt32Array()
	var at := reached
	while at != -1:
		path.append(at)
		at = came_from[at]
	path.reverse()
	return path


## Waypoints (unit directions) for walking from tile `start` to the point
## `target` (a direction): the centres of the tiles on the way, then the
## target itself. If the target can't be reached exactly (it's in water or a
## building), the route stops at the nearest tile centre next to it. Empty if
## there's no way at all.
func route(start: int, target: Vector3) -> PackedVector3Array:
	var goal := data.sphere.find_tile(target, start)
	var path := find_path(start, goal)
	var points := PackedVector3Array()
	if path.is_empty():
		return points
	for i in range(1, path.size() - 1):
		points.append(data.sphere.centers[path[i]])
	if path[-1] == goal:
		points.append(target.normalized())
	elif path.size() > 1:
		points.append(data.sphere.centers[path[-1]])
	return points


# --- Placement spots ---------------------------------------------------------

func slot_count(tile: int) -> int:
	return 1 + data.sphere.corner_count(tile)


func slot_id(tile: int, k: int) -> int:
	return tile * SLOTS_PER_TILE + k


func slot_tile(slot: int) -> int:
	@warning_ignore("integer_division")
	return slot / SLOTS_PER_TILE


## Unit direction of a spot.
func slot_direction(slot: int) -> Vector3:
	var tile := slot_tile(slot)
	var k := slot % SLOTS_PER_TILE
	var center := data.sphere.centers[tile]
	if k == 0:
		return center
	var corner := data.sphere.corners[data.sphere.corner_start[tile] + k - 1]
	return center.lerp(corner, SLOT_REACH).normalized()


func slot_position(slot: int) -> Vector3:
	return slot_direction(slot) * data.top_radius(slot_tile(slot))


## The spot nearest to a direction on a given tile.
func nearest_slot(tile: int, dir: Vector3) -> int:
	var best := slot_id(tile, 0)
	var best_dot := -2.0
	for k in slot_count(tile):
		var d := slot_direction(slot_id(tile, k)).dot(dir)
		if d > best_dot:
			best_dot = d
			best = slot_id(tile, k)
	return best


## Minimal binary heap of (tile, priority) for A*.
class _Heap:
	var _tiles := PackedInt32Array()
	var _keys := PackedFloat32Array()

	func is_empty() -> bool:
		return _tiles.is_empty()

	func push(tile: int, key: float) -> void:
		_tiles.append(tile)
		_keys.append(key)
		var i := _tiles.size() - 1
		while i > 0:
			@warning_ignore("integer_division")
			var parent := (i - 1) / 2
			if _keys[parent] <= _keys[i]:
				break
			_swap(i, parent)
			i = parent

	func pop() -> int:
		var top := _tiles[0]
		var last := _tiles.size() - 1
		_swap(0, last)
		_tiles.resize(last)
		_keys.resize(last)
		var i := 0
		while true:
			var left := i * 2 + 1
			var right := left + 1
			var smallest := i
			if left < last and _keys[left] < _keys[smallest]:
				smallest = left
			if right < last and _keys[right] < _keys[smallest]:
				smallest = right
			if smallest == i:
				break
			_swap(i, smallest)
			i = smallest
		return top

	func _swap(a: int, b: int) -> void:
		var t := _tiles[a]
		_tiles[a] = _tiles[b]
		_tiles[b] = t
		var k := _keys[a]
		_keys[a] = _keys[b]
		_keys[b] = k
