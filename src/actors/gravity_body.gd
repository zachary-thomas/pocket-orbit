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
## That keeps it cheap on phones and matches how tiles work in the rules.

@export var gravity := 20.0
@export var max_step_levels := 1
@export var step_up_speed := 9.0

var planet: Planet
var tile := 0
var heading := Vector3.FORWARD
var vertical_speed := 0.0
var on_ground := true

## Distance from the planet centre to the body's feet.
var _radius := 0.0
var _blocked_tile := -1


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
	var into_wall := SphereMath.tangent(planet.tile_center(_blocked_tile) - planet.tile_center(tile), up)
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
		_blocked_tile = new_tile
		return false
	tile = new_tile
	global_position = planet.global_position + new_up * _radius
	# Parallel transport: carry the heading over to the new ground plane.
	heading = SphereMath.tangent(heading, new_up)
	return true


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
