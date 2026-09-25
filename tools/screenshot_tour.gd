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
	await _cliff_shot("10_surface_cliffs_and_trees", 15.0)
	await _sanctuary_shots()

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


## The village with everything built and villagers about, a tide pool at low
## tide, and the same view in autumn and winter.
func _sanctuary_shots() -> void:
	var game: Game = _main.game
	var state := game.state
	state.stardust = 50000
	state.debt = 0
	state.reputation = 60
	for item: String in ["wood", "stone", "clay", "copper_ore"]:
		game.run({"type": "collect", "item": item, "count": 40})
	game.run({"type": "upgrade_shop"})
	var kinds := ["landing_pad", "archive", "burrow_house"]
	var plots: Array = _planet.data.village.get("plots", [])
	for i in mini(kinds.size(), plots.size()):
		game.run({"type": "build", "kind": kinds[i], "plot": plots[i]["id"]})
	for shelf in 12:
		game.run({"type": "collect", "item": ["meadow_trout", "apple", "amethyst", "glowbug"][shelf % 4]})
		for slot in state.inventory.size():
			if state.inventory.item_at(slot) in ["meadow_trout", "apple", "amethyst", "glowbug"]:
				game.run({"type": "stock_shelf", "slot": slot, "shelf": shelf})
				break
	for species: Dictionary in VillageData.all_species():
		VillageRules.request_move_in(state, species, state.day)
		game.run({"type": "accept_resident", "id": VillageRules.pending_request(state)["id"]})
	state.parcels.append({"item": "wood", "count": 5})
	game.run({"type": "set_flag", "flag": "tour"})
	_main.village.rebuild()
	_sky.set_home_hours(11.0)
	_sky.paused = true
	_player.spawn(_planet, _planet.data.village["street_tile"])
	_camera.reset_behind()
	_camera.set_orbit_mode(false, true)
	_camera.surface_forward = SphereMath.tangent(_planet.tile_center(_planet.data.home_tile) - _planet.tile_center(_planet.data.village["street_tile"]), _player.get_up())
	_camera.distance = 20.0
	_camera.pitch_degrees = 40.0
	await _frames(240)
	await _save("11_village_built")
	_camera.distance = 8.5
	_camera.pitch_degrees = 16.0
	await _frames(4)
	await _save("12_general_shop")
	# The villagers and the inspector lined up in front of the player.
	state.audit["next"] = state.day
	_main.village._spawn_auditor()
	var folk: Array = _main.village.villager_nodes()
	folk.append(_main.village.auditor)
	var up := _player.get_up()
	var side := _player.get_up().cross(_camera.surface_forward).normalized()
	for i in folk.size():
		var npc: Npc = folk[i]
		npc.visible = true
		npc.set_route(PackedVector3Array())
		npc.set_process(false)
		var spot := _player.global_position + _camera.surface_forward * 3.2 + side * (i - (folk.size() - 1) * 0.5) * 1.2
		var dir := _planet.up_at(spot)
		var tile := _planet.find_tile_dir(dir, _player.tile)
		npc.spawn(_planet, tile)
		npc.global_position = _planet.global_position + dir * _planet.ground_radius(tile)
		npc.face(_player.global_position - _camera.surface_forward * 6.0)
	_camera.distance = 6.5
	_camera.pitch_degrees = 12.0
	await _frames(4)
	await _save("16_villagers")
	for npc: Npc in folk:
		npc.set_process(true)
	# A tide pool near home at low tide.
	var pool := {}
	for prop: Dictionary in _planet.data.props:
		if prop["model"] == "tide_pool":
			pool = prop
			break
	if not pool.is_empty():
		for hour in 48:
			_sky.set_home_hours(7.0 + hour * 0.25)
			await _frames(1)
			if _sky.water_depth(pool["tile"]) < -0.02:
				break
		var shore := -1
		for n in _planet.data.sphere.neighbors(pool["tile"]):
			if not _planet.data.is_water(n):
				shore = n
		if shore != -1:
			_player.spawn(_planet, shore)
			_camera.surface_forward = SphereMath.tangent(_planet.tile_center(pool["tile"]) - _planet.tile_center(shore), _player.get_up())
			_camera.distance = 11.0
			_camera.pitch_degrees = 35.0
			await _frames(6)
			await _save("13_tide_pool_low_tide")
	# Seasons: the village in mid-October and mid-January.
	for shot: Array in [["14_autumn", 2026, 10, 20], ["15_winter", 2027, 1, 20]]:
		_sky.day_index = int(Time.get_unix_time_from_datetime_dict({"year": shot[1], "month": shot[2], "day": shot[3]}) / 86400)
		_sky.set_home_hours(12.0)
		_player.spawn(_planet, _planet.data.village["street_tile"])
		_camera.reset_behind()
		_camera.distance = 18.0
		_camera.pitch_degrees = 35.0
		await _frames(30)
		await _save(shot[0])
	_camera.distance = 8.5
	_camera.pitch_degrees = 16.0


## Stands near home at the foot of a terrace with trees on it, looking up at it.
func _cliff_shot(file: String, hours: float) -> void:
	var data := _planet.data
	var area := data.tiles_within(data.home_tile, 7)
	var best := -1
	var target := -1
	for t: int in area:
		if area[t] < 3 or data.is_water(t):
			continue
		for n in data.sphere.neighbors(t):
			if data.level[n] == data.level[t] + 1 and data.biome[n] != Biome.OCEAN:
				if best == -1 or t < best:
					best = t
					target = n
	if best == -1:
		return
	_sky.set_home_hours(hours)
	_sky.paused = true
	_player.spawn(_planet, best)
	_camera.set_orbit_mode(false, true)
	_camera.surface_forward = SphereMath.tangent(_planet.tile_center(target) - _planet.tile_center(best), _player.get_up())
	_player.heading = _camera.surface_forward
	_camera.distance = 14.0
	_camera.pitch_degrees = 38.0
	await _frames(4)
	await _save(file)
	_camera.distance = 8.5
	_camera.pitch_degrees = 16.0


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
