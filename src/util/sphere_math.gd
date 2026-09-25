class_name SphereMath
extends RefCounted
## Small helpers for working on the surface of a sphere.
##
## Conventions used across the project:
## - Directions are unit vectors from the planet centre.
## - Latitude is measured from the equator toward +Y (north).
## - Longitude grows toward the east, which is the direction the planet "turns"
##   relative to the sun, so walking east moves you later into the day.


## Removes the part of `v` that points along `up`, leaving a unit vector in the
## ground plane. Falls back to any perpendicular when `v` is (nearly) vertical.
static func tangent(v: Vector3, up: Vector3) -> Vector3:
	var t := v - up * v.dot(up)
	if t.length_squared() < 1e-10:
		return any_perpendicular(up)
	return t.normalized()


static func any_perpendicular(n: Vector3) -> Vector3:
	var reference := Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT
	return n.cross(reference).normalized()


## Basis whose Y axis is `up`, turned `yaw` radians around it. Used to stand
## props upright on the planet.
static func basis_from_up(up: Vector3, yaw: float = 0.0) -> Basis:
	var x := any_perpendicular(up)
	var z := x.cross(up)
	return Basis(x, up, z).rotated(up, yaw)


## Basis whose Y axis is `up` and whose +Z (the model's front, for buildings)
## points toward `toward` along the ground.
static func basis_facing(up: Vector3, toward: Vector3) -> Basis:
	var z := tangent(toward, up)
	var x := up.cross(z)
	return Basis(x, up, z)


static func latitude_degrees(dir: Vector3) -> float:
	return rad_to_deg(asin(clampf(dir.y, -1.0, 1.0)))


## Radians, -PI..PI, increasing toward the east.
static func longitude(dir: Vector3) -> float:
	return atan2(-dir.z, dir.x)
