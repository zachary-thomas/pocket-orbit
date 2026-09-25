class_name GravityBody
extends Node3D
## Anything that stands on a planet: the player now, villagers and dropped
## items later.
##
## "Up" is always the direction from the planet centre to the body. Rather than
## a global north, the body keeps its own heading (a unit vector in the local
## ground plane) and re-projects it onto the new ground plane every time it
## moves, so nothing flips or spins at the poles.
##
## Movement is tile-based rather than physics-based: the body can step up one
## terrace, drops off higher ones, and is blocked by taller cliffs and water.
## Trees, rocks and buildings are circles it can't walk into. That keeps it
## cheap on phones and matches how tiles work in the rules.
##
## A body can also follow a route (a list of directions, usually tile centres
## from TileGraph.find_path) for tap-to-walk and villagers.

signal arrived

@export var gravity := 20.0
@export var max_step_levels := 1
@export var step_up_speed := 9.0
## Collision radius against props.
@export var body_radius := 0.35
## Props with a smaller collision radius than this are walked through.
@export var min_prop_radius := 0.0

var planet: Planet
var tile := 0
var heading := Vector3.FORWARD
var vertical_speed := 0.0
var on_ground := true

## Distance from the planet centre to the body's feet.
var _radius := 0.0
## Ground-plane direction into whatever blocked the last step.
var _block_dir := Vector3.ZERO
## Directions still to walk through, nearest first.
var route := PackedVector3Array()
var _stuck_time := 0.0


func spawn(p_planet: Planet, p_tile: int) -> void:
	planet = p_planet
	tile = p_tile
	var up := planet.tile_center(tile)
	_radius = planet.ground_radius(tile)
	global_position = planet.global_position + up * _radius
	# Start facing north, or any direction if standing on a pole.
	heading = SphereMath.tangent(Vector3.UP, up)
	vertical_speed = 0.0
	on_ground = true
	_update_basis()


func get_up() -> Vector3:
	return planet.up_at(global_position)


## Moves by `step` (metres, roughly along the ground). If the way is blocked,
## slides along the blocking tile edge instead of stopping dead.
func move_along_surface(step: Vector3) -> void:
	if planet == null or step.length_squared() < 1e-10:
		return
	if _try_step(step):
		return
	var up := get_up()
	var into_wall := SphereMath.tangent(_block_dir, up)
	var slide := step - into_wall * maxf(step.dot(into_wall), 0.0)
	if slide.length_squared() > 1e-10:
		_try_step(slide)


## Rise onto a terrace just walked onto, or fall under gravity.
func update_vertical(delta: float) -> void:
	if planet == null:
		return
	var ground := planet.ground_radius(tile)
	if _radius < ground:
		# Stepped up a terrace: rise quickly instead of popping up.
		_radius = move_toward(_radius, ground, step_up_speed * delta)
		vertical_speed = 0.0
		on_ground = true
	elif _radius > ground or vertical_speed > 0.0:
		vertical_speed -= gravity * delta
		_radius += vertical_speed * delta
		if _radius <= ground:
			_radius = ground
			vertical_speed = 0.0
			on_ground = true
		else:
			on_ground = false
	else:
		on_ground = true
	global_position = planet.global_position + get_up() * _radius
	_update_basis()


## Turn the heading toward `direction` (a ground-plane vector) by `weight` (0..1).
func turn_towards(direction: Vector3, weight: float) -> void:
	var up := get_up()
	var target := SphereMath.tangent(direction, up)
	heading = SphereMath.tangent(heading.slerp(target, clampf(weight, 0.0, 1.0)), up)


func _try_step(step: Vector3) -> bool:
	var up := get_up()
	var new_up := (up * _radius + step).normalized()
	var new_tile := planet.find_tile_dir(new_up, tile)
	if new_tile != tile and not _can_enter(new_tile):
		_block_dir = planet.tile_center(new_tile) - planet.tile_center(tile)
		return false
	var prop_dir := _prop_in_the_way(up, new_up, new_tile)
	if prop_dir != Vector3.ZERO:
		_block_dir = prop_dir - up
		return false
	tile = new_tile
	global_position = planet.global_position + new_up * _radius
	# Parallel transport: carry the heading over to the new ground plane.
	heading = SphereMath.tangent(heading, new_up)
	return true


## Direction of a prop the step would walk into (getting closer to it while
## inside its radius), or zero. Moving away is always allowed, so nothing can
## get stuck inside a prop.
func _prop_in_the_way(up: Vector3, new_up: Vector3, new_tile: int) -> Vector3:
	for prop: Dictionary in planet.data.props_near(new_tile):
		var r: float = prop["radius"]
		if r <= 0.0 or r < min_prop_radius:
			continue
		var dir: Vector3 = (prop["xf"] as Transform3D).origin.normalized()
		var reach := (r + body_radius) / _radius
		var new_angle := new_up.angle_to(dir)
		if new_angle < reach and new_angle < up.angle_to(dir):
			return dir
	return Vector3.ZERO


# --- Routes --------------------------------------------------------------------

func set_route(directions: PackedVector3Array) -> void:
	route = directions
	_stuck_time = 0.0


func has_route() -> bool:
	return not route.is_empty()


## Walks along the route at `speed` for one frame. Returns the ground-plane
## direction walked (zero once there). Waypoints count as reached within
## `waypoint_reach` metres, the last one within `arrive_reach`. If something
## blocks the way for a while, sidesteps, then gives up on that waypoint.
func follow_route(delta: float, speed: float, arrive_reach: float = 0.35, waypoint_reach: float = 1.4) -> Vector3:
	var up := get_up()
	while not route.is_empty():
		var reach := arrive_reach if route.size() == 1 else waypoint_reach
		if up.angle_to(route[0]) * _radius > reach:
			break
		route.remove_at(0)
		if route.is_empty():
			arrived.emit()
	if route.is_empty():
		return Vector3.ZERO
	var remaining := up.angle_to(route[0]) * _radius
	var wish := SphereMath.tangent(route[0] - up, up)
	var before := global_position
	var step := minf(speed * delta, remaining)
	move_along_surface(wish * step)
	if before.distance_to(global_position) < step * 0.3:
		_stuck_time += delta
		if _stuck_time > 0.35:
			move_along_surface(wish.cross(up) * step)
		if _stuck_time > 1.5:
			_stuck_time = 0.0
			route.remove_at(0)
			if route.is_empty():
				arrived.emit()
	else:
		_stuck_time = 0.0
	return wish


func _can_enter(target: int) -> bool:
	if not planet.is_walkable(target):
		return false
	var rise := planet.ground_radius(target) - _radius
	return rise <= max_step_levels * planet.level_height + 0.05


func _update_basis() -> void:
	var up := get_up()
	heading = SphereMath.tangent(heading, up)
	var back := -heading
	global_transform.basis = Basis(up.cross(back), up, back)
