class_name DebugHud
extends CanvasLayer
## Look-test tools: FPS and triangle count, local time and tile info, a time
## scrubber and clock speeds, orbit view, and regenerating with a new seed.
## Plain Godot controls; the real game UI comes later.

signal regenerate_requested(world_seed: int)

var sky: SkySystem
var player: Player
var camera: PlanetCamera
var planet: Planet
var joystick: TouchStick

var _panel: PanelContainer
var _info: Label
var _time_slider: HSlider
var _seed_box: SpinBox
var _orbit_button: Button


func _ready() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -380.0
	_panel.offset_right = -16.0
	_panel.offset_top = 16.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.add_to_group("ui_blocker")
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)

	_info = Label.new()
	box.add_child(_info)

	_time_slider = HSlider.new()
	_time_slider.min_value = 0.0
	_time_slider.max_value = 24.0
	_time_slider.step = 0.01
	_time_slider.custom_minimum_size.y = 32.0
	_time_slider.value_changed.connect(func(hours: float) -> void: sky.set_home_hours(hours))
	box.add_child(_time_slider)

	var clock_row := HBoxContainer.new()
	box.add_child(clock_row)
	_add_button(clock_row, "Real", func() -> void: sky.use_real_time())
	_add_button(clock_row, "Pause", func() -> void: sky.toggle_pause())
	for speed in [60, 600, 3600]:
		_add_button(clock_row, "x%d" % speed, func() -> void: sky.set_speed(speed))

	var world_row := HBoxContainer.new()
	box.add_child(world_row)
	_orbit_button = _add_button(world_row, "Orbit view", func() -> void: toggle_orbit())
	_seed_box = SpinBox.new()
	_seed_box.min_value = 0
	_seed_box.max_value = 999999
	_seed_box.prefix = "Seed"
	world_row.add_child(_seed_box)
	_add_button(world_row, "Regenerate", func() -> void: regenerate_requested.emit(int(_seed_box.value)))

	var help := Label.new()
	help.text = "WASD / stick: walk   Shift: run   Space: jump\nRight-drag or drag: camera   Wheel: zoom   Q/E: turn\nTab: orbit view   [ ]: -/+ 1 hour   F1: hide panel"
	help.add_theme_font_size_override("font_size", 12)
	help.modulate = Color(1, 1, 1, 0.7)
	box.add_child(help)

	joystick = TouchStick.new()
	joystick.anchor_top = 1.0
	joystick.anchor_bottom = 1.0
	joystick.offset_left = 40.0
	joystick.offset_right = 40.0 + joystick.radius * 2.0
	joystick.offset_top = -40.0 - joystick.radius * 2.0
	joystick.offset_bottom = -40.0
	add_child(joystick)


func set_seed(world_seed: int) -> void:
	_seed_box.set_value_no_signal(world_seed)


func toggle_orbit() -> void:
	camera.set_orbit_mode(not camera.orbit_mode)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_orbit"):
		toggle_orbit()
	elif event.is_action_pressed("toggle_hud"):
		_panel.visible = not _panel.visible
	elif event.is_action_pressed("time_back"):
		sky.set_home_hours(sky.home_seconds / 3600.0 - 1.0)
	elif event.is_action_pressed("time_forward"):
		sky.set_home_hours(sky.home_seconds / 3600.0 + 1.0)


func _process(_delta: float) -> void:
	if planet == null or planet.data == null or player.planet == null:
		return
	_time_slider.set_value_no_signal(sky.home_seconds / 3600.0)
	_orbit_button.text = "Surface view" if camera.orbit_mode else "Orbit view"
	var data := planet.data
	var t := player.tile
	var up := player.get_up()
	var lat := SphereMath.latitude_degrees(up)
	var lon := rad_to_deg(SphereMath.longitude(up))
	var triangles := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var lines := PackedStringArray([
		"%d fps   %s triangles" % [Engine.get_frames_per_second(), _thousands(triangles)],
		"Home %s (%s)   Here %s" % [_clock(sky.home_seconds / 3600.0), sky.clock_label(), _clock(sky.local_hours_at(player.global_position))],
		"Tile %d  %s  level %d%s" % [t, Biome.NAMES[data.biome[t]], data.level[t], "  (shrine)" if data.sphere.is_pentagon(t) else ""],
		"%.1f° %s   %.1f° %s" % [absf(lat), "N" if lat >= 0.0 else "S", absf(lon), "E" if lon >= 0.0 else "W"],
	])
	_info.text = "\n".join(lines)


func _add_button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 36)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)
	return button


static func _clock(hours: float) -> String:
	var minutes := int(fposmod(hours, 24.0) * 60.0)
	return "%02d:%02d" % [minutes / 60, minutes % 60]


static func _thousands(value: int) -> String:
	return "%.1fk" % (value / 1000.0) if value >= 1000 else str(value)
