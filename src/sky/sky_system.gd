class_name SkySystem
extends Node3D
## The sun, the space background and the clock.
##
## Time of day follows the real local clock at the home village: when it's
## 18:00 on your phone, it's 18:00 at home. The planet doesn't spin; the sun
## circles it once per real day. Walk east from home and local time runs ahead
## (you reach evening sooner); walk west and it falls behind.
##
## The debug HUD can switch to a simulated clock that runs faster or can be
## scrubbed, since waiting hours for a sunset makes testing slow.

const AXIAL_TILT_DEGREES := 23.4
const SECONDS_PER_DAY := 86400.0
const SPACE_SKY_SHADER := preload("res://shaders/space_sky.gdshader")

var planet: Planet
## Whose local time and daylight the HUD and shadow toggle use (the player).
var observer: Node3D

var use_real_clock := true
var paused := false
## Simulated seconds per real second when not on the real clock.
var time_scale := 1.0
## Local time at home, in seconds since midnight.
var home_seconds := 0.0
var day_of_year := 172
## Unit vector from the planet toward the sun.
var sun_direction := Vector3.UP
var home_longitude := 0.0

var sun: DirectionalLight3D
var environment: Environment
var _sky_material: ShaderMaterial


func _ready() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color("fff1d6")
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 45.0
	add_child(sun)

	_sky_material = ShaderMaterial.new()
	_sky_material.shader = SPACE_SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = _sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	# Sky fill light is done per fragment in planet_lighting.gdshaderinc, since
	# the day and night sides need different ambient light at the same time.
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.BLACK
	environment.ambient_light_energy = 0.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.glow_enabled = true
	environment.glow_intensity = 0.7
	environment.glow_bloom = 0.05
	environment.glow_hdr_threshold = 1.0
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)

	day_of_year = _current_day_of_year()
	home_seconds = _real_seconds()


func setup(p_planet: Planet, p_observer: Node3D) -> void:
	planet = p_planet
	observer = p_observer
	home_longitude = SphereMath.longitude(planet.tile_center(planet.data.home_tile))
	_sky_material.set_shader_parameter("planet_center", planet.global_position)
	_sky_material.set_shader_parameter("atmosphere_radius", planet.atmosphere_radius)
	_update_sun()


func _process(delta: float) -> void:
	if use_real_clock:
		home_seconds = _real_seconds()
	elif not paused:
		home_seconds = fposmod(home_seconds + delta * time_scale, SECONDS_PER_DAY)
	_update_sun()


# --- Controls used by the debug HUD ------------------------------------------

func set_home_hours(hours: float) -> void:
	use_real_clock = false
	home_seconds = fposmod(hours * 3600.0, SECONDS_PER_DAY)


func use_real_time() -> void:
	use_real_clock = true
	paused = false
	time_scale = 1.0


func set_speed(multiplier: float) -> void:
	use_real_clock = false
	paused = false
	time_scale = multiplier


func toggle_pause() -> void:
	use_real_clock = false
	paused = not paused


## Local solar time, in hours, at a point on the planet.
func local_hours_at(world_position: Vector3) -> float:
	var lon := SphereMath.longitude(planet.up_at(world_position))
	return fposmod(home_seconds / 3600.0 + (lon - home_longitude) / TAU * 24.0, 24.0)


func clock_label() -> String:
	if use_real_clock:
		return "real clock"
	if paused:
		return "paused"
	return "x%d" % int(time_scale)


# --- Sun ---------------------------------------------------------------------

## Sun direction from the time at home. The sun sits over home's longitude at
## noon and moves west as the day goes on (longitude grows toward the east, so
## it drops by a full turn per day). Its latitude follows the seasons from the
## axial tilt: the sun is over the northern tropic in June.
func _update_sun() -> void:
	var declination := deg_to_rad(AXIAL_TILT_DEGREES) * sin(TAU * (day_of_year - 80) / 365.0)
	var sun_longitude := home_longitude - (home_seconds / SECONDS_PER_DAY - 0.5) * TAU
	sun_direction = Vector3(
		cos(declination) * cos(sun_longitude),
		sin(declination),
		-cos(declination) * sin(sun_longitude))
	# A directional light shines along its -Z axis, i.e. away from the sun.
	var up_hint := Vector3.UP if absf(sun_direction.y) < 0.99 else Vector3.RIGHT
	sun.global_transform.basis = Basis.looking_at(-sun_direction, up_hint)
	RenderingServer.global_shader_parameter_set("sun_direction", sun_direction)
	if planet == null:
		return

	# Lamps come on after sunset where they stand.
	for lamp: Node3D in get_tree().get_nodes_in_group("night_lights"):
		lamp.visible = planet.up_at(lamp.global_position).dot(sun_direction) < 0.08
	# Shadow maps only matter where the observer can see sunlight.
	if observer:
		sun.shadow_enabled = planet.up_at(observer.global_position).dot(sun_direction) > -0.1


func _real_seconds() -> float:
	var t := Time.get_time_dict_from_system()
	var fraction := fmod(Time.get_unix_time_from_system(), 1.0)
	return t.hour * 3600.0 + t.minute * 60.0 + t.second + fraction


func _current_day_of_year() -> int:
	var today := Time.get_date_dict_from_system()
	var start := Time.get_unix_time_from_datetime_dict({"year": today.year, "month": 1, "day": 1})
	var now := Time.get_unix_time_from_datetime_dict(today)
	return int((now - start) / SECONDS_PER_DAY) + 1
