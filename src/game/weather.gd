class_name Weather
extends Node3D
## Weather around the player: rain or snow showers, fireflies on summer
## nights and falling leaves in autumn. What's falling where is a pure
## function of the planet, day, time and place (kind_at), so everyone on the
## same planet sees the same weather; the particles just follow the player.

## Weather holds for blocks of this many hours.
const SPELL_HOURS := 6
## Chance of a shower in each block, by season.
const SHOWER_CHANCE := {"spring": 0.3, "summer": 0.15, "autumn": 0.35, "winter": 0.3}

var game: Game
var camera: Camera3D
var kind := ""
var _effects := {}
var _check := 0.0


func setup(p_game: Game, p_camera: Camera3D) -> void:
	game = p_game
	camera = p_camera
	if _effects.is_empty():
		_effects = {
			"rain": _make_rain(),
			"snow": _make_snow(),
			"fireflies": _make_fireflies(),
			"leaves": _make_leaves(),
		}
	kind = ""
	_check = 0.0


## What's falling or flying at a spot: "rain", "snow", "fireflies",
## "leaves" or "" for nothing.
static func kind_at(world_seed: int, day: int, hours: float, season: String, biome: int, latitude: float) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, day, int(hours / SPELL_HOURS), "weather"])
	var cold := biome in [Biome.SNOW, Biome.TUNDRA] or (season == "winter" and absf(latitude) > 30.0)
	var chance: float = SHOWER_CHANCE.get(season, 0.2)
	if biome == Biome.DESERT:
		chance *= 0.2
	if rng.randf() < chance:
		return "snow" if cold else "rain"
	var night := hours >= 20.5 or hours < 4.5
	var leafy := biome in [Biome.GRASSLAND, Biome.FOREST, Biome.JUNGLE]
	if night and leafy and season in ["spring", "summer"] and not cold:
		return "fireflies"
	if not night and leafy and season == "autumn":
		return "leaves"
	return ""


func _process(delta: float) -> void:
	if game == null or game.state == null or game.player.planet == null:
		return
	var player := game.player
	var up := player.get_up()
	global_transform = Transform3D(SphereMath.basis_from_up(up), player.global_position)
	_check -= delta
	if _check > 0.0:
		return
	_check = 2.0
	var planet := game.planet
	var lat := SphereMath.latitude_degrees(up)
	var now := kind_at(game.state.world_seed, game.state.day, game.hours_at(player.global_position),
		game.season_at(player.global_position), planet.data.biome[player.tile], lat)
	# From high up (orbit view) there's nothing to see down here.
	if camera and camera.global_position.distance_to(player.global_position) > 60.0:
		now = ""
	if now != kind:
		kind = now
		for name: String in _effects:
			_effects[name].emitting = name == kind


func _particles(amount: int, lifetime: float, mesh: PrimitiveMesh, color: Color, glow: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.emitting = false
	p.local_coords = true
	p.mesh = mesh
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.gravity = Vector3.ZERO
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if color.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	material.vertex_color_use_as_albedo = true
	if glow:
		material.emission_enabled = true
		material.emission = Color(color, 1.0)
		material.emission_energy_multiplier = 3.0
	mesh.material = material
	add_child(p)
	return p


func _make_rain() -> CPUParticles3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.025, 0.55, 0.025)
	var p := _particles(500, 0.9, mesh, Color(0.75, 0.85, 1.0, 0.55), false)
	p.position = Vector3(0, 11, 0)
	p.emission_box_extents = Vector3(15, 0.5, 15)
	p.direction = Vector3(0.05, -1, 0)
	p.spread = 2.0
	p.initial_velocity_min = 13.0
	p.initial_velocity_max = 15.0
	return p


func _make_snow() -> CPUParticles3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	mesh.radial_segments = 6
	mesh.rings = 3
	var p := _particles(350, 7.0, mesh, Color(1, 1, 1, 0.95), false)
	p.position = Vector3(0, 9, 0)
	p.emission_box_extents = Vector3(15, 0.5, 15)
	p.direction = Vector3(0, -1, 0)
	p.spread = 25.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 1.8
	return p


func _make_fireflies() -> CPUParticles3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.045
	mesh.height = 0.09
	mesh.radial_segments = 6
	mesh.rings = 3
	var p := _particles(45, 5.0, mesh, Color(1.0, 0.92, 0.45), true)
	p.position = Vector3(0, 1.2, 0)
	p.emission_box_extents = Vector3(10, 1.0, 10)
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.4
	var fade := Curve.new()
	fade.add_point(Vector2(0, 0))
	fade.add_point(Vector2(0.3, 1))
	fade.add_point(Vector2(0.7, 1))
	fade.add_point(Vector2(1, 0))
	p.scale_amount_curve = fade
	return p


func _make_leaves() -> CPUParticles3D:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.16, 0.1)
	var p := _particles(50, 6.0, mesh, Color(0.94, 0.58, 0.26), false)
	(mesh.material as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	p.position = Vector3(0, 7, 0)
	p.emission_box_extents = Vector3(12, 1.0, 12)
	p.direction = Vector3(0.3, -1, 0.1)
	p.spread = 30.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.4
	p.angular_velocity_min = -180.0
	p.angular_velocity_max = 180.0
	p.color = Color.WHITE
	var colors := Gradient.new()
	colors.set_color(0, Color(0.95, 0.62, 0.25))
	colors.set_color(1, Color(0.85, 0.35, 0.2))
	p.color_initial_ramp = colors
	return p
