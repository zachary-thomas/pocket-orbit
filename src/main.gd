extends Node3D
## Builds the game in code: the planet, sky, clouds, player and camera, the
## game state and everything that acts on it (stall, customers, bugs,
## fishing), and the HUD. Loads the saved game if there is one.
##
## Command-line options (after `--`):
##   --tour=<folder>   save a set of screenshots and quit (tools/screenshot_tour.gd)
##   --playtest=<folder>  play through the Phase 1 loop, report and quit (tools/playtest.gd)
##   --new-game        ignore the save and start fresh
##   --no-save         never write the save file

const DEFAULT_SEED := 1

## Keyboard bindings, set up in code so there's no editor-only setup.
const KEY_BINDINGS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"jump": [KEY_SPACE],
	"interact": [KEY_E, KEY_F, KEY_ENTER],
	"bag": [KEY_I, KEY_B],
	"camera_left": [KEY_Z],
	"camera_right": [KEY_C],
	"toggle_orbit": [KEY_TAB],
	"toggle_hud": [KEY_F1],
	"time_back": [KEY_BRACKETLEFT],
	"time_forward": [KEY_BRACKETRIGHT],
}

var planet: Planet
var sky: SkySystem
var clouds: CloudLayer
var player: Player
var camera: PlanetCamera
var hud: DebugHud
var game: Game
var game_hud: GameHud
var interactions: Interactions
var world_items: WorldItems
var customers: Customers
var bugs: BugSwarm
var fishing: Fishing
var vessa: Npc


func _ready() -> void:
	_bind_keys()
	var args := OS.get_cmdline_user_args()
	var touring := false
	for arg in args:
		touring = touring or arg.begins_with("--tour=") or arg.begins_with("--playtest=")
	planet = _add(Planet.new(), "Planet")
	sky = _add(SkySystem.new(), "Sky")
	clouds = _add(CloudLayer.new(), "Clouds")
	player = _add(Player.new(), "Player")
	camera = _add(PlanetCamera.new(), "Camera")
	camera.make_current()
	game = _add(Game.new(), "Game")
	game.saving_enabled = not touring and not "--no-save" in args
	world_items = _add(WorldItems.new(), "WorldItems")
	customers = _add(Customers.new(), "Customers")
	bugs = _add(BugSwarm.new(), "Bugs")
	fishing = _add(Fishing.new(), "Fishing")
	interactions = _add(Interactions.new(), "Interactions")

	hud = DebugHud.new()
	hud.sky = sky
	hud.player = player
	hud.camera = camera
	hud.planet = planet
	add_child(hud)
	hud.regenerate_requested.connect(func(world_seed: int) -> void: start(world_seed, null))
	game_hud = GameHud.new()
	add_child(game_hud)
	game_hud.ui_open_changed.connect(_on_ui_open)
	player.camera = camera
	player.joystick = game_hud.joystick
	camera.target = player
	camera.planet = planet
	get_tree().auto_accept_quit = true

	var saved: GameState = null
	if not touring and not "--new-game" in args:
		saved = SaveSystem.load_state()
	start(saved.world_seed if saved else DEFAULT_SEED, saved)

	for arg in args:
		for tool: String in ["tour", "playtest"]:
			if arg.begins_with("--%s=" % tool):
				var script: Node = load("res://tools/%s.gd" % ("screenshot_tour" if tool == "tour" else tool)).new()
				script.set("output_dir", arg.trim_prefix("--%s=" % tool))
				add_child(script)


## Builds the planet for `world_seed` and starts playing: from `saved` if
## given, otherwise a new game.
func start(world_seed: int, saved: GameState) -> void:
	var started := Time.get_ticks_msec()
	planet.generate(world_seed)
	clouds.build(planet, world_seed)
	player.build_visual(planet.surface_material)
	sky.setup(planet, player)
	game.start(planet, sky, player, saved)
	var material := planet.surface_material
	world_items.setup(game, material)
	customers.setup(game, material)
	bugs.setup(game, material)
	fishing.setup(game, material)
	_spawn_vessa()
	interactions.game = game
	interactions.camera = camera
	interactions.fishing = fishing
	interactions.bugs = bugs
	interactions.world_items = world_items
	interactions.vessa = vessa
	interactions.material = material
	game_hud.setup(game, interactions)

	var village := planet.data.village
	var spawn_tile: int = village["street_tile"]
	if game.state.player_tile >= 0 and game.state.player_tile < planet.data.tile_count() and planet.is_walkable(game.state.player_tile):
		spawn_tile = game.state.player_tile
	player.spawn(planet, spawn_tile)
	player.face(planet.global_position + (village["stall"] as Transform3D).origin)
	camera.reset_behind()
	hud.set_seed(world_seed)
	print("Started planet %d in %d ms (%d tiles)" % [world_seed, Time.get_ticks_msec() - started, planet.data.tile_count()])
	if not game.state.flags.has("met_vessa"):
		game.toast.emit("Vessa's waiting by the stall. Go and say hello.")


func _spawn_vessa() -> void:
	if vessa:
		vessa.queue_free()
	vessa = Npc.new()
	vessa.name = "Vessa"
	add_child(vessa)
	vessa.build(Npc.Look.VESSA, planet.surface_material, RandomNumberGenerator.new())
	var at: Transform3D = planet.data.village["vessa"]
	vessa.spawn(planet, planet.find_tile_dir(at.origin.normalized(), planet.data.home_tile))
	vessa.global_position = planet.global_position + at.origin
	vessa.face(planet.global_position + at * Vector3(0, 0, 3))


func _on_ui_open(open: bool) -> void:
	interactions.ui_open = open
	player.input_enabled = not open
	if open:
		player.set_route(PackedVector3Array())


func _add(node: Node, node_name: String) -> Node:
	node.name = node_name
	add_child(node)
	return node


func _bind_keys() -> void:
	for action: String in KEY_BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for keycode: Key in KEY_BINDINGS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			InputMap.action_add_event(action, event)
