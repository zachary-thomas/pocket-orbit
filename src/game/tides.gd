class_name Tides
extends RefCounted
## The moon and the tides it raises.
##
## The moon circles the planet in the equatorial plane once every
## MOON_PERIOD_HOURS of planet time, a little slower than the sun, so it rises
## about 50 minutes later each day. Its pull lifts the sea in a bulge under it
## and another on the far side: the local sea height is
##   AMPLITUDE * cos(2 * (longitude - moon longitude))
## which gives two high and two low tides a day everywhere, like on Earth.
##
## At low tide the sea drops below the lowest terrace, so the shallow tiles
## along the coast (tide flats) can be waded across and their tide pools
## searched. Pure functions of time, so they can be tested and later agreed
## on between players.

const AMPLITUDE := 0.5
## Relative to the sun's daily circle, as on Earth (a lunar day).
const MOON_PERIOD_HOURS := 24.84
## Water shallower than this can be waded through.
const WADE_DEPTH := 0.3


## Planet time in seconds: the clock at home plus whole days.
static func planet_seconds(day_index: int, home_seconds: float) -> float:
	return day_index * 86400.0 + home_seconds


## Unit direction from the planet's centre toward the moon. Uses the same
## longitude convention as the sun in SkySystem.
static func moon_direction(seconds: float, home_longitude: float) -> Vector3:
	var turns := seconds / (MOON_PERIOD_HOURS * 3600.0)
	var longitude := home_longitude - fposmod(turns, 1.0) * TAU + 0.7
	return Vector3(cos(longitude), 0.0, -sin(longitude))


## Sea height above its average at a direction from the planet's centre, in
## metres (-AMPLITUDE .. AMPLITUDE).
static func height(dir: Vector3, moon_dir: Vector3) -> float:
	var flat := Vector2(dir.x, dir.z)
	if flat.length_squared() < 1e-8:
		return 0.0
	var c := flat.normalized().dot(Vector2(moon_dir.x, moon_dir.z))
	return AMPLITUDE * (2.0 * c * c - 1.0)


## Local water depth over ground at `ground_radius`, given the average sea
## level and the local tide.
static func depth(ground_radius: float, sea_level_radius: float, tide: float) -> float:
	return sea_level_radius + tide - ground_radius


static func describe(tide: float) -> String:
	if tide < -AMPLITUDE * 0.55:
		return "low tide"
	if tide > AMPLITUDE * 0.55:
		return "high tide"
	return "mid tide"
