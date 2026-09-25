extends Node3D
## Phase 0 look test. Builds the planet, sky, clouds, player, camera and debug
## HUD in code, then drops the player in the home village.
##
## Run with `-- --tour=<folder>` to save a set of screenshots and quit (see
## tools/screenshot_tour.gd).

const DEFAULT_SEED := 1

## Keyboard bindings, set up in code so the look test has no editor-only setup.
const KEY_BINDINGS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"jump": [KEY_SPACE],
	"camera_left": [KEY_Q],
	"camera_right": [KEY_E],
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


func _ready() -> void:
	_bind_keys()
	planet = Planet.new()
	planet.name = "Planet"
	add_child(planet)
	sky = SkySystem.new()
	sky.name = "Sky"
	add_child(sky)
	clouds = CloudLayer.new()
	clouds.name = "Clouds"
	add_child(clouds)
	player = Player.new()
	player.name = "Player"
	add_child(player)
	camera = PlanetCamera.new()
	camera.name = "Camera"
	add_child(camera)
	camera.make_current()

	hud = DebugHud.new()
	hud.sky = sky
	hud.player = player
	hud.camera = camera
	hud.planet = planet
	add_child(hud)
	hud.regenerate_requested.connect(generate)
	player.camera = camera
	player.joystick = hud.joystick
	camera.target = player
	camera.planet = planet

	generate(DEFAULT_SEED)

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tour="):
			var tour: Node = load("res://tools/screenshot_tour.gd").new()
			tour.set("output_dir", arg.trim_prefix("--tour="))
			add_child(tour)


func generate(world_seed: int) -> void:
	var started := Time.get_ticks_msec()
	planet.generate(world_seed)
	clouds.build(planet, world_seed)
	player.build_visual(planet.surface_material)
	player.spawn(planet, planet.data.home_tile)
	camera.reset_behind()
	sky.setup(planet, player)
	hud.set_seed(world_seed)
	print("Generated planet %d in %d ms (%d tiles)" % [world_seed, Time.get_ticks_msec() - started, planet.data.tile_count()])


func _bind_keys() -> void:
	for action: String in KEY_BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for keycode: Key in KEY_BINDINGS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			InputMap.action_add_event(action, event)
