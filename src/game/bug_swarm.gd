class_name BugSwarm
extends Node3D
## Bugs fluttering around the player. A few are kept alive at a time, spawned
## out of sight on land nearby with a species picked from the biome and local
## time (CatchTables.bug). They drift about, and flee if you run at them:
## walk up slowly and swing the net.

const MAX_BUGS := 5
const SPAWN_MIN := 9.0
const SPAWN_MAX := 22.0
const DESPAWN_DISTANCE := 34.0
## Running closer than this scares a bug off.
const SCARE_DISTANCE := 3.2

var game: Game
var _material: Material
var _rng := RandomNumberGenerator.new()
var _spawn_timer := 0.0


class Bug:
	extends Node3D
	var item := ""
	var home := Vector3.ZERO
	var hover := 1.0
	var phase := 0.0
	var fleeing := 0.0
	var mesh: MeshInstance3D


func setup(p_game: Game, material: Material) -> void:
	game = p_game
	_material = material
	_rng.randomize()
	clear()


func clear() -> void:
	for bug in get_children():
		bug.queue_free()


func bugs() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for bug in get_children():
		if not bug.is_queued_for_deletion():
			result.append(bug)
	return result


## Removes a bug that was caught.
func catch(bug: Node3D) -> String:
	var item: String = bug.item
	bug.queue_free()
	return item


func _process(delta: float) -> void:
	if game == null or game.player == null or game.player.planet == null:
		return
	var planet := game.planet
	var player := game.player
	var running := Input.is_action_pressed("sprint") and player.is_moving()
	for bug: Bug in get_children():
		var to_player := player.global_position - bug.home
		if to_player.length() > DESPAWN_DISTANCE:
			bug.queue_free()
			continue
		bug.phase += delta
		if running and to_player.length() < SCARE_DISTANCE:
			bug.fleeing = 1.5
		var up := planet.up_at(bug.home)
		if bug.fleeing > 0.0:
			bug.fleeing -= delta
			var away := SphereMath.tangent(-to_player, up)
			bug.home = planet.global_position + (bug.home - planet.global_position + away * 6.0 * delta)
			bug.hover += delta * 1.5
			if bug.hover > 5.0:
				bug.queue_free()
				continue
		# Lazy figure-of-eight drift around its home spot.
		var frame := SphereMath.basis_from_up(up)
		var drift := frame.x * sin(bug.phase * 0.9) * 0.8 + frame.z * sin(bug.phase * 1.8) * 0.4
		var bob := sin(bug.phase * 3.1) * 0.15
		bug.global_position = bug.home + up * (bug.hover + bob) + drift
		bug.global_transform.basis = SphereMath.basis_facing(up, frame.x * cos(bug.phase * 0.9) + frame.z * cos(bug.phase * 1.8))
		bug.mesh.scale.x = 1.0 + sin(bug.phase * 30.0) * 0.12
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = 2.0
		if get_child_count() < MAX_BUGS:
			_try_spawn()


func _try_spawn() -> void:
	var planet := game.planet
	var player := game.player
	var up := player.get_up()
	var frame := SphereMath.basis_from_up(up, _rng.randf() * TAU)
	var dist := _rng.randf_range(SPAWN_MIN, SPAWN_MAX)
	var dir := (up * planet.ground_radius(player.tile) + frame.x * dist).normalized()
	var tile := planet.find_tile_dir(dir, player.tile)
	if planet.data.is_water(tile):
		return
	var def := CatchTables.bug(_rng, planet.data.biome[tile], game.hours_at(dir * planet.ground_radius(tile)))
	if def == null:
		return
	var bug := Bug.new()
	bug.item = def.id
	bug.home = planet.global_position + dir * planet.ground_radius(tile)
	bug.hover = _rng.randf_range(0.6, 1.4)
	bug.phase = _rng.randf() * TAU
	bug.mesh = MeshInstance3D.new()
	bug.mesh.mesh = ItemMeshes.mesh(def.id, _material)
	bug.mesh.scale = Vector3.ONE * 1.1
	bug.add_child(bug.mesh)
	add_child(bug)
	bug.global_position = bug.home + planet.up_at(bug.home) * bug.hover
