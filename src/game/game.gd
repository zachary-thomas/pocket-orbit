class_name Game
extends Node
## The running game: owns the GameState, runs player actions through
## Commands, keeps the state's day in step with the sky clock, and saves.
##
## Everything else (HUD, customers, the stall display) reads `state` and
## listens to `state.changed`; nothing but Commands changes it.

signal toast(text: String)

## Autosave this often (seconds) when something changed, plus on quit and
## when the app goes to the background.
const AUTOSAVE_SECONDS := 45.0
## Buildings you can't walk through, so routes go around their tiles.
const BUILDINGS := ["cargo_pod", "cottage"]

var state: GameState
var graph: TileGraph
var planet: Planet
var sky: SkySystem
var player: Player
var saving_enabled := true
var save_path := SaveSystem.PATH

var _dirty := false
var _autosave_timer := 0.0


func start(p_planet: Planet, p_sky: SkySystem, p_player: Player, loaded: GameState) -> void:
	planet = p_planet
	sky = p_sky
	player = p_player
	graph = TileGraph.new(planet.data)
	for prop: Dictionary in planet.data.props:
		if prop["model"] in BUILDINGS:
			graph.block(prop["tile"])
	if loaded and loaded.world_seed == planet.data.world_seed:
		state = loaded
	else:
		state = GameState.new()
		state.world_seed = planet.data.world_seed
		state.day = sky.day_index
	_dirty = false


## Runs a command, shows its message and marks the game for saving.
func run(cmd: Dictionary) -> Dictionary:
	var result := Commands.execute(state, cmd)
	var message: String = result.get("message", "")
	if message != "":
		toast.emit(message)
	if result.get("ok", false):
		_dirty = true
	return result


## Local time at home, in hours.
func home_hours() -> float:
	return sky.home_seconds / 3600.0


func is_night_at_home() -> bool:
	return planet.tile_center(planet.data.home_tile).dot(sky.sun_direction) < 0.0


func hours_at(world_position: Vector3) -> float:
	return sky.local_hours_at(world_position)


func worth_today(item: String) -> int:
	return Economy.value_today(item, state.world_seed, state.day)


## A random number generator for one-off rolls (catches, customers).
func rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.randomize()
	return r


func _process(delta: float) -> void:
	if state == null:
		return
	if sky.day_index != state.day:
		run({"type": "new_day", "day": sky.day_index})
		toast.emit("A new day. Check the demand board at the stall.")
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_SECONDS:
		_autosave_timer = 0.0
		if _dirty:
			save_now()


func save_now() -> void:
	if state == null or not saving_enabled:
		return
	if player and player.planet:
		Commands.execute(state, {"type": "set_player_tile", "tile": player.tile})
	if SaveSystem.save(state, save_path):
		_dirty = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		save_now()
