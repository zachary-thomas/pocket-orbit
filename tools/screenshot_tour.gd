extends Node
## Look-test screenshot tour: poses the camera at set times of day, saves a
## PNG of each, walks the player over the north pole to check the camera stays
## steady, then quits.
##
##   godot --path . -- --tour=<output folder>

var output_dir := "user://tour"

var _main: Node
var _sky: SkySystem
var _camera: PlanetCamera
var _player: Player
var _planet: Planet


func _ready() -> void:
	_main = get_parent()
	_sky = _main.sky
	_camera = _main.camera
	_player = _main.player
	_planet = _main.planet
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output_dir)
	var home_up := _planet.tile_center(_planet.data.home_tile)

	# On the ground at home.
	await _surface_shot("01_surface_morning", 9.5, false)
	await _surface_shot("02_surface_noon", 13.0, false)
	await _surface_shot("03_surface_sunset_facing_sun", 18.7, true)
	await _surface_shot("04_surface_dusk_village", 19.6, false)
	await _surface_shot("05_surface_night_village", 23.0, false)

	# From orbit.
	_sky.set_home_hours(12.0)
	await _frames(2)
	await _orbit_shot("06_orbit_day", (home_up * 2.0 + _sky.sun_direction).normalized(), 3.4)
	_sky.set_home_hours(18.0)
	await _frames(2)
	await _orbit_shot("07_orbit_terminator", home_up, 3.4)
	_sky.set_home_hours(0.5)
	await _frames(2)
	await _orbit_shot("08_orbit_night_side", home_up, 2.6)

	await _walk_over_pole()
	await _measure("surface", false)
	await _measure("orbit", true)
	print("Tour saved to ", ProjectSettings.globalize_path(output_dir))
	get_tree().quit()


func _surface_shot(file: String, hours: float, face_sun: bool) -> void:
	_sky.set_home_hours(hours)
	_sky.paused = true
	_player.spawn(_planet, _planet.data.home_tile)
	_camera.reset_behind()
	_camera.set_orbit_mode(false, true)
	if face_sun:
		_camera.surface_forward = SphereMath.tangent(_sky.sun_direction, _player.get_up())
	await _frames(4)
	await _save(file)


func _orbit_shot(file: String, direction: Vector3, radii: float) -> void:
	_sky.paused = true
	_camera.look_from(direction, Vector3.UP, radii)
	await _frames(4)
	await _save(file)


## Walks straight across the north pole and reports the largest frame-to-frame
## turn of the camera heading (after transporting it to the new ground plane).
## Anything near zero means no spinning at the pole.
func _walk_over_pole() -> void:
	_sky.set_home_hours(12.0)
	var start := _planet.find_tile_dir(Vector3(0.0, 0.97, -0.24).normalized())
	_player.spawn(_planet, start)
	_camera.reset_behind()
	_camera.set_orbit_mode(false, true)
	_camera.surface_forward = SphereMath.tangent(Vector3.UP, _player.get_up())
	var worst := 0.0
	var previous := _camera.surface_forward
	var start_lat := SphereMath.latitude_degrees(_player.get_up())
	var max_lat := start_lat
	for i in 240:
		_player.move_along_surface(_camera.surface_forward * 0.25)
		_player.update_vertical(1.0 / 60.0)
		await _frames(1)
		var up := _player.get_up()
		var carried := SphereMath.tangent(previous, up)
		worst = maxf(worst, rad_to_deg(carried.angle_to(_camera.surface_forward)))
		previous = _camera.surface_forward
		max_lat = maxf(max_lat, SphereMath.latitude_degrees(up))
		if i == 120:
			await _save("09_surface_polar")
	var end_lat := SphereMath.latitude_degrees(_player.get_up())
	print("Pole walk: latitude %.1f -> max %.1f -> %.1f, largest camera turn per frame %.3f deg" % [start_lat, max_lat, end_lat, worst])


## Frame rate and triangles on screen after things settle, with the sky
## clock running.
func _measure(label: String, orbit: bool) -> void:
	_sky.set_home_hours(15.0)
	_player.spawn(_planet, _planet.data.home_tile)
	_camera.reset_behind()
	_camera.set_orbit_mode(orbit, true)
	await _frames(180)
	var triangles := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	print("Performance %s: %d fps, %d triangles, %d draw calls" % [label, Engine.get_frames_per_second(), triangles,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])


func _save(file: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(output_dir.path_join(file + ".png"))


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
